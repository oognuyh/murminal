import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:murminal/data/models/audio_session_state.dart';
import 'package:murminal/data/models/output_change_event.dart';
import 'package:murminal/data/models/tool_definition.dart';
import 'package:murminal/data/models/voice_event.dart';
import 'package:murminal/data/models/voice_supervisor_state.dart';
import 'package:murminal/data/models/error_recovery_event.dart';
import 'package:murminal/data/models/pattern_match_event.dart';
import 'package:murminal/data/services/audio_session_service.dart';
import 'package:murminal/data/services/pcm_player_service.dart';
import 'package:murminal/data/services/error_recovery_service.dart';
import 'package:murminal/data/services/mic_service.dart';
import 'package:murminal/data/services/output_monitor.dart';
import 'package:murminal/data/services/pattern_detector.dart';
import 'package:murminal/data/services/pattern_match_service.dart';
import 'package:murminal/data/services/report_generator.dart';
import 'package:murminal/data/services/session_service.dart';
import 'package:murminal/data/services/ssh_connection_pool.dart';
import 'package:murminal/data/services/ssh_service.dart';
import 'package:murminal/data/services/tool_executor.dart';
import 'package:murminal/data/services/voice/local_voice_service.dart';
import 'package:murminal/data/services/voice/realtime_voice_service.dart';

/// Core voice-to-terminal-to-voice pipeline supervisor.
///
/// Orchestrates the full loop:
///   mic audio -> Realtime WebSocket -> tool calls -> tmux -> audio response
///
/// Responsibilities:
/// - Activates the iOS audio session for background operation.
/// - Connects the microphone and streams PCM to the Realtime API.
/// - Dispatches incoming tool calls to the appropriate [TmuxController]
///   or [SessionService] method.
/// - Monitors tmux output changes and injects proactive TTS reports.
/// - Builds and refreshes the system prompt with current server/session state.
/// - Exposes a [state] stream for UI binding.
class VoiceSupervisor {
  static const _tag = 'VoiceSupervisor';

  final RealtimeVoiceService _voiceService;
  final LocalVoiceService? _localVoiceService;
  final AudioSessionService _audioSession;
  final MicService _mic;
  final SessionService _sessionService;
  final OutputMonitor _outputMonitor;
  final PatternDetector? _patternDetector;
  final ReportGenerator? _reportGenerator;
  final ToolExecutor _toolExecutor;
  final SshConnectionPool? _sshPool;
  final ErrorRecoveryService? _errorRecovery;
  final PatternMatchService? _patternMatchService;
  final PcmPlayerService _pcmPlayer = PcmPlayerService();

  /// Whether this supervisor is using the local STT/TTS pipeline.
  bool _useLocal = false;

  /// The server ID this supervisor is operating against.
  final String serverId;

  final _stateController =
      StreamController<VoiceSupervisorState>.broadcast();

  VoiceSupervisorState _currentState = VoiceSupervisorState.idle;
  StreamSubscription<VoiceEvent>? _voiceEventSub;
  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<OutputChangeEvent>? _outputSub;
  StreamSubscription<AudioSessionState>? _audioStateSub;
  StreamSubscription<SshReconnectionEvent>? _reconnectSub;
  StreamSubscription<ErrorRecoveryEvent>? _errorRecoverySub;
  StreamSubscription<PatternMatchEvent>? _patternMatchSub;

  /// Cached API key for WebSocket reconnection after audio interruption.
  String? _apiKey;

  /// The supervisor state before an interruption, used to restore after resume.
  VoiceSupervisorState? _preInterruptionState;

  /// Tracks whether we already announced connection loss for this cycle.
  bool _announcedConnectionLoss = false;

  VoiceSupervisor({
    required RealtimeVoiceService voiceService,
    required AudioSessionService audioSession,
    required MicService mic,
    required SessionService sessionService,
    required OutputMonitor outputMonitor,
    required ToolExecutor toolExecutor,
    required this.serverId,
    LocalVoiceService? localVoiceService,
    SshConnectionPool? sshPool,
    PatternDetector? patternDetector,
    ReportGenerator? reportGenerator,
    ErrorRecoveryService? errorRecovery,
    PatternMatchService? patternMatchService,
  })  : _voiceService = voiceService,
        _localVoiceService = localVoiceService,
        _audioSession = audioSession,
        _mic = mic,
        _sessionService = sessionService,
        _outputMonitor = outputMonitor,
        _patternDetector = patternDetector,
        _reportGenerator = reportGenerator,
        _toolExecutor = toolExecutor,
        _sshPool = sshPool,
        _errorRecovery = errorRecovery,
        _patternMatchService = patternMatchService;

  /// Stream of supervisor state changes for UI binding.
  Stream<VoiceSupervisorState> get state => _stateController.stream;

  /// Current supervisor state.
  VoiceSupervisorState get currentState => _currentState;

  // ---------------------------------------------------------------------------
  // Tool definitions exposed to the Realtime voice model
  // ---------------------------------------------------------------------------

  /// Tool schemas sent to the Realtime API so the model can invoke them.
  static const List<ToolDefinition> toolDefinitions = [
    ToolDefinition(
      name: 'send_command',
      description:
          'Send a shell command to a tmux session. The command is executed '
          'inside the session and the terminal output is returned.',
      parameters: {
        'type': 'object',
        'properties': {
          'session_name': {
            'type': 'string',
            'description': 'Name of the target tmux session.',
          },
          'command': {
            'type': 'string',
            'description': 'Shell command to execute.',
          },
        },
        'required': ['session_name', 'command'],
      },
    ),
    ToolDefinition(
      name: 'get_session_status',
      description:
          'Capture the current terminal output of a tmux session to see '
          'what is on screen.',
      parameters: {
        'type': 'object',
        'properties': {
          'session_name': {
            'type': 'string',
            'description': 'Name of the target tmux session.',
          },
          'lines': {
            'type': 'integer',
            'description':
                'Number of lines to capture from the bottom of the pane. '
                'Defaults to 50.',
          },
        },
        'required': ['session_name'],
      },
    ),
    ToolDefinition(
      name: 'list_sessions',
      description:
          'List all active Murminal-managed tmux sessions on the current server.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    ToolDefinition(
      name: 'create_session',
      description:
          'Create a new tmux session on the current server and optionally '
          'run a startup command inside it.',
      parameters: {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'Human-readable name for the new session.',
          },
          'command': {
            'type': 'string',
            'description': 'Optional shell command to run after creation.',
          },
        },
        'required': ['name'],
      },
    ),
    ToolDefinition(
      name: 'kill_session',
      description: 'Terminate a tmux session by name.',
      parameters: {
        'type': 'object',
        'properties': {
          'session_name': {
            'type': 'string',
            'description': 'Name of the session to kill.',
          },
        },
        'required': ['session_name'],
      },
    ),
    ToolDefinition(
      name: 'get_all_sessions',
      description:
          'List all sessions across all servers. Use this tool to resolve '
          'ambiguous commands by checking which sessions match a user\'s '
          'reference when multiple candidates exist.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
  ];

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Start the voice supervisor pipeline.
  ///
  /// Activates the audio session, connects the microphone, builds the
  /// system prompt, and establishes the voice connection.
  ///
  /// The [apiKey] is the user's BYOK key for the selected voice provider.
  /// When [useLocal] is true, the local STT/TTS pipeline is used instead
  /// of the Realtime WebSocket API.
  Future<void> start(String apiKey, {bool useLocal = false}) async {
    debugPrint('VoiceSupervisor.start() currentState=$_currentState');
    if (_currentState != VoiceSupervisorState.idle &&
        _currentState != VoiceSupervisorState.error) {
      debugPrint('VoiceSupervisor: already running ($_currentState), resetting to idle');
      // Force reset so user can retry.
      _setState(VoiceSupervisorState.idle);
    }

    _setState(VoiceSupervisorState.connecting);
    _apiKey = apiKey;
    _useLocal = useLocal && _localVoiceService != null;

    try {
      // 1. Activate iOS audio session for background playback/recording.
      debugPrint('Step 1: activating audio session...');
      try {
        await _audioSession.activate();
        debugPrint('Step 1: audio session activated');
      } catch (e) {
        debugPrint('Step 1: audio session failed (non-fatal): $e');
        // Continue without audio session — mic may still work.
      }

      // 1a. Listen for audio session interruptions (phone calls, other apps).
      _audioStateSub?.cancel();
      _audioStateSub = _audioSession.stateStream.listen(
        _handleAudioSessionState,
      );

      // 2. Build initial system prompt with current server/session state.
      debugPrint('Step 2: building system prompt...');
      final prompt = await _buildSystemPrompt();
      debugPrint('Step 2: prompt built (${prompt.length} chars)');

      if (_useLocal) {
        // -- Local pipeline: STT -> LM -> TTS --
        final local = _localVoiceService!; // guaranteed non-null by _useLocal
        await local.connect(apiKey, tools: toolDefinitions);
        await local.updateSystemPrompt(prompt);

        // Subscribe to voice events from the local pipeline.
        _voiceEventSub = local.events.listen(_handleVoiceEvent);

        // Start STT listening (mic is handled by the native STT plugin).
        await local.startListening();
      } else {
        // -- Realtime pipeline: WebSocket audio-in/audio-out --
        // Request mic permission and start recording.
        debugPrint('Step 3: requesting mic permission...');
        final granted = await _mic.requestPermission();
        debugPrint('Step 3: mic permission=$granted');
        if (!granted) {
          throw StateError('Microphone permission denied');
        }
        debugPrint('Step 4: starting mic recording...');
        final micStream = await _mic.startRecording();
        debugPrint('Step 4: mic recording started');

        // Connect to the Realtime WebSocket API with tools.
        debugPrint('Step 5: connecting to ${_voiceService.runtimeType}...');
        await _voiceService.connect(apiKey, tools: toolDefinitions);
        debugPrint('Step 5: connected');
        await _voiceService.updateSystemPrompt(prompt);

        // Subscribe to voice events.
        _voiceEventSub = _voiceService.events.listen(_handleVoiceEvent);

        // Pipe mic audio to the Realtime API.
        _micSub = micStream.listen(_voiceService.sendAudio);
      }

      // 7. Subscribe to output monitor for proactive reporting.
      _outputSub = _outputMonitor.changes.listen(_onOutputChange);

      // 8. Subscribe to SSH reconnection events for voice notifications.
      _reconnectSub?.cancel();
      if (_sshPool != null) {
        _reconnectSub =
            _sshPool.reconnectionEvents.listen(_handleReconnectionEvent);
      }

      // 9. Subscribe to error recovery events for unified voice notifications.
      _errorRecoverySub?.cancel();
      if (_errorRecovery != null) {
        _errorRecovery.startMonitoring();
        _errorRecoverySub =
            _errorRecovery.events.listen(_handleErrorRecoveryEvent);
      }

      // 10. Subscribe to pattern match events for voice announcements.
      _patternMatchSub?.cancel();
      if (_patternMatchService != null) {
        _patternMatchService.start();
        _patternMatchSub =
            _patternMatchService.matches.listen(_handlePatternMatch);
      }

      _setState(VoiceSupervisorState.listening);
      developer.log(
        'Pipeline started (${_useLocal ? "local" : "realtime"})',
        name: _tag,
      );
    } catch (e) {
      developer.log('Failed to start: $e', name: _tag);
      _setState(VoiceSupervisorState.error);
      // Best-effort cleanup on partial start failure.
      await _teardown();
    }
  }

  /// Stop the voice supervisor and release all resources.
  Future<void> stop() async {
    developer.log('Stopping pipeline', name: _tag);
    await _teardown();
    _setState(VoiceSupervisorState.idle);
  }

  /// Dispose the supervisor permanently. Must not be reused after this.
  void dispose() {
    _voiceEventSub?.cancel();
    _micSub?.cancel();
    _outputSub?.cancel();
    _audioStateSub?.cancel();
    _reconnectSub?.cancel();
    _errorRecoverySub?.cancel();
    _patternMatchSub?.cancel();
    _errorRecovery?.dispose();
    _patternMatchService?.stop();
    _localVoiceService?.dispose();
    _stateController.close();
  }

  // ---------------------------------------------------------------------------
  // Voice event handling
  // ---------------------------------------------------------------------------

  /// Routes incoming [VoiceEvent]s to the appropriate handler.
  void _handleVoiceEvent(VoiceEvent event) {
    switch (event) {
      case ToolCallRequest():
        _handleToolCall(event);

      case AudioDelta():
        // Update state to indicate the model is speaking.
        if (_currentState != VoiceSupervisorState.speaking) {
          debugPrint('Voice: model speaking');
          _setState(VoiceSupervisorState.speaking);
          // Pause mic to prevent echo feedback (speaker → mic → interrupt loop).
          _micSub?.pause();
        }
        // Play PCM audio through native AVAudioEngine.
        _pcmPlayer.play(event.audio);

      case AudioDone():
        debugPrint('Voice: model done speaking');
        _setState(VoiceSupervisorState.listening);
        // Resume mic after model finishes speaking.
        _micSub?.resume();

      case VoiceError():
        debugPrint('Voice error: ${event.message}');
        _setState(VoiceSupervisorState.error);

      case SessionCreated():
        debugPrint('Voice: session created: ${event.sessionId}');
        _setState(VoiceSupervisorState.listening);

      case TextDelta():
        debugPrint('Voice text: ${event.text}');
        break;

      case TextDone():
        debugPrint('Voice text done: ${event.text}');
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Tool call dispatch
  // ---------------------------------------------------------------------------

  /// Dispatches a tool call from the voice model to [ToolExecutor].
  ///
  /// After execution, sends the result back to the Realtime API and
  /// refreshes the system prompt so subsequent turns have fresh state.
  /// For session lifecycle tools, also manages output monitoring.
  Future<void> _handleToolCall(ToolCallRequest request) async {
    _setState(VoiceSupervisorState.processing);
    developer.log(
      'Tool call: ${request.name}(${request.arguments})',
      name: _tag,
    );

    final toolResult = await _toolExecutor.execute(request);

    // Manage output monitoring for session lifecycle tools.
    if (toolResult.success) {
      switch (request.name) {
        case 'create_session':
          final decoded = jsonDecode(toolResult.output) as Map<String, dynamic>;
          final sessionId = decoded['session_id'] as String?;
          if (sessionId != null) {
            _outputMonitor.startMonitoring(sessionId);
          }
        case 'kill_session':
          final sessionName = request.arguments['session_name'] as String?;
          if (sessionName != null) {
            _outputMonitor.stopMonitoring(sessionName);
          }
      }
    }

    // Return the tool result to the model.
    if (_useLocal && _localVoiceService != null) {
      await _localVoiceService.sendToolResult(
        request.callId,
        toolResult.output,
      );
    } else {
      _voiceService.sendToolResult(request.callId, toolResult.output);
    }

    // Refresh the system prompt with updated state after the tool execution.
    try {
      final prompt = await _buildSystemPrompt();
      if (_useLocal && _localVoiceService != null) {
        await _localVoiceService.updateSystemPrompt(prompt);
      } else {
        await _voiceService.updateSystemPrompt(prompt);
      }
    } catch (e) {
      developer.log('Failed to refresh system prompt: $e', name: _tag);
    }
  }

  // ---------------------------------------------------------------------------
  // Audio session interruption handling
  // ---------------------------------------------------------------------------

  /// Reacts to [AudioSessionState] changes from the system.
  ///
  /// On interruption (phone call, Siri, another app claiming audio):
  ///   - Pauses the microphone to stop streaming audio.
  ///   - Pauses the output monitor to avoid queueing stale reports.
  ///   - Moves the supervisor to [VoiceSupervisorState.interrupted].
  ///
  /// On resume after interruption:
  ///   - Restarts the microphone and output monitor.
  ///   - Reconnects the WebSocket if the connection was dropped.
  ///   - Sends a "Voice session resumed" notification via the voice model.
  void _handleAudioSessionState(AudioSessionState audioState) {
    switch (audioState) {
      case AudioSessionState.interrupted:
        _onAudioInterrupted();
      case AudioSessionState.resumed:
        _onAudioResumed();
      case AudioSessionState.active:
      case AudioSessionState.deactivated:
        // No action needed; deactivation is handled by stop/teardown.
        break;
    }
  }

  /// Pauses voice pipeline components when the audio session is interrupted.
  Future<void> _onAudioInterrupted() async {
    if (_currentState == VoiceSupervisorState.idle ||
        _currentState == VoiceSupervisorState.error) {
      return;
    }

    _preInterruptionState = _currentState;
    _errorRecovery?.reportAudioInterruption();
    developer.log('Audio interrupted, pausing pipeline', name: _tag);

    if (_useLocal && _localVoiceService != null) {
      // Stop STT listening for local pipeline.
      await _localVoiceService.stopListening();
    } else {
      // Pause the microphone to free the audio route.
      _micSub?.cancel();
      _micSub = null;
      await _mic.stopRecording();
    }

    // Pause output monitor to avoid accumulating stale reports.
    _outputSub?.cancel();
    _outputSub = null;

    _setState(VoiceSupervisorState.interrupted);
  }

  /// Restores the voice pipeline after an audio interruption ends.
  ///
  /// Restarts the microphone, re-subscribes to the output monitor,
  /// and reconnects the WebSocket if the connection was lost during
  /// the interruption. Sends a recovery notification so the user
  /// hears "Voice session resumed" when audio returns.
  Future<void> _onAudioResumed() async {
    if (_currentState != VoiceSupervisorState.interrupted) {
      return;
    }

    developer.log('Audio resumed, restoring pipeline', name: _tag);

    try {
      if (_useLocal && _localVoiceService != null) {
        // 1. Restart STT listening for local pipeline.
        await _localVoiceService.startListening();
      } else {
        // 1. Restart the microphone for realtime pipeline.
        final micStream = await _mic.startRecording();
        _micSub = micStream.listen(_voiceService.sendAudio);
      }

      // 2. Re-subscribe to output monitor.
      _outputSub = _outputMonitor.changes.listen(_onOutputChange);

      // 3. Reconnect WebSocket if it was dropped during interruption.
      if (!_useLocal) {
        await _reconnectWebSocketIfNeeded();
      }

      // 4. Restore the pre-interruption state (default to listening).
      final restoredState =
          _preInterruptionState ?? VoiceSupervisorState.listening;
      _preInterruptionState = null;

      // Only restore to listening or speaking; other states are transient.
      if (restoredState == VoiceSupervisorState.listening ||
          restoredState == VoiceSupervisorState.speaking) {
        _setState(restoredState);
      } else {
        _setState(VoiceSupervisorState.listening);
      }

      // 5. Notify the user that the voice session has recovered.
      _errorRecovery?.reportAudioResumed();
      _sendRecoveryNotification();

      developer.log('Pipeline restored after interruption', name: _tag);
    } catch (e) {
      developer.log('Failed to resume after interruption: $e', name: _tag);
      _setState(VoiceSupervisorState.error);
    }
  }

  /// Checks if the WebSocket connection is still alive and reconnects
  /// if it was dropped during the audio interruption.
  Future<void> _reconnectWebSocketIfNeeded() async {
    try {
      // Attempt to refresh the system prompt as a connectivity check.
      final prompt = await _buildSystemPrompt();
      await _voiceService.updateSystemPrompt(prompt);
    } catch (_) {
      // Connection is dead; perform a full reconnect.
      developer.log('WebSocket lost during interruption, reconnecting',
          name: _tag);
      await _voiceService.disconnect();

      if (_apiKey != null) {
        await _voiceService.connect(_apiKey!, tools: toolDefinitions);
        final prompt = await _buildSystemPrompt();
        await _voiceService.updateSystemPrompt(prompt);

        // Re-subscribe to voice events since disconnect clears the stream.
        _voiceEventSub?.cancel();
        _voiceEventSub = _voiceService.events.listen(_handleVoiceEvent);
      }
    }
  }

  /// Sends a "Voice session resumed" notification through the voice model
  /// so the user hears a spoken confirmation when audio returns.
  void _sendRecoveryNotification() {
    const message = '[REPORT] Voice session resumed after interruption.';
    _injectReport(message);
  }

  // ---------------------------------------------------------------------------
  // SSH reconnection voice notifications
  // ---------------------------------------------------------------------------

  /// Handles SSH reconnection events from the connection pool.
  ///
  /// Sends voice notifications when the connection drops and when it
  /// is restored, so the user is kept informed hands-free.
  void _handleReconnectionEvent(SshReconnectionEvent event) {
    if (_currentState == VoiceSupervisorState.idle ||
        _currentState == VoiceSupervisorState.error) {
      return;
    }

    if (event.succeeded) {
      // Connection restored — announce recovery.
      _announcedConnectionLoss = false;
      const message = '[REPORT] SSH connection restored. '
          'Reattaching to existing sessions.';
      _injectReport(message);
    } else if (!_announcedConnectionLoss) {
      // First failure — announce connection loss and reconnection.
      _announcedConnectionLoss = true;
      final message = '[REPORT] Connection lost, reconnecting. '
          'Attempting up to ${event.maxAttempts} retries.';
      _injectReport(message);
    } else if (!event.succeeded &&
        event.attempt >= event.maxAttempts) {
      // All attempts exhausted — notify user.
      _announcedConnectionLoss = false;
      const message = '[REPORT] All reconnection attempts failed. '
          'Please check your network connection.';
      _injectReport(message);
    }
  }

  // ---------------------------------------------------------------------------
  // Unified error recovery voice notifications
  // ---------------------------------------------------------------------------

  /// Handles error recovery events from [ErrorRecoveryService] and
  /// announces them via voice when appropriate.
  ///
  /// Only announces events in [detected], [recovered], and [failed] phases
  /// to avoid excessive chatter. Skips SSH events since they are already
  /// handled by [_handleReconnectionEvent].
  void _handleErrorRecoveryEvent(ErrorRecoveryEvent event) {
    if (_currentState == VoiceSupervisorState.idle ||
        _currentState == VoiceSupervisorState.error) {
      return;
    }

    // Skip SSH events — already handled by _handleReconnectionEvent.
    if (event.category == ErrorCategory.sshDisconnect) return;

    // Skip audio interruption events — already handled with inline
    // recovery notifications.
    if (event.category == ErrorCategory.audioInterruption) return;

    // Only announce key phases to avoid excessive voice notifications.
    if (event.phase == RecoveryPhase.recovering) return;

    final report = '[REPORT] ${event.message}';
    _injectReport(report);
  }

  // ---------------------------------------------------------------------------
  // Pattern match voice announcements
  // ---------------------------------------------------------------------------

  /// Handles pattern match events from [PatternMatchService].
  ///
  /// Announces reportable pattern matches via voice so the user hears
  /// about errors, completions, and input prompts hands-free.
  void _handlePatternMatch(PatternMatchEvent event) {
    if (_currentState == VoiceSupervisorState.idle ||
        _currentState == VoiceSupervisorState.error) {
      return;
    }

    if (!event.shouldReport) return;

    _injectReport(event.reportText);
    developer.log(
      'Voice announced pattern match: ${event.detectedState.type.name} '
      'for session "${event.sessionName}"',
      name: _tag,
    );
  }

  // ---------------------------------------------------------------------------
  // Proactive output reporting
  // ---------------------------------------------------------------------------

  /// Handles output changes detected by [OutputMonitor].
  ///
  /// Uses [PatternDetector] to classify the output change and
  /// [ReportGenerator] to produce a `[REPORT]`-prefixed message.
  /// The report is injected into the Realtime API input audio buffer
  /// so the voice model can relay it naturally to the user.
  ///
  /// Falls back to a simple diff-based report when no pattern detector
  /// or report generator is configured.
  void _onOutputChange(OutputChangeEvent event) {
    if (_currentState == VoiceSupervisorState.idle ||
        _currentState == VoiceSupervisorState.error) {
      return;
    }

    final report = _buildOutputReport(event);
    if (report == null) return;

    if (_useLocal && _localVoiceService != null) {
      // Local pipeline: inject text report directly to the LM.
      _localVoiceService.injectTextReport(report);
    } else {
      // Realtime pipeline: encode as UTF-8 and inject into audio buffer.
      final reportBytes = Uint8List.fromList(utf8.encode(report));
      _voiceService.injectAudioReport(reportBytes);
    }

    developer.log(
      'Injected output report for session ${event.sessionName}',
      name: _tag,
    );
  }

  /// Builds a human-readable report from an output change event.
  ///
  /// When a [PatternDetector] is available, the output is classified into
  /// a [DetectedState] (complete, error, question, thinking) and the
  /// [ReportGenerator] produces a templated report. If no pattern matches
  /// or no detector is configured, falls back to a raw diff report.
  String? _buildOutputReport(OutputChangeEvent event) {
    if (_patternDetector != null && _reportGenerator != null) {
      final detected = _patternDetector.detect(event.currentOutput);
      if (detected != null) {
        return _reportGenerator.generateReport(detected, event.currentOutput);
      }
      // No pattern matched — output is idle / unchanged semantically.
      // Skip reporting to avoid noise.
      return null;
    }

    // Fallback: simple diff-based report when no profile is configured.
    final buffer = StringBuffer('[REPORT] Session "${event.sessionName}" ');
    buffer.writeln('output changed:');
    buffer.writeln(event.diff);
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // System prompt
  // ---------------------------------------------------------------------------

  /// Builds the system prompt with current server and session state.
  ///
  /// Called before the initial connection and refreshed after each tool
  /// call so the model always has up-to-date context about the
  /// environment it is managing.
  Future<String> _buildSystemPrompt() async {
    final buffer = StringBuffer();

    buffer.writeln('You are Murminal, a voice-controlled terminal supervisor.');
    buffer.writeln(
      'You manage tmux sessions on remote servers via SSH. '
      'Users speak commands and you execute them using the available tools.',
    );
    buffer.writeln();

    // Current server context.
    buffer.writeln('## Current Server');
    buffer.writeln('Server ID: $serverId');
    buffer.writeln();

    // Active sessions.
    buffer.writeln('## Active Sessions');
    try {
      final sessions = await _sessionService.listSessions(serverId: serverId);
      if (sessions.isEmpty) {
        buffer.writeln('No active sessions.');
      } else {
        for (final session in sessions) {
          buffer.writeln(
            '- ${session.name} (id: ${session.id}, engine: ${session.engine}, '
            'status: ${session.status.name})',
          );
        }
      }
    } catch (e) {
      buffer.writeln('Unable to retrieve sessions: $e');
    }
    buffer.writeln();

    // Available tools summary.
    buffer.writeln('## Available Tools');
    for (final tool in toolDefinitions) {
      buffer.writeln('- ${tool.name}: ${tool.description}');
    }
    buffer.writeln();

    // Disambiguation instructions.
    buffer.writeln('## Disambiguation');
    buffer.writeln(
      'When a command is ambiguous (e.g., it matches multiple sessions by '
      'name or keyword), you MUST ask the user a clarifying question before '
      'executing the command. Use the get_all_sessions tool to retrieve the '
      'full session list and identify which sessions match the user\'s '
      'reference.',
    );
    buffer.writeln();
    buffer.writeln(
      'Follow these disambiguation rules:',
    );
    buffer.writeln(
      '1. If a user\'s target matches multiple sessions, ask which specific '
      'session they mean by listing the matching candidates.',
    );
    buffer.writeln(
      '2. If the target cannot be resolved to any session, tell the user no '
      'match was found and ask them to clarify.',
    );
    buffer.writeln(
      '3. After 2 clarification attempts without resolution, fall back to '
      'listing all matching options with their details (name, server, '
      'status) so the user can choose directly.',
    );
    buffer.writeln(
      '4. Never guess or pick a session arbitrarily when multiple '
      'candidates match.',
    );
    buffer.writeln();

    // Proactive reporting instructions.
    buffer.writeln('## Proactive Reporting');
    buffer.writeln(
      'When you receive input prefixed with [REPORT], it is a system '
      'monitor update about terminal output changes. Summarize the change '
      'concisely and speak it to the user as a status update.',
    );
    buffer.writeln();

    // Detailed error reporting instructions.
    buffer.writeln('## Error Reporting');
    buffer.writeln(
      'When reporting errors to the user, follow this protocol:\n'
      '1. State the error briefly (one sentence).\n'
      '2. Ask: "Would you like more details?"\n'
      '3. If the user says yes:\n'
      '   a. Use get_session_status with lines=100 to capture extended context.\n'
      '   b. Provide a structured summary with:\n'
      '      - Full error message\n'
      '      - Likely cause of the error\n'
      '      - Suggested fix or next steps\n'
      '      - Relevant file paths mentioned in the output\n'
      '4. If the user says no, move on to the next task.',
    );

    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Tears down all active connections and subscriptions.
  Future<void> _teardown() async {
    _voiceEventSub?.cancel();
    _voiceEventSub = null;

    _micSub?.cancel();
    _micSub = null;

    _outputSub?.cancel();
    _outputSub = null;

    _audioStateSub?.cancel();
    _audioStateSub = null;

    _reconnectSub?.cancel();
    _reconnectSub = null;

    _errorRecoverySub?.cancel();
    _errorRecoverySub = null;
    _errorRecovery?.stopMonitoring();

    _patternMatchSub?.cancel();
    _patternMatchSub = null;
    _patternMatchService?.stop();

    _apiKey = null;
    _preInterruptionState = null;
    _announcedConnectionLoss = false;

    if (_useLocal && _localVoiceService != null) {
      await _localVoiceService.disconnect();
    } else {
      await _mic.stopRecording();
      await _voiceService.disconnect();
    }
    _useLocal = false;
    await _pcmPlayer.stop();
    await _audioSession.deactivate();
  }

  /// Injects a report message through the active voice pipeline.
  ///
  /// For local mode, sends as text to the LM. For realtime mode,
  /// encodes as UTF-8 and injects into the audio buffer.
  void _injectReport(String message) {
    try {
      if (_useLocal && _localVoiceService != null) {
        _localVoiceService.injectTextReport(message);
      } else {
        final reportBytes = Uint8List.fromList(utf8.encode(message));
        _voiceService.injectAudioReport(reportBytes);
      }
    } catch (e) {
      developer.log('Failed to inject report: $e', name: _tag);
    }
  }

  void _setState(VoiceSupervisorState newState) {
    if (_currentState == newState) return;
    _currentState = newState;
    _stateController.add(newState);
    developer.log('State -> ${newState.name}', name: _tag);
  }
}

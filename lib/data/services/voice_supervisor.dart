import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:murminal/data/models/output_change_event.dart';
import 'package:murminal/data/models/tool_definition.dart';
import 'package:murminal/data/models/voice_event.dart';
import 'package:murminal/data/models/voice_supervisor_state.dart';
import 'package:murminal/data/services/audio_session_service.dart';
import 'package:murminal/data/services/mic_service.dart';
import 'package:murminal/data/services/output_monitor.dart';
import 'package:murminal/data/services/pattern_detector.dart';
import 'package:murminal/data/services/report_generator.dart';
import 'package:murminal/data/services/session_service.dart';
import 'package:murminal/data/services/tool_executor.dart';
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
  final AudioSessionService _audioSession;
  final MicService _mic;
  final SessionService _sessionService;
  final OutputMonitor _outputMonitor;
  final PatternDetector? _patternDetector;
  final ReportGenerator? _reportGenerator;
  final ToolExecutor _toolExecutor;

  /// The server ID this supervisor is operating against.
  final String serverId;

  final _stateController =
      StreamController<VoiceSupervisorState>.broadcast();

  VoiceSupervisorState _currentState = VoiceSupervisorState.idle;
  StreamSubscription<VoiceEvent>? _voiceEventSub;
  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<OutputChangeEvent>? _outputSub;

  VoiceSupervisor({
    required RealtimeVoiceService voiceService,
    required AudioSessionService audioSession,
    required MicService mic,
    required SessionService sessionService,
    required OutputMonitor outputMonitor,
    required ToolExecutor toolExecutor,
    required this.serverId,
    PatternDetector? patternDetector,
    ReportGenerator? reportGenerator,
  })  : _voiceService = voiceService,
        _audioSession = audioSession,
        _mic = mic,
        _sessionService = sessionService,
        _outputMonitor = outputMonitor,
        _patternDetector = patternDetector,
        _reportGenerator = reportGenerator,
        _toolExecutor = toolExecutor;

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
  /// system prompt, and establishes the Realtime WebSocket connection.
  /// The [apiKey] is the user's BYOK key for the selected voice provider.
  Future<void> start(String apiKey) async {
    if (_currentState != VoiceSupervisorState.idle &&
        _currentState != VoiceSupervisorState.error) {
      developer.log('Already running, ignoring start()', name: _tag);
      return;
    }

    _setState(VoiceSupervisorState.connecting);

    try {
      // 1. Activate iOS audio session for background playback/recording.
      await _audioSession.activate();

      // 2. Request mic permission and start recording.
      final granted = await _mic.requestPermission();
      if (!granted) {
        throw StateError('Microphone permission denied');
      }
      final micStream = await _mic.startRecording();

      // 3. Build initial system prompt with current server/session state.
      final prompt = await _buildSystemPrompt();

      // 4. Connect to the Realtime WebSocket API with tools.
      await _voiceService.connect(apiKey, tools: toolDefinitions);
      await _voiceService.updateSystemPrompt(prompt);

      // 5. Subscribe to voice events.
      _voiceEventSub = _voiceService.events.listen(_handleVoiceEvent);

      // 6. Pipe mic audio to the Realtime API.
      _micSub = micStream.listen(_voiceService.sendAudio);

      // 7. Subscribe to output monitor for proactive reporting.
      _outputSub = _outputMonitor.changes.listen(_onOutputChange);

      _setState(VoiceSupervisorState.listening);
      developer.log('Pipeline started', name: _tag);
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
        // Audio playback is handled downstream by the audio player;
        // update state to indicate the model is speaking.
        if (_currentState != VoiceSupervisorState.speaking) {
          _setState(VoiceSupervisorState.speaking);
        }

      case AudioDone():
        // Model finished speaking; return to listening.
        _setState(VoiceSupervisorState.listening);

      case VoiceError():
        developer.log('Voice error: ${event.message}', name: _tag);
        _setState(VoiceSupervisorState.error);

      case SessionCreated():
        developer.log('Session created: ${event.sessionId}', name: _tag);

      case TextDelta():
        // Text deltas are informational; no state change needed.
        break;

      case TextDone():
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
    _voiceService.sendToolResult(request.callId, toolResult.output);

    // Refresh the system prompt with updated state after the tool execution.
    try {
      final prompt = await _buildSystemPrompt();
      await _voiceService.updateSystemPrompt(prompt);
    } catch (e) {
      developer.log('Failed to refresh system prompt: $e', name: _tag);
    }
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

    // Encode the report as UTF-8 text data for the Realtime API.
    // The model's system prompt instructs it to relay [REPORT]-prefixed
    // content as spoken status updates.
    final reportBytes = Uint8List.fromList(utf8.encode(report));
    _voiceService.injectAudioReport(reportBytes);

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

    await _mic.stopRecording();
    await _voiceService.disconnect();
    await _audioSession.deactivate();
  }

  void _setState(VoiceSupervisorState newState) {
    if (_currentState == newState) return;
    _currentState = newState;
    _stateController.add(newState);
    developer.log('State -> ${newState.name}', name: _tag);
  }
}

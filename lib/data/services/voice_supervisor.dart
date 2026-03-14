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
import 'package:murminal/data/services/session_service.dart';
import 'package:murminal/data/services/tmux_controller.dart';
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
  final TmuxController _tmux;
  final SessionService _sessionService;
  final OutputMonitor _outputMonitor;

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
    required TmuxController tmux,
    required SessionService sessionService,
    required OutputMonitor outputMonitor,
    required this.serverId,
  })  : _voiceService = voiceService,
        _audioSession = audioSession,
        _mic = mic,
        _tmux = tmux,
        _sessionService = sessionService,
        _outputMonitor = outputMonitor;

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

  /// Dispatches a tool call from the voice model to the correct service.
  ///
  /// After execution, sends the result back to the Realtime API and
  /// refreshes the system prompt so subsequent turns have fresh state.
  Future<void> _handleToolCall(ToolCallRequest request) async {
    _setState(VoiceSupervisorState.processing);
    developer.log(
      'Tool call: ${request.name}(${request.arguments})',
      name: _tag,
    );

    String result;
    try {
      result = await _dispatchTool(request.name, request.arguments);
    } catch (e) {
      result = jsonEncode({'error': e.toString()});
    }

    // Return the tool result to the model.
    _voiceService.sendToolResult(request.callId, result);

    // Refresh the system prompt with updated state after the tool execution.
    try {
      final prompt = await _buildSystemPrompt();
      await _voiceService.updateSystemPrompt(prompt);
    } catch (e) {
      developer.log('Failed to refresh system prompt: $e', name: _tag);
    }
  }

  /// Routes a tool call by name to the appropriate service method.
  Future<String> _dispatchTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    switch (name) {
      case 'send_command':
        final sessionName = args['session_name'] as String;
        final command = args['command'] as String;
        await _tmux.sendKeys(sessionName, command);
        // Wait briefly for command output to appear, then capture.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final output = await _tmux.capturePane(sessionName);
        return jsonEncode({'output': output});

      case 'get_session_status':
        final sessionName = args['session_name'] as String;
        final lines = args['lines'] as int? ?? 50;
        final output =
            await _tmux.capturePane(sessionName, lines: lines);
        return jsonEncode({'output': output});

      case 'list_sessions':
        final sessions = await _sessionService.listSessions(serverId);
        final sessionList = sessions
            .map((s) => {
                  'id': s.id,
                  'name': s.name,
                  'engine': s.engine,
                  'status': s.status.name,
                })
            .toList();
        return jsonEncode({'sessions': sessionList});

      case 'create_session':
        final name = args['name'] as String;
        final command = args['command'] as String?;
        final session = await _sessionService.createSession(
          serverId: serverId,
          engine: 'shell',
          name: name,
          launchCommand: command,
        );
        // Start monitoring the newly created session for output changes.
        _outputMonitor.startMonitoring(session.id);
        return jsonEncode({
          'session_id': session.id,
          'name': session.name,
          'status': session.status.name,
        });

      case 'kill_session':
        final sessionName = args['session_name'] as String;
        _outputMonitor.stopMonitoring(sessionName);
        await _sessionService.terminateSession(sessionName);
        return jsonEncode({'killed': sessionName});

      default:
        return jsonEncode({'error': 'Unknown tool: $name'});
    }
  }

  // ---------------------------------------------------------------------------
  // Proactive output reporting
  // ---------------------------------------------------------------------------

  /// Handles output changes detected by [OutputMonitor].
  ///
  /// Generates a concise text report of what changed and injects it into
  /// the Realtime API input buffer as a text-based report. The system
  /// prompt instructs the model to relay [REPORT]-prefixed content as
  /// spoken system monitor updates.
  void _onOutputChange(OutputChangeEvent event) {
    if (_currentState == VoiceSupervisorState.idle ||
        _currentState == VoiceSupervisorState.error) {
      return;
    }

    final report = _buildOutputReport(event);
    // Encode the report as UTF-8 PCM-like text data for the model to read.
    // Since we cannot synthesize TTS locally, we send the text report as
    // audio-buffer content that the model's system prompt knows to relay.
    final reportBytes = Uint8List.fromList(utf8.encode(report));
    _voiceService.injectAudioReport(reportBytes);

    developer.log(
      'Injected output report for session ${event.sessionName}',
      name: _tag,
    );
  }

  /// Builds a human-readable report from an output change event.
  String _buildOutputReport(OutputChangeEvent event) {
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
      final sessions = await _sessionService.listSessions(serverId);
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

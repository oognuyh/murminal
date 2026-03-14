import 'dart:developer' as developer;

import 'package:murminal/data/models/tool_result.dart';
import 'package:murminal/data/models/voice_event.dart';
import 'package:murminal/data/services/session_service.dart';
import 'package:murminal/data/services/tmux_controller.dart';

/// Executes tool calls requested by the Realtime voice model.
///
/// Routes each [ToolCallRequest] to the appropriate [TmuxController] or
/// [SessionService] method and returns a [ToolResult] with the outcome.
///
/// Supported tools:
/// - `send_command` - Send a shell command to a tmux session via send-keys.
/// - `get_session_status` - Capture current terminal output of a session.
/// - `list_sessions` - List all active Murminal-managed sessions.
/// - `create_session` - Create a new tmux session with optional startup command.
/// - `kill_session` - Terminate a tmux session by name.
class ToolExecutor {
  static const _tag = 'ToolExecutor';

  final TmuxController _tmux;
  final SessionService _sessionService;
  final String serverId;

  /// Delay after sending keys before capturing output, allowing the command
  /// to produce visible results in the terminal.
  final Duration sendCommandDelay;

  ToolExecutor({
    required TmuxController tmux,
    required SessionService sessionService,
    required this.serverId,
    this.sendCommandDelay = const Duration(milliseconds: 500),
  })  : _tmux = tmux,
        _sessionService = sessionService;

  /// Execute a tool call and return the result string for the Realtime API.
  ///
  /// Parses the [request] and delegates to the matching handler. Returns a
  /// JSON-encoded result string on success, or a JSON error on failure.
  Future<ToolResult> execute(ToolCallRequest request) async {
    developer.log(
      'Executing tool: ${request.name}(${request.arguments})',
      name: _tag,
    );

    try {
      switch (request.name) {
        case 'send_command':
          return await _sendCommand(request.arguments);

        case 'get_session_status':
          return await _getSessionStatus(request.arguments);

        case 'list_sessions':
          return await _listSessions();

        case 'create_session':
          return await _createSession(request.arguments);

        case 'kill_session':
          return await _killSession(request.arguments);

        default:
          return ToolResult.error(request.name, 'Unknown tool: ${request.name}');
      }
    } catch (e) {
      developer.log(
        'Tool execution failed: ${request.name} -> $e',
        name: _tag,
      );
      return ToolResult.error(request.name, e.toString());
    }
  }

  /// Send a shell command to a tmux session and capture the resulting output.
  Future<ToolResult> _sendCommand(Map<String, dynamic> args) async {
    final sessionName = args['session_name'] as String;
    final command = args['command'] as String;

    await _tmux.sendKeys(sessionName, command);
    // Wait briefly for command output to appear, then capture.
    await Future<void>.delayed(sendCommandDelay);
    final output = await _tmux.capturePane(sessionName);

    return ToolResult.ok('send_command', {'output': output});
  }

  /// Capture the current terminal output of a tmux session.
  Future<ToolResult> _getSessionStatus(Map<String, dynamic> args) async {
    final sessionName = args['session_name'] as String;
    final lines = args['lines'] as int? ?? 50;

    final output = await _tmux.capturePane(sessionName, lines: lines);
    return ToolResult.ok('get_session_status', {'output': output});
  }

  /// List all active Murminal-managed tmux sessions.
  Future<ToolResult> _listSessions() async {
    final sessions = await _sessionService.listSessions(serverId);
    final sessionList = sessions
        .map((s) => {
              'id': s.id,
              'name': s.name,
              'engine': s.engine,
              'status': s.status.name,
            })
        .toList();

    return ToolResult.ok('list_sessions', {'sessions': sessionList});
  }

  /// Create a new tmux session on the current server.
  Future<ToolResult> _createSession(Map<String, dynamic> args) async {
    final name = args['name'] as String;
    final command = args['command'] as String?;

    final session = await _sessionService.createSession(
      serverId: serverId,
      engine: 'shell',
      name: name,
      launchCommand: command,
    );

    return ToolResult.ok('create_session', {
      'session_id': session.id,
      'name': session.name,
      'status': session.status.name,
    });
  }

  /// Terminate a tmux session by name.
  Future<ToolResult> _killSession(Map<String, dynamic> args) async {
    final sessionName = args['session_name'] as String;
    await _sessionService.terminateSession(sessionName);

    return ToolResult.ok('kill_session', {'killed': sessionName});
  }
}

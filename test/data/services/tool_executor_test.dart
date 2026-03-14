import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/session.dart';
import 'package:murminal/data/models/tool_result.dart';
import 'package:murminal/data/models/voice_event.dart';
import 'package:murminal/data/repositories/session_repository.dart';
import 'package:murminal/data/services/session_service.dart';
import 'package:murminal/data/services/ssh_service.dart';
import 'package:murminal/data/services/tmux_controller.dart';
import 'package:murminal/data/services/tool_executor.dart';

/// Manual mock for SshService.
class MockSshService extends SshService {
  final List<String> commands = [];
  String Function(String command)? _handler;

  void onExecute(String Function(String command) handler) {
    _handler = handler;
  }

  @override
  Future<String> execute(String command) async {
    commands.add(command);
    if (_handler != null) return _handler!(command);
    return '';
  }

  @override
  bool get isConnected => true;
}

/// In-memory session repository for testing.
class InMemorySessionRepository implements SessionRepository {
  final List<Session> _sessions = [];

  @override
  List<Session> loadAll() => List.unmodifiable(_sessions);

  @override
  List<Session> loadByServer(String serverId) =>
      _sessions.where((s) => s.serverId == serverId).toList();

  @override
  Session? findById(String id) {
    try {
      return _sessions.firstWhere((s) => s.id == id);
    } on StateError {
      return null;
    }
  }

  @override
  Future<void> save(Session session) async {
    final index = _sessions.indexWhere((s) => s.id == session.id);
    if (index >= 0) {
      _sessions[index] = session;
    } else {
      _sessions.add(session);
    }
  }

  @override
  Future<void> delete(String id) async {
    _sessions.removeWhere((s) => s.id == id);
  }
}

void main() {
  late MockSshService mockSsh;
  late TmuxController tmux;
  late InMemorySessionRepository repository;
  late SessionService sessionService;
  late ToolExecutor executor;

  const serverId = 'test-server';

  setUp(() {
    mockSsh = MockSshService();
    tmux = TmuxController(mockSsh);
    repository = InMemorySessionRepository();
    sessionService = SessionService(
      tmuxController: tmux,
      repository: repository,
    );
    executor = ToolExecutor(
      tmux: tmux,
      sessionService: sessionService,
      serverId: serverId,
      sendCommandDelay: Duration.zero,
    );
  });

  ToolCallRequest makeRequest(String name, Map<String, dynamic> args) {
    return ToolCallRequest(callId: 'call-1', name: name, arguments: args);
  }

  group('ToolExecutor', () {
    group('send_command', () {
      test('sends keys and captures output', () async {
        mockSsh.onExecute((cmd) {
          if (cmd.contains('capture-pane')) return 'command output\n';
          return '';
        });

        final result = await executor.execute(
          makeRequest('send_command', {
            'session_name': 'dev',
            'command': 'ls -la',
          }),
        );

        expect(result.success, isTrue);
        expect(result.toolName, 'send_command');

        final data = jsonDecode(result.output) as Map<String, dynamic>;
        expect(data['output'], 'command output\n');

        // Verify send-keys was called before capture-pane.
        expect(mockSsh.commands[0], contains('send-keys'));
        expect(mockSsh.commands[0], contains('ls -la'));
        expect(mockSsh.commands[1], contains('capture-pane'));
      });
    });

    group('get_session_status', () {
      test('captures pane with default lines', () async {
        mockSsh.onExecute((_) => 'screen content\n');

        final result = await executor.execute(
          makeRequest('get_session_status', {'session_name': 'dev'}),
        );

        expect(result.success, isTrue);
        final data = jsonDecode(result.output) as Map<String, dynamic>;
        expect(data['output'], 'screen content\n');
        expect(mockSsh.commands[0], contains('-S -50'));
      });

      test('captures pane with custom line count', () async {
        mockSsh.onExecute((_) => 'output');

        final result = await executor.execute(
          makeRequest('get_session_status', {
            'session_name': 'dev',
            'lines': 100,
          }),
        );

        expect(result.success, isTrue);
        expect(mockSsh.commands[0], contains('-S -100'));
      });
    });

    group('list_sessions', () {
      test('returns empty list when no sessions exist', () async {
        mockSsh.onExecute((_) => '');

        final result = await executor.execute(
          makeRequest('list_sessions', {}),
        );

        expect(result.success, isTrue);
        final data = jsonDecode(result.output) as Map<String, dynamic>;
        final sessions = data['sessions'] as List;
        expect(sessions, isEmpty);
      });

      test('returns sessions for the configured server', () async {
        // Pre-create a session.
        await sessionService.createSession(
          serverId: serverId,
          engine: 'shell',
          name: 'my-session',
        );

        // Mock tmux to report the session as alive.
        final epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        mockSsh.onExecute((cmd) {
          if (cmd.contains('list-sessions')) {
            final sessions = repository.loadByServer(serverId);
            if (sessions.isEmpty) return '';
            return 'murminal-${sessions.first.id}|$epoch|0|$epoch\n';
          }
          return '';
        });

        final result = await executor.execute(
          makeRequest('list_sessions', {}),
        );

        expect(result.success, isTrue);
        final data = jsonDecode(result.output) as Map<String, dynamic>;
        final sessions = data['sessions'] as List;
        expect(sessions, hasLength(1));
        expect(sessions[0]['name'], 'my-session');
        expect(sessions[0]['engine'], 'shell');
        expect(sessions[0]['status'], 'running');
      });
    });

    group('create_session', () {
      test('creates session and returns metadata', () async {
        final result = await executor.execute(
          makeRequest('create_session', {'name': 'new-session'}),
        );

        expect(result.success, isTrue);
        expect(result.toolName, 'create_session');

        final data = jsonDecode(result.output) as Map<String, dynamic>;
        expect(data['name'], 'new-session');
        expect(data['status'], 'running');
        expect(data['session_id'], isNotNull);

        // Verify tmux session was created.
        expect(mockSsh.commands[0], contains('new-session'));
      });

      test('creates session with startup command', () async {
        final result = await executor.execute(
          makeRequest('create_session', {
            'name': 'dev',
            'command': 'htop',
          }),
        );

        expect(result.success, isTrue);
        // Verify both create and send-keys commands.
        expect(mockSsh.commands[0], contains('new-session'));
        expect(mockSsh.commands[1], contains('send-keys'));
        expect(mockSsh.commands[1], contains('htop'));
      });
    });

    group('kill_session', () {
      test('terminates session', () async {
        // First create a session to kill.
        final session = await sessionService.createSession(
          serverId: serverId,
          engine: 'shell',
          name: 'to-kill',
        );

        mockSsh.commands.clear();

        final result = await executor.execute(
          makeRequest('kill_session', {'session_name': session.id}),
        );

        expect(result.success, isTrue);
        final data = jsonDecode(result.output) as Map<String, dynamic>;
        expect(data['killed'], session.id);

        // Verify kill command was sent.
        expect(mockSsh.commands[0], contains('kill-session'));
      });
    });

    group('unknown tool', () {
      test('returns error for unrecognized tool name', () async {
        final result = await executor.execute(
          makeRequest('nonexistent_tool', {}),
        );

        expect(result.success, isFalse);
        final data = jsonDecode(result.output) as Map<String, dynamic>;
        expect(data['error'], contains('Unknown tool'));
      });
    });

    group('error handling', () {
      test('returns error result when tmux command fails', () async {
        mockSsh.onExecute((_) => throw Exception('SSH connection lost'));

        final result = await executor.execute(
          makeRequest('send_command', {
            'session_name': 'dev',
            'command': 'ls',
          }),
        );

        expect(result.success, isFalse);
        final data = jsonDecode(result.output) as Map<String, dynamic>;
        expect(data['error'], isNotEmpty);
      });
    });

    group('ToolResult model', () {
      test('equality works correctly', () {
        final a = ToolResult.ok('test', {'key': 'value'});
        final b = ToolResult.ok('test', {'key': 'value'});
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('toString truncates long output', () {
        final result = ToolResult(
          toolName: 'test',
          success: true,
          output: 'x' * 200,
        );
        expect(result.toString(), contains('...'));
      });

      test('error factory sets success to false', () {
        final result = ToolResult.error('test', 'something went wrong');
        expect(result.success, isFalse);
        expect(result.toolName, 'test');
        final data = jsonDecode(result.output) as Map<String, dynamic>;
        expect(data['error'], 'something went wrong');
      });
    });
  });
}

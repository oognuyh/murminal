import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/session.dart';
import 'package:murminal/data/repositories/session_repository.dart';
import 'package:murminal/data/services/session_service.dart';
import 'package:murminal/data/services/ssh_service.dart';
import 'package:murminal/data/services/tmux_controller.dart';

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

/// A testable SessionRepository backed by in-memory storage.
///
/// Overrides all public methods so the super constructor's
/// SharedPreferences instance is never actually accessed.
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
  late SessionService service;

  setUp(() {
    mockSsh = MockSshService();
    tmux = TmuxController(mockSsh);
    repository = InMemorySessionRepository();
    service = SessionService(tmuxController: tmux, repository: repository);
  });

  group('SessionService', () {
    group('createSession', () {
      test('creates tmux session and persists metadata', () async {
        final session = await service.createSession(
          serverId: 'server-1',
          engine: 'claude',
          name: 'dev',
          launchCommand: 'claude',
        );

        expect(session.serverId, 'server-1');
        expect(session.engine, 'claude');
        expect(session.name, 'dev');
        expect(session.status, SessionStatus.running);

        // Verify tmux session was created.
        expect(mockSsh.commands[0], contains('new-session'));
        // Verify engine command was sent.
        expect(mockSsh.commands[1], contains('send-keys'));
        expect(mockSsh.commands[1], contains('claude'));

        // Verify metadata was persisted.
        final stored = repository.findById(session.id);
        expect(stored, isNotNull);
        expect(stored!.engine, 'claude');
      });

      test('creates session without launch command', () async {
        final session = await service.createSession(
          serverId: 'server-1',
          engine: 'raw',
          name: 'shell',
        );

        expect(session.status, SessionStatus.running);
        // Only the create command, no send-keys.
        expect(mockSsh.commands.length, 1);
        expect(mockSsh.commands[0], contains('new-session'));
      });
    });

    group('terminateSession', () {
      test('kills tmux session and updates status to done', () async {
        final session = await service.createSession(
          serverId: 'server-1',
          engine: 'claude',
          name: 'to-kill',
        );

        mockSsh.commands.clear();
        await service.terminateSession(session.id);

        // Verify kill command was sent.
        expect(mockSsh.commands, isNotEmpty);
        expect(mockSsh.commands[0], contains('kill-session'));

        // Verify status updated locally.
        final stored = repository.findById(session.id);
        expect(stored!.status, SessionStatus.done);
      });
    });

    group('listSessions', () {
      test('reconciles live tmux sessions with local metadata', () async {
        final session = await service.createSession(
          serverId: 'server-1',
          engine: 'claude',
          name: 'active',
        );

        // Mock tmux to report the session as still running.
        final epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        mockSsh.onExecute((_) =>
            'murminal-${session.id}|$epoch|0|$epoch\n');

        final sessions = await service.listSessions('server-1');
        expect(sessions, hasLength(1));
        expect(sessions[0].status, SessionStatus.running);
      });

      test('marks sessions as done when missing from tmux', () async {
        await service.createSession(
          serverId: 'server-1',
          engine: 'claude',
          name: 'gone',
        );

        // Mock tmux to return no sessions.
        mockSsh.onExecute((_) => '');

        final sessions = await service.listSessions('server-1');
        expect(sessions, hasLength(1));
        expect(sessions[0].status, SessionStatus.done);
      });

      test('only returns sessions for the requested server', () async {
        await service.createSession(
          serverId: 'server-1',
          engine: 'claude',
          name: 'one',
        );
        await service.createSession(
          serverId: 'server-2',
          engine: 'raw',
          name: 'two',
        );

        mockSsh.onExecute((_) => '');

        final sessions = await service.listSessions('server-1');
        expect(sessions, hasLength(1));
        expect(sessions[0].name, 'one');
      });
    });

    group('updateStatus', () {
      test('updates status of existing session', () async {
        final session = await service.createSession(
          serverId: 'server-1',
          engine: 'claude',
          name: 'status-test',
        );

        await service.updateStatus(session.id, SessionStatus.error);

        final stored = repository.findById(session.id);
        expect(stored!.status, SessionStatus.error);
      });

      test('does nothing for non-existent session', () async {
        // Should not throw.
        await service.updateStatus('non-existent', SessionStatus.error);
      });
    });
  });
}

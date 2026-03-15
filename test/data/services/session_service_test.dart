import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/session.dart';
import 'package:murminal/data/repositories/session_repository.dart';
import 'package:murminal/data/services/session_service.dart';
import 'package:murminal/data/services/ssh_connection_pool.dart';
import 'package:murminal/data/services/ssh_service.dart';

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

/// A fake SshConnectionPool that always returns the provided MockSshService.
class FakeSshConnectionPool extends SshConnectionPool {
  final MockSshService _mockSsh;

  FakeSshConnectionPool(this._mockSsh) : super(serviceFactory: () => _mockSsh);

  @override
  Future<SshService> getConnection(String serverId) async => _mockSsh;

  @override
  bool isConnected(String serverId) => true;
}

void main() {
  late MockSshService mockSsh;
  late FakeSshConnectionPool pool;
  late InMemorySessionRepository repository;
  late SessionService service;

  setUp(() {
    mockSsh = MockSshService();
    pool = FakeSshConnectionPool(mockSsh);
    repository = InMemorySessionRepository();
    service = SessionService(pool: pool, repository: repository);
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

        final sessions = await service.listSessions(serverId: 'server-1');
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

        final sessions = await service.listSessions(serverId: 'server-1');
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

        final sessions = await service.listSessions(serverId: 'server-1');
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

    group('getSession', () {
      test('returns session when found', () async {
        final session = await service.createSession(
          serverId: 'server-1',
          engine: 'claude',
          name: 'find-me',
        );

        final found = service.getSession(session.id);
        expect(found, isNotNull);
        expect(found!.id, session.id);
        expect(found.engine, 'claude');
      });

      test('returns null for non-existent session', () {
        final found = service.getSession('does-not-exist');
        expect(found, isNull);
      });
    });

    group('deleteSession', () {
      test('removes session from persistence', () async {
        final session = await service.createSession(
          serverId: 'server-1',
          engine: 'claude',
          name: 'to-delete',
        );

        await service.deleteSession(session.id);

        final found = repository.findById(session.id);
        expect(found, isNull);
      });
    });

    group('multi-session management', () {
      test('creates multiple sessions on same server', () async {
        mockSsh.onExecute((_) => '');

        final s1 = await service.createSession(
          serverId: 'server-1',
          engine: 'claude',
          name: 'session-a',
        );
        final s2 = await service.createSession(
          serverId: 'server-1',
          engine: 'raw',
          name: 'session-b',
        );
        final s3 = await service.createSession(
          serverId: 'server-1',
          engine: 'claude',
          name: 'session-c',
        );

        expect(s1.id, isNot(equals(s2.id)));
        expect(s2.id, isNot(equals(s3.id)));
        expect(s1.serverId, 'server-1');
        expect(s2.serverId, 'server-1');
        expect(s3.serverId, 'server-1');

        // All three should be persisted.
        final all = repository.loadAll();
        expect(all, hasLength(3));
      });

      test('creates sessions on different servers', () async {
        mockSsh.onExecute((_) => '');

        final s1 = await service.createSession(
          serverId: 'server-1',
          engine: 'claude',
          name: 'alpha',
        );
        final s2 = await service.createSession(
          serverId: 'server-2',
          engine: 'raw',
          name: 'beta',
        );

        expect(s1.serverId, 'server-1');
        expect(s2.serverId, 'server-2');

        final server1Sessions =
            await service.listSessions(serverId: 'server-1');
        expect(server1Sessions, hasLength(1));
        expect(server1Sessions[0].name, 'alpha');

        final server2Sessions =
            await service.listSessions(serverId: 'server-2');
        expect(server2Sessions, hasLength(1));
        expect(server2Sessions[0].name, 'beta');
      });

      test('tracks session state independently', () async {
        final s1 = await service.createSession(
          serverId: 'server-1',
          engine: 'claude',
          name: 'independent-a',
        );
        final s2 = await service.createSession(
          serverId: 'server-1',
          engine: 'raw',
          name: 'independent-b',
        );

        // Update only s1 to error, leave s2 running.
        await service.updateStatus(s1.id, SessionStatus.error);

        final storedS1 = repository.findById(s1.id);
        final storedS2 = repository.findById(s2.id);
        expect(storedS1!.status, SessionStatus.error);
        expect(storedS2!.status, SessionStatus.running);
      });

      test('listSessions without serverId returns all sessions', () async {
        await service.createSession(
          serverId: 'server-1',
          engine: 'claude',
          name: 'all-a',
        );
        await service.createSession(
          serverId: 'server-2',
          engine: 'raw',
          name: 'all-b',
        );
        await service.createSession(
          serverId: 'server-3',
          engine: 'claude',
          name: 'all-c',
        );

        mockSsh.onExecute((_) => '');

        final all = await service.listSessions();
        expect(all, hasLength(3));

        final serverIds = all.map((s) => s.serverId).toSet();
        expect(serverIds, containsAll(['server-1', 'server-2', 'server-3']));
      });

      test('terminateSession only affects targeted session', () async {
        final s1 = await service.createSession(
          serverId: 'server-1',
          engine: 'claude',
          name: 'keep',
        );
        final s2 = await service.createSession(
          serverId: 'server-1',
          engine: 'raw',
          name: 'kill',
        );

        mockSsh.commands.clear();
        await service.terminateSession(s2.id);

        final storedS1 = repository.findById(s1.id);
        final storedS2 = repository.findById(s2.id);
        expect(storedS1!.status, SessionStatus.running);
        expect(storedS2!.status, SessionStatus.done);
      });

      test('session metadata persists across repository reloads', () async {
        final session = await service.createSession(
          serverId: 'server-1',
          engine: 'claude',
          name: 'persist-test',
        );

        // Simulate reload by reading from repository.
        final reloaded = repository.findById(session.id);
        expect(reloaded, isNotNull);
        expect(reloaded!.serverId, 'server-1');
        expect(reloaded.engine, 'claude');
        expect(reloaded.name, 'persist-test');
        expect(reloaded.status, SessionStatus.running);
        expect(reloaded.createdAt, isNotNull);
      });
    });

    group('pool integration', () {
      test('obtains connection from pool for session creation', () async {
        final session = await service.createSession(
          serverId: 'server-1',
          engine: 'claude',
          name: 'pool-test',
        );

        expect(session.status, SessionStatus.running);
        // Tmux commands were issued through the pooled SSH connection.
        expect(mockSsh.commands, isNotEmpty);
        expect(mockSsh.commands[0], contains('new-session'));
      });

      test('obtains connection from pool for session termination', () async {
        final session = await service.createSession(
          serverId: 'server-1',
          engine: 'claude',
          name: 'pool-terminate',
        );

        mockSsh.commands.clear();
        await service.terminateSession(session.id);

        expect(mockSsh.commands, isNotEmpty);
        expect(mockSsh.commands[0], contains('kill-session'));
      });
    });
  });
}

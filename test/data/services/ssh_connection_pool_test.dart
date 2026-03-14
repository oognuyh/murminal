import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/server_config.dart';
import 'package:murminal/data/services/ssh_connection_pool.dart';
import 'package:murminal/data/services/ssh_service.dart';

/// A fake SshService that simulates connection without real SSH.
class FakeSshService extends SshService {
  bool connectCalled = false;
  bool shouldFailConnect = false;
  bool disconnectCalled = false;

  ConnectionState _fakeState = ConnectionState.disconnected;

  @override
  ConnectionState get currentState => _fakeState;

  @override
  bool get isConnected => _fakeState == ConnectionState.connected;

  @override
  Future<void> connect(ServerConfig config) async {
    connectCalled = true;
    if (shouldFailConnect) {
      _fakeState = ConnectionState.disconnected;
      throw Exception('Connection failed');
    }
    _fakeState = ConnectionState.connected;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalled = true;
    _fakeState = ConnectionState.disconnected;
  }

  @override
  void dispose() {
    _fakeState = ConnectionState.disconnected;
  }
}

ServerConfig _makeConfig(String id) => ServerConfig(
      id: id,
      label: 'Server $id',
      host: '10.0.0.1',
      port: 22,
      username: 'user',
      auth: const PasswordAuth(password: 'pass'),
      createdAt: DateTime(2025, 1, 1),
    );

void main() {
  late List<FakeSshService> createdServices;
  late SshConnectionPool pool;

  setUp(() {
    createdServices = [];
    pool = SshConnectionPool(
      serviceFactory: () {
        final service = FakeSshService();
        createdServices.add(service);
        return service;
      },
    );
  });

  tearDown(() {
    pool.dispose();
  });

  group('SshConnectionPool', () {
    group('initial state', () {
      test('has no connections initially', () {
        expect(pool.currentStates, isEmpty);
      });

      test('isConnected returns false for unknown server', () {
        expect(pool.isConnected('unknown'), false);
      });
    });

    group('getConnection', () {
      test('throws when no config is registered', () {
        expect(
          () => pool.getConnection('unknown'),
          throwsA(isA<StateError>()),
        );
      });

      test('lazily connects on first access', () async {
        final config = _makeConfig('srv-1');
        pool.register(config);

        expect(pool.isConnected('srv-1'), false);

        final service = await pool.getConnection('srv-1');

        expect(service.isConnected, true);
        expect(pool.isConnected('srv-1'), true);
        expect(createdServices.length, 1);
        expect(createdServices.first.connectCalled, true);
      });

      test('returns existing connection on subsequent calls', () async {
        pool.register(_makeConfig('srv-1'));

        final first = await pool.getConnection('srv-1');
        final second = await pool.getConnection('srv-1');

        expect(identical(first, second), true);
        expect(createdServices.length, 1);
      });
    });

    group('connectAll', () {
      test('connects to multiple servers concurrently', () async {
        final configs = [_makeConfig('a'), _makeConfig('b'), _makeConfig('c')];
        await pool.connectAll(configs);

        expect(pool.isConnected('a'), true);
        expect(pool.isConnected('b'), true);
        expect(pool.isConnected('c'), true);
        expect(createdServices.length, 3);
      });

      test('partial failure does not block other connections', () async {
        pool = SshConnectionPool(
          serviceFactory: () {
            final service = FakeSshService();
            // Make every other service fail.
            if (createdServices.length.isOdd) {
              service.shouldFailConnect = true;
            }
            createdServices.add(service);
            return service;
          },
        );

        final configs = [_makeConfig('ok'), _makeConfig('fail')];
        await pool.connectAll(configs);

        expect(pool.isConnected('ok'), true);
        expect(pool.isConnected('fail'), false);
      });
    });

    group('disconnect', () {
      test('disconnects a specific server', () async {
        pool.register(_makeConfig('srv-1'));
        await pool.getConnection('srv-1');

        expect(pool.isConnected('srv-1'), true);

        await pool.disconnect('srv-1');

        expect(pool.isConnected('srv-1'), false);
        expect(createdServices.first.disconnectCalled, true);
      });

      test('is safe to call for non-existent server', () async {
        await pool.disconnect('nonexistent');
        // No exception thrown.
      });
    });

    group('disconnectAll', () {
      test('disconnects all servers', () async {
        await pool.connectAll([_makeConfig('a'), _makeConfig('b')]);

        expect(pool.isConnected('a'), true);
        expect(pool.isConnected('b'), true);

        await pool.disconnectAll();

        expect(pool.isConnected('a'), false);
        expect(pool.isConnected('b'), false);
        for (final s in createdServices) {
          expect(s.disconnectCalled, true);
        }
      });
    });

    group('connectionStates stream', () {
      test('emits state changes when servers connect', () async {
        final states = <Map<String, ConnectionState>>[];
        pool.connectionStates.listen(states.add);

        pool.register(_makeConfig('srv-1'));
        await pool.getConnection('srv-1');

        // Allow stream events to propagate.
        await Future<void>.delayed(Duration.zero);

        expect(states, isNotEmpty);
        expect(states.last['srv-1'], ConnectionState.connected);
      });

      test('emits state changes on disconnect', () async {
        pool.register(_makeConfig('srv-1'));
        await pool.getConnection('srv-1');

        final states = <Map<String, ConnectionState>>[];
        pool.connectionStates.listen(states.add);

        await pool.disconnect('srv-1');

        // After disconnect, the server is removed from the pool.
        await Future<void>.delayed(Duration.zero);
        expect(states, isNotEmpty);
      });
    });

    group('max connections per server', () {
      test('enforces limit of ${SshConnectionPool.maxConnectionsPerServer}',
          () async {
        final config = _makeConfig('srv-1');
        pool.register(config);

        // First connection should succeed.
        await pool.getConnection('srv-1');

        // Simulate reaching the max by manipulating internal state
        // through repeated disconnect/reconnect cycles.
        // The pool tracks cumulative connection count per server.
        for (var i = 1; i < SshConnectionPool.maxConnectionsPerServer; i++) {
          // Disconnect the existing connection to force a new one.
          final service = createdServices.last;
          service._fakeState = ConnectionState.disconnected;
          await pool.getConnection('srv-1');
        }

        // The next attempt should exceed the limit.
        final service = createdServices.last;
        service._fakeState = ConnectionState.disconnected;

        expect(
          () => pool.getConnection('srv-1'),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('dispose', () {
      test('prevents further operations after disposal', () {
        pool.dispose();

        expect(
          () => pool.getConnection('any'),
          throwsA(isA<StateError>()),
        );
      });

      test('is safe to call multiple times', () {
        pool.dispose();
        pool.dispose(); // No exception.
      });

      test('cleans up all connections', () async {
        await pool.connectAll([_makeConfig('a'), _makeConfig('b')]);
        pool.dispose();

        expect(pool.currentStates, isEmpty);
      });
    });

    group('register', () {
      test('stores config for lazy connection', () {
        pool.register(_makeConfig('srv-1'));
        // No connection created yet.
        expect(createdServices, isEmpty);
        expect(pool.isConnected('srv-1'), false);
      });

      test('throws after disposal', () {
        pool.dispose();
        expect(
          () => pool.register(_makeConfig('srv-1')),
          throwsA(isA<StateError>()),
        );
      });
    });
  });
}

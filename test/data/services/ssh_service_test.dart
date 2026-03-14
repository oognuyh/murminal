import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/server_config.dart';
import 'package:murminal/data/services/ssh_service.dart';

void main() {
  late SshService service;

  setUp(() {
    service = SshService();
  });

  tearDown(() {
    service.dispose();
  });

  group('SshService', () {
    group('initial state', () {
      test('starts in disconnected state', () {
        expect(service.currentState, ConnectionState.disconnected);
      });

      test('isConnected returns false initially', () {
        expect(service.isConnected, false);
      });
    });

    group('execute', () {
      test('throws StateError when not connected', () {
        expect(
          () => service.execute('ls'),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('disconnect', () {
      test('remains disconnected after disconnect when not connected', () async {
        await service.disconnect();
        expect(service.currentState, ConnectionState.disconnected);
        expect(service.isConnected, false);
      });
    });

    group('connectionState stream', () {
      test('emits connecting then disconnected on failed connect', () async {
        final states = <ConnectionState>[];
        service.connectionState.listen(states.add);

        final config = ServerConfig(
          id: 'test-id',
          label: 'Test Server',
          host: '127.0.0.1',
          port: 1, // Port 1 should refuse connection quickly
          username: 'testuser',
          auth: const PasswordAuth(password: 'testpass'),
          createdAt: DateTime.now(),
        );

        // Connection to refused port should fail quickly.
        try {
          await service.connect(config);
        } on Exception {
          // Expected to fail.
        }

        // Should have transitioned: connecting -> disconnected
        expect(states, contains(ConnectionState.connecting));
        expect(service.currentState, ConnectionState.disconnected);
      });
    });

    group('ServerConfig model', () {
      test('creates with required fields', () {
        final config = ServerConfig(
          id: 'srv-1',
          label: 'My Server',
          host: 'example.com',
          username: 'user',
          auth: const PasswordAuth(password: 'pass'),
          createdAt: DateTime(2025, 1, 1),
        );

        expect(config.id, 'srv-1');
        expect(config.label, 'My Server');
        expect(config.host, 'example.com');
        expect(config.port, 22); // default
        expect(config.username, 'user');
        expect(config.auth, isA<PasswordAuth>());
        expect(config.jumpHost, isNull);
        expect(config.lastConnectedAt, isNull);
      });

      test('creates with key authentication', () {
        final config = ServerConfig(
          id: 'srv-2',
          label: 'Key Server',
          host: '10.0.0.1',
          port: 2222,
          username: 'admin',
          auth: const KeyAuth(privateKeyPath: '/path/to/key'),
          createdAt: DateTime(2025, 1, 1),
        );

        expect(config.port, 2222);
        expect(config.auth, isA<KeyAuth>());
        final keyAuth = config.auth as KeyAuth;
        expect(keyAuth.privateKeyPath, '/path/to/key');
        expect(keyAuth.passphrase, isNull);
      });

      test('copyWith creates new instance with updated fields', () {
        final original = ServerConfig(
          id: 'srv-1',
          label: 'Original',
          host: 'example.com',
          username: 'user',
          auth: const PasswordAuth(password: 'pass'),
          createdAt: DateTime(2025, 1, 1),
        );

        final updated = original.copyWith(
          label: 'Updated',
          port: 2222,
          lastConnectedAt: DateTime(2025, 6, 1),
        );

        expect(updated.id, original.id);
        expect(updated.label, 'Updated');
        expect(updated.host, original.host);
        expect(updated.port, 2222);
        expect(updated.lastConnectedAt, DateTime(2025, 6, 1));
      });
    });

    group('ConnectionState enum', () {
      test('has all expected values', () {
        expect(ConnectionState.values, containsAll([
          ConnectionState.disconnected,
          ConnectionState.connecting,
          ConnectionState.connected,
          ConnectionState.reconnecting,
        ]));
      });
    });
  });
}

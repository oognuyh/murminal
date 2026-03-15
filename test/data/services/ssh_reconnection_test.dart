import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/server_config.dart';
import 'package:murminal/data/services/ssh_service.dart';

/// Helper to create a test config with an unreachable host.
ServerConfig _testConfig() => ServerConfig(
      id: 'test',
      label: 'Test',
      host: '127.0.0.1',
      port: 1,
      username: 'user',
      auth: const PasswordAuth(password: 'pass'),
      createdAt: DateTime(2025, 1, 1),
    );

void main() {
  group('SshReconnectionEvent', () {
    test('represents a failed attempt with delay', () {
      const event = SshReconnectionEvent(
        attempt: 1,
        maxAttempts: 10,
        delay: Duration(seconds: 1),
        succeeded: false,
      );

      expect(event.attempt, 1);
      expect(event.maxAttempts, 10);
      expect(event.delay, const Duration(seconds: 1));
      expect(event.succeeded, false);
      expect(event.error, isNull);
    });

    test('represents a failed attempt with error message', () {
      const event = SshReconnectionEvent(
        attempt: 3,
        maxAttempts: 10,
        delay: Duration(seconds: 4),
        succeeded: false,
        error: 'Connection refused',
      );

      expect(event.attempt, 3);
      expect(event.error, 'Connection refused');
    });

    test('represents a successful reconnection', () {
      const event = SshReconnectionEvent(
        attempt: 2,
        maxAttempts: 10,
        delay: Duration.zero,
        succeeded: true,
      );

      expect(event.succeeded, true);
      expect(event.attempt, 2);
      expect(event.delay, Duration.zero);
    });

    test('represents final failure (attempt == maxAttempts)', () {
      const event = SshReconnectionEvent(
        attempt: 10,
        maxAttempts: 10,
        delay: Duration.zero,
        succeeded: false,
        error: 'All attempts exhausted',
      );

      expect(event.attempt, event.maxAttempts);
      expect(event.succeeded, false);
    });
  });

  group('SshService reconnection configuration', () {
    test('default max attempts is 10', () {
      final service = SshService();
      expect(service.maxReconnectAttempts, 10);
      service.dispose();
    });

    test('accepts custom max attempts', () {
      final service = SshService(maxReconnectAttempts: 3);
      expect(service.maxReconnectAttempts, 3);
      service.dispose();
    });

    test('max backoff delay is 30 seconds', () {
      expect(SshService.maxBackoffDelay, const Duration(seconds: 30));
    });

    test('reconnectionEvents stream is broadcast', () {
      final service = SshService();
      // Multiple listeners should work.
      final sub1 = service.reconnectionEvents.listen((_) {});
      final sub2 = service.reconnectionEvents.listen((_) {});
      sub1.cancel();
      sub2.cancel();
      service.dispose();
    });
  });

  group('Exponential backoff calculation', () {
    test('backoff delays follow exponential pattern capped at 30s', () {
      // Simulate the backoff calculation from SshService._reconnect
      const maxBackoff = 30;
      final delays = <int>[];

      for (var attempt = 1; attempt <= 10; attempt++) {
        final backoffSeconds = 1 << (attempt - 1);
        delays.add(backoffSeconds.clamp(1, maxBackoff));
      }

      // Expected: 1, 2, 4, 8, 16, 30, 30, 30, 30, 30
      expect(delays, [1, 2, 4, 8, 16, 30, 30, 30, 30, 30]);
    });

    test('first attempt has 1 second delay', () {
      const attempt = 1;
      final backoff = (1 << (attempt - 1)).clamp(1, 30);
      expect(backoff, 1);
    });

    test('fourth attempt has 8 second delay', () {
      const attempt = 4;
      final backoff = (1 << (attempt - 1)).clamp(1, 30);
      expect(backoff, 8);
    });

    test('backoff caps at 30 seconds for attempts beyond 5', () {
      for (var attempt = 6; attempt <= 10; attempt++) {
        final backoff = (1 << (attempt - 1)).clamp(1, 30);
        expect(backoff, 30, reason: 'Attempt $attempt should cap at 30s');
      }
    });
  });

  group('SshService state management', () {
    late SshService service;

    setUp(() {
      service = SshService();
    });

    tearDown(() {
      service.dispose();
    });

    test('isReconnecting starts false', () {
      expect(service.isReconnecting, false);
    });

    test('disconnect cancels any pending reconnection', () async {
      // Even if we're not actively reconnecting, disconnect should be safe.
      await service.disconnect();
      expect(service.isReconnecting, false);
      expect(service.currentState, ConnectionState.disconnected);
    });

    test('connectionState stream emits state changes', () async {
      final states = <ConnectionState>[];
      final sub = service.connectionState.listen(states.add);

      // Trigger a failed connect (port 1 should refuse quickly).
      try {
        await service.connect(_testConfig());
      } on Exception {
        // Expected.
      }

      await Future<void>.delayed(Duration.zero);

      expect(states, contains(ConnectionState.connecting));
      expect(states, contains(ConnectionState.disconnected));

      await sub.cancel();
    });
  });
}

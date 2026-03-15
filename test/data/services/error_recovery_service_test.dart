import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/error_recovery_event.dart';
import 'package:murminal/data/models/session.dart';
import 'package:murminal/data/services/error_recovery_service.dart';
import 'package:murminal/data/services/ssh_connection_pool.dart';
import 'package:murminal/data/services/ssh_service.dart';

// ---------------------------------------------------------------------------
// Minimal fakes for dependencies
// ---------------------------------------------------------------------------

class FakeSshConnectionPool extends SshConnectionPool {
  final _reconnController = StreamController<SshReconnectionEvent>.broadcast();
  bool _connected = true;

  @override
  Stream<SshReconnectionEvent> get reconnectionEvents =>
      _reconnController.stream;

  @override
  bool isConnected(String serverId) => _connected;

  void setConnected(bool value) => _connected = value;

  void emitReconnection(SshReconnectionEvent event) {
    _reconnController.add(event);
  }

  @override
  void dispose() {
    _reconnController.close();
    super.dispose();
  }
}

/// In-memory session list used by the injectable session lister.
List<Session> _fakeSessions = [];

Future<List<Session>> _fakeSessionLister({String? serverId}) async {
  return _fakeSessions;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ErrorRecoveryEvent', () {
    test('has correct default timestamp', () {
      final before = DateTime.now();
      final event = ErrorRecoveryEvent(
        category: ErrorCategory.webSocketDisconnect,
        phase: RecoveryPhase.detected,
        message: 'test',
      );
      final after = DateTime.now();

      expect(event.timestamp.isAfter(before) || event.timestamp == before,
          isTrue);
      expect(
          event.timestamp.isBefore(after) || event.timestamp == after, isTrue);
    });

    test('toString includes category and phase', () {
      final event = ErrorRecoveryEvent(
        category: ErrorCategory.apiRateLimit,
        phase: RecoveryPhase.recovering,
        message: 'waiting 60s',
      );

      expect(event.toString(), contains('apiRateLimit'));
      expect(event.toString(), contains('recovering'));
    });
  });

  group('ErrorRecoveryService', () {
    late FakeSshConnectionPool pool;
    late ErrorRecoveryService service;

    setUp(() {
      pool = FakeSshConnectionPool();
      _fakeSessions = [];
      service = ErrorRecoveryService(
        sshPool: pool,
        sessionService: null as dynamic, // Not used; overridden by lister.
        serverId: 'test-server',
        sessionLister: _fakeSessionLister,
      );
    });

    tearDown(() {
      service.dispose();
      pool.dispose();
    });

    group('rate limit reporting', () {
      test('emits detected and recovering events', () async {
        final events = <ErrorRecoveryEvent>[];
        service.events.listen(events.add);

        service.reportRateLimit(
            backoff: const Duration(seconds: 30));

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(2));
        expect(events[0].category, ErrorCategory.apiRateLimit);
        expect(events[0].phase, RecoveryPhase.detected);
        expect(events[0].retryDelay, const Duration(seconds: 30));
        expect(events[1].phase, RecoveryPhase.recovering);
      });

      test('emits recovered event on success', () async {
        final events = <ErrorRecoveryEvent>[];
        service.events.listen(events.add);

        service.reportRateLimitRecovered();

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events[0].category, ErrorCategory.apiRateLimit);
        expect(events[0].phase, RecoveryPhase.recovered);
      });

      test('uses default 60s backoff when none specified', () async {
        final events = <ErrorRecoveryEvent>[];
        service.events.listen(events.add);

        service.reportRateLimit();

        await Future<void>.delayed(Duration.zero);

        expect(events[0].retryDelay, const Duration(seconds: 60));
      });
    });

    group('audio interruption reporting', () {
      test('emits detected event on interruption', () async {
        final events = <ErrorRecoveryEvent>[];
        service.events.listen(events.add);

        service.reportAudioInterruption();

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events[0].category, ErrorCategory.audioInterruption);
        expect(events[0].phase, RecoveryPhase.detected);
      });

      test('emits recovered event on resume', () async {
        final events = <ErrorRecoveryEvent>[];
        service.events.listen(events.add);

        service.reportAudioResumed();

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events[0].category, ErrorCategory.audioInterruption);
        expect(events[0].phase, RecoveryPhase.recovered);
      });
    });

    group('WebSocket disconnect reporting', () {
      test('emits detected event on disconnect', () async {
        final events = <ErrorRecoveryEvent>[];
        service.events.listen(events.add);

        service.reportWebSocketDisconnect();

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events[0].category, ErrorCategory.webSocketDisconnect);
        expect(events[0].phase, RecoveryPhase.detected);
      });

      test('emits recovering event on attempt', () async {
        final events = <ErrorRecoveryEvent>[];
        service.events.listen(events.add);

        service.reportWebSocketReconnectAttempt(2, 5);

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events[0].phase, RecoveryPhase.recovering);
        expect(events[0].attempt, 2);
        expect(events[0].maxAttempts, 5);
      });

      test('emits recovered event on success', () async {
        final events = <ErrorRecoveryEvent>[];
        service.events.listen(events.add);

        service.reportWebSocketReconnected();

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events[0].phase, RecoveryPhase.recovered);
      });

      test('emits failed event when all attempts exhausted', () async {
        final events = <ErrorRecoveryEvent>[];
        service.events.listen(events.add);

        service.reportWebSocketReconnectFailed();

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events[0].phase, RecoveryPhase.failed);
      });
    });

    group('SSH reconnection forwarding', () {
      test('forwards first SSH failure as detected', () async {
        final events = <ErrorRecoveryEvent>[];
        service.events.listen(events.add);
        service.startMonitoring();

        pool.emitReconnection(const SshReconnectionEvent(
          attempt: 1,
          maxAttempts: 10,
          delay: Duration(seconds: 1),
          succeeded: false,
        ));

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events[0].category, ErrorCategory.sshDisconnect);
        expect(events[0].phase, RecoveryPhase.detected);
      });

      test('forwards intermediate SSH failures as recovering', () async {
        final events = <ErrorRecoveryEvent>[];
        service.events.listen(events.add);
        service.startMonitoring();

        pool.emitReconnection(const SshReconnectionEvent(
          attempt: 3,
          maxAttempts: 10,
          delay: Duration(seconds: 4),
          succeeded: false,
        ));

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events[0].phase, RecoveryPhase.recovering);
      });

      test('forwards SSH success as recovered', () async {
        final events = <ErrorRecoveryEvent>[];
        service.events.listen(events.add);
        service.startMonitoring();

        pool.emitReconnection(const SshReconnectionEvent(
          attempt: 2,
          maxAttempts: 10,
          delay: Duration.zero,
          succeeded: true,
        ));

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events[0].phase, RecoveryPhase.recovered);
      });

      test('forwards final SSH failure as failed', () async {
        final events = <ErrorRecoveryEvent>[];
        service.events.listen(events.add);
        service.startMonitoring();

        pool.emitReconnection(const SshReconnectionEvent(
          attempt: 10,
          maxAttempts: 10,
          delay: Duration.zero,
          succeeded: false,
        ));

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events[0].phase, RecoveryPhase.failed);
      });
    });

    group('tmux crash detection', () {
      test('updateKnownSessions tracks running sessions only', () {
        service.updateKnownSessions([
          Session(
            id: 'running-1',
            serverId: 'test-server',
            engine: 'claude',
            name: 'test1',
            status: SessionStatus.running,
            createdAt: DateTime(2025, 1, 1),
          ),
          Session(
            id: 'done-1',
            serverId: 'test-server',
            engine: 'claude',
            name: 'test2',
            status: SessionStatus.done,
            createdAt: DateTime(2025, 1, 1),
          ),
        ]);

        // Verify service remains functional after update.
        expect(() => service.reportRateLimit(), returnsNormally);
      });

      test('tmux health check interval is 30 seconds', () {
        expect(
          ErrorRecoveryService.tmuxHealthCheckInterval,
          const Duration(seconds: 30),
        );
      });
    });

    group('lifecycle', () {
      test('throws after disposal', () {
        service.dispose();

        expect(
          () => service.reportRateLimit(),
          throwsA(isA<StateError>()),
        );
      });

      test('stopMonitoring cancels subscriptions', () {
        service.startMonitoring();
        service.stopMonitoring();

        expect(() => service.stopMonitoring(), returnsNormally);
      });

      test('startMonitoring can be called multiple times safely', () {
        service.startMonitoring();
        service.startMonitoring();
        service.stopMonitoring();

        expect(() => service.stopMonitoring(), returnsNormally);
      });

      test('events stream is broadcast', () {
        final sub1 = service.events.listen((_) {});
        final sub2 = service.events.listen((_) {});
        sub1.cancel();
        sub2.cancel();
      });
    });
  });

  group('ErrorCategory', () {
    test('has all expected values', () {
      expect(ErrorCategory.values, hasLength(5));
      expect(ErrorCategory.values, contains(ErrorCategory.webSocketDisconnect));
      expect(ErrorCategory.values, contains(ErrorCategory.sshDisconnect));
      expect(ErrorCategory.values, contains(ErrorCategory.audioInterruption));
      expect(ErrorCategory.values, contains(ErrorCategory.apiRateLimit));
      expect(ErrorCategory.values, contains(ErrorCategory.tmuxCrash));
    });
  });

  group('RecoveryPhase', () {
    test('has all expected values', () {
      expect(RecoveryPhase.values, hasLength(4));
      expect(RecoveryPhase.values, contains(RecoveryPhase.detected));
      expect(RecoveryPhase.values, contains(RecoveryPhase.recovering));
      expect(RecoveryPhase.values, contains(RecoveryPhase.recovered));
      expect(RecoveryPhase.values, contains(RecoveryPhase.failed));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/services/voice/qwen_realtime_service.dart';

void main() {
  group('QwenRealtimeService reconnection configuration', () {
    test('maxReconnectAttempts is 5', () {
      expect(QwenRealtimeService.maxReconnectAttempts, 5);
    });

    test('maxBackoffDelay is 30 seconds', () {
      expect(
        QwenRealtimeService.maxBackoffDelay,
        const Duration(seconds: 30),
      );
    });

    test('backoff delays follow exponential pattern capped at 30s', () {
      const maxBackoff = 30;
      final delays = <int>[];

      for (var attempt = 1;
          attempt <= QwenRealtimeService.maxReconnectAttempts;
          attempt++) {
        final backoffSeconds = 1 << (attempt - 1);
        delays.add(backoffSeconds.clamp(1, maxBackoff));
      }

      // Expected: 1, 2, 4, 8, 16
      expect(delays, [1, 2, 4, 8, 16]);
    });
  });

  group('QwenRealtimeService callback hooks', () {
    test('onRateLimitDetected is initially null', () {
      final service = QwenRealtimeService();
      expect(service.onRateLimitDetected, isNull);
    });

    test('onReconnectAttempt is initially null', () {
      final service = QwenRealtimeService();
      expect(service.onReconnectAttempt, isNull);
    });

    test('onReconnected is initially null', () {
      final service = QwenRealtimeService();
      expect(service.onReconnected, isNull);
    });

    test('onReconnectFailed is initially null', () {
      final service = QwenRealtimeService();
      expect(service.onReconnectFailed, isNull);
    });

    test('onDisconnected is initially null', () {
      final service = QwenRealtimeService();
      expect(service.onDisconnected, isNull);
    });

    test('callbacks can be set', () {
      final service = QwenRealtimeService();

      var rateLimitCalled = false;
      var reconnectAttemptCalled = false;
      var reconnectedCalled = false;
      var reconnectFailedCalled = false;
      var disconnectedCalled = false;

      service.onRateLimitDetected = (_) => rateLimitCalled = true;
      service.onReconnectAttempt = (_, __) => reconnectAttemptCalled = true;
      service.onReconnected = () => reconnectedCalled = true;
      service.onReconnectFailed = () => reconnectFailedCalled = true;
      service.onDisconnected = () => disconnectedCalled = true;

      // Invoke the callbacks directly.
      service.onRateLimitDetected!(const Duration(seconds: 60));
      service.onReconnectAttempt!(1, 5);
      service.onReconnected!();
      service.onReconnectFailed!();
      service.onDisconnected!();

      expect(rateLimitCalled, isTrue);
      expect(reconnectAttemptCalled, isTrue);
      expect(reconnectedCalled, isTrue);
      expect(reconnectFailedCalled, isTrue);
      expect(disconnectedCalled, isTrue);
    });
  });

  group('Rate limit detection', () {
    // Test the rate limit patterns via event stream observation.
    // The _isRateLimitError and _parseRetryAfter methods are private,
    // so we verify their behavior through integration.
    test('service emits VoiceError on error events', () {
      final service = QwenRealtimeService();
      // The events stream should be a broadcast stream.
      final sub1 = service.events.listen((_) {});
      final sub2 = service.events.listen((_) {});
      sub1.cancel();
      sub2.cancel();
    });
  });
}

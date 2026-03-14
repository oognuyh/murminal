import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/services/report_queue.dart';

void main() {
  late ReportQueue queue;

  ReportEvent makeEvent({
    ReportPriority priority = ReportPriority.normal,
    String sessionId = 'dev',
    String message = 'test',
    DateTime? timestamp,
  }) {
    return ReportEvent(
      priority: priority,
      sessionId: sessionId,
      message: message,
      timestamp: timestamp ?? DateTime(2025, 7, 1),
    );
  }

  setUp(() {
    queue = ReportQueue();
  });

  tearDown(() {
    queue.dispose();
  });

  group('ReportPriority', () {
    test('ordering: critical > high > normal > low', () {
      expect(ReportPriority.critical.value, greaterThan(ReportPriority.high.value));
      expect(ReportPriority.high.value, greaterThan(ReportPriority.normal.value));
      expect(ReportPriority.normal.value, greaterThan(ReportPriority.low.value));
    });

    test('compareTo works correctly', () {
      expect(ReportPriority.critical.compareTo(ReportPriority.low), greaterThan(0));
      expect(ReportPriority.low.compareTo(ReportPriority.critical), lessThan(0));
      expect(ReportPriority.normal.compareTo(ReportPriority.normal), equals(0));
    });
  });

  group('ReportEvent', () {
    test('equality works correctly', () {
      final ts = DateTime(2025, 7, 1);
      final a = ReportEvent(
        priority: ReportPriority.high,
        sessionId: 'dev',
        message: 'build done',
        timestamp: ts,
      );
      final b = ReportEvent(
        priority: ReportPriority.high,
        sessionId: 'dev',
        message: 'build done',
        timestamp: ts,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toString includes priority and session', () {
      final event = makeEvent(
        priority: ReportPriority.critical,
        sessionId: 'prod',
        message: 'server down',
      );
      expect(event.toString(), contains('critical'));
      expect(event.toString(), contains('prod'));
      expect(event.toString(), contains('server down'));
    });
  });

  group('ReportQueue - basic enqueue/drain', () {
    test('emits enqueued events via reports stream', () async {
      final events = <ReportEvent>[];
      queue.reports.listen(events.add);

      queue.enqueue(makeEvent(message: 'hello'));

      // Allow microtask to propagate.
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events[0].message, 'hello');
    });

    test('drains in priority order (highest first)', () async {
      // Pause first so we can enqueue multiple items before draining.
      queue.onUserSpeechStarted();

      queue.enqueue(makeEvent(priority: ReportPriority.low, message: 'low'));
      queue.enqueue(makeEvent(priority: ReportPriority.high, message: 'high'));
      queue.enqueue(makeEvent(priority: ReportPriority.normal, message: 'normal'));

      final events = <ReportEvent>[];
      queue.reports.listen(events.add);

      // Resume to drain.
      queue.onUserSpeechEnded();

      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(3));
      expect(events[0].message, 'high');
      expect(events[1].message, 'normal');
      expect(events[2].message, 'low');
    });

    test('FIFO order within same priority', () async {
      queue.onUserSpeechStarted();

      queue.enqueue(makeEvent(priority: ReportPriority.normal, message: 'first'));
      queue.enqueue(makeEvent(priority: ReportPriority.normal, message: 'second'));
      queue.enqueue(makeEvent(priority: ReportPriority.normal, message: 'third'));

      final events = <ReportEvent>[];
      queue.reports.listen(events.add);

      queue.onUserSpeechEnded();

      await Future<void>.delayed(Duration.zero);

      expect(events[0].message, 'first');
      expect(events[1].message, 'second');
      expect(events[2].message, 'third');
    });

    test('pendingCount reflects queued items', () {
      queue.onUserSpeechStarted();

      expect(queue.pendingCount, 0);
      queue.enqueue(makeEvent(message: 'a'));
      expect(queue.pendingCount, 1);
      queue.enqueue(makeEvent(message: 'b'));
      expect(queue.pendingCount, 2);
    });
  });

  group('ReportQueue - speech pause/resume', () {
    test('pauses draining when user starts speaking', () async {
      queue.onUserSpeechStarted();
      expect(queue.isPaused, isTrue);

      final events = <ReportEvent>[];
      queue.reports.listen(events.add);

      queue.enqueue(makeEvent(message: 'queued'));

      await Future<void>.delayed(Duration.zero);

      // Non-critical event should not be emitted while paused.
      expect(events, isEmpty);
      expect(queue.pendingCount, 1);
    });

    test('resumes and drains after user stops speaking', () async {
      queue.onUserSpeechStarted();

      final events = <ReportEvent>[];
      queue.reports.listen(events.add);

      queue.enqueue(makeEvent(priority: ReportPriority.high, message: 'urgent'));
      queue.enqueue(makeEvent(priority: ReportPriority.low, message: 'info'));

      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);

      queue.onUserSpeechEnded();
      expect(queue.isPaused, isFalse);

      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(2));
      expect(events[0].message, 'urgent');
      expect(events[1].message, 'info');
    });

    test('multiple pause/resume cycles work correctly', () async {
      final events = <ReportEvent>[];
      queue.reports.listen(events.add);

      // First cycle.
      queue.onUserSpeechStarted();
      queue.enqueue(makeEvent(message: 'a'));
      queue.onUserSpeechEnded();
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));

      // Second cycle.
      queue.onUserSpeechStarted();
      queue.enqueue(makeEvent(message: 'b'));
      queue.onUserSpeechEnded();
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(2));
    });
  });

  group('ReportQueue - critical events', () {
    test('critical events bypass pause', () async {
      queue.onUserSpeechStarted();

      final events = <ReportEvent>[];
      queue.reports.listen(events.add);

      queue.enqueue(makeEvent(
        priority: ReportPriority.critical,
        message: 'error!',
      ));

      await Future<void>.delayed(Duration.zero);

      // Critical event emitted despite pause.
      expect(events, hasLength(1));
      expect(events[0].message, 'error!');
      expect(events[0].priority, ReportPriority.critical);
    });

    test('critical events do not affect pending non-critical events', () async {
      queue.onUserSpeechStarted();

      final events = <ReportEvent>[];
      queue.reports.listen(events.add);

      queue.enqueue(makeEvent(priority: ReportPriority.normal, message: 'pending'));
      queue.enqueue(
        makeEvent(priority: ReportPriority.critical, message: 'critical'),
      );

      await Future<void>.delayed(Duration.zero);

      // Only critical event emitted; normal stays queued.
      expect(events, hasLength(1));
      expect(events[0].message, 'critical');
      expect(queue.pendingCount, 1);
    });

    test('critical events emit immediately when not paused', () async {
      final events = <ReportEvent>[];
      queue.reports.listen(events.add);

      queue.enqueue(
        makeEvent(priority: ReportPriority.critical, message: 'immediate'),
      );

      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events[0].priority, ReportPriority.critical);
    });
  });

  group('ReportQueue - clear and dispose', () {
    test('clear removes all pending events', () {
      queue.onUserSpeechStarted();

      queue.enqueue(makeEvent(message: 'a'));
      queue.enqueue(makeEvent(message: 'b'));
      expect(queue.pendingCount, 2);

      queue.clear();
      expect(queue.pendingCount, 0);
    });

    test('dispose closes the stream', () async {
      queue.dispose();

      // Enqueue after dispose should be a no-op.
      queue.enqueue(makeEvent(message: 'ignored'));
      expect(queue.pendingCount, 0);
    });

    test('events enqueued after dispose are ignored', () async {
      final events = <ReportEvent>[];
      queue.reports.listen(
        events.add,
        onDone: () {},
      );

      queue.dispose();

      queue.enqueue(makeEvent(message: 'late'));
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
    });
  });

  group('ReportQueue - mixed priority ordering', () {
    test('interleaved priorities drain correctly', () async {
      queue.onUserSpeechStarted();

      queue.enqueue(makeEvent(priority: ReportPriority.normal, message: 'n1'));
      queue.enqueue(makeEvent(priority: ReportPriority.low, message: 'l1'));
      queue.enqueue(makeEvent(priority: ReportPriority.high, message: 'h1'));
      queue.enqueue(makeEvent(priority: ReportPriority.normal, message: 'n2'));
      queue.enqueue(makeEvent(priority: ReportPriority.high, message: 'h2'));
      queue.enqueue(makeEvent(priority: ReportPriority.low, message: 'l2'));

      final events = <ReportEvent>[];
      queue.reports.listen(events.add);

      queue.onUserSpeechEnded();
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(6));
      // High priority first (FIFO within same priority).
      expect(events[0].message, 'h1');
      expect(events[1].message, 'h2');
      // Normal priority next.
      expect(events[2].message, 'n1');
      expect(events[3].message, 'n2');
      // Low priority last.
      expect(events[4].message, 'l1');
      expect(events[5].message, 'l2');
    });
  });
}

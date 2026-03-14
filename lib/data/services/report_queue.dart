import 'dart:async';
import 'dart:developer' as developer;

/// Priority levels for report events, ordered from lowest to highest.
///
/// Higher-priority events are drained before lower-priority ones.
/// [critical] events can interrupt current TTS playback and bypass
/// the speech pause.
enum ReportPriority implements Comparable<ReportPriority> {
  low(0),
  normal(1),
  high(2),
  critical(3);

  const ReportPriority(this.value);

  /// Numeric weight used for ordering. Higher means more urgent.
  final int value;

  @override
  int compareTo(ReportPriority other) => value.compareTo(other.value);
}

/// A queued report event destined for TTS delivery.
class ReportEvent {
  final ReportPriority priority;
  final String sessionId;
  final String message;
  final DateTime timestamp;

  const ReportEvent({
    required this.priority,
    required this.sessionId,
    required this.message,
    required this.timestamp,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportEvent &&
          runtimeType == other.runtimeType &&
          priority == other.priority &&
          sessionId == other.sessionId &&
          message == other.message &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(priority, sessionId, message, timestamp);

  @override
  String toString() =>
      'ReportEvent(priority: ${priority.name}, session: $sessionId, '
      'message: "$message")';
}

/// Priority-based event queue for TTS report delivery.
///
/// Events are enqueued with a [ReportPriority] and drained sequentially
/// in priority order (highest first, then by insertion time). The queue
/// pauses during user speech (VAD detection) and resumes draining when
/// the user stops speaking.
///
/// Critical events bypass the pause and are emitted immediately.
class ReportQueue {
  static const _tag = 'ReportQueue';

  final _controller = StreamController<ReportEvent>.broadcast();
  final List<ReportEvent> _queue = [];

  bool _paused = false;
  bool _draining = false;
  bool _disposed = false;

  /// Whether the queue is currently paused due to user speech.
  bool get isPaused => _paused;

  /// Number of events waiting in the queue.
  int get pendingCount => _queue.length;

  /// Stream of report events delivered sequentially in priority order.
  ///
  /// Consumers (typically the TTS audio buffer injector) listen to this
  /// stream and process events one at a time.
  Stream<ReportEvent> get reports => _controller.stream;

  /// Add a report event to the queue.
  ///
  /// If the event is [ReportPriority.critical], it bypasses any pause
  /// and is emitted immediately. Otherwise, the event is inserted into
  /// the priority-sorted queue and draining begins if the queue is not
  /// paused.
  void enqueue(ReportEvent event) {
    if (_disposed) return;

    developer.log(
      'Enqueue: ${event.priority.name} — ${event.message}',
      name: _tag,
    );

    if (event.priority == ReportPriority.critical) {
      // Critical events bypass the pause and are emitted immediately.
      _controller.add(event);
      developer.log('Critical event emitted immediately', name: _tag);
      return;
    }

    _insertSorted(event);

    if (!_paused) {
      _drain();
    }
  }

  /// Signal that the user has started speaking (VAD detected).
  ///
  /// Pauses queue draining so reports do not compete with user speech.
  /// Critical events enqueued during a pause still emit immediately.
  void onUserSpeechStarted() {
    if (_disposed) return;
    _paused = true;
    developer.log('Queue paused (user speaking)', name: _tag);
  }

  /// Signal that the user has stopped speaking.
  ///
  /// Resumes queue draining, delivering all pending events in priority
  /// order.
  void onUserSpeechEnded() {
    if (_disposed) return;
    _paused = false;
    developer.log('Queue resumed (user stopped speaking)', name: _tag);
    _drain();
  }

  /// Remove all pending events from the queue without emitting them.
  void clear() {
    _queue.clear();
  }

  /// Dispose the queue and close the stream.
  void dispose() {
    _disposed = true;
    _queue.clear();
    _controller.close();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Insert [event] into [_queue] maintaining descending priority order.
  ///
  /// Events with equal priority are ordered by insertion time (FIFO) —
  /// new events are placed after existing events of the same priority.
  void _insertSorted(ReportEvent event) {
    var index = _queue.length;
    for (var i = 0; i < _queue.length; i++) {
      if (event.priority.value > _queue[i].priority.value) {
        index = i;
        break;
      }
    }
    _queue.insert(index, event);
  }

  /// Drain the queue by emitting events in priority order.
  ///
  /// Runs synchronously since each event emission is non-blocking.
  /// Stops when the queue is empty or the queue becomes paused.
  void _drain() {
    if (_draining || _disposed) return;
    _draining = true;

    while (_queue.isNotEmpty && !_paused && !_disposed) {
      final event = _queue.removeAt(0);
      _controller.add(event);
      developer.log(
        'Drained: ${event.priority.name} — ${event.message}',
        name: _tag,
      );
    }

    _draining = false;
  }
}

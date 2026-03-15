import 'package:murminal/data/models/detected_state.dart';

/// Priority level for a pattern match notification.
enum NotificationPriority {
  /// Informational, no immediate action needed.
  low,

  /// Standard notification for completed tasks.
  normal,

  /// Requires user attention (errors, input prompts).
  high,
}

/// Event emitted when a terminal output pattern matches an engine profile rule.
///
/// Carries the detected state, the session context, and the notification
/// priority derived from the engine profile's state configuration.
class PatternMatchEvent {
  /// The session that produced the matching output.
  final String sessionName;

  /// The detected state from pattern matching.
  final DetectedState detectedState;

  /// Notification priority from the engine profile's state config.
  final NotificationPriority priority;

  /// Whether this state is configured to be reported (notification-worthy).
  final bool shouldReport;

  /// Human-readable report text for voice/notification display.
  final String reportText;

  /// When the match was detected.
  final DateTime timestamp;

  const PatternMatchEvent({
    required this.sessionName,
    required this.detectedState,
    required this.priority,
    required this.shouldReport,
    required this.reportText,
    required this.timestamp,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PatternMatchEvent &&
          runtimeType == other.runtimeType &&
          sessionName == other.sessionName &&
          detectedState == other.detectedState &&
          priority == other.priority &&
          shouldReport == other.shouldReport &&
          reportText == other.reportText &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(
        sessionName,
        detectedState,
        priority,
        shouldReport,
        reportText,
        timestamp,
      );

  @override
  String toString() =>
      'PatternMatchEvent(session: $sessionName, type: ${detectedState.type.name}, '
      'priority: ${priority.name}, report: $shouldReport)';
}

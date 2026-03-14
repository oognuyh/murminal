/// Represents a detected change in tmux pane output.
///
/// Emitted by [OutputMonitor] whenever a polling cycle detects that the
/// captured pane content differs from the previous capture.
class OutputChangeEvent {
  /// The session name (without the "murminal-" prefix).
  final String sessionName;

  /// The pane content from the previous capture, or empty string on first capture.
  final String previousOutput;

  /// The pane content from the current capture.
  final String currentOutput;

  /// A simple line-level diff showing only the lines that changed.
  ///
  /// Lines prefixed with `+` are new, lines prefixed with `-` were removed.
  final String diff;

  /// When the change was detected.
  final DateTime timestamp;

  const OutputChangeEvent({
    required this.sessionName,
    required this.previousOutput,
    required this.currentOutput,
    required this.diff,
    required this.timestamp,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OutputChangeEvent &&
          runtimeType == other.runtimeType &&
          sessionName == other.sessionName &&
          previousOutput == other.previousOutput &&
          currentOutput == other.currentOutput &&
          diff == other.diff &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      Object.hash(sessionName, previousOutput, currentOutput, diff, timestamp);

  @override
  String toString() =>
      'OutputChangeEvent(session: $sessionName, timestamp: $timestamp, '
      'diffLines: ${diff.split('\n').length})';
}

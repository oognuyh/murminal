/// Represents a state detected by pattern matching against terminal output.
///
/// The [PatternDetector] produces instances of this class when a known
/// pattern from an [EngineProfile] matches the current tmux pane content.
class DetectedState {
  /// The state category that was detected.
  final DetectedStateType type;

  /// The raw text that triggered the pattern match.
  final String matchedText;

  /// An optional summary extracted from the matched context.
  ///
  /// For error states this might be the error message; for question states
  /// it could be the prompt text.
  final String? summary;

  const DetectedState({
    required this.type,
    required this.matchedText,
    this.summary,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DetectedState &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          matchedText == other.matchedText &&
          summary == other.summary;

  @override
  int get hashCode => Object.hash(type, matchedText, summary);

  @override
  String toString() =>
      'DetectedState(type: ${type.name}, matchedText: "$matchedText"'
      '${summary != null ? ', summary: "$summary"' : ''})';
}

/// The categories of terminal states that can be detected.
enum DetectedStateType {
  /// The engine has finished a task successfully.
  complete,

  /// The engine encountered an error.
  error,

  /// The engine is asking the user a question or waiting for input.
  question,

  /// The engine is actively working (e.g. spinner visible).
  thinking,

  /// No recognizable pattern matched; the output is stable.
  idle,
}

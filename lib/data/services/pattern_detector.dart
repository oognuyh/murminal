import 'package:murminal/data/models/detected_state.dart';
import 'package:murminal/data/models/engine_profile.dart';

/// Detects the current engine state by matching terminal output against
/// regex patterns defined in an [EngineProfile].
///
/// Each profile provides a map of pattern names (e.g. "complete", "error")
/// to regex strings. The detector compiles these once and tests them
/// against incoming output, returning the first matching [DetectedState]
/// or `null` when no pattern matches (idle).
class PatternDetector {
  final EngineProfile _profile;

  /// Compiled patterns keyed by [DetectedStateType].
  ///
  /// Built lazily on first [detect] call and cached for the lifetime of
  /// this detector instance.
  late final Map<DetectedStateType, RegExp> _compiledPatterns =
      _buildPatterns();

  PatternDetector(this._profile);

  /// The engine profile this detector is configured with.
  EngineProfile get profile => _profile;

  /// Detect the current state from the given terminal [output].
  ///
  /// Returns a [DetectedState] if a known pattern matches, or `null` if
  /// the output does not match any configured pattern (indicating idle).
  ///
  /// Patterns are tested in priority order:
  /// error → question → complete → thinking.
  /// This ensures that errors and questions (which require attention) are
  /// detected before less urgent states.
  DetectedState? detect(String output) {
    if (output.isEmpty) return null;

    // Test in priority order: error > question > complete > thinking.
    const priorityOrder = [
      DetectedStateType.error,
      DetectedStateType.question,
      DetectedStateType.complete,
      DetectedStateType.thinking,
    ];

    for (final type in priorityOrder) {
      final pattern = _compiledPatterns[type];
      if (pattern == null) continue;

      final match = pattern.firstMatch(output);
      if (match != null) {
        return DetectedState(
          type: type,
          matchedText: match.group(0) ?? '',
          summary: _extractSummary(type, output, match),
        );
      }
    }

    return null;
  }

  /// Build the compiled regex map from the engine profile's patterns.
  Map<DetectedStateType, RegExp> _buildPatterns() {
    final result = <DetectedStateType, RegExp>{};

    for (final entry in _profile.patterns.entries) {
      final type = _parseStateType(entry.key);
      final patternStr = entry.value;
      if (type == null || patternStr == null) continue;

      try {
        result[type] = RegExp(patternStr, multiLine: true);
      } on FormatException {
        // Skip invalid patterns rather than crashing the detector.
        continue;
      }
    }

    return result;
  }

  /// Map a pattern key string from the profile to a [DetectedStateType].
  static DetectedStateType? _parseStateType(String key) {
    return switch (key) {
      'complete' => DetectedStateType.complete,
      'error' => DetectedStateType.error,
      'question' => DetectedStateType.question,
      'thinking' => DetectedStateType.thinking,
      _ => null,
    };
  }

  /// Extract a contextual summary from the matched output.
  ///
  /// For errors, captures the line containing the error.
  /// For questions, captures the question text.
  /// For other states, returns `null` (the report template is sufficient).
  String? _extractSummary(
    DetectedStateType type,
    String output,
    RegExpMatch match,
  ) {
    switch (type) {
      case DetectedStateType.error:
      case DetectedStateType.question:
        // Return the line containing the match for context.
        final lineStart = output.lastIndexOf('\n', match.start);
        final lineEnd = output.indexOf('\n', match.end);
        return output.substring(
          lineStart == -1 ? 0 : lineStart + 1,
          lineEnd == -1 ? output.length : lineEnd,
        ).trim();
      case DetectedStateType.complete:
      case DetectedStateType.thinking:
      case DetectedStateType.idle:
        return null;
    }
  }
}

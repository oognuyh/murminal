import 'package:murminal/data/models/session.dart';

/// Classification of why a user command is ambiguous.
enum AmbiguityType {
  /// Multiple sessions match the user's target reference.
  ///
  /// Example: "check claude" when two sessions are named "claude-dev" and
  /// "claude-review".
  multipleSessionMatch,

  /// The target entity (session, server, etc.) cannot be resolved.
  ///
  /// Example: "check postgres" when no session name contains "postgres".
  unknownTarget,

  /// The user's intent is unclear even though the target may be identifiable.
  ///
  /// Example: "do the thing with the build" — ambiguous action.
  unclearIntent,
}

/// Context gathered when a user command cannot be unambiguously routed.
///
/// Tracks the original query, matching candidates, and the number of
/// clarification attempts so far. The voice supervisor uses this to decide
/// whether to ask a follow-up question or fall back to listing options.
class DisambiguationContext {
  /// The kind of ambiguity detected.
  final AmbiguityType type;

  /// Sessions that partially match the user's intent.
  ///
  /// Empty when [type] is [AmbiguityType.unclearIntent] since the issue is
  /// not about session resolution.
  final List<Session> matchingSessions;

  /// The raw user query that triggered disambiguation.
  final String originalQuery;

  /// Number of clarification rounds already attempted for this query.
  ///
  /// After [maxAttempts] the supervisor should fall back to listing all
  /// matching options explicitly.
  final int attempts;

  /// Maximum clarification attempts before the fallback behavior activates.
  static const int maxAttempts = 2;

  const DisambiguationContext({
    required this.type,
    required this.matchingSessions,
    required this.originalQuery,
    this.attempts = 0,
  });

  /// Whether the maximum number of clarification attempts has been reached.
  bool get shouldFallback => attempts >= maxAttempts;

  /// Create a copy with an incremented attempt counter.
  DisambiguationContext withNextAttempt() {
    return DisambiguationContext(
      type: type,
      matchingSessions: matchingSessions,
      originalQuery: originalQuery,
      attempts: attempts + 1,
    );
  }

  /// Create a copy with updated fields.
  DisambiguationContext copyWith({
    AmbiguityType? type,
    List<Session>? matchingSessions,
    String? originalQuery,
    int? attempts,
  }) {
    return DisambiguationContext(
      type: type ?? this.type,
      matchingSessions: matchingSessions ?? this.matchingSessions,
      originalQuery: originalQuery ?? this.originalQuery,
      attempts: attempts ?? this.attempts,
    );
  }

  @override
  String toString() =>
      'DisambiguationContext(type: ${type.name}, '
      'matchingSessions: ${matchingSessions.length}, '
      'originalQuery: $originalQuery, '
      'attempts: $attempts)';
}

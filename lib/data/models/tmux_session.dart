/// Represents a tmux session managed by Murminal.
class TmuxSession {
  /// Session name without the "murminal-" prefix.
  final String name;

  /// When the session was created.
  final DateTime created;

  /// Whether a client is currently attached to the session.
  final bool attached;

  /// Last activity timestamp for the session.
  final DateTime activity;

  const TmuxSession({
    required this.name,
    required this.created,
    required this.attached,
    required this.activity,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TmuxSession &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          created == other.created &&
          attached == other.attached &&
          activity == other.activity;

  @override
  int get hashCode => Object.hash(name, created, attached, activity);

  @override
  String toString() =>
      'TmuxSession(name: $name, created: $created, attached: $attached, activity: $activity)';
}

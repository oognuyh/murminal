import 'dart:convert';

/// Lifecycle status of a Murminal session.
enum SessionStatus {
  running,
  done,
  idle,
  error;

  /// Parse a status string into a [SessionStatus].
  static SessionStatus fromString(String value) {
    return SessionStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => SessionStatus.idle,
    );
  }
}

/// A Murminal session representing a tmux session bound to a server and engine.
class Session {
  final String id;
  final String serverId;
  final String engine;
  final String name;
  final SessionStatus status;
  final DateTime createdAt;

  /// Optional working directory path for worktree-based engines.
  final String? worktreePath;

  /// Branch name associated with the worktree, if any.
  final String? worktreeBranch;

  const Session({
    required this.id,
    required this.serverId,
    required this.engine,
    required this.name,
    required this.status,
    required this.createdAt,
    this.worktreePath,
    this.worktreeBranch,
  });

  /// Create a [Session] from a JSON map.
  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as String,
      serverId: json['server_id'] as String,
      engine: json['engine'] as String,
      name: json['name'] as String,
      status: SessionStatus.fromString(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      worktreePath: json['worktree_path'] as String?,
      worktreeBranch: json['worktree_branch'] as String?,
    );
  }

  /// Serialize this session to a JSON map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'server_id': serverId,
        'engine': engine,
        'name': name,
        'status': status.name,
        'created_at': createdAt.toIso8601String(),
        if (worktreePath != null) 'worktree_path': worktreePath,
        if (worktreeBranch != null) 'worktree_branch': worktreeBranch,
      };

  /// Parse a JSON string into a [Session].
  static Session parse(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return Session.fromJson(json);
  }

  /// Create a copy with updated fields.
  Session copyWith({
    String? id,
    String? serverId,
    String? engine,
    String? name,
    SessionStatus? status,
    DateTime? createdAt,
    String? worktreePath,
    String? worktreeBranch,
  }) {
    return Session(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      engine: engine ?? this.engine,
      name: name ?? this.name,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      worktreePath: worktreePath ?? this.worktreePath,
      worktreeBranch: worktreeBranch ?? this.worktreeBranch,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Session &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          serverId == other.serverId &&
          engine == other.engine &&
          name == other.name &&
          status == other.status &&
          createdAt == other.createdAt &&
          worktreePath == other.worktreePath &&
          worktreeBranch == other.worktreeBranch;

  @override
  int get hashCode => Object.hash(
        id,
        serverId,
        engine,
        name,
        status,
        createdAt,
        worktreePath,
        worktreeBranch,
      );

  @override
  String toString() =>
      'Session(id: $id, serverId: $serverId, engine: $engine, '
      'name: $name, status: ${status.name}, createdAt: $createdAt)';
}

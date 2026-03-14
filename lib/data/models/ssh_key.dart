/// Supported SSH key types.
enum SshKeyType {
  ed25519,
}

/// Represents a stored SSH key pair.
class SshKey {
  final String id;
  final String name;
  final String publicKey;
  final SshKeyType type;
  final DateTime createdAt;

  const SshKey({
    required this.id,
    required this.name,
    required this.publicKey,
    required this.type,
    required this.createdAt,
  });

  /// Serialize to a JSON-compatible map for metadata storage.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'publicKey': publicKey,
      'type': type.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Deserialize from a JSON-compatible map.
  factory SshKey.fromJson(Map<String, dynamic> json) {
    return SshKey(
      id: json['id'] as String,
      name: json['name'] as String,
      publicKey: json['publicKey'] as String,
      type: SshKeyType.values.byName(json['type'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  SshKey copyWith({
    String? id,
    String? name,
    String? publicKey,
    SshKeyType? type,
    DateTime? createdAt,
  }) {
    return SshKey(
      id: id ?? this.id,
      name: name ?? this.name,
      publicKey: publicKey ?? this.publicKey,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SshKey && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SshKey(id: $id, name: $name, type: ${type.name})';
}

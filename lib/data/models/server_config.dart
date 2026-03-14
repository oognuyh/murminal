/// Authentication method for SSH connections.
sealed class AuthMethod {
  const AuthMethod();
}

/// Key-based authentication with a private key file path.
class KeyAuth extends AuthMethod {
  final String privateKeyPath;
  final String? passphrase;

  const KeyAuth({required this.privateKeyPath, this.passphrase});
}

/// Password-based authentication.
class PasswordAuth extends AuthMethod {
  final String password;

  const PasswordAuth({required this.password});
}

/// Configuration for an SSH server connection.
class ServerConfig {
  final String id;
  final String label;
  final String host;
  final int port;
  final String username;
  final AuthMethod auth;
  final String? jumpHost;
  final DateTime createdAt;
  final DateTime? lastConnectedAt;

  const ServerConfig({
    required this.id,
    required this.label,
    required this.host,
    this.port = 22,
    required this.username,
    required this.auth,
    this.jumpHost,
    required this.createdAt,
    this.lastConnectedAt,
  });

  ServerConfig copyWith({
    String? id,
    String? label,
    String? host,
    int? port,
    String? username,
    AuthMethod? auth,
    String? jumpHost,
    DateTime? createdAt,
    DateTime? lastConnectedAt,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      label: label ?? this.label,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      auth: auth ?? this.auth,
      jumpHost: jumpHost ?? this.jumpHost,
      createdAt: createdAt ?? this.createdAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }
}

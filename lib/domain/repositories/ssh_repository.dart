import 'package:murminal/data/models/server_config.dart';
import 'package:murminal/data/services/ssh_service.dart';

/// Abstract interface for SSH connection management.
///
/// Provides a clean boundary between the domain and data layers
/// for SSH operations.
abstract class SshRepository {
  /// Connect to a server with the given configuration.
  Future<void> connect(ServerConfig config);

  /// Disconnect from the current server.
  Future<void> disconnect();

  /// Execute a command on the connected server.
  Future<String> execute(String command);

  /// Whether the client is currently connected.
  bool get isConnected;

  /// Stream of connection state changes.
  Stream<ConnectionState> get connectionState;
}

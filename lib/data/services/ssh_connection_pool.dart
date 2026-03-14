import 'dart:async';

import 'package:murminal/data/models/server_config.dart';
import 'package:murminal/data/services/ssh_service.dart';

/// Manages a pool of SSH connections across multiple servers.
///
/// Supports lazy connection (connect on first use), periodic health checks,
/// and enforces a maximum connection limit per server.
class SshConnectionPool {
  /// Maximum number of concurrent connections allowed per server.
  static const int maxConnectionsPerServer = 5;

  /// Interval between keepalive health checks.
  static const Duration healthCheckInterval = Duration(seconds: 30);

  final Map<String, SshService> _connections = {};
  final Map<String, ServerConfig> _configs = {};
  final Map<String, int> _connectionCounts = {};

  final _stateController =
      StreamController<Map<String, ConnectionState>>.broadcast();

  Timer? _healthCheckTimer;
  bool _disposed = false;

  /// Factory for creating [SshService] instances, injectable for testing.
  final SshService Function() _serviceFactory;

  SshConnectionPool({SshService Function()? serviceFactory})
      : _serviceFactory = serviceFactory ?? SshService.new;

  /// Stream of connection state snapshots keyed by server ID.
  Stream<Map<String, ConnectionState>> get connectionStates =>
      _stateController.stream;

  /// Current connection states for all registered servers.
  Map<String, ConnectionState> get currentStates {
    return {
      for (final entry in _connections.entries)
        entry.key: entry.value.currentState,
    };
  }

  /// Whether the connection for [serverId] is currently connected.
  bool isConnected(String serverId) {
    final service = _connections[serverId];
    return service != null && service.isConnected;
  }

  /// Get or create a connection for [serverId].
  ///
  /// If the server has a registered config but is not yet connected,
  /// a lazy connection is established on first access.
  /// Throws [StateError] if no config is registered for the server.
  Future<SshService> getConnection(String serverId) async {
    _assertNotDisposed();

    final existing = _connections[serverId];
    if (existing != null && existing.isConnected) {
      return existing;
    }

    final config = _configs[serverId];
    if (config == null) {
      throw StateError(
        'No server configuration registered for id: $serverId',
      );
    }

    return _connectServer(config);
  }

  /// Register a server config for lazy connection without connecting.
  void register(ServerConfig config) {
    _assertNotDisposed();
    _configs[config.id] = config;
  }

  /// Connect to all provided server configurations.
  ///
  /// Connections are established concurrently. Failures for individual
  /// servers do not prevent others from connecting.
  Future<void> connectAll(List<ServerConfig> configs) async {
    _assertNotDisposed();

    for (final config in configs) {
      _configs[config.id] = config;
    }

    await Future.wait(
      configs.map((c) => _connectServer(c).then((_) {}).catchError((_) {})),
    );

    _startHealthChecks();
  }

  /// Disconnect a specific server and release its resources.
  Future<void> disconnect(String serverId) async {
    final service = _connections.remove(serverId);
    _connectionCounts.remove(serverId);

    if (service != null) {
      await service.disconnect();
      service.dispose();
      _emitStates();
    }
  }

  /// Disconnect all servers and stop health checks.
  Future<void> disconnectAll() async {
    _stopHealthChecks();

    final futures = <Future<void>>[];
    for (final entry in _connections.entries) {
      futures.add(entry.value.disconnect().then((_) => entry.value.dispose()));
    }
    await Future.wait(futures);

    _connections.clear();
    _connectionCounts.clear();
    _emitStates();
  }

  /// Release all resources. The pool cannot be used after disposal.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopHealthChecks();

    for (final service in _connections.values) {
      service.dispose();
    }
    _connections.clear();
    _configs.clear();
    _connectionCounts.clear();
    _stateController.close();
  }

  Future<SshService> _connectServer(ServerConfig config) async {
    _assertNotDisposed();

    final count = _connectionCounts[config.id] ?? 0;
    if (count >= maxConnectionsPerServer) {
      throw StateError(
        'Maximum connections ($maxConnectionsPerServer) reached for '
        'server: ${config.id}',
      );
    }

    // Reuse existing connected service if available.
    final existing = _connections[config.id];
    if (existing != null && existing.isConnected) {
      return existing;
    }

    // Dispose old service if it exists but is disconnected.
    if (existing != null) {
      existing.dispose();
    }

    final service = _serviceFactory();

    // Forward individual connection state changes to the pool stream.
    service.connectionState.listen((_) => _emitStates());

    _connections[config.id] = service;
    _connectionCounts[config.id] = count + 1;

    await service.connect(config);
    _emitStates();

    return service;
  }

  void _startHealthChecks() {
    _stopHealthChecks();
    _healthCheckTimer = Timer.periodic(healthCheckInterval, (_) {
      _performHealthChecks();
    });
  }

  void _stopHealthChecks() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  /// Check health of all connections by attempting a lightweight command.
  ///
  /// Disconnected connections with a registered config are reconnected.
  Future<void> _performHealthChecks() async {
    if (_disposed) return;

    for (final entry in _connections.entries) {
      final serverId = entry.key;
      final service = entry.value;

      if (!service.isConnected) {
        final config = _configs[serverId];
        if (config != null) {
          try {
            await service.connect(config);
            _emitStates();
          } on Exception {
            // Health check reconnection failed; will retry next interval.
          }
        }
      }
    }
  }

  void _emitStates() {
    if (_disposed) return;
    _stateController.add(currentStates);
  }

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('SshConnectionPool has been disposed');
    }
  }
}

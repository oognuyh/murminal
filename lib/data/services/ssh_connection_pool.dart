import 'dart:async';
import 'dart:developer' as developer;

import 'package:murminal/data/models/server_config.dart';
import 'package:murminal/data/services/ssh_service.dart';
import 'package:murminal/data/services/tmux_install_service.dart';

/// Manages a pool of SSH connections across multiple servers.
///
/// Supports lazy connection (connect on first use), periodic health checks,
/// automatic reconnection with exponential backoff, and enforces a maximum
/// connection limit per server.
/// Tracks tmux availability per server to avoid redundant checks.
class SshConnectionPool {
  static const _tag = 'SshConnectionPool';

  /// Maximum number of concurrent connections allowed per server.
  static const int maxConnectionsPerServer = 5;

  /// Interval between keepalive health checks.
  static const Duration healthCheckInterval = Duration(seconds: 30);

  final Map<String, SshService> _connections = {};
  final Map<String, ServerConfig> _configs = {};
  final Map<String, int> _connectionCounts = {};

  /// Cached tmux check results per server ID.
  ///
  /// Populated on first connection and reused to avoid re-checking.
  final Map<String, TmuxCheckResult> _tmuxStatus = {};

  final _stateController =
      StreamController<Map<String, ConnectionState>>.broadcast();

  final _reconnectionController =
      StreamController<SshReconnectionEvent>.broadcast();

  /// Subscriptions to individual service reconnection events.
  final Map<String, StreamSubscription<SshReconnectionEvent>> _reconnectSubs =
      {};

  Timer? _healthCheckTimer;
  bool _disposed = false;

  /// Factory for creating [SshService] instances, injectable for testing.
  final SshService Function() _serviceFactory;

  SshConnectionPool({SshService Function()? serviceFactory})
      : _serviceFactory = serviceFactory ?? SshService.new;

  /// Stream of connection state snapshots keyed by server ID.
  Stream<Map<String, ConnectionState>> get connectionStates =>
      _stateController.stream;

  /// Stream of reconnection events from all pooled connections.
  ///
  /// The UI and voice layers subscribe to this to show reconnection
  /// banners and speak "Connection lost, reconnecting..." notifications.
  Stream<SshReconnectionEvent> get reconnectionEvents =>
      _reconnectionController.stream;

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

  /// Whether the connection for [serverId] is currently reconnecting.
  bool isReconnecting(String serverId) {
    final service = _connections[serverId];
    return service != null && service.isReconnecting;
  }

  /// Get the cached tmux check result for [serverId].
  ///
  /// Returns null if tmux has not been checked yet for this server.
  TmuxCheckResult? getTmuxStatus(String serverId) => _tmuxStatus[serverId];

  /// Store the tmux check result for [serverId].
  void setTmuxStatus(String serverId, TmuxCheckResult result) {
    _tmuxStatus[serverId] = result;
  }

  /// Clear the cached tmux status for [serverId].
  ///
  /// Use after a successful tmux installation to force re-checking.
  void clearTmuxStatus(String serverId) {
    _tmuxStatus.remove(serverId);
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
    _reconnectSubs[serverId]?.cancel();
    _reconnectSubs.remove(serverId);
    _tmuxStatus.remove(serverId);

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

    for (final sub in _reconnectSubs.values) {
      sub.cancel();
    }
    _reconnectSubs.clear();
    _connections.clear();
    _connectionCounts.clear();
    _emitStates();
  }

  /// Release all resources. The pool cannot be used after disposal.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopHealthChecks();

    for (final sub in _reconnectSubs.values) {
      sub.cancel();
    }
    _reconnectSubs.clear();

    for (final service in _connections.values) {
      service.dispose();
    }
    _connections.clear();
    _configs.clear();
    _connectionCounts.clear();
    _tmuxStatus.clear();
    _stateController.close();
    _reconnectionController.close();
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
      _reconnectSubs[config.id]?.cancel();
      _reconnectSubs.remove(config.id);
      existing.dispose();
    }

    final service = _serviceFactory();

    // Forward individual connection state changes to the pool stream.
    service.connectionState.listen((_) => _emitStates());

    // Forward reconnection events to the pool-level stream.
    _reconnectSubs[config.id] = service.reconnectionEvents.listen((event) {
      developer.log(
        'Reconnection event for ${config.id}: '
        'attempt ${event.attempt}/${event.maxAttempts}, '
        'succeeded: ${event.succeeded}',
        name: _tag,
      );
      if (!_disposed) {
        _reconnectionController.add(event);
      }
    });

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
  /// Connections that are already reconnecting are skipped.
  Future<void> _performHealthChecks() async {
    if (_disposed) return;

    for (final entry in _connections.entries) {
      final serverId = entry.key;
      final service = entry.value;

      if (!service.isConnected && !service.isReconnecting) {
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

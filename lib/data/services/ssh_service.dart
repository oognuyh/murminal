import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import 'package:murminal/data/models/server_config.dart';

/// Connection state for SSH client lifecycle.
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// SSH client service wrapping dartssh2.
///
/// Manages a single SSH connection with automatic reconnection support
/// and connection state monitoring.
class SshService {
  SSHClient? _client;
  ServerConfig? _config;

  final _stateController = StreamController<ConnectionState>.broadcast();
  ConnectionState _state = ConnectionState.disconnected;

  static const _maxReconnectAttempts = 3;

  /// Stream of connection state changes.
  Stream<ConnectionState> get connectionState => _stateController.stream;

  /// Current connection state.
  ConnectionState get currentState => _state;

  /// Whether the client is currently connected.
  bool get isConnected => _state == ConnectionState.connected;

  /// Connect to an SSH server using the given configuration.
  Future<void> connect(ServerConfig config) async {
    if (_state == ConnectionState.connected ||
        _state == ConnectionState.connecting) {
      return;
    }

    _config = config;
    _setState(ConnectionState.connecting);

    try {
      _client = await _createClient(config);
      _setState(ConnectionState.connected);
      _monitorConnection();
    } on Exception {
      _setState(ConnectionState.disconnected);
      rethrow;
    }
  }

  /// Disconnect from the SSH server gracefully.
  Future<void> disconnect() async {
    _config = null;
    _client?.close();
    _client = null;
    _setState(ConnectionState.disconnected);
  }

  /// Execute a remote command and return its stdout output.
  Future<String> execute(String command) async {
    final client = _client;
    if (client == null || !isConnected) {
      throw StateError('SSH client is not connected');
    }

    final session = await client.execute(command);
    final stdout = await utf8.decodeStream(session.stdout);
    // Consume stderr to avoid blocking.
    await utf8.decodeStream(session.stderr);
    session.close();
    return stdout;
  }

  /// Attempt reconnection with exponential backoff.
  Future<void> _reconnect() async {
    final config = _config;
    if (config == null) return;

    _setState(ConnectionState.reconnecting);

    for (var attempt = 0; attempt < _maxReconnectAttempts; attempt++) {
      final delay = Duration(seconds: 1 << attempt); // 1s, 2s, 4s
      await Future<void>.delayed(delay);

      try {
        _client = await _createClient(config);
        _setState(ConnectionState.connected);
        _monitorConnection();
        return;
      } on Exception {
        // Continue to next attempt.
      }
    }

    // All attempts exhausted.
    _setState(ConnectionState.disconnected);
  }

  /// Create an SSHClient from a ServerConfig.
  Future<SSHClient> _createClient(ServerConfig config) async {
    final socket = await SSHSocket.connect(config.host, config.port);

    final SSHClient client;
    switch (config.auth) {
      case PasswordAuth(password: final password):
        client = SSHClient(
          socket,
          username: config.username,
          onPasswordRequest: () => password,
        );
      case KeyAuth(privateKeyPath: final keyPath, passphrase: final passphrase):
        final keyContent = await File(keyPath).readAsString();
        final keyPairs = SSHKeyPair.fromPem(keyContent, passphrase);
        client = SSHClient(
          socket,
          username: config.username,
          identities: keyPairs,
        );
    }

    return client;
  }

  /// Monitor the connection and trigger reconnect on drop.
  void _monitorConnection() {
    final client = _client;
    if (client == null) return;

    client.done.then((_) {
      // Connection closed. If we still have a config, attempt reconnection.
      if (_config != null && _state == ConnectionState.connected) {
        _reconnect();
      }
    });
  }

  void _setState(ConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(newState);
  }

  /// Release resources.
  void dispose() {
    _client?.close();
    _client = null;
    _stateController.close();
  }
}

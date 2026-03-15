import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
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

/// Event emitted during SSH reconnection attempts.
class SshReconnectionEvent {
  /// Current attempt number (1-based).
  final int attempt;

  /// Maximum number of attempts before giving up.
  final int maxAttempts;

  /// Delay before the next attempt (zero if this is the last attempt).
  final Duration delay;

  /// Whether reconnection succeeded on this attempt.
  final bool succeeded;

  /// Error message if the attempt failed.
  final String? error;

  const SshReconnectionEvent({
    required this.attempt,
    required this.maxAttempts,
    required this.delay,
    required this.succeeded,
    this.error,
  });
}

/// SSH client service wrapping dartssh2.
///
/// Manages a single SSH connection with automatic reconnection support
/// using exponential backoff (1s, 2s, 4s, 8s, max 30s) and connection
/// state monitoring.
class SshService {
  static const _tag = 'SshService';

  SSHClient? _client;
  ServerConfig? _config;

  final _stateController = StreamController<ConnectionState>.broadcast();
  final _reconnectionController =
      StreamController<SshReconnectionEvent>.broadcast();
  ConnectionState _state = ConnectionState.disconnected;

  /// Maximum number of reconnection attempts before giving up.
  static const defaultMaxReconnectAttempts = 10;

  /// Maximum backoff delay between reconnection attempts.
  static const maxBackoffDelay = Duration(seconds: 30);

  /// Configurable max reconnection attempts. Defaults to
  /// [defaultMaxReconnectAttempts].
  int maxReconnectAttempts;

  /// Whether a reconnection loop is currently active.
  bool _reconnecting = false;

  /// Completer for tracking active reconnection, allowing cancellation.
  Completer<void>? _reconnectCompleter;

  SshService({this.maxReconnectAttempts = defaultMaxReconnectAttempts});

  /// Stream of connection state changes.
  Stream<ConnectionState> get connectionState => _stateController.stream;

  /// Stream of reconnection attempt events for UI and voice notifications.
  Stream<SshReconnectionEvent> get reconnectionEvents =>
      _reconnectionController.stream;

  /// Current connection state.
  ConnectionState get currentState => _state;

  /// Whether the client is currently connected.
  bool get isConnected => _state == ConnectionState.connected;

  /// Whether a reconnection loop is currently active.
  bool get isReconnecting => _reconnecting;

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
  ///
  /// Cancels any active reconnection loop before disconnecting.
  Future<void> disconnect() async {
    _cancelReconnection();
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
  ///
  /// Backoff schedule: 1s, 2s, 4s, 8s, 16s, 30s, 30s, ...
  /// Emits [SshReconnectionEvent]s for each attempt so the UI and voice
  /// layers can provide user feedback.
  Future<void> _reconnect() async {
    final config = _config;
    if (config == null) return;
    if (_reconnecting) return;

    _reconnecting = true;
    _reconnectCompleter = Completer<void>();
    _setState(ConnectionState.reconnecting);

    developer.log(
      'Starting reconnection (max $maxReconnectAttempts attempts)',
      name: _tag,
    );

    for (var attempt = 1; attempt <= maxReconnectAttempts; attempt++) {
      // Compute exponential backoff delay capped at maxBackoffDelay.
      final backoffSeconds = 1 << (attempt - 1); // 1, 2, 4, 8, 16, 32, ...
      final delay = Duration(
        seconds: backoffSeconds.clamp(1, maxBackoffDelay.inSeconds),
      );

      developer.log(
        'Reconnect attempt $attempt/$maxReconnectAttempts '
        '(delay: ${delay.inSeconds}s)',
        name: _tag,
      );

      // Emit pre-attempt event so UI can show countdown.
      _reconnectionController.add(SshReconnectionEvent(
        attempt: attempt,
        maxAttempts: maxReconnectAttempts,
        delay: delay,
        succeeded: false,
      ));

      await Future<void>.delayed(delay);

      // Check if reconnection was cancelled during the delay.
      if (!_reconnecting) {
        developer.log('Reconnection cancelled', name: _tag);
        return;
      }

      try {
        _client = await _createClient(config);
        _setState(ConnectionState.connected);
        _monitorConnection();

        _reconnectionController.add(SshReconnectionEvent(
          attempt: attempt,
          maxAttempts: maxReconnectAttempts,
          delay: Duration.zero,
          succeeded: true,
        ));

        developer.log('Reconnected on attempt $attempt', name: _tag);
        _reconnecting = false;
        _reconnectCompleter?.complete();
        _reconnectCompleter = null;
        return;
      } on Exception catch (e) {
        developer.log(
          'Reconnect attempt $attempt failed: $e',
          name: _tag,
        );

        _reconnectionController.add(SshReconnectionEvent(
          attempt: attempt,
          maxAttempts: maxReconnectAttempts,
          delay: Duration.zero,
          succeeded: false,
          error: e.toString(),
        ));
      }
    }

    // All attempts exhausted.
    developer.log('All reconnection attempts exhausted', name: _tag);
    _reconnecting = false;
    _reconnectCompleter?.complete();
    _reconnectCompleter = null;
    _setState(ConnectionState.disconnected);
  }

  /// Cancel any active reconnection loop.
  void _cancelReconnection() {
    _reconnecting = false;
    _reconnectCompleter?.complete();
    _reconnectCompleter = null;
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
        developer.log('Connection dropped, initiating reconnection', name: _tag);
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
    _cancelReconnection();
    _client?.close();
    _client = null;
    _stateController.close();
    _reconnectionController.close();
  }
}

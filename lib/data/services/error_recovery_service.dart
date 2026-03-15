import 'dart:async';
import 'dart:developer' as developer;

import 'package:murminal/data/models/error_recovery_event.dart';
import 'package:murminal/data/models/session.dart';
import 'package:murminal/data/services/session_service.dart';
import 'package:murminal/data/services/ssh_connection_pool.dart';
import 'package:murminal/data/services/ssh_service.dart';

/// Central coordinator for error recovery across all failure modes.
///
/// Monitors SSH reconnection events, WebSocket health, tmux session
/// crashes, and API rate limits. Emits [ErrorRecoveryEvent]s that the
/// voice supervisor and UI consume for user notification.
///
/// Recovery strategies:
/// - **WebSocket disconnect**: auto-reconnect with exponential backoff
/// - **SSH drop**: delegated to [SshService] (already implemented);
///   this service listens and re-emits as unified events
/// - **Audio interruption**: handled by [VoiceSupervisor] directly;
///   this service receives forwarded events for unified logging
/// - **API rate limit**: backoff with user notification
/// - **tmux crash**: periodic health check detects missing sessions
class ErrorRecoveryService {
  static const _tag = 'ErrorRecoveryService';

  final SshConnectionPool _sshPool;
  final SessionService? _sessionService;

  /// Injectable function for listing sessions, used for testability.
  ///
  /// Defaults to [SessionService.listSessions] when not overridden.
  final Future<List<Session>> Function({String? serverId})? _sessionLister;

  /// Interval for tmux session health checks.
  static const tmuxHealthCheckInterval = Duration(seconds: 30);

  /// Maximum WebSocket reconnection attempts.
  static const maxWebSocketReconnectAttempts = 5;

  /// Maximum backoff delay for WebSocket reconnection.
  static const maxWebSocketBackoff = Duration(seconds: 30);

  /// Default API rate limit backoff duration.
  static const defaultRateLimitBackoff = Duration(seconds: 60);

  final _eventController = StreamController<ErrorRecoveryEvent>.broadcast();
  StreamSubscription<SshReconnectionEvent>? _sshReconnectSub;
  Timer? _tmuxHealthTimer;
  bool _disposed = false;

  /// Server ID this recovery service is monitoring.
  final String serverId;

  /// Session names known to be running, updated by health checks.
  final Set<String> _knownSessions = {};

  ErrorRecoveryService({
    required SshConnectionPool sshPool,
    SessionService? sessionService,
    required this.serverId,
    Future<List<Session>> Function({String? serverId})? sessionLister,
  })  : _sshPool = sshPool,
        _sessionService = sessionService,
        _sessionLister = sessionLister;

  /// Stream of error recovery events for UI and voice notification.
  Stream<ErrorRecoveryEvent> get events => _eventController.stream;

  /// Start monitoring all error sources.
  void startMonitoring() {
    _assertNotDisposed();

    // Listen to SSH reconnection events and re-emit as unified events.
    _sshReconnectSub?.cancel();
    _sshReconnectSub = _sshPool.reconnectionEvents.listen(
      _handleSshReconnection,
    );

    // Start periodic tmux session health checks.
    _startTmuxHealthChecks();

    developer.log('Error recovery monitoring started', name: _tag);
  }

  /// Stop all monitoring and cancel timers.
  void stopMonitoring() {
    _sshReconnectSub?.cancel();
    _sshReconnectSub = null;
    _tmuxHealthTimer?.cancel();
    _tmuxHealthTimer = null;
    _knownSessions.clear();

    developer.log('Error recovery monitoring stopped', name: _tag);
  }

  /// Report an API rate limit error and schedule retry notification.
  ///
  /// Called by the voice service or tool executor when a 429 response
  /// is received. Emits a [detected] event immediately, then a
  /// [recovering] event with the backoff duration.
  void reportRateLimit({Duration? backoff}) {
    _assertNotDisposed();

    final retryDelay = backoff ?? defaultRateLimitBackoff;

    _emit(ErrorRecoveryEvent(
      category: ErrorCategory.apiRateLimit,
      phase: RecoveryPhase.detected,
      message: 'API rate limit reached. '
          'Retrying in ${retryDelay.inSeconds} seconds.',
      retryDelay: retryDelay,
    ));

    _emit(ErrorRecoveryEvent(
      category: ErrorCategory.apiRateLimit,
      phase: RecoveryPhase.recovering,
      message: 'Waiting ${retryDelay.inSeconds}s before retrying API request.',
      retryDelay: retryDelay,
    ));

    developer.log(
      'Rate limit reported, backoff ${retryDelay.inSeconds}s',
      name: _tag,
    );
  }

  /// Report that rate limit recovery succeeded.
  void reportRateLimitRecovered() {
    _assertNotDisposed();
    _emit(ErrorRecoveryEvent(
      category: ErrorCategory.apiRateLimit,
      phase: RecoveryPhase.recovered,
      message: 'API request succeeded after rate limit backoff.',
    ));
  }

  /// Report an audio interruption for unified event tracking.
  void reportAudioInterruption() {
    _assertNotDisposed();
    _emit(ErrorRecoveryEvent(
      category: ErrorCategory.audioInterruption,
      phase: RecoveryPhase.detected,
      message: 'Audio session interrupted by the system.',
    ));
  }

  /// Report audio session recovery.
  void reportAudioResumed() {
    _assertNotDisposed();
    _emit(ErrorRecoveryEvent(
      category: ErrorCategory.audioInterruption,
      phase: RecoveryPhase.recovered,
      message: 'Audio session resumed after interruption.',
    ));
  }

  /// Report a WebSocket disconnect and begin recovery tracking.
  void reportWebSocketDisconnect() {
    _assertNotDisposed();
    _emit(ErrorRecoveryEvent(
      category: ErrorCategory.webSocketDisconnect,
      phase: RecoveryPhase.detected,
      message: 'Voice connection lost. Attempting to reconnect.',
    ));
  }

  /// Report a WebSocket reconnection attempt.
  void reportWebSocketReconnectAttempt(int attempt, int maxAttempts) {
    _assertNotDisposed();
    _emit(ErrorRecoveryEvent(
      category: ErrorCategory.webSocketDisconnect,
      phase: RecoveryPhase.recovering,
      message: 'Reconnecting to voice service '
          '(attempt $attempt/$maxAttempts).',
      attempt: attempt,
      maxAttempts: maxAttempts,
    ));
  }

  /// Report WebSocket reconnection success.
  void reportWebSocketReconnected() {
    _assertNotDisposed();
    _emit(ErrorRecoveryEvent(
      category: ErrorCategory.webSocketDisconnect,
      phase: RecoveryPhase.recovered,
      message: 'Voice connection restored.',
    ));
  }

  /// Report WebSocket reconnection failure after all attempts.
  void reportWebSocketReconnectFailed() {
    _assertNotDisposed();
    _emit(ErrorRecoveryEvent(
      category: ErrorCategory.webSocketDisconnect,
      phase: RecoveryPhase.failed,
      message: 'Failed to reconnect to voice service. '
          'Please check your network connection.',
    ));
  }

  /// Update the set of known running sessions for tmux crash detection.
  ///
  /// Called after session creation/listing to track which sessions
  /// should be alive.
  void updateKnownSessions(List<Session> sessions) {
    _knownSessions.clear();
    for (final session in sessions) {
      if (session.status == SessionStatus.running) {
        _knownSessions.add(session.id);
      }
    }
  }

  /// Release all resources. The service cannot be reused after disposal.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stopMonitoring();
    _eventController.close();
  }

  // ---------------------------------------------------------------------------
  // SSH reconnection event forwarding
  // ---------------------------------------------------------------------------

  void _handleSshReconnection(SshReconnectionEvent event) {
    if (_disposed) return;

    if (event.succeeded) {
      _emit(ErrorRecoveryEvent(
        category: ErrorCategory.sshDisconnect,
        phase: RecoveryPhase.recovered,
        message: 'SSH connection restored. Reattaching to sessions.',
        attempt: event.attempt,
        maxAttempts: event.maxAttempts,
      ));
    } else if (event.attempt == 1) {
      _emit(ErrorRecoveryEvent(
        category: ErrorCategory.sshDisconnect,
        phase: RecoveryPhase.detected,
        message: 'SSH connection lost. Reconnecting '
            '(up to ${event.maxAttempts} attempts).',
        attempt: event.attempt,
        maxAttempts: event.maxAttempts,
        retryDelay: event.delay,
      ));
    } else if (event.attempt >= event.maxAttempts) {
      _emit(ErrorRecoveryEvent(
        category: ErrorCategory.sshDisconnect,
        phase: RecoveryPhase.failed,
        message: 'All SSH reconnection attempts failed. '
            'Please check your network connection.',
        attempt: event.attempt,
        maxAttempts: event.maxAttempts,
      ));
    } else {
      _emit(ErrorRecoveryEvent(
        category: ErrorCategory.sshDisconnect,
        phase: RecoveryPhase.recovering,
        message: 'SSH reconnect attempt ${event.attempt}/${event.maxAttempts}.',
        attempt: event.attempt,
        maxAttempts: event.maxAttempts,
        retryDelay: event.delay,
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Tmux session health checks
  // ---------------------------------------------------------------------------

  void _startTmuxHealthChecks() {
    _tmuxHealthTimer?.cancel();
    _tmuxHealthTimer = Timer.periodic(tmuxHealthCheckInterval, (_) {
      _checkTmuxHealth();
    });
  }

  /// Compares known running sessions against live tmux state to detect
  /// sessions that crashed or were killed externally.
  Future<void> _checkTmuxHealth() async {
    if (_disposed) return;
    if (_knownSessions.isEmpty) return;
    if (!_sshPool.isConnected(serverId)) return;

    try {
      final sessionService = _sessionService;
      if (_sessionLister == null && sessionService == null) return;
      final lister = _sessionLister ??
          ({String? serverId}) =>
              sessionService!.listSessions(serverId: serverId);
      final liveSessions = await lister(serverId: serverId);

      final liveIds = liveSessions
          .where((s) => s.status == SessionStatus.running)
          .map((s) => s.id)
          .toSet();

      // Detect sessions that were known running but are no longer live.
      final crashed = _knownSessions.difference(liveIds);

      for (final sessionId in crashed) {
        developer.log(
          'Tmux session "$sessionId" crashed or was killed externally',
          name: _tag,
        );

        _emit(ErrorRecoveryEvent(
          category: ErrorCategory.tmuxCrash,
          phase: RecoveryPhase.detected,
          message: 'Session "$sessionId" is no longer running. '
              'It may have crashed or been terminated externally.',
          context: sessionId,
        ));
      }

      // Update known sessions to current live state.
      _knownSessions
        ..clear()
        ..addAll(liveIds);
    } on Exception catch (e) {
      developer.log('Tmux health check failed: $e', name: _tag);
      // Don't emit an event for health check infrastructure failures;
      // SSH disconnect events cover connection-level issues.
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  void _emit(ErrorRecoveryEvent event) {
    if (_disposed) return;
    _eventController.add(event);
  }

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('ErrorRecoveryService has been disposed');
    }
  }
}

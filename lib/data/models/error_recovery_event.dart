/// Categories of recoverable errors handled by the error recovery system.
enum ErrorCategory {
  /// WebSocket connection to the voice API was lost.
  webSocketDisconnect,

  /// SSH connection to a remote server dropped.
  sshDisconnect,

  /// iOS audio session was interrupted (phone call, Siri, etc.).
  audioInterruption,

  /// API rate limit was hit; backing off before retrying.
  apiRateLimit,

  /// A tmux session crashed or was killed externally.
  tmuxCrash,
}

/// Current phase of an error recovery attempt.
enum RecoveryPhase {
  /// Error detected, recovery not yet started.
  detected,

  /// Recovery is in progress (reconnecting, resuming, etc.).
  recovering,

  /// Recovery succeeded; normal operation restored.
  recovered,

  /// Recovery failed after all retry attempts.
  failed,
}

/// Describes an error recovery event flowing through the system.
///
/// Published by [ErrorRecoveryService] and consumed by the voice supervisor
/// to announce errors via TTS and by the UI to display banners.
class ErrorRecoveryEvent {
  /// The type of error that occurred.
  final ErrorCategory category;

  /// Current phase of recovery.
  final RecoveryPhase phase;

  /// Human-readable description of the error or recovery status.
  final String message;

  /// Current retry attempt (1-based), if applicable.
  final int? attempt;

  /// Maximum retry attempts configured, if applicable.
  final int? maxAttempts;

  /// Delay before the next retry, if applicable.
  final Duration? retryDelay;

  /// When the event was created.
  final DateTime timestamp;

  /// Optional context (e.g., server ID, session name).
  final String? context;

  ErrorRecoveryEvent({
    required this.category,
    required this.phase,
    required this.message,
    this.attempt,
    this.maxAttempts,
    this.retryDelay,
    this.context,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() =>
      'ErrorRecoveryEvent(category: ${category.name}, '
      'phase: ${phase.name}, message: $message)';
}

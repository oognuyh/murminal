/// Represents the current state of the iOS audio session.
///
/// Used by [AudioSessionService] to communicate session lifecycle
/// changes to the rest of the application via a reactive stream.
enum AudioSessionState {
  /// Audio session is not configured or has been deactivated.
  deactivated,

  /// Audio session is active and audio I/O is available.
  active,

  /// Audio session was interrupted by the system (e.g. phone call,
  /// Siri activation, or another app claiming the audio route).
  /// Audio I/O is temporarily unavailable.
  interrupted,
}

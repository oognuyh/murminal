/// Represents the current operational state of the [VoiceSupervisor].
///
/// Exposed as a stream so the UI layer can reactively display the
/// supervisor's lifecycle phase (e.g. mic indicator, processing spinner).
enum VoiceSupervisorState {
  /// Supervisor is not running. No resources are held.
  idle,

  /// Establishing connections: audio session, mic, WebSocket.
  connecting,

  /// Mic is active and streaming audio to the Realtime API.
  /// Server-side VAD is listening for speech.
  listening,

  /// A tool call is being executed (e.g. tmux command).
  processing,

  /// The model is generating an audio response being played back.
  speaking,

  /// The audio session was interrupted by the system (phone call,
  /// other app). Mic and output monitoring are paused.
  interrupted,

  /// An unrecoverable error occurred. Call [VoiceSupervisor.stop]
  /// and inspect the error before restarting.
  error,
}

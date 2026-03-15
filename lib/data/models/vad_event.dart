/// Events emitted by the voice activity detection service.
///
/// Each subclass represents a distinct VAD state transition detected
/// from incoming PCM audio data.
sealed class VadEvent {
  const VadEvent();
}

/// Speech activity has been detected in the audio stream.
///
/// Emitted when the VAD transitions from silence to speech.
/// The [timestamp] indicates when speech was first detected.
class SpeechStart extends VadEvent {
  /// When the speech onset was detected.
  final DateTime timestamp;

  const SpeechStart({required this.timestamp});

  @override
  String toString() => 'SpeechStart(timestamp: $timestamp)';
}

/// Silence has been detected after a period of speech.
///
/// Emitted when continuous silence exceeds the configured
/// [VadConfig.silenceThreshold] duration after speech was active.
/// The [speechDuration] indicates how long the preceding speech lasted.
class SpeechEnd extends VadEvent {
  /// When the silence threshold was crossed.
  final DateTime timestamp;

  /// Duration of the preceding speech segment.
  final Duration speechDuration;

  const SpeechEnd({required this.timestamp, required this.speechDuration});

  @override
  String toString() =>
      'SpeechEnd(timestamp: $timestamp, speechDuration: $speechDuration)';
}

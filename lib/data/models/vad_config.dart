/// Configuration for voice activity detection.
///
/// Controls the sensitivity and timing parameters of the VAD algorithm.
/// The defaults are tuned for conversational voice interaction with
/// 16 kHz mono 16-bit PCM input from the microphone.
class VadConfig {
  /// Duration of continuous silence required to trigger a [SpeechEnd] event.
  ///
  /// Lower values make the VAD more responsive but may cause false
  /// end-of-speech triggers during natural pauses. Higher values add
  /// latency but reduce false positives.
  final Duration silenceThreshold;

  /// RMS energy threshold above which audio is considered speech.
  ///
  /// This is a normalized value in the range [0.0, 1.0] relative to
  /// the maximum possible amplitude for 16-bit PCM (32767).
  /// A typical voice signal at normal volume produces values around
  /// 0.02-0.05. Background noise is usually below 0.01.
  final double energyThreshold;

  /// Minimum number of consecutive speech frames required before
  /// emitting a [SpeechStart] event.
  ///
  /// Prevents short noise bursts from triggering false speech starts.
  /// At 16 kHz with 512-sample frames (~32ms each), a value of 3
  /// requires ~96ms of continuous speech.
  final int minSpeechFrames;

  /// Number of audio samples per analysis frame.
  ///
  /// Smaller frames give lower latency but less accurate energy
  /// estimation. Larger frames are more stable but add latency.
  /// At 16 kHz, 512 samples = 32ms per frame.
  final int frameSamples;

  /// Audio sample rate in Hz. Must match the microphone configuration.
  final int sampleRate;

  const VadConfig({
    this.silenceThreshold = const Duration(milliseconds: 1500),
    this.energyThreshold = 0.01,
    this.minSpeechFrames = 3,
    this.frameSamples = 512,
    this.sampleRate = 16000,
  });

  /// Default configuration suitable for 16 kHz mono PCM voice input.
  static const defaultConfig = VadConfig();

  /// Duration of a single analysis frame.
  Duration get frameDuration =>
      Duration(microseconds: (frameSamples * 1000000 ~/ sampleRate));
}

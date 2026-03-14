/// Configuration for microphone PCM capture.
///
/// Provides sensible defaults for the Qwen Omni Realtime API which
/// expects 16 kHz mono 16-bit PCM input.
class MicConfig {
  /// Audio sample rate in Hz.
  final int sampleRate;

  /// Number of audio channels (1 = mono, 2 = stereo).
  final int channels;

  /// Bits per sample (typically 16 for PCM).
  final int bitDepth;

  const MicConfig({
    this.sampleRate = 16000,
    this.channels = 1,
    this.bitDepth = 16,
  });

  /// Default configuration matching Qwen Omni Realtime API requirements.
  static const defaultConfig = MicConfig();
}

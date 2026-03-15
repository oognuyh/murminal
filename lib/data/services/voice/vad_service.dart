import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:murminal/data/models/vad_config.dart';
import 'package:murminal/data/models/vad_event.dart';

/// Energy-based voice activity detection service.
///
/// Analyzes incoming PCM audio chunks to detect speech onset and offset.
/// Uses RMS (root mean square) energy of each frame to distinguish speech
/// from silence. Designed as a drop-in replacement target for a future
/// Silero ONNX-based VAD while providing immediate functionality.
///
/// Usage:
/// ```dart
/// final vad = VadService();
/// vad.events.listen((event) {
///   if (event is SpeechStart) { /* start STT */ }
///   if (event is SpeechEnd)   { /* stop STT  */ }
/// });
///
/// micStream.listen(vad.processAudioChunk);
///
/// vad.dispose();
/// ```
class VadService {
  final VadConfig _config;

  final _eventController = StreamController<VadEvent>.broadcast();

  /// Accumulated PCM bytes that don't yet fill a complete frame.
  final _buffer = BytesBuilder(copy: false);

  /// Whether the VAD currently considers speech to be active.
  bool _isSpeechActive = false;

  /// Number of consecutive frames classified as speech.
  int _consecutiveSpeechFrames = 0;

  /// Number of consecutive frames classified as silence.
  int _consecutiveSilenceFrames = 0;

  /// Timestamp when the current speech segment started.
  DateTime? _speechStartTime;

  /// Number of silence frames required to trigger [SpeechEnd].
  late final int _silenceFrameThreshold;

  VadService({VadConfig config = VadConfig.defaultConfig}) : _config = config {
    _silenceFrameThreshold = _config.silenceThreshold.inMicroseconds ~/
        _config.frameDuration.inMicroseconds;
  }

  /// Stream of [VadEvent]s indicating speech start and end transitions.
  Stream<VadEvent> get events => _eventController.stream;

  /// Whether the VAD currently detects active speech.
  bool get isSpeechActive => _isSpeechActive;

  /// Current VAD configuration.
  VadConfig get config => _config;

  /// Processes a raw PCM audio chunk from the microphone.
  ///
  /// The [pcmData] must be 16-bit little-endian PCM samples matching
  /// the sample rate in [VadConfig]. Chunks can be any size; the
  /// service internally buffers and splits into analysis frames.
  void processAudioChunk(Uint8List pcmData) {
    _buffer.add(pcmData);

    final bytesPerFrame = _config.frameSamples * 2; // 16-bit = 2 bytes/sample

    while (_buffer.length >= bytesPerFrame) {
      final allBytes = _buffer.takeBytes();
      final frameBytes = Uint8List.sublistView(allBytes, 0, bytesPerFrame);

      // Put remaining bytes back into the buffer.
      if (allBytes.length > bytesPerFrame) {
        _buffer.add(
          Uint8List.sublistView(allBytes, bytesPerFrame),
        );
      }

      _processFrame(frameBytes);
    }
  }

  /// Resets the VAD state without disposing the service.
  ///
  /// Useful when starting a new recording session while keeping the
  /// same service instance.
  void reset() {
    _isSpeechActive = false;
    _consecutiveSpeechFrames = 0;
    _consecutiveSilenceFrames = 0;
    _speechStartTime = null;
    _buffer.clear();
  }

  /// Releases resources. The service must not be used after disposal.
  void dispose() {
    _eventController.close();
    _buffer.clear();
  }

  // ---------------------------------------------------------------------------
  // Internal frame processing
  // ---------------------------------------------------------------------------

  /// Analyzes a single frame of PCM audio and updates VAD state.
  void _processFrame(Uint8List frameBytes) {
    final energy = _computeRmsEnergy(frameBytes);
    final isSpeechFrame = energy >= _config.energyThreshold;

    if (isSpeechFrame) {
      _consecutiveSpeechFrames++;
      _consecutiveSilenceFrames = 0;

      if (!_isSpeechActive &&
          _consecutiveSpeechFrames >= _config.minSpeechFrames) {
        _isSpeechActive = true;
        _speechStartTime = DateTime.now();
        _eventController.add(SpeechStart(timestamp: _speechStartTime!));
      }
    } else {
      _consecutiveSilenceFrames++;

      if (_isSpeechActive &&
          _consecutiveSilenceFrames >= _silenceFrameThreshold) {
        final now = DateTime.now();
        final speechDuration = now.difference(_speechStartTime!);

        _isSpeechActive = false;
        _consecutiveSpeechFrames = 0;
        _consecutiveSilenceFrames = 0;
        _speechStartTime = null;

        _eventController.add(
          SpeechEnd(timestamp: now, speechDuration: speechDuration),
        );
      }

      // Don't reset consecutive speech frames while speech is active;
      // only reset when speech officially ends above.
      if (!_isSpeechActive) {
        _consecutiveSpeechFrames = 0;
      }
    }
  }

  /// Computes the normalized RMS energy of a 16-bit PCM frame.
  ///
  /// Returns a value in [0.0, 1.0] where 0.0 is silence and 1.0 is
  /// maximum possible amplitude for signed 16-bit audio.
  double _computeRmsEnergy(Uint8List frameBytes) {
    final samples = frameBytes.buffer.asInt16List(
      frameBytes.offsetInBytes,
      frameBytes.lengthInBytes ~/ 2,
    );

    if (samples.isEmpty) return 0.0;

    var sumOfSquares = 0.0;
    for (final sample in samples) {
      sumOfSquares += sample * sample;
    }

    final rms = math.sqrt(sumOfSquares / samples.length);

    // Normalize to [0, 1] using the max 16-bit amplitude.
    return rms / 32768.0;
  }
}

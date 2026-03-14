import 'dart:async';
import 'dart:typed_data';

import 'package:murminal/data/models/mic_config.dart';
import 'package:record/record.dart';

/// Manages microphone recording and exposes a raw PCM audio stream.
///
/// Uses the `record` package to capture audio from the device microphone
/// in PCM format. Designed to work alongside [AudioSessionService] which
/// handles the iOS AVAudioSession configuration for background audio.
///
/// Usage:
/// ```dart
/// final mic = MicService();
/// final granted = await mic.requestPermission();
/// if (granted) {
///   final stream = await mic.startRecording();
///   stream.listen((pcmChunk) { /* send to API */ });
/// }
/// ```
class MicService {
  final AudioRecorder _recorder = AudioRecorder();

  StreamController<Uint8List>? _streamController;
  StreamSubscription<Uint8List>? _recordingSub;
  bool _recording = false;

  /// Whether the microphone is currently recording.
  bool get isRecording => _recording;

  /// Requests microphone permission from the operating system.
  ///
  /// Returns `true` if permission is granted, `false` otherwise.
  /// On iOS this triggers the system permission dialog on first call.
  Future<bool> requestPermission() async {
    return _recorder.hasPermission();
  }

  /// Starts recording from the microphone and returns a PCM audio stream.
  ///
  /// The [config] parameter controls sample rate, channel count, and bit
  /// depth. Defaults to 16 kHz mono 16-bit PCM for Qwen Omni API
  /// compatibility.
  ///
  /// Throws [StateError] if recording is already in progress.
  Future<Stream<Uint8List>> startRecording({
    MicConfig config = MicConfig.defaultConfig,
  }) async {
    if (_recording) {
      throw StateError('Recording is already in progress.');
    }

    _streamController = StreamController<Uint8List>.broadcast();

    final recordStream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: config.sampleRate,
        numChannels: config.channels,
        bitRate: config.sampleRate * config.channels * config.bitDepth,
      ),
    );

    _recording = true;

    _recordingSub = recordStream.listen(
      (data) => _streamController?.add(data),
      onError: (Object error) => _streamController?.addError(error),
      onDone: () => _cleanup(),
    );

    return _streamController!.stream;
  }

  /// Stops the current recording session.
  ///
  /// If no recording is in progress this method is a no-op.
  Future<void> stopRecording() async {
    if (!_recording) return;

    await _recorder.stop();
    _cleanup();
  }

  /// Releases internal resources.
  void _cleanup() {
    _recordingSub?.cancel();
    _recordingSub = null;
    _streamController?.close();
    _streamController = null;
    _recording = false;
  }

  /// Permanently disposes the recorder.
  ///
  /// After calling this the service instance must not be reused.
  Future<void> dispose() async {
    await stopRecording();
    _recorder.dispose();
  }
}

import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Service for playing raw PCM16 audio chunks in real time.
///
/// Wraps the native iOS PcmPlayerPlugin which uses AVAudioEngine
/// for low-latency playback of 24kHz mono PCM data from Gemini Live.
class PcmPlayerService {
  static const _channel = MethodChannel('com.murminal/pcm_player');

  bool _started = false;

  /// Start the audio engine. Must be called before [play].
  Future<void> start() async {
    if (_started) return;
    await _channel.invokeMethod<void>('start');
    _started = true;
  }

  /// Play a chunk of raw PCM16 audio data (24kHz mono).
  Future<void> play(Uint8List pcmData) async {
    if (!_started) await start();
    await _channel.invokeMethod<void>('play', pcmData);
  }

  /// Stop the audio engine and release resources.
  Future<void> stop() async {
    if (!_started) return;
    await _channel.invokeMethod<void>('stop');
    _started = false;
  }
}

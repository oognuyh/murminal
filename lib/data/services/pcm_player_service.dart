import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Service for playing raw PCM16 audio chunks in real time.
///
/// Buffers incoming PCM chunks and flushes them to the native
/// AVAudioEngine player periodically to avoid platform channel
/// overhead per chunk, which causes stuttering and crackling.
class PcmPlayerService {
  static const _channel = MethodChannel('com.murminal/pcm_player');

  /// Flush interval — how often buffered audio is sent to native.
  static const _flushInterval = Duration(milliseconds: 50);

  bool _started = false;
  final _buffer = BytesBuilder(copy: false);
  Timer? _flushTimer;

  /// Start the audio engine. Must be called before [play].
  Future<void> start() async {
    if (_started) return;
    await _channel.invokeMethod<void>('start');
    _started = true;
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());
  }

  /// Queue a chunk of raw PCM16 audio data (24kHz mono) for playback.
  ///
  /// Chunks are buffered and flushed periodically to reduce
  /// platform channel overhead.
  void play(Uint8List pcmData) {
    if (!_started) {
      start(); // fire-and-forget
    }
    _buffer.add(pcmData);
  }

  /// Flush buffered audio to the native player.
  void _flush() {
    if (_buffer.isEmpty) return;
    final data = _buffer.toBytes();
    _buffer.clear();
    // Fire-and-forget — don't await to avoid blocking the event loop.
    _channel.invokeMethod<void>('play', data);
  }

  /// Stop the audio engine and release resources.
  Future<void> stop() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_buffer.isNotEmpty) {
      _flush();
    }
    if (!_started) return;
    await _channel.invokeMethod<void>('stop');
    _started = false;
  }
}

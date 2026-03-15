import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

/// On-device text-to-speech service wrapping iOS AVSpeechSynthesizer.
///
/// Uses a platform method channel to interface with the native iOS
/// SpeechSynthesisPlugin. Supports speaking text with configurable
/// language, rate, pitch, and volume parameters.
///
/// Usage:
/// ```dart
/// final tts = TtsService();
/// tts.events.listen((event) => print(event));
/// await tts.speak('Hello, world!');
/// ```
class TtsService {
  static const _tag = 'TtsService';
  static const _channel = MethodChannel('com.murminal/speech_synthesis');

  final _eventController = StreamController<TtsEvent>.broadcast();
  bool _speaking = false;
  Completer<void>? _speakCompleter;

  TtsService() {
    _channel.setMethodCallHandler(_handlePlatformCall);
  }

  /// Stream of TTS lifecycle events (started, finished, cancelled).
  Stream<TtsEvent> get events => _eventController.stream;

  /// Whether the synthesizer is currently speaking.
  bool get isSpeaking => _speaking;

  /// Speaks the given text using the device's speech synthesizer.
  ///
  /// Returns a [Future] that completes when the utterance finishes.
  /// If speech is already in progress, it is stopped first.
  Future<void> speak(
    String text, {
    String language = 'en-US',
    double rate = 0.5,
    double pitch = 1.0,
    double volume = 1.0,
  }) async {
    _speakCompleter = Completer<void>();

    try {
      await _channel.invokeMethod<void>('speak', {
        'text': text,
        'language': language,
        'rate': rate,
        'pitch': pitch,
        'volume': volume,
      });
      await _speakCompleter!.future;
    } on PlatformException catch (e) {
      developer.log('Failed to speak: $e', name: _tag);
      _speakCompleter?.complete();
      _speakCompleter = null;
      rethrow;
    }
  }

  /// Stops any ongoing speech immediately.
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
      _speaking = false;
      _speakCompleter?.complete();
      _speakCompleter = null;
    } on PlatformException catch (e) {
      developer.log('Failed to stop: $e', name: _tag);
    }
  }

  /// Queries available TTS voices on the device.
  Future<List<TtsVoice>> getVoices() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getVoices');
      if (result == null) return [];

      return result.map((item) {
        final map = item as Map<Object?, Object?>;
        return TtsVoice(
          identifier: map['identifier'] as String? ?? '',
          name: map['name'] as String? ?? '',
          language: map['language'] as String? ?? '',
          quality: (map['quality'] as int?) ?? 0,
        );
      }).toList();
    } on PlatformException catch (e) {
      developer.log('Failed to get voices: $e', name: _tag);
      return [];
    }
  }

  /// Handles method calls from the native platform.
  Future<void> _handlePlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onStart':
        _speaking = true;
        _eventController.add(TtsEvent.started);
      case 'onFinish':
        _speaking = false;
        _eventController.add(TtsEvent.finished);
        _speakCompleter?.complete();
        _speakCompleter = null;
      case 'onCancel':
        _speaking = false;
        _eventController.add(TtsEvent.cancelled);
        _speakCompleter?.complete();
        _speakCompleter = null;
    }
  }

  /// Releases all resources held by this service.
  void dispose() {
    stop();
    _eventController.close();
  }
}

/// Lifecycle events emitted by the TTS engine.
enum TtsEvent {
  /// Speech synthesis has started.
  started,

  /// Speech synthesis has finished normally.
  finished,

  /// Speech synthesis was cancelled.
  cancelled,
}

/// Represents an available TTS voice on the device.
class TtsVoice {
  final String identifier;
  final String name;
  final String language;
  final int quality;

  const TtsVoice({
    required this.identifier,
    required this.name,
    required this.language,
    required this.quality,
  });

  @override
  String toString() => 'TtsVoice(name: $name, language: $language)';
}

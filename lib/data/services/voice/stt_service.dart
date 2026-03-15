import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

/// On-device speech-to-text service wrapping iOS SFSpeechRecognizer.
///
/// Uses a platform method channel to interface with the native iOS
/// SpeechRecognitionPlugin. Streams partial and final transcription
/// results to the caller. Supports on-device recognition for offline
/// capability when available.
///
/// Usage:
/// ```dart
/// final stt = SttService();
/// final granted = await stt.requestPermission();
/// if (granted) {
///   stt.transcripts.listen((result) => print(result.text));
///   await stt.startListening();
/// }
/// ```
class SttService {
  static const _tag = 'SttService';
  static const _channel = MethodChannel('com.murminal/speech_recognition');

  final _transcriptController = StreamController<SttResult>.broadcast();
  bool _listening = false;

  SttService() {
    _channel.setMethodCallHandler(_handlePlatformCall);
  }

  /// Stream of transcription results from the speech recognizer.
  Stream<SttResult> get transcripts => _transcriptController.stream;

  /// Whether the service is currently listening for speech.
  bool get isListening => _listening;

  /// Requests speech recognition permission from the user.
  ///
  /// Returns `true` if authorization is granted, `false` otherwise.
  Future<bool> requestPermission() async {
    try {
      final status =
          await _channel.invokeMethod<String>('requestPermission');
      developer.log('Speech permission status: $status', name: _tag);
      return status == 'authorized';
    } on PlatformException catch (e) {
      developer.log('Permission request failed: $e', name: _tag);
      return false;
    }
  }

  /// Checks whether speech recognition is available on this device.
  Future<bool> isAvailable() async {
    try {
      final available =
          await _channel.invokeMethod<bool>('isAvailable') ?? false;
      return available;
    } on PlatformException {
      return false;
    }
  }

  /// Checks whether on-device (offline) recognition is supported.
  Future<bool> supportsOnDevice() async {
    try {
      final supported =
          await _channel.invokeMethod<bool>('supportsOnDevice') ?? false;
      return supported;
    } on PlatformException {
      return false;
    }
  }

  /// Starts listening for speech input.
  ///
  /// Transcription results are emitted on the [transcripts] stream.
  /// The [locale] parameter controls the recognition language (default: en-US).
  Future<void> startListening({String locale = 'en-US'}) async {
    if (_listening) return;

    try {
      await _channel.invokeMethod<void>(
        'startListening',
        {'locale': locale},
      );
      _listening = true;
      developer.log('Started listening (locale: $locale)', name: _tag);
    } on PlatformException catch (e) {
      developer.log('Failed to start listening: $e', name: _tag);
      rethrow;
    }
  }

  /// Stops listening for speech input.
  Future<void> stopListening() async {
    if (!_listening) return;

    try {
      await _channel.invokeMethod<void>('stopListening');
      _listening = false;
      developer.log('Stopped listening', name: _tag);
    } on PlatformException catch (e) {
      developer.log('Failed to stop listening: $e', name: _tag);
    }
  }

  /// Handles method calls from the native platform.
  Future<void> _handlePlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onTranscript':
        final args = call.arguments as Map<Object?, Object?>;
        final text = args['text'] as String? ?? '';
        final isFinal = args['isFinal'] as bool? ?? false;
        _transcriptController.add(SttResult(text: text, isFinal: isFinal));
        if (isFinal) {
          _listening = false;
        }
      case 'onError':
        final args = call.arguments as Map<Object?, Object?>;
        final message = args['message'] as String? ?? 'Unknown error';
        developer.log('Recognition error: $message', name: _tag);
        _transcriptController.addError(SttError(message));
        _listening = false;
    }
  }

  /// Releases all resources held by this service.
  void dispose() {
    stopListening();
    _transcriptController.close();
  }
}

/// A transcription result from the speech recognizer.
class SttResult {
  /// The recognized text.
  final String text;

  /// Whether this is a final (non-partial) result.
  final bool isFinal;

  const SttResult({required this.text, required this.isFinal});

  @override
  String toString() => 'SttResult(text: $text, isFinal: $isFinal)';
}

/// Error from the speech recognition engine.
class SttError implements Exception {
  final String message;
  const SttError(this.message);

  @override
  String toString() => 'SttError: $message';
}

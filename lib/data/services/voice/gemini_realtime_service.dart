import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:murminal/data/models/gemini_realtime_event.dart';
import 'package:murminal/data/models/tool_definition.dart';
import 'package:murminal/data/models/voice_event.dart';
import 'package:murminal/data/services/voice/realtime_voice_service.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Gemini Live voice service implementation.
///
/// Connects to the Google Gemini Live WebSocket API
/// (BidiGenerateContent). Handles:
/// - Session setup with system instruction and tool declarations
/// - Bidirectional audio streaming (input 16kHz, output 24kHz PCM16)
/// - Function calling round-trips
/// - Proactive audio report injection via client content
/// - Automatic reconnection with exponential backoff
class GeminiRealtimeService extends RealtimeVoiceService {
  static const _defaultModel = 'gemini-2.5-flash-native-audio-preview-12-2025';
  static const _tag = 'GeminiRealtimeService';

  /// Maximum WebSocket reconnection attempts on unexpected disconnect.
  static const maxReconnectAttempts = 5;

  /// Maximum backoff delay between reconnection attempts.
  static const maxBackoffDelay = Duration(seconds: 30);

  static const _baseEndpoint =
      'wss://generativelanguage.googleapis.com/ws/'
      'google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final StreamController<VoiceEvent> _eventController =
      StreamController<VoiceEvent>.broadcast();

  String? _apiKey;
  String? _model;
  List<ToolDefinition>? _tools;
  String? _systemPrompt;
  bool _connected = false;
  bool _reconnecting = false;

  /// Callback invoked when a rate limit is detected.
  void Function(Duration backoff)? onRateLimitDetected;

  /// Callback invoked on each reconnection attempt.
  void Function(int attempt, int maxAttempts)? onReconnectAttempt;

  /// Callback invoked when reconnection succeeds.
  void Function()? onReconnected;

  /// Callback invoked when all reconnection attempts fail.
  void Function()? onReconnectFailed;

  /// Callback invoked on unexpected disconnect.
  void Function()? onDisconnected;

  @override
  Stream<VoiceEvent> get events => _eventController.stream;

  @override
  Future<void> connect(
    String apiKey, {
    String? model,
    List<ToolDefinition>? tools,
  }) async {
    _apiKey = apiKey;
    _model = model ?? _defaultModel;
    _tools = tools;

    await _establishConnection();
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  @override
  void sendAudio(Uint8List pcmData) {
    _send({
      'realtimeInput': {
        'mediaChunks': [
          {
            'mimeType': 'audio/pcm;rate=16000',
            'data': base64Encode(pcmData),
          },
        ],
      },
    });
  }

  @override
  void sendToolResult(String callId, String result) {
    Map<String, dynamic> parsedResult;
    try {
      parsedResult = jsonDecode(result) as Map<String, dynamic>;
    } catch (_) {
      parsedResult = {'result': result};
    }

    _send({
      'toolResponse': {
        'functionResponses': [
          {
            'id': callId,
            'response': parsedResult,
          },
        ],
      },
    });
  }

  @override
  Future<void> injectAudioReport(Uint8List pcmData) async {
    // Send audio as realtime input, then send a text hint to relay it.
    _send({
      'realtimeInput': {
        'mediaChunks': [
          {
            'mimeType': 'audio/pcm;rate=16000',
            'data': base64Encode(pcmData),
          },
        ],
      },
    });
  }

  @override
  Future<void> updateSystemPrompt(String prompt) async {
    _systemPrompt = prompt;
    // Gemini Live doesn't support updating system instruction mid-session
    // without reconnecting. Store for next reconnection.
    developer.log('System prompt updated (applies on next reconnect)', name: _tag);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _establishConnection() async {
    final apiKey = _apiKey;
    if (apiKey == null) return;

    final uri = Uri.parse('$_baseEndpoint?key=$apiKey');

    _channel = IOWebSocketChannel.connect(uri);

    try {
      await _channel!.ready;
    } on WebSocketChannelException catch (e) {
      _eventController.add(VoiceError('Connection failed: $e'));
      return;
    }

    _connected = true;
    _listenToEvents();
    _sendSetup();
  }

  /// Sends the initial setup message with model config, system instruction,
  /// and tool declarations.
  void _sendSetup() {
    final setup = <String, dynamic>{
      'model': 'models/$_model',
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        'speechConfig': {
          'voiceConfig': {
            'prebuiltVoiceConfig': {
              'voiceName': 'Kore',
            },
          },
        },
      },
    };

    if (_systemPrompt != null) {
      setup['systemInstruction'] = {
        'parts': [
          {'text': _systemPrompt},
        ],
      };
    }

    if (_tools != null && _tools!.isNotEmpty) {
      setup['tools'] = [
        {
          'functionDeclarations': _tools!.map((t) => <String, dynamic>{
            'name': t.name,
            'description': t.description,
            'parameters': t.parameters,
          }).toList(),
        },
      ];
    }

    _send({'setup': setup});
  }

  void _listenToEvents() {
    _subscription = _channel?.stream.listen(
      _onMessage,
      onError: (Object error) {
        developer.log('WebSocket error: $error', name: _tag);
        _eventController.add(VoiceError('WebSocket error: $error'));
      },
      onDone: () {
        developer.log('WebSocket closed', name: _tag);
        if (_connected) {
          _reconnect();
        }
      },
    );
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;

    // Log first 200 chars of every incoming message for debugging.
    final preview = raw.length > 200 ? '${raw.substring(0, 200)}...' : raw;
    debugPrint('Gemini ← $preview');

    final event = GeminiRealtimeEvent.fromJson(raw);
    _dispatchEvent(event);
  }

  void _dispatchEvent(GeminiRealtimeEvent event) {
    switch (event) {
      case GeminiSetupComplete():
        debugPrint('Gemini: setupComplete received');
        _eventController.add(const SessionCreated('gemini-live'));

      case GeminiTextChunk():
        _eventController.add(TextDelta(event.text));

      case GeminiAudioChunk():
        _eventController.add(AudioDelta(event.audio));

      case GeminiTurnComplete():
        _eventController.add(const AudioDone());

      case GeminiInterrupted():
        developer.log('Model output interrupted by user speech', name: _tag);
        _eventController.add(const AudioDone());

      case GeminiToolCall():
        for (final fc in event.functionCalls) {
          _eventController.add(ToolCallRequest(
            callId: fc.id,
            name: fc.name,
            arguments: fc.args,
          ));
        }

      case GeminiServerContent():
        for (final part in event.parts) {
          _dispatchEvent(part);
        }
        if (event.turnComplete) {
          _eventController.add(const AudioDone());
        }

      case GeminiUnknownEvent():
        developer.log(
          'Unknown event: ${event.raw.keys}',
          name: _tag,
        );
    }
  }

  Future<void> _reconnect() async {
    if (_reconnecting) return;
    _reconnecting = true;

    developer.log(
      'Starting WebSocket reconnection (max $maxReconnectAttempts attempts)',
      name: _tag,
    );

    onDisconnected?.call();

    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;

    for (var attempt = 1; attempt <= maxReconnectAttempts; attempt++) {
      if (!_connected) {
        _reconnecting = false;
        return;
      }

      final backoffSeconds = 1 << (attempt - 1);
      final delay = Duration(
        seconds: backoffSeconds.clamp(1, maxBackoffDelay.inSeconds),
      );

      developer.log(
        'WebSocket reconnect attempt $attempt/$maxReconnectAttempts '
        '(delay: ${delay.inSeconds}s)',
        name: _tag,
      );

      onReconnectAttempt?.call(attempt, maxReconnectAttempts);

      await Future<void>.delayed(delay);

      if (!_connected) {
        _reconnecting = false;
        return;
      }

      try {
        await _establishConnection();
        developer.log(
          'WebSocket reconnected on attempt $attempt',
          name: _tag,
        );
        onReconnected?.call();
        _reconnecting = false;
        return;
      } on Exception catch (e) {
        developer.log(
          'WebSocket reconnect attempt $attempt failed: $e',
          name: _tag,
        );
      }
    }

    developer.log('All WebSocket reconnection attempts exhausted', name: _tag);
    onReconnectFailed?.call();
    _reconnecting = false;
    _connected = false;
    _eventController.add(const VoiceError(
      'Voice connection lost. All reconnection attempts failed.',
    ));
  }

  void _send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) {
      developer.log('Cannot send — not connected', name: _tag);
      return;
    }
    channel.sink.add(jsonEncode(message));
  }
}

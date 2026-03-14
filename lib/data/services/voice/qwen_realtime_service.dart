import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:murminal/data/models/qwen_realtime_event.dart';
import 'package:murminal/data/models/tool_definition.dart';
import 'package:murminal/data/models/voice_event.dart';
import 'package:murminal/data/services/voice/realtime_voice_service.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Qwen Omni Realtime voice service implementation.
///
/// Connects to the Alibaba Cloud DashScope Realtime WebSocket API using
/// OpenAI-compatible protocol headers. Handles:
/// - Session establishment with system prompt and tool definitions
/// - Bidirectional audio streaming with server-side VAD
/// - Function calling round-trips
/// - Proactive audio report injection
/// - Automatic reconnection on 120-minute session timeout
class QwenRealtimeService extends RealtimeVoiceService {
  static const _defaultModel = 'qwen-omni-turbo-latest';
  static const _tag = 'QwenRealtimeService';

  /// Maximum session duration before forced reconnection.
  static const _sessionTimeout = Duration(minutes: 120);

  /// Endpoint for the international DashScope Realtime API.
  static const _endpoint =
      'wss://dashscope-intl.aliyuncs.com/api-ws/v1/inference';

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final StreamController<VoiceEvent> _eventController =
      StreamController<VoiceEvent>.broadcast();

  Timer? _sessionTimer;
  String? _apiKey;
  String? _model;
  List<ToolDefinition>? _tools;
  String? _systemPrompt;
  bool _connected = false;

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
    _sessionTimer?.cancel();
    _sessionTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  @override
  void sendAudio(Uint8List pcmData) {
    _send({
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(pcmData),
    });
  }

  @override
  void sendToolResult(String callId, String result) {
    _send({
      'type': 'conversation.item.create',
      'item': {
        'type': 'function_call_output',
        'call_id': callId,
        'output': result,
      },
    });
    // Prompt the model to continue after receiving the tool result.
    _send({'type': 'response.create'});
  }

  @override
  Future<void> injectAudioReport(Uint8List pcmData) async {
    _send({
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(pcmData),
    });
    _send({'type': 'input_audio_buffer.commit'});
    _send({'type': 'response.create'});
  }

  @override
  Future<void> updateSystemPrompt(String prompt) async {
    _systemPrompt = prompt;
    _sendSessionUpdate();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Opens the WebSocket, listens for events, and sends the initial
  /// session.update configuration.
  Future<void> _establishConnection() async {
    final apiKey = _apiKey;
    if (apiKey == null) return;

    final uri = Uri.parse('$_endpoint?model=$_model');

    _channel = IOWebSocketChannel.connect(
      uri,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'OpenAI-Beta': 'realtime=v1',
      },
    );

    try {
      await _channel!.ready;
    } on WebSocketChannelException catch (e) {
      _eventController.add(VoiceError('Connection failed: $e'));
      return;
    }

    _connected = true;
    _listenToEvents();
    _startSessionTimer();
  }

  /// Subscribes to the WebSocket stream and dispatches parsed events.
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
          // Unexpected closure — attempt reconnection.
          _reconnect();
        }
      },
    );
  }

  /// Parses a raw WebSocket message and emits the corresponding [VoiceEvent].
  void _onMessage(dynamic raw) {
    if (raw is! String) return;

    final event = QwenRealtimeEvent.fromJson(raw);

    switch (event) {
      case QwenSessionCreated():
        _sendSessionUpdate();
        _eventController.add(SessionCreated(event.sessionId));

      case QwenSessionUpdated():
        developer.log('Session updated', name: _tag);

      case QwenTextDelta():
        _eventController.add(TextDelta(event.delta));

      case QwenTextDone():
        _eventController.add(TextDone(event.text));

      case QwenAudioDelta():
        _eventController.add(AudioDelta(event.audio));

      case QwenAudioDone():
        _eventController.add(const AudioDone());

      case QwenFunctionCallArgumentsDelta():
        // Partial arguments are accumulated; no event emitted until done.
        break;

      case QwenFunctionCallArgumentsDone():
        _eventController.add(ToolCallRequest(
          callId: event.callId,
          name: event.name,
          arguments: _tryDecodeJson(event.arguments),
        ));

      case QwenResponseDone():
        developer.log('Response complete', name: _tag);

      case QwenSpeechStarted():
        developer.log('Speech started', name: _tag);

      case QwenSpeechStopped():
        developer.log('Speech stopped', name: _tag);

      case QwenBufferCommitted():
        developer.log('Buffer committed', name: _tag);

      case QwenError():
        _eventController.add(VoiceError(event.message));

      case QwenUnknownEvent():
        developer.log(
          'Unknown event: ${event.type}',
          name: _tag,
        );
    }
  }

  /// Sends the session configuration (system prompt + tools) to the server.
  void _sendSessionUpdate() {
    final session = <String, dynamic>{
      'modalities': ['text', 'audio'],
      'input_audio_format': 'pcm16',
      'output_audio_format': 'pcm16',
      'turn_detection': {
        'type': 'server_vad',
      },
    };

    if (_systemPrompt != null) {
      session['instructions'] = _systemPrompt;
    }

    if (_tools != null && _tools!.isNotEmpty) {
      session['tools'] = _tools!.map((t) => t.toJson()).toList();
    }

    _send({
      'type': 'session.update',
      'session': session,
    });
  }

  /// Starts a timer that triggers reconnection before the 120-minute
  /// session limit is reached.
  void _startSessionTimer() {
    _sessionTimer?.cancel();
    // Reconnect slightly before the hard limit to avoid mid-conversation drops.
    final reconnectAt = _sessionTimeout - const Duration(minutes: 2);
    _sessionTimer = Timer(reconnectAt, _reconnect);
  }

  /// Tears down the current connection and re-establishes it, preserving
  /// the API key, model, tools, and system prompt configuration.
  Future<void> _reconnect() async {
    developer.log('Reconnecting (session timeout or unexpected close)',
        name: _tag);
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _sessionTimer?.cancel();
    _sessionTimer = null;

    if (_connected) {
      await _establishConnection();
    }
  }

  /// Serializes and sends a JSON message through the WebSocket.
  void _send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) {
      developer.log('Cannot send — not connected', name: _tag);
      return;
    }
    channel.sink.add(jsonEncode(message));
  }

  /// Attempts to decode a JSON string into a Map, returning an empty map
  /// on failure.
  Map<String, dynamic> _tryDecodeJson(String source) {
    try {
      return jsonDecode(source) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}

import 'dart:typed_data';

import 'package:murminal/data/models/tool_definition.dart';
import 'package:murminal/data/models/voice_event.dart';

/// Abstract interface for Realtime WebSocket voice providers.
///
/// Implementations connect directly to a provider's Realtime WebSocket API
/// (Qwen Omni, Gemini Live, or OpenAI Realtime) without an intermediate
/// agent framework. The API handles server-side VAD, function calling,
/// and multi-turn conversation natively.
///
/// Usage:
/// ```dart
/// final service = QwenRealtimeService(); // or any provider
/// await service.connect(apiKey: key, tools: tools);
/// service.events.listen((event) { /* handle events */ });
/// service.sendAudio(pcmChunk);
/// await service.disconnect();
/// ```
abstract class RealtimeVoiceService {
  /// Establishes a WebSocket connection to the Realtime API.
  ///
  /// [apiKey] is the user-provided API key (BYOK).
  /// [model] optionally overrides the default model for the provider.
  /// [tools] defines the function calling schema available to the model.
  Future<void> connect(
    String apiKey, {
    String? model,
    List<ToolDefinition>? tools,
  });

  /// Closes the WebSocket connection and releases resources.
  Future<void> disconnect();

  /// Streams PCM audio data to the Realtime API input buffer.
  ///
  /// Audio should be 16-bit PCM at the sample rate expected by the
  /// provider (typically 16kHz or 24kHz).
  void sendAudio(Uint8List pcmData);

  /// Returns the result of a tool call back to the model.
  ///
  /// [callId] must match the [ToolCallRequest.callId] from the event.
  /// [result] is the JSON-serialized tool output.
  void sendToolResult(String callId, String result);

  /// Injects pre-rendered TTS audio into the input buffer for
  /// proactive reporting.
  ///
  /// Flow: append PCM data → commit buffer → request response.
  /// The model's system prompt instructs it to relay [REPORT]-prefixed
  /// audio as system monitor updates to the user.
  Future<void> injectAudioReport(Uint8List pcmData);

  /// Updates the session's system prompt without reconnecting.
  ///
  /// Used to refresh the server/session state context that the
  /// Supervisor provides to the model.
  Future<void> updateSystemPrompt(String prompt);

  /// Stream of events received from the Realtime WebSocket API.
  ///
  /// Includes text deltas, audio chunks, tool call requests,
  /// session lifecycle events, and errors.
  Stream<VoiceEvent> get events;
}

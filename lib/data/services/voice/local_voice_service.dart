import 'dart:async';
import 'dart:developer' as developer;

import 'package:murminal/data/models/tool_definition.dart';
import 'package:murminal/data/models/voice_event.dart';
import 'package:murminal/data/services/voice/lm_service.dart';
import 'package:murminal/data/services/voice/stt_service.dart';
import 'package:murminal/data/services/voice/tts_service.dart';

/// On-device voice pipeline that wires STT -> LM -> TTS.
///
/// Unlike [RealtimeVoiceService] which uses a single WebSocket for
/// audio-in/audio-out, this service composes three independent components:
/// - [SttService]: On-device speech-to-text (iOS SFSpeechRecognizer)
/// - [LmService]: Any text-based LM API (Claude, OpenAI, Gemini)
/// - [TtsService]: On-device text-to-speech (iOS AVSpeechSynthesizer)
///
/// This approach works with any text LM API and has zero cost for
/// STT/TTS since both run on-device.
///
/// The service emits [VoiceEvent]s through the [events] stream,
/// maintaining compatibility with [VoiceSupervisor] which expects
/// the same event interface as [RealtimeVoiceService].
class LocalVoiceService {
  static const _tag = 'LocalVoiceService';

  final SttService _stt;
  final TtsService _tts;
  final LmService _lm;

  final _eventController = StreamController<VoiceEvent>.broadcast();
  StreamSubscription<SttResult>? _sttSub;
  StreamSubscription<TtsEvent>? _ttsSub;

  String _systemPrompt = '';
  List<ToolDefinition>? _tools;
  final List<LmMessage> _conversationHistory = [];
  bool _connected = false;

  /// Callback for tool call execution results.
  ///
  /// Set by [LocalVoiceSupervisor] or the pipeline coordinator.
  /// When the LM requests a tool call, this service emits a
  /// [ToolCallRequest] event and waits for the result via
  /// [sendToolResult].
  void Function(String callId, String result)? onToolResult;

  LocalVoiceService({
    required SttService stt,
    required TtsService tts,
    required LmService lm,
  })  : _stt = stt,
        _tts = tts,
        _lm = lm;

  /// Stream of voice events for the supervisor.
  Stream<VoiceEvent> get events => _eventController.stream;

  /// Whether the pipeline is currently active.
  bool get isConnected => _connected;

  /// Configures and starts the local voice pipeline.
  ///
  /// [apiKey] is used for the LM service. STT/TTS are free on-device.
  /// [tools] defines function calling schemas for the LM.
  Future<void> connect(
    String apiKey, {
    String? model,
    List<ToolDefinition>? tools,
  }) async {
    _lm.configure(apiKey: apiKey, model: model);
    _tools = tools;
    _connected = true;

    // Subscribe to STT transcription results.
    _sttSub = _stt.transcripts.listen(_handleTranscript);

    // Subscribe to TTS lifecycle events.
    _ttsSub = _tts.events.listen(_handleTtsEvent);

    _eventController.add(const SessionCreated('local-voice'));
    developer.log('Local voice pipeline connected', name: _tag);
  }

  /// Stops the pipeline and releases resources.
  Future<void> disconnect() async {
    _connected = false;
    _sttSub?.cancel();
    _sttSub = null;
    _ttsSub?.cancel();
    _ttsSub = null;
    await _stt.stopListening();
    await _tts.stop();
    _conversationHistory.clear();
    developer.log('Local voice pipeline disconnected', name: _tag);
  }

  /// Starts listening for speech input.
  ///
  /// Called by the supervisor when the mic should be active.
  Future<void> startListening({String locale = 'en-US'}) async {
    if (!_connected) return;
    await _stt.startListening(locale: locale);
  }

  /// Stops listening for speech input.
  Future<void> stopListening() async {
    await _stt.stopListening();
  }

  /// Sends a tool call result back into the conversation.
  ///
  /// After the supervisor executes a tool, it calls this method
  /// so the LM can incorporate the result in its next response.
  Future<void> sendToolResult(String callId, String result) async {
    _conversationHistory.add(LmMessage.toolResult(
      callId: callId,
      name: callId, // Use callId as name fallback
      content: result,
    ));

    // Continue the conversation after tool result.
    await _processLmResponse();
  }

  /// Injects a text report into the conversation for proactive reporting.
  ///
  /// The report is sent as a user message to the LM, which generates
  /// a spoken summary via TTS.
  Future<void> injectTextReport(String report) async {
    if (!_connected) return;

    _conversationHistory.add(LmMessage.user(report));
    await _processLmResponse();
  }

  /// Updates the system prompt without reconnecting.
  Future<void> updateSystemPrompt(String prompt) async {
    _systemPrompt = prompt;
    developer.log('System prompt updated', name: _tag);
  }

  // ---------------------------------------------------------------------------
  // Internal handlers
  // ---------------------------------------------------------------------------

  /// Handles a transcription result from STT.
  ///
  /// Only processes final results to avoid sending partial transcripts
  /// to the LM. On final result, adds the user message to history
  /// and triggers LM completion.
  void _handleTranscript(SttResult result) {
    _eventController.add(TextDelta(result.text));

    if (result.isFinal && result.text.trim().isNotEmpty) {
      _eventController.add(TextDone(result.text));
      _conversationHistory.add(LmMessage.user(result.text));
      _processLmResponse();
    }
  }

  /// Sends the conversation to the LM and processes the response.
  ///
  /// If the response contains tool calls, emits [ToolCallRequest]
  /// events. Otherwise, speaks the text response via TTS.
  Future<void> _processLmResponse() async {
    if (!_connected) return;

    try {
      final lmTools = _tools
          ?.map((t) => LmTool(
                name: t.name,
                description: t.description,
                parameters: t.parameters,
              ))
          .toList();

      final response = await _lm.complete(
        systemPrompt: _systemPrompt,
        messages: _conversationHistory,
        tools: lmTools,
      );

      if (response.hasToolCalls) {
        // Emit tool call requests for the supervisor to handle.
        for (final tc in response.toolCalls) {
          _eventController.add(ToolCallRequest(
            callId: tc.id,
            name: tc.name,
            arguments: tc.arguments,
          ));
        }

        // Add assistant response to history for context.
        if (response.text.isNotEmpty) {
          _conversationHistory
              .add(LmMessage.assistant(response.text));
        }
      } else if (response.text.isNotEmpty) {
        // Add response to history and speak it.
        _conversationHistory
            .add(LmMessage.assistant(response.text));

        _eventController.add(TextDelta(response.text));
        _eventController.add(TextDone(response.text));

        // Speak the response via TTS.
        await _tts.speak(response.text);
      }
    } catch (e) {
      developer.log('LM processing error: $e', name: _tag);
      _eventController.add(VoiceError('LM error: $e'));
    }
  }

  /// Handles TTS lifecycle events and maps them to voice events.
  void _handleTtsEvent(TtsEvent event) {
    switch (event) {
      case TtsEvent.started:
        // TTS started speaking — emit audio events for state tracking.
        break;
      case TtsEvent.finished:
        _eventController.add(const AudioDone());
        // Restart STT listening after TTS finishes.
        if (_connected) {
          _stt.startListening();
        }
      case TtsEvent.cancelled:
        _eventController.add(const AudioDone());
    }
  }

  /// Releases all resources permanently.
  void dispose() {
    disconnect();
    _eventController.close();
  }
}

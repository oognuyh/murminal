import 'dart:convert';
import 'dart:typed_data';

/// Parsed representation of events received from the Qwen Omni Realtime
/// WebSocket API.
///
/// The API follows an OpenAI-compatible protocol where each message is a
/// JSON object with a `type` field that determines the event kind.
sealed class QwenRealtimeEvent {
  const QwenRealtimeEvent();

  /// Parses a raw JSON string from the WebSocket into a typed event.
  ///
  /// Returns [QwenUnknownEvent] for unrecognized event types so the
  /// caller can log them without crashing.
  factory QwenRealtimeEvent.fromJson(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final type = json['type'] as String? ?? '';

    return switch (type) {
      'session.created' => QwenSessionCreated._(json),
      'session.updated' => QwenSessionUpdated._(json),
      'response.text.delta' => QwenTextDelta._(json),
      'response.text.done' => QwenTextDone._(json),
      'response.audio.delta' => QwenAudioDelta._(json),
      'response.audio.done' => const QwenAudioDone._(),
      'response.function_call_arguments.delta' =>
        QwenFunctionCallArgumentsDelta._(json),
      'response.function_call_arguments.done' =>
        QwenFunctionCallArgumentsDone._(json),
      'response.done' => QwenResponseDone._(json),
      'input_audio_buffer.speech_started' => const QwenSpeechStarted._(),
      'input_audio_buffer.speech_stopped' => const QwenSpeechStopped._(),
      'input_audio_buffer.committed' => const QwenBufferCommitted._(),
      'error' => QwenError._(json),
      _ => QwenUnknownEvent._(type, json),
    };
  }
}

/// The server acknowledged the WebSocket connection and created a session.
class QwenSessionCreated extends QwenRealtimeEvent {
  final String sessionId;

  QwenSessionCreated._(Map<String, dynamic> json)
      : sessionId = (json['session'] as Map<String, dynamic>?)?['id']
            as String? ??
            '';
}

/// Confirmation that a `session.update` request was applied.
class QwenSessionUpdated extends QwenRealtimeEvent {
  final Map<String, dynamic> session;

  QwenSessionUpdated._(Map<String, dynamic> json)
      : session = json['session'] as Map<String, dynamic>? ?? {};
}

/// Incremental text fragment from the model's response.
class QwenTextDelta extends QwenRealtimeEvent {
  final String delta;

  QwenTextDelta._(Map<String, dynamic> json)
      : delta = json['delta'] as String? ?? '';
}

/// Final complete text from the model's response turn.
class QwenTextDone extends QwenRealtimeEvent {
  final String text;

  QwenTextDone._(Map<String, dynamic> json)
      : text = json['text'] as String? ?? '';
}

/// Base64-encoded PCM audio chunk from the model's response.
class QwenAudioDelta extends QwenRealtimeEvent {
  final Uint8List audio;

  QwenAudioDelta._(Map<String, dynamic> json)
      : audio = base64Decode(json['delta'] as String? ?? '');
}

/// Signals the end of the audio stream for the current response.
class QwenAudioDone extends QwenRealtimeEvent {
  const QwenAudioDone._();
}

/// Incremental function call arguments (partial JSON string).
class QwenFunctionCallArgumentsDelta extends QwenRealtimeEvent {
  final String delta;

  QwenFunctionCallArgumentsDelta._(Map<String, dynamic> json)
      : delta = json['delta'] as String? ?? '';
}

/// Complete function call with final arguments, ready for execution.
class QwenFunctionCallArgumentsDone extends QwenRealtimeEvent {
  final String callId;
  final String name;
  final String arguments;

  QwenFunctionCallArgumentsDone._(Map<String, dynamic> json)
      : callId = json['call_id'] as String? ?? '',
        name = json['name'] as String? ?? '',
        arguments = json['arguments'] as String? ?? '{}';
}

/// The full response turn is complete (may contain multiple output items).
class QwenResponseDone extends QwenRealtimeEvent {
  final Map<String, dynamic> response;

  QwenResponseDone._(Map<String, dynamic> json)
      : response = json['response'] as Map<String, dynamic>? ?? {};
}

/// Server-side VAD detected the start of user speech.
class QwenSpeechStarted extends QwenRealtimeEvent {
  const QwenSpeechStarted._();
}

/// Server-side VAD detected the end of user speech.
class QwenSpeechStopped extends QwenRealtimeEvent {
  const QwenSpeechStopped._();
}

/// Confirmation that the input audio buffer was committed.
class QwenBufferCommitted extends QwenRealtimeEvent {
  const QwenBufferCommitted._();
}

/// Error reported by the Qwen Realtime API.
class QwenError extends QwenRealtimeEvent {
  final String message;
  final String? code;

  QwenError._(Map<String, dynamic> json)
      : message = (json['error'] as Map<String, dynamic>?)?['message']
            as String? ??
            'Unknown error',
        code = (json['error'] as Map<String, dynamic>?)?['code'] as String?;
}

/// Unrecognized event type — logged for debugging but not acted upon.
class QwenUnknownEvent extends QwenRealtimeEvent {
  final String type;
  final Map<String, dynamic> raw;

  const QwenUnknownEvent._(this.type, this.raw);
}

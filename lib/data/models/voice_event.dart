import 'dart:typed_data';

/// Events emitted by a [RealtimeVoiceService] through its event stream.
///
/// Each subclass represents a distinct event type received from the
/// Realtime WebSocket API during a voice session.
sealed class VoiceEvent {
  const VoiceEvent();
}

/// Incremental text response fragment from the model.
class TextDelta extends VoiceEvent {
  final String text;
  const TextDelta(this.text);

  @override
  String toString() => 'TextDelta(text: $text)';
}

/// Complete text response from the model.
class TextDone extends VoiceEvent {
  final String text;
  const TextDone(this.text);

  @override
  String toString() => 'TextDone(text: $text)';
}

/// Incremental audio response chunk from the model.
class AudioDelta extends VoiceEvent {
  final Uint8List audio;
  const AudioDelta(this.audio);

  @override
  String toString() => 'AudioDelta(bytes: ${audio.length})';
}

/// Signals the end of the current audio response stream.
class AudioDone extends VoiceEvent {
  const AudioDone();

  @override
  String toString() => 'AudioDone()';
}

/// Function calling request from the model.
///
/// The service consumer should execute the requested tool and return
/// the result via [RealtimeVoiceService.sendToolResult].
class ToolCallRequest extends VoiceEvent {
  final String callId;
  final String name;
  final Map<String, dynamic> arguments;

  const ToolCallRequest({
    required this.callId,
    required this.name,
    required this.arguments,
  });

  @override
  String toString() => 'ToolCallRequest(callId: $callId, name: $name)';
}

/// Confirmation that a voice session has been established.
class SessionCreated extends VoiceEvent {
  final String sessionId;
  const SessionCreated(this.sessionId);

  @override
  String toString() => 'SessionCreated(sessionId: $sessionId)';
}

/// Error reported by the Realtime API or the WebSocket transport.
class VoiceError extends VoiceEvent {
  final String message;
  final int? code;

  const VoiceError(this.message, {this.code});

  @override
  String toString() => 'VoiceError(message: $message, code: $code)';
}

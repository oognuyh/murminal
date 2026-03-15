import 'dart:convert';
import 'dart:typed_data';

/// Parsed representation of events received from the Gemini Live
/// WebSocket API (BidiGenerateContent).
///
/// The Gemini protocol uses a different message format from the
/// OpenAI-compatible protocol used by Qwen. Messages are JSON
/// objects whose top-level keys determine the event kind:
/// - `setupComplete` — session established
/// - `serverContent` — model turn with text/audio parts
/// - `toolCall` — function calling request
sealed class GeminiRealtimeEvent {
  const GeminiRealtimeEvent();

  /// Parses a raw JSON string from the WebSocket into a typed event.
  factory GeminiRealtimeEvent.fromJson(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;

    if (json.containsKey('setupComplete')) {
      return const GeminiSetupComplete._();
    }

    if (json.containsKey('toolCall')) {
      return GeminiToolCall._(json['toolCall'] as Map<String, dynamic>);
    }

    if (json.containsKey('serverContent')) {
      return _parseServerContent(
        json['serverContent'] as Map<String, dynamic>,
      );
    }

    return GeminiUnknownEvent._(json);
  }

  static GeminiRealtimeEvent _parseServerContent(Map<String, dynamic> sc) {
    final turnComplete = sc['turnComplete'] as bool? ?? false;

    final modelTurn = sc['modelTurn'] as Map<String, dynamic>?;
    if (modelTurn == null) {
      if (turnComplete) return const GeminiTurnComplete._();
      // Interrupted — model output was cut off by user speech.
      if (sc['interrupted'] == true) return const GeminiInterrupted._();
      return const GeminiTurnComplete._();
    }

    final parts = modelTurn['parts'] as List<dynamic>? ?? [];
    final events = <GeminiRealtimeEvent>[];

    for (final part in parts) {
      if (part is! Map<String, dynamic>) continue;

      // Audio part
      final inlineData = part['inlineData'] as Map<String, dynamic>?;
      if (inlineData != null) {
        final data = inlineData['data'] as String?;
        if (data != null && data.isNotEmpty) {
          events.add(GeminiAudioChunk._(base64Decode(data)));
        }
        continue;
      }

      // Text part
      final text = part['text'] as String?;
      if (text != null) {
        events.add(GeminiTextChunk._(text));
      }
    }

    if (events.isEmpty && turnComplete) {
      return const GeminiTurnComplete._();
    }
    if (events.length == 1 && !turnComplete) {
      return events.first;
    }

    return GeminiServerContent._(events, turnComplete: turnComplete);
  }
}

/// The server acknowledged the setup message and is ready.
class GeminiSetupComplete extends GeminiRealtimeEvent {
  const GeminiSetupComplete._();
}

/// A batch of content parts from the model, possibly including
/// multiple audio/text chunks and a turn-complete flag.
class GeminiServerContent extends GeminiRealtimeEvent {
  final List<GeminiRealtimeEvent> parts;
  final bool turnComplete;

  const GeminiServerContent._(this.parts, {this.turnComplete = false});
}

/// Incremental text from the model.
class GeminiTextChunk extends GeminiRealtimeEvent {
  final String text;
  const GeminiTextChunk._(this.text);
}

/// Base64-decoded PCM audio chunk from the model (24kHz).
class GeminiAudioChunk extends GeminiRealtimeEvent {
  final Uint8List audio;
  const GeminiAudioChunk._(this.audio);
}

/// The model's turn is complete.
class GeminiTurnComplete extends GeminiRealtimeEvent {
  const GeminiTurnComplete._();
}

/// The model's output was interrupted by user speech.
class GeminiInterrupted extends GeminiRealtimeEvent {
  const GeminiInterrupted._();
}

/// Function calling request from the model.
class GeminiToolCall extends GeminiRealtimeEvent {
  final List<GeminiFunctionCall> functionCalls;

  GeminiToolCall._(Map<String, dynamic> json)
      : functionCalls = (json['functionCalls'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(GeminiFunctionCall._)
            .toList();
}

/// A single function call within a [GeminiToolCall].
class GeminiFunctionCall {
  final String id;
  final String name;
  final Map<String, dynamic> args;

  GeminiFunctionCall._(Map<String, dynamic> json)
      : id = json['id'] as String? ?? '',
        name = json['name'] as String? ?? '',
        args = json['args'] as Map<String, dynamic>? ?? {};
}

/// Unrecognized event.
class GeminiUnknownEvent extends GeminiRealtimeEvent {
  final Map<String, dynamic> raw;
  const GeminiUnknownEvent._(this.raw);
}

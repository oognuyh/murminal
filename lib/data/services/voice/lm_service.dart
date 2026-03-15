import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

/// Abstract text-in/text-out language model service.
///
/// Implementations wrap specific LM provider HTTP APIs (Claude, OpenAI, Gemini)
/// and expose a unified interface for sending messages and receiving text
/// completions. Used by [LocalVoiceService] to process transcribed speech.
///
/// Usage:
/// ```dart
/// final lm = ClaudeLmService();
/// lm.configure(apiKey: 'sk-...', model: 'claude-sonnet-4-20250514');
/// final response = await lm.complete(
///   systemPrompt: 'You are a terminal supervisor.',
///   messages: [LmMessage.user('list my sessions')],
/// );
/// print(response); // "Here are your active sessions..."
/// ```
abstract class LmService {
  /// Configures the service with authentication and model settings.
  void configure({required String apiKey, String? model});

  /// Sends a conversation to the LM and returns the text response.
  ///
  /// [systemPrompt] sets the system-level instruction context.
  /// [messages] is the conversation history in chronological order.
  /// [tools] optionally declares function calling schemas.
  Future<LmResponse> complete({
    required String systemPrompt,
    required List<LmMessage> messages,
    List<LmTool>? tools,
  });

  /// Provider display name for UI and logging.
  String get providerName;
}

/// A message in the LM conversation history.
class LmMessage {
  /// Role of the message sender.
  final LmRole role;

  /// Text content of the message.
  final String content;

  /// Optional tool call ID for tool result messages.
  final String? toolCallId;

  /// Optional tool name for tool result messages.
  final String? toolName;

  const LmMessage({
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolName,
  });

  /// Convenience factory for user messages.
  factory LmMessage.user(String content) =>
      LmMessage(role: LmRole.user, content: content);

  /// Convenience factory for assistant messages.
  factory LmMessage.assistant(String content) =>
      LmMessage(role: LmRole.assistant, content: content);

  /// Convenience factory for tool result messages.
  factory LmMessage.toolResult({
    required String callId,
    required String name,
    required String content,
  }) =>
      LmMessage(
        role: LmRole.tool,
        content: content,
        toolCallId: callId,
        toolName: name,
      );
}

/// Roles in an LM conversation.
enum LmRole { user, assistant, tool }

/// A tool declaration for the LM function calling.
class LmTool {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  const LmTool({
    required this.name,
    required this.description,
    required this.parameters,
  });
}

/// Response from the LM service.
class LmResponse {
  /// The text response from the model.
  final String text;

  /// Optional tool calls requested by the model.
  final List<LmToolCall> toolCalls;

  const LmResponse({required this.text, this.toolCalls = const []});

  /// Whether the response contains tool calls.
  bool get hasToolCalls => toolCalls.isNotEmpty;
}

/// A tool call requested by the model.
class LmToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  const LmToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
}

// ---------------------------------------------------------------------------
// Claude (Anthropic API) implementation
// ---------------------------------------------------------------------------

/// LM service implementation for the Anthropic Claude API.
///
/// Uses the Messages API endpoint to send text conversations and
/// receive text completions. Supports function calling via tool_use.
class ClaudeLmService extends LmService {
  static const _tag = 'ClaudeLmService';
  static const _defaultModel = 'claude-sonnet-4-20250514';
  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  String? _apiKey;
  String _model = _defaultModel;

  @override
  String get providerName => 'Claude';

  @override
  void configure({required String apiKey, String? model}) {
    _apiKey = apiKey;
    if (model != null) _model = model;
  }

  @override
  Future<LmResponse> complete({
    required String systemPrompt,
    required List<LmMessage> messages,
    List<LmTool>? tools,
  }) async {
    if (_apiKey == null) {
      throw StateError('Claude API key not configured');
    }

    final body = <String, dynamic>{
      'model': _model,
      'max_tokens': 1024,
      'system': systemPrompt,
      'messages': messages.map(_encodeClaudeMessage).toList(),
    };

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools
          .map((t) => {
                'name': t.name,
                'description': t.description,
                'input_schema': t.parameters,
              })
          .toList();
    }

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(_endpoint));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('x-api-key', _apiKey!);
      request.headers.set('anthropic-version', '2023-06-01');
      request.add(utf8.encode(jsonEncode(body)));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        developer.log(
          'Claude API error ${response.statusCode}: $responseBody',
          name: _tag,
        );
        throw HttpException(
          'Claude API error: ${response.statusCode}',
          uri: Uri.parse(_endpoint),
        );
      }

      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      return _parseClaudeResponse(json);
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _encodeClaudeMessage(LmMessage msg) {
    if (msg.role == LmRole.tool) {
      return {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': msg.toolCallId,
            'content': msg.content,
          }
        ],
      };
    }
    return {
      'role': msg.role == LmRole.user ? 'user' : 'assistant',
      'content': msg.content,
    };
  }

  LmResponse _parseClaudeResponse(Map<String, dynamic> json) {
    final content = json['content'] as List<dynamic>? ?? [];
    final textParts = <String>[];
    final toolCalls = <LmToolCall>[];

    for (final block in content) {
      final blockMap = block as Map<String, dynamic>;
      if (blockMap['type'] == 'text') {
        textParts.add(blockMap['text'] as String);
      } else if (blockMap['type'] == 'tool_use') {
        toolCalls.add(LmToolCall(
          id: blockMap['id'] as String,
          name: blockMap['name'] as String,
          arguments: blockMap['input'] as Map<String, dynamic>,
        ));
      }
    }

    return LmResponse(text: textParts.join(), toolCalls: toolCalls);
  }
}

// ---------------------------------------------------------------------------
// OpenAI (Chat Completions API) implementation
// ---------------------------------------------------------------------------

/// LM service implementation for the OpenAI Chat Completions API.
///
/// Compatible with GPT-4, GPT-4o, and other OpenAI chat models.
/// Supports function calling via the tools parameter.
class OpenAiLmService extends LmService {
  static const _tag = 'OpenAiLmService';
  static const _defaultModel = 'gpt-4o';
  static const _endpoint = 'https://api.openai.com/v1/chat/completions';

  String? _apiKey;
  String _model = _defaultModel;

  @override
  String get providerName => 'OpenAI';

  @override
  void configure({required String apiKey, String? model}) {
    _apiKey = apiKey;
    if (model != null) _model = model;
  }

  @override
  Future<LmResponse> complete({
    required String systemPrompt,
    required List<LmMessage> messages,
    List<LmTool>? tools,
  }) async {
    if (_apiKey == null) {
      throw StateError('OpenAI API key not configured');
    }

    final openAiMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      ...messages.map(_encodeOpenAiMessage),
    ];

    final body = <String, dynamic>{
      'model': _model,
      'messages': openAiMessages,
    };

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools
          .map((t) => {
                'type': 'function',
                'function': {
                  'name': t.name,
                  'description': t.description,
                  'parameters': t.parameters,
                },
              })
          .toList();
    }

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(_endpoint));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Authorization', 'Bearer $_apiKey');
      request.add(utf8.encode(jsonEncode(body)));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        developer.log(
          'OpenAI API error ${response.statusCode}: $responseBody',
          name: _tag,
        );
        throw HttpException(
          'OpenAI API error: ${response.statusCode}',
          uri: Uri.parse(_endpoint),
        );
      }

      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      return _parseOpenAiResponse(json);
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _encodeOpenAiMessage(LmMessage msg) {
    if (msg.role == LmRole.tool) {
      return {
        'role': 'tool',
        'tool_call_id': msg.toolCallId,
        'content': msg.content,
      };
    }
    return {
      'role': msg.role == LmRole.user ? 'user' : 'assistant',
      'content': msg.content,
    };
  }

  LmResponse _parseOpenAiResponse(Map<String, dynamic> json) {
    final choices = json['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) return const LmResponse(text: '');

    final message =
        (choices[0] as Map<String, dynamic>)['message'] as Map<String, dynamic>;
    final content = message['content'] as String? ?? '';
    final toolCallsJson = message['tool_calls'] as List<dynamic>?;
    final toolCalls = <LmToolCall>[];

    if (toolCallsJson != null) {
      for (final tc in toolCallsJson) {
        final tcMap = tc as Map<String, dynamic>;
        final fn = tcMap['function'] as Map<String, dynamic>;
        toolCalls.add(LmToolCall(
          id: tcMap['id'] as String,
          name: fn['name'] as String,
          arguments: _tryDecodeJson(fn['arguments'] as String),
        ));
      }
    }

    return LmResponse(text: content, toolCalls: toolCalls);
  }

  Map<String, dynamic> _tryDecodeJson(String source) {
    try {
      return jsonDecode(source) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}

// ---------------------------------------------------------------------------
// Gemini (generateContent API) implementation
// ---------------------------------------------------------------------------

/// LM service implementation for the Google Gemini generateContent API.
///
/// Uses the REST API for text-only completions (not the Realtime/Live API).
/// Supports function calling via the tools parameter.
class GeminiLmService extends LmService {
  static const _tag = 'GeminiLmService';
  static const _defaultModel = 'gemini-2.0-flash';
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  String? _apiKey;
  String _model = _defaultModel;

  @override
  String get providerName => 'Gemini';

  @override
  void configure({required String apiKey, String? model}) {
    _apiKey = apiKey;
    if (model != null) _model = model;
  }

  @override
  Future<LmResponse> complete({
    required String systemPrompt,
    required List<LmMessage> messages,
    List<LmTool>? tools,
  }) async {
    if (_apiKey == null) {
      throw StateError('Gemini API key not configured');
    }

    final endpoint = '$_baseUrl/$_model:generateContent?key=$_apiKey';

    final body = <String, dynamic>{
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt},
        ],
      },
      'contents': messages.map(_encodeGeminiMessage).toList(),
    };

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = [
        {
          'functionDeclarations': tools
              .map((t) => {
                    'name': t.name,
                    'description': t.description,
                    'parameters': t.parameters,
                  })
              .toList(),
        },
      ];
    }

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.set('Content-Type', 'application/json');
      request.add(utf8.encode(jsonEncode(body)));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        developer.log(
          'Gemini API error ${response.statusCode}: $responseBody',
          name: _tag,
        );
        throw HttpException(
          'Gemini API error: ${response.statusCode}',
          uri: Uri.parse(endpoint),
        );
      }

      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      return _parseGeminiResponse(json);
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _encodeGeminiMessage(LmMessage msg) {
    return {
      'role': msg.role == LmRole.assistant ? 'model' : 'user',
      'parts': [
        {'text': msg.content},
      ],
    };
  }

  LmResponse _parseGeminiResponse(Map<String, dynamic> json) {
    final candidates = json['candidates'] as List<dynamic>? ?? [];
    if (candidates.isEmpty) return const LmResponse(text: '');

    final content = (candidates[0] as Map<String, dynamic>)['content']
        as Map<String, dynamic>?;
    if (content == null) return const LmResponse(text: '');

    final parts = content['parts'] as List<dynamic>? ?? [];
    final textParts = <String>[];
    final toolCalls = <LmToolCall>[];

    for (final part in parts) {
      final partMap = part as Map<String, dynamic>;
      if (partMap.containsKey('text')) {
        textParts.add(partMap['text'] as String);
      } else if (partMap.containsKey('functionCall')) {
        final fc = partMap['functionCall'] as Map<String, dynamic>;
        toolCalls.add(LmToolCall(
          id: fc['name'] as String, // Gemini uses name as ID
          name: fc['name'] as String,
          arguments: fc['args'] as Map<String, dynamic>? ?? {},
        ));
      }
    }

    return LmResponse(text: textParts.join(), toolCalls: toolCalls);
  }
}

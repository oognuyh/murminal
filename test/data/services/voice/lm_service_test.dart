import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/services/voice/lm_service.dart';

void main() {
  group('LmMessage', () {
    test('user factory creates user role message', () {
      final msg = LmMessage.user('hello');
      expect(msg.role, LmRole.user);
      expect(msg.content, 'hello');
      expect(msg.toolCallId, isNull);
    });

    test('assistant factory creates assistant role message', () {
      final msg = LmMessage.assistant('hi there');
      expect(msg.role, LmRole.assistant);
      expect(msg.content, 'hi there');
    });

    test('toolResult factory creates tool role message', () {
      final msg = LmMessage.toolResult(
        callId: 'call_123',
        name: 'get_status',
        content: '{"status": "ok"}',
      );
      expect(msg.role, LmRole.tool);
      expect(msg.content, '{"status": "ok"}');
      expect(msg.toolCallId, 'call_123');
      expect(msg.toolName, 'get_status');
    });
  });

  group('LmResponse', () {
    test('hasToolCalls returns false when empty', () {
      const response = LmResponse(text: 'hello');
      expect(response.hasToolCalls, isFalse);
    });

    test('hasToolCalls returns true when tool calls present', () {
      const response = LmResponse(
        text: '',
        toolCalls: [
          LmToolCall(id: '1', name: 'test', arguments: {}),
        ],
      );
      expect(response.hasToolCalls, isTrue);
    });
  });

  group('ClaudeLmService', () {
    test('configure stores API key and model', () {
      final service = ClaudeLmService();
      expect(service.providerName, 'Claude');
      // configure should not throw.
      service.configure(apiKey: 'test-key', model: 'claude-sonnet-4-20250514');
    });

    test('complete throws when API key not configured', () {
      final service = ClaudeLmService();
      expect(
        () => service.complete(
          systemPrompt: 'test',
          messages: [LmMessage.user('hello')],
        ),
        throwsStateError,
      );
    });
  });

  group('OpenAiLmService', () {
    test('configure stores API key and model', () {
      final service = OpenAiLmService();
      expect(service.providerName, 'OpenAI');
      service.configure(apiKey: 'test-key', model: 'gpt-4o');
    });

    test('complete throws when API key not configured', () {
      final service = OpenAiLmService();
      expect(
        () => service.complete(
          systemPrompt: 'test',
          messages: [LmMessage.user('hello')],
        ),
        throwsStateError,
      );
    });
  });

  group('GeminiLmService', () {
    test('configure stores API key and model', () {
      final service = GeminiLmService();
      expect(service.providerName, 'Gemini');
      service.configure(apiKey: 'test-key', model: 'gemini-2.0-flash');
    });

    test('complete throws when API key not configured', () {
      final service = GeminiLmService();
      expect(
        () => service.complete(
          systemPrompt: 'test',
          messages: [LmMessage.user('hello')],
        ),
        throwsStateError,
      );
    });
  });
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/tool_definition.dart';
import 'package:murminal/data/models/voice_event.dart';
import 'package:murminal/data/services/voice/lm_service.dart';
import 'package:murminal/data/services/voice/local_voice_service.dart';
import 'package:murminal/data/services/voice/stt_service.dart';
import 'package:murminal/data/services/voice/tts_service.dart';

// ---------------------------------------------------------------------------
// Manual mocks
// ---------------------------------------------------------------------------

/// Mock STT service that does not use platform channels.
///
/// We cannot extend SttService because its constructor registers a
/// platform method call handler which requires WidgetsFlutterBinding.
/// Instead we implement the same interface manually.
class MockSttService implements SttService {
  final _transcriptController = StreamController<SttResult>.broadcast();
  bool startCalled = false;
  bool stopCalled = false;
  String? lastLocale;

  @override
  Stream<SttResult> get transcripts => _transcriptController.stream;

  @override
  bool get isListening => startCalled && !stopCalled;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> supportsOnDevice() async => true;

  @override
  Future<void> startListening({String locale = 'en-US'}) async {
    startCalled = true;
    lastLocale = locale;
  }

  @override
  Future<void> stopListening() async {
    stopCalled = true;
  }

  /// Simulates a transcription result from the native STT engine.
  void emitTranscript(String text, {bool isFinal = false}) {
    _transcriptController.add(SttResult(text: text, isFinal: isFinal));
  }

  @override
  void dispose() {
    _transcriptController.close();
  }
}

class MockTtsService implements TtsService {
  final _eventController = StreamController<TtsEvent>.broadcast();
  final List<String> spokenTexts = [];
  bool stopCalled = false;

  @override
  Stream<TtsEvent> get events => _eventController.stream;

  @override
  bool get isSpeaking => false;

  @override
  Future<void> speak(
    String text, {
    String language = 'en-US',
    double rate = 0.5,
    double pitch = 1.0,
    double volume = 1.0,
  }) async {
    spokenTexts.add(text);
    _eventController.add(TtsEvent.started);
    // Simulate immediate completion for testing.
    _eventController.add(TtsEvent.finished);
  }

  @override
  Future<void> stop() async {
    stopCalled = true;
  }

  @override
  Future<List<TtsVoice>> getVoices() async => [];

  @override
  void dispose() {
    _eventController.close();
  }
}

class MockLmService extends LmService {
  String? lastSystemPrompt;
  List<LmMessage>? lastMessages;
  LmResponse nextResponse = const LmResponse(text: 'Mock response');
  bool configureCalled = false;

  @override
  String get providerName => 'MockLM';

  @override
  void configure({required String apiKey, String? model}) {
    configureCalled = true;
  }

  @override
  Future<LmResponse> complete({
    required String systemPrompt,
    required List<LmMessage> messages,
    List<LmTool>? tools,
  }) async {
    lastSystemPrompt = systemPrompt;
    lastMessages = messages;
    return nextResponse;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockSttService stt;
  late MockTtsService tts;
  late MockLmService lm;
  late LocalVoiceService service;

  setUpAll(() {
    WidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    stt = MockSttService();
    tts = MockTtsService();
    lm = MockLmService();
    service = LocalVoiceService(stt: stt, tts: tts, lm: lm);
  });

  tearDown(() {
    service.dispose();
  });

  group('LocalVoiceService', () {
    test('connect configures LM and emits SessionCreated', () async {
      final events = <VoiceEvent>[];
      service.events.listen(events.add);

      await service.connect('test-key', tools: []);

      expect(service.isConnected, isTrue);
      expect(lm.configureCalled, isTrue);
      expect(events, hasLength(1));
      expect(events.first, isA<SessionCreated>());
    });

    test('disconnect stops listening and clears state', () async {
      await service.connect('test-key');
      await service.disconnect();

      expect(service.isConnected, isFalse);
    });

    test('startListening delegates to STT service', () async {
      await service.connect('test-key');
      await service.startListening(locale: 'ko-KR');

      expect(stt.startCalled, isTrue);
      expect(stt.lastLocale, 'ko-KR');
    });

    test('final transcript triggers LM completion and TTS', () async {
      lm.nextResponse = const LmResponse(text: 'Session is running');

      await service.connect('test-key');

      // Wait for events to be processed.
      final events = <VoiceEvent>[];
      service.events.listen(events.add);

      // Allow subscriptions to settle.
      await Future<void>.delayed(Duration.zero);

      // Simulate a final STT result.
      stt.emitTranscript('check my sessions', isFinal: true);

      // Allow async processing.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // LM should have been called with the transcribed text.
      expect(lm.lastMessages, isNotNull);
      // The first message in the conversation should be the user's.
      final userMessages = lm.lastMessages!
          .where((m) => m.role == LmRole.user)
          .toList();
      expect(userMessages, isNotEmpty);
      expect(userMessages.first.content, 'check my sessions');

      // TTS should have spoken the response.
      expect(tts.spokenTexts, contains('Session is running'));
    });

    test('partial transcript emits TextDelta but does not call LM', () async {
      await service.connect('test-key');

      final events = <VoiceEvent>[];
      service.events.listen(events.add);

      await Future<void>.delayed(Duration.zero);

      stt.emitTranscript('check', isFinal: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Should emit TextDelta but not call LM.
      expect(events.whereType<TextDelta>(), hasLength(1));
      expect(lm.lastMessages, isNull);
    });

    test('tool call response emits ToolCallRequest', () async {
      lm.nextResponse = const LmResponse(
        text: '',
        toolCalls: [
          LmToolCall(
            id: 'call_1',
            name: 'list_sessions',
            arguments: {},
          ),
        ],
      );

      await service.connect('test-key');

      final events = <VoiceEvent>[];
      service.events.listen(events.add);

      await Future<void>.delayed(Duration.zero);

      stt.emitTranscript('list sessions', isFinal: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final toolCalls = events.whereType<ToolCallRequest>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.name, 'list_sessions');
      expect(toolCalls.first.callId, 'call_1');
    });

    test('sendToolResult adds to history and triggers LM', () async {
      lm.nextResponse = const LmResponse(text: 'Here are your sessions');

      await service.connect('test-key');
      await service.sendToolResult('call_1', '{"sessions": []}');

      expect(lm.lastMessages, isNotNull);
      expect(tts.spokenTexts, contains('Here are your sessions'));
    });

    test('injectTextReport sends to LM and speaks', () async {
      lm.nextResponse =
          const LmResponse(text: 'Build complete in session dev');

      await service.connect('test-key');
      await service.injectTextReport('[REPORT] Build completed');

      // The report should appear as a user message in history.
      final userMessages = lm.lastMessages!
          .where((m) => m.role == LmRole.user)
          .toList();
      expect(userMessages, isNotEmpty);
      expect(userMessages.last.content, '[REPORT] Build completed');

      // TTS should have spoken the LM response.
      expect(
        tts.spokenTexts,
        contains('Build complete in session dev'),
      );
    });

    test('updateSystemPrompt stores prompt', () async {
      await service.connect('test-key');
      await service.updateSystemPrompt('You are a test supervisor.');

      // Trigger LM to verify the prompt is used.
      stt.emitTranscript('hello', isFinal: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(lm.lastSystemPrompt, 'You are a test supervisor.');
    });

    test('LM error emits VoiceError event', () async {
      final errorLm = _ErrorLmService();
      final errorService =
          LocalVoiceService(stt: stt, tts: tts, lm: errorLm);

      await errorService.connect('test-key');

      final events = <VoiceEvent>[];
      errorService.events.listen(events.add);

      await Future<void>.delayed(Duration.zero);

      stt.emitTranscript('fail', isFinal: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final errors = events.whereType<VoiceError>().toList();
      expect(errors, isNotEmpty);
      expect(errors.first.message, contains('LM error'));

      errorService.dispose();
    });
  });
}

/// LM service that always throws for error testing.
class _ErrorLmService extends LmService {
  @override
  String get providerName => 'ErrorLM';

  @override
  void configure({required String apiKey, String? model}) {}

  @override
  Future<LmResponse> complete({
    required String systemPrompt,
    required List<LmMessage> messages,
    List<LmTool>? tools,
  }) async {
    throw Exception('Simulated LM failure');
  }
}

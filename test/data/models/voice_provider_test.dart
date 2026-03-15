import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/voice_provider.dart';

void main() {
  group('VoiceProvider', () {
    test('isLocal returns true for local providers', () {
      expect(VoiceProvider.localClaude.isLocal, isTrue);
      expect(VoiceProvider.localOpenai.isLocal, isTrue);
      expect(VoiceProvider.localGemini.isLocal, isTrue);
    });

    test('isLocal returns false for realtime providers', () {
      expect(VoiceProvider.qwen.isLocal, isFalse);
      expect(VoiceProvider.gemini.isLocal, isFalse);
      expect(VoiceProvider.openai.isLocal, isFalse);
    });

    test('isRealtime is inverse of isLocal', () {
      for (final provider in VoiceProvider.values) {
        expect(provider.isRealtime, !provider.isLocal);
      }
    });

    test('displayName returns non-empty string for all providers', () {
      for (final provider in VoiceProvider.values) {
        expect(provider.displayName, isNotEmpty);
      }
    });

    test('shortLabel returns non-empty string for all providers', () {
      for (final provider in VoiceProvider.values) {
        expect(provider.shortLabel, isNotEmpty);
      }
    });

    test('storageKey is unique for each provider', () {
      final keys = VoiceProvider.values.map((p) => p.storageKey).toSet();
      expect(keys.length, VoiceProvider.values.length);
    });

    test('realtime providers have non-empty baseUrl', () {
      for (final provider in VoiceProvider.values.where((p) => p.isRealtime)) {
        expect(provider.baseUrl, isNotEmpty);
      }
    });

    test('local providers have empty baseUrl', () {
      for (final provider in VoiceProvider.values.where((p) => p.isLocal)) {
        expect(provider.baseUrl, isEmpty);
      }
    });

    test('categoryLabel groups correctly', () {
      expect(VoiceProvider.qwen.categoryLabel, 'Realtime (Premium)');
      expect(VoiceProvider.localClaude.categoryLabel, 'On-Device Voice');
    });
  });
}

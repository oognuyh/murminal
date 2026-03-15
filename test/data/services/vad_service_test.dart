import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/vad_config.dart';
import 'package:murminal/data/models/vad_event.dart';
import 'package:murminal/data/services/voice/vad_service.dart';

/// Generates a PCM audio chunk containing a sine wave at the given amplitude.
///
/// [samples] is the number of 16-bit samples to generate.
/// [amplitude] is in the range [0, 32767].
Uint8List _generateTone(int samples, {int amplitude = 16000}) {
  final bytes = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    // Simple square wave toggling between +amplitude and -amplitude.
    final value = (i % 2 == 0) ? amplitude : -amplitude;
    bytes.setInt16(i * 2, value, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// Generates a PCM audio chunk of silence (all zeros).
Uint8List _generateSilence(int samples) {
  return Uint8List(samples * 2); // 16-bit zeros
}

void main() {
  group('VadService', () {
    late VadService vad;

    // Use a fast config for testing: small frames and short silence threshold.
    const testConfig = VadConfig(
      frameSamples: 64,
      sampleRate: 16000,
      silenceThreshold: Duration(milliseconds: 50),
      energyThreshold: 0.01,
      minSpeechFrames: 2,
    );

    setUp(() {
      vad = VadService(config: testConfig);
    });

    tearDown(() {
      vad.dispose();
    });

    group('initialization', () {
      test('starts in non-speech state', () {
        expect(vad.isSpeechActive, isFalse);
      });

      test('exposes the provided config', () {
        expect(vad.config.frameSamples, 64);
        expect(vad.config.silenceThreshold,
            const Duration(milliseconds: 50));
      });

      test('uses default config when none provided', () {
        final defaultVad = VadService();
        expect(defaultVad.config.sampleRate, 16000);
        expect(defaultVad.config.frameSamples, 512);
        expect(defaultVad.config.silenceThreshold,
            const Duration(milliseconds: 1500));
        defaultVad.dispose();
      });
    });

    group('speech detection', () {
      test('emits SpeechStart after minSpeechFrames of loud audio', () async {
        final events = <VadEvent>[];
        vad.events.listen(events.add);

        // Feed enough loud frames to exceed minSpeechFrames (2).
        final loudChunk = _generateTone(
          testConfig.frameSamples * 3,
          amplitude: 8000,
        );
        vad.processAudioChunk(loudChunk);

        // Allow the stream to deliver events.
        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events.first, isA<SpeechStart>());
        expect(vad.isSpeechActive, isTrue);
      });

      test('does not emit SpeechStart for single loud frame', () async {
        final events = <VadEvent>[];
        vad.events.listen(events.add);

        // Only one frame of audio, below minSpeechFrames threshold.
        final singleFrame = _generateTone(testConfig.frameSamples,
            amplitude: 8000);
        vad.processAudioChunk(singleFrame);

        await Future<void>.delayed(Duration.zero);

        expect(events, isEmpty);
        expect(vad.isSpeechActive, isFalse);
      });

      test('does not emit SpeechStart for quiet audio', () async {
        final events = <VadEvent>[];
        vad.events.listen(events.add);

        // Very low amplitude, below energyThreshold.
        final quietChunk = _generateTone(
          testConfig.frameSamples * 5,
          amplitude: 50,
        );
        vad.processAudioChunk(quietChunk);

        await Future<void>.delayed(Duration.zero);

        expect(events, isEmpty);
        expect(vad.isSpeechActive, isFalse);
      });
    });

    group('silence detection', () {
      test('emits SpeechEnd after silence threshold', () async {
        final events = <VadEvent>[];
        vad.events.listen(events.add);

        // Trigger speech start first.
        final loudChunk = _generateTone(
          testConfig.frameSamples * 3,
          amplitude: 8000,
        );
        vad.processAudioChunk(loudChunk);

        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(1));
        expect(events.first, isA<SpeechStart>());

        // Now feed enough silence to exceed the silence threshold.
        // silenceThreshold = 50ms, frameDuration = 64/16000 = 4ms
        // Need 50/4 = ~13 silent frames.
        final silenceChunk = _generateSilence(testConfig.frameSamples * 20);
        vad.processAudioChunk(silenceChunk);

        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(2));
        expect(events[1], isA<SpeechEnd>());
        final endEvent = events[1] as SpeechEnd;
        expect(endEvent.speechDuration, isNotNull);
        expect(vad.isSpeechActive, isFalse);
      });

      test('does not emit SpeechEnd for brief silence during speech',
          () async {
        final events = <VadEvent>[];
        vad.events.listen(events.add);

        // Start speech.
        final loudChunk = _generateTone(
          testConfig.frameSamples * 3,
          amplitude: 8000,
        );
        vad.processAudioChunk(loudChunk);

        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(1));

        // Brief silence (only 2 frames, well below threshold).
        final briefSilence = _generateSilence(testConfig.frameSamples * 2);
        vad.processAudioChunk(briefSilence);

        // Resume speech.
        final moreLoud = _generateTone(
          testConfig.frameSamples * 3,
          amplitude: 8000,
        );
        vad.processAudioChunk(moreLoud);

        await Future<void>.delayed(Duration.zero);

        // Should still only have the initial SpeechStart.
        expect(events, hasLength(1));
        expect(vad.isSpeechActive, isTrue);
      });
    });

    group('chunked input handling', () {
      test('handles partial frames across multiple chunks', () async {
        final events = <VadEvent>[];
        vad.events.listen(events.add);

        // Send audio in oddly-sized chunks that don't align to frame size.
        // Frame = 64 samples = 128 bytes. Send 100 bytes at a time.
        final loudData = _generateTone(
          testConfig.frameSamples * 4,
          amplitude: 8000,
        );

        const chunkSize = 100;
        for (var offset = 0; offset < loudData.length; offset += chunkSize) {
          final end = offset + chunkSize > loudData.length
              ? loudData.length
              : offset + chunkSize;
          vad.processAudioChunk(
            Uint8List.sublistView(loudData, offset, end),
          );
        }

        await Future<void>.delayed(Duration.zero);

        // Should detect speech despite fragmented delivery.
        expect(events.isNotEmpty, isTrue);
        expect(events.first, isA<SpeechStart>());
      });
    });

    group('reset', () {
      test('clears speech state', () async {
        final events = <VadEvent>[];
        vad.events.listen(events.add);

        // Activate speech.
        final loudChunk = _generateTone(
          testConfig.frameSamples * 3,
          amplitude: 8000,
        );
        vad.processAudioChunk(loudChunk);

        await Future<void>.delayed(Duration.zero);
        expect(vad.isSpeechActive, isTrue);

        vad.reset();

        expect(vad.isSpeechActive, isFalse);
      });

      test('allows re-detection after reset', () async {
        final events = <VadEvent>[];
        vad.events.listen(events.add);

        // First speech activation.
        final loudChunk = _generateTone(
          testConfig.frameSamples * 3,
          amplitude: 8000,
        );
        vad.processAudioChunk(loudChunk);

        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(1));

        vad.reset();

        // Second speech activation.
        vad.processAudioChunk(loudChunk);

        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(2));
        expect(events[1], isA<SpeechStart>());
      });
    });

    group('full speech cycle', () {
      test('detects speech start and end in sequence', () async {
        final events = <VadEvent>[];
        vad.events.listen(events.add);

        // Speech segment.
        final speech = _generateTone(
          testConfig.frameSamples * 5,
          amplitude: 8000,
        );
        vad.processAudioChunk(speech);

        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(1));
        expect(events.first, isA<SpeechStart>());

        // Silence segment long enough to trigger end.
        final silence = _generateSilence(testConfig.frameSamples * 25);
        vad.processAudioChunk(silence);

        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(2));
        expect(events[1], isA<SpeechEnd>());

        // Another speech segment.
        vad.processAudioChunk(speech);

        await Future<void>.delayed(Duration.zero);
        expect(events, hasLength(3));
        expect(events[2], isA<SpeechStart>());
      });
    });

    group('VadConfig', () {
      test('frameDuration calculates correctly', () {
        const config = VadConfig(frameSamples: 512, sampleRate: 16000);
        // 512 / 16000 = 0.032s = 32ms
        expect(config.frameDuration, const Duration(milliseconds: 32));
      });

      test('frameDuration with different sample rates', () {
        const config = VadConfig(frameSamples: 480, sampleRate: 24000);
        // 480 / 24000 = 0.02s = 20ms
        expect(config.frameDuration, const Duration(milliseconds: 20));
      });
    });

    group('VadEvent model', () {
      test('SpeechStart toString includes timestamp', () {
        final event = SpeechStart(timestamp: DateTime(2025, 7, 1));
        expect(event.toString(), contains('SpeechStart'));
        expect(event.toString(), contains('2025'));
      });

      test('SpeechEnd toString includes duration', () {
        final event = SpeechEnd(
          timestamp: DateTime(2025, 7, 1),
          speechDuration: const Duration(seconds: 2),
        );
        expect(event.toString(), contains('SpeechEnd'));
        expect(event.toString(), contains('speechDuration'));
      });
    });
  });
}

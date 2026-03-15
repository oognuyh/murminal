import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/detected_state.dart';
import 'package:murminal/data/models/pattern_match_event.dart';
import 'package:murminal/data/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationService service;
  late List<MethodCall> nativeCalls;

  setUp(() {
    nativeCalls = [];
    service = NotificationService();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.murminal/notifications'),
      (MethodCall call) async {
        nativeCalls.add(call);
        if (call.method == 'requestPermission') return true;
        return null;
      },
    );
  });

  tearDown(() {
    service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.murminal/notifications'),
      null,
    );
  });

  group('NotificationService', () {
    test('requestPermission sends platform message', () async {
      final granted = await service.requestPermission();

      expect(granted, isTrue);
      expect(service.hasPermission, isTrue);
      expect(nativeCalls.length, 1);
      expect(nativeCalls.first.method, 'requestPermission');
    });

    test('showPatternMatchNotification sends platform message', () async {
      await service.requestPermission();
      nativeCalls.clear();

      final event = PatternMatchEvent(
        sessionName: 'dev-session',
        detectedState: const DetectedState(
          type: DetectedStateType.error,
          matchedText: 'Error: build failed',
          summary: 'build failed',
        ),
        priority: NotificationPriority.high,
        shouldReport: true,
        reportText: '[REPORT] Error detected: build failed',
        timestamp: DateTime(2025, 1, 1),
      );

      await service.showPatternMatchNotification(event);

      expect(nativeCalls.length, 1);
      expect(nativeCalls.first.method, 'showNotification');

      final args = nativeCalls.first.arguments as Map;
      expect(args['title'], contains('Error'));
      expect(args['title'], contains('dev-session'));
      expect(args['body'], 'Error detected: build failed');
      expect(args['sessionName'], 'dev-session');
      expect(args['priority'], 'high');
    });

    test('skips notification when shouldReport is false', () async {
      await service.requestPermission();
      nativeCalls.clear();

      final event = PatternMatchEvent(
        sessionName: 'dev-session',
        detectedState: const DetectedState(
          type: DetectedStateType.thinking,
          matchedText: 'Loading...',
        ),
        priority: NotificationPriority.low,
        shouldReport: false,
        reportText: '[REPORT] Working...',
        timestamp: DateTime(2025, 1, 1),
      );

      await service.showPatternMatchNotification(event);

      expect(nativeCalls, isEmpty);
    });

    test('skips notification when permission not granted', () async {
      final event = PatternMatchEvent(
        sessionName: 'dev-session',
        detectedState: const DetectedState(
          type: DetectedStateType.error,
          matchedText: 'Error: test',
        ),
        priority: NotificationPriority.high,
        shouldReport: true,
        reportText: '[REPORT] Error detected: test',
        timestamp: DateTime(2025, 1, 1),
      );

      await service.showPatternMatchNotification(event);

      expect(nativeCalls, isEmpty);
    });

    test('notification tap emits session name', () async {
      final taps = <String>[];
      final sub = service.onNotificationTap.listen(taps.add);

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('com.murminal/notifications');
      final data = const StandardMethodCodec()
          .encodeMethodCall(const MethodCall('onNotificationTap', 'dev-session'));
      await messenger.handlePlatformMessage(
        channel.name,
        data,
        (ByteData? reply) {},
      );

      await Future<void>.delayed(Duration.zero);

      expect(taps, ['dev-session']);

      await sub.cancel();
    });

    test('question notification has correct title', () async {
      await service.requestPermission();
      nativeCalls.clear();

      final event = PatternMatchEvent(
        sessionName: 'build-session',
        detectedState: const DetectedState(
          type: DetectedStateType.question,
          matchedText: '(y/N)',
          summary: 'Do you want to proceed? (y/N)',
        ),
        priority: NotificationPriority.high,
        shouldReport: true,
        reportText: '[REPORT] Input required: Do you want to proceed? (y/N)',
        timestamp: DateTime(2025, 1, 1),
      );

      await service.showPatternMatchNotification(event);

      final args = nativeCalls.first.arguments as Map;
      expect(args['title'], contains('Input needed'));
    });

    test('complete notification has correct title', () async {
      await service.requestPermission();
      nativeCalls.clear();

      final event = PatternMatchEvent(
        sessionName: 'ci-runner',
        detectedState: const DetectedState(
          type: DetectedStateType.complete,
          matchedText: 'All tests passed',
        ),
        priority: NotificationPriority.normal,
        shouldReport: true,
        reportText: '[REPORT] Task completed.',
        timestamp: DateTime(2025, 1, 1),
      );

      await service.showPatternMatchNotification(event);

      final args = nativeCalls.first.arguments as Map;
      expect(args['title'], contains('Completed'));
      expect(args['priority'], 'normal');
    });
  });
}

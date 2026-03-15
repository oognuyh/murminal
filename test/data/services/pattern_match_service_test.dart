import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/detected_state.dart';
import 'package:murminal/data/models/engine_profile.dart';
import 'package:murminal/data/models/pattern_match_event.dart';
import 'package:murminal/data/services/output_monitor.dart';
import 'package:murminal/data/services/pattern_match_service.dart';
import 'package:murminal/data/services/tmux_controller.dart';
import 'package:murminal/data/services/ssh_service.dart';

/// Minimal mock for SshService.
class MockSshService extends SshService {
  String Function(String command)? _handler;

  void onExecute(String Function(String command) handler) {
    _handler = handler;
  }

  @override
  Future<String> execute(String command, {bool throwOnError = true}) async {
    if (_handler != null) return _handler!(command);
    return '';
  }

  @override
  bool get isConnected => true;
}

void main() {
  late MockSshService mockSsh;
  late TmuxController controller;
  late OutputMonitor monitor;
  late PatternMatchService service;

  final testProfile = EngineProfile(
    name: 'test-engine',
    displayName: 'Test Engine',
    type: 'chat-tui',
    inputMode: 'natural_language',
    launch: const LaunchConfig(),
    patterns: {
      'error': r'Error:|FAILED',
      'question': r'\(y\/N\)|\(Y\/n\)',
      'complete': r'Done|Complete',
      'thinking': r'Loading\.\.\.',
    },
    states: {
      'error': const StateConfig(
        indicator: 'error_text',
        report: true,
        priority: 'high',
      ),
      'question': const StateConfig(
        indicator: 'prompt_text',
        report: true,
        priority: 'high',
      ),
      'complete': const StateConfig(
        indicator: 'checkmark',
        report: true,
        priority: 'normal',
      ),
      'thinking': const StateConfig(
        indicator: 'spinner',
        report: false,
      ),
    },
    reportTemplates: {
      'complete': 'Task completed.',
      'error': 'Error detected: {summary}',
      'question': 'Input required: {summary}',
      'thinking': 'Working...',
    },
  );

  setUp(() {
    mockSsh = MockSshService();
    controller = TmuxController(mockSsh);
    monitor = OutputMonitor(controller);
    service = PatternMatchService(
      monitor,
      debounceInterval: Duration.zero,
    );
  });

  tearDown(() {
    service.dispose();
    monitor.dispose();
  });

  group('PatternMatchService', () {
    test('emits match event when error pattern detected', () async {
      service.registerSession('dev', testProfile);
      service.start();

      final events = <PatternMatchEvent>[];
      final sub = service.matches.listen(events.add);

      mockSsh.onExecute((_) => 'Error: build failed\nline2');
      monitor.startMonitoring('dev',
          interval: const Duration(milliseconds: 50));

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(events, isNotEmpty);
      expect(events.first.detectedState.type, DetectedStateType.error);
      expect(events.first.sessionName, 'dev');
      expect(events.first.shouldReport, isTrue);
      expect(events.first.priority, NotificationPriority.high);

      await sub.cancel();
    });

    test('emits match event when question pattern detected', () async {
      service.registerSession('dev', testProfile);
      service.start();

      final events = <PatternMatchEvent>[];
      final sub = service.matches.listen(events.add);

      mockSsh.onExecute((_) => 'Do you want to continue? (y/N)');
      monitor.startMonitoring('dev',
          interval: const Duration(milliseconds: 50));

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(events, isNotEmpty);
      expect(events.first.detectedState.type, DetectedStateType.question);
      expect(events.first.priority, NotificationPriority.high);

      await sub.cancel();
    });

    test('emits match event when complete pattern detected', () async {
      service.registerSession('dev', testProfile);
      service.start();

      final events = <PatternMatchEvent>[];
      final sub = service.matches.listen(events.add);

      mockSsh.onExecute((_) => 'Build Done');
      monitor.startMonitoring('dev',
          interval: const Duration(milliseconds: 50));

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(events, isNotEmpty);
      expect(events.first.detectedState.type, DetectedStateType.complete);
      expect(events.first.priority, NotificationPriority.normal);
      expect(events.first.shouldReport, isTrue);

      await sub.cancel();
    });

    test('does not emit duplicate events for same state type', () async {
      service.registerSession('dev', testProfile);
      service.start();

      final events = <PatternMatchEvent>[];
      final sub = service.matches.listen(events.add);

      mockSsh.onExecute((_) => 'Error: first');
      monitor.startMonitoring('dev',
          interval: const Duration(milliseconds: 50));

      await Future<void>.delayed(const Duration(milliseconds: 200));

      mockSsh.onExecute((_) => 'Error: second');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(events.length, 1);

      await sub.cancel();
    });

    test('emits new event when state type changes', () async {
      service.registerSession('dev', testProfile);
      service.start();

      final events = <PatternMatchEvent>[];
      final sub = service.matches.listen(events.add);

      mockSsh.onExecute((_) => 'Error: something');
      monitor.startMonitoring('dev',
          interval: const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      mockSsh.onExecute((_) => 'Done');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(events.length, 2);
      expect(events[0].detectedState.type, DetectedStateType.error);
      expect(events[1].detectedState.type, DetectedStateType.complete);

      await sub.cancel();
    });

    test('thinking state has shouldReport false', () async {
      service.registerSession('dev', testProfile);
      service.start();

      final events = <PatternMatchEvent>[];
      final sub = service.matches.listen(events.add);

      mockSsh.onExecute((_) => 'Loading...');
      monitor.startMonitoring('dev',
          interval: const Duration(milliseconds: 50));

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(events, isNotEmpty);
      expect(events.first.detectedState.type, DetectedStateType.thinking);
      expect(events.first.shouldReport, isFalse);

      await sub.cancel();
    });

    test('uses default patterns when no profile registered', () async {
      service.start();

      final events = <PatternMatchEvent>[];
      final sub = service.matches.listen(events.add);

      mockSsh.onExecute((_) => 'fatal: something went wrong');
      monitor.startMonitoring('unknown-session',
          interval: const Duration(milliseconds: 50));

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(events, isNotEmpty);
      expect(events.first.detectedState.type, DetectedStateType.error);

      await sub.cancel();
    });

    test('unregisterSession clears session state', () async {
      service.registerSession('dev', testProfile);
      service.unregisterSession('dev');
      service.start();

      final events = <PatternMatchEvent>[];
      final sub = service.matches.listen(events.add);

      mockSsh.onExecute((_) => 'Error: test');
      monitor.startMonitoring('dev',
          interval: const Duration(milliseconds: 50));

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(events, isNotEmpty);

      await sub.cancel();
    });

    test('stop prevents further emissions', () async {
      service.registerSession('dev', testProfile);
      service.start();
      service.stop();

      final events = <PatternMatchEvent>[];
      final sub = service.matches.listen(events.add);

      mockSsh.onExecute((_) => 'Error: test');
      monitor.startMonitoring('dev',
          interval: const Duration(milliseconds: 50));

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(events, isEmpty);

      await sub.cancel();
    });
  });
}

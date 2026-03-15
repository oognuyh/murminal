import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/output_change_event.dart';
import 'package:murminal/data/services/output_monitor.dart';
import 'package:murminal/data/services/ssh_service.dart';
import 'package:murminal/data/services/tmux_controller.dart';

/// Manual mock for SshService used by TmuxController.
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

  setUp(() {
    mockSsh = MockSshService();
    controller = TmuxController(mockSsh);
    monitor = OutputMonitor(controller);
  });

  tearDown(() {
    monitor.dispose();
  });

  group('OutputMonitor', () {
    group('startMonitoring / stopMonitoring', () {
      test('isMonitoring returns true after start', () {
        mockSsh.onExecute((_) => 'output');
        monitor.startMonitoring('dev',
            interval: const Duration(seconds: 10));
        expect(monitor.isMonitoring('dev'), isTrue);

        monitor.stopMonitoring('dev');
        expect(monitor.isMonitoring('dev'), isFalse);
      });

      test('stopAll cancels all monitors', () {
        mockSsh.onExecute((_) => 'output');
        monitor.startMonitoring('dev',
            interval: const Duration(seconds: 10));
        monitor.startMonitoring('prod',
            interval: const Duration(seconds: 10));

        expect(monitor.isMonitoring('dev'), isTrue);
        expect(monitor.isMonitoring('prod'), isTrue);

        monitor.stopAll();
        expect(monitor.isMonitoring('dev'), isFalse);
        expect(monitor.isMonitoring('prod'), isFalse);
      });

      test('restarting monitoring replaces previous timer', () {
        mockSsh.onExecute((_) => 'output');
        monitor.startMonitoring('dev',
            interval: const Duration(seconds: 10));
        // Starting again should not throw or cause issues.
        monitor.startMonitoring('dev',
            interval: const Duration(seconds: 5));
        expect(monitor.isMonitoring('dev'), isTrue);
      });
    });

    group('change detection', () {
      test('emits event when output changes', () async {
        var callCount = 0;
        mockSsh.onExecute((_) {
          callCount++;
          return callCount == 1 ? 'first output' : 'second output';
        });

        final events = <OutputChangeEvent>[];
        monitor.changes.listen(events.add);

        // Use a short interval for testing.
        monitor.startMonitoring('dev',
            interval: const Duration(milliseconds: 50));

        // Wait for at least two poll cycles.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        monitor.stopMonitoring('dev');

        // First poll always emits (empty -> first output).
        // Second poll emits (first output -> second output).
        expect(events.length, greaterThanOrEqualTo(2));

        // Verify first event: empty previous, first capture.
        expect(events[0].sessionName, 'dev');
        expect(events[0].previousOutput, '');
        expect(events[0].currentOutput, 'first output');

        // Verify second event: transition between outputs.
        expect(events[1].previousOutput, 'first output');
        expect(events[1].currentOutput, 'second output');
      });

      test('does not emit when output is unchanged', () async {
        mockSsh.onExecute((_) => 'same output');

        final events = <OutputChangeEvent>[];
        monitor.changes.listen(events.add);

        monitor.startMonitoring('dev',
            interval: const Duration(milliseconds: 50));

        await Future<void>.delayed(const Duration(milliseconds: 200));
        monitor.stopMonitoring('dev');

        // Only the first poll (empty -> "same output") should emit.
        expect(events.length, 1);
        expect(events[0].previousOutput, '');
        expect(events[0].currentOutput, 'same output');
      });
    });

    group('diff computation', () {
      test('event includes line-level diff', () async {
        var callCount = 0;
        mockSsh.onExecute((_) {
          callCount++;
          if (callCount == 1) return 'line1\nline2';
          return 'line1\nline3';
        });

        final events = <OutputChangeEvent>[];
        monitor.changes.listen(events.add);

        monitor.startMonitoring('dev',
            interval: const Duration(milliseconds: 50));

        await Future<void>.delayed(const Duration(milliseconds: 200));
        monitor.stopMonitoring('dev');

        // The second event should show the diff between captures.
        expect(events.length, greaterThanOrEqualTo(2));
        final diffEvent = events[1];
        expect(diffEvent.diff, contains('-line2'));
        expect(diffEvent.diff, contains('+line3'));
      });
    });

    group('error handling', () {
      test('stops monitoring when session disappears', () async {
        var callCount = 0;
        mockSsh.onExecute((cmd) {
          callCount++;
          if (callCount > 1) {
            throw Exception('session not found');
          }
          return 'initial';
        });

        monitor.startMonitoring('gone',
            interval: const Duration(milliseconds: 50));

        await Future<void>.delayed(const Duration(milliseconds: 200));

        // Monitor should have stopped itself after the error.
        expect(monitor.isMonitoring('gone'), isFalse);
      });
    });

    group('multi-session batch monitoring', () {
      test('monitorSessions tracks all provided sessions', () {
        mockSsh.onExecute((_) => 'output');
        monitor.monitorSessions(['dev', 'staging', 'prod']);

        expect(monitor.isMonitoring('dev'), isTrue);
        expect(monitor.isMonitoring('staging'), isTrue);
        expect(monitor.isMonitoring('prod'), isTrue);
        expect(monitor.batchSessions, ['dev', 'staging', 'prod']);
      });

      test('monitorSessions replaces previous batch config', () {
        mockSsh.onExecute((_) => 'output');
        monitor.monitorSessions(['dev', 'staging']);
        monitor.monitorSessions(['prod']);

        expect(monitor.isMonitoring('dev'), isFalse);
        expect(monitor.isMonitoring('staging'), isFalse);
        expect(monitor.isMonitoring('prod'), isTrue);
        expect(monitor.batchSessions, ['prod']);
      });

      test('monitorSessions with empty list is a no-op', () {
        monitor.monitorSessions([]);
        expect(monitor.batchSessions, isEmpty);
      });

      test('stopBatchMonitoring clears batch sessions', () {
        mockSsh.onExecute((_) => 'output');
        monitor.monitorSessions(['dev', 'prod']);
        monitor.stopBatchMonitoring();

        expect(monitor.isMonitoring('dev'), isFalse);
        expect(monitor.isMonitoring('prod'), isFalse);
        expect(monitor.batchSessions, isEmpty);
      });

      test('stopMonitoring removes single session from batch', () {
        mockSsh.onExecute((_) => 'output');
        monitor.monitorSessions(['dev', 'prod']);
        monitor.stopMonitoring('dev');

        expect(monitor.isMonitoring('dev'), isFalse);
        expect(monitor.isMonitoring('prod'), isTrue);
        expect(monitor.batchSessions, ['prod']);
      });

      test('stopAll stops both individual and batch monitors', () {
        mockSsh.onExecute((_) => 'output');
        monitor.startMonitoring('individual',
            interval: const Duration(seconds: 10));
        monitor.monitorSessions(['batch1', 'batch2']);

        monitor.stopAll();

        expect(monitor.isMonitoring('individual'), isFalse);
        expect(monitor.isMonitoring('batch1'), isFalse);
        expect(monitor.isMonitoring('batch2'), isFalse);
      });

      test('batch polling emits per-session events', () async {
        final delimiter = TmuxController.batchDelimiter;
        mockSsh.onExecute((cmd) {
          if (cmd.contains('echo')) {
            // Batch command: return delimited output.
            return 'dev output$delimiter\nprod output';
          }
          return 'fallback';
        });

        final events = <OutputChangeEvent>[];
        monitor.changes.listen(events.add);

        monitor.monitorSessions(['dev', 'prod']);

        // Wait for batch poll to fire (interval is 1.7s for 2 sessions).
        await Future<void>.delayed(const Duration(milliseconds: 2500));
        monitor.stopBatchMonitoring();

        // Should have events for both sessions.
        final devEvents =
            events.where((e) => e.sessionName == 'dev').toList();
        final prodEvents =
            events.where((e) => e.sessionName == 'prod').toList();

        expect(devEvents, isNotEmpty);
        expect(prodEvents, isNotEmpty);
        expect(devEvents.first.currentOutput, 'dev output');
        expect(prodEvents.first.currentOutput, 'prod output');
      });

      test('batch polling detects per-session changes independently',
          () async {
        final delimiter = TmuxController.batchDelimiter;
        var callCount = 0;
        mockSsh.onExecute((cmd) {
          callCount++;
          if (cmd.contains('echo')) {
            if (callCount <= 1) {
              return 'dev v1$delimiter\nprod v1';
            }
            // Only dev changes on second poll.
            return 'dev v2$delimiter\nprod v1';
          }
          return '';
        });

        final events = <OutputChangeEvent>[];
        monitor.changes.listen(events.add);

        monitor.monitorSessions(['dev', 'prod']);

        // Wait for two batch poll cycles (interval 1.7s for 2 sessions).
        await Future<void>.delayed(const Duration(milliseconds: 4500));
        monitor.stopBatchMonitoring();

        // First cycle: both sessions emit (empty -> v1).
        // Second cycle: only dev emits (v1 -> v2), prod unchanged.
        final devEvents =
            events.where((e) => e.sessionName == 'dev').toList();
        final prodEvents =
            events.where((e) => e.sessionName == 'prod').toList();

        expect(devEvents.length, greaterThanOrEqualTo(2));
        expect(prodEvents.length, 1); // Only initial capture.
      });

      test('batch polling stops after consecutive failures', () async {
        mockSsh.onExecute((cmd) {
          throw Exception('connection lost');
        });

        monitor.monitorSessions(['dev']);

        // Wait for enough poll cycles to trigger failure threshold.
        await Future<void>.delayed(const Duration(milliseconds: 5500));

        // Monitor should have stopped after maxConsecutiveFailures.
        expect(monitor.batchSessions, isEmpty);
      });
    });

    group('adaptive polling interval', () {
      test('single session uses base interval', () {
        final interval = monitor.computeBatchInterval(1);
        expect(interval.inMilliseconds, 1500);
      });

      test('two sessions adds 200ms', () {
        final interval = monitor.computeBatchInterval(2);
        expect(interval.inMilliseconds, 1700);
      });

      test('five sessions adds 800ms', () {
        final interval = monitor.computeBatchInterval(5);
        expect(interval.inMilliseconds, 2300);
      });

      test('zero sessions uses base interval', () {
        final interval = monitor.computeBatchInterval(0);
        expect(interval.inMilliseconds, 1500);
      });
    });

    group('OutputChangeEvent model', () {
      test('equality works correctly', () {
        final ts = DateTime(2025, 6, 1);
        final a = OutputChangeEvent(
          sessionName: 'dev',
          previousOutput: 'old',
          currentOutput: 'new',
          diff: '+new\n-old',
          timestamp: ts,
        );
        final b = OutputChangeEvent(
          sessionName: 'dev',
          previousOutput: 'old',
          currentOutput: 'new',
          diff: '+new\n-old',
          timestamp: ts,
        );
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('toString includes session name', () {
        final event = OutputChangeEvent(
          sessionName: 'dev',
          previousOutput: '',
          currentOutput: 'output',
          diff: '+output',
          timestamp: DateTime(2025, 6, 1),
        );
        expect(event.toString(), contains('dev'));
      });
    });
  });

  group('TmuxController.batchCapturePane', () {
    late MockSshService mockSsh;
    late TmuxController controller;

    setUp(() {
      mockSsh = MockSshService();
      controller = TmuxController(mockSsh);
    });

    test('returns empty map for empty session list', () async {
      final result = await controller.batchCapturePane([]);
      expect(result, isEmpty);
    });

    test('delegates to capturePane for single session', () async {
      mockSsh.onExecute((cmd) {
        expect(cmd, contains('murminal-dev'));
        return 'single output';
      });

      final result = await controller.batchCapturePane(['dev']);
      expect(result, {'dev': 'single output'});
    });

    test('captures multiple sessions in one call', () async {
      final delimiter = TmuxController.batchDelimiter;
      mockSsh.onExecute((cmd) {
        // Verify the batch command references both sessions.
        expect(cmd, contains('murminal-dev'));
        expect(cmd, contains('murminal-prod'));
        expect(cmd, contains('echo'));
        return 'dev output$delimiter\nprod output';
      });

      final result = await controller.batchCapturePane(['dev', 'prod']);
      expect(result['dev'], 'dev output');
      expect(result['prod'], 'prod output');
    });

    test('throws TmuxCommandException on SSH failure', () async {
      mockSsh.onExecute((cmd) {
        throw Exception('connection refused');
      });

      expect(
        () => controller.batchCapturePane(['dev', 'prod']),
        throwsA(isA<TmuxCommandException>()),
      );
    });
  });
}

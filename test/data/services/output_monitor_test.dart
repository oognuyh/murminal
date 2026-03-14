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
  Future<String> execute(String command) async {
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
}

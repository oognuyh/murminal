import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/tmux_session.dart';
import 'package:murminal/data/services/ssh_service.dart';
import 'package:murminal/data/services/tmux_controller.dart';

/// Manual mock for SshService to avoid build_runner dependency.
class MockSshService extends SshService {
  String? lastCommand;
  final List<String> commands = [];
  String Function(String command)? _handler;

  void onExecute(String Function(String command) handler) {
    _handler = handler;
  }

  @override
  Future<String> execute(String command, {bool throwOnError = true}) async {
    lastCommand = command;
    commands.add(command);
    if (_handler != null) return _handler!(command);
    return '';
  }

  @override
  bool get isConnected => true;
}

void main() {
  late MockSshService mockSsh;
  late TmuxController controller;

  setUp(() {
    mockSsh = MockSshService();
    controller = TmuxController(mockSsh);
  });

  group('TmuxController', () {
    group('checkTmuxInstalled', () {
      test('returns true when tmux is found', () async {
        mockSsh.onExecute((_) => '/usr/bin/tmux\n');
        expect(await controller.checkTmuxInstalled(), isTrue);
      });

      test('returns false when tmux is not found', () async {
        mockSsh.onExecute((_) => '');
        expect(await controller.checkTmuxInstalled(), isFalse);
      });
    });

    group('createSession', () {
      test('creates session with prefixed name', () async {
        await controller.createSession('my-session');
        expect(mockSsh.commands, contains('tmux new-session -d -s "murminal-my-session"'));
      });

      test('sends command after session creation when provided', () async {
        await controller.createSession('dev', command: 'claude');
        expect(mockSsh.commands.length, 2);
        expect(mockSsh.commands[0], 'tmux new-session -d -s "murminal-dev"');
        expect(mockSsh.commands[1], contains('send-keys'));
        expect(mockSsh.commands[1], contains('claude'));
      });
    });

    group('killSession', () {
      test('kills session with prefixed name', () async {
        await controller.killSession('my-session');
        expect(mockSsh.lastCommand, 'tmux kill-session -t "murminal-my-session"');
      });
    });

    group('listSessions', () {
      test('parses sessions correctly', () async {
        final epoch1 = DateTime(2025, 6, 1).millisecondsSinceEpoch ~/ 1000;
        final epoch2 = DateTime(2025, 6, 2).millisecondsSinceEpoch ~/ 1000;

        mockSsh.onExecute((_) =>
            'murminal-dev|$epoch1|1|$epoch2\n'
            'murminal-prod|$epoch1|0|$epoch2\n');

        final sessions = await controller.listSessions();
        expect(sessions, hasLength(2));
        expect(sessions[0].name, 'dev');
        expect(sessions[0].attached, isTrue);
        expect(sessions[1].name, 'prod');
        expect(sessions[1].attached, isFalse);
      });

      test('filters out non-murminal sessions', () async {
        final epoch = DateTime(2025, 1, 1).millisecondsSinceEpoch ~/ 1000;
        mockSsh.onExecute((_) =>
            'my-other-session|$epoch|0|$epoch\n'
            'murminal-mine|$epoch|0|$epoch\n');

        final sessions = await controller.listSessions();
        expect(sessions, hasLength(1));
        expect(sessions[0].name, 'mine');
      });

      test('returns empty list when no sessions exist', () async {
        mockSsh.onExecute((_) => '');
        final sessions = await controller.listSessions();
        expect(sessions, isEmpty);
      });
    });

    group('sendKeys', () {
      test('sends keys with Enter to prefixed session', () async {
        await controller.sendKeys('dev', 'ls -la');
        expect(mockSsh.lastCommand,
          'tmux send-keys -t "murminal-dev" "ls -la" Enter');
      });
    });

    group('capturePane', () {
      test('captures last 50 lines by default', () async {
        mockSsh.onExecute((_) => 'line1\nline2\n');
        final output = await controller.capturePane('dev');
        expect(mockSsh.lastCommand,
          'tmux capture-pane -t "murminal-dev" -p -S -50');
        expect(output, 'line1\nline2\n');
      });

      test('uses custom line count', () async {
        mockSsh.onExecute((_) => 'output');
        await controller.capturePane('dev', lines: 100);
        expect(mockSsh.lastCommand,
          'tmux capture-pane -t "murminal-dev" -p -S -100');
      });
    });

    group('sessionPrefix', () {
      test('is murminal-', () {
        expect(TmuxController.sessionPrefix, 'murminal-');
      });
    });

    group('TmuxSession model', () {
      test('equality works correctly', () {
        final a = TmuxSession(
          name: 'dev',
          created: DateTime(2025, 1, 1),
          attached: true,
          activity: DateTime(2025, 1, 2),
        );
        final b = TmuxSession(
          name: 'dev',
          created: DateTime(2025, 1, 1),
          attached: true,
          activity: DateTime(2025, 1, 2),
        );
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });
  });
}

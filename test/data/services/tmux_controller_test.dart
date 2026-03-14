import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:murminal/data/models/tmux_session.dart';
import 'package:murminal/data/services/ssh_service.dart';
import 'package:murminal/data/services/tmux_controller.dart';

@GenerateMocks([SshService])
import 'tmux_controller_test.mocks.dart';

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
        when(mockSsh.execute('which tmux'))
            .thenAnswer((_) async => '/usr/bin/tmux\n');

        expect(await controller.checkTmuxInstalled(), isTrue);
      });

      test('returns false when tmux is not found', () async {
        when(mockSsh.execute('which tmux'))
            .thenAnswer((_) async => '');

        expect(await controller.checkTmuxInstalled(), isFalse);
      });

      test('returns false when ssh throws', () async {
        when(mockSsh.execute('which tmux'))
            .thenThrow(StateError('not connected'));

        expect(await controller.checkTmuxInstalled(), isFalse);
      });
    });

    group('createSession', () {
      test('creates session with prefixed name', () async {
        when(mockSsh.execute(any)).thenAnswer((_) async => '');

        await controller.createSession('my-session');

        verify(mockSsh.execute('tmux new-session -d -s "murminal-my-session"'))
            .called(1);
      });

      test('sends command after session creation when provided', () async {
        when(mockSsh.execute(any)).thenAnswer((_) async => '');

        await controller.createSession('dev', command: 'claude');

        verifyInOrder([
          mockSsh.execute('tmux new-session -d -s "murminal-dev"'),
          mockSsh.execute('tmux send-keys -t "murminal-dev" "claude" Enter'),
        ]);
      });

      test('does not send keys when command is null', () async {
        when(mockSsh.execute(any)).thenAnswer((_) async => '');

        await controller.createSession('plain');

        verify(mockSsh.execute('tmux new-session -d -s "murminal-plain"'))
            .called(1);
        verifyNever(mockSsh.execute(argThat(contains('send-keys'))));
      });

      test('throws TmuxCommandException on failure', () async {
        when(mockSsh.execute(any)).thenThrow(StateError('not connected'));

        expect(
          () => controller.createSession('fail'),
          throwsA(isA<TmuxCommandException>()),
        );
      });
    });

    group('killSession', () {
      test('kills session with prefixed name', () async {
        when(mockSsh.execute(any)).thenAnswer((_) async => '');

        await controller.killSession('my-session');

        verify(mockSsh.execute('tmux kill-session -t "murminal-my-session"'))
            .called(1);
      });

      test('throws TmuxCommandException on failure', () async {
        when(mockSsh.execute(any)).thenThrow(StateError('not connected'));

        expect(
          () => controller.killSession('gone'),
          throwsA(isA<TmuxCommandException>()),
        );
      });
    });

    group('listSessions', () {
      test('parses sessions correctly', () async {
        final epoch1 = DateTime(2025, 6, 1).millisecondsSinceEpoch ~/ 1000;
        final epoch2 = DateTime(2025, 6, 2).millisecondsSinceEpoch ~/ 1000;

        when(mockSsh.execute(any)).thenAnswer((_) async =>
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

        when(mockSsh.execute(any)).thenAnswer((_) async =>
            'my-other-session|$epoch|0|$epoch\n'
            'murminal-mine|$epoch|0|$epoch\n');

        final sessions = await controller.listSessions();

        expect(sessions, hasLength(1));
        expect(sessions[0].name, 'mine');
      });

      test('returns empty list when no sessions exist', () async {
        when(mockSsh.execute(any)).thenAnswer((_) async => '');

        final sessions = await controller.listSessions();

        expect(sessions, isEmpty);
      });

      test('returns empty list on ssh error', () async {
        when(mockSsh.execute(any)).thenThrow(StateError('not connected'));

        final sessions = await controller.listSessions();

        expect(sessions, isEmpty);
      });

      test('skips lines with invalid format', () async {
        final epoch = DateTime(2025, 1, 1).millisecondsSinceEpoch ~/ 1000;

        when(mockSsh.execute(any)).thenAnswer((_) async =>
            'murminal-ok|$epoch|0|$epoch\n'
            'murminal-bad|not-a-number|0|$epoch\n'
            'murminal-short|$epoch\n');

        final sessions = await controller.listSessions();

        expect(sessions, hasLength(1));
        expect(sessions[0].name, 'ok');
      });
    });

    group('sendKeys', () {
      test('sends keys with Enter to prefixed session', () async {
        when(mockSsh.execute(any)).thenAnswer((_) async => '');

        await controller.sendKeys('dev', 'ls -la');

        verify(mockSsh.execute(
          'tmux send-keys -t "murminal-dev" "ls -la" Enter',
        )).called(1);
      });

      test('escapes special characters', () async {
        when(mockSsh.execute(any)).thenAnswer((_) async => '');

        await controller.sendKeys('dev', 'echo "\$HOME"');

        verify(mockSsh.execute(
          'tmux send-keys -t "murminal-dev" "echo \\"\\\$HOME\\"" Enter',
        )).called(1);
      });

      test('throws TmuxCommandException on failure', () async {
        when(mockSsh.execute(any)).thenThrow(StateError('not connected'));

        expect(
          () => controller.sendKeys('dev', 'ls'),
          throwsA(isA<TmuxCommandException>()),
        );
      });
    });

    group('capturePane', () {
      test('captures last 50 lines by default', () async {
        when(mockSsh.execute(any)).thenAnswer((_) async => 'line1\nline2\n');

        final output = await controller.capturePane('dev');

        verify(mockSsh.execute(
          'tmux capture-pane -t "murminal-dev" -p -S -50',
        )).called(1);
        expect(output, 'line1\nline2\n');
      });

      test('uses custom line count', () async {
        when(mockSsh.execute(any)).thenAnswer((_) async => 'output');

        await controller.capturePane('dev', lines: 100);

        verify(mockSsh.execute(
          'tmux capture-pane -t "murminal-dev" -p -S -100',
        )).called(1);
      });

      test('throws TmuxCommandException on failure', () async {
        when(mockSsh.execute(any)).thenThrow(StateError('not connected'));

        expect(
          () => controller.capturePane('dev'),
          throwsA(isA<TmuxCommandException>()),
        );
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

      test('toString contains session info', () {
        final session = TmuxSession(
          name: 'test',
          created: DateTime(2025, 1, 1),
          attached: false,
          activity: DateTime(2025, 1, 1),
        );

        expect(session.toString(), contains('test'));
        expect(session.toString(), contains('attached: false'));
      });
    });

    group('TmuxNotInstalledException', () {
      test('has descriptive message', () {
        final ex = TmuxNotInstalledException();
        expect(ex.toString(), contains('tmux is not installed'));
      });
    });

    group('TmuxCommandException', () {
      test('includes command and message', () {
        const ex = TmuxCommandException(
          command: 'tmux list-sessions',
          message: 'connection lost',
        );
        expect(ex.toString(), contains('tmux list-sessions'));
        expect(ex.toString(), contains('connection lost'));
      });
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/worktree_info.dart';
import 'package:murminal/data/services/ssh_service.dart';
import 'package:murminal/data/services/worktree_service.dart';

/// Manual mock for SshService to avoid build_runner dependency.
class MockSshService extends SshService {
  String? lastCommand;
  final List<String> commands = [];
  String Function(String command)? _handler;
  bool _shouldThrow = false;

  void onExecute(String Function(String command) handler) {
    _handler = handler;
  }

  void throwOnExecute() {
    _shouldThrow = true;
  }

  @override
  Future<String> execute(String command) async {
    lastCommand = command;
    commands.add(command);
    if (_shouldThrow) throw Exception('SSH command failed');
    if (_handler != null) return _handler!(command);
    return '';
  }

  @override
  bool get isConnected => true;
}

void main() {
  late MockSshService mockSsh;
  late WorktreeService service;

  setUp(() {
    mockSsh = MockSshService();
    service = WorktreeService(mockSsh);
  });

  group('WorktreeService', () {
    group('createWorktree', () {
      test('executes git worktree add with default target dir', () async {
        mockSsh.onExecute((cmd) {
          if (cmd.contains('worktree add')) return '';
          // Return porcelain list for the follow-up listWorktrees call.
          return 'worktree /home/user/repo\n'
              'HEAD abc1234\n'
              'branch refs/heads/main\n'
              '\n'
              'worktree /home/user/feature-x\n'
              'HEAD def5678\n'
              'branch refs/heads/feature-x\n';
        });

        final result = await service.createWorktree('/home/user/repo', 'feature-x');

        expect(
          mockSsh.commands[0],
          'cd "/home/user/repo" && git worktree add "../feature-x" "feature-x"',
        );
        expect(result.branch, 'feature-x');
        expect(result.head, 'def5678');
      });

      test('uses custom target directory when provided', () async {
        mockSsh.onExecute((cmd) {
          if (cmd.contains('worktree add')) return '';
          return 'worktree /tmp/custom-dir\n'
              'HEAD aaa1111\n'
              'branch refs/heads/my-branch\n';
        });

        await service.createWorktree(
          '/home/user/repo',
          'my-branch',
          targetDir: '/tmp/custom-dir',
        );

        expect(
          mockSsh.commands[0],
          'cd "/home/user/repo" && git worktree add "/tmp/custom-dir" "my-branch"',
        );
      });

      test('throws WorktreeException when creation fails', () async {
        mockSsh.throwOnExecute();

        expect(
          () => service.createWorktree('/repo', 'branch'),
          throwsA(isA<WorktreeException>()),
        );
      });
    });

    group('listWorktrees', () {
      test('parses porcelain output correctly', () async {
        mockSsh.onExecute((_) =>
            'worktree /home/user/repo\n'
            'HEAD abc1234\n'
            'branch refs/heads/main\n'
            '\n'
            'worktree /home/user/feature\n'
            'HEAD def5678\n'
            'branch refs/heads/feature-branch\n');

        final worktrees = await service.listWorktrees('/home/user/repo');

        expect(worktrees, hasLength(2));
        expect(worktrees[0].path, '/home/user/repo');
        expect(worktrees[0].branch, 'main');
        expect(worktrees[0].head, 'abc1234');
        expect(worktrees[1].path, '/home/user/feature');
        expect(worktrees[1].branch, 'feature-branch');
        expect(worktrees[1].head, 'def5678');
      });

      test('handles detached HEAD entries', () async {
        mockSsh.onExecute((_) =>
            'worktree /home/user/detached\n'
            'HEAD 999abcd\n'
            'detached\n');

        final worktrees = await service.listWorktrees('/repo');

        expect(worktrees, hasLength(1));
        expect(worktrees[0].branch, isNull);
        expect(worktrees[0].head, '999abcd');
      });

      test('returns empty list on failure', () async {
        mockSsh.throwOnExecute();

        final worktrees = await service.listWorktrees('/repo');
        expect(worktrees, isEmpty);
      });

      test('returns empty list for empty output', () async {
        mockSsh.onExecute((_) => '');

        final worktrees = await service.listWorktrees('/repo');
        expect(worktrees, isEmpty);
      });
    });

    group('removeWorktree', () {
      test('executes git worktree remove command', () async {
        await service.removeWorktree('/home/user/repo', '/home/user/feature');

        expect(
          mockSsh.lastCommand,
          'cd "/home/user/repo" && git worktree remove "/home/user/feature"',
        );
      });

      test('throws WorktreeException when removal fails', () async {
        mockSsh.throwOnExecute();

        expect(
          () => service.removeWorktree('/repo', '/repo-feature'),
          throwsA(isA<WorktreeException>()),
        );
      });
    });

    group('WorktreeInfo model', () {
      test('equality works correctly', () {
        const a = WorktreeInfo(path: '/a', branch: 'main', head: 'abc');
        const b = WorktreeInfo(path: '/a', branch: 'main', head: 'abc');
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('inequality for different fields', () {
        const a = WorktreeInfo(path: '/a', branch: 'main', head: 'abc');
        const b = WorktreeInfo(path: '/b', branch: 'main', head: 'abc');
        expect(a, isNot(equals(b)));
      });

      test('toString returns readable representation', () {
        const info = WorktreeInfo(path: '/repo', branch: 'dev', head: '123');
        expect(info.toString(), contains('WorktreeInfo'));
        expect(info.toString(), contains('/repo'));
      });

      test('branch can be null for detached HEAD', () {
        const info = WorktreeInfo(path: '/repo', branch: null, head: 'abc');
        expect(info.branch, isNull);
      });
    });
  });
}

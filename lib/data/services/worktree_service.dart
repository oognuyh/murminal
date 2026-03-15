import 'package:murminal/data/models/worktree_info.dart';
import 'package:murminal/data/services/ssh_service.dart';

/// Exception thrown when a git worktree command fails.
class WorktreeException implements Exception {
  final String command;
  final String message;

  const WorktreeException({required this.command, required this.message});

  @override
  String toString() => 'WorktreeException: $message (command: $command)';
}

/// Manages git worktrees on a remote host via SSH.
///
/// All operations execute git commands through [SshService.execute].
class WorktreeService {
  final SshService _ssh;

  WorktreeService(this._ssh);

  /// Create a new worktree for [branch] inside [repoPath].
  ///
  /// If [targetDir] is provided it is used as the worktree directory path;
  /// otherwise git places the worktree next to the repository using the
  /// branch name.
  ///
  /// Returns the [WorktreeInfo] for the newly created worktree.
  /// Throws [WorktreeException] on failure.
  Future<WorktreeInfo> createWorktree(
    String repoPath,
    String branch, {
    String? targetDir,
  }) async {
    final target = targetDir ?? '../$branch';
    final cmd = 'cd "$repoPath" && git worktree add "$target" "$branch"';

    try {
      await _ssh.execute(cmd);
    } catch (e) {
      throw WorktreeException(
        command: cmd,
        message: 'Failed to create worktree for branch "$branch": $e',
      );
    }

    // Retrieve the actual worktree state after creation.
    final worktrees = await listWorktrees(repoPath);
    final created = worktrees.where((w) => w.branch == branch).firstOrNull;
    if (created != null) return created;

    // Fallback: return basic info when the list doesn't contain the new entry.
    return WorktreeInfo(path: target, branch: branch, head: '');
  }

  /// List all worktrees for the repository at [repoPath].
  ///
  /// Uses the porcelain format for reliable parsing.
  /// Returns an empty list when no worktrees exist or the command fails.
  Future<List<WorktreeInfo>> listWorktrees(String repoPath) async {
    final cmd = 'cd "$repoPath" && git worktree list --porcelain';

    try {
      final output = await _ssh.execute(cmd);
      return _parseWorktreeList(output);
    } catch (_) {
      return [];
    }
  }

  /// Remove the worktree at [worktreePath] from the repository at [repoPath].
  ///
  /// Throws [WorktreeException] if removal fails (e.g. path not found or
  /// worktree has uncommitted changes).
  Future<void> removeWorktree(
    String repoPath,
    String worktreePath,
  ) async {
    final cmd =
        'cd "$repoPath" && git worktree remove "$worktreePath"';

    try {
      await _ssh.execute(cmd);
    } catch (e) {
      throw WorktreeException(
        command: cmd,
        message: 'Failed to remove worktree "$worktreePath": $e',
      );
    }
  }

  /// Parse `git worktree list --porcelain` output into [WorktreeInfo] objects.
  ///
  /// Porcelain format example:
  /// ```
  /// worktree /home/user/repo
  /// HEAD abc1234
  /// branch refs/heads/main
  ///
  /// worktree /home/user/feature
  /// HEAD def5678
  /// branch refs/heads/feature-x
  /// ```
  List<WorktreeInfo> _parseWorktreeList(String output) {
    final worktrees = <WorktreeInfo>[];
    String? path;
    String? head;
    String? branch;

    for (final line in output.split('\n')) {
      final trimmed = line.trim();

      if (trimmed.startsWith('worktree ')) {
        // Save previous entry if complete.
        if (path != null && head != null) {
          worktrees.add(WorktreeInfo(path: path, branch: branch, head: head));
        }
        path = trimmed.substring('worktree '.length);
        head = null;
        branch = null;
      } else if (trimmed.startsWith('HEAD ')) {
        head = trimmed.substring('HEAD '.length);
      } else if (trimmed.startsWith('branch ')) {
        final ref = trimmed.substring('branch '.length);
        // Strip refs/heads/ prefix for a clean branch name.
        branch = ref.startsWith('refs/heads/')
            ? ref.substring('refs/heads/'.length)
            : ref;
      } else if (trimmed == 'detached') {
        branch = null;
      }
    }

    // Don't forget the last entry.
    if (path != null && head != null) {
      worktrees.add(WorktreeInfo(path: path, branch: branch, head: head));
    }

    return worktrees;
  }
}

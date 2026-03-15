/// Represents a git worktree entry on the remote host.
class WorktreeInfo {
  /// Absolute path of the worktree directory.
  final String path;

  /// Branch checked out in the worktree, or `null` for a detached HEAD.
  final String? branch;

  /// Current HEAD commit hash (abbreviated or full).
  final String head;

  const WorktreeInfo({
    required this.path,
    required this.branch,
    required this.head,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorktreeInfo &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          branch == other.branch &&
          head == other.head;

  @override
  int get hashCode => Object.hash(path, branch, head);

  @override
  String toString() =>
      'WorktreeInfo(path: $path, branch: $branch, head: $head)';
}

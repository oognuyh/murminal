import 'package:murminal/data/models/tmux_session.dart';
import 'package:murminal/data/services/ssh_service.dart';

/// Exception thrown when tmux is not installed on the remote host.
class TmuxNotInstalledException implements Exception {
  @override
  String toString() => 'tmux is not installed on the remote host';
}

/// Exception thrown when a tmux command fails.
class TmuxCommandException implements Exception {
  final String command;
  final String message;

  const TmuxCommandException({required this.command, required this.message});

  @override
  String toString() => 'TmuxCommandException: $message (command: $command)';
}

/// Controls tmux sessions over an SSH connection.
///
/// All session names are automatically prefixed with "murminal-" to avoid
/// collisions with user-managed tmux sessions on the remote host.
class TmuxController {
  final SshService _ssh;

  /// Prefix applied to all session names managed by Murminal.
  static const sessionPrefix = 'murminal-';

  TmuxController(this._ssh);

  /// Check whether tmux is installed on the remote host.
  Future<bool> checkTmuxInstalled() async {
    try {
      final output = await _ssh.execute('which tmux', throwOnError: false);
      return output.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Create a new tmux session with the given [name].
  ///
  /// Optionally runs [command] inside the session after creation.
  /// Throws [TmuxNotInstalledException] if tmux is not available.
  /// Throws [TmuxCommandException] if session creation fails.
  Future<void> createSession(
    String name, {
    String? command,
    int cols = 80,
    int rows = 24,
  }) async {
    final fullName = '$sessionPrefix$name';
    final createCmd = 'tmux new-session -d -s "$fullName" -x $cols -y $rows';

    try {
      await _ssh.execute(createCmd);
    } catch (e) {
      throw TmuxCommandException(
        command: createCmd,
        message: 'Failed to create session "$fullName": $e',
      );
    }

    if (command != null) {
      await sendKeys(name, command);
    }
  }

  /// Kill (destroy) the tmux session with the given [name].
  ///
  /// Throws [TmuxCommandException] if the session does not exist or
  /// the kill command fails.
  Future<void> killSession(String name) async {
    final fullName = '$sessionPrefix$name';
    final killCmd = 'tmux kill-session -t "$fullName"';

    try {
      await _ssh.execute(killCmd);
    } catch (e) {
      throw TmuxCommandException(
        command: killCmd,
        message: 'Failed to kill session "$fullName": $e',
      );
    }
  }

  /// Resize the tmux session to match the app's terminal view.
  ///
  /// For detached sessions, forces the window size by setting
  /// window-size to manual and resizing window + pane.
  Future<void> resizeWindow(String name, int cols, int rows) async {
    final fullName = '$sessionPrefix$name';
    final cmd = 'tmux set -t "$fullName" window-size manual 2>/dev/null; '
        'tmux resize-window -t "$fullName" -x $cols -y $rows 2>/dev/null; '
        'tmux resize-pane -t "$fullName" -x $cols -y $rows 2>/dev/null';
    try {
      await _ssh.execute(cmd, throwOnError: false);
    } catch (_) {
      // Best-effort resize.
    }
  }

  /// List all Murminal-managed tmux sessions.
  ///
  /// Only returns sessions whose names start with [sessionPrefix].
  /// Returns an empty list when no sessions exist or tmux reports an error.
  Future<List<TmuxSession>> listSessions() async {
    try {
      final output = await _ssh.execute(
        'tmux list-sessions -F '
        '"#{session_name}|#{session_created}|#{session_attached}|#{session_activity}" '
        '2>/dev/null',
        throwOnError: false,
      );
      return _parseSessions(output);
    } catch (_) {
      return [];
    }
  }

  /// Send [keys] to the tmux session identified by [session], followed
  /// by Enter.
  ///
  /// Throws [TmuxCommandException] if the command fails.
  Future<void> sendKeys(String session, String keys) async {
    final fullName = '$sessionPrefix$session';
    final escaped = _escapeForTmux(keys);
    final cmd = 'tmux send-keys -t "$fullName" "$escaped" Enter';

    try {
      await _ssh.execute(cmd, throwOnError: false);
    } catch (e) {
      throw TmuxCommandException(
        command: cmd,
        message: 'Failed to send keys to session "$fullName": $e',
      );
    }
  }

  /// Send raw [keys] to the tmux session without appending Enter.
  ///
  /// Use this for special keys (Tab, Escape, arrow keys, Ctrl sequences)
  /// or individual characters that should not trigger a newline.
  /// Throws [TmuxCommandException] if the command fails.
  Future<void> sendRawKeys(String session, String keys) async {
    final fullName = '$sessionPrefix$session';
    final cmd = 'tmux send-keys -t "$fullName" $keys';

    try {
      await _ssh.execute(cmd, throwOnError: false);
    } catch (e) {
      throw TmuxCommandException(
        command: cmd,
        message: 'Failed to send raw keys to session "$fullName": $e',
      );
    }
  }

  /// Capture the last [lines] lines of output from the tmux pane
  /// in the given [session].
  ///
  /// Returns the captured text. Throws [TmuxCommandException] on failure.
  Future<String> capturePane(String session, {int lines = 50}) async {
    final fullName = '$sessionPrefix$session';
    // -e preserves ANSI escape sequences so xterm can render colors
    // and cursor positioning correctly.
    final cmd = 'tmux capture-pane -t "$fullName" -p -e -S -$lines';

    try {
      return await _ssh.execute(cmd, throwOnError: false);
    } catch (e) {
      throw TmuxCommandException(
        command: cmd,
        message: 'Failed to capture pane for session "$fullName": $e',
      );
    }
  }

  /// Parse the output of `tmux list-sessions` into [TmuxSession] objects.
  ///
  /// Each line is expected to have the format:
  ///   session_name|session_created|session_attached|session_activity
  List<TmuxSession> _parseSessions(String output) {
    final sessions = <TmuxSession>[];

    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Only include Murminal-managed sessions.
      if (!trimmed.startsWith(sessionPrefix)) continue;

      final parts = trimmed.split('|');
      if (parts.length < 4) continue;

      final name = parts[0].substring(sessionPrefix.length);
      final createdEpoch = int.tryParse(parts[1]);
      final attachedCount = int.tryParse(parts[2]);
      final activityEpoch = int.tryParse(parts[3]);

      if (createdEpoch == null || attachedCount == null || activityEpoch == null) {
        continue;
      }

      sessions.add(TmuxSession(
        name: name,
        created: DateTime.fromMillisecondsSinceEpoch(createdEpoch * 1000),
        attached: attachedCount > 0,
        activity: DateTime.fromMillisecondsSinceEpoch(activityEpoch * 1000),
      ));
    }

    return sessions;
  }

  /// Delimiter used to separate outputs from different sessions in batch
  /// capture commands.
  static const batchDelimiter = '<<<MURMINAL_SESSION_BOUNDARY>>>';

  /// Capture pane output from multiple sessions in a single SSH exec call.
  ///
  /// Returns a map of session name to captured output. Sessions that fail
  /// to capture (e.g., killed externally) are omitted from the result.
  ///
  /// Throws [TmuxCommandException] if the SSH exec itself fails entirely
  /// (e.g., connection dropped).
  Future<Map<String, String>> batchCapturePane(
    List<String> sessions, {
    int lines = 50,
  }) async {
    if (sessions.isEmpty) return {};
    if (sessions.length == 1) {
      final output = await capturePane(sessions.first, lines: lines);
      return {sessions.first: output};
    }

    // Build a shell script that captures each session and separates
    // outputs with a known delimiter.
    final buffer = StringBuffer();
    for (var i = 0; i < sessions.length; i++) {
      final fullName = '$sessionPrefix${sessions[i]}';
      if (i > 0) {
        buffer.write('echo "$batchDelimiter"; ');
      }
      buffer.write(
        'tmux capture-pane -t "$fullName" -p -S -$lines 2>/dev/null; ',
      );
    }

    final cmd = buffer.toString();
    try {
      final rawOutput = await _ssh.execute(cmd, throwOnError: false);
      return _parseBatchOutput(sessions, rawOutput);
    } catch (e) {
      throw TmuxCommandException(
        command: cmd,
        message: 'Batch capture failed: $e',
      );
    }
  }

  /// Parse the raw output of a batch capture command into per-session outputs.
  Map<String, String> _parseBatchOutput(
    List<String> sessions,
    String rawOutput,
  ) {
    final parts = rawOutput.split(batchDelimiter);
    final result = <String, String>{};

    for (var i = 0; i < sessions.length && i < parts.length; i++) {
      result[sessions[i]] = parts[i].trim();
    }

    return result;
  }

  /// Escape special characters for safe use inside tmux send-keys.
  String _escapeForTmux(String input) {
    return input
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll(r'$', r'\$')
        .replaceAll('`', r'\`');
  }
}

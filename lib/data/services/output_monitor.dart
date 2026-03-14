import 'dart:async';

import 'package:murminal/data/models/output_change_event.dart';
import 'package:murminal/data/services/tmux_controller.dart';

/// Exception thrown when the SSH connection drops during monitoring.
class MonitorDisconnectedException implements Exception {
  final String message;

  const MonitorDisconnectedException(this.message);

  @override
  String toString() => 'MonitorDisconnectedException: $message';
}

/// Monitors tmux session output by polling [TmuxController.capturePane]
/// at a configurable interval and emitting [OutputChangeEvent]s when
/// the captured content changes.
///
/// Supports both single-session monitoring via [startMonitoring] and
/// multi-session batch monitoring via [monitorSessions], which captures
/// all sessions in a single SSH exec call for efficiency.
class OutputMonitor {
  final TmuxController _tmux;

  /// Active polling timers keyed by session name.
  final Map<String, Timer> _timers = {};

  /// Last captured output per session, used for diff detection.
  final Map<String, String> _previousOutputs = {};

  final StreamController<OutputChangeEvent> _changeController =
      StreamController<OutputChangeEvent>.broadcast();

  /// Timer for batch multi-session polling.
  Timer? _batchTimer;

  /// Session names currently monitored via batch polling.
  final List<String> _batchSessions = [];

  /// Base polling interval for batch monitoring.
  static const _batchBaseInterval = Duration(milliseconds: 1500);

  /// Additional interval per session beyond the first.
  static const _batchPerSessionMs = 200;

  /// Number of consecutive SSH failures during batch polling.
  int _consecutiveFailures = 0;

  /// Maximum consecutive failures before stopping batch monitoring.
  static const maxConsecutiveFailures = 3;

  OutputMonitor(this._tmux);

  /// Stream of output change events across all monitored sessions.
  Stream<OutputChangeEvent> get changes => _changeController.stream;

  /// Whether the given [sessionName] is currently being monitored.
  bool isMonitoring(String sessionName) =>
      _timers.containsKey(sessionName) ||
      _batchSessions.contains(sessionName);

  /// The session names currently tracked by batch monitoring.
  List<String> get batchSessions => List.unmodifiable(_batchSessions);

  /// Compute the adaptive polling interval for batch monitoring.
  ///
  /// Formula: base 1.5s + 0.2s per additional session (beyond the first).
  Duration computeBatchInterval(int sessionCount) {
    if (sessionCount <= 1) return _batchBaseInterval;
    final extraMs = (sessionCount - 1) * _batchPerSessionMs;
    return _batchBaseInterval + Duration(milliseconds: extraMs);
  }

  /// Start polling the given [sessionName] for output changes.
  ///
  /// The [interval] controls how often the pane is captured (default 2s).
  /// The [lines] parameter is forwarded to [TmuxController.capturePane].
  ///
  /// If the session is already being monitored, the existing timer is
  /// cancelled and replaced with a new one using the provided parameters.
  void startMonitoring(
    String sessionName, {
    Duration interval = const Duration(seconds: 2),
    int lines = 50,
  }) {
    // Cancel any existing monitor for this session.
    stopMonitoring(sessionName);

    _timers[sessionName] = Timer.periodic(interval, (_) async {
      await _poll(sessionName, lines: lines);
    });
  }

  /// Start batch monitoring for multiple sessions using a single SSH exec
  /// per polling cycle.
  ///
  /// The polling interval adapts based on the number of sessions:
  /// base 1.5s + 0.2s per additional session.
  ///
  /// The [lines] parameter controls how many lines to capture per session.
  ///
  /// Replaces any previous batch monitoring configuration. Individual
  /// per-session monitors started via [startMonitoring] are NOT affected.
  void monitorSessions(
    List<String> sessionNames, {
    int lines = 50,
  }) {
    stopBatchMonitoring();

    if (sessionNames.isEmpty) return;

    _batchSessions.addAll(sessionNames);
    _consecutiveFailures = 0;

    final interval = computeBatchInterval(sessionNames.length);
    _batchTimer = Timer.periodic(interval, (_) async {
      await _batchPoll(lines: lines);
    });
  }

  /// Stop monitoring the given [sessionName].
  ///
  /// Removes from both individual timers and batch session list.
  /// No-op if the session is not currently monitored.
  void stopMonitoring(String sessionName) {
    _timers[sessionName]?.cancel();
    _timers.remove(sessionName);
    _previousOutputs.remove(sessionName);

    // Also remove from batch if present.
    _batchSessions.remove(sessionName);
    // If batch list is now empty, cancel batch timer.
    if (_batchSessions.isEmpty) {
      _batchTimer?.cancel();
      _batchTimer = null;
    }
  }

  /// Stop batch monitoring for all sessions.
  ///
  /// Does NOT affect individual per-session monitors.
  void stopBatchMonitoring() {
    _batchTimer?.cancel();
    _batchTimer = null;
    for (final session in _batchSessions) {
      _previousOutputs.remove(session);
    }
    _batchSessions.clear();
    _consecutiveFailures = 0;
  }

  /// Stop monitoring all sessions and clean up resources.
  void stopAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _previousOutputs.clear();
    stopBatchMonitoring();
  }

  /// Release all resources including the change stream.
  ///
  /// After calling dispose, the monitor should not be used again.
  void dispose() {
    stopAll();
    _changeController.close();
  }

  /// Perform a single poll cycle for the given [sessionName].
  Future<void> _poll(String sessionName, {int lines = 50}) async {
    try {
      final currentOutput =
          await _tmux.capturePane(sessionName, lines: lines);
      _processSessionOutput(sessionName, currentOutput);
    } on TmuxCommandException {
      // Session may have been killed externally; stop monitoring.
      stopMonitoring(sessionName);
    }
  }

  /// Perform a batch poll cycle for all batch-monitored sessions using
  /// a single SSH exec call.
  ///
  /// Builds a shell command that loops over all session names and captures
  /// each pane, using a delimiter to separate outputs.
  Future<void> _batchPoll({int lines = 50}) async {
    if (_batchSessions.isEmpty) return;

    try {
      final outputs = await _tmux.batchCapturePane(
        _batchSessions,
        lines: lines,
      );

      _consecutiveFailures = 0;

      // Process each session output independently.
      for (final entry in outputs.entries) {
        _processSessionOutput(entry.key, entry.value);
      }
    } on TmuxCommandException catch (e) {
      // Individual session failure during batch — try to identify which
      // session is gone and remove it.
      _handleBatchSessionError(e);
    } on MonitorDisconnectedException {
      // SSH connection dropped entirely; stop all batch monitoring.
      stopBatchMonitoring();
    } catch (_) {
      _consecutiveFailures++;
      if (_consecutiveFailures >= maxConsecutiveFailures) {
        stopBatchMonitoring();
      }
    }
  }

  /// Handle a session-level error during batch polling.
  ///
  /// If the error message contains a session name, that session is removed
  /// from batch monitoring. Otherwise, increment the failure counter.
  void _handleBatchSessionError(TmuxCommandException e) {
    // Try to find which session caused the error.
    final failedSession = _batchSessions.cast<String?>().firstWhere(
          (s) => e.message.contains(s!),
          orElse: () => null,
        );

    if (failedSession != null) {
      stopMonitoring(failedSession);
    } else {
      _consecutiveFailures++;
      if (_consecutiveFailures >= maxConsecutiveFailures) {
        stopBatchMonitoring();
      }
    }
  }

  /// Compare captured output against previous state for a session
  /// and emit an [OutputChangeEvent] if it changed.
  void _processSessionOutput(String sessionName, String currentOutput) {
    final previousOutput = _previousOutputs[sessionName] ?? '';

    if (currentOutput != previousOutput) {
      final diff = _computeDiff(previousOutput, currentOutput);
      _previousOutputs[sessionName] = currentOutput;

      _changeController.add(OutputChangeEvent(
        sessionName: sessionName,
        previousOutput: previousOutput,
        currentOutput: currentOutput,
        diff: diff,
        timestamp: DateTime.now(),
      ));
    }
  }

  /// Compute a simple line-level diff between [previous] and [current].
  ///
  /// Lines only in [previous] are prefixed with `-`.
  /// Lines only in [current] are prefixed with `+`.
  static String _computeDiff(String previous, String current) {
    final oldLines = previous.split('\n');
    final newLines = current.split('\n');
    final oldSet = oldLines.toSet();
    final newSet = newLines.toSet();

    final buffer = StringBuffer();

    for (final line in oldLines) {
      if (!newSet.contains(line)) {
        buffer.writeln('-$line');
      }
    }
    for (final line in newLines) {
      if (!oldSet.contains(line)) {
        buffer.writeln('+$line');
      }
    }

    return buffer.toString().trimRight();
  }
}

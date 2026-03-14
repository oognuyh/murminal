import 'dart:async';

import 'package:murminal/data/models/output_change_event.dart';
import 'package:murminal/data/services/tmux_controller.dart';

/// Monitors tmux session output by polling [TmuxController.capturePane]
/// at a configurable interval and emitting [OutputChangeEvent]s when
/// the captured content changes.
class OutputMonitor {
  final TmuxController _tmux;

  /// Active polling timers keyed by session name.
  final Map<String, Timer> _timers = {};

  /// Last captured output per session, used for diff detection.
  final Map<String, String> _previousOutputs = {};

  final StreamController<OutputChangeEvent> _changeController =
      StreamController<OutputChangeEvent>.broadcast();

  OutputMonitor(this._tmux);

  /// Stream of output change events across all monitored sessions.
  Stream<OutputChangeEvent> get changes => _changeController.stream;

  /// Whether the given [sessionName] is currently being monitored.
  bool isMonitoring(String sessionName) => _timers.containsKey(sessionName);

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

  /// Stop monitoring the given [sessionName].
  ///
  /// No-op if the session is not currently monitored.
  void stopMonitoring(String sessionName) {
    _timers[sessionName]?.cancel();
    _timers.remove(sessionName);
    _previousOutputs.remove(sessionName);
  }

  /// Stop monitoring all sessions and clean up resources.
  void stopAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _previousOutputs.clear();
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
      final currentOutput = await _tmux.capturePane(sessionName, lines: lines);
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
    } on TmuxCommandException {
      // Session may have been killed externally; stop monitoring.
      stopMonitoring(sessionName);
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

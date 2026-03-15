import 'dart:async';
import 'dart:developer' as developer;

import 'package:murminal/data/models/detected_state.dart';
import 'package:murminal/data/models/engine_profile.dart';
import 'package:murminal/data/models/output_change_event.dart';
import 'package:murminal/data/models/pattern_match_event.dart';
import 'package:murminal/data/services/default_patterns.dart';
import 'package:murminal/data/services/output_monitor.dart';
import 'package:murminal/data/services/pattern_detector.dart';
import 'package:murminal/data/services/report_generator.dart';

/// Watches [OutputMonitor] and matches terminal output against engine
/// profile patterns, emitting [PatternMatchEvent]s for notifications.
///
/// Each monitored session can be associated with an [EngineProfile]
/// for engine-specific pattern matching. Sessions without a profile
/// use [DefaultPatterns.defaultProfile] as a fallback.
///
/// Debounces rapid output changes to avoid notification spam — only
/// the latest state within a configurable window is emitted.
class PatternMatchService {
  static const _tag = 'PatternMatchService';

  final OutputMonitor _outputMonitor;

  /// Per-session pattern detectors, keyed by session name.
  final Map<String, PatternDetector> _detectors = {};

  /// Per-session report generators, keyed by session name.
  final Map<String, ReportGenerator> _generators = {};

  /// Last emitted state per session, used to avoid duplicate notifications.
  final Map<String, DetectedStateType> _lastEmittedState = {};

  /// Debounce timers per session.
  final Map<String, Timer> _debounceTimers = {};

  /// Debounce duration for rapid output changes.
  final Duration debounceInterval;

  StreamSubscription<OutputChangeEvent>? _outputSub;

  final StreamController<PatternMatchEvent> _matchController =
      StreamController<PatternMatchEvent>.broadcast();

  /// Creates a [PatternMatchService] watching the given [OutputMonitor].
  ///
  /// The [debounceInterval] controls how long to wait after an output
  /// change before emitting a match event (default 500ms).
  PatternMatchService(
    this._outputMonitor, {
    this.debounceInterval = const Duration(milliseconds: 500),
  });

  /// Stream of pattern match events for notification dispatch.
  Stream<PatternMatchEvent> get matches => _matchController.stream;

  /// Start listening to output changes from the monitor.
  void start() {
    _outputSub?.cancel();
    _outputSub = _outputMonitor.changes.listen(_onOutputChange);
    developer.log('Started pattern match service', name: _tag);
  }

  /// Stop listening and clear all state.
  void stop() {
    _outputSub?.cancel();
    _outputSub = null;
    _cancelAllDebounce();
    _lastEmittedState.clear();
    developer.log('Stopped pattern match service', name: _tag);
  }

  /// Register an engine profile for a specific session.
  ///
  /// Creates a [PatternDetector] and [ReportGenerator] from the profile.
  /// If the session already has a profile, it is replaced.
  void registerSession(String sessionName, EngineProfile profile) {
    _detectors[sessionName] = PatternDetector(profile);
    _generators[sessionName] = ReportGenerator(profile);
    developer.log(
      'Registered profile "${profile.name}" for session "$sessionName"',
      name: _tag,
    );
  }

  /// Unregister a session, removing its profile and clearing state.
  void unregisterSession(String sessionName) {
    _detectors.remove(sessionName);
    _generators.remove(sessionName);
    _lastEmittedState.remove(sessionName);
    _debounceTimers[sessionName]?.cancel();
    _debounceTimers.remove(sessionName);
  }

  /// Handle an output change event from the monitor.
  void _onOutputChange(OutputChangeEvent event) {
    final sessionName = event.sessionName;

    // Get or create detector for this session.
    var detector = _detectors[sessionName];
    var generator = _generators[sessionName];

    // Fall back to default patterns if no profile registered.
    if (detector == null) {
      final defaultProfile = DefaultPatterns.defaultProfile;
      detector = PatternDetector(defaultProfile);
      generator = ReportGenerator(defaultProfile);
      _detectors[sessionName] = detector;
      _generators[sessionName] = generator;
    }

    generator ??= ReportGenerator(detector.profile);

    // Run pattern detection on the new output.
    final detected = detector.detect(event.currentOutput);
    if (detected == null) return;

    // Debounce: cancel any pending emission for this session.
    _debounceTimers[sessionName]?.cancel();
    _debounceTimers[sessionName] = Timer(debounceInterval, () {
      _emitIfNew(sessionName, detected, generator!);
    });
  }

  /// Emit a match event if the detected state differs from the last
  /// emitted state for this session.
  void _emitIfNew(
    String sessionName,
    DetectedState detected,
    ReportGenerator generator,
  ) {
    final lastState = _lastEmittedState[sessionName];
    if (lastState == detected.type) return;

    _lastEmittedState[sessionName] = detected.type;

    // Look up state config for priority and report flag.
    final profile = generator.profile;
    final stateConfig = profile.states[detected.type.name];
    final shouldReport = stateConfig?.report ?? false;
    final priority = _parsePriority(stateConfig?.priority);

    // Generate the report text.
    final reportText =
        generator.generateReport(detected, detected.matchedText);

    final event = PatternMatchEvent(
      sessionName: sessionName,
      detectedState: detected,
      priority: priority,
      shouldReport: shouldReport,
      reportText: reportText,
      timestamp: DateTime.now(),
    );

    _matchController.add(event);

    developer.log(
      'Pattern match: session="$sessionName" type=${detected.type.name} '
      'priority=${priority.name} report=$shouldReport',
      name: _tag,
    );
  }

  /// Parse a priority string from the state config into an enum value.
  static NotificationPriority _parsePriority(String? priority) {
    return switch (priority) {
      'high' => NotificationPriority.high,
      'normal' => NotificationPriority.normal,
      'low' => NotificationPriority.low,
      _ => NotificationPriority.normal,
    };
  }

  void _cancelAllDebounce() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
  }

  /// Release all resources. The service must not be used after this.
  void dispose() {
    stop();
    _cancelAllDebounce();
    _detectors.clear();
    _generators.clear();
    _matchController.close();
  }
}

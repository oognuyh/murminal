/// Engine type classification.
enum EngineType {
  chatTui('chat-tui'),
  rawShell('raw-shell'),
  editor('editor');

  const EngineType(this.value);
  final String value;

  static EngineType fromString(String value) {
    return EngineType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw ArgumentError('Unknown engine type: $value'),
    );
  }
}

/// Input mode for the engine.
enum InputMode {
  naturalLanguage('natural_language'),
  command('command'),
  keySequence('key_sequence');

  const InputMode(this.value);
  final String value;

  static InputMode fromString(String value) {
    return InputMode.values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw ArgumentError('Unknown input mode: $value'),
    );
  }
}

/// Detected engine state from terminal output.
enum EngineState {
  idle,
  working,
  needsInput,
  error,
  done,
  unknown,
}

/// Report priority level.
enum ReportPriority {
  normal,
  high,
  critical;

  static ReportPriority fromString(String value) {
    return ReportPriority.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw ArgumentError('Unknown priority: $value'),
    );
  }
}

/// Launch configuration for starting the engine process.
class LaunchConfig {
  final String? command;
  final List<String> flags;
  final Map<String, String> env;

  const LaunchConfig({
    this.command,
    this.flags = const [],
    this.env = const {},
  });

  factory LaunchConfig.fromJson(Map<String, dynamic> json) {
    return LaunchConfig(
      command: json['command'] as String?,
      flags: (json['flags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      env: (json['env'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'command': command,
        'flags': flags,
        'env': env,
      };
}

/// Configuration for a single engine state.
class StateConfig {
  final String indicator;
  final bool report;
  final ReportPriority? priority;

  const StateConfig({
    required this.indicator,
    this.report = false,
    this.priority,
  });

  factory StateConfig.fromJson(Map<String, dynamic> json) {
    return StateConfig(
      indicator: json['indicator'] as String,
      report: json['report'] as bool? ?? false,
      priority: json['priority'] != null
          ? ReportPriority.fromString(json['priority'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'indicator': indicator,
        'report': report,
        if (priority != null) 'priority': priority!.name,
      };
}

/// Engine profile defining behavior patterns for a coding agent.
///
/// Profiles are loaded from JSON files in `assets/profiles/` and describe
/// how to launch, monitor, and interpret terminal output from an engine.
class EngineProfile {
  final String name;
  final String displayName;
  final String? icon;
  final EngineType type;
  final InputMode inputMode;
  final LaunchConfig launch;
  final Map<String, String?> patterns;
  final Map<String, StateConfig> states;
  final Map<String, String> reportTemplates;

  const EngineProfile({
    required this.name,
    required this.displayName,
    this.icon,
    required this.type,
    required this.inputMode,
    required this.launch,
    required this.patterns,
    this.states = const {},
    this.reportTemplates = const {},
  });

  factory EngineProfile.fromJson(Map<String, dynamic> json) {
    final patternsRaw = json['patterns'] as Map<String, dynamic>? ?? {};
    final patterns = patternsRaw.map(
      (k, v) => MapEntry(k, v as String?),
    );

    final statesRaw = json['states'] as Map<String, dynamic>? ?? {};
    final states = statesRaw.map(
      (k, v) => MapEntry(k, StateConfig.fromJson(v as Map<String, dynamic>)),
    );

    final templatesRaw =
        json['report_templates'] as Map<String, dynamic>? ?? {};
    final reportTemplates = templatesRaw.map(
      (k, v) => MapEntry(k, v as String),
    );

    return EngineProfile(
      name: json['name'] as String,
      displayName: json['display_name'] as String,
      icon: json['icon'] as String?,
      type: EngineType.fromString(json['type'] as String),
      inputMode: InputMode.fromString(json['input_mode'] as String),
      launch: json['launch'] != null
          ? LaunchConfig.fromJson(json['launch'] as Map<String, dynamic>)
          : const LaunchConfig(),
      patterns: patterns,
      states: states,
      reportTemplates: reportTemplates,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'display_name': displayName,
        if (icon != null) 'icon': icon,
        'type': type.value,
        'input_mode': inputMode.value,
        'launch': launch.toJson(),
        'patterns': patterns,
        'states': states.map((k, v) => MapEntry(k, v.toJson())),
        'report_templates': reportTemplates,
      };
}

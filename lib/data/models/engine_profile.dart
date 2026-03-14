import 'dart:convert';

/// Launch configuration for an engine.
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

/// State configuration for engine state detection.
class StateConfig {
  final String indicator;
  final bool report;
  final String? priority;

  const StateConfig({
    required this.indicator,
    this.report = false,
    this.priority,
  });

  factory StateConfig.fromJson(Map<String, dynamic> json) {
    return StateConfig(
      indicator: json['indicator'] as String,
      report: json['report'] as bool? ?? false,
      priority: json['priority'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'indicator': indicator,
        'report': report,
        if (priority != null) 'priority': priority,
      };
}

/// Detected engine state from terminal output pattern matching.
enum EngineState {
  idle,
  working,
  needsInput,
  error,
  done,
  unknown,
}

/// Engine profile defining behavior patterns for a terminal engine.
///
/// Profiles are loaded from JSON files in assets/profiles/ and allow
/// adding new engines without code changes.
class EngineProfile {
  final String name;
  final String displayName;
  final String type;
  final String inputMode;
  final LaunchConfig launch;
  final Map<String, String?> patterns;
  final Map<String, StateConfig> states;
  final Map<String, String> reportTemplates;

  const EngineProfile({
    required this.name,
    required this.displayName,
    required this.type,
    required this.inputMode,
    required this.launch,
    this.patterns = const {},
    this.states = const {},
    this.reportTemplates = const {},
  });

  factory EngineProfile.fromJson(Map<String, dynamic> json) {
    return EngineProfile(
      name: json['name'] as String,
      displayName: json['display_name'] as String,
      type: json['type'] as String,
      inputMode: json['input_mode'] as String,
      launch: json['launch'] != null
          ? LaunchConfig.fromJson(json['launch'] as Map<String, dynamic>)
          : const LaunchConfig(),
      patterns: (json['patterns'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as String?),
          ) ??
          const {},
      states: (json['states'] as Map<String, dynamic>?)?.map(
            (k, v) =>
                MapEntry(k, StateConfig.fromJson(v as Map<String, dynamic>)),
          ) ??
          const {},
      reportTemplates:
          (json['report_templates'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, v as String),
              ) ??
              const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'display_name': displayName,
        'type': type,
        'input_mode': inputMode,
        'launch': launch.toJson(),
        'patterns': patterns,
        'states': states.map((k, v) => MapEntry(k, v.toJson())),
        'report_templates': reportTemplates,
      };

  /// Parse a JSON string into an [EngineProfile].
  static EngineProfile parse(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return EngineProfile.fromJson(json);
  }
}

import 'package:murminal/data/models/engine_profile.dart';

/// Built-in default patterns for common CLI tools.
///
/// These patterns are used as a fallback when no engine profile is
/// configured for a session, providing reasonable detection for
/// approval requests, errors, completions, and input prompts.
class DefaultPatterns {
  DefaultPatterns._();

  /// Default pattern strings keyed by detected state type.
  ///
  /// Each pattern is a regex that matches common terminal output
  /// from a wide variety of CLI tools.
  static const Map<String, String> patterns = {
    'question': r'Do you want to proceed\?'
        r'|\(y\/N\)|\(Y\/n\)|\(yes\/no\)'
        r'|Enter password:|Enter passphrase:'
        r'|Are you sure\?|Continue\?'
        r'|\[y\/n\]|\[Y\/n\]|\[yes\/no\]'
        r'|Press any key|Press Enter',
    'error': r'error:|ERROR:|Error:'
        r'|FAILED|FAIL:|fatal:'
        r'|Exception:|Traceback \(most recent'
        r'|panic:|PANIC:'
        r'|Permission denied'
        r'|command not found'
        r'|No such file or directory',
    'complete': r'Build succeeded|Build successful'
        r'|All tests passed|Tests passed'
        r'|\bDone\b|Finished|Complete'
        r'|Successfully|Success'
        r'|✓|✔|passed',
    'thinking': r'⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏'
        r'|Loading\.\.\.|Compiling\.\.\.'
        r'|Building\.\.\.|Installing\.\.\.'
        r'|Downloading\.\.\.',
  };

  /// Default state configurations keyed by state name.
  static const Map<String, StateConfig> states = {
    'question': StateConfig(
      indicator: 'prompt_text',
      report: true,
      priority: 'high',
    ),
    'error': StateConfig(
      indicator: 'error_text',
      report: true,
      priority: 'high',
    ),
    'complete': StateConfig(
      indicator: 'checkmark',
      report: true,
      priority: 'normal',
    ),
    'thinking': StateConfig(
      indicator: 'spinner',
      report: false,
    ),
  };

  /// Default report templates for notification text.
  static const Map<String, String> reportTemplates = {
    'complete': 'Task completed.',
    'error': 'Error detected: {summary}',
    'question': 'Input required: {summary}',
    'thinking': 'Working...',
  };

  /// Create a synthetic [EngineProfile] using the default patterns.
  ///
  /// Used when a session has no specific engine profile configured,
  /// providing reasonable pattern matching for common CLI output.
  static EngineProfile get defaultProfile => EngineProfile(
        name: '_default',
        displayName: 'Default',
        type: 'shell',
        inputMode: 'command',
        launch: const LaunchConfig(),
        patterns: patterns,
        states: states,
        reportTemplates: reportTemplates,
      );
}

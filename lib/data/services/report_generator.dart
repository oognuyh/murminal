import 'package:murminal/data/models/detected_state.dart';
import 'package:murminal/data/models/engine_profile.dart';

/// Generates human-readable report text from a [DetectedState].
///
/// Reports are prefixed with `[REPORT]` so the Realtime voice model can
/// distinguish system monitor updates from user speech. The report body
/// is built from the engine profile's `reportTemplates` with `{summary}`
/// placeholder substitution.
class ReportGenerator {
  final EngineProfile _profile;

  const ReportGenerator(this._profile);

  /// The engine profile this generator is configured with.
  EngineProfile get profile => _profile;

  /// Generate a report string for the given [state] and [rawOutput].
  ///
  /// The returned string is always prefixed with `[REPORT]` and includes
  /// the detected state type and a human-readable description derived
  /// from the engine profile's report templates.
  ///
  /// If no template is configured for the state type, a generic fallback
  /// message is used.
  String generateReport(DetectedState state, String rawOutput) {
    final template = _profile.reportTemplates[state.type.name];
    final body = _applyTemplate(template, state);

    return '[REPORT] $body';
  }

  /// Substitute `{summary}` in the template with the detected state's
  /// summary, or fall back to a generic description if no template is
  /// available.
  String _applyTemplate(String? template, DetectedState state) {
    if (template == null) {
      return _fallbackMessage(state);
    }

    final summary = state.summary ?? state.matchedText;
    return template.replaceAll('{summary}', summary);
  }

  /// Provide a reasonable default message when no template is configured.
  String _fallbackMessage(DetectedState state) {
    return switch (state.type) {
      DetectedStateType.complete => 'Task completed.',
      DetectedStateType.error =>
        'Error detected: ${state.summary ?? state.matchedText}',
      DetectedStateType.question =>
        'Input required: ${state.summary ?? state.matchedText}',
      DetectedStateType.thinking => 'Processing...',
      DetectedStateType.idle => 'No activity.',
    };
  }
}

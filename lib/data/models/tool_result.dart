import 'dart:convert';

/// Result of executing a tool call from the Realtime voice model.
///
/// Wraps the outcome of a [ToolExecutor.execute] invocation, capturing
/// whether the call succeeded and the human-readable output or error.
class ToolResult {
  /// Name of the tool that was executed.
  final String toolName;

  /// Whether the tool executed successfully.
  final bool success;

  /// Human-readable output when [success] is true, or error message otherwise.
  final String output;

  const ToolResult({
    required this.toolName,
    required this.success,
    required this.output,
  });

  /// Convenience factory for a successful result.
  factory ToolResult.ok(String toolName, Map<String, dynamic> data) {
    return ToolResult(
      toolName: toolName,
      success: true,
      output: jsonEncode(data),
    );
  }

  /// Convenience factory for a failed result.
  factory ToolResult.error(String toolName, String message) {
    return ToolResult(
      toolName: toolName,
      success: false,
      output: jsonEncode({'error': message}),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolResult &&
          runtimeType == other.runtimeType &&
          toolName == other.toolName &&
          success == other.success &&
          output == other.output;

  @override
  int get hashCode => Object.hash(toolName, success, output);

  @override
  String toString() =>
      'ToolResult(toolName: $toolName, success: $success, '
      'output: ${output.length > 80 ? '${output.substring(0, 80)}...' : output})';
}

/// Schema definition for a tool that the Realtime voice model can invoke.
///
/// Maps to the function calling schema expected by Realtime WebSocket APIs
/// (OpenAI-compatible format used by Qwen, Gemini, and OpenAI).
class ToolDefinition {
  /// Unique name of the tool (e.g. "send_command", "switch_session").
  final String name;

  /// Human-readable description of what the tool does.
  final String description;

  /// JSON Schema describing the tool's parameters.
  ///
  /// Example:
  /// ```dart
  /// {
  ///   'type': 'object',
  ///   'properties': {
  ///     'session_id': {'type': 'string', 'description': 'Target session ID'},
  ///     'command': {'type': 'string', 'description': 'Command to execute'},
  ///   },
  ///   'required': ['session_id', 'command'],
  /// }
  /// ```
  final Map<String, dynamic> parameters;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });

  /// Converts to the JSON format expected by Realtime WebSocket APIs.
  Map<String, dynamic> toJson() => {
        'type': 'function',
        'name': name,
        'description': description,
        'parameters': parameters,
      };
}

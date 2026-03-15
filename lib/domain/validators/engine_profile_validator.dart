/// Validation logic for [EngineProfile] instances.
///
/// Provides both individual field validation and full-profile validation.
/// Validation errors are collected as a list of human-readable messages
/// so the caller can display them to the user.
class EngineProfileValidator {
  /// Required fields and their display labels.
  static const _requiredFields = ['name', 'display_name', 'type', 'input_mode'];

  /// Allowed characters for profile names (kebab-case identifiers).
  static final _namePattern = RegExp(r'^[a-z0-9][a-z0-9\-]*$');

  /// Maximum length for the profile name.
  static const _maxNameLength = 64;

  /// Maximum length for display name.
  static const _maxDisplayNameLength = 128;

  /// Validates a profile name.
  ///
  /// Returns null if valid, or an error message string.
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Name is required';
    }
    final name = value.trim();
    if (name.length > _maxNameLength) {
      return 'Name must be at most $_maxNameLength characters';
    }
    if (!_namePattern.hasMatch(name)) {
      return 'Name must be lowercase alphanumeric with hyphens (e.g. my-engine)';
    }
    return null;
  }

  /// Validates a display name.
  static String? validateDisplayName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Display name is required';
    }
    if (value.trim().length > _maxDisplayNameLength) {
      return 'Display name must be at most $_maxDisplayNameLength characters';
    }
    return null;
  }

  /// Validates the type field.
  static String? validateType(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Type is required';
    }
    return null;
  }

  /// Validates the input mode field.
  static String? validateInputMode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Input mode is required';
    }
    return null;
  }

  /// Validates a regex pattern string.
  ///
  /// Returns null if valid (including empty), or an error message.
  static String? validatePattern(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      RegExp(value.trim());
      return null;
    } on FormatException catch (e) {
      return 'Invalid regex: ${e.message}';
    }
  }

  /// Validates a complete profile JSON map.
  ///
  /// Returns a list of error messages. Empty list means valid.
  static List<String> validateProfileJson(Map<String, dynamic> json) {
    final errors = <String>[];

    // Check required fields.
    for (final field in _requiredFields) {
      if (!json.containsKey(field) || json[field] == null) {
        errors.add('Missing required field: $field');
      } else if (json[field] is! String || (json[field] as String).isEmpty) {
        errors.add('Field "$field" must be a non-empty string');
      }
    }

    // Validate name format if present.
    if (json.containsKey('name') && json['name'] is String) {
      final nameError = validateName(json['name'] as String);
      if (nameError != null) errors.add(nameError);
    }

    // Validate patterns are valid regex.
    if (json.containsKey('patterns') && json['patterns'] is Map) {
      final patterns = json['patterns'] as Map;
      for (final entry in patterns.entries) {
        if (entry.value is String) {
          final patternError = validatePattern(entry.value as String);
          if (patternError != null) {
            errors.add('Pattern "${entry.key}": $patternError');
          }
        }
      }
    }

    // Validate states structure.
    if (json.containsKey('states') && json['states'] is Map) {
      final states = json['states'] as Map;
      for (final entry in states.entries) {
        if (entry.value is! Map) {
          errors.add('State "${entry.key}" must be an object');
        } else {
          final state = entry.value as Map;
          if (!state.containsKey('indicator')) {
            errors.add('State "${entry.key}" is missing "indicator" field');
          }
        }
      }
    }

    return errors;
  }
}

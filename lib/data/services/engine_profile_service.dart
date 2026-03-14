import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:murminal/data/models/engine_profile.dart';

/// Service for loading and managing engine profiles.
///
/// Loads bundled profiles from `assets/profiles/` and provides
/// lookup and enumeration of available engines.
class EngineProfileService {
  final Map<String, EngineProfile> _profiles = {};

  /// All loaded engine profiles.
  List<EngineProfile> get availableEngines => _profiles.values.toList();

  /// Retrieve a profile by its unique name.
  EngineProfile? getProfile(String name) => _profiles[name];

  /// Load all bundled engine profiles from assets.
  ///
  /// Reads the asset manifest to discover profile JSON files,
  /// parses each one, and registers it in the internal map.
  Future<void> loadProfiles() async {
    _profiles.clear();

    final manifestJson = await rootBundle.loadString('AssetManifest.json');
    final manifest = json.decode(manifestJson) as Map<String, dynamic>;

    final profilePaths = manifest.keys
        .where((key) => key.startsWith('assets/profiles/') && key.endsWith('.json'));

    for (final path in profilePaths) {
      try {
        final content = await rootBundle.loadString(path);
        final jsonData = json.decode(content) as Map<String, dynamic>;
        final profile = EngineProfile.fromJson(jsonData);
        _profiles[profile.name] = profile;
      } on FormatException {
        // Skip malformed profile files.
      }
    }
  }

  /// Load a single profile from a JSON string.
  ///
  /// Useful for loading user-provided custom profiles.
  EngineProfile loadFromString(String jsonString) {
    final jsonData = json.decode(jsonString) as Map<String, dynamic>;
    final profile = EngineProfile.fromJson(jsonData);
    _profiles[profile.name] = profile;
    return profile;
  }

  /// Detect the current engine state from terminal output.
  ///
  /// Matches patterns in priority order: question > error > complete >
  /// thinking > ready, as defined in the engine profile schema.
  EngineState detectState(EngineProfile profile, String output) {
    if (_matchesPattern(output, profile.patterns['question'])) {
      return EngineState.needsInput;
    }
    if (_matchesPattern(output, profile.patterns['error'])) {
      return EngineState.error;
    }
    if (_matchesPattern(output, profile.patterns['complete'])) {
      return EngineState.done;
    }
    if (_matchesPattern(output, profile.patterns['thinking'])) {
      return EngineState.working;
    }
    if (_matchesPattern(output, profile.patterns['ready'])) {
      return EngineState.idle;
    }
    return EngineState.unknown;
  }

  /// Format a report template with context substitution.
  ///
  /// Replaces `{context}` placeholder in the template with the
  /// provided context string.
  String formatReport(EngineProfile profile, String stateKey, String context) {
    final template = profile.reportTemplates[stateKey];
    if (template == null) return context;
    return template.replaceAll('{context}', context);
  }

  bool _matchesPattern(String output, String? pattern) {
    if (pattern == null) return false;
    return RegExp(pattern).hasMatch(output);
  }
}

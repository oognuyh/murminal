import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:murminal/data/models/engine_profile.dart';

/// Required top-level fields for a valid engine profile JSON.
const _requiredFields = ['name', 'display_name', 'type', 'input_mode'];

/// Registry that manages [EngineProfile] instances.
///
/// Profiles can be loaded from bundled JSON assets at startup or
/// registered/unregistered at runtime. Each profile is keyed by its
/// unique [EngineProfile.name].
class EngineRegistry {
  final Map<String, EngineProfile> _profiles = {};

  /// All currently registered profiles.
  List<EngineProfile> get profiles => List.unmodifiable(_profiles.values.toList());

  /// Loads bundled profile JSON files from `assets/profiles/`.
  ///
  /// Reads the asset manifest to discover profile files, validates
  /// each against the required schema, and registers valid profiles.
  /// Throws [FormatException] if a profile fails schema validation.
  Future<void> loadBundledProfiles(AssetBundle bundle) async {
    final manifestJson = await bundle.loadString('AssetManifest.json');
    final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;

    final profileKeys = manifest.keys
        .where((key) => key.startsWith('assets/profiles/') && key.endsWith('.json'));

    for (final key in profileKeys) {
      final jsonString = await bundle.loadString(key);
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      _validateSchema(json, key);
      final profile = EngineProfile.fromJson(json);
      _profiles[profile.name] = profile;
    }
  }

  /// Registers a profile at runtime.
  ///
  /// If a profile with the same name already exists, it is replaced.
  void register(EngineProfile profile) {
    _profiles[profile.name] = profile;
  }

  /// Removes the profile with the given [name].
  ///
  /// Returns `true` if a profile was removed, `false` if no profile
  /// with that name was registered.
  bool unregister(String name) {
    return _profiles.remove(name) != null;
  }

  /// Returns the profile registered under [name], or `null` if none.
  EngineProfile? getProfile(String name) {
    return _profiles[name];
  }

  /// Validates that [json] contains all required top-level fields.
  ///
  /// Throws [FormatException] listing missing fields when validation fails.
  void _validateSchema(Map<String, dynamic> json, String source) {
    final missing = _requiredFields.where((f) => !json.containsKey(f)).toList();
    if (missing.isNotEmpty) {
      throw FormatException(
        'Invalid engine profile ($source): missing fields: ${missing.join(', ')}',
      );
    }
  }
}

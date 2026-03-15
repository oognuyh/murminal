import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:murminal/data/models/engine_profile.dart';

/// Persistence key for user-created engine profiles.
const _kStorageKey = 'user_engine_profiles';

/// Repository for persisting user-created engine profiles.
///
/// Bundled profiles are managed by [EngineRegistry] and loaded from
/// assets. This repository handles only user-created/customized profiles
/// stored in [SharedPreferences].
class EngineProfileRepository {
  final SharedPreferences _prefs;

  EngineProfileRepository(this._prefs);

  /// Returns all user-created profiles.
  List<EngineProfile> getAll() {
    final raw = _prefs.getStringList(_kStorageKey) ?? [];
    final profiles = <EngineProfile>[];
    for (final jsonStr in raw) {
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        profiles.add(EngineProfile.fromJson(json));
      } on FormatException {
        // Skip malformed entries.
      }
    }
    return profiles;
  }

  /// Saves a user profile. Replaces any existing profile with the same name.
  Future<void> save(EngineProfile profile) async {
    final profiles = getAll();
    final index = profiles.indexWhere((p) => p.name == profile.name);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }
    await _persist(profiles);
  }

  /// Deletes the user profile with the given [name].
  ///
  /// Returns `true` if a profile was removed.
  Future<bool> delete(String name) async {
    final profiles = getAll();
    final lengthBefore = profiles.length;
    profiles.removeWhere((p) => p.name == name);
    await _persist(profiles);
    return profiles.length < lengthBefore;
  }

  /// Returns the JSON string representation of a profile for export.
  String export(EngineProfile profile) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(profile.toJson());
  }

  /// Imports a profile from a JSON string.
  ///
  /// Throws [FormatException] if the JSON is invalid or missing required fields.
  EngineProfile import_(String jsonString) {
    return EngineProfile.parse(jsonString);
  }

  /// Removes all user profiles, resetting to defaults (bundled only).
  Future<void> resetToDefaults() async {
    await _prefs.remove(_kStorageKey);
  }

  Future<void> _persist(List<EngineProfile> profiles) async {
    final raw = profiles
        .map((p) => jsonEncode(p.toJson()))
        .toList();
    await _prefs.setStringList(_kStorageKey, raw);
  }
}

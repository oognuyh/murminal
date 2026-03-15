import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:murminal/data/models/engine_profile.dart';
import 'package:murminal/domain/validators/engine_profile_validator.dart';

/// Legacy persistence key for user-created engine profiles.
///
/// Used only during migration from SharedPreferences to file-based storage.
const _kLegacyStorageKey = 'user_engine_profiles';

/// Subdirectory name under the app documents directory.
const _kProfilesDir = 'user_profiles';

/// Repository for persisting user-created engine profiles.
///
/// Bundled profiles are managed by [EngineRegistry] and loaded from
/// assets. This repository handles only user-created/customized profiles
/// stored as individual JSON files in the app documents directory.
///
/// On first access, any profiles previously stored in [SharedPreferences]
/// are migrated to the file system automatically.
class EngineProfileRepository {
  final SharedPreferences _prefs;
  final Directory _profilesDir;

  /// In-memory cache of loaded profiles, populated on first [getAll] call.
  List<EngineProfile>? _cache;

  EngineProfileRepository._({
    required SharedPreferences prefs,
    required Directory profilesDir,
  })  : _prefs = prefs,
        _profilesDir = profilesDir;

  /// Creates a repository with the given [prefs] and [documentsPath].
  ///
  /// User profiles are stored as JSON files under
  /// `<documentsPath>/user_profiles/`.
  factory EngineProfileRepository({
    required SharedPreferences prefs,
    required String documentsPath,
  }) {
    final dir = Directory(p.join(documentsPath, _kProfilesDir));
    return EngineProfileRepository._(prefs: prefs, profilesDir: dir);
  }

  /// Returns all user-created profiles.
  ///
  /// On the first call, migrates any legacy SharedPreferences data
  /// to the file system and loads profiles from disk.
  List<EngineProfile> getAll() {
    if (_cache != null) return List.unmodifiable(_cache!);

    _ensureDir();
    _migrateLegacyIfNeeded();
    _cache = _loadFromDisk();
    return List.unmodifiable(_cache!);
  }

  /// Saves a user profile after validation.
  ///
  /// Replaces any existing profile with the same name.
  /// Throws [ProfileValidationException] if the profile is invalid.
  Future<void> save(EngineProfile profile) async {
    final errors = EngineProfileValidator.validateProfileJson(profile.toJson());
    if (errors.isNotEmpty) {
      throw ProfileValidationException(errors);
    }

    _ensureDir();
    final file = _fileForProfile(profile.name);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(profile.toJson()));
    _invalidateCache();
  }

  /// Deletes the user profile with the given [name].
  ///
  /// Returns `true` if a profile was removed.
  Future<bool> delete(String name) async {
    final file = _fileForProfile(name);
    if (await file.exists()) {
      await file.delete();
      _invalidateCache();
      return true;
    }
    return false;
  }

  /// Returns the JSON string representation of a profile for export.
  String export(EngineProfile profile) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(profile.toJson());
  }

  /// Imports a profile from a JSON string.
  ///
  /// Validates the JSON structure before returning the parsed profile.
  /// Throws [FormatException] if the JSON is invalid.
  /// Throws [ProfileValidationException] if validation fails.
  EngineProfile import_(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    final errors = EngineProfileValidator.validateProfileJson(json);
    if (errors.isNotEmpty) {
      throw ProfileValidationException(errors);
    }
    return EngineProfile.fromJson(json);
  }

  /// Removes all user profiles, resetting to defaults (bundled only).
  Future<void> resetToDefaults() async {
    if (await _profilesDir.exists()) {
      final files = _profilesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'));
      for (final file in files) {
        await file.delete();
      }
    }
    _invalidateCache();
  }

  /// Returns the file path for a profile by name.
  File _fileForProfile(String name) {
    // Sanitize the name for safe file system usage.
    final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9\-_]'), '_');
    return File(p.join(_profilesDir.path, '$safeName.json'));
  }

  /// Ensures the profiles directory exists.
  void _ensureDir() {
    if (!_profilesDir.existsSync()) {
      _profilesDir.createSync(recursive: true);
    }
  }

  /// Migrates profiles from SharedPreferences to file system.
  ///
  /// Only runs once; removes the legacy key after successful migration.
  void _migrateLegacyIfNeeded() {
    final raw = _prefs.getStringList(_kLegacyStorageKey);
    if (raw == null || raw.isEmpty) return;

    for (final jsonStr in raw) {
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        final profile = EngineProfile.fromJson(json);
        final file = _fileForProfile(profile.name);
        if (!file.existsSync()) {
          const encoder = JsonEncoder.withIndent('  ');
          file.writeAsStringSync(encoder.convert(profile.toJson()));
        }
      } on FormatException {
        // Skip malformed legacy entries.
      }
    }

    // Remove legacy data after migration.
    _prefs.remove(_kLegacyStorageKey);
  }

  /// Loads all profile JSON files from the profiles directory.
  List<EngineProfile> _loadFromDisk() {
    if (!_profilesDir.existsSync()) return [];

    final profiles = <EngineProfile>[];
    final files = _profilesDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'));

    for (final file in files) {
      try {
        final jsonStr = file.readAsStringSync();
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        profiles.add(EngineProfile.fromJson(json));
      } on FormatException {
        // Skip malformed files.
      } on FileSystemException {
        // Skip unreadable files.
      }
    }
    return profiles;
  }

  /// Clears the in-memory cache so the next [getAll] reloads from disk.
  void _invalidateCache() {
    _cache = null;
  }
}

/// Exception thrown when profile validation fails.
///
/// Contains a list of human-readable error messages.
class ProfileValidationException implements Exception {
  final List<String> errors;

  const ProfileValidationException(this.errors);

  @override
  String toString() => 'Profile validation failed:\n${errors.join('\n')}';
}

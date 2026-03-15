import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:murminal/data/models/engine_profile.dart';
import 'package:murminal/data/repositories/engine_profile_repository.dart';

/// Creates a minimal valid [EngineProfile] for testing.
EngineProfile _makeProfile({
  String name = 'test-engine',
  String displayName = 'Test Engine',
  String type = 'chat-tui',
  String inputMode = 'natural_language',
}) {
  return EngineProfile(
    name: name,
    displayName: displayName,
    type: type,
    inputMode: inputMode,
    launch: const LaunchConfig(),
  );
}

void main() {
  late EngineProfileRepository repo;
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tempDir = await Directory.systemTemp.createTemp('engine_profile_test_');
    repo = EngineProfileRepository(
      prefs: prefs,
      documentsPath: tempDir.path,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('getAll', () {
    test('returns empty list when no profiles are saved', () {
      expect(repo.getAll(), isEmpty);
    });

    test('returns saved profiles', () async {
      await repo.save(_makeProfile(name: 'alpha'));
      await repo.save(_makeProfile(name: 'beta'));

      // Create new repo instance to force reload from disk.
      final prefs = await SharedPreferences.getInstance();
      final freshRepo = EngineProfileRepository(
        prefs: prefs,
        documentsPath: tempDir.path,
      );
      final profiles = freshRepo.getAll();
      final names = profiles.map((p) => p.name).toSet();
      expect(names, {'alpha', 'beta'});
    });
  });

  group('save', () {
    test('adds a new profile as a JSON file', () async {
      await repo.save(_makeProfile(name: 'new-engine'));

      final profiles = repo.getAll();
      expect(profiles.length, 1);
      expect(profiles.first.name, 'new-engine');

      // Verify file exists on disk.
      final file = File('${tempDir.path}/user_profiles/new-engine.json');
      expect(file.existsSync(), isTrue);
    });

    test('replaces existing profile with same name', () async {
      await repo.save(_makeProfile(name: 'engine', displayName: 'V1'));
      await repo.save(_makeProfile(name: 'engine', displayName: 'V2'));

      final profiles = repo.getAll();
      expect(profiles.length, 1);
      expect(profiles.first.displayName, 'V2');
    });

    test('preserves other profiles when updating', () async {
      await repo.save(_makeProfile(name: 'a'));
      await repo.save(_makeProfile(name: 'b'));
      await repo.save(_makeProfile(name: 'a', displayName: 'Updated'));

      final profiles = repo.getAll();
      expect(profiles.length, 2);
      final a = profiles.firstWhere((p) => p.name == 'a');
      expect(a.displayName, 'Updated');
    });

    test('throws ProfileValidationException for invalid profile', () async {
      final invalid = EngineProfile(
        name: '', // Empty name is invalid.
        displayName: 'Test',
        type: 'chat-tui',
        inputMode: 'natural_language',
        launch: const LaunchConfig(),
      );

      expect(
        () => repo.save(invalid),
        throwsA(isA<ProfileValidationException>()),
      );
    });

    test('validates regex patterns on save', () async {
      final invalidPattern = EngineProfile(
        name: 'bad-regex',
        displayName: 'Bad Regex',
        type: 'chat-tui',
        inputMode: 'natural_language',
        launch: const LaunchConfig(),
        patterns: {'broken': '[invalid'}, // Unclosed bracket.
      );

      expect(
        () => repo.save(invalidPattern),
        throwsA(isA<ProfileValidationException>()),
      );
    });
  });

  group('delete', () {
    test('removes the profile file', () async {
      await repo.save(_makeProfile(name: 'to-delete'));
      final result = await repo.delete('to-delete');

      expect(result, isTrue);
      expect(repo.getAll(), isEmpty);

      final file = File('${tempDir.path}/user_profiles/to-delete.json');
      expect(file.existsSync(), isFalse);
    });

    test('returns false when profile does not exist', () async {
      final result = await repo.delete('nonexistent');
      expect(result, isFalse);
    });

    test('preserves other profiles when deleting', () async {
      await repo.save(_makeProfile(name: 'keep'));
      await repo.save(_makeProfile(name: 'remove'));
      await repo.delete('remove');

      final profiles = repo.getAll();
      expect(profiles.length, 1);
      expect(profiles.first.name, 'keep');
    });
  });

  group('export', () {
    test('returns valid JSON string', () {
      final profile = _makeProfile();
      final json = repo.export(profile);

      final parsed = jsonDecode(json) as Map<String, dynamic>;
      expect(parsed['name'], 'test-engine');
      expect(parsed['display_name'], 'Test Engine');
    });

    test('produces formatted JSON with indentation', () {
      final profile = _makeProfile();
      final json = repo.export(profile);

      // Indented JSON contains newlines.
      expect(json, contains('\n'));
    });
  });

  group('import_', () {
    test('parses valid JSON into EngineProfile', () {
      final jsonStr = jsonEncode({
        'name': 'imported',
        'display_name': 'Imported Engine',
        'type': 'shell',
        'input_mode': 'command',
      });

      final profile = repo.import_(jsonStr);
      expect(profile.name, 'imported');
      expect(profile.displayName, 'Imported Engine');
    });

    test('throws FormatException for invalid JSON', () {
      expect(() => repo.import_('not json'), throwsA(isA<FormatException>()));
    });

    test('throws ProfileValidationException for missing fields', () {
      final jsonStr = jsonEncode({'name': 'incomplete'});
      expect(
        () => repo.import_(jsonStr),
        throwsA(isA<ProfileValidationException>()),
      );
    });
  });

  group('resetToDefaults', () {
    test('removes all saved profile files', () async {
      await repo.save(_makeProfile(name: 'custom-1'));
      await repo.save(_makeProfile(name: 'custom-2'));

      await repo.resetToDefaults();

      expect(repo.getAll(), isEmpty);

      // Verify directory is empty.
      final dir = Directory('${tempDir.path}/user_profiles');
      final files = dir.listSync().whereType<File>().toList();
      expect(files, isEmpty);
    });
  });

  group('legacy migration', () {
    test('migrates profiles from SharedPreferences to files', () async {
      final legacyProfile = _makeProfile(name: 'legacy-engine');
      final legacyJson = jsonEncode(legacyProfile.toJson());

      SharedPreferences.setMockInitialValues({
        'user_engine_profiles': [legacyJson],
      });
      final prefs = await SharedPreferences.getInstance();
      final migratingRepo = EngineProfileRepository(
        prefs: prefs,
        documentsPath: tempDir.path,
      );

      final profiles = migratingRepo.getAll();
      expect(profiles.length, 1);
      expect(profiles.first.name, 'legacy-engine');

      // Verify file was created.
      final file = File('${tempDir.path}/user_profiles/legacy-engine.json');
      expect(file.existsSync(), isTrue);

      // Verify legacy key was removed.
      expect(prefs.getStringList('user_engine_profiles'), isNull);
    });
  });

  group('round-trip', () {
    test('export then import preserves profile data', () {
      final original = EngineProfile(
        name: 'roundtrip',
        displayName: 'Round Trip',
        type: 'chat-tui',
        inputMode: 'natural_language',
        launch: const LaunchConfig(
          command: 'claude',
          flags: ['--verbose'],
        ),
        patterns: {'error': r'Error:.*', 'complete': r'Done'},
        states: {
          'error': const StateConfig(
            indicator: 'error_text',
            report: true,
            priority: 'high',
          ),
        },
        reportTemplates: {'error': 'Error: {summary}'},
      );

      final json = repo.export(original);
      final imported = repo.import_(json);

      expect(imported.name, original.name);
      expect(imported.displayName, original.displayName);
      expect(imported.type, original.type);
      expect(imported.inputMode, original.inputMode);
      expect(imported.launch.command, original.launch.command);
      expect(imported.launch.flags, original.launch.flags);
      expect(imported.patterns, original.patterns);
      expect(imported.states.keys, original.states.keys);
      expect(imported.reportTemplates, original.reportTemplates);
    });
  });
}

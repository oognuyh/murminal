import 'dart:convert';

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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = EngineProfileRepository(prefs);
  });

  group('getAll', () {
    test('returns empty list when no profiles are saved', () {
      expect(repo.getAll(), isEmpty);
    });

    test('returns saved profiles', () async {
      await repo.save(_makeProfile(name: 'alpha'));
      await repo.save(_makeProfile(name: 'beta'));

      final profiles = repo.getAll();
      final names = profiles.map((p) => p.name).toSet();
      expect(names, {'alpha', 'beta'});
    });
  });

  group('save', () {
    test('adds a new profile', () async {
      await repo.save(_makeProfile(name: 'new-engine'));

      final profiles = repo.getAll();
      expect(profiles.length, 1);
      expect(profiles.first.name, 'new-engine');
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
  });

  group('delete', () {
    test('removes the profile by name', () async {
      await repo.save(_makeProfile(name: 'to-delete'));
      await repo.delete('to-delete');

      expect(repo.getAll(), isEmpty);
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
  });

  group('resetToDefaults', () {
    test('removes all saved profiles', () async {
      await repo.save(_makeProfile(name: 'custom-1'));
      await repo.save(_makeProfile(name: 'custom-2'));

      await repo.resetToDefaults();

      expect(repo.getAll(), isEmpty);
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

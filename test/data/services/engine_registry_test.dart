import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/engine_profile.dart';
import 'package:murminal/data/services/engine_registry.dart';

/// Minimal valid profile JSON for testing.
Map<String, dynamic> _validProfileJson({
  String name = 'test-engine',
  String displayName = 'Test Engine',
  String type = 'chat-tui',
  String inputMode = 'natural_language',
}) =>
    {
      'name': name,
      'display_name': displayName,
      'type': type,
      'input_mode': inputMode,
    };

/// Creates an [EngineProfile] from minimal fields for test convenience.
EngineProfile _makeProfile({
  String name = 'test-engine',
  String displayName = 'Test Engine',
}) =>
    EngineProfile.fromJson(_validProfileJson(
      name: name,
      displayName: displayName,
    ));

void main() {
  late EngineRegistry registry;

  setUp(() {
    registry = EngineRegistry();
  });

  group('register / unregister', () {
    test('register adds a profile retrievable by name', () {
      final profile = _makeProfile();
      registry.register(profile);

      expect(registry.getProfile('test-engine'), equals(profile));
    });

    test('register replaces an existing profile with the same name', () {
      final v1 = _makeProfile(displayName: 'V1');
      final v2 = _makeProfile(displayName: 'V2');

      registry.register(v1);
      registry.register(v2);

      expect(registry.getProfile('test-engine')?.displayName, 'V2');
      expect(registry.profiles.length, 1);
    });

    test('unregister removes a registered profile and returns true', () {
      registry.register(_makeProfile());
      final removed = registry.unregister('test-engine');

      expect(removed, isTrue);
      expect(registry.getProfile('test-engine'), isNull);
    });

    test('unregister returns false for unknown name', () {
      expect(registry.unregister('nonexistent'), isFalse);
    });
  });

  group('getProfile', () {
    test('returns null for unregistered name', () {
      expect(registry.getProfile('missing'), isNull);
    });

    test('returns correct profile among multiple registrations', () {
      final a = _makeProfile(name: 'alpha', displayName: 'Alpha');
      final b = _makeProfile(name: 'beta', displayName: 'Beta');
      registry.register(a);
      registry.register(b);

      expect(registry.getProfile('alpha')?.displayName, 'Alpha');
      expect(registry.getProfile('beta')?.displayName, 'Beta');
    });
  });

  group('profiles', () {
    test('returns empty list when nothing is registered', () {
      expect(registry.profiles, isEmpty);
    });

    test('returns all registered profiles', () {
      registry.register(_makeProfile(name: 'a'));
      registry.register(_makeProfile(name: 'b'));
      registry.register(_makeProfile(name: 'c'));

      final names = registry.profiles.map((p) => p.name).toSet();
      expect(names, {'a', 'b', 'c'});
    });

    test('returned list is unmodifiable', () {
      registry.register(_makeProfile());
      final list = registry.profiles;

      expect(() => list.add(_makeProfile(name: 'hack')), throwsUnsupportedError);
    });
  });

  group('loadBundledProfiles', () {
    late _FakeAssetBundle bundle;

    test('loads profiles from asset manifest', () async {
      final profileJson = _validProfileJson(name: 'bundled');
      bundle = _FakeAssetBundle({
        'assets/profiles/bundled.json': jsonEncode(profileJson),
      });

      await registry.loadBundledProfiles(bundle);

      expect(registry.getProfile('bundled'), isNotNull);
      expect(registry.getProfile('bundled')?.displayName, 'Test Engine');
    });

    test('loads multiple profiles', () async {
      bundle = _FakeAssetBundle({
        'assets/profiles/a.json':
            jsonEncode(_validProfileJson(name: 'a')),
        'assets/profiles/b.json':
            jsonEncode(_validProfileJson(name: 'b')),
      });

      await registry.loadBundledProfiles(bundle);

      expect(registry.profiles.length, 2);
    });

    test('ignores non-profile asset keys', () async {
      bundle = _FakeAssetBundle({
        'assets/profiles/valid.json':
            jsonEncode(_validProfileJson(name: 'valid')),
        'assets/images/logo.png': '', // not a profile path
        'other/file.json': '', // not under profiles/
      });

      await registry.loadBundledProfiles(bundle);

      expect(registry.profiles.length, 1);
      expect(registry.getProfile('valid'), isNotNull);
    });

    test('records error for missing required fields', () async {
      final invalidJson = {'name': 'incomplete'};
      bundle = _FakeAssetBundle({
        'assets/profiles/bad.json': jsonEncode(invalidJson),
      });

      await registry.loadBundledProfiles(bundle);

      expect(registry.profiles, isEmpty);
      expect(registry.loadErrors, hasLength(1));
    });

    test('records error listing all missing fields', () async {
      // Missing display_name, type, input_mode
      final json = {'name': 'only-name'};
      bundle = _FakeAssetBundle({
        'assets/profiles/bad.json': jsonEncode(json),
      });

      await registry.loadBundledProfiles(bundle);

      expect(registry.profiles, isEmpty);
      final error = registry.loadErrors['assets/profiles/bad.json']!;
      expect(error, contains('display_name'));
      expect(error, contains('type'));
      expect(error, contains('input_mode'));
    });
  });
}

/// Fake [AssetBundle] that serves in-memory assets for testing.
class _FakeAssetBundle extends CachingAssetBundle {
  final Map<String, String> _assets;

  _FakeAssetBundle(this._assets);

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key == 'AssetManifest.json') {
      // Build a manifest with all registered asset keys.
      final manifest = {
        for (final k in _assets.keys) k: [k],
      };
      return jsonEncode(manifest);
    }
    if (_assets.containsKey(key)) {
      return _assets[key]!;
    }
    throw Exception('Asset not found: $key');
  }

  @override
  Future<ByteData> load(String key) async {
    throw UnimplementedError('load() not used in these tests');
  }
}

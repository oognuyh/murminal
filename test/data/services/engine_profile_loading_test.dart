import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/models/engine_profile.dart';
import 'package:murminal/data/services/engine_registry.dart';

/// Full profile JSON including patterns and states.
Map<String, dynamic> _fullProfileJson({
  String name = 'test-engine',
  Map<String, dynamic>? patterns,
}) =>
    {
      'name': name,
      'display_name': 'Test Engine',
      'type': 'chat-tui',
      'input_mode': 'natural_language',
      'launch': {'command': 'test-cmd', 'flags': ['--verbose'], 'env': {}},
      'patterns': patterns ??
          {
            'prompt': r'❯\s',
            'error': r'Error:|FAIL',
            'thinking': null,
          },
      'states': {
        'error': {'indicator': 'error_text', 'report': true, 'priority': 'high'},
      },
      'report_templates': {
        'error': 'Something went wrong: {summary}',
      },
    };

void main() {
  group('EngineProfile.fromJson', () {
    test('parses all fields from valid JSON', () {
      final json = _fullProfileJson();
      final profile = EngineProfile.fromJson(json);

      expect(profile.name, 'test-engine');
      expect(profile.displayName, 'Test Engine');
      expect(profile.type, 'chat-tui');
      expect(profile.inputMode, 'natural_language');
      expect(profile.launch.command, 'test-cmd');
      expect(profile.launch.flags, ['--verbose']);
      expect(profile.patterns['prompt'], r'❯\s');
      expect(profile.states['error']?.report, isTrue);
      expect(profile.reportTemplates['error'], contains('{summary}'));
    });

    test('compiles regex patterns at parse time', () {
      final json = _fullProfileJson(patterns: {
        'prompt': r'❯\s',
        'error': r'Error:|FAIL',
      });
      final profile = EngineProfile.fromJson(json);

      expect(profile.compiledPatterns, hasLength(2));
      expect(profile.compiledPatterns['prompt'], isA<RegExp>());
      expect(profile.compiledPatterns['error'], isA<RegExp>());

      // Verify the compiled patterns actually match expected text.
      expect(profile.compiledPatterns['prompt']!.hasMatch('❯ '), isTrue);
      expect(profile.compiledPatterns['error']!.hasMatch('Error: bad'), isTrue);
      expect(profile.compiledPatterns['error']!.hasMatch('FAIL'), isTrue);
      expect(profile.compiledPatterns['error']!.hasMatch('all good'), isFalse);
    });

    test('skips null pattern values during compilation', () {
      final json = _fullProfileJson(patterns: {
        'active': r'\$\s*$',
        'inactive': null,
      });
      final profile = EngineProfile.fromJson(json);

      expect(profile.compiledPatterns, hasLength(1));
      expect(profile.compiledPatterns.containsKey('active'), isTrue);
      expect(profile.compiledPatterns.containsKey('inactive'), isFalse);
    });

    test('skips invalid regex patterns gracefully', () {
      final json = _fullProfileJson(patterns: {
        'good': r'hello',
        'bad': r'[invalid(regex',
      });
      final profile = EngineProfile.fromJson(json);

      expect(profile.compiledPatterns, hasLength(1));
      expect(profile.compiledPatterns.containsKey('good'), isTrue);
      expect(profile.compiledPatterns.containsKey('bad'), isFalse);
    });

    test('returns empty compiledPatterns when no patterns provided', () {
      final json = _fullProfileJson(patterns: {});
      final profile = EngineProfile.fromJson(json);

      expect(profile.compiledPatterns, isEmpty);
    });

    test('defaults to empty launch config when launch is absent', () {
      final json = _fullProfileJson()..remove('launch');
      final profile = EngineProfile.fromJson(json);

      expect(profile.launch.command, isNull);
      expect(profile.launch.flags, isEmpty);
    });
  });

  group('EngineProfile.parse', () {
    test('parses a JSON string into EngineProfile', () {
      final jsonString = jsonEncode(_fullProfileJson(name: 'parsed'));
      final profile = EngineProfile.parse(jsonString);

      expect(profile.name, 'parsed');
      expect(profile.compiledPatterns, isNotEmpty);
    });

    test('throws FormatException for invalid JSON string', () {
      expect(
        () => EngineProfile.parse('not valid json'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('EngineRegistry.loadBundledProfiles', () {
    late EngineRegistry registry;

    setUp(() {
      registry = EngineRegistry();
    });

    test('loads profile with compiled patterns from bundle', () async {
      final bundle = _FakeAssetBundle({
        'assets/profiles/engine.json': jsonEncode(_fullProfileJson()),
      });

      await registry.loadBundledProfiles(bundle);

      final profile = registry.getProfile('test-engine');
      expect(profile, isNotNull);
      expect(profile!.compiledPatterns, isNotEmpty);
      expect(profile.compiledPatterns['prompt'], isA<RegExp>());
    });

    test('records error for malformed JSON and continues loading', () async {
      final bundle = _FakeAssetBundle({
        'assets/profiles/good.json':
            jsonEncode(_fullProfileJson(name: 'good')),
        'assets/profiles/bad.json': '{ not valid json }}}',
      });

      await registry.loadBundledProfiles(bundle);

      expect(registry.getProfile('good'), isNotNull);
      expect(registry.loadErrors, hasLength(1));
      expect(registry.loadErrors.keys.first, 'assets/profiles/bad.json');
    });

    test('records error for profile missing required fields', () async {
      final bundle = _FakeAssetBundle({
        'assets/profiles/incomplete.json': jsonEncode({'name': 'only-name'}),
      });

      await registry.loadBundledProfiles(bundle);

      expect(registry.profiles, isEmpty);
      expect(registry.loadErrors, hasLength(1));
      expect(
        registry.loadErrors['assets/profiles/incomplete.json'],
        contains('display_name'),
      );
    });

    test('records error for wrong field types', () async {
      final bundle = _FakeAssetBundle({
        'assets/profiles/bad-types.json': jsonEncode({
          'name': 123, // should be String
          'display_name': 'Test',
          'type': 'raw',
          'input_mode': 'command',
        }),
      });

      await registry.loadBundledProfiles(bundle);

      expect(registry.profiles, isEmpty);
      expect(registry.loadErrors, hasLength(1));
    });

    test('loads real bundled profile format (claude-code style)', () async {
      final claudeProfile = {
        'name': 'claude-code',
        'display_name': 'Claude Code',
        'type': 'chat-tui',
        'input_mode': 'natural_language',
        'launch': {'command': 'claude', 'flags': <String>[], 'env': {}},
        'patterns': {
          'prompt': r'❯\s|^\$\s',
          'thinking': '⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏',
          'complete': '✓|✔|Done|Complete',
          'error': 'Error:|error:|ERR!|FAIL|Failed',
          'question': r'\(y\/n\)|\(Y\/n\)|Yes\/No|Continue\?',
        },
        'states': {
          'thinking': {'indicator': 'spinner', 'report': false},
          'complete': {
            'indicator': 'checkmark',
            'report': true,
            'priority': 'normal',
          },
        },
        'report_templates': {
          'complete': 'Task completed successfully',
          'error': 'Error encountered: {summary}',
        },
      };

      final bundle = _FakeAssetBundle({
        'assets/profiles/claude-code.json': jsonEncode(claudeProfile),
      });

      await registry.loadBundledProfiles(bundle);

      final profile = registry.getProfile('claude-code');
      expect(profile, isNotNull);
      expect(profile!.compiledPatterns, hasLength(5));
      expect(
        profile.compiledPatterns['thinking']!.hasMatch('⠋'),
        isTrue,
      );
      expect(
        profile.compiledPatterns['question']!.hasMatch('(y/n)'),
        isTrue,
      );
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

import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/domain/validators/engine_profile_validator.dart';

void main() {
  group('validateName', () {
    test('returns null for valid kebab-case name', () {
      expect(EngineProfileValidator.validateName('my-engine'), isNull);
      expect(EngineProfileValidator.validateName('claude-code'), isNull);
      expect(EngineProfileValidator.validateName('engine1'), isNull);
      expect(EngineProfileValidator.validateName('a'), isNull);
    });

    test('returns error for empty name', () {
      expect(EngineProfileValidator.validateName(''), isNotNull);
      expect(EngineProfileValidator.validateName(null), isNotNull);
      expect(EngineProfileValidator.validateName('  '), isNotNull);
    });

    test('returns error for uppercase characters', () {
      expect(EngineProfileValidator.validateName('MyEngine'), isNotNull);
    });

    test('returns error for spaces', () {
      expect(EngineProfileValidator.validateName('my engine'), isNotNull);
    });

    test('returns error for leading hyphen', () {
      expect(EngineProfileValidator.validateName('-engine'), isNotNull);
    });

    test('returns error for names exceeding max length', () {
      final longName = 'a' * 65;
      expect(EngineProfileValidator.validateName(longName), isNotNull);
    });

    test('accepts name at max length', () {
      final maxName = 'a' * 64;
      expect(EngineProfileValidator.validateName(maxName), isNull);
    });
  });

  group('validateDisplayName', () {
    test('returns null for valid display name', () {
      expect(EngineProfileValidator.validateDisplayName('My Engine'), isNull);
    });

    test('returns error for empty display name', () {
      expect(EngineProfileValidator.validateDisplayName(''), isNotNull);
      expect(EngineProfileValidator.validateDisplayName(null), isNotNull);
    });

    test('returns error for exceeding max length', () {
      final longName = 'A' * 129;
      expect(EngineProfileValidator.validateDisplayName(longName), isNotNull);
    });
  });

  group('validateType', () {
    test('returns null for non-empty type', () {
      expect(EngineProfileValidator.validateType('chat-tui'), isNull);
    });

    test('returns error for empty type', () {
      expect(EngineProfileValidator.validateType(''), isNotNull);
    });
  });

  group('validateInputMode', () {
    test('returns null for non-empty input mode', () {
      expect(
        EngineProfileValidator.validateInputMode('natural_language'),
        isNull,
      );
    });

    test('returns error for empty input mode', () {
      expect(EngineProfileValidator.validateInputMode(''), isNotNull);
    });
  });

  group('validatePattern', () {
    test('returns null for valid regex', () {
      expect(EngineProfileValidator.validatePattern(r'^Error:.*'), isNull);
      expect(EngineProfileValidator.validatePattern(r'\d+'), isNull);
    });

    test('returns null for empty pattern', () {
      expect(EngineProfileValidator.validatePattern(''), isNull);
      expect(EngineProfileValidator.validatePattern(null), isNull);
    });

    test('returns error for invalid regex', () {
      expect(EngineProfileValidator.validatePattern('[invalid'), isNotNull);
      expect(EngineProfileValidator.validatePattern('(unclosed'), isNotNull);
    });
  });

  group('validateProfileJson', () {
    test('returns empty list for valid profile', () {
      final json = {
        'name': 'valid-engine',
        'display_name': 'Valid Engine',
        'type': 'chat-tui',
        'input_mode': 'natural_language',
      };
      expect(EngineProfileValidator.validateProfileJson(json), isEmpty);
    });

    test('returns errors for missing required fields', () {
      final json = <String, dynamic>{'name': 'incomplete'};
      final errors = EngineProfileValidator.validateProfileJson(json);
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('display_name')), isTrue);
      expect(errors.any((e) => e.contains('type')), isTrue);
      expect(errors.any((e) => e.contains('input_mode')), isTrue);
    });

    test('returns errors for empty required fields', () {
      final json = {
        'name': '',
        'display_name': '',
        'type': '',
        'input_mode': '',
      };
      final errors = EngineProfileValidator.validateProfileJson(json);
      expect(errors, isNotEmpty);
    });

    test('validates regex patterns in profile', () {
      final json = {
        'name': 'bad-regex',
        'display_name': 'Bad Regex',
        'type': 'chat-tui',
        'input_mode': 'natural_language',
        'patterns': {
          'good': r'^OK$',
          'bad': '[invalid',
        },
      };
      final errors = EngineProfileValidator.validateProfileJson(json);
      expect(errors.any((e) => e.contains('bad')), isTrue);
      expect(errors.any((e) => e.contains('good')), isFalse);
    });

    test('validates state config structure', () {
      final json = {
        'name': 'bad-state',
        'display_name': 'Bad State',
        'type': 'chat-tui',
        'input_mode': 'natural_language',
        'states': {
          'valid': {'indicator': 'spinner'},
          'missing-indicator': <String, dynamic>{},
        },
      };
      final errors = EngineProfileValidator.validateProfileJson(json);
      expect(
        errors.any((e) => e.contains('missing-indicator')),
        isTrue,
      );
    });

    test('validates name format within profile JSON', () {
      final json = {
        'name': 'INVALID NAME',
        'display_name': 'Test',
        'type': 'chat-tui',
        'input_mode': 'natural_language',
      };
      final errors = EngineProfileValidator.validateProfileJson(json);
      expect(errors.any((e) => e.contains('lowercase')), isTrue);
    });
  });
}

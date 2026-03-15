import 'package:flutter_test/flutter_test.dart';

import 'package:murminal/data/services/default_patterns.dart';
import 'package:murminal/data/services/pattern_detector.dart';

void main() {
  late PatternDetector detector;

  setUp(() {
    detector = PatternDetector(DefaultPatterns.defaultProfile);
  });

  group('DefaultPatterns', () {
    group('approval/question patterns', () {
      test('detects (y/N) prompt', () {
        final result = detector.detect('Do you want to proceed? (y/N)');
        expect(result, isNotNull);
        expect(result!.type.name, 'question');
      });

      test('detects (Y/n) prompt', () {
        final result = detector.detect('Continue? (Y/n)');
        expect(result, isNotNull);
        expect(result!.type.name, 'question');
      });

      test('detects Enter password prompt', () {
        final result = detector.detect('Enter password:');
        expect(result, isNotNull);
        expect(result!.type.name, 'question');
      });

      test('detects [y/n] prompt', () {
        final result = detector.detect('Are you sure? [y/n]');
        expect(result, isNotNull);
        expect(result!.type.name, 'question');
      });

      test('detects Are you sure prompt', () {
        final result = detector.detect('Are you sure?');
        expect(result, isNotNull);
        expect(result!.type.name, 'question');
      });
    });

    group('error patterns', () {
      test('detects error: prefix', () {
        final result = detector.detect('error: compilation failed');
        expect(result, isNotNull);
        expect(result!.type.name, 'error');
      });

      test('detects FAILED keyword', () {
        final result = detector.detect('Build FAILED');
        expect(result, isNotNull);
        expect(result!.type.name, 'error');
      });

      test('detects fatal: prefix', () {
        final result = detector.detect("fatal: not a git repository");
        expect(result, isNotNull);
        expect(result!.type.name, 'error');
      });

      test('detects Exception: prefix', () {
        final result = detector.detect('Exception: null pointer');
        expect(result, isNotNull);
        expect(result!.type.name, 'error');
      });

      test('detects Python traceback', () {
        final result = detector.detect('Traceback (most recent call last):');
        expect(result, isNotNull);
        expect(result!.type.name, 'error');
      });

      test('detects Permission denied', () {
        final result = detector.detect('Permission denied (publickey)');
        expect(result, isNotNull);
        expect(result!.type.name, 'error');
      });

      test('detects command not found', () {
        final result = detector.detect('zsh: command not found: foo');
        expect(result, isNotNull);
        expect(result!.type.name, 'error');
      });
    });

    group('completion patterns', () {
      test('detects Build succeeded', () {
        final result = detector.detect('Build succeeded');
        expect(result, isNotNull);
        expect(result!.type.name, 'complete');
      });

      test('detects All tests passed', () {
        final result = detector.detect('All tests passed');
        expect(result, isNotNull);
        expect(result!.type.name, 'complete');
      });

      test('detects Done keyword', () {
        final result = detector.detect('Done in 2.3s');
        expect(result, isNotNull);
        expect(result!.type.name, 'complete');
      });

      test('detects checkmark symbol', () {
        final result = detector.detect('All checks passed');
        expect(result, isNotNull);
        expect(result!.type.name, 'complete');
      });

      test('detects Successfully keyword', () {
        final result = detector.detect('Successfully installed package');
        expect(result, isNotNull);
        expect(result!.type.name, 'complete');
      });
    });

    group('thinking patterns', () {
      test('detects spinner characters', () {
        final result = detector.detect('\u280b Building project...');
        expect(result, isNotNull);
        expect(result!.type.name, 'thinking');
      });

      test('detects Loading...', () {
        final result = detector.detect('Loading...');
        expect(result, isNotNull);
        expect(result!.type.name, 'thinking');
      });

      test('detects Compiling...', () {
        final result = detector.detect('Compiling...');
        expect(result, isNotNull);
        expect(result!.type.name, 'thinking');
      });
    });

    group('priority ordering', () {
      test('error takes priority over complete', () {
        final result = detector.detect('Error: build failed\nDone');
        expect(result, isNotNull);
        expect(result!.type.name, 'error');
      });

      test('question takes priority over complete', () {
        final result =
            detector.detect('Tests passed\nContinue? (y/N)');
        expect(result, isNotNull);
        expect(result!.type.name, 'question');
      });
    });

    group('no match', () {
      test('returns null for idle output', () {
        final result = detector.detect('user@server:~\$');
        expect(result, isNull);
      });

      test('returns null for empty string', () {
        final result = detector.detect('');
        expect(result, isNull);
      });
    });

    group('defaultProfile', () {
      test('has all required fields', () {
        final profile = DefaultPatterns.defaultProfile;
        expect(profile.name, '_default');
        expect(profile.patterns, isNotEmpty);
        expect(profile.states, isNotEmpty);
        expect(profile.reportTemplates, isNotEmpty);
      });

      test('has all four state types configured', () {
        final profile = DefaultPatterns.defaultProfile;
        expect(profile.states.containsKey('question'), isTrue);
        expect(profile.states.containsKey('error'), isTrue);
        expect(profile.states.containsKey('complete'), isTrue);
        expect(profile.states.containsKey('thinking'), isTrue);
      });

      test('error and question are high priority', () {
        final profile = DefaultPatterns.defaultProfile;
        expect(profile.states['error']!.priority, 'high');
        expect(profile.states['question']!.priority, 'high');
      });

      test('thinking does not report', () {
        final profile = DefaultPatterns.defaultProfile;
        expect(profile.states['thinking']!.report, isFalse);
      });
    });
  });
}

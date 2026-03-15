import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:murminal/core/providers.dart';
import 'package:murminal/data/models/engine_profile.dart';
import 'package:murminal/data/services/engine_registry.dart';
import 'package:murminal/ui/engine_profiles/engine_profile_list_screen.dart';

/// Creates a minimal valid [EngineProfile] for testing.
EngineProfile _makeProfile({
  String name = 'test-engine',
  String displayName = 'Test Engine',
}) {
  return EngineProfile(
    name: name,
    displayName: displayName,
    type: 'chat-tui',
    inputMode: 'natural_language',
    launch: const LaunchConfig(),
  );
}

void main() {
  group('EngineProfileListScreen', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    testWidgets('shows empty state when no profiles exist', (tester) async {
      final registry = EngineRegistry();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            engineRegistryProvider.overrideWithValue(registry),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MaterialApp(
            home: EngineProfileListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No engine profiles'), findsOneWidget);
    });

    testWidgets('displays bundled profiles with BUNDLED badge', (tester) async {
      final registry = EngineRegistry();
      registry.register(_makeProfile(name: 'claude', displayName: 'Claude Code'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            engineRegistryProvider.overrideWithValue(registry),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MaterialApp(
            home: EngineProfileListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Claude Code'), findsOneWidget);
      expect(find.text('BUNDLED'), findsOneWidget);
    });

    testWidgets('displays multiple profiles', (tester) async {
      final registry = EngineRegistry();
      registry.register(_makeProfile(name: 'alpha', displayName: 'Alpha'));
      registry.register(_makeProfile(name: 'beta', displayName: 'Beta'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            engineRegistryProvider.overrideWithValue(registry),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MaterialApp(
            home: EngineProfileListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('shows app bar with title', (tester) async {
      final registry = EngineRegistry();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            engineRegistryProvider.overrideWithValue(registry),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MaterialApp(
            home: EngineProfileListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Engine Profiles'), findsOneWidget);
    });

    testWidgets('has floating action button for adding profiles', (tester) async {
      final registry = EngineRegistry();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            engineRegistryProvider.overrideWithValue(registry),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MaterialApp(
            home: EngineProfileListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('shows profile type and input mode', (tester) async {
      final registry = EngineRegistry();
      registry.register(_makeProfile());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            engineRegistryProvider.overrideWithValue(registry),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MaterialApp(
            home: EngineProfileListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Type and input mode shown as subtitle.
      expect(find.textContaining('chat-tui'), findsOneWidget);
    });
  });
}

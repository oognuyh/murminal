import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:murminal/core/providers.dart';
import 'package:murminal/data/models/engine_profile.dart';
import 'package:murminal/data/services/engine_registry.dart';
import 'package:murminal/ui/engine_profiles/engine_profile_editor_screen.dart';

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
    launch: const LaunchConfig(command: 'test-cmd'),
    patterns: {'error': r'Error:.*'},
    states: {
      'error': const StateConfig(
        indicator: 'error_text',
        report: true,
        priority: 'high',
      ),
    },
    reportTemplates: {'error': 'Error occurred'},
  );
}

/// Pumps widget and waits for post-frame callbacks (profile loading).
Future<void> _pumpEditor(
  WidgetTester tester, {
  required EngineRegistry registry,
  required SharedPreferences prefs,
  required String documentsPath,
  String? profileName,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        engineRegistryProvider.overrideWithValue(registry),
        sharedPreferencesProvider.overrideWithValue(prefs),
        documentsPathProvider.overrideWithValue(documentsPath),
      ],
      child: MaterialApp(
        home: EngineProfileEditorScreen(profileName: profileName),
      ),
    ),
  );
  // Allow post-frame callback for profile loading.
  await tester.pump();
  await tester.pump();
}

void main() {
  group('EngineProfileEditorScreen', () {
    late SharedPreferences prefs;
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      tempDir = await Directory.systemTemp.createTemp('editor_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('shows New Profile in app bar when profileName is null',
        (tester) async {
      final registry = EngineRegistry();

      await _pumpEditor(tester,
          registry: registry, prefs: prefs, documentsPath: tempDir.path);

      expect(find.text('New Profile'), findsOneWidget);
    });

    testWidgets('shows GENERAL section header', (tester) async {
      final registry = EngineRegistry();

      await _pumpEditor(tester,
          registry: registry, prefs: prefs, documentsPath: tempDir.path);

      expect(find.text('GENERAL'), findsOneWidget);
    });

    testWidgets('shows LAUNCH section header', (tester) async {
      final registry = EngineRegistry();

      await _pumpEditor(tester,
          registry: registry, prefs: prefs, documentsPath: tempDir.path);

      expect(find.text('LAUNCH'), findsOneWidget);
    });

    testWidgets('shows read-only banner for bundled profile', (tester) async {
      final registry = EngineRegistry();
      registry.register(_makeProfile(name: 'bundled', displayName: 'Bundled'));

      await _pumpEditor(
        tester,
        registry: registry,
        prefs: prefs,
        documentsPath: tempDir.path,
        profileName: 'bundled',
      );

      expect(find.textContaining('Bundled profile'), findsOneWidget);
    });

    testWidgets('populates name field when editing', (tester) async {
      final registry = EngineRegistry();
      registry.register(_makeProfile(name: 'edit-me', displayName: 'Edit Me'));

      await _pumpEditor(
        tester,
        registry: registry,
        prefs: prefs,
        documentsPath: tempDir.path,
        profileName: 'edit-me',
      );

      // Find the TextFormField containing the profile name.
      final nameFinder = find.widgetWithText(TextFormField, 'edit-me');
      expect(nameFinder, findsOneWidget);
    });

    testWidgets('shows create button when scrolled to bottom', (tester) async {
      final registry = EngineRegistry();

      await _pumpEditor(tester,
          registry: registry, prefs: prefs, documentsPath: tempDir.path);

      // Scroll to the bottom of the list view.
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Create Profile'),
        200,
        scrollable: scrollable,
      );

      expect(find.text('Create Profile'), findsOneWidget);
    });

    testWidgets('shows duplicate button for bundled profile', (tester) async {
      final registry = EngineRegistry();
      registry.register(_makeProfile(name: 'bundled', displayName: 'Bundled'));

      await _pumpEditor(
        tester,
        registry: registry,
        prefs: prefs,
        documentsPath: tempDir.path,
        profileName: 'bundled',
      );

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Duplicate as Custom Profile'),
        200,
        scrollable: scrollable,
      );

      expect(find.text('Duplicate as Custom Profile'), findsOneWidget);
    });
  });
}

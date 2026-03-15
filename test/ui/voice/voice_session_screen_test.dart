import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:murminal/core/providers.dart';
import 'package:murminal/data/models/session.dart';
import 'package:murminal/data/models/voice_supervisor_state.dart';
import 'package:murminal/ui/voice/voice_session_screen.dart';

void main() {
  group('VoiceSessionScreen', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    /// Builds the widget under test with provider overrides.
    ///
    /// Overrides the voice supervisor state and session list providers
    /// to avoid real service instantiation in tests.
    Widget buildWidget({
      VoiceSupervisorState initialState = VoiceSupervisorState.listening,
      List<Session> sessions = const [],
    }) {
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          voiceSupervisorStateProvider(
            'test-server',
          ).overrideWith((ref) => Stream.value(initialState)),
          allSessionsProvider.overrideWith(
            (ref) => Future.value(sessions),
          ),
          serverListProvider.overrideWithValue([]),
          voiceApiKeyProvider.overrideWith(
            (ref) => Future.value('test-key'),
          ),
        ],
        child: const MaterialApp(
          home: VoiceSessionScreen(serverId: 'test-server'),
        ),
      );
    }

    testWidgets('shows voice session active banner', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('VOICE SESSION ACTIVE'), findsOneWidget);
    });

    testWidgets('displays listening state text', (tester) async {
      await tester.pumpWidget(buildWidget(
        initialState: VoiceSupervisorState.listening,
      ));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Listening...'), findsOneWidget);
    });

    testWidgets('displays speaking state text', (tester) async {
      await tester.pumpWidget(buildWidget(
        initialState: VoiceSupervisorState.speaking,
      ));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Speaking...'), findsOneWidget);
    });

    testWidgets('displays processing state text', (tester) async {
      await tester.pumpWidget(buildWidget(
        initialState: VoiceSupervisorState.processing,
      ));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Processing...'), findsOneWidget);
    });

    testWidgets('shows tap to stop text', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Tap to stop'), findsOneWidget);
    });

    testWidgets('shows session status section when sessions exist',
        (tester) async {
      final sessions = [
        Session(
          id: 's1',
          serverId: 'test-server',
          engine: 'claude',
          name: 'dev-session',
          status: SessionStatus.running,
          createdAt: DateTime.now(),
        ),
        Session(
          id: 's2',
          serverId: 'test-server',
          engine: 'codex',
          name: 'build-session',
          status: SessionStatus.idle,
          createdAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(buildWidget(sessions: sessions));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('SESSION STATUS'), findsOneWidget);
      expect(find.text('dev-session'), findsOneWidget);
      expect(find.text('build-session'), findsOneWidget);
      expect(find.text('RUNNING'), findsOneWidget);
      expect(find.text('IDLE'), findsOneWidget);
    });

    testWidgets('shows session and server count info', (tester) async {
      final sessions = [
        Session(
          id: 's1',
          serverId: 'test-server',
          engine: 'claude',
          name: 'dev-session',
          status: SessionStatus.running,
          createdAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(buildWidget(sessions: sessions));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('1 session'), findsOneWidget);
    });

    testWidgets('shows error banner when in error state', (tester) async {
      await tester.pumpWidget(buildWidget(
        initialState: VoiceSupervisorState.error,
      ));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('SESSION ERROR'), findsOneWidget);
      expect(find.text('Error'), findsOneWidget);
    });

    testWidgets('displays elapsed timer format', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump(const Duration(milliseconds: 100));

      // Timer starts at 00:00.
      expect(find.textContaining('00:00'), findsOneWidget);
    });

    testWidgets('hides session status section when no sessions',
        (tester) async {
      await tester.pumpWidget(buildWidget(sessions: []));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('SESSION STATUS'), findsNothing);
    });
  });
}

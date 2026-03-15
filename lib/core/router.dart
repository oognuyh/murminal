import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:murminal/data/models/server_config.dart';
import 'package:murminal/data/repositories/server_repository.dart';
import 'package:murminal/ui/home/home_view.dart';
import 'package:murminal/ui/screens/add_server_screen.dart';
import 'package:murminal/ui/screens/new_session_screen.dart';
import 'package:murminal/ui/screens/session_detail_screen.dart';
import 'package:murminal/ui/servers/server_list_view.dart';
import 'package:murminal/ui/sessions/session_list_view.dart';
import 'package:murminal/ui/settings/settings_view.dart';
import 'package:murminal/ui/widgets/main_scaffold.dart';

/// Route paths for the main tabs.
abstract final class AppRoutes {
  static const home = '/';
  static const servers = '/servers';
  static const sessions = '/sessions';
  static const settings = '/settings';
  static const sessionDetail = '/sessions/:sessionId';
  static const newSession = '/sessions/new';
  static const addServer = '/servers/add';
}

/// Maps route location to tab index.
int _tabIndexFromLocation(String location) {
  return switch (location) {
    AppRoutes.servers => 1,
    AppRoutes.sessions => 2,
    AppRoutes.settings => 3,
    _ => 0,
  };
}

/// Maps tab index to route path.
String _locationFromTabIndex(int index) {
  return switch (index) {
    1 => AppRoutes.servers,
    2 => AppRoutes.sessions,
    3 => AppRoutes.settings,
    _ => AppRoutes.home,
  };
}

/// Global navigation key for the shell route.
final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// Application router with bottom navigation shell.
final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: AppRoutes.home,
  routes: [
    GoRoute(
      path: AppRoutes.newSession,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const NewSessionScreen(),
    ),
    GoRoute(
      path: AppRoutes.sessionDetail,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final sessionId = state.pathParameters['sessionId']!;
        final sessionName =
            state.uri.queryParameters['name'] ?? sessionId;
        final serverId = state.uri.queryParameters['serverId'] ?? '';
        return SessionDetailScreen(
          sessionId: sessionId,
          sessionName: sessionName,
          serverId: serverId,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.addServer,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return AddServerScreen(
          repository: extra!['repository'] as ServerRepository,
          existingConfig: extra['existingConfig'] as ServerConfig?,
        );
      },
    ),
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        final currentIndex = _tabIndexFromLocation(
          state.uri.path,
        );

        return MainScaffold(
          currentIndex: currentIndex,
          onTabSelected: (index) {
            final location = _locationFromTabIndex(index);
            GoRouter.of(context).go(location);
          },
          onMicPressed: () {
            // Voice action will be implemented in a future issue.
          },
          tabs: const [
            HomeView(),
            ServerListView(),
            SessionListView(),
            SettingsView(),
          ],
        );
      },
      routes: [
        GoRoute(
          path: AppRoutes.home,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SizedBox.shrink(),
          ),
        ),
        GoRoute(
          path: AppRoutes.servers,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SizedBox.shrink(),
          ),
        ),
        GoRoute(
          path: AppRoutes.sessions,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SizedBox.shrink(),
          ),
        ),
        GoRoute(
          path: AppRoutes.settings,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SizedBox.shrink(),
          ),
        ),
      ],
    ),
  ],
);

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:murminal/core/providers.dart';
import 'package:murminal/core/router.dart';
import 'package:murminal/core/theme.dart';

class MurminalApp extends ConsumerStatefulWidget {
  const MurminalApp({super.key});

  @override
  ConsumerState<MurminalApp> createState() => _MurminalAppState();
}

class _MurminalAppState extends ConsumerState<MurminalApp> {
  @override
  void initState() {
    super.initState();
    _loadEngineProfiles();
    _reconnectSavedServers();
  }

  Future<void> _loadEngineProfiles() async {
    final registry = ref.read(engineRegistryProvider);
    await registry.loadBundledProfiles(rootBundle);
  }

  /// Reconnect to previously connected servers on app startup.
  ///
  /// Restores the SSH connection pool state so that sessions can be
  /// reconciled with live tmux state and the voice FAB finds connected
  /// servers.
  Future<void> _reconnectSavedServers() async {
    final serverRepo = ref.read(serverRepositoryProvider);
    final pool = ref.read(sshConnectionPoolProvider);
    final servers = serverRepo.getAll();

    for (final server in servers) {
      pool.register(server);
      try {
        await pool.getConnection(server.id);
      } catch (_) {
        // Connection may fail if server is offline — that's expected.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Murminal',
      theme: murminalTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

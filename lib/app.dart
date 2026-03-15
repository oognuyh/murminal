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
  }

  Future<void> _loadEngineProfiles() async {
    final registry = ref.read(engineRegistryProvider);
    await registry.loadBundledProfiles(rootBundle);
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

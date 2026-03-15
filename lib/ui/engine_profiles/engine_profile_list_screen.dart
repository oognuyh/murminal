import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:murminal/core/providers.dart';
import 'package:murminal/core/router.dart';
import 'package:murminal/data/models/engine_profile.dart';

/// Theme colors matching the app's dark slate design.
const _kBgColor = Color(0xFF0A0F1C);
const _kSurfaceColor = Color(0xFF1E293B);
const _kAccentColor = Color(0xFF22D3EE);
const _kTextSecondary = Color(0xFF94A3B8);

/// Screen listing all engine profiles (bundled + user-created).
///
/// Provides navigation to view/edit individual profiles and
/// options to create new profiles, import, and reset to defaults.
class EngineProfileListScreen extends ConsumerWidget {
  const EngineProfileListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(allEngineProfilesProvider);
    final bundledNames = ref.watch(bundledProfileNamesProvider);
    final userNames = ref.watch(userProfileNamesProvider);

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: _kBgColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Engine Profiles',
          style: TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 18,
            letterSpacing: 1,
          ),
        ),
        actions: [
          PopupMenuButton<_MenuAction>(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            color: _kSurfaceColor,
            onSelected: (action) =>
                _handleMenuAction(context, ref, action),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _MenuAction.create,
                child: _MenuItemRow(
                  icon: Icons.add,
                  label: 'New Profile',
                ),
              ),
              const PopupMenuItem(
                value: _MenuAction.import_,
                child: _MenuItemRow(
                  icon: Icons.file_download_outlined,
                  label: 'Import Profile',
                ),
              ),
              const PopupMenuItem(
                value: _MenuAction.reset,
                child: _MenuItemRow(
                  icon: Icons.restore,
                  label: 'Reset to Defaults',
                ),
              ),
            ],
          ),
        ],
      ),
      body: profiles.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              itemCount: profiles.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final profile = profiles[index];
                final isBundled = bundledNames.contains(profile.name) &&
                    !userNames.contains(profile.name);
                return _ProfileTile(
                  profile: profile,
                  isBundled: isBundled,
                  onTap: () => context.push(
                    '${AppRoutes.engineProfiles}/${Uri.encodeComponent(profile.name)}',
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _kAccentColor,
        foregroundColor: _kBgColor,
        onPressed: () => context.push(AppRoutes.engineProfileEditor),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    _MenuAction action,
  ) {
    switch (action) {
      case _MenuAction.create:
        context.push(AppRoutes.engineProfileEditor);
      case _MenuAction.import_:
        _importProfile(context, ref);
      case _MenuAction.reset:
        _resetToDefaults(context, ref);
    }
  }

  Future<void> _importProfile(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final json = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSurfaceColor,
        title: const Text(
          'Import Profile',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          maxLines: 10,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'JetBrains Mono',
            fontSize: 12,
          ),
          decoration: InputDecoration(
            hintText: 'Paste profile JSON here...',
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: _kBgColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Import', style: TextStyle(color: _kAccentColor)),
          ),
        ],
      ),
    );
    controller.dispose();

    if (json == null || json.trim().isEmpty) return;

    try {
      final repo = ref.read(engineProfileRepositoryProvider);
      final profile = repo.import_(json);
      await repo.save(profile);
      ref.invalidate(allEngineProfilesProvider);
      ref.invalidate(userProfileNamesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported "${profile.displayName}"'),
            backgroundColor: _kSurfaceColor,
          ),
        );
      }
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid profile JSON: ${e.message}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _resetToDefaults(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSurfaceColor,
        title: const Text(
          'Reset to Defaults',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will remove all custom profiles. Bundled profiles will remain unchanged.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final repo = ref.read(engineProfileRepositoryProvider);
    await repo.resetToDefaults();
    ref.invalidate(allEngineProfilesProvider);
    ref.invalidate(userProfileNamesProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All custom profiles removed'),
          backgroundColor: _kSurfaceColor,
        ),
      );
    }
  }
}

/// Empty state placeholder when no profiles are loaded.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.terminal, size: 48, color: Colors.white24),
          SizedBox(height: 16),
          Text(
            'No engine profiles',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 16,
              fontFamily: 'JetBrains Mono',
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Create or import a profile to get started',
            style: TextStyle(color: Colors.white24, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Single profile tile in the list.
class _ProfileTile extends StatelessWidget {
  final EngineProfile profile;
  final bool isBundled;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.profile,
    required this.isBundled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kSurfaceColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _kAccentColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.terminal,
                  color: _kAccentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _Badge(
                          label: isBundled ? 'BUNDLED' : 'CUSTOM',
                          color: isBundled
                              ? Colors.white24
                              : _kAccentColor.withAlpha(102),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${profile.type} \u2022 ${profile.inputMode}',
                      style: const TextStyle(
                        color: _kTextSecondary,
                        fontSize: 12,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.white24,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small badge label for profile type (bundled/custom).
class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 9,
          fontFamily: 'JetBrains Mono',
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Row layout for popup menu items.
class _MenuItemRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuItemRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}

enum _MenuAction { create, import_, reset }

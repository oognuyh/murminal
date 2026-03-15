import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:murminal/core/providers.dart';
import 'package:murminal/core/router.dart';
import 'package:murminal/data/models/voice_provider.dart';

/// Background color for the settings screen.
const _kBgColor = Color(0xFF0A0F1C);

/// Surface color for cards and tiles.
const _kSurfaceColor = Color(0xFF1E293B);

/// Accent color for active controls and highlights.
const _kAccentColor = Color(0xFF22D3EE);

/// Supported languages for voice interaction.
const _kLanguages = ['Korean', 'English', 'Japanese', 'Chinese'];

/// Settings screen with sectioned list layout matching the pen wireframe.
///
/// Sections: VOICE, ENGINE, ABOUT. Each section has grey header labels
/// and list tiles with icon + label + optional value/chevron.
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        children: [
          const Text(
            'SETTINGS',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 18,
              fontFamily: 'JetBrains Mono',
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 32),
          _buildVoiceSection(context, ref),
          const SizedBox(height: 32),
          _buildEngineSection(context),
          const SizedBox(height: 32),
          _buildAboutSection(context, ref),
        ],
      ),
      ),
    );
  }

  // -- VOICE section ----------------------------------------------------------

  Widget _buildVoiceSection(BuildContext context, WidgetRef ref) {
    final selectedProvider = ref.watch(voiceProviderSettingProvider);
    final autoReport = ref.watch(autoReportProvider);
    final language = ref.watch(languageSettingProvider);

    return _Section(
      title: 'VOICE',
      children: [
        _DropdownTile<VoiceProvider>(
          icon: Icons.record_voice_over,
          label: 'Voice Provider',
          value: selectedProvider,
          items: VoiceProvider.values,
          itemLabel: (p) => p.displayName,
          onChanged: (value) {
            if (value != null) {
              ref.read(voiceProviderSettingProvider.notifier).state = value;
              final prefs = ref.read(sharedPreferencesProvider);
              prefs.setString('voice_provider', value.name);
            }
          },
        ),
        _ToggleTile(
          icon: Icons.auto_awesome,
          label: 'Auto Report',
          value: autoReport,
          onChanged: (value) {
            ref.read(autoReportProvider.notifier).state = value;
            final prefs = ref.read(sharedPreferencesProvider);
            prefs.setBool('auto_report', value);
          },
        ),
        _DropdownTile<String>(
          icon: Icons.language,
          label: 'Language',
          value: language,
          items: _kLanguages,
          itemLabel: (l) => l,
          onChanged: (value) {
            if (value != null) {
              ref.read(languageSettingProvider.notifier).state = value;
              final prefs = ref.read(sharedPreferencesProvider);
              prefs.setString('language', value);
            }
          },
        ),
      ],
    );
  }

  // -- ENGINE section ---------------------------------------------------------

  Widget _buildEngineSection(BuildContext context) {
    return _Section(
      title: 'ENGINE',
      children: [
        _NavigationTile(
          icon: Icons.terminal,
          label: 'Engine Profiles',
          onTap: () => context.push(AppRoutes.engineProfiles),
        ),
        _NavigationTile(
          icon: Icons.shield_outlined,
          label: 'Safety Rules',
          onTap: () {
            // Safety rules screen not yet implemented; show placeholder.
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Safety Rules — coming soon'),
                backgroundColor: _kSurfaceColor,
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
      ],
    );
  }

  // -- ABOUT section ----------------------------------------------------------

  Widget _buildAboutSection(BuildContext context, WidgetRef ref) {
    return _Section(
      title: 'ABOUT',
      children: [
        _ValueTile(
          icon: Icons.info_outline,
          label: 'Version',
          value: '1.0.0',
        ),
        _NavigationTile(
          icon: Icons.vpn_key_outlined,
          label: 'API Keys',
          onTap: () => context.push(AppRoutes.apiKeys),
        ),
      ],
    );
  }
}

// =============================================================================
// Shared section widget
// =============================================================================

/// A labelled section with a grey header and a rounded card containing tiles.
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 13,
            fontFamily: 'JetBrains Mono',
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _kSurfaceColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  const Divider(
                    height: 1,
                    indent: 52,
                    color: Colors.white10,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Tile variants
// =============================================================================

/// Navigation tile with icon, label, and trailing chevron.
class _NavigationTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavigationTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: _kAccentColor, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
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

/// Static tile displaying a read-only value on the right.
class _ValueTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ValueTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: _kAccentColor, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 14,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ],
      ),
    );
  }
}

/// Toggle tile with a switch on the right.
class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: _kAccentColor, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: _kAccentColor,
          ),
        ],
      ),
    );
  }
}

/// Dropdown tile that shows the current value and opens a dropdown on tap.
class _DropdownTile<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;

  const _DropdownTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: _kAccentColor, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          DropdownButton<T>(
            value: value,
            dropdownColor: _kSurfaceColor,
            underline: const SizedBox.shrink(),
            icon: const Icon(
              Icons.expand_more,
              color: Colors.white24,
              size: 20,
            ),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
            items: items.map((item) {
              return DropdownMenuItem<T>(
                value: item,
                child: Text(itemLabel(item)),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

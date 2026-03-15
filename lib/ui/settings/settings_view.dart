import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:murminal/core/providers.dart';
import 'package:murminal/data/models/voice_provider.dart';

/// Background color for the settings screen.
const _kBgColor = Color(0xFF0A0F1C);

/// Surface color for cards and containers.
const _kSurfaceColor = Color(0xFF1E293B);

/// Accent color for active controls and highlights.
const _kAccentColor = Color(0xFF22D3EE);

/// Settings screen with voice provider configuration and polling interval.
class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  final Map<VoiceProvider, TextEditingController> _keyControllers = {};
  final Map<VoiceProvider, bool> _obscured = {};
  final Map<VoiceProvider, _ConnectionTestStatus> _testStatus = {};

  @override
  void initState() {
    super.initState();
    for (final provider in VoiceProvider.values) {
      _keyControllers[provider] = TextEditingController();
      _obscured[provider] = true;
      _testStatus[provider] = _ConnectionTestStatus.idle;
    }
    _loadApiKeys();
  }

  Future<void> _loadApiKeys() async {
    final storage = ref.read(secureStorageProvider);
    for (final provider in VoiceProvider.values) {
      final key = await storage.read(key: provider.storageKey);
      if (key != null && mounted) {
        _keyControllers[provider]!.text = key;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _keyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pollingInterval = ref.watch(pollingIntervalProvider);
    final selectedProvider = ref.watch(voiceProviderSettingProvider);

    return Scaffold(
      backgroundColor: _kBgColor,
      body: ListView(
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
          _buildVoiceProviderSection(context, selectedProvider),
          const SizedBox(height: 32),
          _buildPollingIntervalSection(context, ref, pollingInterval),
        ],
      ),
    );
  }

  // -- Voice provider section ------------------------------------------------

  Widget _buildVoiceProviderSection(
    BuildContext context,
    VoiceProvider selected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('VOICE'),
        const SizedBox(height: 16),
        _buildProviderSelector(selected),
        const SizedBox(height: 20),
        _buildApiKeyField(selected),
        const SizedBox(height: 16),
        _buildTestConnectionButton(selected),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 13,
        fontFamily: 'JetBrains Mono',
        letterSpacing: 1.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildProviderSelector(VoiceProvider selected) {
    return Container(
      decoration: BoxDecoration(
        color: _kSurfaceColor,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: VoiceProvider.values.map((provider) {
          final isSelected = provider == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                ref.read(voiceProviderSettingProvider.notifier).state =
                    provider;
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? _kAccentColor.withAlpha(38) : null,
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: _kAccentColor.withAlpha(102))
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  provider.name[0].toUpperCase() + provider.name.substring(1),
                  style: TextStyle(
                    color: isSelected ? _kAccentColor : Colors.white54,
                    fontSize: 13,
                    fontFamily: 'JetBrains Mono',
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildApiKeyField(VoiceProvider provider) {
    final controller = _keyControllers[provider]!;
    final obscured = _obscured[provider]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${provider.displayName} API Key',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscured,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'JetBrains Mono',
            fontSize: 13,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: _kSurfaceColor,
            hintText: 'Enter your API key',
            hintStyle: const TextStyle(color: Colors.white24),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    obscured ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white38,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscured[provider] = !obscured;
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(
                    Icons.save_outlined,
                    color: _kAccentColor,
                    size: 20,
                  ),
                  onPressed: () => _saveApiKey(provider),
                ),
              ],
            ),
          ),
          onSubmitted: (_) => _saveApiKey(provider),
        ),
      ],
    );
  }

  Future<void> _saveApiKey(VoiceProvider provider) async {
    final storage = ref.read(secureStorageProvider);
    final key = _keyControllers[provider]!.text.trim();
    if (key.isEmpty) {
      await storage.delete(key: provider.storageKey);
    } else {
      await storage.write(key: provider.storageKey, value: key);
    }
    // Invalidate the API key provider so downstream consumers re-read.
    ref.invalidate(voiceApiKeyProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            key.isEmpty
                ? '${provider.displayName} API key removed'
                : '${provider.displayName} API key saved',
          ),
          backgroundColor: _kSurfaceColor,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildTestConnectionButton(VoiceProvider provider) {
    final status = _testStatus[provider]!;
    final isTesting = status == _ConnectionTestStatus.testing;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: isTesting ? null : () => _testConnection(provider),
        icon: _testStatusIcon(status),
        label: Text(
          isTesting ? 'Testing...' : 'Test Connection',
          style: const TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 13,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: _kAccentColor,
          side: BorderSide(color: _kAccentColor.withAlpha(102)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _testStatusIcon(_ConnectionTestStatus status) {
    return switch (status) {
      _ConnectionTestStatus.idle =>
        const Icon(Icons.wifi_tethering, size: 18),
      _ConnectionTestStatus.testing => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _kAccentColor,
          ),
        ),
      _ConnectionTestStatus.success =>
        const Icon(Icons.check_circle_outline, size: 18, color: Colors.green),
      _ConnectionTestStatus.failure =>
        const Icon(Icons.error_outline, size: 18, color: Colors.redAccent),
    };
  }

  Future<void> _testConnection(VoiceProvider provider) async {
    final key = _keyControllers[provider]!.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an API key first'),
          backgroundColor: _kSurfaceColor,
        ),
      );
      return;
    }

    setState(() {
      _testStatus[provider] = _ConnectionTestStatus.testing;
    });

    try {
      final storage = ref.read(secureStorageProvider);
      final storedKey = await storage.read(key: provider.storageKey);
      // Verify the key is saved and readable.
      final success = storedKey != null && storedKey == key;
      if (mounted) {
        setState(() {
          _testStatus[provider] = success
              ? _ConnectionTestStatus.success
              : _ConnectionTestStatus.failure;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _testStatus[provider] = _ConnectionTestStatus.failure;
        });
      }
    }
  }

  // -- Polling section (existing) -------------------------------------------

  Widget _buildPollingIntervalSection(
    BuildContext context,
    WidgetRef ref,
    double value,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('POLLING'),
        const SizedBox(height: 16),
        Text(
          'Output Polling Interval',
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'How often terminal output is checked for changes.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white38,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text(
              '0.5s',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontFamily: 'JetBrains Mono',
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: theme.colorScheme.primary,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: theme.colorScheme.primary,
                  overlayColor:
                      theme.colorScheme.primary.withAlpha(30),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: value,
                  min: 0.5,
                  max: 5.0,
                  divisions: 9,
                  onChanged: (newValue) {
                    ref.read(pollingIntervalProvider.notifier).state =
                        newValue;
                  },
                  onChangeEnd: (newValue) {
                    // Persist to SharedPreferences on release.
                    final prefs = ref.read(sharedPreferencesProvider);
                    prefs.setDouble('polling_interval', newValue);
                  },
                ),
              ),
            ),
            const Text(
              '5.0s',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(13),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              '${value.toStringAsFixed(1)}s',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontFamily: 'JetBrains Mono',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Internal status for the connection test button.
enum _ConnectionTestStatus { idle, testing, success, failure }

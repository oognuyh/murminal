import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:murminal/core/providers.dart';

/// Settings screen with configurable polling interval for output monitoring.
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pollingInterval = ref.watch(pollingIntervalProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
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
          _buildPollingIntervalSection(context, ref, pollingInterval),
        ],
      ),
    );
  }

  Widget _buildPollingIntervalSection(
    BuildContext context,
    WidgetRef ref,
    double value,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

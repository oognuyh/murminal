import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:murminal/core/providers.dart';
import 'package:murminal/data/models/voice_provider.dart';

/// Background color for the screen.
const _kBgColor = Color(0xFF0A0F1C);

/// Surface color for cards and input fields.
const _kSurfaceColor = Color(0xFF1E293B);

/// Accent color for active controls.
const _kAccentColor = Color(0xFF22D3EE);

/// Sub-screen for managing API keys for all voice providers.
///
/// Each provider has an expandable card with a secure text field,
/// visibility toggle, save button, and connection test.
class ApiKeysScreen extends ConsumerStatefulWidget {
  const ApiKeysScreen({super.key});

  @override
  ConsumerState<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends ConsumerState<ApiKeysScreen> {
  final Map<VoiceProvider, TextEditingController> _controllers = {};
  final Map<VoiceProvider, bool> _obscured = {};
  final Map<VoiceProvider, _TestStatus> _testStatus = {};

  @override
  void initState() {
    super.initState();
    for (final provider in VoiceProvider.values) {
      _controllers[provider] = TextEditingController();
      _obscured[provider] = true;
      _testStatus[provider] = _TestStatus.idle;
    }
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final storage = ref.read(secureStorageProvider);
    for (final provider in VoiceProvider.values) {
      final key = await storage.read(key: provider.storageKey);
      if (key != null && mounted) {
        _controllers[provider]!.text = key;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: _kBgColor,
        foregroundColor: Colors.white,
        title: const Text(
          'API Keys',
          style: TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 18,
          ),
        ),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          const Text(
            'Enter your API keys below. Keys are stored securely on this device.',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 24),
          for (final provider in VoiceProvider.values) ...[
            _buildProviderCard(provider),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildProviderCard(VoiceProvider provider) {
    final controller = _controllers[provider]!;
    final obscured = _obscured[provider]!;
    final status = _testStatus[provider]!;
    final isTesting = status == _TestStatus.testing;

    return Container(
      decoration: BoxDecoration(
        color: _kSurfaceColor,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            provider.displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
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
              fillColor: _kBgColor,
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
              suffixIcon: IconButton(
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
            ),
            onSubmitted: (_) => _saveKey(provider),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isTesting ? null : () => _testConnection(provider),
                  icon: _testIcon(status),
                  label: Text(
                    isTesting ? 'Testing...' : 'Test',
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 12,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kAccentColor,
                    side: BorderSide(color: _kAccentColor.withAlpha(102)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _saveKey(provider),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text(
                    'Save',
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 12,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _kAccentColor,
                    foregroundColor: _kBgColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _testIcon(_TestStatus status) {
    return switch (status) {
      _TestStatus.idle => const Icon(Icons.wifi_tethering, size: 16),
      _TestStatus.testing => const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: _kAccentColor),
        ),
      _TestStatus.success =>
        const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
      _TestStatus.failure =>
        const Icon(Icons.error_outline, size: 16, color: Colors.redAccent),
    };
  }

  Future<void> _saveKey(VoiceProvider provider) async {
    final storage = ref.read(secureStorageProvider);
    final key = _controllers[provider]!.text.trim();
    if (key.isEmpty) {
      await storage.delete(key: provider.storageKey);
    } else {
      await storage.write(key: provider.storageKey, value: key);
    }
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

  Future<void> _testConnection(VoiceProvider provider) async {
    final key = _controllers[provider]!.text.trim();
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
      _testStatus[provider] = _TestStatus.testing;
    });

    try {
      final service = ref.read(realtimeVoiceServiceProvider);
      await service.connect(key);
      await service.disconnect();
      if (mounted) {
        setState(() {
          _testStatus[provider] = _TestStatus.success;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _testStatus[provider] = _TestStatus.failure;
        });
      }
    }
  }
}

enum _TestStatus { idle, testing, success, failure }

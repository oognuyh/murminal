import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:murminal/core/providers.dart';
import 'package:murminal/data/models/voice_provider.dart';

/// Theme colors matching the app's dark slate design.
const _background = Color(0xFF0A0F1C);
const _surface = Color(0xFF1E293B);
const _accent = Color(0xFF22D3EE);
const _textPrimary = Color(0xFFFFFFFF);
const _textSecondary = Color(0xFF94A3B8);
const _textMuted = Color(0xFF475569);
const _surfaceBorder = Color(0xFF334155);
const _errorRed = Color(0xFFEF4444);
const _successGreen = Color(0xFF22C55E);

/// Settings screen with voice provider selection and API key management.
///
/// Allows users to:
/// - Select a voice provider (Qwen Omni / Gemini Live / OpenAI Realtime)
/// - Enter and persist API keys per provider in secure storage
/// - Test WebSocket connectivity for the selected provider
///
/// Provider changes take effect on the next voice session.
class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  final Map<VoiceProvider, TextEditingController> _keyControllers = {};
  final Map<VoiceProvider, bool> _keyObscured = {};
  final Map<VoiceProvider, _TestResult?> _testResults = {};
  final Map<VoiceProvider, bool> _isTesting = {};
  @override
  void initState() {
    super.initState();
    for (final provider in VoiceProvider.values) {
      _keyControllers[provider] = TextEditingController();
      _keyObscured[provider] = true;
      _testResults[provider] = null;
      _isTesting[provider] = false;
    }
    _loadApiKeys();
  }

  @override
  void dispose() {
    for (final controller in _keyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Loads persisted API keys from secure storage into the text controllers.
  Future<void> _loadApiKeys() async {
    final storage = ref.read(secureStorageProvider);
    for (final provider in VoiceProvider.values) {
      final key = await storage.read(key: provider.storageKey);
      if (key != null && mounted) {
        _keyControllers[provider]!.text = key;
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  /// Persists the API key for [provider] in secure storage.
  Future<void> _saveApiKey(VoiceProvider provider) async {
    final storage = ref.read(secureStorageProvider);
    final key = _keyControllers[provider]!.text.trim();
    if (key.isEmpty) {
      await storage.delete(key: provider.storageKey);
    } else {
      await storage.write(key: provider.storageKey, value: key);
    }
    // Invalidate the cached API key so downstream providers pick up changes.
    ref.invalidate(voiceApiKeyProvider);
  }

  /// Attempts a WebSocket connection to the provider's Realtime API endpoint
  /// using the entered API key. Validates that the handshake succeeds.
  Future<void> _testConnection(VoiceProvider provider) async {
    final apiKey = _keyControllers[provider]!.text.trim();
    if (apiKey.isEmpty) {
      setState(() {
        _testResults[provider] = _TestResult.failure('API key is required');
      });
      return;
    }

    setState(() {
      _isTesting[provider] = true;
      _testResults[provider] = null;
    });

    try {
      // Build the authorization header value based on the provider.
      final headerValue = switch (provider) {
        VoiceProvider.qwen => 'Bearer $apiKey',
        VoiceProvider.gemini => apiKey,
        VoiceProvider.openai => 'Bearer $apiKey',
      };

      // Build provider-specific connection URL.
      final uri = switch (provider) {
        VoiceProvider.qwen =>
          Uri.parse('${provider.baseUrl}?model=qwen-omni-turbo-latest'),
        VoiceProvider.gemini =>
          Uri.parse('${provider.baseUrl}?key=$apiKey'),
        VoiceProvider.openai =>
          Uri.parse('${provider.baseUrl}?model=gpt-4o-realtime-preview'),
      };

      final headers = <String, dynamic>{
        provider.headerKey: headerValue,
      };

      // Qwen requires an additional beta header.
      if (provider == VoiceProvider.qwen) {
        headers['OpenAI-Beta'] = 'realtime=v1';
      }
      if (provider == VoiceProvider.openai) {
        headers['OpenAI-Beta'] = 'realtime=v1';
      }

      final channel = IOWebSocketChannel.connect(uri, headers: headers);

      await channel.ready.timeout(const Duration(seconds: 10));
      await channel.sink.close();

      if (mounted) {
        setState(() {
          _testResults[provider] = _TestResult.success;
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _testResults[provider] =
              _TestResult.failure('Connection timed out');
        });
      }
    } on WebSocketChannelException catch (e) {
      if (mounted) {
        setState(() {
          _testResults[provider] =
              _TestResult.failure('WebSocket error: $e');
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _testResults[provider] = _TestResult.failure(e.toString());
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTesting[provider] = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedProvider = ref.watch(voiceProviderSettingProvider);

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          children: [
            const Text(
              'SETTINGS',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                fontFamily: 'JetBrains Mono',
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 32),
            _buildSectionHeader('VOICE'),
            const SizedBox(height: 16),
            _buildProviderSelector(selectedProvider),
            const SizedBox(height: 24),
            _buildApiKeySection(selectedProvider),
            const SizedBox(height: 16),
            _buildTestResult(selectedProvider),
            const SizedBox(height: 16),
            _buildTestButton(selectedProvider),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: _accent,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        fontFamily: 'JetBrains Mono',
        letterSpacing: 3,
      ),
    );
  }

  /// Builds the segmented provider selector control.
  Widget _buildProviderSelector(VoiceProvider selected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Provider',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _surfaceBorder),
          ),
          child: Row(
            children: VoiceProvider.values.map((provider) {
              final isSelected = provider == selected;
              final isFirst = provider == VoiceProvider.values.first;
              final isLast = provider == VoiceProvider.values.last;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    ref.read(voiceProviderSettingProvider.notifier).state =
                        provider;
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color:
                          isSelected ? _accent : Colors.transparent,
                      borderRadius: BorderRadius.horizontal(
                        left: isFirst
                            ? const Radius.circular(6)
                            : Radius.zero,
                        right: isLast
                            ? const Radius.circular(6)
                            : Radius.zero,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _providerShortName(provider),
                      style: TextStyle(
                        color: isSelected
                            ? _background
                            : _textMuted,
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        fontFamily: 'JetBrains Mono',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// Returns a short label for the segmented control to keep it compact.
  String _providerShortName(VoiceProvider provider) {
    return switch (provider) {
      VoiceProvider.qwen => 'Qwen',
      VoiceProvider.gemini => 'Gemini',
      VoiceProvider.openai => 'OpenAI',
    };
  }

  /// Builds the API key input field for the selected provider.
  Widget _buildApiKeySection(VoiceProvider provider) {
    final controller = _keyControllers[provider]!;
    final obscured = _keyObscured[provider]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${provider.displayName} API Key',
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscured,
          style: const TextStyle(
            color: _textPrimary,
            fontFamily: 'JetBrains Mono',
            fontSize: 13,
          ),
          cursorColor: _accent,
          onChanged: (_) => _saveApiKey(provider),
          decoration: InputDecoration(
            hintText: 'Enter your API key',
            hintStyle: const TextStyle(
              color: _textMuted,
              fontFamily: 'JetBrains Mono',
              fontSize: 13,
            ),
            filled: true,
            fillColor: _surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                obscured ? Icons.visibility_off : Icons.visibility,
                color: _textMuted,
                size: 20,
              ),
              onPressed: () {
                setState(() {
                  _keyObscured[provider] = !obscured;
                });
              },
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _surfaceBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _surfaceBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _accent, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Stored securely on device. '
          'Changes apply on next voice session.',
          style: const TextStyle(
            color: _textMuted,
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  /// Displays the test connection result banner for the selected provider.
  Widget _buildTestResult(VoiceProvider provider) {
    final result = _testResults[provider];
    if (result == null) return const SizedBox.shrink();

    final isSuccess = result == _TestResult.success;
    final color = isSuccess ? _successGreen : _errorRed;
    final icon = isSuccess ? Icons.check_circle_outline : Icons.error_outline;
    final message = isSuccess
        ? 'Connection successful'
        : 'Connection failed: ${(result as _TestFailure).message}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the test connection button for the selected provider.
  Widget _buildTestButton(VoiceProvider provider) {
    final testing = _isTesting[provider] ?? false;

    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: testing ? null : () => _testConnection(provider),
        icon: testing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _accent,
                ),
              )
            : const Icon(Icons.wifi_tethering, size: 18),
        label: Text(testing ? 'Testing...' : 'Test Connection'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _accent,
          side: const BorderSide(color: _accent),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

/// Result of a provider WebSocket connection test.
sealed class _TestResult {
  static const success = _TestSuccess();

  const _TestResult();

  factory _TestResult.failure(String message) = _TestFailure;
}

class _TestSuccess extends _TestResult {
  const _TestSuccess();
}

class _TestFailure extends _TestResult {
  final String message;

  const _TestFailure(this.message);
}

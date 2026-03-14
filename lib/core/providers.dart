import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:murminal/data/models/voice_provider.dart';

/// Secure storage instance for API key management (BYOK).
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

/// Currently selected voice provider.
///
/// Defaults to [VoiceProvider.qwen]. Updated from the settings UI.
final voiceProviderSettingProvider =
    StateProvider<VoiceProvider>((ref) => VoiceProvider.qwen);

/// Reads the stored API key for the currently selected voice provider.
final voiceApiKeyProvider = FutureProvider<String?>((ref) async {
  final provider = ref.watch(voiceProviderSettingProvider);
  final storage = ref.watch(secureStorageProvider);
  return storage.read(key: provider.storageKey);
});

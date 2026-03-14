import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:murminal/data/models/audio_session_state.dart';
import 'package:murminal/data/models/voice_provider.dart';
import 'package:murminal/data/services/audio_session_service.dart';

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

/// Singleton [AudioSessionService] instance for iOS background audio.
///
/// Manages the AVAudioSession lifecycle (playAndRecord category) and
/// emits interruption events so the Voice Supervisor can pause/resume.
final audioSessionServiceProvider = Provider<AudioSessionService>((ref) {
  final service = AudioSessionService();
  ref.onDispose(service.dispose);
  return service;
});

/// Reactive stream of [AudioSessionState] changes.
///
/// UI widgets and the Voice Supervisor can watch this provider to
/// respond to audio interruptions (phone calls, Siri, other apps).
final audioSessionStateProvider = StreamProvider<AudioSessionState>((ref) {
  final service = ref.watch(audioSessionServiceProvider);
  return service.stateStream;
});

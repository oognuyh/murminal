import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:murminal/data/models/audio_session_state.dart';
import 'package:murminal/data/models/session.dart';
import 'package:murminal/data/models/voice_provider.dart';
import 'package:murminal/data/repositories/session_repository.dart';
import 'package:murminal/data/services/audio_session_service.dart';
import 'package:murminal/data/services/session_service.dart';
import 'package:murminal/data/services/ssh_service.dart';
import 'package:murminal/data/services/tmux_controller.dart';

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

/// SharedPreferences instance, must be overridden at app startup.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden with a real instance',
  );
});

/// SSH service provider. One instance per server connection.
final sshServiceProvider = Provider<SshService>((ref) {
  final service = SshService();
  ref.onDispose(service.dispose);
  return service;
});

/// TmuxController backed by the current SSH connection.
final tmuxControllerProvider = Provider<TmuxController>((ref) {
  final ssh = ref.watch(sshServiceProvider);
  return TmuxController(ssh);
});

/// Session repository for local persistence.
final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SessionRepository(prefs);
});

/// Session service coordinating tmux and local persistence.
final sessionServiceProvider = Provider<SessionService>((ref) {
  final tmux = ref.watch(tmuxControllerProvider);
  final repository = ref.watch(sessionRepositoryProvider);
  return SessionService(tmuxController: tmux, repository: repository);
});

/// Lists sessions for a given server ID.
///
/// Returns a [Future] that resolves to the reconciled session list.
final sessionListProvider =
    FutureProvider.family<List<Session>, String>((ref, serverId) async {
  final service = ref.watch(sessionServiceProvider);
  return service.listSessions(serverId);
});

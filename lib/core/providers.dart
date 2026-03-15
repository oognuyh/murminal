import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:murminal/data/models/audio_session_state.dart';
import 'package:murminal/data/models/server_config.dart';
import 'package:murminal/data/models/session.dart';
import 'package:murminal/data/models/voice_provider.dart';
import 'package:murminal/data/repositories/server_repository.dart';
import 'package:murminal/data/repositories/session_repository.dart';
import 'package:murminal/data/services/audio_session_service.dart';
import 'package:murminal/data/services/now_playing_service.dart';
import 'package:murminal/data/services/session_service.dart';
import 'package:murminal/data/services/mic_service.dart';
import 'package:murminal/data/services/output_monitor.dart';
import 'package:murminal/data/services/ssh_connection_pool.dart';
import 'package:murminal/data/services/ssh_service.dart';
import 'package:murminal/data/services/tmux_controller.dart';
import 'package:murminal/data/services/tool_executor.dart';
import 'package:murminal/data/services/voice/qwen_realtime_service.dart';
import 'package:murminal/data/services/voice/realtime_voice_service.dart';
import 'package:murminal/data/services/engine_registry.dart';
import 'package:murminal/data/services/voice_supervisor.dart';
import 'package:murminal/data/models/voice_supervisor_state.dart';

/// Singleton [EngineRegistry] for managing engine profiles.
///
/// Holds all loaded and runtime-registered [EngineProfile] instances.
/// Call [EngineRegistry.loadBundledProfiles] at app startup to populate
/// from bundled JSON assets.
final engineRegistryProvider = Provider<EngineRegistry>((ref) {
  return EngineRegistry();
});

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

/// Singleton [NowPlayingService] for lock screen media controls.
///
/// Manages MPNowPlayingInfoCenter metadata and MPRemoteCommandCenter
/// play/stop targets on iOS. Displays "Murminal" with the current
/// voice session status on the lock screen and Control Center.
final nowPlayingServiceProvider = Provider<NowPlayingService>((ref) {
  final service = NowPlayingService();
  ref.onDispose(service.dispose);
  return service;
});

/// SharedPreferences instance, must be overridden at app startup.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden with a real instance',
  );
});

/// Server repository for SSH server configuration persistence.
final serverRepositoryProvider = Provider<ServerRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ServerRepository(prefs);
});

/// All saved server configurations, refreshable.
final serverListProvider = Provider<List<ServerConfig>>((ref) {
  final repository = ref.watch(serverRepositoryProvider);
  return repository.getAll();
});

/// SSH connection pool for managing multiple server connections.
///
/// Provides lazy connection, health monitoring, and connection limits.
final sshConnectionPoolProvider = Provider<SshConnectionPool>((ref) {
  final pool = SshConnectionPool();
  ref.onDispose(pool.dispose);
  return pool;
});

/// Stream of connection state changes across all pooled servers.
final poolConnectionStatesProvider =
    StreamProvider<Map<String, ConnectionState>>((ref) {
  final pool = ref.watch(sshConnectionPoolProvider);
  return pool.connectionStates;
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
/// Returns a [Future] that resolves to the reconciled session list
/// filtered to the specified server.
final sessionsByServerProvider =
    FutureProvider.family<List<Session>, String>((ref, serverId) async {
  final service = ref.watch(sessionServiceProvider);
  return service.listSessions(serverId: serverId);
});

/// Lists all sessions across all servers.
///
/// Returns a [Future] that resolves to every persisted session,
/// reconciled against live tmux state.
final allSessionsProvider = FutureProvider<List<Session>>((ref) async {
  final service = ref.watch(sessionServiceProvider);
  return service.listSessions();
});

/// Retrieves a single session by its ID.
///
/// Returns null if no session with the given ID exists.
final sessionProvider = Provider.family<Session?, String>((ref, sessionId) {
  final service = ref.watch(sessionServiceProvider);
  return service.getSession(sessionId);
});

/// @deprecated Use [sessionsByServerProvider] instead.
final sessionListProvider =
    FutureProvider.family<List<Session>, String>((ref, serverId) async {
  final service = ref.watch(sessionServiceProvider);
  return service.listSessions(serverId: serverId);
});

/// Microphone service for PCM audio capture.
final micServiceProvider = Provider<MicService>((ref) {
  final service = MicService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Realtime voice service backed by the selected provider.
///
/// Currently defaults to [QwenRealtimeService]. When additional providers
/// are implemented, this should switch based on [voiceProviderSettingProvider].
final realtimeVoiceServiceProvider = Provider<RealtimeVoiceService>((ref) {
  return QwenRealtimeService();
});

/// Output monitor for detecting tmux pane changes.
final outputMonitorProvider = Provider<OutputMonitor>((ref) {
  final tmux = ref.watch(tmuxControllerProvider);
  final monitor = OutputMonitor(tmux);
  ref.onDispose(monitor.dispose);
  return monitor;
});

/// Voice supervisor parameterized by server ID.
///
/// Creates the full voice-to-terminal pipeline for the given server.
final voiceSupervisorProvider =
    Provider.family<VoiceSupervisor, String>((ref, serverId) {
  final tmux = ref.watch(tmuxControllerProvider);
  final sessionSvc = ref.watch(sessionServiceProvider);
  final toolExecutor = ToolExecutor(
    tmux: tmux,
    sessionService: sessionSvc,
    serverId: serverId,
  );
  final supervisor = VoiceSupervisor(
    voiceService: ref.watch(realtimeVoiceServiceProvider),
    audioSession: ref.watch(audioSessionServiceProvider),
    mic: ref.watch(micServiceProvider),
    sessionService: sessionSvc,
    outputMonitor: ref.watch(outputMonitorProvider),
    toolExecutor: toolExecutor,
    serverId: serverId,
  );
  ref.onDispose(supervisor.dispose);
  return supervisor;
});

/// Reactive stream of [VoiceSupervisorState] for UI binding.
///
/// Parameterized by server ID to match [voiceSupervisorProvider].
final voiceSupervisorStateProvider =
    StreamProvider.family<VoiceSupervisorState, String>((ref, serverId) {
  final supervisor = ref.watch(voiceSupervisorProvider(serverId));
  return supervisor.state;
});

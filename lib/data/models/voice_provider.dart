/// Supported voice pipeline providers.
///
/// Providers are split into two categories:
/// - **Realtime** (premium): WebSocket-based APIs with built-in server-side VAD.
///   Audio-in/audio-out over a single connection. Users supply their own API keys.
/// - **Local**: On-device STT/TTS with any text-based LM API.
///   STT (SFSpeechRecognizer) and TTS (AVSpeechSynthesizer) run free on-device.
///   Only the LM API call requires an API key.
enum VoiceProvider {
  // -- Realtime (premium) providers --
  qwen,
  gemini,
  openai,

  // -- Local STT/TTS + text LM providers --
  localClaude,
  localOpenai,
  localGemini;

  /// Whether this provider uses the on-device STT/TTS pipeline.
  bool get isLocal => switch (this) {
        VoiceProvider.localClaude => true,
        VoiceProvider.localOpenai => true,
        VoiceProvider.localGemini => true,
        _ => false,
      };

  /// Whether this provider uses the Realtime WebSocket pipeline.
  bool get isRealtime => !isLocal;
}

/// Convenience accessors for provider-specific configuration.
extension VoiceProviderExtension on VoiceProvider {
  /// Human-readable display name for the settings UI.
  String get displayName => switch (this) {
        VoiceProvider.qwen => 'Qwen Omni Realtime',
        VoiceProvider.gemini => 'Gemini Live',
        VoiceProvider.openai => 'OpenAI Realtime',
        VoiceProvider.localClaude => 'Local + Claude',
        VoiceProvider.localOpenai => 'Local + OpenAI',
        VoiceProvider.localGemini => 'Local + Gemini',
      };

  /// Short label for compact UI elements.
  String get shortLabel => switch (this) {
        VoiceProvider.qwen => 'Qwen',
        VoiceProvider.gemini => 'Gemini',
        VoiceProvider.openai => 'OpenAI',
        VoiceProvider.localClaude => 'Claude',
        VoiceProvider.localOpenai => 'GPT',
        VoiceProvider.localGemini => 'Gemini',
      };

  /// Category label for grouping in the UI.
  String get categoryLabel => isLocal ? 'On-Device Voice' : 'Realtime (Premium)';

  /// Base WebSocket URL for Realtime providers. Unused for local providers.
  String get baseUrl => switch (this) {
        VoiceProvider.qwen =>
          'wss://dashscope-intl.aliyuncs.com/api-ws/v1/inference',
        VoiceProvider.gemini =>
          'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent',
        VoiceProvider.openai => 'wss://api.openai.com/v1/realtime',
        VoiceProvider.localClaude => '',
        VoiceProvider.localOpenai => '',
        VoiceProvider.localGemini => '',
      };

  /// HTTP header key used to pass the API key during WebSocket upgrade.
  String get headerKey => switch (this) {
        VoiceProvider.qwen => 'Authorization',
        VoiceProvider.gemini => 'x-goog-api-key',
        VoiceProvider.openai => 'Authorization',
        VoiceProvider.localClaude => 'x-api-key',
        VoiceProvider.localOpenai => 'Authorization',
        VoiceProvider.localGemini => '',
      };

  /// flutter_secure_storage key for persisting the user's API key.
  String get storageKey => switch (this) {
        VoiceProvider.qwen => 'api_key_qwen',
        VoiceProvider.gemini => 'api_key_gemini',
        VoiceProvider.openai => 'api_key_openai',
        VoiceProvider.localClaude => 'api_key_local_claude',
        VoiceProvider.localOpenai => 'api_key_local_openai',
        VoiceProvider.localGemini => 'api_key_local_gemini',
      };
}

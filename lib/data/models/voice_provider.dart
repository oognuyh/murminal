/// Supported Realtime voice API providers.
///
/// Each provider uses a WebSocket-based Realtime API with built-in
/// server-side VAD. Users supply their own API keys (BYOK model).
enum VoiceProvider {
  qwen,
  gemini,
  openai;
}

/// Convenience accessors for provider-specific configuration.
extension VoiceProviderExtension on VoiceProvider {
  /// Human-readable display name for the settings UI.
  String get displayName => switch (this) {
        VoiceProvider.qwen => 'Qwen Omni Realtime',
        VoiceProvider.gemini => 'Gemini Live',
        VoiceProvider.openai => 'OpenAI Realtime',
      };

  /// Base WebSocket URL for the provider's Realtime API.
  String get baseUrl => switch (this) {
        VoiceProvider.qwen =>
          'wss://dashscope.aliyuncs.com/api-ws/v1/inference',
        VoiceProvider.gemini =>
          'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent',
        VoiceProvider.openai => 'wss://api.openai.com/v1/realtime',
      };

  /// HTTP header key used to pass the API key during WebSocket upgrade.
  String get headerKey => switch (this) {
        VoiceProvider.qwen => 'Authorization',
        VoiceProvider.gemini => 'x-goog-api-key',
        VoiceProvider.openai => 'Authorization',
      };

  /// flutter_secure_storage key for persisting the user's API key.
  String get storageKey => switch (this) {
        VoiceProvider.qwen => 'api_key_qwen',
        VoiceProvider.gemini => 'api_key_gemini',
        VoiceProvider.openai => 'api_key_openai',
      };
}

import Flutter
import AVFoundation

/// Native iOS plugin for on-device text-to-speech using AVSpeechSynthesizer.
///
/// Exposes a Flutter method channel for speaking text, stopping speech,
/// and querying available voices. Streams lifecycle events (started, finished,
/// cancelled) back to the Dart layer.
class SpeechSynthesisPlugin: NSObject, AVSpeechSynthesizerDelegate {
  private let channel: FlutterMethodChannel
  private let synthesizer = AVSpeechSynthesizer()

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.murminal/speech_synthesis",
      binaryMessenger: messenger
    )
    super.init()
    synthesizer.delegate = self
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "speak":
      guard let args = call.arguments as? [String: Any],
            let text = args["text"] as? String else {
        result(FlutterError(
          code: "INVALID_ARGS",
          message: "Missing 'text' argument",
          details: nil
        ))
        return
      }
      let language = args["language"] as? String ?? "en-US"
      let rate = args["rate"] as? Float ?? AVSpeechUtteranceDefaultSpeechRate
      let pitch = args["pitch"] as? Float ?? 1.0
      let volume = args["volume"] as? Float ?? 1.0
      speak(text: text, language: language, rate: rate, pitch: pitch, volume: volume)
      result(nil)

    case "stop":
      synthesizer.stopSpeaking(at: .immediate)
      result(nil)

    case "isSpeaking":
      result(synthesizer.isSpeaking)

    case "getVoices":
      let voices = AVSpeechSynthesisVoice.speechVoices().map { voice -> [String: Any] in
        return [
          "identifier": voice.identifier,
          "name": voice.name,
          "language": voice.language,
          "quality": voice.quality.rawValue,
        ]
      }
      result(voices)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Synthesizes speech from the given text using AVSpeechSynthesizer.
  private func speak(text: String, language: String, rate: Float, pitch: Float, volume: Float) {
    // Stop any ongoing speech before starting new utterance.
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }

    let utterance = AVSpeechUtterance(string: text)
    utterance.rate = rate
    utterance.pitchMultiplier = pitch
    utterance.volume = volume

    // Find a voice matching the requested language.
    if let voice = AVSpeechSynthesisVoice(language: language) {
      utterance.voice = voice
    }

    synthesizer.speak(utterance)
  }

  // MARK: - AVSpeechSynthesizerDelegate

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didStart utterance: AVSpeechUtterance
  ) {
    channel.invokeMethod("onStart", arguments: nil)
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    channel.invokeMethod("onFinish", arguments: nil)
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    channel.invokeMethod("onCancel", arguments: nil)
  }
}

import Flutter
import Speech

/// Native iOS plugin for on-device speech-to-text using SFSpeechRecognizer.
///
/// Exposes a Flutter method channel that starts/stops speech recognition
/// and streams partial transcription results back to Dart. Uses on-device
/// recognition when available for offline capability and reduced latency.
class SpeechRecognitionPlugin: NSObject {
  private let channel: FlutterMethodChannel
  private let speechRecognizer: SFSpeechRecognizer?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private let audioEngine = AVAudioEngine()

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.murminal/speech_recognition",
      binaryMessenger: messenger
    )
    speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    super.init()
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermission":
      requestPermission(result: result)
    case "startListening":
      let args = call.arguments as? [String: Any]
      let locale = args?["locale"] as? String ?? "en-US"
      startListening(locale: locale, result: result)
    case "stopListening":
      stopListening(result: result)
    case "isAvailable":
      result(speechRecognizer?.isAvailable ?? false)
    case "supportsOnDevice":
      if #available(iOS 13, *) {
        result(speechRecognizer?.supportsOnDeviceRecognition ?? false)
      } else {
        result(false)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Requests speech recognition authorization from the user.
  private func requestPermission(result: @escaping FlutterResult) {
    SFSpeechRecognizer.requestAuthorization { status in
      DispatchQueue.main.async {
        switch status {
        case .authorized:
          result("authorized")
        case .denied:
          result("denied")
        case .restricted:
          result("restricted")
        case .notDetermined:
          result("notDetermined")
        @unknown default:
          result("denied")
        }
      }
    }
  }

  /// Starts on-device speech recognition and streams partial results to Flutter.
  private func startListening(locale: String, result: @escaping FlutterResult) {
    // Cancel any existing task.
    recognitionTask?.cancel()
    recognitionTask = nil

    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
          recognizer.isAvailable else {
      result(FlutterError(
        code: "UNAVAILABLE",
        message: "Speech recognizer is not available for locale: \(locale)",
        details: nil
      ))
      return
    }

    recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
    guard let recognitionRequest = recognitionRequest else {
      result(FlutterError(
        code: "REQUEST_ERROR",
        message: "Unable to create recognition request",
        details: nil
      ))
      return
    }

    recognitionRequest.shouldReportPartialResults = true

    // Prefer on-device recognition when available.
    if #available(iOS 13, *) {
      recognitionRequest.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
    }

    let inputNode = audioEngine.inputNode
    let recordingFormat = inputNode.outputFormat(forBus: 0)

    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
      [weak self] buffer, _ in
      self?.recognitionRequest?.append(buffer)
    }

    audioEngine.prepare()

    do {
      try audioEngine.start()
    } catch {
      result(FlutterError(
        code: "ENGINE_ERROR",
        message: "Audio engine failed to start: \(error.localizedDescription)",
        details: nil
      ))
      return
    }

    recognitionTask = recognizer.recognitionTask(with: recognitionRequest) {
      [weak self] taskResult, error in
      guard let self = self else { return }

      if let taskResult = taskResult {
        let transcript = taskResult.bestTranscription.formattedString
        let isFinal = taskResult.isFinal

        self.channel.invokeMethod("onTranscript", arguments: [
          "text": transcript,
          "isFinal": isFinal,
        ])

        if isFinal {
          self.stopAudioEngine()
        }
      }

      if let error = error {
        self.channel.invokeMethod("onError", arguments: [
          "message": error.localizedDescription,
        ])
        self.stopAudioEngine()
      }
    }

    result(nil)
  }

  /// Stops speech recognition and the audio engine.
  private func stopListening(result: @escaping FlutterResult) {
    stopAudioEngine()
    result(nil)
  }

  private func stopAudioEngine() {
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    recognitionRequest?.endAudio()
    recognitionRequest = nil
    recognitionTask?.cancel()
    recognitionTask = nil
  }
}

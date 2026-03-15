import Flutter
import AVFoundation

/// Native iOS plugin for playing raw PCM audio chunks in real time.
///
/// Receives base64-encoded or raw PCM16 audio at 24kHz mono from the
/// Dart layer and plays it through AVAudioEngine with minimal latency.
class PcmPlayerPlugin: NSObject {
  private let channel: FlutterMethodChannel
  private var audioEngine: AVAudioEngine?
  private var playerNode: AVAudioPlayerNode?
  private let format: AVAudioFormat

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.murminal/pcm_player",
      binaryMessenger: messenger
    )
    // Gemini Live outputs 24kHz mono PCM16.
    format = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: 24000,
      channels: 1,
      interleaved: true
    )!
    super.init()
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      startEngine()
      result(nil)
    case "play":
      guard let args = call.arguments as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGS", message: "Expected Uint8List", details: nil))
        return
      }
      playChunk(args.data)
      result(nil)
    case "stop":
      stopEngine()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startEngine() {
    stopEngine()

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()

    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)

    do {
      try engine.start()
      player.play()
      self.audioEngine = engine
      self.playerNode = player
    } catch {
      NSLog("PcmPlayerPlugin: failed to start engine: \(error)")
    }
  }

  private func playChunk(_ data: Data) {
    guard let player = playerNode, let engine = audioEngine, engine.isRunning else {
      return
    }

    let frameCount = UInt32(data.count / 2) // 16-bit = 2 bytes per frame
    guard frameCount > 0 else { return }

    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
      return
    }
    buffer.frameLength = frameCount

    // Copy PCM data into the buffer.
    data.withUnsafeBytes { rawPtr in
      if let src = rawPtr.baseAddress {
        memcpy(buffer.int16ChannelData![0], src, data.count)
      }
    }

    player.scheduleBuffer(buffer, completionHandler: nil)
  }

  private func stopEngine() {
    playerNode?.stop()
    audioEngine?.stop()
    playerNode = nil
    audioEngine = nil
  }
}

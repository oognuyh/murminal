import Flutter
import AVFoundation

/// Native iOS plugin for playing raw PCM audio chunks in real time.
///
/// Uses AVAudioEngine with a manual render approach to play 24kHz
/// mono PCM16 audio from the Gemini Live API.
class PcmPlayerPlugin: NSObject {
  private let channel: FlutterMethodChannel
  private var audioEngine: AVAudioEngine?
  private var playerNode: AVAudioPlayerNode?
  private let pcmFormat: AVAudioFormat
  private let outputFormat: AVAudioFormat?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.murminal/pcm_player",
      binaryMessenger: messenger
    )
    // Gemini Live outputs 24kHz mono PCM16.
    pcmFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: 24000,
      channels: 1,
      interleaved: true
    )!
    // Standard output format at 24kHz float32 for the mixer.
    outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 24000,
      channels: 1,
      interleaved: false
    )
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

    do {
      let engine = AVAudioEngine()
      let player = AVAudioPlayerNode()

      engine.attach(player)

      // Connect player → mixer using the output format to avoid
      // format mismatch crashes with the audio session.
      let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
      engine.connect(player, to: engine.mainMixerNode, format: mixerFormat)

      engine.prepare()
      try engine.start()
      player.play()

      self.audioEngine = engine
      self.playerNode = player

      NSLog("PcmPlayerPlugin: engine started (mixer rate=\(mixerFormat.sampleRate))")
    } catch {
      NSLog("PcmPlayerPlugin: failed to start engine: \(error)")
    }
  }

  private func playChunk(_ data: Data) {
    guard let player = playerNode, let engine = audioEngine, engine.isRunning else {
      // Lazy start if not yet running.
      startEngine()
      guard let p = playerNode, let e = audioEngine, e.isRunning else { return }
      enqueueData(data, player: p)
      return
    }
    enqueueData(data, player: player)
  }

  private func enqueueData(_ data: Data, player: AVAudioPlayerNode) {
    let frameCount = UInt32(data.count / 2) // 16-bit = 2 bytes per frame
    guard frameCount > 0 else { return }

    // Create PCM buffer at 24kHz Int16.
    guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount) else {
      return
    }
    srcBuffer.frameLength = frameCount

    data.withUnsafeBytes { rawPtr in
      if let src = rawPtr.baseAddress {
        memcpy(srcBuffer.int16ChannelData![0], src, data.count)
      }
    }

    // Convert to the mixer's format if needed.
    guard let mixerFormat = audioEngine?.mainMixerNode.outputFormat(forBus: 0) else { return }

    if mixerFormat.sampleRate == pcmFormat.sampleRate && mixerFormat.channelCount == pcmFormat.channelCount {
      // Same sample rate — convert Int16 → Float32 manually.
      guard let floatBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat!, frameCapacity: frameCount) else { return }
      floatBuffer.frameLength = frameCount
      let src = srcBuffer.int16ChannelData![0]
      let dst = floatBuffer.floatChannelData![0]
      for i in 0..<Int(frameCount) {
        dst[i] = Float(src[i]) / 32768.0
      }
      player.scheduleBuffer(floatBuffer, completionHandler: nil)
    } else {
      // Need sample rate conversion.
      guard let converter = AVAudioConverter(from: pcmFormat, to: mixerFormat) else { return }
      let ratio = mixerFormat.sampleRate / pcmFormat.sampleRate
      let outFrames = UInt32(Double(frameCount) * ratio)
      guard let outBuffer = AVAudioPCMBuffer(pcmFormat: mixerFormat, frameCapacity: outFrames) else { return }

      var error: NSError?
      converter.convert(to: outBuffer, error: &error) { _, outStatus in
        outStatus.pointee = .haveData
        return srcBuffer
      }
      if error == nil {
        player.scheduleBuffer(outBuffer, completionHandler: nil)
      }
    }
  }

  private func stopEngine() {
    playerNode?.stop()
    audioEngine?.stop()
    playerNode = nil
    audioEngine = nil
  }
}

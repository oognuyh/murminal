import Flutter
import MediaPlayer

/// Native iOS plugin for MPNowPlayingInfoCenter and MPRemoteCommandCenter.
///
/// Exposes lock screen / Control Center media controls so the Flutter layer
/// can display session status and receive play/stop commands without
/// actually playing audio through AVPlayer.
class NowPlayingPlugin: NSObject {
  private let channel: FlutterMethodChannel
  private var isRegistered = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.murminal/now_playing",
      binaryMessenger: messenger,
    )
    super.init()
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "updateNowPlaying":
      guard let args = call.arguments as? [String: Any],
            let title = args["title"] as? String,
            let subtitle = args["subtitle"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing title or subtitle", details: nil))
        return
      }
      updateNowPlaying(title: title, subtitle: subtitle)
      result(nil)

    case "enableCommands":
      enableRemoteCommands()
      result(nil)

    case "disableCommands":
      disableRemoteCommands()
      result(nil)

    case "clearNowPlaying":
      clearNowPlaying()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Sets the now playing info displayed on the lock screen and Control Center.
  private func updateNowPlaying(title: String, subtitle: String) {
    var info = [String: Any]()
    info[MPMediaItemPropertyTitle] = title
    info[MPMediaItemPropertyArtist] = subtitle
    // Use a large duration to prevent the progress bar from completing.
    info[MPMediaItemPropertyPlaybackDuration] = 0
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
    info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  /// Registers play and stop commands on MPRemoteCommandCenter.
  ///
  /// Play maps to starting a voice session; stop maps to ending one.
  /// Commands are forwarded to the Flutter layer via the method channel.
  private func enableRemoteCommands() {
    guard !isRegistered else { return }
    isRegistered = true

    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget { [weak self] _ in
      self?.channel.invokeMethod("onPlay", arguments: nil)
      return .success
    }

    commandCenter.stopCommand.isEnabled = true
    commandCenter.stopCommand.addTarget { [weak self] _ in
      self?.channel.invokeMethod("onStop", arguments: nil)
      return .success
    }

    commandCenter.pauseCommand.isEnabled = true
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.channel.invokeMethod("onStop", arguments: nil)
      return .success
    }

    // Disable unused commands to keep the UI clean.
    commandCenter.nextTrackCommand.isEnabled = false
    commandCenter.previousTrackCommand.isEnabled = false
    commandCenter.skipForwardCommand.isEnabled = false
    commandCenter.skipBackwardCommand.isEnabled = false
    commandCenter.changePlaybackPositionCommand.isEnabled = false
  }

  /// Removes all remote command targets and clears now playing info.
  private func disableRemoteCommands() {
    guard isRegistered else { return }
    isRegistered = false

    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.removeTarget(nil)
    commandCenter.stopCommand.removeTarget(nil)
    commandCenter.pauseCommand.removeTarget(nil)
  }

  /// Clears the now playing info from the lock screen.
  private func clearNowPlaying() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    disableRemoteCommands()
  }
}

import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var nowPlayingPlugin: NowPlayingPlugin?
  private var speechRecognitionPlugin: SpeechRecognitionPlugin?
  private var speechSynthesisPlugin: SpeechSynthesisPlugin?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      nowPlayingPlugin = NowPlayingPlugin(messenger: controller.binaryMessenger)
      speechRecognitionPlugin = SpeechRecognitionPlugin(messenger: controller.binaryMessenger)
      speechSynthesisPlugin = SpeechSynthesisPlugin(messenger: controller.binaryMessenger)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

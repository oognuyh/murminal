import Flutter
import UserNotifications

/// Native iOS plugin for local notifications via UNUserNotificationCenter.
///
/// Handles permission requests, notification posting with session payload,
/// and notification tap callbacks forwarded to the Flutter layer.
class NotificationPlugin: NSObject, UNUserNotificationCenterDelegate {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.murminal/notifications",
      binaryMessenger: messenger,
    )
    super.init()
    channel.setMethodCallHandler(handle)
    UNUserNotificationCenter.current().delegate = self
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermission":
      requestPermission(result: result)

    case "showNotification":
      guard let args = call.arguments as? [String: Any],
            let id = args["id"] as? String,
            let title = args["title"] as? String,
            let body = args["body"] as? String else {
        result(FlutterError(
          code: "INVALID_ARGS",
          message: "Missing required notification arguments",
          details: nil
        ))
        return
      }
      let sessionName = args["sessionName"] as? String ?? ""
      let priority = args["priority"] as? String ?? "normal"
      showNotification(
        id: id,
        title: title,
        body: body,
        sessionName: sessionName,
        priority: priority,
        result: result
      )

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Request notification permission from the user.
  private func requestPermission(result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(
            code: "PERMISSION_ERROR",
            message: error.localizedDescription,
            details: nil
          ))
        } else {
          result(granted)
        }
      }
    }
  }

  /// Post a local notification with the given content.
  private func showNotification(
    id: String,
    title: String,
    body: String,
    sessionName: String,
    priority: String,
    result: @escaping FlutterResult
  ) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.userInfo = ["sessionName": sessionName]

    // Set interruption level based on priority.
    if #available(iOS 15.0, *) {
      content.interruptionLevel = priority == "high"
        ? .timeSensitive
        : .active
    }

    // Use sound for high-priority notifications.
    if priority == "high" {
      content.sound = .default
    }

    // Deliver immediately (no trigger delay).
    let request = UNNotificationRequest(
      identifier: id,
      content: content,
      trigger: nil
    )

    UNUserNotificationCenter.current().add(request) { error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(
            code: "NOTIFICATION_ERROR",
            message: error.localizedDescription,
            details: nil
          ))
        } else {
          result(nil)
        }
      }
    }
  }

  // MARK: - UNUserNotificationCenterDelegate

  /// Called when a notification is delivered while the app is in the foreground.
  ///
  /// Shows the notification banner even when the app is active, so the user
  /// sees pattern match alerts without switching away.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  /// Called when the user taps a notification.
  ///
  /// Extracts the session name from the notification payload and forwards
  /// it to the Flutter layer for navigation.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    if let sessionName = userInfo["sessionName"] as? String {
      channel.invokeMethod("onNotificationTap", arguments: sessionName)
    }
    completionHandler()
  }
}

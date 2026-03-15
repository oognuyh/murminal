import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:murminal/data/models/detected_state.dart';
import 'package:murminal/data/models/pattern_match_event.dart';

/// Manages iOS local notifications via UNUserNotificationCenter.
///
/// Uses a platform method channel to bridge Flutter with the native
/// iOS notification API. Handles permission requests, notification
/// posting, and notification tap callbacks for session navigation.
class NotificationService {
  static const _tag = 'NotificationService';
  static const _channel = MethodChannel('com.murminal/notifications');

  /// Emits the session name when the user taps a notification.
  final _tapController = StreamController<String>.broadcast();

  /// Whether notification permission has been granted.
  bool _permissionGranted = false;

  /// Stream of session names from notification taps.
  ///
  /// Consumers can use this to navigate to the relevant session.
  Stream<String> get onNotificationTap => _tapController.stream;

  /// Whether the user has granted notification permission.
  bool get hasPermission => _permissionGranted;

  NotificationService() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  /// Handles incoming method calls from the native iOS layer.
  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onNotificationTap':
        final sessionName = call.arguments as String?;
        if (sessionName != null) {
          _tapController.add(sessionName);
          developer.log(
            'Notification tapped for session: $sessionName',
            name: _tag,
          );
        }
    }
  }

  /// Request notification permission from the user.
  ///
  /// Returns `true` if permission was granted. The result is cached
  /// so subsequent calls return immediately.
  Future<bool> requestPermission() async {
    if (_permissionGranted) return true;

    try {
      final granted =
          await _channel.invokeMethod<bool>('requestPermission') ?? false;
      _permissionGranted = granted;
      developer.log('Notification permission: $granted', name: _tag);
      return granted;
    } on PlatformException catch (e) {
      developer.log('Failed to request permission: $e', name: _tag);
      return false;
    }
  }

  /// Show a local notification for a pattern match event.
  ///
  /// The notification title is derived from the session name and
  /// detected state type. The body contains the report text.
  /// A [sessionName] payload is attached so tapping the notification
  /// can navigate to the relevant session.
  ///
  /// No-op if notification permission has not been granted.
  Future<void> showPatternMatchNotification(PatternMatchEvent event) async {
    if (!_permissionGranted) return;
    if (!event.shouldReport) return;

    final title = _titleForEvent(event);
    final body = event.reportText.replaceFirst('[REPORT] ', '');

    try {
      await _channel.invokeMethod<void>('showNotification', {
        'id': '${event.sessionName}_${event.timestamp.millisecondsSinceEpoch}',
        'title': title,
        'body': body,
        'sessionName': event.sessionName,
        'priority': event.priority.name,
      });

      developer.log(
        'Posted notification for session "${event.sessionName}"',
        name: _tag,
      );
    } on PlatformException catch (e) {
      developer.log('Failed to post notification: $e', name: _tag);
    }
  }

  /// Build a notification title from the event type and session.
  String _titleForEvent(PatternMatchEvent event) {
    final sessionLabel = event.sessionName;
    return switch (event.detectedState.type) {
      DetectedStateType.error => 'Error in $sessionLabel',
      DetectedStateType.question => 'Input needed in $sessionLabel',
      DetectedStateType.complete => 'Completed in $sessionLabel',
      DetectedStateType.thinking => 'Processing in $sessionLabel',
      DetectedStateType.idle => 'Status: $sessionLabel',
    };
  }

  /// Release all resources. The service must not be used after this.
  void dispose() {
    _tapController.close();
    _channel.setMethodCallHandler(null);
  }
}

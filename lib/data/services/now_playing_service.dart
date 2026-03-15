import 'dart:async';

import 'package:flutter/services.dart';
import 'package:murminal/data/models/voice_supervisor_state.dart';

/// Manages lock screen and Control Center media controls on iOS.
///
/// Bridges Flutter with the native MPNowPlayingInfoCenter and
/// MPRemoteCommandCenter via a platform method channel. Displays
/// "Murminal" as the title with the current voice session status
/// as the subtitle, and forwards play/stop commands back to the
/// app so the Voice Supervisor can start or stop a session.
///
/// Works alongside [AudioSessionService] which holds the
/// AVAudioSession in `playAndRecord` mode — this service only
/// controls the metadata and remote command targets shown on the
/// lock screen and in Control Center.
class NowPlayingService {
  static const _channel = MethodChannel('com.murminal/now_playing');

  final _playController = StreamController<void>.broadcast();
  final _stopController = StreamController<void>.broadcast();

  bool _commandsEnabled = false;

  /// Emits when the user taps Play on the lock screen or Control Center.
  Stream<void> get onPlay => _playController.stream;

  /// Emits when the user taps Stop/Pause on the lock screen or Control Center.
  Stream<void> get onStop => _stopController.stream;

  NowPlayingService() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  /// Handles incoming method calls from the native iOS layer.
  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onPlay':
        _playController.add(null);
      case 'onStop':
        _stopController.add(null);
    }
  }

  /// Enables remote command handling on the native side.
  ///
  /// Call this once when the app starts or when the first voice
  /// session is created. Registers play/stop/pause targets on
  /// MPRemoteCommandCenter so the lock screen shows controls.
  Future<void> enable() async {
    if (_commandsEnabled) return;
    _commandsEnabled = true;
    await _channel.invokeMethod<void>('enableCommands');
    await updateSessionState(VoiceSupervisorState.idle);
  }

  /// Updates the lock screen now playing info to reflect the
  /// current voice session state.
  ///
  /// The title is always "Murminal". The subtitle is derived
  /// from the [VoiceSupervisorState] to give the user a quick
  /// status glance without unlocking the device.
  Future<void> updateSessionState(VoiceSupervisorState state) async {
    final subtitle = _subtitleForState(state);
    await _channel.invokeMethod<void>('updateNowPlaying', {
      'title': 'Murminal',
      'subtitle': subtitle,
    });
  }

  /// Clears the now playing info and disables remote commands.
  ///
  /// Call this when the app is terminating or when voice features
  /// are completely disabled.
  Future<void> disable() async {
    _commandsEnabled = false;
    await _channel.invokeMethod<void>('clearNowPlaying');
  }

  /// Maps a [VoiceSupervisorState] to a human-readable subtitle
  /// for the lock screen display.
  String _subtitleForState(VoiceSupervisorState state) {
    return switch (state) {
      VoiceSupervisorState.idle => 'Session idle',
      VoiceSupervisorState.connecting => 'Connecting...',
      VoiceSupervisorState.listening => 'Listening',
      VoiceSupervisorState.processing => 'Processing command',
      VoiceSupervisorState.speaking => 'Speaking',
      VoiceSupervisorState.interrupted => 'Interrupted — waiting to resume',
      VoiceSupervisorState.error => 'Error — tap play to retry',
    };
  }

  /// Releases all resources held by this service.
  void dispose() {
    _playController.close();
    _stopController.close();
    _channel.setMethodCallHandler(null);
  }
}

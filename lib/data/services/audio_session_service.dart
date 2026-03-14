import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:murminal/data/models/audio_session_state.dart';

/// Manages the iOS AVAudioSession for background voice operation.
///
/// Configures the audio session with the `playAndRecord` category so
/// that both microphone input and speaker output work simultaneously,
/// including while the app is in the background (paired with the
/// `UIBackgroundModes: audio` Info.plist entry).
///
/// Exposes a [stateStream] that emits [AudioSessionState] changes so
/// the Voice Supervisor can react to interruptions (phone calls, Siri,
/// other apps) and resume automatically when possible.
class AudioSessionService {
  AudioSession? _session;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;

  final _stateController =
      StreamController<AudioSessionState>.broadcast();

  /// Stream of audio session state changes.
  ///
  /// Emits [AudioSessionState.active] after a successful [activate],
  /// [AudioSessionState.interrupted] when the system interrupts audio,
  /// and [AudioSessionState.deactivated] after [deactivate] or when
  /// an interruption ends without the ability to resume.
  Stream<AudioSessionState> get stateStream => _stateController.stream;

  /// Current cached state. Defaults to [AudioSessionState.deactivated].
  AudioSessionState _currentState = AudioSessionState.deactivated;
  AudioSessionState get currentState => _currentState;

  /// Configures and activates the audio session.
  ///
  /// Sets the AVAudioSession category to `playAndRecord` with
  /// `defaultToSpeaker` and `allowBluetooth` so that audio works
  /// through the device speaker, wired headset, or Bluetooth.
  ///
  /// Subscribes to system interruption events to handle incoming
  /// phone calls and other audio route changes.
  Future<void> activate() async {
    _session = await AudioSession.instance;

    await _session!.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
                AVAudioSessionCategoryOptions.allowBluetooth |
                AVAudioSessionCategoryOptions.allowBluetoothA2dp,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
      ),
    );

    final activated = await _session!.setActive(true);
    if (activated) {
      _updateState(AudioSessionState.active);
    }

    _interruptionSub?.cancel();
    _interruptionSub = _session!.interruptionEventStream.listen(
      _handleInterruption,
    );
  }

  /// Deactivates the audio session and releases resources.
  ///
  /// After calling this method the microphone and speaker are no longer
  /// held by the app, allowing other apps to claim the audio route.
  Future<void> deactivate() async {
    _interruptionSub?.cancel();
    _interruptionSub = null;

    if (_session != null) {
      await _session!.setActive(false);
    }

    _updateState(AudioSessionState.deactivated);
  }

  /// Handles system audio interruptions.
  ///
  /// When an interruption begins (e.g. incoming phone call), the state
  /// moves to [AudioSessionState.interrupted]. When the interruption
  /// ends, the session is automatically reactivated if the system
  /// indicates it should resume.
  void _handleInterruption(AudioInterruptionEvent event) {
    switch (event.begin) {
      case true:
        _updateState(AudioSessionState.interrupted);
      case false:
        if (event.type == AudioInterruptionType.pause) {
          // The interruption ended and we should resume playback.
          _resumeAfterInterruption();
        } else {
          // Duck-type interruption ended; restore full volume.
          _updateState(AudioSessionState.active);
        }
    }
  }

  /// Attempts to reactivate the audio session after an interruption.
  Future<void> _resumeAfterInterruption() async {
    try {
      if (_session != null) {
        final activated = await _session!.setActive(true);
        _updateState(
          activated
              ? AudioSessionState.active
              : AudioSessionState.deactivated,
        );
      }
    } catch (_) {
      _updateState(AudioSessionState.deactivated);
    }
  }

  void _updateState(AudioSessionState state) {
    _currentState = state;
    _stateController.add(state);
  }

  /// Releases all resources held by this service.
  ///
  /// Call this when the service is permanently disposed.
  void dispose() {
    _interruptionSub?.cancel();
    _stateController.close();
  }
}

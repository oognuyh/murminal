import 'dart:developer' as developer;

import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provides short audio feedback cues for voice pipeline events.
///
/// Plays distinct sounds for command recognition, success, and error
/// states. Playback can be toggled via [enabled], which persists the
/// preference in [SharedPreferences].
///
/// Uses [just_audio] for low-latency asset playback. Each sound type
/// has a dedicated [AudioPlayer] instance so overlapping cues do not
/// cancel each other.
class FeedbackSoundService {
  static const _tag = 'FeedbackSoundService';
  static const _prefKey = 'feedback_sounds_enabled';

  static const _successAsset = 'assets/sounds/success.wav';
  static const _errorAsset = 'assets/sounds/error.wav';
  static const _recognizedAsset = 'assets/sounds/recognized.wav';

  final SharedPreferences _prefs;

  final AudioPlayer _successPlayer = AudioPlayer();
  final AudioPlayer _errorPlayer = AudioPlayer();
  final AudioPlayer _recognizedPlayer = AudioPlayer();

  bool _enabled;
  bool _initialized = false;

  FeedbackSoundService(this._prefs)
      : _enabled = _prefs.getBool(_prefKey) ?? true;

  /// Whether feedback sounds are enabled.
  bool get enabled => _enabled;

  /// Enable or disable feedback sounds. Persists the preference.
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _prefs.setBool(_prefKey, value);
    developer.log('Feedback sounds ${value ? "enabled" : "disabled"}',
        name: _tag);
  }

  /// Pre-load audio assets for minimal first-play latency.
  ///
  /// Call once after construction (e.g. during app startup). Subsequent
  /// calls are no-ops.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Future.wait([
        _successPlayer.setAsset(_successAsset),
        _errorPlayer.setAsset(_errorAsset),
        _recognizedPlayer.setAsset(_recognizedAsset),
      ]);
      _initialized = true;
      developer.log('Audio assets preloaded', name: _tag);
    } catch (e) {
      developer.log('Failed to preload audio assets: $e', name: _tag);
    }
  }

  /// Play a short ascending chime indicating successful execution.
  Future<void> playSuccess() => _play(_successPlayer, 'success');

  /// Play a short descending tone indicating an error.
  Future<void> playError() => _play(_errorPlayer, 'error');

  /// Play a subtle click/beep indicating command recognition.
  Future<void> playRecognized() => _play(_recognizedPlayer, 'recognized');

  /// Release all player resources. Do not reuse after calling this.
  Future<void> dispose() async {
    await Future.wait([
      _successPlayer.dispose(),
      _errorPlayer.dispose(),
      _recognizedPlayer.dispose(),
    ]);
  }

  Future<void> _play(AudioPlayer player, String label) async {
    if (!_enabled) return;

    try {
      await player.seek(Duration.zero);
      await player.play();
    } catch (e) {
      developer.log('Failed to play $label sound: $e', name: _tag);
    }
  }
}

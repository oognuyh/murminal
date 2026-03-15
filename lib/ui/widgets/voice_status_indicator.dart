import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/voice_supervisor_state.dart';

/// Color constants matching the app design system.
const _cyanColor = Color(0xFF22D3EE);
const _idleColor = Color(0xFF475569);
const _errorColor = Color(0xFFEF4444);

/// Default icon size for the voice status indicator.
const _defaultIconSize = 24.0;

/// Number of bars in the waveform visualization.
const _waveformBarCount = 5;

/// Animated indicator that reflects the current [VoiceSupervisorState].
///
/// Each state maps to a distinct visual treatment:
/// - [VoiceSupervisorState.idle]: static mic icon in slate gray.
/// - [VoiceSupervisorState.listening]: oscillating waveform bars in cyan.
/// - [VoiceSupervisorState.processing]: cyan circular progress spinner.
/// - [VoiceSupervisorState.speaking]: pulsing/scaling mic icon in cyan.
/// - [VoiceSupervisorState.connecting]: rotating sync icon in cyan.
/// - [VoiceSupervisorState.error]: shaking mic-off icon in red.
class VoiceStatusIndicator extends StatefulWidget {
  /// The current voice supervisor state to visualize.
  final VoiceSupervisorState state;

  /// The size of the indicator. Defaults to [_defaultIconSize].
  final double size;

  const VoiceStatusIndicator({
    super.key,
    required this.state,
    this.size = _defaultIconSize,
  });

  @override
  State<VoiceStatusIndicator> createState() => _VoiceStatusIndicatorState();
}

class _VoiceStatusIndicatorState extends State<VoiceStatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(VoiceStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _syncAnimation();
    }
  }

  /// Starts or stops the animation controller based on the current state.
  void _syncAnimation() {
    if (widget.state == VoiceSupervisorState.idle) {
      _controller.stop();
      _controller.reset();
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(child: _buildForState()),
    );
  }

  Widget _buildForState() {
    return switch (widget.state) {
      VoiceSupervisorState.idle => _buildIdle(),
      VoiceSupervisorState.listening => _buildListening(),
      VoiceSupervisorState.processing => _buildProcessing(),
      VoiceSupervisorState.speaking => _buildSpeaking(),
      VoiceSupervisorState.connecting => _buildConnecting(),
      VoiceSupervisorState.error => _buildError(),
    };
  }

  /// Static mic icon in slate gray.
  Widget _buildIdle() {
    return Icon(
      Icons.mic,
      size: widget.size,
      color: _idleColor,
    );
  }

  /// Animated waveform bars that oscillate at staggered phases.
  Widget _buildListening() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(_waveformBarCount, (index) {
            // Each bar oscillates with a phase offset for a wave effect.
            final phase = index / _waveformBarCount * 2 * math.pi;
            final sinValue = math.sin(_controller.value * 2 * math.pi + phase);
            // Map sine [-1, 1] to height fraction [0.3, 1.0].
            final heightFraction = 0.3 + 0.7 * ((sinValue + 1) / 2);
            final barWidth = widget.size / (_waveformBarCount * 2);

            return Container(
              margin: EdgeInsets.symmetric(horizontal: barWidth * 0.25),
              width: barWidth,
              height: widget.size * heightFraction,
              decoration: BoxDecoration(
                color: _cyanColor,
                borderRadius: BorderRadius.circular(barWidth / 2),
              ),
            );
          }),
        );
      },
    );
  }

  /// Cyan circular progress indicator.
  Widget _buildProcessing() {
    final strokeWidth = math.max(2.0, widget.size / 12);
    return SizedBox(
      width: widget.size * 0.8,
      height: widget.size * 0.8,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: const AlwaysStoppedAnimation<Color>(_cyanColor),
      ),
    );
  }

  /// Pulsing mic icon that scales between 0.85 and 1.15.
  Widget _buildSpeaking() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 0.85 + 0.3 * (0.5 + 0.5 * math.sin(
          _controller.value * 2 * math.pi,
        ));
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: Icon(
        Icons.mic,
        size: widget.size,
        color: _cyanColor,
      ),
    );
  }

  /// Rotating sync icon in cyan.
  Widget _buildConnecting() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * math.pi,
          child: child,
        );
      },
      child: Icon(
        Icons.sync,
        size: widget.size,
        color: _cyanColor,
      ),
    );
  }

  /// Red mic-off icon with a horizontal shake animation.
  Widget _buildError() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Rapid shake: small horizontal oscillation that decays.
        final shakeProgress = _controller.value;
        final decay = 1.0 - shakeProgress;
        final offset = math.sin(shakeProgress * 8 * math.pi) * 3.0 * decay;
        return Transform.translate(
          offset: Offset(offset, 0),
          child: child,
        );
      },
      child: Icon(
        Icons.mic_off,
        size: widget.size,
        color: _errorColor,
      ),
    );
  }
}

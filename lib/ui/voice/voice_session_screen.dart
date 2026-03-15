import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:murminal/core/providers.dart';
import 'package:murminal/data/models/session.dart';
import 'package:murminal/data/models/voice_supervisor_state.dart';

/// Theme colors matching the app's dark slate design.
const _background = Color(0xFF0A0F1C);
const _surface = Color(0xFF1E293B);
const _accent = Color(0xFF22D3EE);
const _green = Color(0xFF4ADE80);
const _textPrimary = Color(0xFFFFFFFF);
const _textSecondary = Color(0xFF94A3B8);
const _textTertiary = Color(0xFF64748B);
const _amber = Color(0xFFFBBF24);
const _errorRed = Color(0xFFF87171);

/// Number of bars in the audio waveform visualization.
const _waveformBarCount = 24;

/// Voice session full-screen overlay matching the pen wireframe design.
///
/// Displays:
/// - Green "VOICE SESSION ACTIVE" banner with elapsed timer at top
/// - Real-time audio waveform visualization (cyan bars)
/// - State text: "Listening...", "Speaking...", "Processing..."
/// - Current transcription text in quotes
/// - Session/server count info
/// - Square stop button with "Tap to stop" label
/// - SESSION STATUS section listing active sessions
class VoiceSessionScreen extends ConsumerStatefulWidget {
  /// The server ID to run the voice session against.
  final String serverId;

  const VoiceSessionScreen({
    super.key,
    required this.serverId,
  });

  @override
  ConsumerState<VoiceSessionScreen> createState() =>
      _VoiceSessionScreenState();
}

class _VoiceSessionScreenState extends ConsumerState<VoiceSessionScreen>
    with TickerProviderStateMixin {
  late final AnimationController _waveformController;
  late final AnimationController _pulseController;

  DateTime? _sessionStartTime;
  Timer? _timerTick;
  String _elapsedText = '00:00';
  final String _currentTranscription = '';

  @override
  void initState() {
    super.initState();

    _waveformController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _sessionStartTime = DateTime.now();
    _timerTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsedText = _formatElapsed();
        });
      }
    });

    // Start the voice supervisor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startVoiceSession();
    });
  }

  @override
  void dispose() {
    _waveformController.dispose();
    _pulseController.dispose();
    _timerTick?.cancel();
    super.dispose();
  }

  Future<void> _startVoiceSession() async {
    final apiKey = await ref.read(voiceApiKeyProvider.future);
    if (apiKey == null || apiKey.isEmpty) return;

    final provider = ref.read(voiceProviderSettingProvider);
    final supervisor = ref.read(voiceSupervisorProvider(widget.serverId));
    await supervisor.start(apiKey, useLocal: provider.isLocal);
  }

  Future<void> _stopVoiceSession() async {
    final supervisor = ref.read(voiceSupervisorProvider(widget.serverId));
    await supervisor.stop();
    if (mounted) {
      context.go('/');
    }
  }

  String _formatElapsed() {
    if (_sessionStartTime == null) return '00:00';
    final elapsed = DateTime.now().difference(_sessionStartTime!);
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (elapsed.inHours > 0) {
      final hours = elapsed.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String _stateLabel(VoiceSupervisorState state) {
    return switch (state) {
      VoiceSupervisorState.idle => 'Ready',
      VoiceSupervisorState.connecting => 'Connecting...',
      VoiceSupervisorState.listening => 'Listening...',
      VoiceSupervisorState.processing => 'Processing...',
      VoiceSupervisorState.speaking => 'Speaking...',
      VoiceSupervisorState.interrupted => 'Interrupted',
      VoiceSupervisorState.error => 'Error',
    };
  }

  Color _stateColor(VoiceSupervisorState state) {
    return switch (state) {
      VoiceSupervisorState.listening => _accent,
      VoiceSupervisorState.speaking => _green,
      VoiceSupervisorState.processing => _amber,
      VoiceSupervisorState.connecting => _textSecondary,
      VoiceSupervisorState.interrupted => _amber,
      VoiceSupervisorState.error => _errorRed,
      VoiceSupervisorState.idle => _textSecondary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final supervisorState = ref.watch(
      voiceSupervisorStateProvider(widget.serverId),
    );
    final state =
        supervisorState.valueOrNull ?? VoiceSupervisorState.connecting;
    final sessionsAsync = ref.watch(allSessionsProvider);
    final servers = ref.watch(serverListProvider);

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            // Green active banner with timer.
            _buildActiveBanner(state),
            // Main content area.
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),
                  // Audio waveform visualization.
                  _buildWaveform(state),
                  const SizedBox(height: 32),
                  // State text.
                  _buildStateText(state),
                  const SizedBox(height: 16),
                  // Current transcription.
                  _buildTranscription(state),
                  const SizedBox(height: 24),
                  // Session/server count info.
                  sessionsAsync.when(
                    data: (sessions) => _buildInfoLine(sessions, servers),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  const Spacer(flex: 2),
                  // Stop button.
                  _buildStopButton(),
                  const SizedBox(height: 12),
                  const Text(
                    'Tap to stop',
                    style: TextStyle(
                      color: _textTertiary,
                      fontSize: 13,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            // Session status section at bottom.
            sessionsAsync.when(
              data: (sessions) => _buildSessionStatusSection(sessions),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  /// Green banner showing "VOICE SESSION ACTIVE" and elapsed timer.
  Widget _buildActiveBanner(VoiceSupervisorState state) {
    final isActive = state != VoiceSupervisorState.idle &&
        state != VoiceSupervisorState.error;
    final bannerColor = isActive ? _green : _errorRed;
    final label = isActive ? 'VOICE SESSION ACTIVE' : 'SESSION ERROR';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      color: bannerColor.withValues(alpha: 0.15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: bannerColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$label \u00B7 $_elapsedText',
            style: TextStyle(
              color: bannerColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'JetBrains Mono',
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  /// Audio waveform visualization with cyan animated bars.
  Widget _buildWaveform(VoiceSupervisorState state) {
    final isAnimating = state == VoiceSupervisorState.listening ||
        state == VoiceSupervisorState.speaking;

    return SizedBox(
      height: 80,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _waveformController,
        builder: (context, _) {
          return CustomPaint(
            painter: _WaveformPainter(
              animationValue: _waveformController.value,
              isAnimating: isAnimating,
              barCount: _waveformBarCount,
              color: _accent,
              state: state,
            ),
          );
        },
      ),
    );
  }

  /// Large state text: "Listening...", "Speaking...", etc.
  Widget _buildStateText(VoiceSupervisorState state) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Text(
        _stateLabel(state),
        key: ValueKey(state),
        style: TextStyle(
          color: _stateColor(state),
          fontSize: 28,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
      ),
    );
  }

  /// Current command/transcription displayed in quotes.
  Widget _buildTranscription(VoiceSupervisorState state) {
    // Listen to text events from the supervisor via voice events.
    // For now, show a placeholder when in listening state.
    final text = _currentTranscription.isNotEmpty
        ? '"$_currentTranscription"'
        : state == VoiceSupervisorState.listening
            ? ''
            : '';

    if (text.isEmpty) return const SizedBox(height: 20);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Text(
        text,
        style: const TextStyle(
          color: _textSecondary,
          fontSize: 16,
          fontStyle: FontStyle.italic,
          fontFamily: 'Inter',
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Info line: "3 sessions \u00B7 2 servers".
  Widget _buildInfoLine(List<Session> sessions, List<dynamic> servers) {
    final sessionCount = sessions.length;
    final serverCount = servers.length;
    final sessionLabel = sessionCount == 1 ? 'session' : 'sessions';
    final serverLabel = serverCount == 1 ? 'server' : 'servers';

    return Text(
      '$sessionCount $sessionLabel \u00B7 $serverCount $serverLabel',
      style: const TextStyle(
        color: _textTertiary,
        fontSize: 13,
        fontFamily: 'JetBrains Mono',
      ),
    );
  }

  /// Square stop button with white outline.
  Widget _buildStopButton() {
    return GestureDetector(
      onTap: _stopVoiceSession,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final scale = 1.0 + 0.05 * _pulseController.value;
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            border: Border.all(color: _textPrimary, width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: _textPrimary,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// SESSION STATUS section at the bottom listing active sessions.
  Widget _buildSessionStatusSection(List<Session> sessions) {
    if (sessions.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Section label.
          Row(
            children: [
              Text(
                'SESSION STATUS',
                style: TextStyle(
                  color: _textSecondary.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 1,
                  color: _textSecondary.withValues(alpha: 0.15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Session list (max 4 shown to avoid overflow).
          ...sessions.take(4).map(_buildSessionRow),
        ],
      ),
    );
  }

  /// Individual session row in the status section.
  Widget _buildSessionRow(Session session) {
    final (Color color, String label) = switch (session.status) {
      SessionStatus.running => (_green, 'RUNNING'),
      SessionStatus.done => (_textSecondary, 'DONE'),
      SessionStatus.idle => (_amber, 'IDLE'),
      SessionStatus.error => (_errorRed, 'ERROR'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Status dot.
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          // Session name.
          Expanded(
            child: Text(
              session.name,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 13,
                fontFamily: 'JetBrains Mono',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Status label.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFamily: 'JetBrains Mono',
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the audio waveform visualization.
///
/// Draws [barCount] vertical bars centered horizontally. When [isAnimating]
/// is true, bar heights oscillate using sine waves with staggered phases
/// to create a wave effect. When not animating, bars settle to a low
/// baseline height.
class _WaveformPainter extends CustomPainter {
  final double animationValue;
  final bool isAnimating;
  final int barCount;
  final Color color;
  final VoiceSupervisorState state;

  _WaveformPainter({
    required this.animationValue,
    required this.isAnimating,
    required this.barCount,
    required this.color,
    required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final barWidth = (size.width * 0.6) / (barCount * 1.8);
    final gap = barWidth * 0.8;
    final totalWidth = barCount * barWidth + (barCount - 1) * gap;
    final startX = (size.width - totalWidth) / 2;

    for (var i = 0; i < barCount; i++) {
      final x = startX + i * (barWidth + gap);

      double heightFraction;
      if (isAnimating) {
        // Create a multi-frequency wave pattern for organic feel.
        final phase1 = i / barCount * 2 * math.pi;
        final phase2 = i / barCount * 4 * math.pi;
        final wave1 = math.sin(animationValue * 2 * math.pi + phase1);
        final wave2 = math.sin(animationValue * 3 * math.pi + phase2) * 0.5;
        final combined = (wave1 + wave2) / 1.5;
        // Map to [0.15, 1.0] range.
        heightFraction = 0.15 + 0.85 * ((combined + 1) / 2);

        // Speaking state has more energy (taller bars on average).
        if (state == VoiceSupervisorState.speaking) {
          heightFraction = 0.3 + 0.7 * heightFraction;
        }
      } else {
        // Idle baseline: low uniform bars.
        heightFraction = 0.1;
      }

      final barHeight = size.height * heightFraction;
      final y = (size.height - barHeight) / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isAnimating != isAnimating ||
        oldDelegate.state != state;
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:murminal/data/services/ssh_service.dart' as ssh;

/// Theme colors matching the app's dark slate design.
const _surface = Color(0xFF1E293B);
const _amber = Color(0xFFF59E0B);
const _red = Color(0xFFEF4444);
const _green = Color(0xFF4ADE80);
const _textPrimary = Color(0xFFFFFFFF);
const _textSecondary = Color(0xFF94A3B8);

/// Animated banner displayed during SSH reconnection attempts.
///
/// Shows the current attempt number, a progress indicator, and the
/// reconnection status. Automatically hides when the connection is
/// restored. Displays a failure message when all attempts are exhausted.
class SshReconnectionBanner extends StatefulWidget {
  /// The latest reconnection event to display.
  final ssh.SshReconnectionEvent? event;

  /// The current SSH connection state.
  final ssh.ConnectionState connectionState;

  /// Callback invoked when the user dismisses the failure banner.
  final VoidCallback? onDismiss;

  const SshReconnectionBanner({
    super.key,
    this.event,
    required this.connectionState,
    this.onDismiss,
  });

  @override
  State<SshReconnectionBanner> createState() => _SshReconnectionBannerState();
}

class _SshReconnectionBannerState extends State<SshReconnectionBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only show during reconnecting or when showing final failure.
    if (widget.connectionState == ssh.ConnectionState.connected) {
      // Briefly show success state if we just reconnected.
      if (widget.event != null && widget.event!.succeeded) {
        return _buildSuccessBanner();
      }
      return const SizedBox.shrink();
    }

    if (widget.connectionState != ssh.ConnectionState.reconnecting) {
      // Show failure banner if all attempts exhausted.
      if (widget.event != null &&
          !widget.event!.succeeded &&
          widget.event!.attempt >= widget.event!.maxAttempts &&
          widget.connectionState == ssh.ConnectionState.disconnected) {
        return _buildFailureBanner();
      }
      return const SizedBox.shrink();
    }

    return _buildReconnectingBanner();
  }

  Widget _buildReconnectingBanner() {
    final event = widget.event;
    final attempt = event?.attempt ?? 0;
    final maxAttempts = event?.maxAttempts ?? ssh.SshService.defaultMaxReconnectAttempts;
    final progress = attempt / maxAttempts;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final opacity = 0.85 + 0.15 * _pulseController.value;
        return Opacity(opacity: opacity, child: child);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _surface,
          border: Border(
            bottom: BorderSide(
              color: _amber.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // Animated sync icon.
            _RotatingIcon(
              icon: Icons.sync,
              color: _amber,
              size: 18,
              controller: _pulseController,
            ),
            const SizedBox(width: 12),
            // Status text.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Connection lost, reconnecting...',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Attempt $attempt of $maxAttempts',
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 11,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                ],
              ),
            ),
            // Progress indicator.
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 2.5,
                backgroundColor: _textSecondary.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation<Color>(_amber),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailureBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(
          bottom: BorderSide(
            color: _red.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: _red, size: 18),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Reconnection failed',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'All retry attempts exhausted. Check your network.',
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 11,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ],
            ),
          ),
          if (widget.onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close, color: _textSecondary, size: 16),
              onPressed: widget.onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  Widget _buildSuccessBanner() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.0, end: 0.0),
      duration: const Duration(seconds: 3),
      builder: (context, value, child) {
        if (value <= 0) return const SizedBox.shrink();
        return Opacity(opacity: value, child: child);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _surface,
          border: Border(
            bottom: BorderSide(
              color: _green.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: _green, size: 18),
            SizedBox(width: 12),
            Text(
              'Connection restored',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A continuously rotating icon widget.
class _RotatingIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final AnimationController controller;

  const _RotatingIcon({
    required this.icon,
    required this.color,
    required this.size,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: controller.value * 2 * math.pi,
          child: child,
        );
      },
      child: Icon(icon, color: color, size: size),
    );
  }
}

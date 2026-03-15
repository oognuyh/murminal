import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import 'package:murminal/core/providers.dart';

/// Theme colors matching the app's dark slate design.
const _background = Color(0xFF0A0F1C);
const _surface = Color(0xFF1E293B);
const _accent = Color(0xFF22D3EE);
const _textPrimary = Color(0xFFFFFFFF);
/// Default number of scrollback lines for the terminal buffer.
const _defaultScrollbackLines = 1000;

/// Interval between tmux capture-pane polls.
const _captureInterval = Duration(seconds: 1);

/// Number of tmux pane lines to capture per poll.
const _captureLines = 50;

/// Terminal theme matching the app's dark slate/cyan palette.
final _terminalTheme = TerminalTheme(
  cursor: _accent,
  selection: _accent.withValues(alpha: 0.3),
  foreground: _textPrimary,
  background: _background,
  black: const Color(0xFF0A0F1C),
  red: const Color(0xFFF87171),
  green: const Color(0xFF4ADE80),
  yellow: const Color(0xFFFBBF24),
  blue: const Color(0xFF60A5FA),
  magenta: const Color(0xFFC084FC),
  cyan: _accent,
  white: const Color(0xFFE2E8F0),
  brightBlack: const Color(0xFF475569),
  brightRed: const Color(0xFFFCA5A5),
  brightGreen: const Color(0xFF86EFAC),
  brightYellow: const Color(0xFFFDE68A),
  brightBlue: const Color(0xFF93C5FD),
  brightMagenta: const Color(0xFFD8B4FE),
  brightCyan: const Color(0xFF67E8F9),
  brightWhite: const Color(0xFFFFFFFF),
  searchHitBackground: _accent.withValues(alpha: 0.3),
  searchHitBackgroundCurrent: _accent.withValues(alpha: 0.6),
  searchHitForeground: _textPrimary,
);

/// Screen displaying a terminal view for a specific session.
///
/// Renders tmux capture-pane output in an xterm.dart [TerminalView] widget,
/// polling at regular intervals to stream SSH output in near real-time.
class SessionDetailScreen extends ConsumerStatefulWidget {
  /// The session ID to display.
  final String sessionId;

  /// The display name shown in the AppBar.
  final String sessionName;

  const SessionDetailScreen({
    super.key,
    required this.sessionId,
    required this.sessionName,
  });

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  late final Terminal _terminal;
  Timer? _pollTimer;
  String _lastOutput = '';

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: _defaultScrollbackLines);
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Start polling tmux capture-pane for terminal output.
  void _startPolling() {
    // Initial capture immediately.
    _captureOutput();
    _pollTimer = Timer.periodic(_captureInterval, (_) => _captureOutput());
  }

  /// Fetch the latest tmux pane content and write new output to the terminal.
  Future<void> _captureOutput() async {
    try {
      final tmux = ref.read(tmuxControllerProvider);
      final output = await tmux.capturePane(
        widget.sessionId,
        lines: _captureLines,
      );

      if (output == _lastOutput) return;

      // On first capture or when content changes, refresh the terminal.
      _terminal.eraseDisplay();
      _terminal.setCursor(0, 0);
      _terminal.write(output);
      _lastOutput = output;
    } catch (_) {
      // Silently ignore capture failures (session may have ended).
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.sessionName,
          style: const TextStyle(
            color: _textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'JetBrains Mono',
          ),
        ),
        actions: [
          // Session status indicator.
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
        elevation: 0,
      ),
      body: SafeArea(
        child: TerminalView(
          _terminal,
          theme: _terminalTheme,
          textStyle: const TerminalStyle(
            fontSize: 12,
            fontFamily: 'JetBrains Mono',
          ),
          padding: const EdgeInsets.all(8),
        ),
      ),
    );
  }
}

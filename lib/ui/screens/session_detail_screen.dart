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
const _textSecondary = Color(0xFF94A3B8);

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

/// Tmux key identifiers for special key buttons.
class _TmuxKeys {
  static const tab = 'Tab';
  static const escape = 'Escape';
  static const up = 'Up';
  static const down = 'Down';
  static const left = 'Left';
  static const right = 'Right';
  static const ctrlC = 'C-c';
  static const ctrlD = 'C-d';
  static const ctrlZ = 'C-z';
}

/// Screen displaying a terminal view for a specific session.
///
/// Renders tmux capture-pane output in an xterm.dart [TerminalView] widget,
/// polling at regular intervals to stream SSH output in near real-time.
/// Provides on-screen keyboard input with a fallback text bar and special
/// key buttons for Tab, Ctrl+C, arrow keys, and Escape.
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
  late final TextEditingController _inputController;
  late final FocusNode _inputFocusNode;
  Timer? _pollTimer;
  String _lastOutput = '';
  bool _showSpecialKeys = true;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: _defaultScrollbackLines);
    _inputController = TextEditingController();
    _inputFocusNode = FocusNode();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  /// Start polling tmux capture-pane for terminal output.
  void _startPolling() {
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

      _terminal.eraseDisplay();
      _terminal.setCursor(0, 0);
      _terminal.write(output);
      _lastOutput = output;
    } catch (_) {
      // Silently ignore capture failures (session may have ended).
    }
  }

  /// Send typed text to tmux as a command (with Enter).
  Future<void> _submitInput() async {
    final text = _inputController.text;
    if (text.isEmpty) return;

    try {
      final tmux = ref.read(tmuxControllerProvider);
      await tmux.sendKeys(widget.sessionId, text);
      _inputController.clear();
      // Trigger an immediate capture to show the result.
      _captureOutput();
    } catch (_) {
      // Ignore send failures.
    }
  }

  /// Send a special key to tmux without appending Enter.
  Future<void> _sendSpecialKey(String key) async {
    try {
      final tmux = ref.read(tmuxControllerProvider);
      await tmux.sendRawKeys(widget.sessionId, key);
      _captureOutput();
    } catch (_) {
      // Ignore send failures.
    }
  }

  /// Dismiss the on-screen keyboard.
  void _dismissKeyboard() {
    _inputFocusNode.unfocus();
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
          // Toggle special keys bar visibility.
          IconButton(
            icon: Icon(
              _showSpecialKeys ? Icons.keyboard_hide : Icons.keyboard,
              color: _textSecondary,
            ),
            onPressed: () {
              setState(() {
                _showSpecialKeys = !_showSpecialKeys;
              });
            },
            tooltip: _showSpecialKeys ? 'Hide special keys' : 'Show special keys',
          ),
          // Dismiss keyboard button.
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, color: _textSecondary),
            onPressed: _dismissKeyboard,
            tooltip: 'Dismiss keyboard',
          ),
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
        child: Column(
          children: [
            // Terminal view.
            Expanded(
              child: GestureDetector(
                onTap: () {
                  // Tap terminal to focus the input field.
                  _inputFocusNode.requestFocus();
                },
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
            ),
            // Special keys row.
            if (_showSpecialKeys) _buildSpecialKeysBar(),
            // Text input bar.
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  /// Build the special keys toolbar with common terminal keys.
  Widget _buildSpecialKeysBar() {
    return Container(
      color: _surface,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _specialKeyButton('Tab', _TmuxKeys.tab),
            _specialKeyButton('Esc', _TmuxKeys.escape),
            _specialKeyButton('Ctrl+C', _TmuxKeys.ctrlC),
            _specialKeyButton('Ctrl+D', _TmuxKeys.ctrlD),
            _specialKeyButton('Ctrl+Z', _TmuxKeys.ctrlZ),
            const SizedBox(width: 8),
            _specialKeyButton('\u2191', _TmuxKeys.up, tooltip: 'Up'),
            _specialKeyButton('\u2193', _TmuxKeys.down, tooltip: 'Down'),
            _specialKeyButton('\u2190', _TmuxKeys.left, tooltip: 'Left'),
            _specialKeyButton('\u2192', _TmuxKeys.right, tooltip: 'Right'),
          ],
        ),
      ),
    );
  }

  /// Build an individual special key button.
  Widget _specialKeyButton(String label, String tmuxKey, {String? tooltip}) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _sendSpecialKey(tmuxKey),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: _background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _accent.withValues(alpha: 0.3)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 12,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
  }

  /// Build the bottom text input bar for fallback typing.
  Widget _buildInputBar() {
    return Container(
      color: _surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          // Dollar-sign prompt indicator.
          const Text(
            '\$',
            style: TextStyle(
              color: _accent,
              fontSize: 14,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          // Text input field.
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocusNode,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 14,
                fontFamily: 'JetBrains Mono',
              ),
              decoration: const InputDecoration(
                hintText: 'Type command...',
                hintStyle: TextStyle(color: _textSecondary, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitInput(),
              autocorrect: false,
              enableSuggestions: false,
            ),
          ),
          // Send button.
          IconButton(
            icon: const Icon(Icons.send, color: _accent, size: 20),
            onPressed: _submitInput,
            tooltip: 'Send command',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import 'package:murminal/core/providers.dart';
import 'package:murminal/data/services/ssh_service.dart' as ssh;
import 'package:murminal/ui/widgets/ssh_reconnection_banner.dart';

/// Theme colors matching the app's dark slate design.
const _background = Color(0xFF0A0F1C);
const _surface = Color(0xFF1E293B);
const _accent = Color(0xFF22D3EE);
const _textPrimary = Color(0xFFFFFFFF);
const _textSecondary = Color(0xFF94A3B8);

/// Default number of scrollback lines for the terminal buffer.
const _defaultScrollbackLines = 1000;

/// Default PTY dimensions when the terminal view size is unknown.
const _defaultCols = 80;
const _defaultRows = 24;

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

/// ANSI escape sequences for special keys sent directly to the PTY.
class _PtyKeys {
  static final tab = Uint8List.fromList([0x09]);
  static final escape = Uint8List.fromList([0x1B]);
  static final ctrlC = Uint8List.fromList([0x03]);
  static final ctrlD = Uint8List.fromList([0x04]);
  static final ctrlZ = Uint8List.fromList([0x1A]);
  static final up = Uint8List.fromList(utf8.encode('\x1b[A'));
  static final down = Uint8List.fromList(utf8.encode('\x1b[B'));
  static final right = Uint8List.fromList(utf8.encode('\x1b[C'));
  static final left = Uint8List.fromList(utf8.encode('\x1b[D'));
}

/// Screen displaying an interactive terminal connected to a remote SSH PTY.
///
/// Establishes a direct PTY channel over SSH so that keyboard input flows
/// to the remote shell in real time and stdout is rendered immediately in
/// the xterm widget. Special key buttons (Tab, Ctrl+C, arrows, etc.) send
/// raw escape sequences to the PTY.
///
/// The xterm widget handles all keyboard input natively; no separate text
/// input bar is needed. tmux sessions still work inside the PTY shell.
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
  final _terminalKey = GlobalKey();
  ssh.SshPtySession? _ptySession;
  StreamSubscription<Uint8List>? _stdoutSub;
  bool _showSpecialKeys = true;
  bool _connecting = true;
  String? _errorMessage;

  /// Current PTY dimensions used for resize detection.
  int _currentCols = _defaultCols;
  int _currentRows = _defaultRows;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: _defaultScrollbackLines);

    // Listen for terminal output (user typing) and forward to PTY stdin.
    _terminal.onOutput = _onTerminalOutput;

    _initPtyConnection();
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();
    _ptySession?.close();
    super.dispose();
  }

  /// Establish the SSH PTY connection for this session's server.
  Future<void> _initPtyConnection() async {
    final sessionService = ref.read(sessionServiceProvider);
    final session = sessionService.getSession(widget.sessionId);

    if (session == null) {
      setState(() {
        _connecting = false;
        _errorMessage = 'Session not found';
      });
      return;
    }

    final pool = ref.read(sshConnectionPoolProvider);

    // Re-register the server config from persistent storage if the
    // pool lost it (e.g. after app restart).
    if (!pool.isConnected(session.serverId)) {
      final serverRepo = ref.read(serverRepositoryProvider);
      final serverConfig = serverRepo.getById(session.serverId);
      if (serverConfig != null) {
        pool.register(serverConfig);
      }
    }

    try {
      final sshService = await pool.getConnection(session.serverId);

      // Calculate initial terminal size from screen after first frame.
      final size = _estimateTerminalSize();
      _currentCols = size.$1;
      _currentRows = size.$2;

      final ptySession = await sshService.shell(
        cols: _currentCols,
        rows: _currentRows,
      );

      _ptySession = ptySession;

      // Forward PTY stdout to the xterm terminal widget.
      _stdoutSub = ptySession.stdout.listen(
        (data) {
          _terminal.write(String.fromCharCodes(data));
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _errorMessage = 'Connection closed';
            });
          }
        },
        onError: (Object error) {
          debugPrint('PTY stdout error: $error');
          if (mounted) {
            setState(() {
              _errorMessage = 'Connection error: $error';
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _connecting = false;
        });
      }

      // Schedule a resize after the terminal view is laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncTerminalSize();
      });
    } catch (e) {
      debugPrint('SSH PTY connection failed: $e');
      if (mounted) {
        setState(() {
          _connecting = false;
          _errorMessage = 'Connection failed: $e';
        });
      }
    }
  }

  /// Handle terminal output events (user keyboard input captured by xterm).
  void _onTerminalOutput(String data) {
    final pty = _ptySession;
    if (pty == null || pty.isClosed) return;
    pty.write(Uint8List.fromList(utf8.encode(data)));
  }

  /// Send raw bytes to the PTY (for special key buttons).
  void _sendToPty(Uint8List data) {
    final pty = _ptySession;
    if (pty == null || pty.isClosed) return;
    pty.write(data);
  }

  /// Estimate terminal dimensions from available screen space.
  (int cols, int rows) _estimateTerminalSize() {
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null) return (_defaultCols, _defaultRows);

    final screenWidth = mediaQuery.size.width - 16; // padding
    final screenHeight = mediaQuery.size.height * 0.7;
    // Approximate character dimensions for JetBrains Mono 12pt.
    const charWidth = 7.2;
    const charHeight = 16.0;
    final cols = (screenWidth / charWidth).floor().clamp(20, 300);
    final rows = (screenHeight / charHeight).floor().clamp(10, 100);
    return (cols, rows);
  }

  /// Recalculate terminal size and send resize to PTY if dimensions changed.
  void _syncTerminalSize() {
    final pty = _ptySession;
    if (pty == null || pty.isClosed) return;

    final size = _estimateTerminalSize();
    final newCols = size.$1;
    final newRows = size.$2;

    if (newCols != _currentCols || newRows != _currentRows) {
      _currentCols = newCols;
      _currentRows = newRows;
      pty.resize(newCols, newRows);
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
          // Session status indicator.
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _connecting
                      ? Colors.orange
                      : (_errorMessage != null ? Colors.red : _accent),
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
            // SSH reconnection banner.
            _buildReconnectionBanner(),
            // Terminal view or loading/error state.
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Sync terminal size on layout changes.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _syncTerminalSize();
                  });

                  if (_connecting) {
                    return const Center(
                      child: CircularProgressIndicator(color: _accent),
                    );
                  }

                  if (_errorMessage != null && _ptySession == null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: _textSecondary,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _connecting = true;
                                  _errorMessage = null;
                                });
                                _initPtyConnection();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accent,
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return TerminalView(
                    _terminal,
                    key: _terminalKey,
                    theme: _terminalTheme,
                    textStyle: const TerminalStyle(
                      fontSize: 12,
                      fontFamily: 'JetBrains Mono',
                    ),
                    padding: const EdgeInsets.all(8),
                    autofocus: true,
                    hardwareKeyboardOnly: false,
                  );
                },
              ),
            ),
            // Special keys row.
            if (_showSpecialKeys) _buildSpecialKeysBar(),
          ],
        ),
      ),
    );
  }

  /// Build the SSH reconnection banner that reacts to pool state.
  Widget _buildReconnectionBanner() {
    final reconnectAsync = ref.watch(sshReconnectionEventsProvider);
    final poolStatesAsync = ref.watch(poolConnectionStatesProvider);

    // Determine if any connection is reconnecting.
    final poolStates = poolStatesAsync.valueOrNull ?? {};
    final hasReconnecting = poolStates.values
        .any((s) => s == ssh.ConnectionState.reconnecting);
    final allDisconnected = poolStates.isNotEmpty &&
        poolStates.values
            .every((s) => s == ssh.ConnectionState.disconnected);

    // Determine effective connection state for the banner.
    ssh.ConnectionState effectiveState;
    if (hasReconnecting) {
      effectiveState = ssh.ConnectionState.reconnecting;
    } else if (allDisconnected) {
      effectiveState = ssh.ConnectionState.disconnected;
    } else {
      effectiveState = ssh.ConnectionState.connected;
    }

    final event = reconnectAsync.valueOrNull;

    return SshReconnectionBanner(
      event: event,
      connectionState: effectiveState,
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
            _specialKeyButton('Tab', _PtyKeys.tab),
            _specialKeyButton('Esc', _PtyKeys.escape),
            _specialKeyButton('Ctrl+C', _PtyKeys.ctrlC),
            _specialKeyButton('Ctrl+D', _PtyKeys.ctrlD),
            _specialKeyButton('Ctrl+Z', _PtyKeys.ctrlZ),
            const SizedBox(width: 8),
            _specialKeyButton('\u2191', _PtyKeys.up, tooltip: 'Up'),
            _specialKeyButton('\u2193', _PtyKeys.down, tooltip: 'Down'),
            _specialKeyButton('\u2190', _PtyKeys.left, tooltip: 'Left'),
            _specialKeyButton('\u2192', _PtyKeys.right, tooltip: 'Right'),
          ],
        ),
      ),
    );
  }

  /// Build an individual special key button.
  Widget _specialKeyButton(String label, Uint8List keyData, {String? tooltip}) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _sendToPty(keyData),
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
}

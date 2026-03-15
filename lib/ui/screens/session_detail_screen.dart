import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import 'package:murminal/core/providers.dart';
import 'package:murminal/data/models/session.dart';
import 'package:murminal/data/services/ssh_service.dart' as ssh;
import 'package:murminal/ui/widgets/ssh_reconnection_banner.dart';

/// Theme colors matching the app's dark slate design.
const _background = Color(0xFF0A0F1C);
const _surface = Color(0xFF1E293B);
const _accent = Color(0xFF22D3EE);
const _textPrimary = Color(0xFFFFFFFF);
const _textSecondary = Color(0xFF94A3B8);

/// Status badge colors.
const _statusRunning = Color(0xFF4ADE80);
const _statusDone = Color(0xFF94A3B8);
const _statusIdle = Color(0xFFFBBF24);
const _statusError = Color(0xFFF87171);

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
/// Shows a session info header card with engine name, server details, status
/// badge, and elapsed time above the terminal view. The header matches the
/// pen wireframe design with a dark card layout.
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
      // Use utf8.decode with allowMalformed to handle multi-byte
      // characters (emoji, CJK, icons) split across stream chunks.
      _stdoutSub = ptySession.stdout.listen(
        (data) {
          _terminal.write(utf8.decode(data, allowMalformed: true));
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

  /// Format elapsed time since session creation as a human-readable string.
  String _formatElapsedTime(DateTime createdAt) {
    final elapsed = DateTime.now().difference(createdAt);
    if (elapsed.inDays > 0) {
      return 'Started ${elapsed.inDays}d ago';
    } else if (elapsed.inHours > 0) {
      return 'Started ${elapsed.inHours}h ago';
    } else if (elapsed.inMinutes > 0) {
      return 'Started ${elapsed.inMinutes} min ago';
    }
    return 'Started just now';
  }

  /// Get the color for a session status badge.
  Color _statusColor(SessionStatus status) {
    switch (status) {
      case SessionStatus.running:
        return _statusRunning;
      case SessionStatus.done:
        return _statusDone;
      case SessionStatus.idle:
        return _statusIdle;
      case SessionStatus.error:
        return _statusError;
    }
  }

  /// Get the icon for an engine type.
  IconData _engineIcon(String engine) {
    switch (engine.toLowerCase()) {
      case 'claude':
        return Icons.auto_awesome;
      case 'codex':
        return Icons.code;
      case 'gemini':
        return Icons.diamond;
      default:
        return Icons.terminal;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Look up the full session and server data for the header card.
    final session = ref.watch(sessionProvider(widget.sessionId));
    final serverRepo = ref.read(serverRepositoryProvider);
    final serverConfig =
        session != null ? serverRepo.getById(session.serverId) : null;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Sessions',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
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
          // Kebab menu.
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: _textSecondary),
            color: _surface,
            onSelected: (value) {
              if (value == 'reconnect') {
                setState(() {
                  _connecting = true;
                  _errorMessage = null;
                });
                _initPtyConnection();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'reconnect',
                child: Text(
                  'Reconnect',
                  style: TextStyle(color: _textPrimary),
                ),
              ),
            ],
          ),
        ],
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // SSH reconnection banner.
            _buildReconnectionBanner(),
            // Session info header card.
            if (session != null)
              _buildSessionInfoCard(session, serverConfig),
            // "TERMINAL OUTPUT" section label.
            _buildSectionLabel(),
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

  /// Build the session info header card showing engine, server, and status.
  Widget _buildSessionInfoCard(Session session, dynamic serverConfig) {
    final statusColor = _statusColor(session.status);
    final statusLabel = session.status.name.toUpperCase();
    final elapsedText = _formatElapsedTime(session.createdAt);

    // Build server info line: host and optional branch.
    String serverInfo = '';
    if (serverConfig != null) {
      serverInfo = '${serverConfig.host}:${serverConfig.port}';
    }
    if (session.worktreeBranch != null) {
      final branchSuffix = ' \u00B7 ${session.worktreeBranch}';
      serverInfo = serverInfo.isEmpty
          ? session.worktreeBranch!
          : '$serverInfo$branchSuffix';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _accent.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          // Engine icon.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _engineIcon(session.engine),
              color: _accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          // Session details.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Engine name (bold).
                Text(
                  session.engine,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (serverInfo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    serverInfo,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                // Elapsed time.
                Text(
                  elapsedText,
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Status badge.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build the "TERMINAL OUTPUT" section label divider.
  Widget _buildSectionLabel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Row(
        children: [
          Text(
            'TERMINAL OUTPUT',
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

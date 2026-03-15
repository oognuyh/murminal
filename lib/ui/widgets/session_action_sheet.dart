import 'package:flutter/material.dart';

import 'package:murminal/data/models/session.dart';

/// Theme colors matching the app's dark slate design.
const _surface = Color(0xFF1E293B);
const _textPrimary = Color(0xFFFFFFFF);
const _textMuted = Color(0xFF64748B);
const _accent = Color(0xFF22D3EE);
const _destructive = Color(0xFFF87171);

/// Action types available in the session action sheet.
enum SessionAction {
  viewTerminal,
  voiceControl,
  restart,
  terminate,
  delete,
}

/// Bottom sheet displaying contextual actions for a session.
///
/// Matches the pen wireframe (docs/merminal.pen, node WSaHa):
/// - Drag handle at top
/// - Session info header with engine icon, name, server, branch, and path
/// - Action list: View Terminal, Voice Control, Restart, Terminate, Delete
/// - Dark surface color with rounded top corners
class SessionActionSheet extends StatelessWidget {
  /// The session to display actions for.
  final Session session;

  /// Human-readable server label resolved from server ID.
  final String serverLabel;

  /// Callback invoked when the user selects an action.
  final void Function(SessionAction action) onAction;

  const SessionActionSheet({
    super.key,
    required this.session,
    required this.serverLabel,
    required this.onAction,
  });

  /// Show this action sheet as a modal bottom sheet.
  static Future<void> show({
    required BuildContext context,
    required Session session,
    required String serverLabel,
    required void Function(SessionAction action) onAction,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SessionActionSheet(
        session: session,
        serverLabel: serverLabel,
        onAction: (action) {
          Navigator.pop(context);
          onAction(action);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDragHandle(),
            const SizedBox(height: 12),
            _buildSessionHeader(),
            const Divider(color: _textMuted, height: 24, thickness: 0.5),
            _buildActionTile(
              icon: Icons.terminal,
              label: 'View Terminal',
              onTap: () => onAction(SessionAction.viewTerminal),
            ),
            _buildActionTile(
              icon: Icons.mic_outlined,
              label: 'Voice Control',
              onTap: () => onAction(SessionAction.voiceControl),
            ),
            _buildActionTile(
              icon: Icons.refresh,
              label: 'Restart Session',
              onTap: () => onAction(SessionAction.restart),
            ),
            if (session.status == SessionStatus.running)
              _buildActionTile(
                icon: Icons.stop_circle_outlined,
                label: 'Terminate Session',
                color: _destructive,
                onTap: () => onAction(SessionAction.terminate),
              ),
            _buildActionTile(
              icon: Icons.delete_outline,
              label: 'Delete Session',
              color: _destructive,
              onTap: () => onAction(SessionAction.delete),
            ),
          ],
        ),
      ),
    );
  }

  /// Drag handle indicator at the top of the sheet.
  Widget _buildDragHandle() {
    return Container(
      width: 32,
      height: 4,
      decoration: BoxDecoration(
        color: _textMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  /// Session info header: engine icon + name (bold), server/branch/path below.
  Widget _buildSessionHeader() {
    final subtitleParts = <String>[serverLabel];
    if (session.worktreeBranch != null) {
      subtitleParts.add(session.worktreeBranch!);
    }
    if (session.worktreePath != null) {
      subtitleParts.add(session.worktreePath!);
    }
    final subtitle = subtitleParts.join(' \u00b7 ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.memory,
              color: _accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.engine,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 12,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A single action row with icon and label.
  Widget _buildActionTile({
    required IconData icon,
    required String label,
    Color color = _textPrimary,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontFamily: 'JetBrains Mono',
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:murminal/core/providers.dart';
import 'package:murminal/data/models/session.dart';

/// Theme colors matching the app's dark slate design.
const _background = Color(0xFF0A0F1C);
const _surface = Color(0xFF1E293B);
const _accent = Color(0xFF22D3EE);
const _textPrimary = Color(0xFFFFFFFF);
const _textMuted = Color(0xFF64748B);
const _green = Color(0xFF4ADE80);
const _red = Color(0xFFF87171);

/// Filter tabs for the session list.
enum _SessionFilter {
  all('All'),
  running('Running'),
  done('Done'),
  idle('Idle');

  final String label;
  const _SessionFilter(this.label);
}

/// Session list screen displaying all sessions across all servers.
///
/// Provides filter tabs (All, Running, Done, Idle) with underline indicator,
/// session cards with status-colored left border, and actions for creating
/// and managing sessions. Matches the pen wireframe design.
class SessionListView extends ConsumerStatefulWidget {
  const SessionListView({super.key});

  @override
  ConsumerState<SessionListView> createState() => _SessionListViewState();
}

class _SessionListViewState extends ConsumerState<SessionListView> {
  _SessionFilter _activeFilter = _SessionFilter.all;

  /// Filter sessions by the currently active tab.
  List<Session> _applyFilter(List<Session> sessions) {
    return switch (_activeFilter) {
      _SessionFilter.all => sessions,
      _SessionFilter.running =>
        sessions.where((s) => s.status == SessionStatus.running).toList(),
      _SessionFilter.done =>
        sessions.where((s) => s.status == SessionStatus.done).toList(),
      _SessionFilter.idle =>
        sessions.where((s) => s.status == SessionStatus.idle).toList(),
    };
  }

  /// Resolve a server ID to its label. Falls back to a truncated ID.
  String _serverLabel(String serverId) {
    final servers = ref.read(serverListProvider);
    for (final server in servers) {
      if (server.id == serverId) return server.label;
    }
    // Fallback: show truncated ID.
    return serverId.length > 12 ? '${serverId.substring(0, 12)}...' : serverId;
  }

  /// Left border color for the given session status.
  Color _statusBorderColor(SessionStatus status) {
    return switch (status) {
      SessionStatus.running => _accent,
      SessionStatus.done => _green,
      SessionStatus.idle => _textMuted.withValues(alpha: 0.4),
      SessionStatus.error => _red,
    };
  }

  /// Status indicator widget for the given session status.
  Widget _statusIndicator(SessionStatus status) {
    return switch (status) {
      SessionStatus.running => Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: _accent,
            shape: BoxShape.circle,
          ),
        ),
      SessionStatus.done => const Text(
          '\u2713',
          style: TextStyle(
            color: _green,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      SessionStatus.idle => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: _textMuted, width: 1.5),
          ),
        ),
      SessionStatus.error => const Text(
          '\u2717',
          style: TextStyle(
            color: _red,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
    };
  }

  /// Format a DateTime as a relative "last activity" string.
  String _formatActivity(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// Navigate to the session detail terminal view.
  void _onSessionTap(Session session) {
    context.push(
      '/sessions/${session.id}?name=${Uri.encodeComponent(session.name)}',
    );
  }

  /// Show actions bottom sheet on long press.
  void _onSessionLongPress(Session session) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _textMuted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _buildActionTile(
                icon: Icons.info_outline,
                label: 'View Details',
                onTap: () {
                  Navigator.pop(context);
                  _onSessionTap(session);
                },
              ),
              if (session.status == SessionStatus.running)
                _buildActionTile(
                  icon: Icons.stop_circle_outlined,
                  label: 'Terminate',
                  color: _red,
                  onTap: () async {
                    Navigator.pop(context);
                    final service = ref.read(sessionServiceProvider);
                    await service.terminateSession(session.id);
                    ref.invalidate(allSessionsProvider);
                  },
                ),
              _buildActionTile(
                icon: Icons.delete_outline,
                label: 'Delete',
                color: _red,
                onTap: () async {
                  Navigator.pop(context);
                  final service = ref.read(sessionServiceProvider);
                  await service.deleteSession(session.id);
                  ref.invalidate(allSessionsProvider);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build a single action tile for the bottom sheet.
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

  /// Navigate to new session creation.
  void _onAddSession() {
    context.push('/sessions/new');
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(allSessionsProvider);

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              _buildHeader(),
              const SizedBox(height: 24),
              _buildFilterTabs(),
              const SizedBox(height: 20),
              Expanded(
                child: sessionsAsync.when(
                  data: (sessions) {
                    final filtered = _applyFilter(sessions);
                    if (filtered.isEmpty) {
                      return _buildEmptyState(sessions.isEmpty);
                    }
                    return ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) =>
                          _buildSessionCard(filtered[index]),
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: _accent),
                  ),
                  error: (error, _) => Center(
                    child: Text(
                      'Failed to load sessions.\n$error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 13,
                        fontFamily: 'JetBrains Mono',
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Title row with SESSIONS heading and cyan circular add button.
  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'SESSIONS',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            fontFamily: 'JetBrains Mono',
            letterSpacing: 2,
          ),
        ),
        GestureDetector(
          onTap: _onAddSession,
          child: Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: _accent,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.add,
              color: _background,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  /// Underline-style filter tabs for session status filtering.
  Widget _buildFilterTabs() {
    return Row(
      children: _SessionFilter.values.map((filter) {
        final isActive = _activeFilter == filter;
        return Padding(
          padding: const EdgeInsets.only(right: 24),
          child: GestureDetector(
            onTap: () => setState(() => _activeFilter = filter),
            behavior: HitTestBehavior.opaque,
            child: Column(
              children: [
                Text(
                  filter.label,
                  style: TextStyle(
                    color: isActive ? _textPrimary : _textMuted,
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 2,
                  width: isActive ? 24 : 0,
                  decoration: BoxDecoration(
                    color: isActive ? _accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Session card with status-colored left border, status indicator,
  /// engine name (bold), server name (right-aligned), and branch/task row.
  Widget _buildSessionCard(Session session) {
    final borderColor = _statusBorderColor(session.status);
    final server = _serverLabel(session.serverId);
    final activity = _formatActivity(session.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _onSessionTap(session),
        onLongPress: () => _onSessionLongPress(session),
        child: Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(color: borderColor, width: 3),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: status dot + engine name (left), server name (right).
              Row(
                children: [
                  _statusIndicator(session.status),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      session.engine,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ),
                  Text(
                    server,
                    style: const TextStyle(
                      color: _textMuted,
                      fontSize: 12,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Bottom row: branch and/or activity info.
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Row(
                  children: [
                    if (session.worktreeBranch != null) ...[
                      Icon(
                        Icons.account_tree_outlined,
                        size: 12,
                        color: _accent.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          session.worktreeBranch!,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _accent.withValues(alpha: 0.7),
                            fontSize: 11,
                            fontFamily: 'JetBrains Mono',
                          ),
                        ),
                      ),
                      Text(
                        '  \u00b7  ',
                        style: TextStyle(
                          color: _textMuted.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                    ],
                    Text(
                      activity,
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 11,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Empty state when no sessions exist or match the filter.
  Widget _buildEmptyState(bool noSessionsAtAll) {
    final message = noSessionsAtAll
        ? 'No sessions yet.\nTap + to create your first session.'
        : 'No sessions match this filter.';

    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _textMuted,
          fontSize: 14,
          fontFamily: 'JetBrains Mono',
          height: 1.6,
        ),
      ),
    );
  }
}

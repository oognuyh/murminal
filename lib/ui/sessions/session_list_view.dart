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
/// Provides filter tabs (All, Running, Done, Idle), session cards with
/// status indicators, and actions for creating and managing sessions.
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

  /// Status icon character for the given session status.
  String _statusIcon(SessionStatus status) {
    return switch (status) {
      SessionStatus.running => '◐',
      SessionStatus.done => '✓',
      SessionStatus.idle => '○',
      SessionStatus.error => '✗',
    };
  }

  /// Status color for the given session status.
  Color _statusColor(SessionStatus status) {
    return switch (status) {
      SessionStatus.running => _accent,
      SessionStatus.done => const Color(0xFF4ADE80),
      SessionStatus.idle => _textMuted,
      SessionStatus.error => const Color(0xFFF87171),
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
                  color: const Color(0xFFF87171),
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
                color: const Color(0xFFF87171),
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

  /// Navigate to new session creation (placeholder).
  void _onAddSession() {
    // Placeholder navigation for new session creation screen.
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
              const SizedBox(height: 20),
              _buildFilterTabs(),
              const SizedBox(height: 24),
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

  /// Title row with SESSIONS heading and add button.
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.add,
              color: _accent,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  /// Segmented filter tabs for session status filtering.
  Widget _buildFilterTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: _SessionFilter.values.map((filter) {
          final isActive = _activeFilter == filter;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeFilter = filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? _accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: Text(
                  filter.label,
                  style: TextStyle(
                    color: isActive ? const Color(0xFF0A0F1C) : _textMuted,
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Individual session card with status icon, engine, server, and activity.
  Widget _buildSessionCard(Session session) {
    final icon = _statusIcon(session.status);
    final color = _statusColor(session.status);
    final server = _serverLabel(session.serverId);
    final activity = _formatActivity(session.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _onSessionTap(session),
        onLongPress: () => _onSessionLongPress(session),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Status icon.
              SizedBox(
                width: 24,
                child: Text(
                  icon,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Session info.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.engine,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$server  ·  $activity',
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ],
                ),
              ),
              // Chevron right.
              const Icon(
                Icons.chevron_right,
                color: _textMuted,
                size: 20,
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

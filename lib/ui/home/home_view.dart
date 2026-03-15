import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:murminal/core/providers.dart';
import 'package:murminal/core/router.dart';
import 'package:murminal/data/models/session.dart';

/// Theme colors matching the app's dark slate design.
const _background = Color(0xFF0A0F1C);
const _surface = Color(0xFF1E293B);
const _accent = Color(0xFF22D3EE);
const _textPrimary = Color(0xFFFFFFFF);
const _textSecondary = Color(0xFF94A3B8);
const _textTertiary = Color(0xFF64748B);
const _textMuted = Color(0xFF475569);

/// Status-specific colors for card left-border accents.
const _statusCyan = Color(0xFF22D3EE);
const _statusGreen = Color(0xFF22C55E);
const _statusGrey = Color(0xFF64748B);
const _statusRed = Color(0xFFEF4444);

/// Session count threshold above which compact mode activates.
const _compactThreshold = 4;

/// Home dashboard displaying session status cards.
///
/// Shows a header with the app title, subtitle, and settings gear icon,
/// followed by an "ACTIVE SESSIONS" section with a scrollable list of
/// session cards sorted by status: running first, then done, then idle.
class HomeView extends ConsumerWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(allSessionsProvider);
    final servers = ref.watch(serverListProvider);

    // Build a lookup map from server ID to server label.
    final serverLabels = <String, String>{};
    for (final server in servers) {
      serverLabels[server.id] = server.label;
    }

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              _buildHeader(context),
              const SizedBox(height: 24),
              sessionsAsync.when(
                data: (sessions) =>
                    _buildSessionList(context, sessions, serverLabels),
                loading: () => const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: _accent),
                  ),
                ),
                error: (error, _) => Expanded(
                  child: Center(
                    child: Text(
                      'Failed to load sessions',
                      style: const TextStyle(
                        color: _textTertiary,
                        fontSize: 14,
                        fontFamily: 'JetBrains Mono',
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

  /// App header with title, subtitle, and settings gear icon.
  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MURMINAL',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                fontFamily: 'JetBrains Mono',
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Voice Terminal Supervisor',
              style: TextStyle(
                color: _textTertiary,
                fontSize: 13,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
        GestureDetector(
          onTap: () => context.go(AppRoutes.settings),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.settings_outlined,
              color: _textSecondary,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  /// Session list with section label and sorted cards.
  Widget _buildSessionList(
    BuildContext context,
    List<Session> sessions,
    Map<String, String> serverLabels,
  ) {
    final sorted = _sortSessions(sessions);
    final activeCount =
        sessions.where((s) => s.status == SessionStatus.running).length;
    final compact = sessions.length > _compactThreshold;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(activeCount),
          const SizedBox(height: 12),
          Expanded(
            child: sorted.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    itemCount: sorted.length,
                    padding: const EdgeInsets.only(bottom: 100),
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      return _SessionCard(
                        session: sorted[index],
                        compact: compact,
                        serverLabel: serverLabels[sorted[index].serverId],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Section header: ACTIVE SESSIONS label with cyan count on the right.
  Widget _buildSectionHeader(int activeCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'ACTIVE SESSIONS',
          style: TextStyle(
            color: _textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
            letterSpacing: 2,
          ),
        ),
        Text(
          '$activeCount',
          style: const TextStyle(
            color: _accent,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }

  /// Sort sessions: running first, then done, then idle.
  List<Session> _sortSessions(List<Session> sessions) {
    final sorted = List<Session>.from(sessions);
    sorted.sort((a, b) {
      final order = {
        SessionStatus.running: 0,
        SessionStatus.done: 1,
        SessionStatus.idle: 2,
        SessionStatus.error: 3,
      };
      final cmp = (order[a.status] ?? 3).compareTo(order[b.status] ?? 3);
      if (cmp != 0) return cmp;
      // Within same status, most recent first.
      return b.createdAt.compareTo(a.createdAt);
    });
    return sorted;
  }

  /// Empty state when no sessions exist.
  Widget _buildEmptyState() {
    return const Center(
      child: Text(
        'No active sessions.\nStart a session from a server.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _textTertiary,
          fontSize: 14,
          fontFamily: 'JetBrains Mono',
          height: 1.6,
        ),
      ),
    );
  }
}

/// Individual session status card matching the wireframe design.
///
/// Layout:
/// - Top row: cyan status dot + engine name (bold) | server name (right)
/// - Second row: branch info (if available)
/// - Third row: task description
/// - Bottom row: time ago + status label
///
/// Uses [AnimatedContainer] for smooth 200ms transitions when status
/// changes. In compact mode (>4 sessions) the branch and task rows
/// are hidden.
class _SessionCard extends StatelessWidget {
  final Session session;
  final bool compact;
  final String? serverLabel;

  const _SessionCard({
    required this.session,
    this.compact = false,
    this.serverLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = session.status == SessionStatus.done;
    final isIdle = session.status == SessionStatus.idle;
    final isRunning = session.status == SessionStatus.running;
    final isError = session.status == SessionStatus.error;

    // Muted surface for done and idle states.
    final cardColor =
        (isDone || isIdle) ? _surface.withValues(alpha: 0.6) : _surface;

    // Left border accent color per status.
    final borderColor = switch (session.status) {
      SessionStatus.running => _statusCyan,
      SessionStatus.error => _statusRed,
      SessionStatus.done => Colors.transparent,
      SessionStatus.idle => Colors.transparent,
    };

    // Text color dims for idle sessions.
    final primaryText = isIdle ? _textMuted : _textPrimary;
    final secondaryText = isIdle ? _textMuted : _textTertiary;

    return GestureDetector(
      onTap: () {
        context.push(
          '/sessions/${session.id}?name=${Uri.encodeComponent(session.name)}',
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: EdgeInsets.all(compact ? 12 : 16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: (isRunning || isError)
              ? Border(
                  left: BorderSide(color: borderColor, width: 3.0),
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: status dot + engine name (bold) | server name (right)
            Row(
              children: [
                _buildStatusDot(),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    session.engine,
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                ),
                Text(
                  serverLabel ?? session.serverId,
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ],
            ),
            if (!compact) ...[
              // Branch info row (if available).
              if (session.worktreeBranch != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Row(
                    children: [
                      Icon(
                        Icons.call_split,
                        color: secondaryText,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          session.worktreeBranch!,
                          style: TextStyle(
                            color: secondaryText,
                            fontSize: 12,
                            fontFamily: 'JetBrains Mono',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Task description row.
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Text(
                  _taskDescription(),
                  style: TextStyle(
                    color: isIdle ? _textMuted : _textSecondary,
                    fontSize: 13,
                    fontFamily: 'Inter',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Bottom row: time ago + status label.
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Row(
                  children: [
                    Text(
                      _formatTimeSince(session.createdAt),
                      style: TextStyle(
                        color: secondaryText,
                        fontSize: 11,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildStatusLabel(),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Small colored dot indicating session status.
  ///
  /// Running: cyan filled, Done: green checkmark, Idle: grey, Error: red.
  Widget _buildStatusDot() {
    if (session.status == SessionStatus.done) {
      return Icon(
        Icons.check_circle,
        color: _statusGreen,
        size: 10,
      );
    }

    final color = switch (session.status) {
      SessionStatus.running => _statusCyan,
      SessionStatus.idle => _statusGrey,
      SessionStatus.error => _statusRed,
      SessionStatus.done => _statusGreen,
    };

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  /// Colored status label badge.
  Widget _buildStatusLabel() {
    final (String label, Color color) = switch (session.status) {
      SessionStatus.running => ('running', _statusCyan),
      SessionStatus.done => ('done', _statusGreen),
      SessionStatus.idle => ('idle', _statusGrey),
      SessionStatus.error => ('error', _statusRed),
    };

    return Container(
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
          fontFamily: 'Inter',
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Format time elapsed since the given date.
  String _formatTimeSince(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'now';
  }

  /// Task description derived from session status.
  String _taskDescription() {
    return switch (session.status) {
      SessionStatus.running => 'Session active',
      SessionStatus.done => 'Session completed',
      SessionStatus.idle => 'Waiting for input',
      SessionStatus.error => 'Error occurred',
    };
  }
}

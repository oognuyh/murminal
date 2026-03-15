import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:murminal/core/providers.dart';
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
const _statusRed = Color(0xFFEF4444);

/// Session count threshold above which compact mode activates.
const _compactThreshold = 4;

/// Home screen displaying session status cards.
///
/// Shows a header with the app title and bell button, followed by
/// a scrollable list of session cards sorted by status: running first,
/// then done, then idle.
class HomeView extends ConsumerWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              sessionsAsync.when(
                data: (sessions) => _buildSessionList(sessions),
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

  /// App header with title, subtitle, and notification bell.
  Widget _buildHeader() {
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
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.notifications_outlined,
            color: _textSecondary,
            size: 22,
          ),
        ),
      ],
    );
  }

  /// Session list with section label and sorted cards.
  Widget _buildSessionList(List<Session> sessions) {
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
                    itemBuilder: (context, index) {
                      return _SessionCard(
                        session: sorted[index],
                        compact: compact,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Section header: ACTIVE SESSIONS label + count badge.
  Widget _buildSectionHeader(int activeCount) {
    return Row(
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
        const SizedBox(width: 8),
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

/// Individual session status card with animated state transitions.
///
/// Displays the session engine icon, name, server, status indicator,
/// current task description, and time since last activity.
///
/// Uses [AnimatedContainer] for smooth 200ms transitions when status
/// changes. In compact mode (>4 sessions) padding is reduced and the
/// task description row is hidden.
class _SessionCard extends StatelessWidget {
  final Session session;
  final bool compact;

  const _SessionCard({required this.session, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final isDone = session.status == SessionStatus.done;
    final isIdle = session.status == SessionStatus.idle;
    final isRunning = session.status == SessionStatus.running;
    final isError = session.status == SessionStatus.error;

    // Muted surface for done and idle states.
    final cardColor = (isDone || isIdle)
        ? _surface.withValues(alpha: 0.6)
        : _surface;

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
        // Navigate to session detail (to be implemented in a future issue).
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: EdgeInsets.all(compact ? 12 : 16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              color: borderColor,
              width: (isRunning || isError) ? 3.0 : 0.0,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStatusIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.engine,
                        style: TextStyle(
                          color: primaryText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        session.name,
                        style: TextStyle(
                          color: secondaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                    ],
                  ),
                ),
                if (isRunning) ...[
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _statusCyan.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (isDone)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.check_circle_outline,
                      color: _statusGreen,
                      size: 16,
                    ),
                  ),
                Text(
                  _formatTimeSince(session.createdAt),
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
              const SizedBox(height: 10),
              // Server info row.
              Text(
                'server: ${session.serverId}',
                style: TextStyle(
                  color: isIdle ? _textMuted : _textMuted,
                  fontSize: 12,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 4),
              // Task description from session status.
              Text(
                _taskDescription(),
                style: TextStyle(
                  color: isIdle ? _textMuted : _textSecondary,
                  fontSize: 13,
                  fontFamily: 'Inter',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Status indicator icon with color-coded background.
  ///
  /// Running: ◐ cyan, Done: checkmark green, Idle: ○ muted, Error: ✗ red.
  Widget _buildStatusIcon() {
    final (String symbol, Color color) = switch (session.status) {
      SessionStatus.running => ('\u25D0', _statusCyan),
      SessionStatus.done => ('\u2713', _statusGreen),
      SessionStatus.idle => ('\u25CB', _textMuted),
      SessionStatus.error => ('\u2717', _statusRed),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          symbol,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
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

import 'package:flutter/material.dart';

/// Theme constants for the bottom navigation bar.
const _pillColor = Color(0xFF1E293B);
const _activeColor = Color(0xFF22D3EE);
const _inactiveColor = Color(0xFF475569);
const _fabSize = 60.0;
const _fabIconSize = 26.0;
const _pillHeight = 62.0;
const _pillRadius = 36.0;
const _pillBorderColor = Color(0xFF0F172A);
const _tabIconSize = 18.0;

/// Tab definition for the bottom navigation bar.
class _TabItem {
  final IconData icon;
  final String label;

  const _TabItem({required this.icon, required this.label});
}

const _tabs = [
  _TabItem(icon: Icons.home_outlined, label: 'HOME'),
  _TabItem(icon: Icons.dns_outlined, label: 'SERVERS'),
  // Center gap for FAB
  _TabItem(icon: Icons.terminal_outlined, label: 'SESSIONS'),
  _TabItem(icon: Icons.settings_outlined, label: 'SETTINGS'),
];

/// Pill-style bottom navigation bar with a center FAB mic button.
///
/// The bar renders as a floating pill with 4 tabs (2 on each side)
/// and a protruding center FAB for the microphone action.
class BottomNavBar extends StatefulWidget {
  /// Currently selected tab index (0-3).
  final int currentIndex;

  /// Callback when a tab is tapped.
  final ValueChanged<int> onTabSelected;

  /// Callback when the center FAB is tapped.
  final VoidCallback onMicPressed;

  /// Whether a voice session is currently active.
  ///
  /// When true the FAB displays a pulsing cyan glow to indicate
  /// the microphone is live.
  final bool isVoiceActive;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.onMicPressed,
    this.isVoiceActive = false,
  });

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 0.33, end: 0.8).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.isVoiceActive) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant BottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVoiceActive && !oldWidget.isVoiceActive) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isVoiceActive && oldWidget.isVoiceActive) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return SizedBox(
      height: _pillHeight + _fabSize / 2 + 16 + bottomPadding,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // Pill background with tabs
          Padding(
            padding: EdgeInsets.only(bottom: bottomPadding),
            child: _buildPill(),
          ),
          // Center FAB protruding above the pill
          Positioned(
            bottom: _pillHeight / 2 + bottomPadding,
            child: _buildFab(),
          ),
        ],
      ),
    );
  }

  Widget _buildPill() {
    return Container(
      height: _pillHeight,
      margin: const EdgeInsets.symmetric(horizontal: 21),
      decoration: BoxDecoration(
        color: _pillColor,
        borderRadius: BorderRadius.circular(_pillRadius),
        border: Border.all(color: _pillBorderColor, width: 1),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          // Left tabs (HOME, SERVERS)
          Expanded(child: _buildTab(0)),
          Expanded(child: _buildTab(1)),
          // Center spacer for FAB
          const SizedBox(width: _fabSize + 8),
          // Right tabs (SESSIONS, SETTINGS)
          Expanded(child: _buildTab(2)),
          Expanded(child: _buildTab(3)),
        ],
      ),
    );
  }

  Widget _buildTab(int index) {
    final tab = _tabs[index];
    final isActive = widget.currentIndex == index;

    return GestureDetector(
      onTap: () => widget.onTabSelected(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isActive ? _activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              tab.icon,
              size: _tabIconSize,
              color: isActive ? const Color(0xFF0A0F1C) : _inactiveColor,
            ),
            const SizedBox(height: 2),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 8,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? const Color(0xFF0A0F1C) : _inactiveColor,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFab() {
    final isActive = widget.isVoiceActive;
    return GestureDetector(
      onTap: widget.onMicPressed,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Container(
            width: _fabSize,
            height: _fabSize,
            decoration: BoxDecoration(
              color: isActive ? _activeColor : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _activeColor.withValues(
                    alpha: isActive ? _pulseAnimation.value : 0.33,
                  ),
                  blurRadius: isActive ? 24 : 16,
                  spreadRadius: isActive ? 6 : 2,
                ),
              ],
            ),
            child: Icon(
              isActive ? Icons.mic : Icons.mic_none,
              size: _fabIconSize,
              color: isActive ? Colors.white : const Color(0xFF0A0F1C),
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:murminal/ui/widgets/bottom_nav_bar.dart';

/// Main scaffold that wraps all tab screens with the bottom navigation bar.
///
/// Uses an [IndexedStack] to preserve tab state when switching between tabs.
class MainScaffold extends StatelessWidget {
  /// The list of tab screen widgets.
  final List<Widget> tabs;

  /// Currently selected tab index.
  final int currentIndex;

  /// Callback when a tab is selected.
  final ValueChanged<int> onTabSelected;

  /// Callback when the center FAB mic button is pressed.
  final VoidCallback onMicPressed;

  const MainScaffold({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onTabSelected,
    required this.onMicPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: tabs,
      ),
      extendBody: true,
      bottomNavigationBar: BottomNavBar(
        currentIndex: currentIndex,
        onTabSelected: onTabSelected,
        onMicPressed: onMicPressed,
      ),
    );
  }
}

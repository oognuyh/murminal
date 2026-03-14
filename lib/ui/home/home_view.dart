import 'package:flutter/material.dart';

/// Placeholder screen for the Home tab.
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Text(
          'HOME',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 18,
            fontFamily: 'JetBrains Mono',
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

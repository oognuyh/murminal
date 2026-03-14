import 'package:flutter/material.dart';

/// Placeholder screen for the Sessions tab.
class SessionListView extends StatelessWidget {
  const SessionListView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Text(
          'SESSIONS',
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

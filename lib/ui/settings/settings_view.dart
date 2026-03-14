import 'package:flutter/material.dart';

/// Placeholder screen for the Settings tab.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Text(
          'SETTINGS',
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

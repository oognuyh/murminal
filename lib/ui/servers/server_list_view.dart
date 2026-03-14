import 'package:flutter/material.dart';

/// Placeholder screen for the Servers tab.
class ServerListView extends StatelessWidget {
  const ServerListView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Text(
          'SERVERS',
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

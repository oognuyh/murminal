import 'package:flutter/material.dart';
import 'package:murminal/core/router.dart';
import 'package:murminal/core/theme.dart';

class MurminalApp extends StatelessWidget {
  const MurminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Murminal',
      theme: murminalTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('Murminal', style: TextStyle(fontSize: 24))),
      ),
    ),
  ],
);

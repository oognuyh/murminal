import 'package:flutter/material.dart';

const _background = Color(0xFF0A0F1C);
const _surface = Color(0xFF1E293B);
const _surfaceDim = Color(0xFF0F172A); // ignore: unused_element
const _accent = Color(0xFF22D3EE);
const _textPrimary = Color(0xFFFFFFFF);
const _textSecondary = Color(0xFF94A3B8); // ignore: unused_element
const _textTertiary = Color(0xFF64748B); // ignore: unused_element
const _textMuted = Color(0xFF475569);

final murminalTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: _background,
  colorScheme: const ColorScheme.dark(
    primary: _accent,
    surface: _surface,
    onPrimary: _background,
    onSurface: _textPrimary,
  ),
  fontFamily: 'Inter',
  appBarTheme: const AppBarTheme(
    backgroundColor: _background,
    foregroundColor: _textPrimary,
    elevation: 0,
  ),
  cardTheme: CardThemeData(
    color: _surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: _surface,
    selectedItemColor: _accent,
    unselectedItemColor: _textMuted,
  ),
);

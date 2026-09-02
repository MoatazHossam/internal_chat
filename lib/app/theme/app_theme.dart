import 'package:flutter/material.dart';

class AppTheme {
  static const primary   = Color(0xFFA1887F); // light brown
  static const dark1     = Color(0xFF795548); // deeper brown (accents)
  static const uaeRed    = Color(0xFFEF3340); // kept for OTP/error states
  // Legacy alias so existing code compiles without changes
  static const uaeGreen  = primary;

  static final light = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      secondary: dark1,
      error: uaeRed,
    ),
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: primary,
      foregroundColor: Colors.white,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: primary),
    ),
  );

  static final dark = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: primary,
      secondary: dark1,
      error: uaeRed,
    ),
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
    ),
  );
}

import 'package:flutter/material.dart';

class KounColors {
  static const background = Color(0xFF0F141B);
  static const surface = Color(0xFF17212B);
  static const surfaceContainer = Color(0xFF223141);
  static const card = Color(0xFF1C2732);
  static const primary = Color(0xFF7BA2A8);
  static const secondary = Color(0xFF94A2B3);
  static const error = Color(0xFFCF6679);
}

class KounTheme {
  static ThemeData get dark {
    final base = ColorScheme.fromSeed(
      seedColor: KounColors.primary,
      brightness: Brightness.dark,
    );
    final scheme = base.copyWith(
      primary: KounColors.primary,
      secondary: KounColors.secondary,
      surface: KounColors.surface,
      surfaceContainerHighest: KounColors.surfaceContainer,
      error: KounColors.error,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: KounColors.background,
      cardTheme: const CardThemeData(color: KounColors.card, elevation: 0),
      appBarTheme: AppBarTheme(
        backgroundColor: KounColors.background,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: KounColors.surface,
        indicatorColor: KounColors.surfaceContainer,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: KounColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: KounColors.surface),
    );
  }
}

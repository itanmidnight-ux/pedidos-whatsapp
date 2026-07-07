import 'package:flutter/material.dart';
import 'app_text_styles.dart';

class AppTheme {
  AppTheme._();

  static const successColor = Color(0xFF2E7D32);
  static const warningColor = Color(0xFFB5651D);
  static const errorColor   = Color(0xFFB3261E);
  static const infoColor    = Color(0xFF3B5A73);

  static ThemeData build({
    required Color primary,
    required Color accent,
    required Brightness brightness,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      secondary: accent,
      error: errorColor,
    );

    final onSurface = scheme.onSurface;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: TextTheme(
        displayMedium: AppTextStyles.display(onSurface),
        headlineSmall: AppTextStyles.h1(onSurface),
        titleLarge:    AppTextStyles.h2(onSurface),
        bodyMedium:    AppTextStyles.body(onSurface),
        bodyLarge:     AppTextStyles.bodyStrong(onSurface),
        labelSmall:    AppTextStyles.caption(onSurface),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: primary.withValues(alpha: 0.12)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: primary.withValues(alpha: 0.16),
        elevation: 8,
      ),
    );
  }
}

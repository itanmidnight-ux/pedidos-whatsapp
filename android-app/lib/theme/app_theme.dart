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
    var scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      secondary: accent,
      error: errorColor,
    );

    // Material 3 genera superficies con un tinte del color semilla (verde
    // oliva) que en fondos grandes se ve apagado/sucio en vez de calido y
    // profesional. En claro forzamos blanco real como base -- el color de
    // marca queda en acentos (AppBar, botones, indicadores), no en el fondo.
    if (brightness == Brightness.light) {
      scheme = scheme.copyWith(
        surface: Colors.white,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFFAFAF7),
        surfaceContainer: const Color(0xFFF5F4F0),
        surfaceContainerHigh: const Color(0xFFEFEEE8),
      );
    }

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
      // Transicion fade+scale unificada en todas las plataformas (Android,
      // iOS, Web) en vez de la mezcla por defecto (Zoom en Android, Cupertino
      // deslizante en iOS) -- se siente mas pulido y consistente.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

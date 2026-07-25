import 'package:flutter/material.dart';

/// Central design tokens: a violet fintech accent and soft rounded surfaces.
/// Both light and dark themes are supported; the app follows the system
/// setting. Typography stays on the platform font on purpose: runtime font
/// downloads re-layout the whole app whenever a weight arrives (visible
/// flicker) and fail on LAN-only game nights with no internet.
abstract final class AppColors {
  static const accent = Color(0xFF635BFF);
  static const accentAlt = Color(0xFF9E77FF);

  /// The hero gradient used on the balance card and primary highlights.
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5B54F0), Color(0xFF8E5CF7), Color(0xFFB16CEF)],
  );

  static const income = Color(0xFF16C784);
  static const expense = Color(0xFFFF5C7A);

  static const darkScaffold = Color(0xFF0B0D14);
  static const darkSurface = Color(0xFF151824);
  static const darkSurfaceAlt = Color(0xFF1D2130);

  static const lightScaffold = Color(0xFFF4F5FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceAlt = Color(0xFFEDEEF6);

  /// Deterministic avatar palette: every device derives the same color for
  /// the same player id, so avatars match across phones with no syncing.
  static const avatarPalette = [
    Color(0xFF635BFF),
    Color(0xFF16C784),
    Color(0xFFFF8A48),
    Color(0xFFFF5C7A),
    Color(0xFF2FB8E8),
    Color(0xFFB16CEF),
    Color(0xFFF2B33D),
    Color(0xFF4ECB8C),
  ];

  static Color avatarColor(String id) =>
      avatarPalette[id.hashCode.abs() % avatarPalette.length];
}

abstract final class AppTheme {
  static const double radius = 22;

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.accent,
      surface: isDark ? AppColors.darkScaffold : AppColors.lightScaffold,
      surfaceContainerLow:
          isDark ? AppColors.darkSurface : AppColors.lightSurface,
      surfaceContainer:
          isDark ? AppColors.darkSurface : AppColors.lightSurface,
      surfaceContainerHigh:
          isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
      error: AppColors.expense,
    );

    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final textTheme = base.textTheme;

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        // Labels always float: full-size labels get clipped inside the
        // narrow numeric fields on the board editor.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.accent.withValues(alpha: 0.16),
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
      ),
    );
  }
}

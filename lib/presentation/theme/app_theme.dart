import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Maps `docs/brand.md`'s tokens onto a Flutter `ThemeData` — this is the
/// one file screens should pull typography/colour from, rather than
/// hard-coding hex values or font families inline.
///
/// **Font family choice per locale (brand.md §3.1):** Tajawal is Arabic
/// (and its own Latin cut); Manrope is the Latin family, and — per the
/// weight-mapping rule — Manrope SemiBold (600) has no Tajawal equivalent,
/// so Arabic headings render one step heavier (Tajawal Bold 700) at the
/// same size/line-height. `MaterialApp` picks the base `fontFamily`; per
/// -locale substitution for the "SemiBold" style specifically is applied
/// where used (see `LockGateScreen`'s headline styles) rather than baked
/// into a single global `TextTheme`, since `ThemeData` has no built-in
/// concept of "the current locale's font."
abstract final class AppTheme {
  static ThemeData light() {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
      error: AppColors.error,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.surface,
      fontFamily: 'Manrope',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: _textTheme(),
    );
  }

  static TextTheme _textTheme() {
    // Sizes/weights/line-heights transcribed from docs/design.md §2.2 —
    // Flutter's TextStyle takes `fontSize`/`height` (a multiplier of
    // fontSize, not an absolute px line-height) and `fontWeight`.
    return const TextTheme(
      // H1 — screen title: 24/32, SemiBold(600).
      headlineSmall: TextStyle(
        fontSize: 24,
        height: 32 / 24,
        fontWeight: FontWeight.w600,
        color: AppColors.ink900,
      ),
      // H2 — section header: 20/28, SemiBold(600).
      titleLarge: TextStyle(
        fontSize: 20,
        height: 28 / 20,
        fontWeight: FontWeight.w600,
        color: AppColors.ink900,
      ),
      // H3 — card/list header: 17/24, Medium(500).
      titleMedium: TextStyle(
        fontSize: 17,
        height: 24 / 17,
        fontWeight: FontWeight.w500,
        color: AppColors.ink900,
      ),
      // Body Large: 17/24, Regular(400).
      bodyLarge: TextStyle(
        fontSize: 17,
        height: 24 / 17,
        fontWeight: FontWeight.w400,
        color: AppColors.ink900,
      ),
      // Body: 15/22, Regular(400).
      bodyMedium: TextStyle(
        fontSize: 15,
        height: 22 / 15,
        fontWeight: FontWeight.w400,
        color: AppColors.ink900,
      ),
      // Body Small / Caption: 13/18, Regular(400).
      bodySmall: TextStyle(
        fontSize: 13,
        height: 18 / 13,
        fontWeight: FontWeight.w400,
        color: AppColors.ink700,
      ),
      // Label / Button: 15/20, Medium(500).
      labelLarge: TextStyle(
        fontSize: 15,
        height: 20 / 15,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: AppColors.ink900,
      ),
    );
  }
}

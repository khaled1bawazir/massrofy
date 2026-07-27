import 'package:flutter/material.dart';

/// Colour tokens, copied **verbatim** from `docs/brand.md` §7 (the quick
/// reference table engineers are told to implement directly, not
/// reinterpret). Keeping every value in one place means a screen can never
/// quietly drift from the approved palette.
abstract final class AppColors {
  static const Color primary = Color(0xFF0B3D62);
  static const Color primaryPressed = Color(0xFF0A3454);
  static const Color primaryTint10 = Color(0xFFE7EEF4);

  static const Color secondary = Color(0xFFB8842E);
  static const Color secondaryText = Color(0xFF8A5F1E);
  static const Color secondaryTint10 = Color(0xFFF7EEDD);

  static const Color ink900 = Color(0xFF101418);
  static const Color ink700 = Color(0xFF3A434C);
  static const Color ink500 = Color(0xFF6B7580);
  static const Color ink300 = Color(0xFFC7CDD4);
  static const Color ink100 = Color(0xFFEEF1F4);

  static const Color surface = Color(0xFFF7F8FA);
  static const Color white = Color(0xFFFFFFFF);

  static const Color success = Color(0xFF1E7A46);
  static const Color successTint = Color(0xFFE5F3EA);

  static const Color error = Color(0xFFB3261E);
  static const Color errorTint = Color(0xFFFBEAE9);

  static const Color warningText = Color(0xFF8A5A00);
  static const Color warningFill = Color(0xFFF2A93B);

  static const Color info = Color(0xFF0B6E8C);
  static const Color infoTint = Color(0xFFE4F1F5);
}

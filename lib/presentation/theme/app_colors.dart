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

  // -----------------------------------------------------------------------
  // Categorical / chart palette — `docs/brand.md` §2.5, copied verbatim.
  //
  // **Reports only.** brand.md is explicit that these are *"separate from
  // semantic colours"* and must never be reused to carry a meaning: a slice
  // that happens to be `chartRose` is not an error, and `success` must never
  // become a category's colour. Keeping them in their own block, named
  // `chart*`, is what makes that rule visible at the call site.
  //
  // Every slice and bar in P5b also carries a **text label and a figure**
  // (NFR-U4, brand.md §5.3's "never a bare, unlabelled colour-only chart"), so
  // the palette is reinforcement. Delete every colour from the reports screens
  // and each row still reads.
  // -----------------------------------------------------------------------

  static const Color chartNavy = Color(0xFF0B3D62);
  static const Color chartGold = Color(0xFFB8842E);
  static const Color chartTeal = Color(0xFF2E7D8C);
  static const Color chartPlum = Color(0xFF6B4C8A);
  static const Color chartTerracotta = Color(0xFFB25D3F);
  static const Color chartSlate = Color(0xFF55708A);
  static const Color chartOlive = Color(0xFF7A7A3E);
  static const Color chartRose = Color(0xFFA34E63);

  /// Fixed grey, and **never reassigned to a real category**.
  ///
  /// brand.md §2.5: *"always `ink-500`, fixed grey — never reassigned to a real
  /// category's colour, so 'Uncategorized' always reads as unassigned, not as a
  /// themed category"*. AC-E2.3 requires the Uncategorized line to be present
  /// and honest; giving it a palette colour would make it look like one more
  /// kind of spending rather than the app admitting it does not know.
  static const Color chartUncategorized = ink500;

  /// brand.md §2.5's eight slots, in order.
  ///
  /// Ordered, and reused in order when a ledger has more than eight
  /// distinguishable series — which brand.md allows; what it forbids is reusing
  /// [chartUncategorized].
  static const List<Color> chartSeries = <Color>[
    chartNavy,
    chartGold,
    chartTeal,
    chartPlum,
    chartTerracotta,
    chartSlate,
    chartOlive,
    chartRose,
  ];

  /// The colour for a `docs/brand.md` §2.5 token as stored on
  /// `Category.colorToken`.
  ///
  /// An unknown or null token falls back to [ink500] rather than throwing, the
  /// same forward-compatibility posture `categoryIconFor` takes: a category the
  /// user created carries whatever token the picker offered, and a future token
  /// added to brand.md must not be able to crash the report that renders it.
  /// Falling back to the *neutral* grey (rather than to a palette slot) is
  /// deliberate — an unrecognised token is closer to "unassigned" than to any
  /// particular series.
  static Color chartColorFor(String? token) => switch (token) {
    'chart-navy' => chartNavy,
    'chart-gold' => chartGold,
    'chart-teal' => chartTeal,
    'chart-plum' => chartPlum,
    'chart-terracotta' => chartTerracotta,
    'chart-slate' => chartSlate,
    'chart-olive' => chartOlive,
    'chart-rose' => chartRose,
    'chart-uncategorized' => chartUncategorized,
    _ => ink500,
  };
}

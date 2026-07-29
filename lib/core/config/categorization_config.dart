/// **ADR-008's tuning constants, in one place — residual open question O-1.**
///
/// The architecture is deliberate about this file existing:
///
/// > `autoApplyThreshold` is **a single named constant in
/// > `CategorizationConfig`**, initial value **0.85**, tunable without
/// > touching matching code. This is the residual of OQ-14: the *value* is a
/// > build-phase tuning parameter to be set against the corpus in P4, not a
/// > product commitment.
///
/// ## Why a config object and not literals at the comparison sites
///
/// Every number below decides whether the app is allowed to put a real
/// transaction into a category **without asking anyone**. If those numbers
/// were written at their comparison sites, tuning one would mean editing
/// matching logic, and a reviewer could not tell at a glance how aggressive
/// the app currently is. Here, the whole safety posture of the learning loop
/// is nine lines you can read in one go.
///
/// ## The one thing tuning cannot change (read before editing any value)
///
/// AC-D2.3's bar — *match, or flag; **never** silently miscategorise* — is
/// **not** enforced by these numbers. It is enforced by the tier structure in
/// `features/categorization/merchant_matcher.dart`, where the fuzzy tier T4
/// is incapable of auto-applying regardless of what [autoApplyThreshold] is
/// set to. Setting the threshold to `0.0` would still not let a T4 guess
/// through. That separation is intentional: a tuning mistake must not be able
/// to become a correctness failure.
///
/// ## A note for readers new to Dart
///
/// `abstract final class` means "this is a namespace for constants; you may
/// not instantiate it and you may not extend it" — the same shape
/// `SmsTextNormalizer` and `TransactionField` use elsewhere in this codebase.
library;

/// The tunable parameters of the merchant→category matcher (ADR-008).
abstract final class CategorizationConfig {
  /// **The single named constant ADR-008 requires.** A match is applied
  /// automatically only when its confidence is `>=` this value.
  ///
  /// Initial value 0.85, and it is still 0.85 after P4a's corpus tuning — see
  /// `test/features/categorization/merchant_matcher_test.dart`, which pins
  /// what each candidate value would do:
  ///
  /// | Value | Effect on the P4a corpus |
  /// |---|---|
  /// | 0.90 | T2 seed rules (0.90) still apply, but **every** token-set match
  ///   is refused — the "PANDA STORE 1234" ↔ "PANDA" class of cosmetic
  ///   variant would need re-tagging forever, and the learning loop never pays
  ///   off (the "too strict" failure KHA-31 names). |
  /// | **0.85** | Exact and alias matches apply. A token-set match applies
  ///   only at Jaccard `1.0` — i.e. the two strings contain *the same tokens*
  ///   and differ only in order, spacing, case, store number or noise words.
  ///   Every partial-overlap match is surfaced for review instead. |
  /// | 0.60 | Every T3 match applies, including `PANDA FRESH` ↔ `PANDA
  ///   EXPRESS`-shaped partial overlaps. That is the "silently merge unrelated
  ///   merchants" failure AC-D2.3 forbids. |
  ///
  /// So 0.85 is not inherited unexamined: it is the only value in the band
  /// that admits pure cosmetic variance and refuses partial overlap.
  static const double autoApplyThreshold = 0.85;

  /// Confidence for **T1** — an exact merchant-key (or user-linked alias)
  /// match against a rule the **user** created. Certainty by construction:
  /// the person told us this merchant belongs in this category.
  static const double userRuleConfidence = 1.00;

  /// Confidence for **T2** — an exact match against a **seed** rule (one
  /// shipped with the app rather than taught by this user).
  ///
  /// Below [userRuleConfidence] on purpose, so a user rule always outranks a
  /// seed rule for the same merchant (AC-D3.1). Still above
  /// [autoApplyThreshold], because an exact key match on a curated rule is
  /// not a guess.
  static const double seedRuleConfidence = 0.90;

  /// **T3 gate.** Token-set Jaccard similarity must reach this before a
  /// token-set match is even considered.
  static const double tokenSetJaccardFloor = 0.80;

  /// **T3 output band.** Jaccard [tokenSetJaccardFloor] maps to
  /// [tokenSetConfidenceFloor]; Jaccard `1.0` maps to
  /// [tokenSetConfidenceCeiling]. ADR-008's table states the band as
  /// `0.60–0.85`.
  static const double tokenSetConfidenceFloor = 0.60;
  static const double tokenSetConfidenceCeiling = 0.85;

  /// **T4 gate.** Normalised Damerau-Levenshtein similarity must reach this
  /// before the matcher will even *suggest* a merchant.
  static const double editDistanceRatioFloor = 0.90;

  /// **T4 ceiling.** ADR-008: T4 is `<= 0.60` and **never** auto-applies.
  ///
  /// The "never" is enforced structurally rather than by this number — see
  /// the library comment above and `MerchantMatch.canAutoApply`.
  static const double editDistanceConfidenceCeiling = 0.60;

  /// Fuzzy tiers (T3, T4) refuse to consider a merchant key shorter than
  /// this.
  ///
  /// **This is a safety rule, not a tuning knob.** Short keys are where fuzzy
  /// matching goes wrong in the way AC-D2.3 forbids: at three characters, a
  /// single substitution is already a 0.67 ratio and two unrelated merchants
  /// can look similar by pure coincidence. A short novel merchant must land
  /// in Uncategorized (AC-D2.4), which is exactly what refusing to fuzzy-match
  /// it produces.
  static const int minimumFuzzyMatchKeyLength = 4;
}

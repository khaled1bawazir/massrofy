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
  /// | **0.85** | Exact and alias matches apply. A token-**multiset** match
  ///   applies only at Jaccard `1.0` — i.e. the two strings contain *the same
  ///   tokens with the same multiplicities* and differ only in order, spacing,
  ///   case, store number or noise words. Every partial-overlap match is
  ///   surfaced for review instead. |
  /// | 0.60 | Every T3 match applies, including `PANDA FRESH` ↔ `PANDA
  ///   EXPRESS`-shaped partial overlaps. That is the "silently merge unrelated
  ///   merchants" failure AC-D2.3 forbids. |
  ///
  /// So 0.85 is not inherited unexamined: it is the only value in the band
  /// that admits pure cosmetic variance and refuses partial overlap.
  ///
  /// ## The multiset correction (KHA-100), and a corrected number (KHA-98)
  ///
  /// The "same tokens, different arrangement" sentence above is a
  /// **permutation** claim, and until ADR-008 v1.3 the code compared Dart
  /// `Set`s — so multiplicity was invisible and `QAFE QAFE` reached Jaccard 1.0
  /// against `QAFE`, auto-applying another brand's rule at exactly this
  /// threshold. The **code moved to meet the rationale**, not the other way
  /// round: `MerchantMatcher` now compares
  /// [MerchantKey.tokenMultisetOf](../../features/categorization/merchant_key.dart),
  /// so `{QAFE, QAFE}` vs `{QAFE}` is 1/2 = 0.5, below
  /// [tokenSetJaccardFloor], and the pair falls through to T4 where it can
  /// never auto-apply. The sentence above is now literally true.
  ///
  /// One figure a future tuner will look for, recorded correctly here because
  /// QA's report and this file both once had it wrong. After KHA-98 dropped
  /// city names from the noise list, `PANDA RIYADH` and `PANDA JEDDAH` are two
  /// keys rather than one. **Their Jaccard is 1/3 ≈ 0.33, not 0.5** —
  /// `|A ∩ B| / |A ∪ B|` over `{PANDA, RIYADH}` and `{PANDA, JEDDAH}` is
  /// 1 shared over 3 distinct. Either figure is far below the 0.80 floor, so
  /// the conclusion (flagged for review, never merged) is unchanged — but the
  /// number itself is what a tuner would reason from.
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

  /// **T3 gate.** Token-**multiset** Jaccard similarity must reach this before
  /// a T3 match is even considered (KHA-100 — see [autoApplyThreshold]).
  static const double tokenSetJaccardFloor = 0.80;

  // **`referenceDigitRunMinLength` was deleted here at ADR-008 v1.4
  // (KHA-106).** It is recorded as a comment rather than removed without trace,
  // because the temptation it represents is going to recur: a digit-length
  // threshold reads like an obvious tuning knob and it is not one.
  //
  // It was corroboration signal (ii) for the trailing-digit strip: "a run of ≥N
  // digits is a till/terminal id". At N = 4 it merged `QAMART 1000` and
  // `QAMART 2000` into ONE merchant row at confidence 1.00 — and no value of N
  // fixes that, because a length signal decides strippability from the run
  // alone and always leaves the shared prefix as the residue. **Every** N
  // collapses some pair of sibling outlets; N only chooses which pair.
  //
  // So it was deleted rather than retuned. O-1's posture — "the value is
  // tuning, the bar is not" — cannot protect a constant whose existence *is*
  // the bar. Do not reintroduce it, and do not add any other corroborator that
  // is not itself a `MerchantKey.noiseTokens` word: that property is what makes
  // `MerchantKey.of` idempotent (see its doc comment).

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

/// **ADR-008's tiered matcher** — KHA-31, risk R-5, AC-D2.1/D2.3/D2.4.
///
/// | Tier | Condition | Confidence | Action |
/// |---|---|---|---|
/// | T1 | exact `merchantKey` match on a **user-created** rule | 1.00 | auto-apply |
/// | T2 | exact `merchantKey` match on a **seed** rule | 0.90 | auto-apply |
/// | T3 | token-set Jaccard ≥ 0.80 against a known merchant | 0.60–0.85 | apply **only if ≥ threshold**, else flag |
/// | T4 | normalised Damerau-Levenshtein ratio ≥ 0.90 | ≤ 0.60 | **never** auto-apply — surface as "did you mean…" |
/// | — | no match | 0.00 | Uncategorized + `needsReview` (AC-D2.4) |
///
/// ## The bar, and where it is actually enforced
///
/// KHA-31 states it absolutely: **match, or flag as low-confidence. Never
/// silently miscategorize, and never silently merge unrelated merchants.**
///
/// That bar is *not* enforced by the confidence numbers. It is enforced by
/// three structural properties of this file, each of which survives any
/// retuning of `CategorizationConfig`:
///
///  1. [MerchantMatch.canAutoApply] is `false` for [MatchTier.editDistance]
///     **unconditionally**. Setting `autoApplyThreshold` to 0.0 would still
///     not let a T4 guess through.
///  2. A key shorter than `CategorizationConfig.minimumFuzzyMatchKeyLength`
///     is never fuzzy-matched at all. Short strings are where coincidental
///     similarity lives.
///  3. No match at all returns [MerchantMatch.none], whose category is null
///     and whose `needsReview` is true — AC-D2.4's *"a never-before-seen
///     merchant must be Uncategorized or low-confidence-flagged, and must NOT
///     be assigned a confident category by coincidence"*. There is no code
///     path from "unknown merchant" to "a category", because [none] carries no
///     category to apply.
///
/// ## This is a pure function, on purpose
///
/// [MerchantMatcher.match] takes a raw merchant string and a list of
/// candidates, and touches no database and no clock. That is what lets
/// KHA-31's required corpus tests be a table of inputs and expected verdicts
/// rather than a fixture-heavy integration test, and it is why the assembly of
/// candidates lives in `CategorizationService` rather than here.
library;

import 'dart:math' as math;

import '../../core/config/categorization_config.dart';
import 'merchant_key.dart';

/// Which tier produced a match.
enum MatchTier {
  /// T1 — exact key (or user-linked alias) on a rule the user created.
  userRule,

  /// T2 — exact key (or user-linked alias) on a rule shipped with the app.
  seedRule,

  /// T3 — the same set of significant tokens, in any order.
  tokenSet,

  /// T4 — a near-miss spelling. **Suggestion only, never applied.**
  editDistance,

  /// No candidate reached any tier's floor.
  none,
}

/// One merchant the matcher may match against, with its rule if it has one.
///
/// Assembled by the service layer from `merchant`, `merchant_alias` and
/// `merchant_rule` rows. A candidate with a null [categoryId] is a merchant
/// the app has seen but the user has never categorised — it can still be
/// *identified* (which is what stops a second row being created for it) but it
/// has nothing to teach.
final class MerchantCandidate {
  final int merchantId;

  /// The merchant's own ADR-008 key.
  final String merchantKey;

  /// User-linked alternative spellings (ADR-008's cross-script answer). An
  /// exact hit on one of these is as good as a hit on [merchantKey] — that is
  /// the entire point of the alias table: *"rules key on `merchantId`, not on
  /// the raw string, so one link fixes both scripts forever"*.
  final Set<String> aliasKeys;

  /// The rule's target category, or null when this merchant has no rule.
  final String? categoryId;

  /// `merchant_rule.id`, recorded on the transaction so it can say which rule
  /// categorised it (AC-D2.2).
  final int? ruleId;

  /// `user` | `seed` — decides T1 vs T2, and therefore AC-D3.1's precedence.
  final String? ruleSource;

  const MerchantCandidate({
    required this.merchantId,
    required this.merchantKey,
    this.aliasKeys = const <String>{},
    this.categoryId,
    this.ruleId,
    this.ruleSource,
  });

  bool get hasRule => categoryId != null && ruleId != null;

  /// No merchant string (NFR-S4).
  @override
  String toString() => 'MerchantCandidate(#$merchantId, rule=$ruleId)';
}

/// The matcher's verdict.
final class MerchantMatch {
  final MatchTier tier;

  /// The matched merchant, or null when nothing matched. **Note this is
  /// populated even when [categoryId] is null**: recognising the shop is
  /// useful (it stops a duplicate merchant row) even when it teaches no
  /// category.
  final int? merchantId;

  /// The category the matched rule names, or null when there is nothing to
  /// apply.
  final String? categoryId;

  final int? ruleId;

  /// `0.0`–`1.0`. Not money; a float is correct (architecture §4.2).
  final double confidence;

  const MerchantMatch({
    required this.tier,
    required this.confidence,
    this.merchantId,
    this.categoryId,
    this.ruleId,
  });

  /// AC-D2.4's landing place for an unrecognised merchant.
  static const MerchantMatch none = MerchantMatch(
    tier: MatchTier.none,
    confidence: 0.0,
  );

  /// **The single gate every automatic categorization passes through.**
  ///
  /// Three conditions, all required:
  ///
  ///  - there is a category to apply at all;
  ///  - the tier is allowed to apply automatically — T4 never is, regardless
  ///    of confidence or configuration (ADR-008: *"never auto-apply — surface
  ///    as 'did you mean…' in review"*);
  ///  - confidence reaches `CategorizationConfig.autoApplyThreshold`.
  bool get canAutoApply =>
      categoryId != null &&
      tier != MatchTier.editDistance &&
      tier != MatchTier.none &&
      confidence >= CategorizationConfig.autoApplyThreshold;

  /// True when the user should be asked. Every outcome that is not an
  /// auto-apply is one of these — there is no third, silent option.
  bool get needsReview => !canAutoApply;

  @override
  String toString() =>
      'MerchantMatch(${tier.name}, ${confidence.toStringAsFixed(2)}, '
      'merchant=$merchantId)';
}

/// ADR-008's matching tiers.
abstract final class MerchantMatcher {
  /// Matches [rawMerchant] against [candidates].
  ///
  /// Tiers are evaluated in order and the **first** hit wins, so a user rule
  /// can never be beaten by a fuzzy match on some other merchant (AC-D3.1).
  /// Within a tier, ties break on the longest key, which prefers the more
  /// specific merchant — `PANDA EXPRESS` over `PANDA` when both somehow tie.
  static MerchantMatch match(
    String? rawMerchant,
    List<MerchantCandidate> candidates,
  ) {
    final String? key = MerchantKey.ofOrNull(rawMerchant);
    if (key == null || candidates.isEmpty) {
      return MerchantMatch.none;
    }

    // --- T1 / T2: exact key, or an exact hit on a user-linked alias --------
    //
    // One pass over the candidates, collecting exact hits, then user rules
    // before seed rules. Collecting first (rather than returning on the first
    // exact hit) is what makes AC-D3.1 structural: if a merchant somehow had
    // both a user and a seed rule reachable, the user's wins by construction
    // rather than by iteration order.
    MerchantCandidate? exactUser;
    MerchantCandidate? exactSeed;
    MerchantCandidate? exactNoRule;

    for (final MerchantCandidate candidate in candidates) {
      final bool exact =
          candidate.merchantKey == key || candidate.aliasKeys.contains(key);
      if (!exact) {
        continue;
      }
      if (!candidate.hasRule) {
        exactNoRule ??= candidate;
        continue;
      }
      if (candidate.ruleSource == 'user') {
        exactUser ??= candidate;
      } else {
        exactSeed ??= candidate;
      }
    }

    if (exactUser != null) {
      return _applied(
        exactUser,
        MatchTier.userRule,
        CategorizationConfig.userRuleConfidence,
      );
    }
    if (exactSeed != null) {
      return _applied(
        exactSeed,
        MatchTier.seedRule,
        CategorizationConfig.seedRuleConfidence,
      );
    }
    if (exactNoRule != null) {
      // The shop is known; nobody has said where it belongs. Identified but
      // uncategorised — `merchantId` is returned so the caller reuses the
      // existing merchant row rather than creating a second one, and
      // `categoryId` stays null so nothing is applied.
      return MerchantMatch(
        tier: MatchTier.none,
        confidence: 0.0,
        merchantId: exactNoRule.merchantId,
      );
    }

    // Fuzzy tiers refuse short keys outright — see property 2 in the library
    // comment.
    if (key.length < CategorizationConfig.minimumFuzzyMatchKeyLength) {
      return MerchantMatch.none;
    }

    // --- T3: token-set Jaccard --------------------------------------------
    final Set<String> keyTokens = MerchantKey.tokensOf(key);
    MerchantCandidate? bestTokenSet;
    double bestJaccard = 0.0;

    for (final MerchantCandidate candidate in candidates) {
      if (!candidate.hasRule ||
          candidate.merchantKey.length <
              CategorizationConfig.minimumFuzzyMatchKeyLength) {
        continue;
      }
      final double jaccard = _jaccard(
        keyTokens,
        MerchantKey.tokensOf(candidate.merchantKey),
      );
      if (jaccard < CategorizationConfig.tokenSetJaccardFloor) {
        continue;
      }
      if (jaccard > bestJaccard ||
          (jaccard == bestJaccard &&
              bestTokenSet != null &&
              candidate.merchantKey.length > bestTokenSet.merchantKey.length)) {
        bestJaccard = jaccard;
        bestTokenSet = candidate;
      }
    }

    if (bestTokenSet != null) {
      return _applied(
        bestTokenSet,
        MatchTier.tokenSet,
        _tokenSetConfidence(bestJaccard),
      );
    }

    // --- T4: normalised Damerau-Levenshtein — suggestion only -------------
    MerchantCandidate? bestEdit;
    double bestRatio = 0.0;

    for (final MerchantCandidate candidate in candidates) {
      if (!candidate.hasRule ||
          candidate.merchantKey.length <
              CategorizationConfig.minimumFuzzyMatchKeyLength) {
        continue;
      }
      final double ratio = _damerauLevenshteinRatio(key, candidate.merchantKey);
      if (ratio < CategorizationConfig.editDistanceRatioFloor) {
        continue;
      }
      if (ratio > bestRatio) {
        bestRatio = ratio;
        bestEdit = candidate;
      }
    }

    if (bestEdit != null) {
      return _applied(
        bestEdit,
        MatchTier.editDistance,
        // Capped at ADR-008's ceiling. Even at ratio 1.0 — impossible here,
        // since an identical key would have matched exactly above — this stays
        // a suggestion, because `canAutoApply` refuses the tier itself.
        math.min(
          CategorizationConfig.editDistanceConfidenceCeiling,
          CategorizationConfig.editDistanceConfidenceCeiling * bestRatio,
        ),
      );
    }

    return MerchantMatch.none;
  }

  static MerchantMatch _applied(
    MerchantCandidate candidate,
    MatchTier tier,
    double confidence,
  ) => MerchantMatch(
    tier: tier,
    confidence: confidence,
    merchantId: candidate.merchantId,
    categoryId: candidate.categoryId,
    ruleId: candidate.ruleId,
  );

  /// Maps a Jaccard similarity in `[floor, 1.0]` onto ADR-008's stated
  /// confidence band `[0.60, 0.85]`, linearly.
  ///
  /// The consequence at the shipped threshold (0.85) is worth stating plainly,
  /// because it *is* the tuning decision: only a Jaccard of **1.0** reaches
  /// 0.85. So a token-set match auto-applies exactly when the two strings
  /// contain the same significant tokens and differ only in order, spacing,
  /// case, store number or noise words — i.e. when they are cosmetic variants
  /// (AC-D2.3's first requirement). Any *partial* overlap — `PANDA FRESH` vs
  /// `PANDA EXPRESS` — lands below and is surfaced for review instead of
  /// merging two shops (AC-D2.3's second requirement).
  static double _tokenSetConfidence(double jaccard) {
    const double floor = CategorizationConfig.tokenSetJaccardFloor;
    const double low = CategorizationConfig.tokenSetConfidenceFloor;
    const double high = CategorizationConfig.tokenSetConfidenceCeiling;
    final double position = ((jaccard - floor) / (1.0 - floor)).clamp(0.0, 1.0);
    return low + (high - low) * position;
  }

  /// |A ∩ B| / |A ∪ B|. Zero for two empty sets — not 1.0, which would call
  /// two merchants with no significant tokens identical.
  static double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) {
      return 0.0;
    }
    final int intersection = a.where(b.contains).length;
    final int union = <String>{...a, ...b}.length;
    return intersection / union;
  }

  /// `1 - distance / maxLength`, using Damerau-Levenshtein (Levenshtein plus
  /// **transposition**, so `PANAD` ↔ `PANDA` costs 1 edit and not 2 — swapped
  /// adjacent letters are the commonest typo shape in a hand-keyed merchant
  /// name).
  ///
  /// This is the *optimal string alignment* variant: adjacent transpositions
  /// are counted, but a substring is not transposed twice. It is the standard
  /// choice for short strings and it cannot under-count, which is the
  /// direction that matters — under-counting distance would over-state
  /// similarity.
  static double _damerauLevenshteinRatio(String a, String b) {
    if (a == b) {
      return 1.0;
    }
    if (a.isEmpty || b.isEmpty) {
      return 0.0;
    }

    final List<int> first = a.codeUnits;
    final List<int> second = b.codeUnits;
    final int rows = first.length + 1;
    final int columns = second.length + 1;

    final List<List<int>> distance = List<List<int>>.generate(
      rows,
      (int i) => List<int>.filled(columns, 0),
      growable: false,
    );

    for (int i = 0; i < rows; i++) {
      distance[i][0] = i;
    }
    for (int j = 0; j < columns; j++) {
      distance[0][j] = j;
    }

    for (int i = 1; i < rows; i++) {
      for (int j = 1; j < columns; j++) {
        final int cost = first[i - 1] == second[j - 1] ? 0 : 1;
        int best = math.min(
          distance[i - 1][j] + 1, // deletion
          math.min(
            distance[i][j - 1] + 1, // insertion
            distance[i - 1][j - 1] + cost, // substitution
          ),
        );
        if (i > 1 &&
            j > 1 &&
            first[i - 1] == second[j - 2] &&
            first[i - 2] == second[j - 1]) {
          best = math.min(best, distance[i - 2][j - 2] + 1); // transposition
        }
        distance[i][j] = best;
      }
    }

    final int longest = math.max(first.length, second.length);
    return 1.0 - distance[first.length][second.length] / longest;
  }
}

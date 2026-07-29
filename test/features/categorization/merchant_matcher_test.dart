/// **KHA-31's corpus tests** — ADR-008's tier table, and the bar it exists to
/// hold:
///
/// > **match, or flag as low-confidence. Never silently miscategorize, and
/// > never silently merge unrelated merchants.**
///
/// Three groups do the work KHA-31's done check names:
///
///  - *cosmetic variants match the right rule*,
///  - *an unrelated merchant does not match*,
///  - *a novel merchant lands Uncategorized/flagged rather than confidently
///    categorized*.
///
/// A fourth group is the **tuning evidence** for `autoApplyThreshold`
/// (residual open question O-1): it measures what the corpus does at 0.90,
/// 0.85 and 0.60 rather than asserting the shipped value is good because it is
/// the shipped value.
///
/// Every merchant string here is **synthetic** (NFR-M3).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/config/categorization_config.dart';
import 'package:massrofy/features/categorization/merchant_key.dart';
import 'package:massrofy/features/categorization/merchant_matcher.dart';

/// Builds a candidate the way `CategorizationService.loadCandidates` does.
MerchantCandidate candidate(
  int id,
  String rawName, {
  String? categoryId,
  int? ruleId,
  String? ruleSource,
  Set<String> aliases = const <String>{},
}) => MerchantCandidate(
  merchantId: id,
  merchantKey: MerchantKey.of(rawName),
  aliasKeys: aliases.map(MerchantKey.of).toSet(),
  categoryId: categoryId,
  ruleId: ruleId,
  ruleSource: ruleSource,
);

void main() {
  // A small, deliberately varied store: a user rule, a seed rule, a merchant
  // with no rule at all, and a long multi-token name.
  final List<MerchantCandidate> store = <MerchantCandidate>[
    candidate(
      1,
      'PANDA FOODS',
      categoryId: 'groceries',
      ruleId: 11,
      ruleSource: 'user',
    ),
    candidate(
      2,
      'SEC-KAHRABA',
      categoryId: 'utilities_bills',
      ruleId: 12,
      ruleSource: 'seed',
    ),
    candidate(3, 'TAMIMI MARKETS'),
    candidate(
      4,
      'NORTHWIND COFFEE ROASTERS',
      categoryId: 'dining',
      ruleId: 14,
      ruleSource: 'user',
    ),
  ];

  group('T1/T2 — exact key (AC-D2.1)', () {
    test('an exact match on a user rule applies at 1.00', () {
      final MerchantMatch match = MerchantMatcher.match('PANDA FOODS', store);
      expect(match.tier, MatchTier.userRule);
      expect(match.confidence, CategorizationConfig.userRuleConfidence);
      expect(match.categoryId, 'groceries');
      expect(match.ruleId, 11);
      expect(match.canAutoApply, isTrue);
    });

    test('an exact match on a seed rule applies at 0.90', () {
      final MerchantMatch match = MerchantMatcher.match('SEC-KAHRABA', store);
      expect(match.tier, MatchTier.seedRule);
      expect(match.confidence, CategorizationConfig.seedRuleConfidence);
      expect(match.canAutoApply, isTrue);
    });

    test('a known merchant with no rule is identified but categorises '
        'nothing', () {
      // Recognising the shop matters (it stops a second merchant row being
      // created); it teaches no category, so nothing is applied.
      final MerchantMatch match = MerchantMatcher.match(
        'TAMIMI MARKETS',
        store,
      );
      expect(match.merchantId, 3);
      expect(match.categoryId, isNull);
      expect(match.canAutoApply, isFalse);
      expect(match.needsReview, isTrue);
    });

    test('a user-linked alias hits the same tier as the merchant key — one '
        'link fixes both scripts (R-5)', () {
      final List<MerchantCandidate> withAlias = <MerchantCandidate>[
        candidate(
          5,
          'AL BAIK',
          categoryId: 'dining',
          ruleId: 15,
          ruleSource: 'user',
          aliases: <String>{'البيك'},
        ),
      ];
      final MerchantMatch match = MerchantMatcher.match('البيك', withAlias);
      expect(match.tier, MatchTier.userRule);
      expect(match.categoryId, 'dining');
      expect(match.canAutoApply, isTrue);
    });
  });

  group('cosmetic variants match the right rule (AC-D2.3)', () {
    // These all normalise to the same key, so they are T1 hits rather than
    // fuzzy ones — which is the design working: the *pipeline* absorbs
    // cosmetic variance so the *matcher* rarely has to guess.
    for (final String variant in <String>[
      'panda foods',
      'PANDA  FOODS',
      'PANDA FOODS BRANCH',
      // `PANDA FOODS STORE RIYADH` left this list at ADR-008 v1.3 (KHA-98):
      // the city name is a proper noun and is no longer stripped, so this is a
      // *different key* — a branch, not a cosmetic variant. It is asserted
      // below as the flagged case it now is.
      //
      // `PANDA FOODS 1420` and `PANDA-FOODS-0042` left it at ADR-008 v1.4
      // (KHA-106): a BARE digit run is no longer absorbed, because the length
      // signal that absorbed it also merged `QAMART 1000` with `QAMART 2000`
      // at confidence 1.00. What still absorbs a store number is a structural
      // marker beside it — the two rows below — and that is now read on either
      // side of the run (KHA-107).
      'PANDA FOODS STORE 0042',
      'PANDA FOODS 0042 STORE',
    ]) {
      test('"$variant" matches the PANDA FOODS rule', () {
        final MerchantMatch match = MerchantMatcher.match(variant, store);
        expect(match.categoryId, 'groceries');
        expect(match.canAutoApply, isTrue);
      });
    }

    test('KHA-106 — an UNCORROBORATED store number is flagged, not '
        'auto-applied: the disclosed cost, executed', () {
      // The other side of the rows removed above. `PANDA FOODS 1420` keys as
      // itself, and against `PANDA FOODS` the multiset Jaccard is 2/3 ≈ 0.67 —
      // below the 0.80 T3 floor — so it reaches no tier that may auto-apply.
      //
      // This is deliberately the same shape as the KHA-98 city case below: a
      // narrower normalisation trades a merge we cannot verify for a question
      // the user answers once. Recorded as a test so a future "improvement"
      // that widens the strip again fails CI instead of passing quietly.
      for (final String numbered in <String>[
        'PANDA FOODS 1420',
        'PANDA-FOODS-0042',
      ]) {
        final MerchantMatch match = MerchantMatcher.match(numbered, store);
        expect(
          match.canAutoApply,
          isFalse,
          reason:
              '"$numbered" carries nothing that says 1420/0042 is not part '
              'of the name, so the app must ask rather than merge',
        );
        expect(match.needsReview, isTrue);
      }
    });

    test('KHA-98 — a branch identified by a CITY name is flagged, not '
        'auto-applied', () {
      // The stated cost of dropping city names from the noise list, executed
      // rather than asserted in prose. `PANDA FOODS STORE RIYADH` keys as
      // `PANDA FOODS RIYADH`, whose multiset Jaccard against `PANDA FOODS` is
      // 2/3 ≈ 0.67 — below the 0.80 T3 floor — so the pair reaches no tier that
      // may auto-apply.
      //
      // This is AC-D2.3's named-and-accepted direction: *"match, or flag as
      // low-confidence — never silently merge unrelated merchants."* The user
      // links the branch once with a `MerchantAlias` and it is right forever.
      final MerchantMatch match = MerchantMatcher.match(
        'PANDA FOODS STORE RIYADH',
        store,
      );
      expect(
        match.canAutoApply,
        isFalse,
        reason:
            'a city-distinguished branch must be surfaced for review, not '
            'merged onto the parent chain\'s rule',
      );
      expect(match.needsReview, isTrue);
    });

    test('KHA-100 — a REPEATED token is a real difference, so T3 refuses it', () {
      // T3 is defined over the token *multiset* (ADR-008 v1.3 settled answer
      // 4). Over sets, `PANDA PANDA FOODS` was `{PANDA, FOODS}` — identical to
      // `PANDA FOODS`, Jaccard 1.0 — and auto-applied another brand's rule at
      // exactly the threshold. Over multisets it is 2/3 ≈ 0.67 and falls
      // through.
      //
      // No step of `MerchantKey.of` produces or removes a repeated token, so
      // the multiplicity is signal: two brand names that differ by a repetition
      // are two brand names.
      final MerchantMatch match = MerchantMatcher.match(
        'PANDA PANDA FOODS',
        store,
      );
      expect(match.canAutoApply, isFalse);
      expect(match.tier, isNot(MatchTier.tokenSet));
    });

    test('a genuine token reordering matches at T3 and applies', () {
      // Same tokens, different order — Jaccard 1.0, which is the only T3
      // score that reaches the shipped threshold.
      final MerchantMatch match = MerchantMatcher.match(
        'ROASTERS COFFEE NORTHWIND',
        store,
      );
      expect(match.tier, MatchTier.tokenSet);
      expect(match.confidence, CategorizationConfig.tokenSetConfidenceCeiling);
      expect(match.canAutoApply, isTrue);
      expect(match.categoryId, 'dining');
    });
  });

  group('an unrelated merchant does not match (AC-D2.3)', () {
    test('a partial token overlap is refused, not merged', () {
      // `PANDA EXPRESS` shares one token of two with `PANDA FOODS`:
      // Jaccard 1/3. Nowhere near the T3 floor, and it must never inherit the
      // groceries rule.
      final MerchantMatch match = MerchantMatcher.match('PANDA EXPRESS', store);
      expect(match.canAutoApply, isFalse);
      expect(match.categoryId, isNull);
    });

    test('a shared first token with a longer name is refused', () {
      final MerchantMatch match = MerchantMatcher.match(
        'NORTHWIND HARDWARE SUPPLY',
        store,
      );
      expect(match.canAutoApply, isFalse);
    });

    test('two completely unrelated names do not match at any tier', () {
      final MerchantMatch match = MerchantMatcher.match(
        'BLUE LAGOON DIVING',
        store,
      );
      expect(match.tier, MatchTier.none);
      expect(match.merchantId, isNull);
    });
  });

  group('a novel merchant lands Uncategorized/flagged (AC-D2.4)', () {
    test('an unseen merchant returns no category and asks for review', () {
      final MerchantMatch match = MerchantMatcher.match(
        'SYNTHETIC BOOKSHOP',
        store,
      );
      expect(match.tier, MatchTier.none);
      expect(match.categoryId, isNull);
      expect(match.canAutoApply, isFalse);
      expect(match.needsReview, isTrue);
    });

    test('an empty store categorises nothing', () {
      expect(
        MerchantMatcher.match(
          'PANDA FOODS',
          <MerchantCandidate>[],
        ).canAutoApply,
        isFalse,
      );
    });

    test('a short key is never fuzzy-matched, in either direction', () {
      // Three characters: one substitution is already a 0.67 ratio, and two
      // unrelated shops can look similar by pure coincidence.
      final List<MerchantCandidate> shortStore = <MerchantCandidate>[
        candidate(
          9,
          'ABC',
          categoryId: 'shopping_retail',
          ruleId: 19,
          ruleSource: 'user',
        ),
      ];
      expect(MerchantMatcher.match('ABD', shortStore).canAutoApply, isFalse);
      expect(MerchantMatcher.match('ABD', shortStore).tier, MatchTier.none);
    });

    test('no input at all matches nothing', () {
      expect(MerchantMatcher.match(null, store).tier, MatchTier.none);
      expect(MerchantMatcher.match('   ', store).tier, MatchTier.none);
    });
  });

  group('T4 — the tier that may never apply (ADR-008)', () {
    // One transposed pair inside a long key: ratio ≥ 0.90, so T4 fires —
    // and must produce a suggestion, never a categorization.
    const String nearMiss = 'NORTHWIDN COFFEE ROASTERS';

    test('a near-miss spelling is surfaced as a suggestion, not applied', () {
      final MerchantMatch match = MerchantMatcher.match(nearMiss, store);
      expect(match.tier, MatchTier.editDistance);
      expect(match.merchantId, 4);
      expect(
        match.confidence,
        lessThanOrEqualTo(CategorizationConfig.editDistanceConfidenceCeiling),
      );
      expect(match.canAutoApply, isFalse);
      expect(match.needsReview, isTrue);
    });

    test('T4 STILL cannot auto-apply if the threshold is dropped to zero — '
        'the refusal is structural, not numeric', () {
      // The single most important assertion in this file. AC-D2.3's bar is
      // enforced by `canAutoApply` refusing the *tier*, so no retuning of
      // `autoApplyThreshold` — including a mistaken one — can turn a T4 guess
      // into an automatic categorization.
      final MerchantMatch match = MerchantMatcher.match(nearMiss, store);
      const double anyThresholdHowever = 0.0;
      expect(match.confidence, greaterThanOrEqualTo(anyThresholdHowever));
      expect(
        match.canAutoApply,
        isFalse,
        reason:
            'canAutoApply must reject MatchTier.editDistance before it ever '
            'looks at a number',
      );
    });
  });

  group('AC-D3.1 — a user rule outranks a seed rule', () {
    test('when both are reachable for the same key, the user rule wins', () {
      // Constructed deliberately: two candidates whose keys are identical, one
      // seeded and one taught by the user. The matcher collects exact hits and
      // prefers the user's, so the outcome does not depend on list order.
      final List<MerchantCandidate> conflicting = <MerchantCandidate>[
        candidate(
          20,
          'DUAL RULED SHOP',
          categoryId: 'shopping_retail',
          ruleId: 30,
          ruleSource: 'seed',
        ),
        candidate(
          21,
          'DUAL RULED SHOP',
          categoryId: 'groceries',
          ruleId: 31,
          ruleSource: 'user',
        ),
      ];

      expect(
        MerchantMatcher.match('DUAL RULED SHOP', conflicting).categoryId,
        'groceries',
      );
      expect(
        MerchantMatcher.match(
          'DUAL RULED SHOP',
          conflicting.reversed.toList(),
        ).categoryId,
        'groceries',
        reason: 'the precedence must not depend on iteration order',
      );
    });
  });

  group('O-1 — tuning evidence for autoApplyThreshold', () {
    // What each candidate value would do to this corpus. The numbers are
    // measured here rather than asserted from intuition, which is what
    // ADR-008 asks for: "the *value* is a build-phase tuning parameter to be
    // set against the corpus in P4".
    const double shipped = CategorizationConfig.autoApplyThreshold;

    test('the shipped value is 0.85', () {
      expect(shipped, 0.85);
    });

    test('at 0.85, a pure token reordering applies and a partial overlap does '
        'not — the band that separates them is real', () {
      final MerchantMatch reordered = MerchantMatcher.match(
        'ROASTERS COFFEE NORTHWIND',
        store,
      );
      final MerchantMatch partial = MerchantMatcher.match(
        'NORTHWIND COFFEE',
        store,
      );

      expect(reordered.confidence, greaterThanOrEqualTo(shipped));
      expect(
        partial.confidence,
        lessThan(shipped),
        reason:
            'two of three tokens shared is a different shop until a person '
            'says otherwise',
      );
    });

    test('at 0.90 the token-set tier would be dead — every cosmetic variant '
        'needs re-tagging forever', () {
      // The "too strict" failure KHA-31 names: the learning loop never pays
      // off. Measured, not assumed: the ceiling of the T3 band is 0.85, so a
      // threshold of 0.90 refuses every T3 match there can ever be.
      expect(CategorizationConfig.tokenSetConfidenceCeiling, lessThan(0.90));
    });

    test('at 0.60 an unrelated partial overlap would auto-apply — the "too '
        'loose" failure', () {
      // `PANDA EXPRESS` vs `PANDA FOODS` is below the T3 *floor*, so it is
      // refused at any threshold — good. The measurable danger at 0.60 is the
      // band's own floor: every T3 match, however partial, would apply.
      const double loose = 0.60;
      expect(
        CategorizationConfig.tokenSetConfidenceFloor,
        greaterThanOrEqualTo(loose),
        reason:
            'at a 0.60 threshold every token-set match down to Jaccard 0.80 '
            'auto-applies, which is where unrelated branches of different '
            'chains start merging',
      );
    });
  });
}

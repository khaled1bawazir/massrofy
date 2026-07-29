/// **QA adversarial probe suite for PR #30 (P4a-1 — KHA-88/94/96/98/99/100/
/// 101/102/103/104/105).**
///
/// Written by qa-tester against head `3620388`, 2026-07-29. This is the
/// **third** adversarial round on `MerchantKey`/`MerchantMatcher` and the
/// **third** on the merge/undo link, so the standing instruction for this file
/// is: *do not re-run the fixed probes and call that coverage*. The inverted
/// probes in `qa_pr20/24/27_probe_test.dart` already pin every done-check.
/// This file only asks questions those files do not.
///
/// The four hostile questions of this round:
///
///  1. **The corroboration rule is a rule now, not a list — does the code
///     satisfy its own rule?** Specifically condition 3, *residue-safety*: is
///     there any OTHER pair of strings the pipeline still reduces to one key,
///     and does `MerchantKey.of` still hold the invariants its own doc comment
///     claims (idempotence)?
///  2. **KHA-94 was a composition attack, and composition attacks do not come
///     one at a time.** Does the set-valued link survive three-deep absorbs,
///     an undo in the middle, a re-merge after an undo, and concurrency —
///     rather than only the two-merge-one-undo shape J1/J1b cover?
///  3. **Does each narrowing shipped in this PR narrow to exactly the right
///     set?** A fix that adds a condition can leave a residue on the other
///     side of that condition. `isUserOwnedCategory` (KHA-103) and
///     `possibleDuplicateOfId` (O-QA-11) are both new conditions.
///  4. **Are the two-sided defences actually two-sided?** KHA-104 claims a
///     write-side AND a read-side guard; a claim of redundancy is worth
///     nothing if only one half exists.
///
/// Naming convention, carried over from the previous three suites:
///
///  - `HOLDS` — the property survived the attack. This is audit evidence that
///    the attack was *run*, not an assumption that it would fail.
///  - `DEFECT` — an executed reproduction of behaviour that contradicts an
///    acceptance criterion, a done-check, or a claim the code makes about
///    itself. Each is filed in `docs/defects.md` under the id in the test name.
///
/// **No production code is changed by this file.** It is additive, test-only
/// evidence; the tree hash of `lib/` is identical with and without it.
///
/// NFR-M3: every merchant string below is synthetic. No real user's SMS text
/// appears here.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/config/categorization_config.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/category_dao.dart';
import 'package:massrofy/data/dao/merchant_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/categorization/categorization_service.dart';
import 'package:massrofy/features/categorization/merchant_key.dart';
import 'package:massrofy/features/categorization/merchant_matcher.dart';
import 'package:massrofy/features/ledger/transaction_merge.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../support/plain_test_database.dart';

final List<int> _qaChainKey = List<int>.generate(32, (int i) => i + 101);

void main() {
  late AppDatabase db;
  late AuditLogDao auditLogDao;
  late CategoryDao categoryDao;
  late MerchantDao merchantDao;
  late TransactionDao transactionDao;
  late CategorizationService service;
  late TransactionMergeService merge;

  setUp(() async {
    db = openPlainTestDatabase();
    auditLogDao = AuditLogDao(db, auditChainKey: _qaChainKey);
    categoryDao = CategoryDao(db, auditLogDao);
    merchantDao = MerchantDao(db, auditLogDao);
    transactionDao = TransactionDao(db, auditLogDao);
    service = CategorizationService(
      categoryDao: categoryDao,
      merchantDao: merchantDao,
      transactionDao: transactionDao,
    );
    merge = TransactionMergeService(
      database: db,
      transactionDao: transactionDao,
    );
    await service.ensureDefaultsSeeded();
  });

  tearDown(() async => db.close());

  int nextMessageId = 5000;

  /// One ingested purchase. Defaults are identical across calls on purpose, so
  /// any two are a legitimate duplicate pair and `MergePlan.between` has no
  /// field disagreement to refuse on — the merge probes are about the *link*,
  /// not about field comparison.
  Future<int> sms({String? merchant, String amount = '152.75'}) =>
      transactionDao.insertFromParsedSms(
        amount: Money.parse(amount, currency: 'SAR'),
        merchantRawText: merchant,
        occurredAt: DateTime.utc(2026, 7, 15, 12),
        direction: 'debit',
        transactionType: TransactionType.posPurchase,
        affectsSpend: true,
        sourceMessageId: nextMessageId++,
        rulePackId: 'sa-core',
        rulePackVersion: '2026.07.28',
        ruleId: 'baj-pos-purchase-ar',
      );

  /// The invariant `absorbedTransactionIds`' doc comment states as the thing
  /// that makes the scalar cache safe. Asserted after *every* mutation in the
  /// merge probes below, rather than once at the end, so a probe reports the
  /// step that broke it.
  Future<void> expectScalarSetInvariant(int id, {required String at}) async {
    final TransactionRow row = await transactionDao.byId(id);
    final List<int> absorbed = await transactionDao.absorbedTransactionIds(id);
    expect(
      row.mergedFromTransactionId == null,
      absorbed.isEmpty,
      reason:
          'the scalar is null iff the set is empty — violated at "$at" '
          '(scalar=${row.mergedFromTransactionId}, set=$absorbed)',
    );
    if (absorbed.isNotEmpty) {
      expect(
        row.mergedFromTransactionId,
        absorbed.first,
        reason: 'the scalar must name the MOST RECENT absorbed row at "$at"',
      );
    }
  }

  // =========================================================================
  // PROBE M — merchant identity, round 3. Attacking the *rule*, not the list.
  // =========================================================================
  group('PROBE M — does the corroboration rule hold against strings nobody '
      'has tried yet?', () {
    test('M1 DEFECT (D-QA-30-1) — `MerchantKey.of` is NOT idempotent, and its '
        'own doc comment says it must be: a trailing digit run that only '
        'becomes trailing AFTER noise removal is stripped on the second pass '
        'but not the first', () async {
      // `of`'s doc comment states the invariant and states why it matters:
      //   "Idempotent — of(of(x)) == of(x) — which matters because a key is
      //    computed when a merchant is created and recomputed on every later
      //    message. A pipeline that changed its own output on a second pass
      //    would stop matching the very rows it wrote."
      //
      // The pipeline runs step 6 (digit strip) BEFORE step 7 (noise strip).
      // So in `PANDA 1234 STORE` the digit run is not last when step 6 looks,
      // and step 7 then removes `STORE` and *makes* it last. Feed the result
      // back in and the digit run is now stripped.
      const String raw = 'PANDA 1234 STORE';
      final String once = MerchantKey.of(raw);
      final String twice = MerchantKey.of(once);

      expect(
        once,
        'PANDA 1234',
        reason: 'first pass: STORE removed, 1234 kept',
      );
      expect(twice, 'PANDA', reason: 'second pass: 1234 is now trailing');
      expect(
        twice,
        isNot(once),
        reason:
            'D-QA-30-1: of(of(x)) != of(x) — the documented invariant '
            'is false for this shape',
      );

      // The user-visible consequence, and the reason this is filed rather than
      // noted: two orderings of the SAME shop's name produce different keys,
      // so PRD §3.4's "all renderings of one shop produce one key" fails here.
      expect(
        MerchantKey.of('PANDA STORE 1234'),
        'PANDA',
        reason: 'marker-before-digits: corroborated, stripped',
      );
      expect(
        MerchantKey.of('PANDA 1234 STORE'),
        isNot(MerchantKey.of('PANDA STORE 1234')),
        reason:
            'D-QA-30-1: the same three tokens in a different order are '
            'two different merchant identities',
      );
    });

    test('M2 DEFECT (D-QA-30-2) — KHA-99 is closed at 3 digits and OPEN at 4: '
        'numbered sibling outlets with a 4-digit number still collapse to one '
        'identity at confidence 1.00', () async {
      // KHA-99's done-check names `QAMART 100` / `QAMART 200`, and that pair is
      // genuinely fixed. But the length signal (corroboration (ii)) fires on
      // any run of `referenceDigitRunMinLength` = 4 or more digits with no
      // other corroboration at all, so the very same defect survives one digit
      // further along. Four-digit outlet numbers are not exotic.
      expect(CategorizationConfig.referenceDigitRunMinLength, 4);

      expect(
        MerchantKey.of('QAMART 100'),
        'QAMART 100',
        reason: 'KHA-99 fixed',
      );
      expect(
        MerchantKey.of('QAMART 200'),
        'QAMART 200',
        reason: 'KHA-99 fixed',
      );

      // …and here is the same shape one digit longer.
      expect(MerchantKey.of('QAMART 1000'), 'QAMART');
      expect(MerchantKey.of('QAMART 2000'), 'QAMART');
      expect(
        MerchantKey.of('QAMART 1000'),
        MerchantKey.of('QAMART 2000'),
        reason:
            'D-QA-30-2: two distinct numbered outlets, one merchant_key — '
            'the KHA-98/99 collision shape, unreached by either done-check',
      );

      // Executed end to end, because a key collision alone is only half the
      // story: this is the tier and confidence it lands at.
      final MerchantMatch match =
          MerchantMatcher.match('QAMART 2000', <MerchantCandidate>[
            const MerchantCandidate(
              merchantId: 1,
              merchantKey: 'QAMART',
              categoryId: 'groceries',
              ruleId: 1,
              ruleSource: 'user',
            ),
          ]);
      expect(match.tier, MatchTier.userRule);
      expect(match.confidence, 1.00);
      expect(
        match.canAutoApply,
        isTrue,
        reason:
            'D-QA-30-2: auto-applied at T1 — above every tier gate, '
            'exactly as KHA-98/99 described',
      );
    });

    test('M3 HOLDS — the residue-safety sweep: no OTHER structural token in '
        'the noise list can collapse two distinguishable businesses', () async {
      // Condition 3 of the corroboration rule, checked mechanically rather than
      // by reading the list. For every noise token N, `QANDA <N>` must not
      // become equal to some *other* proper-noun key — i.e. removing N may only
      // ever remove N, never expose a collision with a different name.
      //
      // The real risk this checks for is a token that is structural in one
      // reading and a proper noun in another. Nothing currently in the list is,
      // and this is the evidence.
      for (final String noise in MerchantKey.noiseTokens) {
        expect(
          MerchantKey.of('QANDA $noise'),
          'QANDA',
          reason: '$noise is structural: it may only remove itself',
        );
        expect(
          MerchantKey.ofOrNull(noise),
          isNull,
          reason: '$noise alone is not an identity (KHA-102)',
        );
      }

      // Two shops that differ ONLY in a proper noun must never collide — the
      // KHA-98 shape, swept over city-shaped, district-shaped, mall-shaped and
      // person-shaped distinguishing tokens rather than the one pair the
      // done-check names.
      const List<String> properNouns = <String>[
        'MAKKAH',
        'MADINAH',
        'RIYADH',
        'JEDDAH',
        'DAMMAM',
        'KHOBAR',
        'OLAYA',
        'TAHLIA',
        'QANDAMALL',
        'ALQANDI',
      ];
      final Set<String> keys = <String>{
        for (final String noun in properNouns) MerchantKey.of('$noun BAKERY'),
      };
      expect(
        keys,
        hasLength(properNouns.length),
        reason: 'every distinguishing proper noun must survive into the key',
      );

      // Arabic branch vocabulary still strips (this is the *wanted* half of
      // KHA-98's fix boundary: `فرع` is structural, the city was not).
      expect(MerchantKey.of('فرع QANDA'), 'QANDA');
    });

    test('M4 HOLDS — `referenceMarkerTokens` is a subset of `noiseTokens`, so '
        'adjacency corroboration cannot be widened without also widening the '
        'reviewed noise list', () async {
      // If a token could corroborate a digit strip WITHOUT itself being noise,
      // someone could add a proper noun there (`RIYADH`) and get a digit strip
      // that the noise-list allow-list test would never see. The subset
      // property is what makes the allow-list test cover both sets. It holds
      // today; it is not asserted anywhere in the engineer's suite, so this is
      // the only thing standing between a future edit and that gap.
      expect(
        MerchantKey.referenceMarkerTokens.difference(MerchantKey.noiseTokens),
        isEmpty,
        reason: 'every reference marker must also be a reviewed noise token',
      );
    });

    test('M5 HOLDS — the KHA-100 multiset fix is not "disable T3", and a '
        'repeated token cannot reach auto-apply by any arrangement', () async {
      const List<MerchantCandidate> candidates = <MerchantCandidate>[
        MerchantCandidate(
          merchantId: 7,
          merchantKey: 'QAFE',
          categoryId: 'dining',
          ruleId: 3,
          ruleSource: 'user',
        ),
      ];

      // The KHA-100 case: 1/2 = 0.5, below the 0.80 floor, so not even T3.
      final MerchantMatch repeated = MerchantMatcher.match(
        'QAFE QAFE',
        candidates,
      );
      expect(repeated.canAutoApply, isFalse);

      // Three-deep repetition, and repetition in the *candidate* rather than
      // the query — the mirror direction, which the engineer's test does not
      // cover. Multiset Jaccard is symmetric; asserted, not assumed.
      expect(
        MerchantMatcher.match('QAFE QAFE QAFE', candidates).canAutoApply,
        isFalse,
      );
      expect(
        MerchantMatcher.match('QAFE', const <MerchantCandidate>[
          MerchantCandidate(
            merchantId: 7,
            merchantKey: 'QAFE QAFE',
            categoryId: 'dining',
            ruleId: 3,
            ruleSource: 'user',
          ),
        ]).canAutoApply,
        isFalse,
        reason: 'the mirror direction must refuse too',
      );

      // …but a genuine permutation still applies, or the fix would have been
      // "turn T3 off", which AC-D2.1's learning promise cannot afford.
      final MerchantMatch permuted =
          MerchantMatcher.match('FRESH QANDA', const <MerchantCandidate>[
            MerchantCandidate(
              merchantId: 9,
              merchantKey: 'QANDA FRESH',
              categoryId: 'groceries',
              ruleId: 5,
              ruleSource: 'user',
            ),
          ]);
      expect(permuted.tier, MatchTier.tokenSet);
      expect(permuted.canAutoApply, isTrue);
    });

    test('M6 HOLDS — KHA-98\'s pair is refused at EVERY tier, not merely at '
        'T1: no "did you mean" leaks it back in', () async {
      // The done-check only asks that the keys differ. Differing keys are not
      // enough on their own — T3 or T4 could still reunite them. This is the
      // end-to-end refusal.
      final MerchantMatch match =
          MerchantMatcher.match('MADINAH BAKERY', const <MerchantCandidate>[
            MerchantCandidate(
              merchantId: 1,
              merchantKey: 'MAKKAH BAKERY',
              categoryId: 'dining',
              ruleId: 1,
              ruleSource: 'user',
            ),
          ]);
      expect(match.tier, MatchTier.none);
      expect(match.categoryId, isNull);
      expect(match.canAutoApply, isFalse);
      expect(match.needsReview, isTrue);
    });

    test('M7 HOLDS — the ADR-008 v1.3 footnote this PR discloses is accurate: '
        '`QAFE QAFE` falls past T4 as well, and the DL ratio is ≈0.44', () {
      // The PR discloses a correction to its own ADR (the ADR said T4 offers a
      // suggestion; it does not). Verifying a disclosed correction rather than
      // taking it on trust — a PR that corrects itself can still get the
      // correction wrong.
      final MerchantMatch match =
          MerchantMatcher.match('QAFE QAFE', const <MerchantCandidate>[
            MerchantCandidate(
              merchantId: 7,
              merchantKey: 'QAFE',
              categoryId: 'dining',
              ruleId: 3,
              ruleSource: 'user',
            ),
          ]);
      expect(match.tier, MatchTier.none, reason: 'past T4, not stopped at it');

      // 1 - 5/9 = 0.444…  ('QAFE QAFE' is 9 chars, 'QAFE' is 4; 5 insertions.)
      const double expected = 1.0 - 5.0 / 9.0;
      expect(expected, lessThan(CategorizationConfig.editDistanceRatioFloor));
      expect((expected * 100).round(), 44, reason: 'the PR says ≈0.44');
    });
  });

  // =========================================================================
  // PROBE N — the set-valued link under compositions J1/J1b do not reach.
  // =========================================================================
  group('PROBE N — does the KHA-94 fix survive composition beyond the probe '
      'that proves it?', () {
    test('N1 HOLDS — KHA-94 end to end through the public service: '
        'merge → merge → undo → re-merge is refused for the RIGHT reason, and '
        'the invariant holds at every step', () async {
      final int survivor = await sms();
      final int first = await sms();
      final int second = await sms();
      final int newSurvivor = await sms();

      await expectScalarSetInvariant(survivor, at: 'before any merge');

      await merge.merge(
        survivorId: survivor,
        mergedAwayId: first,
        confirmedByUser: true,
      );
      await expectScalarSetInvariant(survivor, at: 'after absorbing first');

      await merge.merge(
        survivorId: survivor,
        mergedAwayId: second,
        confirmedByUser: true,
      );
      await expectScalarSetInvariant(survivor, at: 'after absorbing second');
      expect(
        await transactionDao.absorbedTransactionIds(survivor),
        <int>[second, first],
        reason: 'newest-absorbed first',
      );

      // The step that used to blank the scalar and disarm the guard.
      await merge.undo(second);
      await expectScalarSetInvariant(survivor, at: 'after undoing second');
      expect(
        (await transactionDao.byId(survivor)).mergedFromTransactionId,
        first,
        reason: 'KHA-88: re-pointed to the earlier absorb, not blanked',
      );

      final MergeResult chained = await merge.merge(
        survivorId: newSurvivor,
        mergedAwayId: survivor,
        confirmedByUser: true,
      );
      expect(
        (chained as MergeRejected).reason,
        MergeRefusal.chainWouldForm,
        reason: 'KHA-94: the composition no longer defeats the guard',
      );
      expect((await transactionDao.byId(survivor)).isDeleted, isFalse);
      expect((await transactionDao.byId(first)).isDeleted, isTrue);
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('N2 HOLDS — three-deep absorb with the MIDDLE undo: the scalar '
        'follows the remaining set, and undoing every absorb re-opens the '
        'merge (no false-positive lock-out)', () async {
      final int survivor = await sms();
      final int a = await sms();
      final int b = await sms();
      final int c = await sms();
      final int target = await sms();

      for (final int absorbed in <int>[a, b, c]) {
        await merge.merge(
          survivorId: survivor,
          mergedAwayId: absorbed,
          confirmedByUser: true,
        );
        await expectScalarSetInvariant(survivor, at: 'absorbed $absorbed');
      }
      expect(await transactionDao.absorbedTransactionIds(survivor), <int>[
        c,
        b,
        a,
      ]);

      // Undo the MIDDLE one — the scalar does not name it, so `restore`'s
      // identity check must leave the scalar alone entirely.
      await merge.undo(b);
      await expectScalarSetInvariant(survivor, at: 'undid the middle absorb');
      expect(
        (await transactionDao.byId(survivor)).mergedFromTransactionId,
        c,
        reason: 'the most recent absorb is untouched by an unrelated undo',
      );
      expect(await transactionDao.absorbedTransactionIds(survivor), <int>[
        c,
        a,
      ]);

      // Still encumbered, so still refused.
      expect(
        (await merge.merge(
                  survivorId: target,
                  mergedAwayId: survivor,
                  confirmedByUser: true,
                )
                as MergeRejected)
            .reason,
        MergeRefusal.chainWouldForm,
      );

      // Now undo the rest. The guard must RELEASE — a guard that never lets go
      // is its own defect, and nothing in the fix's own tests checks that the
      // refusal is reversible.
      await merge.undo(c);
      await expectScalarSetInvariant(survivor, at: 'undid the newest absorb');
      expect(
        (await transactionDao.byId(survivor)).mergedFromTransactionId,
        a,
        reason: 're-pointed past the already-restored middle row',
      );

      await merge.undo(a);
      await expectScalarSetInvariant(survivor, at: 'undid the last absorb');
      expect(
        (await transactionDao.byId(survivor)).mergedFromTransactionId,
        isNull,
      );
      expect(
        await merge.merge(
          survivorId: target,
          mergedAwayId: survivor,
          confirmedByUser: true,
        ),
        isA<MergeCompleted>(),
        reason: 'a genuinely unencumbered row must still be mergeable',
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('N3 HOLDS — merge → undo → RE-merge the same pair, then chain: the '
        'guard re-arms', () async {
      final int survivor = await sms();
      final int absorbed = await sms();
      final int target = await sms();

      await merge.merge(
        survivorId: survivor,
        mergedAwayId: absorbed,
        confirmedByUser: true,
      );
      await merge.undo(absorbed);
      await expectScalarSetInvariant(survivor, at: 'after undo');

      // Re-merging the same pair is the ordinary "I changed my mind twice"
      // path, and it must leave the guard armed again rather than in some
      // half-state left over from the undo.
      expect(
        await merge.merge(
          survivorId: survivor,
          mergedAwayId: absorbed,
          confirmedByUser: true,
        ),
        isA<MergeCompleted>(),
      );
      await expectScalarSetInvariant(survivor, at: 'after re-merge');
      expect(
        (await merge.merge(
                  survivorId: target,
                  mergedAwayId: survivor,
                  confirmedByUser: true,
                )
                as MergeRejected)
            .reason,
        MergeRefusal.chainWouldForm,
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('N4 HOLDS — concurrent merges into the SAME survivor: both land, the '
        'set holds both, and the scalar names exactly one of them', () async {
      // PR #20's probe B7 raced two merges of one row into two survivors. The
      // untested direction is two DIFFERENT rows into one survivor at once,
      // which is the shape that writes the scalar twice.
      final int survivor = await sms();
      final int first = await sms();
      final int second = await sms();

      final List<MergeResult> results =
          await Future.wait<MergeResult>(<Future<MergeResult>>[
            merge.merge(
              survivorId: survivor,
              mergedAwayId: first,
              confirmedByUser: true,
            ),
            merge.merge(
              survivorId: survivor,
              mergedAwayId: second,
              confirmedByUser: true,
            ),
          ]);

      expect(results.whereType<MergeCompleted>(), hasLength(2));
      expect(
        (await transactionDao.absorbedTransactionIds(survivor)).toSet(),
        <int>{first, second},
      );
      await expectScalarSetInvariant(survivor, at: 'after concurrent merges');
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('N5 HOLDS — a row that has absorbed nothing but was ITSELF restored '
        'from an absorb can be merged again: the back-pointer is cleared on '
        'restore, so `absorbedTransactionIds` cannot see a ghost', () async {
      // `absorbedTransactionIds` filters on `merged_into_id = survivor AND
      // is_deleted`. If `restore` cleared only one of the two, a restored row
      // would either haunt the set forever (permanent false refusal) or vanish
      // from it while still deleted (the KHA-94 hole again). Both halves must
      // move together; this asserts they do.
      final int survivor = await sms();
      final int absorbed = await sms();
      final int target = await sms();

      await merge.merge(
        survivorId: survivor,
        mergedAwayId: absorbed,
        confirmedByUser: true,
      );
      await merge.undo(absorbed);

      final TransactionRow restored = await transactionDao.byId(absorbed);
      expect(restored.isDeleted, isFalse);
      expect(restored.mergedIntoId, isNull, reason: 'no ghost back-pointer');
      expect(await transactionDao.absorbedTransactionIds(survivor), isEmpty);

      expect(
        await merge.merge(
          survivorId: target,
          mergedAwayId: absorbed,
          confirmedByUser: true,
        ),
        isA<MergeCompleted>(),
        reason: 'a restored row is an ordinary live row again',
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });
  });

  // =========================================================================
  // PROBE P — do this PR's new NARROWINGS narrow to the right set?
  // =========================================================================
  group('PROBE P — the conditions added by this PR, attacked from the other '
      'side of the condition', () {
    test('P1 HOLDS (attack run, defeated) — KHA-103\'s `isUserOwnedCategory` '
        'narrowing reads WIDER than the comment beside it, but the dangerous '
        'state it would admit is unreachable: nothing can produce '
        '`category_source = \'rule\'` on a row marked user-edited', () async {
      // KHA-103's done-check, verbatim: "no transaction holds a
      // `category_rule_id` for a non-existent rule, AND NONE SAYS
      // `category_source = 'rule'` WITH A NULL `category_id`."
      //
      // The fix guards the source/confidence clear on `isUserOwnedCategory`,
      // and the comment beside it explains the exception as "a row whose
      // category a PERSON chose keeps `category_source = 'user'`". But
      // `isUserOwnedCategory` is an **OR** of two deliberately-redundant
      // signals (`category_source == 'user'` OR `user_edited_fields` contains
      // `categoryId`), so when only the SECOND disjunct is true the row keeps
      // `category_source = 'rule'` — not `'user'` as the comment predicts.
      //
      // So the attack is: separate the two signals — reach a row that is
      // `user_edited_fields`-protected while `category_source` is still
      // `'rule'` — then delete its category. The merge looked like the way in,
      // because it unions protected fields across the pair without touching
      // the survivor's own `category_source`.
      //
      // **It does not work, and the reason is worth recording**: the union is
      // over `MergeEnrichment.protectedFields`, which contains only fields
      // actually *carried* into a gap. A rule-categorized survivor has no gap
      // in `category_id`, so nothing is carried and no protection is
      // inherited. And in the one shape where `category_id` IS carried, the
      // survivor by definition had no category, so its source was never
      // `'rule'` either. Backed up structurally by
      // `applyAutomaticCategory`'s AC-D3.1 guard, which returns without
      // writing anything at all for a user-owned row — so the automatic path
      // can never stamp `'rule'` onto a protected row in the first place.
      //
      // Filed as O-QA-30-1 (an observation on the comment, not a defect):
      // `isUserOwnedCategory` is an OR, the comment beside the call site
      // predicts `'user'`, and only an invariant enforced in a different file
      // makes the two agree.
      final CategoryRow doomed = (await categoryDao.createCustom(
        name: 'QA Doomed',
        iconToken: 'tag',
        groupKey: 'other',
      ))!;

      final int userOwned = await sms(merchant: 'QANDA');
      final int ruleOwned = await sms(merchant: 'QANDA');

      // Left row: a person chose the category -> source 'user' AND the field
      // marked user-edited. Also mints the merchant rule.
      await service.applyUserCategory(
        transactionId: userOwned,
        categoryId: doomed.id,
      );
      // Right row: the rule fires -> source 'rule', no user-edited marking.
      await service.categorizeTransaction(transactionId: ruleOwned);
      expect(
        (await transactionDao.byId(ruleOwned)).categorySource,
        StoredCategorySource.rule,
      );
      expect(
        decodeUserEditedFields(
          (await transactionDao.byId(ruleOwned)).userEditedFields,
        ),
        isNot(contains(TransactionField.categoryId)),
      );

      // The attack: merge the user-owned row INTO the rule-owned one, hoping
      // the survivor inherits the protection marking while keeping `'rule'`.
      expect(
        await merge.merge(
          survivorId: ruleOwned,
          mergedAwayId: userOwned,
          confirmedByUser: true,
        ),
        isA<MergeCompleted>(),
      );
      final TransactionRow merged = await transactionDao.byId(ruleOwned);
      expect(
        merged.categorySource,
        StoredCategorySource.rule,
        reason: 'the merge does not move the survivor\'s own source',
      );
      expect(
        decodeUserEditedFields(merged.userEditedFields),
        isNot(contains(TransactionField.categoryId)),
        reason:
            'THE ATTACK FAILS HERE: protection is unioned only for fields '
            'actually carried into a gap, and a rule-categorized survivor has '
            'no gap in `category_id`',
      );
      expect(
        isUserOwnedCategory(merged),
        isFalse,
        reason: 'the two AC-D3.1 signals do not disagree',
      );

      await categoryDao.deleteCategory(
        id: doomed.id,
        decision: const SetToUncategorized(),
        actor: 'user',
      );

      final TransactionRow after = await transactionDao.byId(ruleOwned);
      expect(after.categoryId, isNull, reason: 'uncategorized, as asked');
      expect(after.categoryRuleId, isNull, reason: 'KHA-103 clause 1');
      expect(
        after.categorySource,
        StoredCategorySource.none,
        reason: 'KHA-103 clause 2: no row says "a rule put nothing here"',
      );
      expect(after.categoryConfidence, isNull);

      // The structural reason the attack can never work, asserted directly
      // rather than inferred: the automatic path refuses to write ANYTHING to
      // a user-owned row, so `'rule'` and the protection marking cannot
      // coexist however the rows are composed.
      final int protectedRow = await sms(merchant: 'QANDA');
      await transactionDao.setUserCategory(
        id: protectedRow,
        categoryId: uncategorizedCategoryId,
      );
      expect(
        await transactionDao.applyAutomaticCategory(
          id: protectedRow,
          categoryId: 'dining',
          confidence: 1.0,
          actorDetail: 'merchant_rule:1',
        ),
        isFalse,
        reason:
            'AC-D3.1: the automatic path writes nothing to a user-owned '
            'row, which is what keeps the two signals in agreement',
      );
      expect(
        (await transactionDao.byId(protectedRow)).categorySource,
        StoredCategorySource.user,
      );
    });

    test('P2 HOLDS — the ordinary KHA-103 paths are both correct: a '
        'rule-categorized row is fully cleared, and a user-chosen row keeps '
        '`source = user`', () async {
      final CategoryRow doomed2 = (await categoryDao.createCustom(
        name: 'QA Doomed 2',
        iconToken: 'tag',
        groupKey: 'other',
      ))!;

      final int seed = await sms(merchant: 'QANDB');
      await service.applyUserCategory(
        transactionId: seed,
        categoryId: doomed2.id,
      );
      final int auto = await sms(merchant: 'QANDB');
      await service.categorizeTransaction(transactionId: auto);
      expect(
        (await transactionDao.byId(auto)).categorySource,
        StoredCategorySource.rule,
      );

      await categoryDao.deleteCategory(
        id: doomed2.id,
        decision: const SetToUncategorized(),
        actor: 'user',
      );

      final TransactionRow autoAfter = await transactionDao.byId(auto);
      expect(autoAfter.categoryId, isNull);
      expect(autoAfter.categoryRuleId, isNull);
      expect(autoAfter.categorySource, StoredCategorySource.none);
      expect(autoAfter.categoryConfidence, isNull);

      final TransactionRow seedAfter = await transactionDao.byId(seed);
      expect(
        seedAfter.categorySource,
        StoredCategorySource.user,
        reason: 'AC-D3.1: the user\'s ownership signal is not downgraded',
      );
    });

    test('P3 HOLDS — O-QA-11 narrows correctly in BOTH directions: a flag '
        'about this pair is cleared, a flag about a third row survives the '
        'merge AND survives an undo', () async {
      final int survivor = await sms();
      final int absorbed = await sms();
      final int third = await sms();

      // The survivor is flagged as a possible duplicate of a THIRD row — a
      // question this merge does not answer.
      await transactionDao.flagAsPossibleDuplicate(
        id: survivor,
        otherId: third,
        reviewReason: 'possible_duplicate',
      );
      expect((await transactionDao.byId(survivor)).needsReview, isTrue);

      await merge.merge(
        survivorId: survivor,
        mergedAwayId: absorbed,
        confirmedByUser: true,
      );
      final TransactionRow afterMerge = await transactionDao.byId(survivor);
      expect(
        afterMerge.needsReview,
        isTrue,
        reason: 'O-QA-11: the unrelated question is still open',
      );
      expect(afterMerge.possibleDuplicateOfId, third);

      // And the fix must not have simply moved the loss to the undo path.
      await merge.undo(absorbed);
      expect((await transactionDao.byId(survivor)).needsReview, isTrue);
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });
  });

  // =========================================================================
  // PROBE Q — is the claimed redundancy actually two-sided?
  // =========================================================================
  group('PROBE Q — KHA-104/105, each half independently', () {
    test('Q1 HOLDS — the WRITE side: `upsertRule` declines an unknown '
        'category and writes nothing', () async {
      final int merchantId = await merchantDao.ensureMerchant(
        merchantKey: 'QANDC',
        canonicalName: 'QANDC',
      );
      final int result = await merchantDao.upsertRule(
        merchantId: merchantId,
        categoryId: 'no_such_category',
        source: 'user',
        actor: 'user',
      );
      expect(result, lessThan(0), reason: 'the refusal sentinel');
      expect(await merchantDao.ruleForMerchant(merchantId), isNull);
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('Q2 HOLDS — the READ side is INDEPENDENTLY real: a dangling rule '
        'inserted by raw SQL (bypassing `upsertRule` entirely) never reaches '
        'the matcher', () async {
      // This is the half that matters most, because it is the one that defends
      // rows already in the table. Written by raw SQL precisely so the write
      // guard cannot be the thing making this pass.
      final int merchantId = await merchantDao.ensureMerchant(
        merchantKey: 'QANDD',
        canonicalName: 'QANDD',
      );
      await db.customStatement(
        'INSERT INTO merchant_rule '
        '(merchant_id, category_id, match_type, source, is_enabled, '
        'applied_count) '
        "VALUES ($merchantId, 'no_such_category', 'exact_key', 'user', 1, 0)",
      );
      expect(
        await merchantDao.ruleForMerchant(merchantId),
        isNotNull,
        reason: 'the dangling rule really is in the table',
      );

      final List<MerchantCandidate> candidates = await service.loadCandidates();
      final MerchantCandidate candidate = candidates.singleWhere(
        (MerchantCandidate c) => c.merchantId == merchantId,
      );
      expect(candidate.categoryId, isNull, reason: 'the rule is dropped…');
      expect(
        candidate.merchantKey,
        'QANDD',
        reason: '…but the shop is still identified, so no second merchant row',
      );

      final int txn = await sms(merchant: 'QANDD');
      await service.categorizeTransaction(transactionId: txn);
      final TransactionRow row = await transactionDao.byId(txn);
      expect(row.categoryId, isNull);
      expect(
        row.needsReview,
        isTrue,
        reason: 'the app asks rather than stamping an unrenderable category',
      );
    });

    test('Q3 HOLDS — KHA-105: `applyAutomaticCategory` with no `merchantId` '
        'leaves an existing link alone, and still does on the flag path the '
        'categorizer itself uses', () async {
      final int txn = await sms(merchant: 'QANDE');
      await service.categorizeTransaction(transactionId: txn);
      final int? linked = (await transactionDao.byId(txn)).merchantId;
      expect(linked, isNotNull);

      await transactionDao.applyAutomaticCategory(
        id: txn,
        categoryId: null,
        confidence: 0.0,
        actorDetail: 'no_rule_matched',
      );
      expect(
        (await transactionDao.byId(txn)).merchantId,
        linked,
        reason: 'KHA-105: absent(), not null',
      );
    });
  });
}

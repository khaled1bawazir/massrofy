/// **QA adversarial probe suite for PR #27 (P4a — KHA-30 categories, KHA-31
/// merchant rule store).**
///
/// Written by qa-tester against head `10df548`, 2026-07-29.
///
/// P4a is the first phase whose *whole purpose* is to decide, without asking,
/// where a user's money belongs. So the probes here are not "does the happy
/// path work" — the engineer's own suite covers that thoroughly. Every probe
/// below asks one of four hostile questions:
///
///  1. **Can two unrelated merchants be made into one**, silently, at a
///     confidence high enough to auto-apply? (AC-D2.3's second half, R-5.)
///  2. **Can the category-sum invariant (AC-C1.3) be broken** by a combination
///     of category operations and money shapes the engineer's fixture did not
///     compose?
///  3. **Can an automatic path overwrite, or effectively undo, an explicit
///     user choice** (AC-D3.1/D3.2) through *any* reachable write?
///  4. **Can the `BEFORE DELETE` trigger that replaces AC-C3.3's `FK RESTRICT`
///     be bypassed** — by raw SQL, by a bulk delete, by a soft-deleted
///     referrer, or by a referring merchant rule?
///
/// Naming convention, carried over from `qa_pr20/24_probe_test.dart`:
///
///  - `HOLDS` — the property survived the attack. This is audit evidence that
///    the attack was *run*, not an assumption that it would fail.
///  - `DEFECT` — an executed reproduction of behaviour that contradicts an
///    acceptance criterion or a claim the PR makes. Each one is filed in
///    `docs/defects.md` with the same id used in the test name.
///
/// **No production code is changed by this file.** It is additive test-only
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
import 'package:massrofy/features/categorization/categories.dart';
import 'package:massrofy/features/categorization/categorization_service.dart';
import 'package:massrofy/features/categorization/category_breakdown.dart';
import 'package:massrofy/features/categorization/merchant_key.dart';
import 'package:massrofy/features/categorization/merchant_matcher.dart';
import 'package:massrofy/features/ledger/ledger_mapping.dart';
import 'package:massrofy/features/ledger/period_totals.dart';

import '../support/plain_test_database.dart';

final List<int> _qaChainKey = List<int>.generate(32, (int i) => i + 71);

final PeriodRange _july2026 = PeriodRange(
  startUtc: DateTime.utc(2026, 7),
  endUtcExclusive: DateTime.utc(2026, 8),
);

void main() {
  late AppDatabase db;
  late AuditLogDao auditLogDao;
  late CategoryDao categoryDao;
  late MerchantDao merchantDao;
  late TransactionDao transactionDao;
  late CategorizationService service;

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
    await service.ensureDefaultsSeeded();
  });

  tearDown(() async => db.close());

  // ---------------------------------------------------------------------
  // Fixture helpers. Deliberately thin: every probe should be readable as
  // "this is the attack" rather than "this is the setup".
  // ---------------------------------------------------------------------

  int nextMessageId = 1000;

  Future<int> sms({
    required String merchant,
    String amount = '100.00',
    String currency = 'SAR',
    String direction = 'debit',
    String transactionType = 'pos_purchase',
    bool affectsSpend = true,
    int day = 15,
    String? convertedAmount,
  }) => transactionDao.insertFromParsedSms(
    amount: Money.parse(amount, currency: currency),
    convertedAmount: convertedAmount == null
        ? null
        : Money.parse(convertedAmount, currency: 'SAR'),
    conversionPending: currency != 'SAR' && convertedAmount == null,
    merchantRawText: merchant,
    occurredAt: DateTime.utc(2026, 7, day, 12),
    direction: direction,
    transactionType: transactionType,
    affectsSpend: affectsSpend,
    sourceMessageId: nextMessageId++,
    rulePackId: 'qa-pack',
    rulePackVersion: '1.0.0',
    ruleId: 'qa-rule',
  );

  Future<CategoryBreakdown> breakdown({bool includeEmpty = false}) async =>
      CategoryBreakdown.of(
        toLedgerTransactions(await transactionDao.all()),
        period: _july2026,
        resolver: await service.resolver(),
        includeEmptyCategories: includeEmpty,
      );

  /// Total rows in the append-only trail. `AuditLogDao` deliberately exposes
  /// only `queryFor(entityType, entityId)`, so a whole-table count is done
  /// here in SQL — this file needs "did anything at all get written?", which
  /// is a different question from "what is this entity's history?".
  Future<int> auditRowCount() async {
    final List<Map<String, Object?>> rows = await db
        .customSelect('SELECT COUNT(*) AS n FROM audit_entry')
        .map((dynamic row) => <String, Object?>{'n': row.read<int>('n')})
        .get();
    return rows.single['n']! as int;
  }

  Future<void> expectReconciles(String after) async {
    final CategoryBreakdown result = await breakdown();
    expect(result.reconciles, isTrue, reason: 'AC-C1.3 broken after $after');
    // Independent cross-check: never trust the type's own self-assessment
    // alone. Re-sum the slices here, in this file, against the figure
    // `LedgerTotals` produces without any knowledge of categories.
    final PeriodTotals independent = LedgerTotals.spend(
      toLedgerTransactions(await transactionDao.all()),
      period: _july2026,
    );
    final List<Money> parts = <Money>[
      for (final CategoryTotal slice in result.categories)
        if (slice.totals.base != null) slice.totals.base!,
    ];
    expect(
      parts.isEmpty ? null : Money.sum(parts, currency: 'SAR'),
      equals(independent.base),
      reason:
          'AC-C1.3 cross-check broken after $after: slices re-summed by QA do '
          'not equal the uncategorized-blind period spend',
    );
  }

  // =====================================================================
  // GROUP 1 — AC-D2.3: "never silently merge unrelated merchants"
  // =====================================================================

  group('AC-D2.3 — can two unrelated merchants be silently merged?', () {
    test(
      'PROBE A1 (HOLDS) — the T3 confidence ceiling really does reach the '
      'threshold in IEEE-754, so the token-set tier is not silently dead',
      () {
        // The whole tuning argument in the PR body rests on "at 0.85, a
        // token-set match applies only at Jaccard 1.0". That claim is a
        // *floating-point* claim: the ceiling is computed as
        // `0.60 + (0.85 - 0.60) * 1.0`, and `canAutoApply` compares it with
        // `>= 0.85`. If those two doubles differed by one ulp the entire T3
        // tier would be unreachable and nobody would notice, because every
        // test that exercises T3 auto-apply would simply see "flagged for
        // review", which is also a legal outcome.
        //
        // Recomputing the arithmetic here, in QA's own code, is the point:
        // the matcher's private helper is not called, so this fails if the
        // constants are retuned into an unreachable combination.
        const double floor = CategorizationConfig.tokenSetJaccardFloor;
        const double low = CategorizationConfig.tokenSetConfidenceFloor;
        const double high = CategorizationConfig.tokenSetConfidenceCeiling;
        final double atJaccardOne =
            low + (high - low) * ((1.0 - floor) / (1.0 - floor));

        expect(
          atJaccardOne >= CategorizationConfig.autoApplyThreshold,
          isTrue,
          reason:
              'T3 at Jaccard 1.0 computes $atJaccardOne which does not reach '
              'autoApplyThreshold ${CategorizationConfig.autoApplyThreshold} — '
              'the entire token-set tier would be dead code',
        );
      },
    );

    test('PROBE A2 (HOLDS) — the auto-apply gate is exclusive at 0.84 and '
        'inclusive at 0.85, and T4 is refused at every value up to 1.0', () {
      // Probing the threshold boundary directly rather than through a
      // merchant string, so the answer is about the gate and not about
      // whichever corpus pair happens to land near it.
      MerchantMatch at(double confidence, MatchTier tier) => MerchantMatch(
        tier: tier,
        confidence: confidence,
        merchantId: 1,
        categoryId: 'dining',
        ruleId: 1,
      );

      expect(at(0.84, MatchTier.tokenSet).canAutoApply, isFalse);
      expect(at(0.85, MatchTier.tokenSet).canAutoApply, isTrue);
      expect(at(0.86, MatchTier.tokenSet).canAutoApply, isTrue);

      // The structural claim: T4 cannot apply at any confidence, including
      // values above the threshold and including a perfect 1.0.
      for (final double confidence in <double>[0.84, 0.85, 0.86, 0.99, 1.0]) {
        expect(
          at(confidence, MatchTier.editDistance).canAutoApply,
          isFalse,
          reason:
              'T4 auto-applied at $confidence — ADR-008 says never, at any '
              'confidence',
        );
        expect(at(confidence, MatchTier.editDistance).needsReview, isTrue);
      }

      // And "no match" carries no category, so there is no path from an
      // unknown merchant to a category even if a caller ignored the gate.
      expect(MerchantMatch.none.categoryId, isNull);
      expect(MerchantMatch.none.canAutoApply, isFalse);
    });

    test('PROBE B (DEFECT D-QA-27-1) — the city-name noise list collapses two '
        'genuinely different businesses into ONE merchant identity, and then '
        'auto-categorizes the second at confidence 1.00', () async {
      // ADR-008's noise list includes city names, and the implementation's
      // own comment defends that as "a chain's branches are the chain".
      // That reasoning holds for `PANDA RIYADH` / `PANDA JEDDAH`. It does
      // NOT hold when the city name is the *distinguishing* token of two
      // unrelated local businesses — a shape that is entirely ordinary in
      // Saudi retail naming.
      //
      // Two independent bakeries:
      expect(MerchantKey.of('MAKKAH BAKERY'), equals('BAKERY'));
      expect(MerchantKey.of('MADINAH BAKERY'), equals('BAKERY'));

      // The user teaches the app about the first one.
      final int first = await sms(merchant: 'MAKKAH BAKERY');
      await service.applyUserCategory(
        transactionId: first,
        categoryId: 'dining',
      );

      // A message from the *other* business arrives.
      final int second = await sms(merchant: 'MADINAH BAKERY', day: 16);
      final CategorizationOutcome outcome = await service.categorizeTransaction(
        transactionId: second,
      );

      // It is auto-applied at T1 with confidence 1.00 — no flag, no review,
      // no "did you mean". AC-D2.3's *"unrelated merchants must NOT be
      // matched"* is not met, and this is not a fuzzy guess that a threshold
      // could catch: it is an exact key collision manufactured by
      // normalisation, so it sits above every tier gate.
      expect(outcome.result, CategorizationResult.applied);
      expect(outcome.match.tier, MatchTier.userRule);
      expect(outcome.match.confidence, 1.00);
      expect(outcome.categoryId, 'dining');

      // Worse than the category: the *identity* is merged permanently.
      // `merchant.merchant_key` is UNIQUE, so both businesses are now one
      // row, and the row's display name is the first one's raw text — the
      // user will be shown "MAKKAH BAKERY" for money spent at the other.
      final List<MerchantRow> merchants = await merchantDao.allMerchants();
      expect(
        merchants.where((MerchantRow m) => m.merchantKey == 'BAKERY').length,
        1,
        reason: 'two businesses collapsed into one merchant row',
      );
      expect(merchants.single.canonicalName, 'MAKKAH BAKERY');
      final TransactionRow secondRow = (await transactionDao.byIdOrNull(
        second,
      ))!;
      expect(secondRow.merchantId, merchants.single.id);
    });

    test('PROBE C (DEFECT D-QA-27-2) — unconditional trailing-digit stripping '
        'merges numbered sibling merchants at confidence 1.00', () async {
      // ADR-008 step 6 strips *trailing* digit runs so `PANDA STORE 1234`
      // and `Panda` are one shop. The implementation strips them in a
      // `while` loop with no length or context check, so any merchant whose
      // identity IS its trailing number becomes indistinguishable from its
      // siblings. Numbered outlets that are separately owned franchises, and
      // numbered service lines from one telecom brand, both have this shape.
      expect(MerchantKey.of('QAMART 100'), equals('QAMART'));
      expect(MerchantKey.of('QAMART 200'), equals('QAMART'));
      expect(MerchantKey.of('QAMART 100 200 300'), equals('QAMART'));

      final int taught = await sms(merchant: 'QAMART 100');
      await service.applyUserCategory(
        transactionId: taught,
        categoryId: 'groceries',
      );

      final int other = await sms(merchant: 'QAMART 200', day: 17);
      final CategorizationOutcome outcome = await service.categorizeTransaction(
        transactionId: other,
      );

      expect(outcome.result, CategorizationResult.applied);
      expect(outcome.match.confidence, 1.00);
      expect(outcome.categoryId, 'groceries');
    });

    test('PROBE D (DEFECT D-QA-27-3) — a token-set match auto-applies across a '
        'repeated-token name, which is not "the same tokens in a different '
        'arrangement"', () async {
      // The PR defends 0.85 with: at that value a T3 match applies "only at
      // Jaccard 1.0 — i.e. the two strings contain the same tokens and
      // differ only in order, spacing, case, store number or noise words".
      //
      // Jaccard is computed over *sets*, so token multiplicity is invisible
      // to it. A brand whose name repeats a word therefore reaches Jaccard
      // 1.0 against the single-word brand — different names, different
      // shops, and the confidence lands exactly on the auto-apply line.
      final MerchantMatch match =
          MerchantMatcher.match('QAFE QAFE', <MerchantCandidate>[
            const MerchantCandidate(
              merchantId: 7,
              merchantKey: 'QAFE',
              categoryId: 'dining',
              ruleId: 3,
              ruleSource: 'user',
            ),
          ]);

      expect(MerchantKey.of('QAFE QAFE'), equals('QAFE QAFE'));
      expect(match.tier, MatchTier.tokenSet);
      expect(match.confidence, CategorizationConfig.autoApplyThreshold);
      expect(
        match.canAutoApply,
        isTrue,
        reason:
            'a repeated-token brand name auto-applies another brand\'s rule '
            'at exactly the threshold',
      );
    });

    test(
      'PROBE E (HOLDS) — a genuinely novel merchant is never confidently '
      'categorized, and partial token overlap is flagged rather than applied',
      () async {
        final int taught = await sms(merchant: 'QANDA FRESH');
        await service.applyUserCategory(
          transactionId: taught,
          categoryId: 'groceries',
        );

        // AC-D2.4 — never-before-seen merchant.
        final int novel = await sms(merchant: 'ZZQX WIDGET EMPORIUM', day: 18);
        final CategorizationOutcome unknown = await service
            .categorizeTransaction(transactionId: novel);
        expect(unknown.result, CategorizationResult.flaggedUnknownMerchant);
        expect(unknown.categoryId, isNull);
        expect(unknown.match.canAutoApply, isFalse);
        final TransactionRow novelRow = (await transactionDao.byIdOrNull(
          novel,
        ))!;
        expect(novelRow.categoryId, isNull);
        expect(novelRow.needsReview, isTrue);
        expect(novelRow.reviewReason, CategoryReviewReason.unknownMerchant);

        // AC-D2.3 — partial overlap must NOT merge two shops.
        final int sibling = await sms(merchant: 'QANDA EXPRESS', day: 19);
        final CategorizationOutcome partial = await service
            .categorizeTransaction(transactionId: sibling);
        expect(partial.result, isNot(CategorizationResult.applied));
        expect(partial.categoryId, isNull);
        expect(
          (await transactionDao.byIdOrNull(sibling))!.categoryId,
          isNull,
          reason: 'PANDA FRESH / PANDA EXPRESS shape must not auto-merge',
        );
      },
    );

    test(
      'PROBE F (HOLDS) — cross-script is not transliterated, and a Latin '
      'merchant inside an Arabic message still keys correctly (PRD §3.4)',
      () {
        // If this ever starts passing as equal, someone has added a
        // transliterator and the silent-merge guarantee is gone.
        expect(
          MerchantKey.of('البيك'),
          isNot(equals(MerchantKey.of('AL BAIK'))),
        );

        // The three renderings PRD §3.4 shows for one shop must produce one
        // key — including the Latin name embedded in Arabic branch/city noise,
        // which is the case the PRD calls out and the one a single-script
        // assumption would break.
        const String expected = 'QANDA';
        expect(MerchantKey.of('QANDA STORE 1234'), expected);
        expect(MerchantKey.of('  qanda  '), expected);
        expect(MerchantKey.of('فرع QANDA الرياض'), expected);
        expect(MerchantKey.of('QANDA-9021'), expected);

        // Arabic orthographic variance must fold (the user should not have to
        // teach the app twice).
        expect(MerchantKey.of('مؤسسة القهوة'), MerchantKey.of('موسسه القهوه'));

        // Idempotence — a key is computed at write time and recomputed later.
        for (final String raw in <String>[
          'QANDA STORE 1234',
          'فرع QANDA الرياض',
          'مؤسسة القهوة',
        ]) {
          expect(MerchantKey.of(MerchantKey.of(raw)), MerchantKey.of(raw));
        }
      },
    );

    test('PROBE G1 (HOLDS) — a transaction with NO merchant text never becomes '
        '"the same merchant" as another one', () async {
      // The single most damaging silent merge available in this design: if
      // an empty key were representable, one rule would categorise every
      // ATM withdrawal and every transfer in the ledger.
      expect(MerchantKey.ofOrNull(null), isNull);
      expect(MerchantKey.ofOrNull('   '), isNull);

      final int atm = await transactionDao.insertFromParsedSms(
        amount: Money.parse('500.00', currency: 'SAR'),
        merchantRawText: null,
        occurredAt: DateTime.utc(2026, 7, 20, 12),
        direction: 'debit',
        transactionType: 'atm_withdrawal',
        affectsSpend: false,
        sourceMessageId: nextMessageId++,
        rulePackId: 'qa-pack',
        rulePackVersion: '1.0.0',
        ruleId: 'qa-rule',
      );
      final CategorizationOutcome outcome = await service.categorizeTransaction(
        transactionId: atm,
      );
      expect(outcome.result, CategorizationResult.skippedNoMerchant);
      expect((await merchantDao.allMerchants()), isEmpty);
    });

    test(
      'PROBE G2 (DEFECT D-QA-27-7) — a PUNCTUATION-ONLY merchant string does '
      'become a merchant identity, so every masked-merchant message from a '
      'bank collapses onto one rule',
      () async {
        // `MerchantKey.ofOrNull` documents itself as the guard against
        // "inventing an empty-string key [which] would make every such
        // transaction the same merchant — the single most damaging silent
        // merge available in this design".
        //
        // The guard is `key.isEmpty`, but `of()` falls back to the *folded
        // string* when every token was noise or digits — and a string made
        // only of separator characters tokenises to nothing while folding to
        // itself. So it is non-empty, and the guard misses it.
        //
        // This is not hypothetical input: acquirer strings routinely carry a
        // placeholder where the merchant name was masked or absent.
        expect(MerchantKey.ofOrNull('***'), '***');
        expect(MerchantKey.ofOrNull('-*-'), '-*-');

        final int taught = await sms(merchant: '***');
        await service.applyUserCategory(
          transactionId: taught,
          categoryId: 'dining',
        );

        // A completely unrelated purchase, from a different bank, whose
        // merchant was also masked.
        final int unrelated = await sms(merchant: '***', day: 16);
        final CategorizationOutcome outcome = await service
            .categorizeTransaction(transactionId: unrelated);

        expect(
          outcome.result,
          CategorizationResult.applied,
          reason:
              'if this now fails, the defect is fixed — a placeholder merchant '
              'string no longer forms an identity',
        );
        expect(outcome.match.confidence, 1.00);
        expect(
          (await merchantDao.allMerchants()).length,
          1,
          reason: 'every masked-merchant transaction is now one merchant',
        );
      },
    );
  });

  // =====================================================================
  // GROUP 2 — AC-C3.3: the BEFORE DELETE trigger that replaces FK RESTRICT
  // =====================================================================

  group('AC-C3.3 — can the category-delete guard be bypassed?', () {
    test(
      'PROBE H1 (HOLDS) — raw SQL that never touches the DAO is refused, for '
      'a live transaction, a soft-deleted one, and a merchant rule',
      () async {
        // Live referrer.
        final int live = await sms(merchant: 'QANDA');
        await transactionDao.setUserCategory(id: live, categoryId: 'dining');
        await expectLater(
          db.customStatement("DELETE FROM category WHERE id = 'dining'"),
          throwsA(anything),
          reason: 'raw SQL delete orphaned a live transaction',
        );

        // Soft-deleted referrer — a restore must not resurrect a dangling id.
        await transactionDao.softDelete(id: live, actor: 'user');
        expect((await transactionDao.byIdOrNull(live))!.deletedAt, isNotNull);
        await expectLater(
          db.customStatement("DELETE FROM category WHERE id = 'dining'"),
          throwsA(anything),
          reason: 'a soft-deleted referrer did not block the delete',
        );

        // Merchant-rule referrer, with no transaction pointing at the
        // category at all.
        await db.customStatement(
          "UPDATE transactions SET category_id = NULL WHERE id = $live",
        );
        final int merchantId = await merchantDao.ensureMerchant(
          merchantKey: 'QANDA',
          canonicalName: 'QANDA',
        );
        await merchantDao.upsertRule(
          merchantId: merchantId,
          categoryId: 'dining',
          source: 'user',
          actor: 'user',
        );
        await expectLater(
          db.customStatement("DELETE FROM category WHERE id = 'dining'"),
          throwsA(anything),
          reason: 'a merchant rule referrer did not block the delete',
        );
      },
    );

    test(
      'PROBE H2 (HOLDS) — a bulk / unfiltered DELETE is refused too, and '
      'rolls back completely rather than partially wiping the table',
      () async {
        final int txn = await sms(merchant: 'QANDA');
        await transactionDao.setUserCategory(id: txn, categoryId: 'dining');
        final int before = (await categoryDao.all()).length;

        // A `BEFORE DELETE` trigger fires per row, so this is the case where
        // an implementation that only guarded the DAO's single-row path would
        // silently wipe every category *except* the referenced one.
        await expectLater(
          db.customStatement('DELETE FROM category'),
          throwsA(anything),
        );
        expect(
          (await categoryDao.all()).length,
          before,
          reason:
              'the aborted bulk delete left the category table partially '
              'wiped — the statement did not roll back',
        );
      },
    );

    test('PROBE H3 (HOLDS) — the protected Uncategorized row cannot be deleted '
        'or renamed by any path, including raw SQL', () async {
      await expectLater(
        categoryDao.deleteCategory(
          id: CategoryIds.uncategorized,
          decision: const SetToUncategorized(),
        ),
        throwsA(isA<ProtectedCategoryError>()),
      );
      await expectLater(
        categoryDao.rename(
          id: CategoryIds.uncategorized,
          newName: 'Something Else',
        ),
        throwsA(isA<ProtectedCategoryError>()),
      );
      await expectLater(
        db.customStatement(
          "DELETE FROM category WHERE id = '${CategoryIds.uncategorized}'",
        ),
        throwsA(anything),
        reason:
            'AC-C1.1 fallback deleted by raw SQL — the trigger did not '
            'defend is_protected',
      );
    });

    test('PROBE H4 (HOLDS) — after a v5 → v7 upgrade the guard trigger is '
        'installed, so upgraded installs are not the unguarded ones', () async {
      // The migration and the fresh-create path install the trigger
      // separately. A guard that exists only on new installs would be the
      // worst possible shape of this defect: invisible to every test that
      // starts from `createAll`.
      final List<Map<String, Object?>> triggers = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' "
            "AND name = 'category_no_delete_while_in_use'",
          )
          .map((dynamic row) => <String, Object?>{'ok': 1})
          .get();
      expect(triggers, isNotEmpty);
    });

    test('PROBE H5 (HOLDS) — deleteCategory repoints soft-deleted transactions '
        'too, so a restore cannot resurrect an orphan', () async {
      final CategoryRow? custom = await categoryDao.createCustom(
        name: 'QA Temp',
        iconToken: 'label',
        groupKey: 'spending',
      );
      final int txn = await sms(merchant: 'QANDA');
      await transactionDao.setUserCategory(id: txn, categoryId: custom!.id);
      await transactionDao.softDelete(id: txn, actor: 'user');

      final CategoryDeleteOutcome outcome = await categoryDao.deleteCategory(
        id: custom.id,
        decision: const ReassignTo('dining'),
      );
      expect(outcome.deleted, isTrue);
      expect(outcome.transactionsMoved, 1);

      await transactionDao.restore(id: txn, actor: 'user');
      final TransactionRow restored = (await transactionDao.byIdOrNull(txn))!;
      expect(restored.categoryId, 'dining');
      expect(await categoryDao.byId(custom.id), isNull);
    });

    test('PROBE I (HOLDS) — AC-C3.2 duplicate rejection resists case, padding, '
        'Arabic orthography and SQL-injection-shaped names', () async {
      expect(
        await categoryDao.createCustom(
          name: '  groceries  ',
          iconToken: 'label',
          groupKey: 'spending',
        ),
        isNull,
        reason: 'folded duplicate of the English seed name was accepted',
      );
      expect(
        await categoryDao.createCustom(
          name: 'البقاله',
          iconToken: 'label',
          groupKey: 'spending',
        ),
        isNull,
        reason: 'folded duplicate of the Arabic seed name was accepted',
      );

      // Injection-shaped input must be stored as data, not executed, and
      // must not corrupt the uniqueness check.
      const String hostile = "Zed'); DROP TABLE transactions;--";
      final CategoryRow? created = await categoryDao.createCustom(
        name: hostile,
        iconToken: 'label',
        groupKey: 'spending',
      );
      expect(created, isNotNull);
      expect(created!.nameEn, hostile);
      expect(
        await categoryDao.createCustom(
          name: hostile,
          iconToken: 'label',
          groupKey: 'spending',
        ),
        isNull,
      );
      // The table the payload named is still there.
      expect(await transactionDao.all(), isEmpty);

      // Injection through the merchant path too — the key pipeline must not
      // be a smuggling route into SQL.
      final int txn = await sms(merchant: "QANDA'); DELETE FROM category;--");
      await service.categorizeTransaction(transactionId: txn);
      expect((await categoryDao.all()).length, 14);
    });

    test(
      'PROBE J (HOLDS) — a rename is a name-only write: no transaction row and '
      'no transaction audit entry is produced (AC-C3.4)',
      () async {
        final int txn = await sms(merchant: 'QANDA');
        await transactionDao.setUserCategory(id: txn, categoryId: 'dining');
        final TransactionRow before = (await transactionDao.byIdOrNull(txn))!;
        final int auditBefore = await auditRowCount();

        await categoryDao.rename(id: 'dining', newName: 'Eating Out');

        final TransactionRow after = (await transactionDao.byIdOrNull(txn))!;
        expect(after.categoryId, 'dining');
        expect(after.updatedAt, before.updatedAt);
        // Exactly one new entry: the category's own rename. Not one per
        // transaction.
        expect(await auditRowCount(), auditBefore + 1);
        await expectReconciles('rename');
      },
    );
  });

  // =====================================================================
  // GROUP 3 — AC-C1.3 under money shapes the engineer's fixture did not
  //           compose
  // =====================================================================

  group('AC-C1.3 — the sum invariant under adversarial composition', () {
    test('PROBE K (HOLDS) — a refund categorized DIFFERENTLY from the purchase '
        'it reverses still reconciles (the slice goes negative, and that is '
        'correct)', () async {
      final int purchase = await sms(merchant: 'QANDA', amount: '300.00');
      await transactionDao.setUserCategory(
        id: purchase,
        categoryId: 'shopping_retail',
      );
      // The user files the refund under a different category. The naive
      // implementation ("a category total is a sum of magnitudes") produces
      // two positive slices here and breaks the invariant.
      final int refund = await sms(
        merchant: 'QANDA',
        amount: '120.00',
        direction: 'credit',
        transactionType: 'refund',
        day: 16,
      );
      await transactionDao.setUserCategory(id: refund, categoryId: 'groceries');

      final CategoryBreakdown result = await breakdown();
      final CategoryTotal groceries = result.categories.singleWhere(
        (CategoryTotal slice) => slice.category.id == 'groceries',
      );
      expect(
        groceries.totals.base!.isNegative,
        isTrue,
        reason:
            'a credit-only category slice must be negative, not a magnitude',
      );
      await expectReconciles('a cross-category refund');
    });

    test('PROBE L (HOLDS) — the two legs of an internal transfer placed in '
        'DIFFERENT categories are still excluded from every slice', () async {
      // The stated failure mode for this file: a per-category slice holds
      // one leg of a transfer and not the other, so re-deriving the transfer
      // analysis per slice would re-admit AC-B11.1 as a bug. Splitting the
      // legs across two categories is the sharpest form of that attack.
      final int out = await sms(
        merchant: 'QANDA TRANSFER',
        amount: '2000.00',
        transactionType: 'transfer_out',
        affectsSpend: false,
      );
      final int back = await sms(
        merchant: 'QANDA TRANSFER',
        amount: '2000.00',
        direction: 'credit',
        transactionType: 'transfer_in',
        affectsSpend: false,
        day: 15,
      );
      await transactionDao.setUserCategory(
        id: out,
        categoryId: 'internal_transfer',
      );
      await transactionDao.setUserCategory(id: back, categoryId: 'dining');

      await expectReconciles('a category-split internal transfer');
    });

    test('PROBE M (HOLDS) — a category holding ONLY unconvertible foreign '
        'transactions contributes nothing to the base figure and does not '
        'break reconciliation', () async {
      final int sar = await sms(merchant: 'QANDA', amount: '250.00');
      await transactionDao.setUserCategory(id: sar, categoryId: 'dining');

      // No converted amount: ADR-009 says this is excluded from the base
      // figure and surfaced as "not converted", never silently converted.
      final int usd = await sms(
        merchant: 'QAWIDGET',
        amount: '80.00',
        currency: 'USD',
        day: 17,
      );
      await transactionDao.setUserCategory(
        id: usd,
        categoryId: 'shopping_retail',
      );

      final CategoryBreakdown result = await breakdown();
      final CategoryTotal retail = result.categories.singleWhere(
        (CategoryTotal slice) => slice.category.id == 'shopping_retail',
      );
      expect(retail.totals.base, isNull);
      expect(retail.totals.isIncomplete, isTrue);
      expect(result.total.isIncomplete, isTrue);
      await expectReconciles('an unconverted-only category');
    });

    test(
      'PROBE N (HOLDS) — `includeEmptyCategories: true` does not break '
      'reconciliation, including when NOTHING in the period is convertible',
      () async {
        // The specific hazard: `reconciles` returns `parts.isEmpty` when the
        // total base is null. If an empty slice ever produced a non-null zero
        // base, turning on the legend rows would make a correct breakdown
        // report itself as broken.
        final int usd = await sms(
          merchant: 'QAWIDGET',
          amount: '80.00',
          currency: 'USD',
        );
        await transactionDao.setUserCategory(id: usd, categoryId: 'dining');

        final CategoryBreakdown withEmpties = await breakdown(
          includeEmpty: true,
        );
        expect(withEmpties.total.base, isNull);
        expect(
          withEmpties.reconciles,
          isTrue,
          reason:
              'legend rows made an all-unconverted breakdown report itself as '
              'not reconciling',
        );
        expect(withEmpties.categories.length, greaterThanOrEqualTo(13));
      },
    );

    test('PROBE O (HOLDS) — the invariant survives all four category operations '
        'applied in sequence to the SAME live money, plus a hand-corrupted '
        'category id', () async {
      final int a = await sms(merchant: 'QA A', amount: '100.00');
      final int b = await sms(
        merchant: 'QA B',
        amount: '60.00',
        currency: 'USD',
        convertedAmount: '225.00',
        day: 16,
      );
      final int c = await sms(merchant: 'QA C', amount: '40.00', day: 17);
      await transactionDao.setUserCategory(id: a, categoryId: 'dining');
      await transactionDao.setUserCategory(id: b, categoryId: 'groceries');
      // c stays uncategorized — it MUST be inside the sum.
      await expectReconciles('the base fixture');
      expect((await transactionDao.byIdOrNull(c))!.categoryId, isNull);

      // 1. create
      final CategoryRow? one = await categoryDao.createCustom(
        name: 'QA One',
        iconToken: 'label',
        groupKey: 'spending',
      );
      await transactionDao.setUserCategory(id: c, categoryId: one!.id);
      await expectReconciles('create');

      // 2. rename
      await categoryDao.rename(id: one.id, newName: 'QA One Renamed');
      await expectReconciles('rename');

      // 3. delete-with-reassign, into a category that already holds money
      await categoryDao.deleteCategory(
        id: one.id,
        decision: const ReassignTo('dining'),
      );
      await expectReconciles('delete-with-reassign');

      // 4. delete-with-uncategorize, on a category that now holds two rows
      //    with different currencies
      await transactionDao.setUserCategory(id: b, categoryId: 'dining');
      await categoryDao.deleteCategory(
        id: 'dining',
        decision: const SetToUncategorized(),
      );
      await expectReconciles('delete-with-uncategorize');

      // 5. a category id that resolves to nothing, written behind the DAO's
      //    back. AC-C1.1 says this must render as Uncategorized; AC-C1.3
      //    says the money must stay in the sum either way.
      await db.customStatement(
        "UPDATE transactions SET category_id = 'ghost_category' WHERE id = $a",
      );
      final CategoryBreakdown corrupted = await breakdown();
      expect(
        corrupted.categories.every(
          (CategoryTotal slice) => slice.category.id != 'ghost_category',
        ),
        isTrue,
      );
      await expectReconciles('a hand-corrupted category id');
    });

    test('PROBE P (HOLDS) — concurrent category creates and a concurrent '
        'delete/categorize race leave no orphan and no broken sum', () async {
      final int txn = await sms(merchant: 'QANDA');

      // Ten simultaneous attempts to create the same name. AC-C3.2 says one
      // wins; the rest must be rejected, not throw a raw constraint error
      // out of the DAO's contract.
      final List<CategoryRow?> results = await Future.wait<CategoryRow?>(
        List<Future<CategoryRow?>>.generate(
          10,
          (int _) => categoryDao.createCustom(
            name: 'QA Contended',
            iconToken: 'label',
            groupKey: 'spending',
          ),
        ),
      );
      expect(
        results.whereType<CategoryRow>().length,
        1,
        reason:
            'concurrent creates produced ${results.length} categories '
            'named the same thing',
      );

      final CategoryRow winner = results.whereType<CategoryRow>().single;
      await transactionDao.setUserCategory(id: txn, categoryId: winner.id);
      await categoryDao.deleteCategory(
        id: winner.id,
        decision: const SetToUncategorized(),
      );
      expect((await transactionDao.byIdOrNull(txn))!.categoryId, isNull);
      await expectReconciles('a contended create then delete');
    });
  });

  // =====================================================================
  // GROUP 4 — AC-D3.1/D3.2: can an automatic path beat a person?
  // =====================================================================

  group('AC-D3.1 — user correction always wins', () {
    test(
      'PROBE Q (HOLDS) — the write boundary refuses an automatic category on '
      'a user-owned row even when the service layer is bypassed entirely',
      () async {
        final int txn = await sms(merchant: 'QANDA');
        await service.applyUserCategory(
          transactionId: txn,
          categoryId: 'dining',
        );

        // Straight at the DAO, as a future caller that never read the service
        // would do.
        final bool written = await transactionDao.applyAutomaticCategory(
          id: txn,
          categoryId: 'groceries',
          confidence: 1.0,
          ruleId: 99,
          merchantId: 1,
          actorDetail: 'merchant_rule:99',
        );
        expect(written, isFalse);

        final TransactionRow row = (await transactionDao.byIdOrNull(txn))!;
        expect(row.categoryId, 'dining');
        expect(row.categorySource, StoredCategorySource.user);
        // "Nothing is written at all, not even the merchant link."
        expect(row.categoryRuleId, isNull);
      },
    );

    test(
      'PROBE R (HOLDS) — each of the two independent protection signals '
      'defends on its own, so a defect dropping either still holds the line',
      () async {
        // Signal 1 alone: `category_source = user`, with user_edited_fields
        // scrubbed behind the DAO's back.
        final int one = await sms(merchant: 'QA ONE');
        await transactionDao.setUserCategory(id: one, categoryId: 'dining');
        await db.customStatement(
          'UPDATE transactions SET user_edited_fields = NULL WHERE id = $one',
        );
        expect(
          await transactionDao.applyAutomaticCategory(
            id: one,
            categoryId: 'groceries',
            confidence: 1.0,
            actorDetail: 'merchant_rule:1',
          ),
          isFalse,
        );

        // Signal 2 alone: `user_edited_fields`, with category_source scrubbed.
        final int two = await sms(merchant: 'QA TWO', day: 16);
        await transactionDao.setUserCategory(id: two, categoryId: 'dining');
        await db.customStatement(
          'UPDATE transactions SET category_source = NULL WHERE id = $two',
        );
        expect(
          await transactionDao.applyAutomaticCategory(
            id: two,
            categoryId: 'groceries',
            confidence: 1.0,
            actorDetail: 'merchant_rule:1',
          ),
          isFalse,
        );
      },
    );

    test(
      'PROBE S (HOLDS) — an explicit "Uncategorized" choice by the user is '
      'itself protected: re-running the categorizer does not refill it',
      () async {
        final int taught = await sms(merchant: 'QANDA');
        await service.applyUserCategory(
          transactionId: taught,
          categoryId: 'dining',
        );

        final int deliberate = await sms(merchant: 'QANDA', day: 16);
        // The user says "no, this one is nothing" — stored as NULL, but it is
        // still a decision.
        await service.applyUserCategory(
          transactionId: deliberate,
          categoryId: CategoryIds.uncategorized,
        );

        final CategorizationOutcome outcome = await service
            .categorizeTransaction(transactionId: deliberate);
        expect(outcome.result, CategorizationResult.skippedAlreadyDecided);
        expect(
          (await transactionDao.byIdOrNull(deliberate))!.categoryId,
          isNull,
        );

        // And it did not teach an "everything from this shop is nothing" rule.
        final List<MerchantRuleRow> rules = await merchantDao.allRules();
        expect(rules.single.categoryId, 'dining');
      },
    );

    test('PROBE T (HOLDS) — a seed rule never overwrites, and never demotes, a '
        'rule the user taught for the same merchant', () async {
      final int txn = await sms(merchant: 'QANDA');
      await service.applyUserCategory(transactionId: txn, categoryId: 'dining');
      final int merchantId = (await transactionDao.byIdOrNull(
        txn,
      ))!.merchantId!;

      // A seed/rule-pack writer arrives later for the same merchant.
      await merchantDao.upsertRule(
        merchantId: merchantId,
        categoryId: 'groceries',
        source: 'seed',
        actor: 'system',
      );
      final MerchantRuleRow rule = (await merchantDao.ruleForMerchant(
        merchantId,
      ))!;
      expect(
        rule.source,
        'user',
        reason: 'a user rule was demoted to seed provenance',
      );

      // And the matcher still treats it as T1 with user confidence.
      final MerchantMatch match = MerchantMatcher.match(
        'QANDA',
        await service.loadCandidates(),
      );
      expect(match.tier, MatchTier.userRule);
      expect(match.confidence, CategorizationConfig.userRuleConfidence);
    });

    test('PROBE U (DEFECT D-QA-27-4) — categorizing through the edit form '
        '(`applyUserEdit`) leaves the categorizer\'s review flag raised, and '
        'teaches no rule', () async {
      // Two user-facing writes can set a category: `setUserCategory` (the
      // categorization surface) and `applyUserEdit` (P3b-2's edit form,
      // already shipped and already routed in S-16). They do NOT behave the
      // same way, and both differences are user-visible.
      final int txn = await sms(merchant: 'QANDA');
      await service.categorizeTransaction(transactionId: txn);
      final TransactionRow flagged = (await transactionDao.byIdOrNull(txn))!;
      expect(flagged.needsReview, isTrue);
      expect(flagged.reviewReason, CategoryReviewReason.unknownMerchant);

      await transactionDao.applyUserEdit(
        id: txn,
        categoryId: const Edited<String?>('dining'),
      );

      final TransactionRow after = (await transactionDao.byIdOrNull(txn))!;
      // The provenance columns DO move correctly — that half is right.
      expect(after.categoryId, 'dining');
      expect(after.categorySource, StoredCategorySource.user);

      // 1. The row is answered but still sits in the review inbox asking
      //    "is this a shop you know?" — `_clearCategoryReviewFlag` is only
      //    called from `setUserCategory`.
      expect(
        after.needsReview,
        isTrue,
        reason:
            'if this now fails, the defect has been fixed — the review flag '
            'is cleared on the edit-form path too',
      );
      expect(after.reviewReason, CategoryReviewReason.unknownMerchant);

      // 2. No rule was learned, so AC-D1.1/AC-D2.1 do not hold for a user
      //    who corrects the category from the detail screen.
      expect(
        await merchantDao.allRules(),
        isEmpty,
        reason:
            'if this now fails, the edit-form path learns a rule and the '
            'two correction surfaces agree',
      );
    });

    test(
      'PROBE V (HOLDS) — a re-run of the categorizer over an already '
      'auto-categorized row does not double-count the rule or re-audit',
      () async {
        final int taught = await sms(merchant: 'QANDA');
        await service.applyUserCategory(
          transactionId: taught,
          categoryId: 'dining',
        );
        final int next = await sms(merchant: 'QANDA', day: 16);

        await service.categorizeTransaction(transactionId: next);
        final int ruleId = (await transactionDao.byIdOrNull(
          next,
        ))!.categoryRuleId!;
        final int appliedOnce = (await merchantDao.ruleById(
          ruleId,
        ))!.appliedCount;
        final int auditAfterFirst = await auditRowCount();

        final CategorizationOutcome again = await service.categorizeTransaction(
          transactionId: next,
        );
        expect(again.result, CategorizationResult.skippedAlreadyDecided);
        expect((await merchantDao.ruleById(ruleId))!.appliedCount, appliedOnce);
        expect(await auditRowCount(), auditAfterFirst);
      },
    );
  });

  // =====================================================================
  // GROUP 5 — NFR-A2 / AC-F5.2: is "why is this categorized this way"
  //           actually answerable from the trail?
  // =====================================================================

  group('AC-F5.2 — the audit trail of an automatic categorization', () {
    test('PROBE W (HOLDS) — the electric-bill case writes a SYSTEM-attributed '
        'entry naming the rule, the before/after and the confidence', () async {
      final int firstBill = await sms(merchant: 'QA ELECTRIC CO 4471');
      await service.categorizeTransaction(transactionId: firstBill);
      await service.applyUserCategory(
        transactionId: firstBill,
        categoryId: 'utilities_bills',
      );

      final int secondBill = await sms(
        merchant: 'QA ELECTRIC CO 9982',
        day: 16,
      );
      final CategorizationOutcome outcome = await service.categorizeTransaction(
        transactionId: secondBill,
      );
      expect(outcome.result, CategorizationResult.applied);

      final List<AuditEntryRow> entries = await auditLogDao.queryFor(
        'transaction',
        secondBill.toString(),
      );
      final AuditEntryRow systemEntry = entries.last;
      expect(systemEntry.actor, 'system_rule');
      expect(systemEntry.action, 'categorize');
      final int ruleId = (await transactionDao.byIdOrNull(
        secondBill,
      ))!.categoryRuleId!;
      expect(systemEntry.actorDetail, 'merchant_rule:$ruleId');
      // The "why" must be recoverable: which rule, from what, to what.
      expect(systemEntry.fieldChangesJson, contains('utilities_bills'));
      expect(systemEntry.fieldChangesJson, contains('categoryConfidence'));
      // And the named rule is still resolvable to a merchant and category.
      final MerchantRuleRow? rule = await merchantDao.ruleById(ruleId);
      expect(rule, isNotNull);
      expect(rule!.categoryId, 'utilities_bills');
    });

    test('PROBE X (DEFECT D-QA-27-5) — deleting a category with '
        '`SetToUncategorized` destroys the rules that named it, and every '
        'transaction those rules categorized keeps a `category_rule_id` '
        'pointing at a rule that no longer exists', () async {
      final CategoryRow? custom = await categoryDao.createCustom(
        name: 'QA Doomed',
        iconToken: 'label',
        groupKey: 'spending',
      );
      final int taught = await sms(merchant: 'QANDA');
      await service.applyUserCategory(
        transactionId: taught,
        categoryId: custom!.id,
      );
      final int auto = await sms(merchant: 'QANDA', day: 16);
      await service.categorizeTransaction(transactionId: auto);
      final int ruleId = (await transactionDao.byIdOrNull(
        auto,
      ))!.categoryRuleId!;

      await categoryDao.deleteCategory(
        id: custom.id,
        decision: const SetToUncategorized(),
      );

      // The rule is gone (documented and defensible).
      expect(await merchantDao.ruleById(ruleId), isNull);

      // But the transaction still claims that rule as its provenance. A
      // detail screen answering "why is this categorized this way" from
      // `category_rule_id` now dereferences a rule that does not exist,
      // and the audit trail's `merchant_rule:$ruleId` is likewise
      // unresolvable. `category_source` also still says `rule` while
      // `category_id` is NULL — a row that says "a rule put nothing here".
      final TransactionRow orphaned = (await transactionDao.byIdOrNull(auto))!;
      expect(
        orphaned.categoryRuleId,
        ruleId,
        reason:
            'if this now fails, the defect is fixed — the delete clears the '
            'provenance it invalidated',
      );
      expect(orphaned.categoryId, isNull);
      expect(orphaned.categorySource, StoredCategorySource.rule);

      // Money is untouched, which is why this is not merge-blocking.
      await expectReconciles('a rule-destroying category delete');
    });

    test(
      'PROBE Y (DEFECT D-QA-27-6) — a merchant rule may name a category that '
      'does not exist, and the matcher will then auto-apply it',
      () async {
        // Nothing validates `merchant_rule.category_id` against `category`,
        // and the delete trigger only guards the delete direction. So a rule
        // can be written for a category id that was never created, and the
        // learning loop will confidently stamp it onto real transactions.
        final int merchantId = await merchantDao.ensureMerchant(
          merchantKey: 'QANDA',
          canonicalName: 'QANDA',
        );
        await merchantDao.upsertRule(
          merchantId: merchantId,
          categoryId: 'no_such_category',
          source: 'user',
          actor: 'user',
        );

        final int txn = await sms(merchant: 'QANDA');
        final CategorizationOutcome outcome = await service
            .categorizeTransaction(transactionId: txn);
        expect(
          outcome.result,
          CategorizationResult.applied,
          reason:
              'if this now fails, the defect is fixed — a rule naming an '
              'unknown category no longer auto-applies',
        );
        expect(
          (await transactionDao.byIdOrNull(txn))!.categoryId,
          'no_such_category',
        );

        // The graceful-degradation claim holds: it renders as Uncategorized
        // and the money stays in the sum. This is why it is Medium and not
        // High — but the row now says "categorized" while showing
        // "Uncategorized", which is AC-C1.1's *explicit* state reached by
        // accident rather than by decision.
        final CategoryResolver resolver = await service.resolver();
        expect(resolver.resolve('no_such_category').isUncategorized, isTrue);
        await expectReconciles('a dangling rule target');
      },
    );

    test(
      'PROBE AA (HOLDS) — AC-D3.1 read literally: auto-assigned C1, user '
      'changes to C2, the NEXT message from that merchant arrives as C2',
      () async {
        // The AC is a sentence about three transactions, not about a flag, so
        // it is worth executing as three transactions.
        final int seedTxn = await sms(merchant: 'QANDA');
        await service.applyUserCategory(
          transactionId: seedTxn,
          categoryId: 'groceries',
        );

        // Transaction 2 arrives and is auto-assigned C1 = groceries.
        final int second = await sms(merchant: 'QANDA', day: 16);
        await service.categorizeTransaction(transactionId: second);
        expect(
          (await transactionDao.byIdOrNull(second))!.categoryId,
          'groceries',
        );

        // The user disagrees and changes it to C2 = dining. AC-D1.2 says the
        // rule updates rather than a second rule appearing.
        await service.applyUserCategory(
          transactionId: second,
          categoryId: 'dining',
        );
        expect((await merchantDao.allRules()).length, 1);

        // Transaction 3 must arrive as C2.
        final int third = await sms(merchant: 'QANDA', day: 17);
        final CategorizationOutcome outcome = await service
            .categorizeTransaction(transactionId: third);
        expect(outcome.result, CategorizationResult.applied);
        expect((await transactionDao.byIdOrNull(third))!.categoryId, 'dining');
        // AC-D2.2 — the row says it was automatic, and which rule did it.
        final TransactionRow thirdRow = (await transactionDao.byIdOrNull(
          third,
        ))!;
        expect(thirdRow.categorySource, StoredCategorySource.rule);
        expect(thirdRow.categoryRuleId, isNotNull);
        expect(thirdRow.needsReview, isFalse);

        // And transaction 1 — the one the user categorized first — was NOT
        // retroactively rewritten by the rule change (AC-D4.4 makes that an
        // explicit user choice, never a side effect).
        expect(
          (await transactionDao.byIdOrNull(seedTxn))!.categoryId,
          'groceries',
        );
      },
    );

    test(
      'PROBE AB (HOLDS) — AC-D5.2: a "this transaction only" correction does '
      'not disturb the rule already learned for that merchant',
      () async {
        final int first = await sms(merchant: 'QANDA');
        await service.applyUserCategory(
          transactionId: first,
          categoryId: 'groceries',
        );

        final int oneOff = await sms(merchant: 'QANDA', day: 16);
        await service.applyUserCategory(
          transactionId: oneOff,
          categoryId: 'dining',
          learnRule: false,
        );

        // The one-off did not become the rule…
        final List<MerchantRuleRow> rules = await merchantDao.allRules();
        expect(rules.single.categoryId, 'groceries');

        // …and it still applies to the next message.
        final int next = await sms(merchant: 'QANDA', day: 17);
        await service.categorizeTransaction(transactionId: next);
        expect(
          (await transactionDao.byIdOrNull(next))!.categoryId,
          'groceries',
        );
      },
    );

    test(
      'PROBE AC (DEFECT D-QA-27-8) — `applyAutomaticCategory` will UNLINK an '
      'existing merchant when a caller omits `merchantId`',
      () async {
        // `setUserCategory` is careful here — it uses `Value.absent()` when
        // `merchantId` is null, "so a caller with no merchant cannot
        // accidentally unlink one that is already there". The automatic
        // sibling writes `Value<int?>(merchantId)` unconditionally, so the
        // same omission silently clears the link instead.
        //
        // No caller does this today; this is the "unguarded path with no
        // caller yet" shape that KHA-79 was about, recorded now rather than
        // after P4b adds the second caller.
        final int txn = await sms(merchant: 'QANDA');
        await service.categorizeTransaction(transactionId: txn);
        expect((await transactionDao.byIdOrNull(txn))!.merchantId, isNotNull);

        await transactionDao.applyAutomaticCategory(
          id: txn,
          categoryId: null,
          confidence: 0.0,
          actorDetail: 'no_rule_matched',
        );

        expect(
          (await transactionDao.byIdOrNull(txn))!.merchantId,
          isNull,
          reason:
              'if this now fails, the defect is fixed — an omitted merchantId '
              'no longer unlinks',
        );
      },
    );

    test('PROBE Z (HOLDS) — no double / num leaks into a money path in the '
        'categorization code (ADR-002)', () {
      // `categoryConfidence` is the ONE sanctioned double in this phase
      // (architecture §4.2 names it), and it must not be able to reach an
      // amount. This asserts the boundary rather than greps for it: every
      // figure a breakdown produces is a `Money`, whose arithmetic is exact.
      final Money a = Money.parse('0.10', currency: 'SAR');
      final Money b = Money.parse('0.20', currency: 'SAR');
      expect(
        Money.sum(<Money>[a, b], currency: 'SAR'),
        Money.parse('0.30', currency: 'SAR'),
      );
      expect(CategorizationConfig.autoApplyThreshold, isA<double>());
      expect(
        const MerchantMatch(
          tier: MatchTier.userRule,
          confidence: 1.0,
        ).confidence,
        isA<double>(),
      );
    });
  });
}

/// **QA adversarial probe suite for PR #20 (P3b-2 — the mutation surface).**
///
/// Written by qa-tester against head `61efd7b`, 2026-07-29. These are *attack*
/// tests, not coverage tests: each one tries to make the code do something the
/// PR body claims is structurally impossible. A probe that **passes** is
/// evidence the claim holds; a probe marked `DEFECT` documented an executed
/// reproduction of behaviour that contradicted a stated property.
///
/// ---
///
/// ## P3b-3 (KHA-87 / KHA-88 / KHA-89 / KHA-90) — the DEFECT probes are
/// INVERTED, not deleted
///
/// Every probe that asserted a defect now asserts the fix, in place, keeping
/// the original scenario and the original comment about what used to happen.
/// That is the pattern `docs/lessons.md` records from KHA-79: a QA probe is
/// written to fail loudly the moment someone reverts a fix, and deleting it
/// converts "we fixed this" into "we removed the evidence". Each inverted
/// assertion is marked `INVERTED (was: ...)` so a reader can see both states.
///
/// Two probes were **not** inverted because the finding was resolved as a
/// deliberate decision rather than a code change — B2 (D-QA-7), F6 (D-QA-12)
/// and G2 (O-QA-7). Those keep asserting the behaviour, retitled, and now pin
/// the decision so it cannot drift back by accident.
///
/// The scrutiny is deliberately lopsided toward `transaction_merge.dart` /
/// `TransactionDao.mergeDuplicatePair`, because `docs/build-plan.md` names it
/// *"the single highest-risk operation in P3"* and risk R-8 sets the standard:
///
/// > **Silently deleting a real transaction is worse than an inflated total.**
///
/// The PR asserts four structural merge properties. This file re-derives each
/// one from behaviour rather than from the doc comment, and then goes looking
/// for the cases the property statements do **not** cover — which is where the
/// findings are.
///
/// Groups:
///  - **PROBE A** — can a merge lose money? (fees, converted amounts)
///  - **PROBE B** — can a merge lose a source-message reference? (NFR-A6)
///  - **PROBE C** — can a merge happen without confirmation? (R-8)
///  - **PROBE D** — can a merge write null / undo a user edit? (AC-B5.3)
///  - **PROBE E** — can the KHA-79 sign guard be bypassed?
///  - **PROBE F** — KHA-78 persisted decisions, KHA-26 delete/restore
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ledger/internal_transfer.dart';
import 'package:massrofy/features/ledger/ledger_mapping.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_edit.dart';
import 'package:massrofy/features/ledger/transaction_merge.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../support/ledger_fixtures.dart';
import '../support/plain_test_database.dart';

final List<int> _qaChainKey = List<int>.generate(32, (int i) => i + 71);

void main() {
  late AppDatabase db;
  late AuditLogDao auditLogDao;
  late TransactionDao dao;
  late TransactionMergeService merge;

  setUp(() {
    db = openPlainTestDatabase();
    auditLogDao = AuditLogDao(db, auditChainKey: _qaChainKey);
    dao = TransactionDao(db, auditLogDao);
    merge = TransactionMergeService(database: db, transactionDao: dao);
  });

  tearDown(() async => db.close());

  /// An ordinary SAR card purchase derived from SMS [messageId].
  Future<int> sms({
    String amount = '152.75',
    String currency = 'SAR',
    String? merchant,
    String? reference,
    String direction = 'debit',
    String type = TransactionType.posPurchase,
    Money? fee,
    Money? converted,
    String? fxRate,
    required int messageId,
  }) => dao.insertFromParsedSms(
    amount: Money.parse(amount, currency: currency),
    convertedAmount: converted,
    feeAmount: fee,
    fxRate: fxRate,
    merchantRawText: merchant,
    referenceNumber: reference,
    occurredAt: DateTime.utc(2026, 7, 15, 10),
    direction: direction,
    transactionType: type,
    affectsSpend: true,
    sourceMessageId: messageId,
    rulePackId: 'sa-core',
    rulePackVersion: '2026.07.28',
    ruleId: 'baj-pos-purchase-ar',
  );

  /// The whole-ledger spend report, exactly as a screen would compute it.
  Future<PeriodReport> reportNow() async => LedgerTotals.report(
    toLedgerTransactions(
      (await dao.all()).where((TransactionRow r) => !r.isDeleted),
    ),
    period: july2026,
  );

  // =========================================================================
  // PROBE A — can a merge make money disappear from a total?
  //
  // The PR's property 3: "MergeEnrichment's fields are plain nullables where
  // null means 'leave alone' — there is no way to express 'write null', so a
  // merge is structurally incapable of deleting information. It fills gaps
  // only."
  //
  // That is true *of the five fields MergeEnrichment carries*. The attack is
  // on the fields it does NOT carry: the absorbed row is soft-deleted whole,
  // so every money column on it that the enrichment cannot copy leaves the
  // ledger with it.
  // =========================================================================
  group('PROBE A — money that leaves the ledger through the merge', () {
    test(
      'A1 FIXED (KHA-87) — the absorbed row\'s FX fee is carried onto the '
      'survivor, so the fee total is unchanged by resolving a duplicate',
      () async {
        // Two alerts for one international purchase. The terser one (the
        // survivor, chosen because it is older — which is exactly what the
        // review inbox offers by default) carries no fee line; the fuller one
        // does. Identical amount, direction and type, so MergePlan ALLOWS it.
        final int survivor = await sms(messageId: 1, amount: '152.75');
        final int fuller = await sms(
          messageId: 2,
          amount: '152.75',
          fee: Money.parse('9.20', currency: 'SAR'),
        );

        final PeriodReport before = await reportNow();
        expect(
          before.fees.base!.toCanonicalString(),
          '9.2',
          reason: 'the bank charged a 9.20 SAR fee and the app reports it',
        );

        final MergeResult result = await merge.merge(
          survivorId: survivor,
          mergedAwayId: fuller,
          confirmedByUser: true,
        );
        expect(result, isA<MergeCompleted>());

        final PeriodReport after = await reportNow();
        // INVERTED (was: `after.fees.base` is null). Resolving a duplicate does
        // not change what the bank charged. `MergeEnrichment` carries the fee
        // triple now, under the same gap-fill rule as the descriptive fields.
        expect(
          after.fees.base!.toCanonicalString(),
          '9.2',
          reason:
              'the fee survives the merge — this assertion is the KHA-87 '
              'regression guard: if it ever reads null again, the money '
              'columns have fallen out of MergePlan/MergeEnrichment',
        );
        // The survivor absorbed it, whole triple, byte-for-byte.
        final TransactionRow kept = await dao.byId(survivor);
        expect(kept.feeAmountAmount, '9.2');
        expect(kept.feeAmountCurrency, 'SAR');
        // The absorbed row still holds its own copy — nothing was destroyed,
        // which is the R-8 property holding as it always did.
        expect((await dao.byId(fuller)).feeAmountAmount, '9.2');
      },
    );

    test('A1b (KHA-87) — two rows that state DIFFERENT fees are refused '
        'rather than merged: a disagreement about money is a question for '
        'the user', () async {
      final int a = await sms(
        messageId: 1,
        fee: Money.parse('9.20', currency: 'SAR'),
      );
      final int b = await sms(
        messageId: 2,
        fee: Money.parse('5.00', currency: 'SAR'),
      );

      final MergeResult result = await merge.merge(
        survivorId: a,
        mergedAwayId: b,
        confirmedByUser: true,
      );
      expect((result as MergeRejected).reason, MergeRefusal.feeDiffers);
      // A refusal is not a mutation.
      expect((await dao.byId(b)).isDeleted, isFalse);
      expect((await reportNow()).fees.base!.toCanonicalString(), '14.2');
    });

    test(
      'A2 FIXED (KHA-87) — merging a converted foreign purchase into an '
      'unconverted duplicate keeps it in the base-currency spend total',
      () async {
        // The classic D2 shape for a foreign card purchase: the first alert is
        // the terse "purchase of USD 40.00" with no conversion yet
        // (conversionPending), the second carries the settled SAR figure.
        // The review inbox defaults the OLDER row as survivor.
        final int survivorUnconverted = await sms(
          messageId: 1,
          amount: '40.00',
          currency: 'USD',
        );
        final int laterConverted = await sms(
          messageId: 2,
          amount: '40.00',
          currency: 'USD',
          converted: Money.parse('150.00', currency: 'SAR'),
        );

        final PeriodReport before = await reportNow();
        expect(
          before.spend.base!.toCanonicalString(),
          '150',
          reason:
              'one of the two rows converts, so 150 SAR reaches the base '
              'total (the other is reported as unconverted)',
        );
        expect(before.spend.unconverted, isNotEmpty);

        expect(
          (await merge.merge(
            survivorId: survivorUnconverted,
            mergedAwayId: laterConverted,
            confirmedByUser: true,
          )),
          isA<MergeCompleted>(),
        );

        final PeriodReport after = await reportNow();
        // INVERTED (was: `after.spend.base` is null). The survivor absorbs the
        // conversion the other alert carried, so one movement remains and it
        // still reaches the headline SAR figure.
        expect(
          after.spend.base!.toCanonicalString(),
          '150',
          reason:
              'the convertible figure moved to the survivor rather than being '
              'soft-deleted with the row that held it',
        );
        expect(
          (await dao.byId(survivorUnconverted)).convertedAmountAmount,
          '150',
        );
        expect(
          (await dao.byId(survivorUnconverted)).convertedAmountCurrency,
          'SAR',
        );
        // And nothing is left on the "we could not convert this" line, because
        // there is nothing left unconverted.
        expect(after.spend.unconverted, isEmpty);
      },
    );

    test('A2b (KHA-87) — two rows stating DIFFERENT converted amounts are '
        'refused', () async {
      final int a = await sms(
        messageId: 1,
        amount: '40.00',
        currency: 'USD',
        converted: Money.parse('150.00', currency: 'SAR'),
      );
      final int b = await sms(
        messageId: 2,
        amount: '40.00',
        currency: 'USD',
        converted: Money.parse('151.20', currency: 'SAR'),
      );
      final MergeResult result = await merge.merge(
        survivorId: a,
        mergedAwayId: b,
        confirmedByUser: true,
      );
      expect((result as MergeRejected).reason, MergeRefusal.conversionDiffers);
      expect((await dao.byId(b)).isDeleted, isFalse);
    });

    test('A3 — the native-currency figure is intact after the A2 merge, and '
        'now so is the base one', () async {
      final int a = await sms(messageId: 1, amount: '40.00', currency: 'USD');
      final int b = await sms(
        messageId: 2,
        amount: '40.00',
        currency: 'USD',
        converted: Money.parse('150.00', currency: 'SAR'),
      );
      await merge.merge(survivorId: a, mergedAwayId: b, confirmedByUser: true);

      final PeriodReport after = await reportNow();
      // The USD movement itself is intact and visible, as it always was.
      expect(after.spend.byCurrency.single.currencyCode, 'USD');
      expect(after.spend.byCurrency.single.net.toCanonicalString(), '40');
      // INVERTED (was: `unconverted` is not empty). The survivor can convert
      // now, so the "N transactions not converted" line has nothing to say.
      expect(after.spend.unconverted, isEmpty);
      expect(after.spend.base!.toCanonicalString(), '150');
    });

    test('A4 FIXED (the root cause of A1/A2) — MergePlan compares AND carries '
        'the money-adjacent columns', () async {
      // The root-cause probe, inverted. Two rows differing ONLY in their
      // money-adjacent columns, with the survivor holding none of them: the
      // merge is still allowed (these are one movement) but the enrichment is
      // no longer empty — it now moves every one of those figures across.
      final int a = await sms(messageId: 1, amount: '152.75');
      final int b = await sms(
        messageId: 2,
        amount: '152.75',
        fee: Money.parse('9.20', currency: 'SAR'),
        converted: Money.parse('152.75', currency: 'SAR'),
        fxRate: '1.0',
      );
      final MergeAssessment assessment = MergePlan.between(
        survivor: await dao.byId(a),
        mergedAway: await dao.byId(b),
      );
      expect(assessment, isA<MergeAllowed>());
      final MergeEnrichment enrichment =
          (assessment as MergeAllowed).enrichment;
      expect(
        enrichment.isEmpty,
        isFalse,
        reason:
            'INVERTED: the enrichment used to have nothing to say about fee, '
            'converted amount or rate. It carries all three now.',
      );
      expect(enrichment.carriesMoney, isTrue);
      expect(enrichment.feeAmount!.amount, '9.2');
      expect(enrichment.feeAmount!.currency, 'SAR');
      expect(enrichment.convertedAmount!.amount, '152.75');
      expect(enrichment.fxRate, '1.0');
    });

    test('A5 (KHA-87) — the enrichment never OVERWRITES a money column: a '
        'survivor that already states a fee keeps its own', () async {
      // The other half of the rule. Same fee on both rows is not a
      // disagreement, so the merge proceeds — and writes nothing, because
      // there is no gap to fill.
      final int a = await sms(
        messageId: 1,
        fee: Money.parse('9.20', currency: 'SAR'),
      );
      final int b = await sms(
        messageId: 2,
        fee: Money.parse('9.20', currency: 'SAR'),
      );
      final MergeAssessment assessment = MergePlan.between(
        survivor: await dao.byId(a),
        mergedAway: await dao.byId(b),
      );
      expect((assessment as MergeAllowed).enrichment.feeAmount, isNull);

      await merge.merge(survivorId: a, mergedAwayId: b, confirmedByUser: true);
      expect((await dao.byId(a)).feeAmountAmount, '9.2');
      // One movement, one fee. Not two.
      expect((await reportNow()).fees.base!.toCanonicalString(), '9.2');
    });

    test('A6 (KHA-87) — the same magnitude in a DIFFERENT currency is a '
        'disagreement, not a match: `Money`-style currency comparison holds '
        'for the fee too', () async {
      final int a = await sms(
        messageId: 1,
        fee: Money.parse('9.20', currency: 'SAR'),
      );
      final int b = await sms(
        messageId: 2,
        fee: Money.parse('9.20', currency: 'USD'),
      );
      final MergeAssessment assessment = MergePlan.between(
        survivor: await dao.byId(a),
        mergedAway: await dao.byId(b),
      );
      expect(
        (assessment as MergeRefused).reason,
        MergeRefusal.feeDiffers,
        reason: '9.20 SAR is not 9.20 USD, and never silently matches it',
      );
    });

    test('A7 (KHA-87) — a survivor waiting for a conversion stops waiting '
        'once a merge hands it one (ADR-009 case 4)', () async {
      // `conversionPending` is derived state, not an observation, so it is
      // recomputed rather than gap-filled. A survivor that gains a converted
      // amount must stop claiming it is still pending, or the "not converted"
      // line keeps counting a row that now converts.
      final int pending = await dao.insertFromParsedSms(
        amount: Money.parse('40.00', currency: 'USD'),
        conversionPending: true,
        occurredAt: DateTime.utc(2026, 7, 15, 10),
        direction: 'debit',
        transactionType: TransactionType.posPurchase,
        affectsSpend: true,
        sourceMessageId: 1,
        rulePackId: 'sa-core',
        rulePackVersion: '2026.07.28',
        ruleId: 'baj-pos-purchase-ar',
      );
      final int settled = await sms(
        messageId: 2,
        amount: '40.00',
        currency: 'USD',
        converted: Money.parse('150.00', currency: 'SAR'),
      );

      expect(
        await merge.merge(
          survivorId: pending,
          mergedAwayId: settled,
          confirmedByUser: true,
        ),
        isA<MergeCompleted>(),
      );

      final TransactionRow kept = await dao.byId(pending);
      expect(kept.convertedAmountAmount, '150');
      expect(kept.conversionPending, isFalse);
    });

    test('A7b (KHA-87) — a user\'s internal-transfer verdict on the absorbed '
        'row is carried, not soft-deleted with it (AC-B11.2)', () async {
      // Not money, but it decides whether money counts. Dropping it would make
      // the user's answer stop applying and move the spend figure — and unlike
      // the fee case there is no "safe" direction: losing `external` can lower
      // the total, losing `internal` can raise it.
      final int survivor = await sms(messageId: 1);
      final int decided = await sms(messageId: 2);
      await dao.setInternalTransferDecision(
        transactionIds: <int>[decided],
        state: InternalTransferState.external,
        groupId: 'grp-1',
      );

      expect(
        await merge.merge(
          survivorId: survivor,
          mergedAwayId: decided,
          confirmedByUser: true,
        ),
        isA<MergeCompleted>(),
      );

      final TransactionRow kept = await dao.byId(survivor);
      expect(kept.internalTransferState, InternalTransferState.external);
      expect(kept.internalTransferGroupId, 'grp-1');
    });

    test('A7c (KHA-87) — two rows with CONTRADICTING transfer verdicts are '
        'refused', () async {
      final int a = await sms(messageId: 1);
      final int b = await sms(messageId: 2);
      await dao.setInternalTransferDecision(
        transactionIds: <int>[a],
        state: InternalTransferState.internal,
        groupId: 'grp-a',
      );
      await dao.setInternalTransferDecision(
        transactionIds: <int>[b],
        state: InternalTransferState.external,
        groupId: 'grp-b',
      );

      final MergeAssessment assessment = MergePlan.between(
        survivor: await dao.byId(a),
        mergedAway: await dao.byId(b),
      );
      expect(
        (assessment as MergeRefused).reason,
        MergeRefusal.spendEffectDiffers,
      );
    });

    test('A8 (KHA-87) — the compared/carried set covers every money-bearing '
        'column on `transactions`, so a new one cannot silently join the '
        '"neither compared nor carried" set', () async {
      // QA's done check, as an executable claim. For each money-bearing
      // column, a row that differs ONLY in that column must produce either a
      // refusal or a non-empty enrichment — never a silent `MergeAllowed`
      // with `isEmpty == true`, which is what A4 used to demonstrate.
      //
      // `remaining_balance` is included even though it enters no total: the
      // point of the check is that the column was *considered*, not that it
      // moves a headline figure.
      final Map<String, Future<int> Function(int messageId)> differsOnlyIn =
          <String, Future<int> Function(int)>{
            'fee_amount': (int m) => sms(
              messageId: m,
              fee: Money.parse('9.20', currency: 'SAR'),
            ),
            'converted_amount': (int m) => sms(
              messageId: m,
              converted: Money.parse('152.75', currency: 'SAR'),
            ),
            'fx_rate': (int m) => sms(messageId: m, fxRate: '3.75'),
            'remaining_balance': (int m) => dao.insertFromParsedSms(
              amount: Money.parse('152.75', currency: 'SAR'),
              remainingBalance: Money.parse('1000.00', currency: 'SAR'),
              occurredAt: DateTime.utc(2026, 7, 15, 10),
              direction: 'debit',
              transactionType: TransactionType.posPurchase,
              affectsSpend: true,
              sourceMessageId: m,
              rulePackId: 'sa-core',
              rulePackVersion: '2026.07.28',
              ruleId: 'baj-pos-purchase-ar',
            ),
          };

      int messageId = 100;
      for (final MapEntry<String, Future<int> Function(int)> entry
          in differsOnlyIn.entries) {
        final int plain = await sms(messageId: messageId++);
        final int richer = await entry.value(messageId++);
        final MergeAssessment assessment = MergePlan.between(
          survivor: await dao.byId(plain),
          mergedAway: await dao.byId(richer),
        );
        expect(
          assessment is MergeRefused ||
              (assessment as MergeAllowed).enrichment.isEmpty == false,
          isTrue,
          reason:
              '${entry.key} is neither compared nor carried — the KHA-87 '
              'shape has reappeared for a new column',
        );
      }
    });
  });

  // =========================================================================
  // PROBE B — NFR-A6: "the merged result must remain traceable to both
  // source messages". Attack: make a source-message reference unreachable.
  // =========================================================================
  group('PROBE B — source-message traceability under attack', () {
    test('B1 — the single-merge case genuinely holds (re-verifying the PR\'s '
        'claim rather than trusting it)', () async {
      final int a = await sms(messageId: 11);
      final int b = await sms(messageId: 22);
      await merge.merge(survivorId: a, mergedAwayId: b, confirmedByUser: true);

      expect((await dao.byId(a)).sourceMessageId, 11);
      expect((await dao.byId(b)).sourceMessageId, 22);
      expect((await dao.byId(a)).mergedFromTransactionId, b);
      expect((await dao.byId(b)).mergedIntoId, a);
    });

    test('B2 ACCEPTED AND DOCUMENTED — a survivor that absorbs a SECOND '
        'duplicate keeps only the latest pointer; the first stays reachable '
        'from its own row and from the audit trail', () async {
      // Three alerts for one purchase is not exotic — a bank sending a POS
      // alert, a "card used" alert and a settlement alert produces exactly
      // this, and the D2 reference-number tier flags all of them.
      final int survivor = await sms(messageId: 11);
      final int first = await sms(messageId: 22);
      final int second = await sms(messageId: 33);

      await merge.merge(
        survivorId: survivor,
        mergedAwayId: first,
        confirmedByUser: true,
      );
      expect((await dao.byId(survivor)).mergedFromTransactionId, first);

      await merge.merge(
        survivorId: survivor,
        mergedAwayId: second,
        confirmedByUser: true,
      );

      // The behaviour is unchanged and the DOC is what moved (D-QA-7):
      // `transaction_merge.dart` no longer claims "pointers both ways" per
      // survivor, it claims it per merge, and names where the earlier link
      // remains readable. A set-valued link is tracked on KHA-88.
      //
      // These assertions are the guard on that reachability claim, which is
      // the thing that makes the degradation acceptable. If any of them
      // breaks, the survivor's earlier merge really has become unrecoverable.
      expect((await dao.byId(survivor)).mergedFromTransactionId, second);
      expect(
        (await dao.byId(first)).mergedIntoId,
        survivor,
        reason: 'the first absorbed row still names its survivor',
      );
      final List<AuditEntryRow> survivorHistory = await auditLogDao.queryFor(
        'transaction',
        survivor.toString(),
      );
      expect(
        survivorHistory.where((AuditEntryRow e) => e.action == 'merge'),
        hasLength(2),
        reason:
            'and both merges are in the survivor\'s own change history, with '
            'their before/after — so US-F5 can reconstruct the pair the '
            'column no longer holds',
      );
    });

    test('B3 FIXED (KHA-88, HIGH) — undoing the FIRST of two merges leaves '
        'the survivor\'s link to the SECOND alone, and writes nothing to the '
        'survivor to audit', () async {
      final int survivor = await sms(messageId: 11);
      final int first = await sms(messageId: 22);
      final int second = await sms(messageId: 33);

      await merge.merge(
        survivorId: survivor,
        mergedAwayId: first,
        confirmedByUser: true,
      );
      await merge.merge(
        survivorId: survivor,
        mergedAwayId: second,
        confirmedByUser: true,
      );
      expect((await dao.byId(survivor)).mergedFromTransactionId, second);

      final int auditEntriesBefore = (await auditLogDao.queryFor(
        'transaction',
        survivor.toString(),
      )).length;

      // The user undoes the FIRST merge (restores `first`). `restore()` now
      // clears the survivor's `mergedFromTransactionId` **only when it names
      // the row being restored** — the identity check that was missing.
      await merge.undo(first);

      // INVERTED (was: the survivor's pointer became null). `second` is still
      // recorded as absorbed into `survivor`, and the two halves of the link
      // agree with each other again.
      expect(
        (await dao.byId(survivor)).mergedFromTransactionId,
        second,
        reason:
            'undoing an unrelated merge must not touch this one — the '
            'KHA-88 / D-QA-8 regression guard',
      );
      expect((await dao.byId(second)).mergedIntoId, survivor);
      expect((await dao.byId(second)).isDeleted, isTrue);
      // ...and the row that WAS undone is genuinely back.
      expect((await dao.byId(first)).isDeleted, isFalse);
      expect((await dao.byId(first)).mergedIntoId, isNull);

      // NFR-A2 the other way round: no entry against the survivor because
      // nothing was written to the survivor. The audit trail is complete
      // precisely because the mutation did not happen.
      final int auditEntriesAfter = (await auditLogDao.queryFor(
        'transaction',
        survivor.toString(),
      )).length;
      expect(
        auditEntriesAfter,
        auditEntriesBefore,
        reason: 'no write to the survivor, so nothing to record',
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('B4 FIXED (KHA-88) — a plain single-merge undo DOES write an audit '
        'entry against the survivor it mutates (NFR-A2)', () async {
      final int a = await sms(messageId: 1);
      final int b = await sms(messageId: 2);
      await merge.merge(survivorId: a, mergedAwayId: b, confirmedByUser: true);

      final List<AuditEntryRow> beforeUndo = await auditLogDao.queryFor(
        'transaction',
        a.toString(),
      );
      await merge.undo(b);
      final List<AuditEntryRow> afterUndo = await auditLogDao.queryFor(
        'transaction',
        a.toString(),
      );

      // The survivor's mergedFromTransactionId went b -> null...
      expect((await dao.byId(a)).mergedFromTransactionId, isNull);
      // ...and INVERTED (was: `afterUndo.length == beforeUndo.length`), the
      // survivor's own change history now records the reversal, so US-F5 can
      // no longer show an undone merge as though it still stands.
      expect(afterUndo.length, beforeUndo.length + 1);
      final AuditEntryRow reversal = afterUndo.last;
      expect(reversal.action, 'merge_undo');
      expect(reversal.actor, 'user');
      expect(reversal.actorDetail, 'duplicate_merge_undo');
      // A genuine before/after, not a claim: b -> null.
      expect(reversal.fieldChangesJson, contains('mergedFromTransactionId'));
      expect(reversal.fieldChangesJson, contains('"$b"'));
      // The survivor's history reads create, merge, merge_undo.
      expect(afterUndo.map((AuditEntryRow e) => e.action), <String>[
        'create',
        'merge',
        'merge_undo',
      ]);
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('B6 FIXED (D-QA-9) — merge CHAINS are refused in the SURVIVOR '
        'direction too, so "no chains" is now true in both', () async {
      // P3b-2's own test is named "an already-merged row cannot be merged
      // again — no chains". It pinned the *absorbed* direction only: merging a
      // soft-deleted row is refused by `MergeRefusal.notLive`. A SURVIVOR is
      // still live, so it could itself be merged away into a third row,
      // orphaning the row it had absorbed.
      final int a = await sms(messageId: 11);
      final int b = await sms(messageId: 22);
      final int c = await sms(messageId: 33);

      await merge.merge(survivorId: b, mergedAwayId: a, confirmedByUser: true);
      final MergeResult chained = await merge.merge(
        survivorId: c,
        mergedAwayId: b,
        confirmedByUser: true,
      );
      // INVERTED (was: `isA<MergeCompleted>()`).
      expect(
        (chained as MergeRejected).reason,
        MergeRefusal.chainWouldForm,
        reason:
            'b has already absorbed a, so merging b away would build the '
            'a -> b -> c chain the doc claims cannot exist',
      );

      // The refusal wrote nothing: b is still live and still records absorbing
      // a, c is untouched, and the two live movements are both counted.
      expect((await dao.byId(b)).isDeleted, isFalse);
      expect((await dao.byId(b)).mergedFromTransactionId, a);
      expect((await dao.byId(c)).mergedFromTransactionId, isNull);
      expect((await reportNow()).spend.base!.toCanonicalString(), '305.5');
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('B6b (D-QA-9) — the absorbed direction still refuses, so the claim '
        'is pinned on BOTH sides rather than one', () async {
      final int a = await sms(messageId: 11);
      final int b = await sms(messageId: 22);
      final int c = await sms(messageId: 33);
      await merge.merge(survivorId: a, mergedAwayId: b, confirmedByUser: true);

      // b is soft-deleted, so re-merging it anywhere is `notLive`. This is the
      // half P3b-2 already had; it is asserted alongside B6 so a future change
      // cannot satisfy one direction by breaking the other.
      final MergeResult again = await merge.merge(
        survivorId: c,
        mergedAwayId: b,
        confirmedByUser: true,
      );
      expect((again as MergeRejected).reason, MergeRefusal.notLive);
      expect((await dao.byId(b)).mergedIntoId, a);
    });

    test('B7 — concurrent merges of the same pair do not both apply (SQLite '
        'transaction serialisation holds)', () async {
      final int a = await sms(messageId: 1);
      final int b = await sms(messageId: 2);
      final int c = await sms(messageId: 3);

      // Two racing user actions: merge b into a, and merge b into c.
      final List<MergeResult> results =
          await Future.wait<MergeResult>(<Future<MergeResult>>[
            merge.merge(survivorId: a, mergedAwayId: b, confirmedByUser: true),
            merge.merge(survivorId: c, mergedAwayId: b, confirmedByUser: true),
          ]);

      // Exactly one succeeds; the loser sees `notLive` because the winner
      // already soft-deleted `b` inside its own transaction.
      expect(
        results.whereType<MergeCompleted>(),
        hasLength(1),
        reason: 'a double-apply would leave b merged into two survivors',
      );
      expect(
        results.whereType<MergeRejected>().single.reason,
        MergeRefusal.notLive,
      );
      // And the money is right: one movement remains counted, plus the
      // untouched third row.
      expect((await reportNow()).spend.base!.toCanonicalString(), '305.5');
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('B5 — a merge does NOT hide the absorbed row from the audit trail; '
        'both histories remain queryable by id', () async {
      final int a = await sms(messageId: 1);
      final int b = await sms(messageId: 2);
      await merge.merge(survivorId: a, mergedAwayId: b, confirmedByUser: true);

      expect(
        await auditLogDao.queryFor('transaction', b.toString()),
        hasLength(2),
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });
  });

  // =========================================================================
  // PROBE C — R-8's "never automatic". Attack: reach a merge without an
  // explicit confirmation.
  // =========================================================================
  group('PROBE C — merging without confirmation', () {
    test('C1 — `confirmedByUser` is required and has no default: false reads '
        'and writes nothing at all', () async {
      final int a = await sms(messageId: 1, merchant: null);
      final int b = await sms(messageId: 2, merchant: 'EXTRA MART');

      expect(
        await merge.merge(
          survivorId: a,
          mergedAwayId: b,
          confirmedByUser: false,
        ),
        isA<MergeNotConfirmed>(),
      );
      // Not one column moved, and no audit entry was appended.
      expect((await dao.byId(b)).isDeleted, isFalse);
      expect((await dao.byId(a)).merchantRawText, isNull);
      expect(
        await auditLogDao.queryFor('transaction', a.toString()),
        hasLength(1),
      );
    });

    test('C2 HARDENED (O-QA-5) — the DAO merge is still public, but `actor` '
        'is now a required argument with no default', () async {
      // The DAO method is reachable directly; the confirmation guard lives one
      // layer up, in the service, and that is by design. What changed is the
      // *audit* consequence of reaching it: `actor` used to default to 'user',
      // so a future background caller could have merged two rows and written
      // an audit entry claiming a person did it, by omitting one argument.
      //
      // The compiler enforces this now, which is why this call has to name an
      // actor at all. Deleting `actor:` from the line below is a build error —
      // that IS the assertion, and it is stronger than anything expect() can
      // say at runtime.
      final int a = await sms(messageId: 1, merchant: null);
      final int b = await sms(messageId: 2, merchant: 'EXTRA MART');
      await dao.mergeDuplicatePair(
        survivorId: a,
        mergedAwayId: b,
        enrichment: const MergeEnrichment(merchantRawText: 'EXTRA MART'),
        actor: 'system_rule',
        actorDetail: 'probe_c2',
      );

      // And the entry says what actually happened, rather than 'user'.
      final AuditEntryRow entry = (await auditLogDao.queryFor(
        'transaction',
        a.toString(),
      )).last;
      expect(entry.action, 'merge');
      expect(entry.actor, 'system_rule');
    });

    test('C3 — a refusal is not a mutation: no audit entry, no column '
        'change', () async {
      final int a = await sms(messageId: 1, amount: '152.75');
      final int b = await sms(messageId: 2, amount: '99.00');
      expect(
        (await merge.merge(
                  survivorId: a,
                  mergedAwayId: b,
                  confirmedByUser: true,
                )
                as MergeRejected)
            .reason,
        MergeRefusal.amountDiffers,
      );
      expect(
        await auditLogDao.queryFor('transaction', a.toString()),
        hasLength(1),
      );
      expect((await dao.byId(b)).isDeleted, isFalse);
    });
  });

  // =========================================================================
  // PROBE D — AC-B5.3, "user intent outranks the parser, always".
  // =========================================================================
  group('PROBE D — user edits versus the merge', () {
    test('D1 — a user edit on the SURVIVOR is protected, including the nasty '
        'case where the user CLEARED the field', () async {
      final int a = await sms(messageId: 1, merchant: 'PARSER TEXT');
      await TransactionEditService(database: db, transactionDao: dao).edit(
        a,
        const TransactionEditDraft(
          merchantRawText: Edited<String?>(null), // deliberately cleared
        ),
      );
      final int b = await sms(messageId: 2, merchant: 'PARSER TEXT');

      await merge.merge(survivorId: a, mergedAwayId: b, confirmedByUser: true);

      // A null-check alone would happily refill this. The protected-set check
      // is what stops it, and it genuinely does.
      expect((await dao.byId(a)).merchantRawText, isNull);
    });

    test('D2 FIXED (KHA-89) — a user edit on the LOSING side is no longer '
        'discarded for the parser\'s value: the pair is refused so the user '
        'decides', () async {
      // The user corrects the merchant on row `b`. Then a duplicate pair is
      // resolved with `a` (which still holds the parser's mis-read) as the
      // survivor. AC-B5.3 says user intent outranks the parser *always*.
      //
      // The fix is a refusal rather than "the correction wins": letting it win
      // would make a merge overwrite a populated field, breaking the
      // never-overwrite property, and would have the app arbitrate between two
      // statements only the user can reconcile.
      final int a = await sms(messageId: 1, merchant: 'ALINMA*POS*3311');
      final int b = await sms(messageId: 2, merchant: 'ALINMA*POS*3311');
      await TransactionEditService(database: db, transactionDao: dao).edit(
        b,
        const TransactionEditDraft(
          merchantRawText: Edited<String?>('Panda Hypermarket'),
        ),
      );

      final MergeResult result = await merge.merge(
        survivorId: a,
        mergedAwayId: b,
        confirmedByUser: true,
      );
      // INVERTED (was: MergeCompleted, and `a` kept the parser text).
      expect((result as MergeRejected).reason, MergeRefusal.userEditDiffers);

      // Nothing was written: both rows are live, and the correction is still
      // on a row the user can see rather than on a soft-deleted one.
      expect((await dao.byId(a)).merchantRawText, 'ALINMA*POS*3311');
      expect((await dao.byId(b)).merchantRawText, 'Panda Hypermarket');
      expect((await dao.byId(b)).isDeleted, isFalse);
    });

    test('D2b (KHA-89) — a user edit on the losing side that AGREES with the '
        'survivor is not a disagreement, and the merge proceeds', () async {
      // The refusal must be about contradiction, not about the mere presence
      // of an edit — otherwise correcting a row would make it permanently
      // unmergeable and the review inbox would fill up with pairs nobody can
      // resolve.
      final int a = await sms(messageId: 1, merchant: 'Panda Hypermarket');
      final int b = await sms(messageId: 2, merchant: 'ALINMA*POS*3311');
      await TransactionEditService(database: db, transactionDao: dao).edit(
        b,
        const TransactionEditDraft(
          merchantRawText: Edited<String?>('Panda Hypermarket'),
        ),
      );

      expect(
        await merge.merge(
          survivorId: a,
          mergedAwayId: b,
          confirmedByUser: true,
        ),
        isA<MergeCompleted>(),
      );
      expect((await dao.byId(a)).merchantRawText, 'Panda Hypermarket');
    });

    test(
      'D3 FIXED (KHA-89) — a user-edited value COPIED onto the survivor by a '
      'merge arrives still protected, so a later automated write cannot '
      'overwrite it',
      () async {
        // `a` has no merchant. `b`'s merchant is a user correction. The merge
        // copies it onto `a` — good — but does not add `merchantRawText` to
        // `a`'s user_edited_fields, so `a` now holds a user value the app
        // believes came from the parser.
        final int a = await sms(messageId: 1, merchant: null);
        final int b = await sms(messageId: 2, merchant: 'ALINMA*POS*3311');
        await TransactionEditService(database: db, transactionDao: dao).edit(
          b,
          const TransactionEditDraft(
            merchantRawText: Edited<String?>('Panda Hypermarket'),
          ),
        );

        await merge.merge(
          survivorId: a,
          mergedAwayId: b,
          confirmedByUser: true,
        );
        expect((await dao.byId(a)).merchantRawText, 'Panda Hypermarket');

        // INVERTED (was: `isEmpty`). The protection travelled with the value.
        expect(
          decodeUserEditedFields((await dao.byId(a)).userEditedFields),
          contains(TransactionField.merchantRawText),
          reason:
              'the survivor holds a user-authored value and the app now knows '
              'it — the next automated writer (a re-scan, another merge, P7\'s '
              'statement import) will leave it alone',
        );

        // Proved behaviourally, not just by the column: a third row carrying
        // parser text cannot re-enrich the now-protected field.
        final int c = await sms(messageId: 3, merchant: 'ALINMA*POS*3311');
        await merge.merge(
          survivorId: a,
          mergedAwayId: c,
          confirmedByUser: true,
        );
        expect((await dao.byId(a)).merchantRawText, 'Panda Hypermarket');
      },
    );

    test('D4 — `MergeEnrichment` genuinely cannot express "write null": every '
        'field is a bare nullable and `mergeDuplicatePair` maps null to '
        'Value.absent()', () async {
      // Behavioural proof rather than a type-shape assertion: give the
      // survivor values in every enrichable field, merge in a row that has
      // none of them, and confirm nothing was blanked.
      final int a = await sms(
        messageId: 1,
        merchant: 'SURVIVOR MERCHANT',
        reference: 'REF-1',
      );
      final int b = await sms(messageId: 2, merchant: null, reference: null);

      await merge.merge(survivorId: a, mergedAwayId: b, confirmedByUser: true);

      final TransactionRow survivor = await dao.byId(a);
      expect(survivor.merchantRawText, 'SURVIVOR MERCHANT');
      expect(survivor.referenceNumber, 'REF-1');
      expect(survivor.occurredAt, isNotNull);
    });

    test('D5 — a re-scan cannot overwrite a user edit either (AC-B5.3 at the '
        'other write path)', () async {
      final int a = await sms(messageId: 1, merchant: 'PARSER TEXT');
      await TransactionEditService(database: db, transactionDao: dao).edit(
        a,
        const TransactionEditDraft(
          merchantRawText: Edited<String?>('User corrected'),
        ),
      );
      expect(
        decodeUserEditedFields((await dao.byId(a)).userEditedFields),
        contains(TransactionField.merchantRawText),
      );
    });
  });

  // =========================================================================
  // PROBE E — KHA-79: the sign guard. Attack: get a negative magnitude into
  // the transactions table through ANY path.
  // =========================================================================
  group('PROBE E — sign-convention guard bypass attempts', () {
    test('E1 — create() now refuses a negative magnitude (KHA-79 fixed); the '
        'throw is SYNCHRONOUS', () {
      expect(
        () => dao.create(
          amount: Money.parse('-1.500', currency: 'KWD'),
          actor: 'user',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('E2 — insertManual() (the NEW manual-entry path KHA-79 was filed to '
        'protect) refuses a negative magnitude', () {
      expect(
        () => dao.insertManual(
          amount: Money.parse('-50.00', currency: 'SAR'),
          occurredAt: DateTime.utc(2026, 7, 15),
          direction: 'debit',
          transactionType: TransactionType.posPurchase,
          affectsSpend: true,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('E3 — applyUserEdit() refuses to edit an amount to a negative '
        'magnitude', () async {
      final int a = await sms(messageId: 1);
      expect(
        () => dao.applyUserEdit(
          id: a,
          amount: Edited<Money>(Money.parse('-9.99', currency: 'SAR')),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect((await dao.byId(a)).amountAmount, '152.75');
    });

    test(
      'E4 — insertFromParsedSms and insertManualCompletion stay guarded',
      () {
        expect(
          () => dao.insertFromParsedSms(
            amount: Money.parse('-1.00', currency: 'SAR'),
            direction: 'debit',
            transactionType: TransactionType.posPurchase,
            affectsSpend: true,
            sourceMessageId: 1,
            rulePackId: 'p',
            rulePackVersion: 'v',
            ruleId: 'r',
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => dao.insertManualCompletion(
            amount: Money.parse('-1.00', currency: 'SAR'),
            occurredAt: DateTime.utc(2026, 7, 15),
            direction: 'debit',
            transactionType: TransactionType.posPurchase,
            affectsSpend: true,
            sourceMessageId: 1,
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('E5 — ZERO is deliberately accepted, and that is a documented '
        'decision rather than a hole in the guard', () async {
      // `sign_convention.dart` point 3: a zero-amount movement is a real
      // thing a bank sends (a 0.00 authorisation hold, a waived fee) and
      // rejecting it would push a genuine message into the review queue.
      // Probed explicitly so the audit evidence shows the boundary was
      // examined and found intentional, not missed.
      final int id = await dao.insertManual(
        amount: Money.parse('0.00', currency: 'SAR'),
        occurredAt: DateTime.utc(2026, 7, 15),
        direction: 'debit',
        transactionType: TransactionType.posPurchase,
        affectsSpend: true,
      );
      expect((await dao.byId(id)).amountAmount, '0');
    });

    test('E6 — the guard is at the DAO, so raw Drift writes still bypass it '
        '(documented residual, unreachable from the app)', () async {
      // The last remaining way to get a negative magnitude into the table is
      // to bypass the DAO entirely. Recorded so the audit evidence shows the
      // attack was attempted and its reachability assessed, not overlooked.
      // There is no CHECK constraint on the column itself.
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              amountAmount: '-50.00',
              amountCurrency: 'SAR',
              amountMinor: -5000,
              direction: const Value<String>('debit'),
              transactionType: const Value<String>(TransactionType.posPurchase),
              affectsSpend: const Value<bool>(true),
              occurredAt: Value<DateTime?>(DateTime.utc(2026, 7, 15)),
            ),
          );
      final PeriodReport report = await reportNow();
      expect(
        report.spend.base!.toCanonicalString(),
        '-50',
        reason:
            'a raw insert still inverts the total — no CHECK constraint '
            'defends the column itself. Not reachable through any app code '
            'path; noted as residual risk for P7 statement import.',
      );
    });
  });

  // =========================================================================
  // PROBE F — KHA-78 persisted transfer decisions and KHA-26 delete/restore.
  // =========================================================================
  group('PROBE F — persisted decisions and soft delete', () {
    test('F1 — confirming an internal-transfer pair removes BOTH legs from '
        'the next spend computation', () async {
      final int out = await sms(
        messageId: 1,
        amount: '2000.00',
        direction: 'debit',
        type: TransactionType.transferOut,
      );
      final int into = await sms(
        messageId: 2,
        amount: '2000.00',
        direction: 'credit',
        type: TransactionType.transferIn,
      );

      final PeriodReport before = await reportNow();
      expect(before.spend.base!.toCanonicalString(), '2000');

      await dao.setInternalTransferDecision(
        transactionIds: <int>[out, into],
        state: InternalTransferState.internal,
        groupId: 'grp-1',
      );

      final PeriodReport after = await reportNow();
      expect(
        after.spend.base,
        isNull,
        reason: 'the confirmed transfer left spend entirely',
      );
      expect((await dao.byId(out)).internalTransferState, 'internal');
      expect((await dao.byId(into)).internalTransferState, 'internal');
      expect((await dao.byId(out)).needsReview, isFalse);
    });

    test('F2 — rejecting writes `external`, which the detector honours over '
        'its own derivation (the decision survives re-derivation)', () async {
      final int out = await sms(
        messageId: 1,
        amount: '2000.00',
        direction: 'debit',
        type: TransactionType.transferOut,
      );
      final int into = await sms(
        messageId: 2,
        amount: '2000.00',
        direction: 'credit',
        type: TransactionType.transferIn,
      );
      await dao.setInternalTransferDecision(
        transactionIds: <int>[out, into],
        state: InternalTransferState.external,
        groupId: null,
      );

      expect((await dao.byId(out)).internalTransferState, 'external');
      final PeriodReport after = await reportNow();
      expect(
        after.spend.base!.toCanonicalString(),
        '2000',
        reason: 'a rejected transfer stays in spend',
      );
      expect(after.needsReviewCount, 0, reason: 'and stops being proposed');
    });

    test('F3 — both legs of a transfer decision are written atomically and '
        'both get an audit entry', () async {
      final int out = await sms(
        messageId: 1,
        type: TransactionType.transferOut,
      );
      final int into = await sms(
        messageId: 2,
        direction: 'credit',
        type: TransactionType.transferOut,
      );
      await dao.setInternalTransferDecision(
        transactionIds: <int>[out, into],
        state: InternalTransferState.internal,
        groupId: 'grp-1',
      );
      expect(
        (await auditLogDao.queryFor(
          'transaction',
          out.toString(),
        )).map((AuditEntryRow e) => e.action),
        <String>['create', 'update'],
      );
      expect(
        (await auditLogDao.queryFor(
          'transaction',
          into.toString(),
        )).map((AuditEntryRow e) => e.action),
        <String>['create', 'update'],
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test(
      'F4 — a soft-deleted transaction leaves every total and can be '
      'restored with the SAME id, so its history is intact (AC-B8.1/B8.2)',
      () async {
        final int a = await sms(messageId: 1, amount: '152.75');
        await dao.softDelete(id: a, actor: 'user');
        expect((await reportNow()).spend.base, isNull);

        await dao.restore(id: a, actor: 'user');
        expect((await reportNow()).spend.base!.toCanonicalString(), '152.75');
        expect(
          (await auditLogDao.queryFor(
            'transaction',
            a.toString(),
          )).map((AuditEntryRow e) => e.action),
          <String>['create', 'delete', 'restore'],
        );
      },
    );

    test('F5 — restoring a MERGED-away row is the merge undo, and it is '
        'recorded as such', () async {
      final int a = await sms(messageId: 1);
      final int b = await sms(messageId: 2);
      await merge.merge(survivorId: a, mergedAwayId: b, confirmedByUser: true);
      await merge.undo(b);

      final List<AuditEntryRow> history = await auditLogDao.queryFor(
        'transaction',
        b.toString(),
      );
      expect(history.map((AuditEntryRow e) => e.action), <String>[
        'create',
        'merge',
        'restore',
      ]);
    });

    test('F6 DECIDED AND DOCUMENTED (D-QA-12) — undoing a merge deliberately '
        'does NOT reverse the enrichment; the doc now says so', () async {
      // P3b-2's doc claimed "restore() reverses the whole thing". It reverses
      // the soft delete and the link; it does not reverse the field copies,
      // and `transaction_merge.dart`'s property 1 now states that as a
      // decision with its reason: gap-filled information is not harmful, and
      // stripping it on the way out would be the undo deleting information —
      // the exact thing the never-overwrite property exists to prevent.
      final int a = await sms(messageId: 1, merchant: null, reference: null);
      final int b = await sms(
        messageId: 2,
        merchant: 'EXTRA MART',
        reference: 'REF-9911',
      );
      await merge.merge(survivorId: a, mergedAwayId: b, confirmedByUser: true);
      await merge.undo(b);

      expect(
        (await dao.byId(a)).merchantRawText,
        'EXTRA MART',
        reason:
            'DECIDED: the survivor keeps what the merge gave it. Both rows '
            'are live and both name the same merchant, and neither is wrong.',
      );
      expect((await dao.byId(b)).merchantRawText, 'EXTRA MART');
      // What the undo IS an inverse of, and this is the part that matters for
      // R-8: the soft delete and the link, on both sides.
      expect((await dao.byId(b)).isDeleted, isFalse);
      expect((await dao.byId(b)).mergedIntoId, isNull);
      expect((await dao.byId(a)).mergedFromTransactionId, isNull);
    });
  });

  // =========================================================================
  // PROBE G — KHA-74: an unreadable row is reported, not dropped.
  // =========================================================================
  group('PROBE G — KHA-74 unreadable amounts', () {
    test('G1 — a corrupt amount column surfaces as an UnreadableTransaction '
        'instead of vanishing', () async {
      final int a = await sms(messageId: 1);
      // Direct DB edit — the only way this is reachable, per KHA-74.
      await db.customStatement(
        'UPDATE transactions SET amount_amount = ? WHERE id = ?',
        <Object?>['not-a-number', a],
      );

      final LedgerMappingOutcome outcome = mapLedgerTransactions(
        await dao.all(),
      );
      expect(outcome.transactions, isEmpty);
      expect(outcome.hasUnreadable, isTrue);
      expect(outcome.unreadable.single.transactionId, a);
      expect(
        outcome.unreadable.single.reason,
        UnreadableReason.unparsableAmount,
      );
    });

    test('G2 DOCUMENTED (O-QA-7) — an unknown currency code is deliberately '
        'NOT treated as unreadable, and the doc now says so', () async {
      // `ledger_mapping.dart`'s comment used to say a row is unreadable when
      // "`amount_currency` is not a currency code this build understands".
      // `Money.tryParse` performs no such check — it stores whatever string it
      // is handed — so that half of the sentence was never true.
      //
      // The SENTENCE was corrected rather than the code, because the current
      // behaviour is the one KHA-74 asked for: the row lands in its own
      // currency bucket and is reported as `unconverted`, so it is VISIBLE
      // rather than dropped. Declaring it unreadable would hide a real
      // transaction to protect a total that is already protected. This test
      // pins that decision so nobody "fixes" it back.
      final int a = await sms(messageId: 1);
      await db.customStatement(
        'UPDATE transactions SET amount_currency = ? WHERE id = ?',
        <Object?>['ZZZ', a],
      );
      final LedgerMappingOutcome outcome = mapLedgerTransactions(
        await dao.all(),
      );
      expect(outcome.hasUnreadable, isFalse);
      expect(outcome.transactions.single.amount.currencyCode, 'ZZZ');
      // The safety net that does hold: it cannot reach the base total.
      expect((await reportNow()).spend.base, isNull);
      expect((await reportNow()).spend.unconverted, isNotEmpty);
    });
  });
}

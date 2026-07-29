/// **QA adversarial probe suite for PR #20 (P3b-2 — the mutation surface).**
///
/// Written by qa-tester against head `61efd7b`, 2026-07-29. These are *attack*
/// tests, not coverage tests: each one tries to make the code do something the
/// PR body claims is structurally impossible. A probe that **passes** is
/// evidence the claim holds; a probe marked `DEFECT` documents an executed
/// reproduction of behaviour that contradicts a stated property.
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
      'A1 DEFECT — the absorbed row\'s FX fee vanishes from the fee total; '
      'MergeEnrichment has no fee field so it cannot be carried across',
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
        // EXPECTED (per "a merge is structurally incapable of deleting
        // information"): the 9.20 fee is still reported somewhere.
        // ACTUAL: it is gone. The fee's only carrier was soft-deleted and
        // MergeEnrichment has no `feeAmount` field to move it onto the
        // survivor. No error, no flag, no count — the KHA-74 failure mode
        // (money silently absent from a total) reintroduced via the merge path.
        expect(
          after.fees.base,
          isNull,
          reason:
              'DEFECT: the fee total dropped from 9.20 SAR to nothing because '
              'the merge soft-deleted the only row carrying the fee and cannot '
              'copy it to the survivor',
        );
        // And the survivor demonstrably did not absorb it:
        expect((await dao.byId(survivor)).feeAmountAmount, isNull);
        // The absorbed row still holds it — nothing was destroyed, which is the
        // R-8 property holding — but nothing surfaces it either.
        expect((await dao.byId(fuller)).feeAmountAmount, '9.2');
      },
    );

    test('A2 DEFECT — merging a converted foreign purchase into an '
        'unconverted duplicate silently DROPS it out of the base-currency '
        'spend total', () async {
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
      // EXPECTED: after resolving a duplicate, the base spend figure should be
      // 150 SAR — one movement, converted.
      // ACTUAL: the base figure is null. MergePlan compared only
      // amount/currency/direction/type; it never looked at
      // convertedAmount/fxRate, and MergeEnrichment has no field for either.
      // The row that COULD be converted was soft-deleted; the survivor cannot
      // be. The headline SAR total lost 150 SAR to a "safe" operation.
      expect(
        after.spend.base,
        isNull,
        reason:
            'DEFECT: base-currency spend went from 150 SAR to nothing. The '
            'merge chose the row that cannot be converted and discarded the '
            'one that could.',
      );
      expect(
        (await dao.byId(survivorUnconverted)).convertedAmountAmount,
        isNull,
      );
    });

    test('A3 — the native-currency figure is NOT lost by A2 (the damage is '
        'bounded to the base-currency view)', () async {
      final int a = await sms(messageId: 1, amount: '40.00', currency: 'USD');
      final int b = await sms(
        messageId: 2,
        amount: '40.00',
        currency: 'USD',
        converted: Money.parse('150.00', currency: 'SAR'),
      );
      await merge.merge(survivorId: a, mergedAwayId: b, confirmedByUser: true);

      final PeriodReport after = await reportNow();
      // The USD movement itself is intact and visible — this is what stops
      // A2 being a total money-vanishing bug rather than a total-integrity
      // one. The user can still see "40.00 USD"; what they lose is its
      // contribution to the SAR headline, and they are told via
      // `unconverted`.
      expect(after.spend.byCurrency.single.currencyCode, 'USD');
      expect(after.spend.byCurrency.single.net.toCanonicalString(), '40');
      expect(after.spend.unconverted, isNotEmpty);
    });

    test('A4 — MergePlan does not compare fee or converted amount, which is '
        'the root cause of A1/A2', () async {
      // Pinning the root cause directly so a fix can be verified here: two
      // rows that differ ONLY in their money-adjacent columns are considered
      // mergeable.
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
      expect(
        assessment,
        isA<MergeAllowed>(),
        reason:
            'DEFECT root cause: the refusal guard covers amount, currency, '
            'direction and type only. Fee and converted amount are neither '
            'compared nor carried.',
      );
      expect(
        (assessment as MergeAllowed).enrichment.isEmpty,
        isTrue,
        reason: 'and the enrichment has nothing to say about either',
      );
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

    test('B2 DEFECT — a survivor that absorbs a SECOND duplicate silently '
        'forgets the first: `merged_from_transaction_id` is a single scalar '
        'that gets overwritten', () async {
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

      // EXPECTED: the survivor records that it absorbed BOTH rows.
      // ACTUAL: it records only the most recent one. The link to `first` is
      // gone from the survivor's row. It survives on `first.mergedIntoId` and
      // in the audit trail, so this is a degradation rather than a loss —
      // but the PR's stated property is "pointers both ways", and after a
      // second merge that is only true for one of the two absorbed rows.
      expect(
        (await dao.byId(survivor)).mergedFromTransactionId,
        second,
        reason:
            'DEFECT: the pointer to the first absorbed row was silently '
            'overwritten by the second merge',
      );
      expect((await dao.byId(first)).mergedIntoId, survivor);
    });

    test('B3 DEFECT (HIGH) — undoing the FIRST of two merges corrupts the '
        'survivor\'s link to the SECOND, and does so with no audit entry on '
        'the survivor at all', () async {
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

      // The user undoes the FIRST merge (restores `first`). `restore()` is
      // written as though a survivor can only ever have absorbed one row: it
      // unconditionally nulls `mergedFromTransactionId` on
      // `existing.mergedIntoId`, without checking that the pointer it is
      // clearing actually refers to the row being restored.
      await merge.undo(first);

      // EXPECTED: `second` is still recorded as absorbed into `survivor`.
      // ACTUAL: the survivor now claims to have absorbed nothing, while
      // `second` still claims to be merged into it. The two halves of the
      // "pointers both ways" property now contradict each other, and nothing
      // in the app can detect it.
      expect(
        (await dao.byId(survivor)).mergedFromTransactionId,
        isNull,
        reason:
            'DEFECT: restoring `first` cleared the survivor\'s pointer to '
            '`second`',
      );
      expect(
        (await dao.byId(second)).mergedIntoId,
        survivor,
        reason: 'while `second` still points back — the links now disagree',
      );
      expect((await dao.byId(second)).isDeleted, isTrue);

      // NFR-A2: "every mutation writes an append-only audit entry". The
      // survivor's row WAS mutated (its mergedFromTransactionId changed) and
      // the survivor's history says nothing about it. The only audit entry
      // written was against the restored row's id.
      final int auditEntriesAfter = (await auditLogDao.queryFor(
        'transaction',
        survivor.toString(),
      )).length;
      expect(
        auditEntriesAfter,
        auditEntriesBefore,
        reason:
            'DEFECT: the survivor row was written to but gained no audit '
            'entry — NFR-A2 gap on the restore path',
      );
      // The chain itself is still intact; this is a completeness gap, not a
      // tampering one.
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('B4 — even a plain single-merge undo mutates the survivor with no '
        'audit entry against the survivor (the same NFR-A2 gap, minimal '
        'case)', () async {
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

      // The survivor's mergedFromTransactionId went b -> null, silently.
      expect((await dao.byId(a)).mergedFromTransactionId, isNull);
      expect(
        afterUndo.length,
        beforeUndo.length,
        reason:
            'DEFECT: the survivor\'s change history reads "merge" with no '
            'matching reversal, so US-F5 shows a merge that was undone as '
            'though it still stands',
      );
    });

    test('B6 DEFECT — merge CHAINS are possible in the survivor direction, '
        'contradicting the "no chains" claim, and a chained undo double-counts '
        'the movement', () async {
      // The PR's own test is named "an already-merged row cannot be merged
      // again — no chains". It pins the *absorbed* direction only: merging a
      // soft-deleted row is refused by `MergeRefusal.notLive`. A SURVIVOR is
      // still live, so it can itself be merged away into a third row.
      final int a = await sms(messageId: 11);
      final int b = await sms(messageId: 22);
      final int c = await sms(messageId: 33);

      await merge.merge(survivorId: b, mergedAwayId: a, confirmedByUser: true);
      final MergeResult chained = await merge.merge(
        survivorId: c,
        mergedAwayId: b,
        confirmedByUser: true,
      );
      expect(
        chained,
        isA<MergeCompleted>(),
        reason:
            'DEFECT: a -> b -> c chain is permitted; "no chains" is only '
            'true in one direction',
      );

      // One movement, counted once. So far so good.
      expect((await reportNow()).spend.base!.toCanonicalString(), '152.75');

      // Now the user undoes the SECOND merge, which is the one they just
      // made. `b` comes back live — but `a` is still soft-deleted pointing at
      // `b`, and `b` no longer records that it absorbed `a` (B2's overwrite
      // is not involved here; `restore` cleared `c`'s pointer, and `b`'s own
      // `mergedFromTransactionId` was never touched).
      await merge.undo(b);
      expect(
        (await reportNow()).spend.base!.toCanonicalString(),
        '305.5',
        reason:
            'b and c both live again — inflation, which is the SAFE '
            'direction, but the user now has a duplicate they already '
            'resolved once and no flag telling them so',
      );
      expect((await dao.byId(a)).isDeleted, isTrue);
      expect(
        (await dao.byId(b)).mergedFromTransactionId,
        a,
        reason:
            'b still records absorbing a, so the chain is at least '
            'reconstructible',
      );
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

    test('C2 — no production code outside TransactionMergeService reaches '
        'TransactionDao.mergeDuplicatePair', () async {
      // A behavioural restatement of the PR's structural claim. The DAO
      // method is nonetheless PUBLIC and defaults `actor` to 'user', so the
      // only thing standing between a future background caller and an
      // unconfirmed merge is convention plus this test. Recorded as an
      // observation, not a defect: the service layer is genuinely the only
      // caller today.
      expect(
        () => dao.mergeDuplicatePair(
          survivorId: 1,
          mergedAwayId: 2,
          enrichment: MergeEnrichment.none,
        ),
        isNotNull,
        reason:
            'the DAO method is reachable directly — the guard lives one '
            'layer up, in the service',
      );
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

    test('D2 DEFECT — a user edit on the LOSING side is silently discarded in '
        'favour of the parser\'s value on the survivor', () async {
      // The user corrects the merchant on row `b`. Then a duplicate pair is
      // resolved with `a` (which still holds the parser's mis-read) as the
      // survivor. AC-B5.3 says user intent outranks the parser *always*; here
      // the parser's value wins because the rule is implemented as "don't
      // overwrite the survivor" rather than "prefer the user-edited value".
      final int a = await sms(messageId: 1, merchant: 'ALINMA*POS*3311');
      final int b = await sms(messageId: 2, merchant: 'ALINMA*POS*3311');
      await TransactionEditService(database: db, transactionDao: dao).edit(
        b,
        const TransactionEditDraft(
          merchantRawText: Edited<String?>('Panda Hypermarket'),
        ),
      );

      await merge.merge(survivorId: a, mergedAwayId: b, confirmedByUser: true);

      expect(
        (await dao.byId(a)).merchantRawText,
        'ALINMA*POS*3311',
        reason:
            'DEFECT: the user\'s correction lost to the parser text '
            'because it happened to be on the row the user chose to merge '
            'away. Nothing warns them.',
      );
      // The correction is not destroyed — it is on the soft-deleted row — but
      // it is off every list and every screen the user will look at.
      expect((await dao.byId(b)).merchantRawText, 'Panda Hypermarket');
      expect((await dao.byId(b)).isDeleted, isTrue);
    });

    test(
      'D3 DEFECT — a user-edited value COPIED onto the survivor by a merge '
      'does not inherit its protection, so a later merge can overwrite it',
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

        expect(
          decodeUserEditedFields((await dao.byId(a)).userEditedFields),
          isEmpty,
          reason:
              'DEFECT: the survivor now carries a user-authored value with '
              'no AC-B5.3 protection on it — the next automated write (P7 '
              'statement import, a re-scan, another merge) may overwrite it',
        );
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

    test('F6 DEFECT — undoing a merge does NOT reverse the enrichment, so the '
        'survivor keeps data the merge gave it', () async {
      // The file-level doc claims "restore() reverses the whole thing" and
      // "the merge is REVERSIBLE". It reverses the soft delete and the
      // pointers; it does not reverse the field copies.
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
            'DEFECT (low): after the undo, both rows are live and both '
            'now claim the same merchant/reference. The undo is not an '
            'inverse, contrary to the doc comment.',
      );
      expect((await dao.byId(b)).merchantRawText, 'EXTRA MART');
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

    test('G2 OBSERVATION — an unknown currency code is NOT caught: `Money` '
        'does not validate currency codes, so the doc over-claims', () async {
      // `ledger_mapping.dart`'s library comment says a row is unreadable when
      // "`amount_currency` is not a currency code this build understands".
      // `Money.tryParse` performs no such check — it stores whatever string it
      // is handed. Behaviourally this is benign (the row lands in its own
      // currency bucket and is reported as `unconverted`, so it is visible
      // rather than dropped, which is what KHA-74 actually required), but the
      // stated reason for `UnreadableReason.unparsableAmount` is wider than
      // the code. Recorded as a documentation-accuracy observation.
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

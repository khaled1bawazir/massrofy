/// **QA adversarial probe suite for PR #24 (P3b-3 — KHA-87/88/89/90).**
///
/// Written by qa-tester against head `8761e3e`, 2026-07-29. This is the
/// SECOND adversarial round on the same merge operation. PR #20's probes are
/// now the inverted/fixed baseline (`qa_pr20_probe_test.dart`), so this file
/// deliberately goes past them and attacks the thing PR #24 newly introduced:
/// the **hybrid** rule "refuse on disagreement, gap-fill on absence" applied to
/// the money-bearing columns.
///
/// The question every probe here asks is one of:
///
///  1. can the gap-fill half of the hybrid be made to **lose** or **wrongly
///     attribute** money, i.e. can the null-detection be fooled?
///  2. does the byte-verbatim `MoneyColumns` copy ever propagate an internally
///     inconsistent triple?
///  3. do the new refusals (chain, transfer verdict, categoryId) actually hold
///     under composition, rather than only in the single-step case the fix's
///     own tests cover?
///
/// A probe named `HOLDS` is evidence the property survives the attack. A probe
/// named `DEFECT` is an executed reproduction of behaviour that contradicts a
/// claim the PR makes.
library;

import 'package:drift/drift.dart' show GeneratedColumn;
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ledger/internal_transfer.dart';
import 'package:massrofy/features/ledger/ledger_mapping.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_merge.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../support/ledger_fixtures.dart';
import '../support/plain_test_database.dart';

final List<int> _qaChainKey = List<int>.generate(32, (int i) => i + 91);

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

  Future<int> sms({
    String amount = '152.75',
    String currency = 'SAR',
    String? merchant,
    Money? fee,
    Money? converted,
    Money? remainingBalance,
    String? fxRate,
    DateTime? fxRateDate,
    String? fxRateSource,
    bool conversionPending = false,
    required int messageId,
  }) => dao.insertFromParsedSms(
    amount: Money.parse(amount, currency: currency),
    convertedAmount: converted,
    feeAmount: fee,
    remainingBalance: remainingBalance,
    fxRate: fxRate,
    fxRateDate: fxRateDate,
    fxRateSource: fxRateSource,
    conversionPending: conversionPending,
    merchantRawText: merchant,
    occurredAt: DateTime.utc(2026, 7, 15, 10),
    direction: 'debit',
    transactionType: TransactionType.posPurchase,
    affectsSpend: true,
    sourceMessageId: messageId,
    rulePackId: 'sa-core',
    rulePackVersion: '2026.07.28',
    ruleId: 'baj-pos-purchase-ar',
  );

  Future<PeriodReport> reportNow() async => LedgerTotals.report(
    toLedgerTransactions(
      (await dao.all()).where((TransactionRow r) => !r.isDeleted),
    ),
    period: july2026,
  );

  // =========================================================================
  // PROBE H — attacking the HYBRID itself (gap-fill vs refuse-on-disagree).
  // =========================================================================
  group('PROBE H — can the gap-fill half lose or misattribute money?', () {
    test('H1 HOLDS — a ZERO fee is a value, not a gap: it is defended from '
        'being overwritten by a non-zero fee (KHA-25)', () async {
      // KHA-25 established that zero is a legitimate, deliberate value that is
      // distinct from "unknown". If `MoneyColumns.read` or the fill helper had
      // used falsiness/emptiness rather than a strict null check, a stored
      // 0.00 fee would look like a gap and 9.20 would be written over it —
      // silently changing a reported figure. This asserts it does not.
      final int survivorZeroFee = await sms(
        messageId: 1,
        fee: Money.parse('0.00', currency: 'SAR'),
      );
      final int otherWithFee = await sms(
        messageId: 2,
        fee: Money.parse('9.20', currency: 'SAR'),
      );

      final MergeAssessment assessment = MergePlan.between(
        survivor: await dao.byId(survivorZeroFee),
        mergedAway: await dao.byId(otherWithFee),
      );
      expect(
        (assessment as MergeRefused).reason,
        MergeRefusal.feeDiffers,
        reason:
            'a stored 0 fee disagrees with a 9.20 fee; it is not an absence '
            'for the enrichment to fill',
      );
      // And the reverse direction is symmetric — 0 must not be treated as a
      // gap when it is on the *incoming* row either.
      final MergeAssessment reversed = MergePlan.between(
        survivor: await dao.byId(otherWithFee),
        mergedAway: await dao.byId(survivorZeroFee),
      );
      expect((reversed as MergeRefused).reason, MergeRefusal.feeDiffers);
    });

    test('H2 HOLDS — the verbatim MoneyColumns copy always moves amount, '
        'currency and minor as ONE consistent unit', () async {
      // The PR justifies copying the ADR-002 triple verbatim (rather than
      // round-tripping through `Money`) on the grounds that a byte-for-byte
      // copy "cannot disagree with what the original write path stored". The
      // risk this probe tests is the opposite one: that a verbatim copy could
      // pair one row's `_minor` with another row's amount, propagating a
      // latent inconsistency instead of catching it.
      //
      // It cannot: `fillMoney` returns the *incoming* MoneyColumns whole or
      // returns null, and the DAO writes all three columns from that single
      // object or leaves all three absent.
      final int plain = await sms(messageId: 1);
      final int rich = await sms(
        messageId: 2,
        fee: Money.parse('9.20', currency: 'SAR'),
        converted: Money.parse('152.75', currency: 'SAR'),
        remainingBalance: Money.parse('1000.00', currency: 'SAR'),
      );
      final TransactionRow source = await dao.byId(rich);

      await merge.merge(
        survivorId: plain,
        mergedAwayId: rich,
        confirmedByUser: true,
      );
      final TransactionRow kept = await dao.byId(plain);

      // Every one of the three triples on the survivor is byte-identical to
      // the source row's, including the derived `_minor`.
      expect(kept.feeAmountAmount, source.feeAmountAmount);
      expect(kept.feeAmountCurrency, source.feeAmountCurrency);
      expect(kept.feeAmountMinor, source.feeAmountMinor);
      expect(kept.convertedAmountAmount, source.convertedAmountAmount);
      expect(kept.convertedAmountCurrency, source.convertedAmountCurrency);
      expect(kept.convertedAmountMinor, source.convertedAmountMinor);
      expect(kept.remainingBalanceAmount, source.remainingBalanceAmount);
      expect(kept.remainingBalanceCurrency, source.remainingBalanceCurrency);
      expect(kept.remainingBalanceMinor, source.remainingBalanceMinor);
    });

    test('H3 DEFECT — a HALF-WRITTEN money triple (amount present, currency '
        'null) reads as an ABSENCE, so the gap-fill silently overwrites a '
        'stored amount', () async {
      // `MoneyColumns.read` returns null when EITHER text column is null, and
      // the fill helper treats that null as a gap. So a row holding
      // `fee_amount_amount = '9.20'` with `fee_amount_currency = NULL` is
      // indistinguishable, to the merge, from a row with no fee at all —
      // and 5.00 is written straight over the 9.20 with no refusal.
      //
      // Reachability: the DAO writes each triple from a `Money?` so all three
      // columns move together; this state is only producible by a raw Drift
      // write (the same residual O-QA-6 identified for negative amounts) or by
      // a future migration that back-fills one column at a time. Recorded
      // because the class doc asserts "half a money triple is not a value"
      // without noting that the *consequence* of that choice is that the
      // stored number becomes overwritable.
      final int survivorHalfTriple = await sms(messageId: 1);
      await db.customStatement(
        'UPDATE transactions SET fee_amount_amount = ?, '
        'fee_amount_currency = NULL WHERE id = ?',
        <Object?>['9.20', survivorHalfTriple],
      );
      final int other = await sms(
        messageId: 2,
        fee: Money.parse('5.00', currency: 'SAR'),
      );

      final MergeAssessment assessment = MergePlan.between(
        survivor: await dao.byId(survivorHalfTriple),
        mergedAway: await dao.byId(other),
      );
      expect(
        assessment,
        isA<MergeAllowed>(),
        reason:
            'DEFECT: the 9.20 on the survivor is not seen as a disagreement',
      );
      await merge.merge(
        survivorId: survivorHalfTriple,
        mergedAwayId: other,
        confirmedByUser: true,
      );
      expect(
        (await dao.byId(survivorHalfTriple)).feeAmountAmount,
        '5',
        reason:
            'DEFECT: 9.20 was overwritten by 5.00 with no refusal. The '
            'enrichment DID overwrite a stored number, which property 3 says '
            'is structurally impossible',
      );
    });

    test('H4 DEFECT — the FX block is carried as FOUR independent gap-fills, '
        'so a survivor can end up with a converted amount and a rate that '
        'contradict each other', () async {
      // `_moneyDisagreement` refuses only when BOTH rows hold the same field.
      // Here neither field collides: the survivor has the converted amount and
      // no rate, the other row has a rate and no converted amount. So the
      // merge is allowed and the rate is gap-filled onto a survivor whose
      // converted figure came from somewhere else entirely.
      //
      // 40.00 USD converted to 150.00 SAR implies a rate of 3.75. The rate
      // being carried is 9.99. After the merge the survivor states both, and
      // nothing in the app reconciles them — AC-B9.3's detail screen shows the
      // user a rate that does not produce the amount printed next to it.
      //
      // Contrast the deliberate care taken with the money triple itself:
      // "each money triple is written whole or not at all ... so a survivor
      // can never end up holding an amount without its currency". The same
      // reasoning is not applied to (converted, rate, rateDate, rateSource).
      final int survivorConverted = await sms(
        messageId: 1,
        amount: '40.00',
        currency: 'USD',
        converted: Money.parse('150.00', currency: 'SAR'),
      );
      final int otherWithRate = await sms(
        messageId: 2,
        amount: '40.00',
        currency: 'USD',
        fxRate: '9.99',
        fxRateDate: DateTime.utc(2026, 7, 20),
        fxRateSource: 'sms_stated',
      );

      final MergeAssessment assessment = MergePlan.between(
        survivor: await dao.byId(survivorConverted),
        mergedAway: await dao.byId(otherWithRate),
      );
      expect(
        assessment,
        isA<MergeAllowed>(),
        reason: 'no single FX field collides, so nothing refuses',
      );

      await merge.merge(
        survivorId: survivorConverted,
        mergedAwayId: otherWithRate,
        confirmedByUser: true,
      );
      final TransactionRow kept = await dao.byId(survivorConverted);
      expect(kept.convertedAmountAmount, '150');
      expect(
        kept.fxRate,
        '9.99',
        reason:
            'DEFECT: 40.00 USD x 9.99 is 399.60, not the 150 SAR stored '
            'beside it. The FX record is now self-contradictory and the '
            'source of each half is different',
      );
      expect(kept.fxRateSource, 'sms_stated');
      // The headline total is unaffected (ADR-009 case 2 prefers the bank's
      // converted figure), so this is a displayed-provenance defect, not a
      // total-corruption one.
      expect((await reportNow()).spend.base!.toCanonicalString(), '150');
    });

    test('H5 DEFECT — a gap-filled fxRate DOES move the base-currency total, '
        'so the FX gap-fill is a money write, not a display detail', () async {
      // Establishes the severity floor for H4: ADR-009 case 3 converts from a
      // stated rate when there is no converted amount, so carrying a rate
      // across is a change to `report.spend.base`. This one is the INTENDED
      // behaviour (it is what makes A3 pass) — it is asserted here to show
      // that the four-independent-gap-fills shape in H4 operates on a value
      // that reaches a headline figure, not merely a label.
      final int survivorNothing = await sms(
        messageId: 1,
        amount: '40.00',
        currency: 'USD',
        conversionPending: true,
      );
      final int otherRateOnly = await sms(
        messageId: 2,
        amount: '40.00',
        currency: 'USD',
        fxRate: '3.75',
        fxRateSource: 'sms_stated',
      );

      expect((await reportNow()).spend.base!.toCanonicalString(), '150');
      await merge.merge(
        survivorId: survivorNothing,
        mergedAwayId: otherRateOnly,
        confirmedByUser: true,
      );
      final PeriodReport after = await reportNow();
      expect(after.spend.base!.toCanonicalString(), '150');
      expect(after.spend.unconverted, isEmpty);
      expect((await dao.byId(survivorNothing)).fxRate, '3.75');
      expect(
        (await dao.byId(survivorNothing)).conversionPending,
        isFalse,
        reason: 'the derived pending flag is recomputed, per A7',
      );
    });

    test('H6 DEFECT — `conversionPending` is cleared by a carried RATE even '
        'when the rate cannot actually convert the row', () async {
      // `conversionPending` is set to false whenever a converted amount OR a
      // rate is carried. But a rate only converts when it is a rate into the
      // base currency. Carry a rate onto a survivor whose currency the rate
      // does not relate to the base and the row now claims it is no longer
      // waiting for a conversion while still contributing nothing to the base
      // total — the row drops off the explicit "N transactions not converted"
      // line that ADR-009 case 4 exists to keep it on.
      //
      // Constructed with a rate string the converter rejects (a rate is parsed
      // with `Decimal.parse`; anything unparseable degrades to "not
      // converted" per NFR-R5) — the same degradation any malformed legacy row
      // would produce.
      final int pending = await sms(
        messageId: 1,
        amount: '40.00',
        currency: 'USD',
        conversionPending: true,
      );
      final int otherBadRate = await dao.insertFromParsedSms(
        amount: Money.parse('40.00', currency: 'USD'),
        fxRate: 'not-a-rate',
        fxRateSource: 'sms_stated',
        occurredAt: DateTime.utc(2026, 7, 15, 10),
        direction: 'debit',
        transactionType: TransactionType.posPurchase,
        affectsSpend: true,
        sourceMessageId: 2,
        rulePackId: 'sa-core',
        rulePackVersion: '2026.07.28',
        ruleId: 'baj-pos-purchase-ar',
      );

      await merge.merge(
        survivorId: pending,
        mergedAwayId: otherBadRate,
        confirmedByUser: true,
      );
      final TransactionRow kept = await dao.byId(pending);
      final PeriodReport after = await reportNow();

      expect(kept.fxRate, 'not-a-rate');
      expect(
        kept.conversionPending,
        isFalse,
        reason:
            'DEFECT: the row stopped claiming it is waiting for a conversion '
            'because a rate string arrived, without checking that the rate '
            'produces one',
      );
      expect(
        after.spend.base,
        isNull,
        reason: 'and it still contributes nothing to the base total',
      );
      expect(
        after.spend.unconverted,
        isNotEmpty,
        reason:
            'the unconverted LINE is derived from the conversion attempt, not '
            'from the flag — which is what keeps this Low rather than a '
            'KHA-74 repeat',
      );
    });
  });

  // =========================================================================
  // PROBE J — composition attacks on the new refusals.
  // =========================================================================
  group('PROBE J — do the new refusals hold under composition?', () {
    test('J1 FIXED (KHA-94/KHA-88) — the chain guard survives the D-QA-7 '
        'pointer overwrite plus an undo: a survivor that still holds an '
        'absorbed row cannot be merged away', () async {
      // `MergeRefusal.chainWouldForm` read ONE scalar,
      // `mergedAway.mergedFromTransactionId`, to decide whether the row had
      // absorbed anything. D-QA-7 means that scalar records only the MOST
      // RECENT merge into that survivor. `restore()`'s identity check then
      // cleared the scalar when the most recent merge was undone — correctly,
      // in isolation — leaving the survivor holding an earlier absorbed row
      // with a null pointer. The guard then saw "absorbed nothing".
      //
      // Two independent changes close it, and the probe checks both:
      //
      //  1. **`restore()` re-points rather than blanks.** The invariant is now
      //     *"the scalar is null iff `absorbedTransactionIds` is empty"*.
      //  2. **The guard asks the authoritative question.**
      //     `TransactionMergeService.merge` queries the `merged_into_id`
      //     back-pointers — the set itself — rather than trusting the cache,
      //     so it holds even if the invariant is broken from outside the DAO.
      final int survivor = await sms(messageId: 11);
      final int first = await sms(messageId: 22);
      final int second = await sms(messageId: 33);
      final int newSurvivor = await sms(messageId: 44);

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
      // The scalar names `second`, the most recent merge. The complete set is
      // both, and is now askable.
      expect((await dao.byId(survivor)).mergedFromTransactionId, second);
      expect(await dao.absorbedTransactionIds(survivor), <int>[second, first]);

      // The user undoes the most recent merge. INVERTED (was: the pointer
      // became null while `first` was still absorbed). It is re-pointed at the
      // earlier merge that genuinely still stands.
      await merge.undo(second);
      expect(
        (await dao.byId(survivor)).mergedFromTransactionId,
        first,
        reason:
            'the survivor still holds `first`, so it must not claim to have '
            'absorbed nothing',
      );
      expect(await dao.absorbedTransactionIds(survivor), <int>[first]);
      expect(
        (await dao.byId(first)).isDeleted,
        isTrue,
        reason: '`first` is still absorbed — nothing undid THAT merge',
      );

      final MergeResult chained = await merge.merge(
        survivorId: newSurvivor,
        mergedAwayId: survivor,
        confirmedByUser: true,
      );
      // INVERTED (was: `isA<MergeCompleted>()`).
      expect(
        (chained as MergeRejected).reason,
        MergeRefusal.chainWouldForm,
        reason:
            'this is the a -> b -> c chain B6 asserts is refused; the guard '
            'must not be blind to it just because an unrelated undo touched '
            'the survivor\'s scalar pointer',
      );

      // The refusal wrote nothing: no chain exists, `survivor` is still live
      // and still holds `first`, and `newSurvivor` gained no link.
      expect((await dao.byId(survivor)).isDeleted, isFalse);
      expect((await dao.byId(survivor)).mergedIntoId, isNull);
      expect((await dao.byId(first)).mergedIntoId, survivor);
      expect((await dao.byId(newSurvivor)).mergedFromTransactionId, isNull);
      // Three live movements now: `survivor`, `second` (restored) and
      // `newSurvivor`.
      expect((await reportNow()).spend.base!.toCanonicalString(), '458.25');
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test(
      'J1b FIXED (KHA-94) — the guard is authoritative, not merely '
      'cache-consistent: a hand-corrupted scalar does not defeat it',
      () async {
        // The invariant `restore()` maintains is what makes the *pure*
        // `MergePlan.between` check sound. This probe removes that invariant by
        // raw SQL — the shape a partially-applied migration, an external DB edit
        // or a future writer with a bug would produce — and asserts the guard
        // still refuses, because `TransactionMergeService.merge` asks the
        // `merged_into_id` back-pointers directly.
        //
        // Two guards on one property, so neither being wrong is sufficient.
        final int survivor = await sms(messageId: 11);
        final int absorbed = await sms(messageId: 22);
        final int newSurvivor = await sms(messageId: 33);

        await merge.merge(
          survivorId: survivor,
          mergedAwayId: absorbed,
          confirmedByUser: true,
        );

        await db.customStatement(
          'UPDATE transactions SET merged_from_transaction_id = NULL '
          'WHERE id = $survivor',
        );
        expect((await dao.byId(survivor)).mergedFromTransactionId, isNull);
        // The authoritative answer disagrees with the corrupted cache…
        expect(await dao.absorbedTransactionIds(survivor), <int>[absorbed]);

        // …and the authoritative answer is the one the guard uses.
        final MergeResult chained = await merge.merge(
          survivorId: newSurvivor,
          mergedAwayId: survivor,
          confirmedByUser: true,
        );
        expect((chained as MergeRejected).reason, MergeRefusal.chainWouldForm);
        expect((await dao.byId(survivor)).isDeleted, isFalse);
        expect(await auditLogDao.verifyChainIntegrity(), isTrue);
      },
    );

    test('J2 HOLDS — three-way merge in the intended order: the RESULT of a '
        'merge can still absorb a third alert', () async {
      // The legitimate three-alert case, one step further than the PR's own
      // test: after `survivor` absorbs `first`, the enriched survivor must
      // still be able to absorb `second` AND keep everything it gained.
      final int survivor = await sms(messageId: 11);
      final int first = await sms(
        messageId: 22,
        fee: Money.parse('9.20', currency: 'SAR'),
      );
      final int second = await sms(messageId: 33, merchant: 'EXTRA MART');

      await merge.merge(
        survivorId: survivor,
        mergedAwayId: first,
        confirmedByUser: true,
      );
      expect(
        await merge.merge(
          survivorId: survivor,
          mergedAwayId: second,
          confirmedByUser: true,
        ),
        isA<MergeCompleted>(),
      );

      final TransactionRow kept = await dao.byId(survivor);
      expect(kept.feeAmountAmount, '9.2', reason: 'gained in merge 1, kept');
      expect(kept.merchantRawText, 'EXTRA MART', reason: 'gained in merge 2');
      // One movement, one fee, counted once.
      expect((await reportNow()).fees.base!.toCanonicalString(), '9.2');
      expect((await reportNow()).spend.base!.toCanonicalString(), '152.75');
    });

    test('J3 HOLDS — a fee carried in merge 1 becomes a real disagreement in '
        'merge 2, so a third alert stating a different fee is refused', () {
      // Composition check on the hybrid: after the survivor absorbs 9.20, it
      // is no longer a gap, so a later alert claiming 5.00 must refuse rather
      // than overwrite. If the carried value did not fully "become" the
      // survivor's own, this would silently take the later figure.
      return () async {
        final int survivor = await sms(messageId: 11);
        final int first = await sms(
          messageId: 22,
          fee: Money.parse('9.20', currency: 'SAR'),
        );
        final int third = await sms(
          messageId: 33,
          fee: Money.parse('5.00', currency: 'SAR'),
        );
        await merge.merge(
          survivorId: survivor,
          mergedAwayId: first,
          confirmedByUser: true,
        );
        final MergeResult later = await merge.merge(
          survivorId: survivor,
          mergedAwayId: third,
          confirmedByUser: true,
        );
        expect((later as MergeRejected).reason, MergeRefusal.feeDiffers);
        expect((await dao.byId(survivor)).feeAmountAmount, '9.2');
      }();
    });

    test('J4 OBSERVATION — undoing a merge that carried money now DOUBLE '
        'COUNTS that money, because the undo deliberately does not '
        'un-enrich (D-QA-12 x KHA-87)', () async {
      // D-QA-12's "keeping the enrichment is the better behaviour" was decided
      // when the enrichment carried five DESCRIPTIVE fields. A duplicated
      // merchant name is harmless; a duplicated fee is a reported figure.
      //
      // This is the safe direction under R-8 (an inflated total is on screen
      // and one tap fixes it) and it is consistent with the amount, which
      // doubles too once both rows are live again. Recorded because the
      // decision's stated rationale does not mention that the class of
      // information it now preserves includes money, and the doc comment
      // reads as though it still only covers "a gap-filled merchant name".
      final int survivor = await sms(messageId: 1);
      final int withFee = await sms(
        messageId: 2,
        fee: Money.parse('9.20', currency: 'SAR'),
      );

      expect((await reportNow()).fees.base!.toCanonicalString(), '9.2');
      await merge.merge(
        survivorId: survivor,
        mergedAwayId: withFee,
        confirmedByUser: true,
      );
      expect((await reportNow()).fees.base!.toCanonicalString(), '9.2');

      await merge.undo(withFee);
      expect(
        (await reportNow()).fees.base!.toCanonicalString(),
        '18.4',
        reason:
            'both rows are live and both now state the 9.20 fee — the undo '
            'did not restore the pre-merge fee total',
      );
      // The amount doubles as well, which is what makes this defensible: the
      // user is looking at two rows again, exactly as they were before.
      expect((await reportNow()).spend.base!.toCanonicalString(), '305.5');
    });

    test('J5 HOLDS — an internal-transfer verdict is carried with its group '
        'id atomically, and a survivor holding its own verdict absorbs '
        'neither half', () async {
      // The pair-or-nothing claim, tested in both directions. Losing
      // `external` deflates nothing but losing `internal` would raise the
      // spend figure, so a half-carried decision is the failure to look for.
      final int survivor = await sms(messageId: 1);
      final int decided = await sms(messageId: 2);
      await dao.setInternalTransferDecision(
        transactionIds: <int>[decided],
        state: InternalTransferState.internal,
        groupId: 'grp-1',
      );

      await merge.merge(
        survivorId: survivor,
        mergedAwayId: decided,
        confirmedByUser: true,
      );
      final TransactionRow kept = await dao.byId(survivor);
      expect(kept.internalTransferState, InternalTransferState.internal);
      expect(
        kept.internalTransferGroupId,
        'grp-1',
        reason: 'the group id travelled with the state, not separately',
      );
      // The user's `internal` verdict now applies to the surviving row, so the
      // movement is out of spend — which is the point of carrying it.
      expect((await reportNow()).spend.base, isNull);
    });

    test('J6 DEFECT (minor) — a survivor holding a verdict with NO group id '
        'does not absorb the group id the other row carries', () async {
      // The carry is gated on `survivor.internalTransferState == null` for
      // BOTH halves. A survivor that has a state but no group id therefore
      // never gains one, even when the absorbed row states the same verdict
      // and knows the group. The survivor is left holding the "half a
      // decision" the doc comment says the pairing exists to prevent.
      final int survivor = await sms(messageId: 1);
      final int decided = await sms(messageId: 2);
      await dao.setInternalTransferDecision(
        transactionIds: <int>[survivor],
        state: InternalTransferState.internal,
      );
      await dao.setInternalTransferDecision(
        transactionIds: <int>[decided],
        state: InternalTransferState.internal,
        groupId: 'grp-1',
      );

      expect(
        await merge.merge(
          survivorId: survivor,
          mergedAwayId: decided,
          confirmedByUser: true,
        ),
        isA<MergeCompleted>(),
        reason: 'same verdict, so no disagreement',
      );
      expect(
        (await dao.byId(survivor)).internalTransferGroupId,
        isNull,
        reason:
            'DEFECT: the group id was a genuine gap on the survivor and the '
            'absorbed row held it, but the carry is gated on the STATE being '
            'null rather than on each half being a gap',
      );
    });

    test('J7 HOLDS — a user-set category on the losing row genuinely refuses '
        'with a reason, and writes nothing', () async {
      // KHA-89's "refuses rather than strands". Re-derived here against the
      // SERVICE (the PR asserts it against the service too, but through
      // `TransactionEditService`) and with the no-mutation half asserted,
      // which the PR's version does only for `isDeleted`.
      final int survivor = await sms(messageId: 1);
      final int categorised = await sms(messageId: 2);
      await dao.applyUserEdit(
        id: categorised,
        categoryId: const Edited<String?>('groceries'),
        actor: 'user',
      );

      final MergeResult result = await merge.merge(
        survivorId: survivor,
        mergedAwayId: categorised,
        confirmedByUser: true,
      );
      expect((result as MergeRejected).reason, MergeRefusal.userEditDiffers);
      // A refusal is not a mutation, on either row.
      expect((await dao.byId(categorised)).isDeleted, isFalse);
      expect((await dao.byId(categorised)).mergedIntoId, isNull);
      expect((await dao.byId(survivor)).mergedFromTransactionId, isNull);
      expect((await dao.byId(survivor)).categoryId, isNull);
      expect(
        await auditLogDao.queryFor('transaction', survivor.toString()),
        hasLength(1),
        reason: 'only the original `create` entry',
      );
    });

    test('J8 DEFECT (minor) — a RULE-assigned category on the losing row is '
        'still silently dropped, because the refusal is gated on the field '
        'being USER-edited', () async {
      // The `refuse rather than strand` rule iterates `incomingProtected`
      // only. A `category_id` that was never a user edit — P4 will assign
      // categories automatically — is neither compared, nor carried, nor
      // refused: exactly the KHA-87 shape, on a non-money column, still
      // present after this fix.
      final int survivor = await sms(messageId: 1);
      final int categorised = await sms(messageId: 2);
      // Written raw, so `user_edited_fields` is NOT touched — this models a
      // category assigned by a rule rather than typed by a person.
      await db.customStatement(
        'UPDATE transactions SET category_id = ? WHERE id = ?',
        <Object?>['groceries', categorised],
      );

      expect(
        await merge.merge(
          survivorId: survivor,
          mergedAwayId: categorised,
          confirmedByUser: true,
        ),
        isA<MergeCompleted>(),
      );
      expect(
        (await dao.byId(survivor)).categoryId,
        isNull,
        reason:
            'DEFECT: the category left the ledger with the soft-deleted row, '
            'with no refusal and no carry',
      );
    });
  });

  // =========================================================================
  // PROBE L — KHA-88's `merge_undo` audit entry: same transaction, real
  // before/after, and not derailable by bad data.
  // =========================================================================
  group('PROBE L — the merge_undo audit entry', () {
    test('L1 HOLDS — the survivor\'s data write and its `merge_undo` entry '
        'share one timestamp, i.e. they came from one operation, and the '
        'entry carries a genuine before/after rather than a stub', () async {
      // NFR-A2's requirement is not merely "an entry exists" — it is that the
      // entry and the mutation it describes cannot drift apart. The code puts
      // both inside one `transaction()` block; this is the behavioural
      // corroboration: the survivor's `updated_at` and the entry's
      // `changed_at` are the same instant, because both are written from the
      // single `timestamp` computed once at the top of `restore()`.
      final int survivor = await sms(messageId: 1);
      final int absorbed = await sms(messageId: 2);
      await merge.merge(
        survivorId: survivor,
        mergedAwayId: absorbed,
        confirmedByUser: true,
      );

      final DateTime undoAt = DateTime.utc(2026, 7, 20, 12, 30);
      await merge.undo(absorbed, now: undoAt);

      final TransactionRow kept = await dao.byId(survivor);
      final List<AuditEntryRow> history = await auditLogDao.queryFor(
        'transaction',
        survivor.toString(),
      );
      final AuditEntryRow undoEntry = history.last;

      expect(undoEntry.action, 'merge_undo');
      expect(kept.mergedFromTransactionId, isNull);
      expect(
        kept.updatedAt.toUtc(),
        undoAt,
        reason: 'the survivor row was written with the operation\'s timestamp',
      );
      expect(
        undoEntry.changedAt.toUtc(),
        undoAt,
        reason:
            'and so was its audit entry — one timestamp, one transaction, so '
            'the row and its history cannot half-commit',
      );
      // A genuine before/after: the id it used to hold, and an explicit null.
      expect(undoEntry.fieldChangesJson, contains('mergedFromTransactionId'));
      expect(undoEntry.fieldChangesJson, contains('"$absorbed"'));
      expect(undoEntry.fieldChangesJson, contains('null'));
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('L2 HOLDS — a DANGLING survivor id does not abort an otherwise valid '
        'undo, and writes no phantom audit entry', () async {
      // The PR claims `getSingleOrNull` (not `getSingle`) so "a dangling id is
      // data we should not crash on". Attacked directly: point a soft-deleted
      // row at a survivor that does not exist, then undo it.
      final int orphan = await sms(messageId: 1);
      await merge.undo(orphan).catchError((Object _) {});
      await db.customStatement(
        'UPDATE transactions SET is_deleted = 1, merged_into_id = 99999 '
        'WHERE id = ?',
        <Object?>[orphan],
      );

      await merge.undo(orphan);
      final TransactionRow restored = await dao.byId(orphan);
      expect(restored.isDeleted, isFalse);
      expect(restored.mergedIntoId, isNull);
      expect(
        await auditLogDao.queryFor('transaction', '99999'),
        isEmpty,
        reason: 'no entry was invented against a row that does not exist',
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });
  });

  // =========================================================================
  // PROBE K — is the KHA-87 "forcing function" really a forcing function?
  // =========================================================================
  group('PROBE K — the anti-regression forcing function', () {
    test('K1 DEFECT — the coverage check is a HAND-WRITTEN list, and a '
        'schema-derived version immediately finds two columns with no '
        'recorded merge decision (`provenance`, `provenance_detail`)', () {
      // KHA-87's done check asks for a test that pins the compared/carried set
      // "so the next column added to `transactions` cannot silently join the
      // 'neither compared nor carried' set". The shipped A8 probe enumerates
      // four columns by hand; adding a fifth to the schema changes nothing
      // about whether A8 passes. The field-vocabulary forcing function in
      // `transaction_merge_test.dart` IS schema-derived, but only over
      // `TransactionField` — the user-editable vocabulary — which contains no
      // money column at all.
      //
      // This is what the real thing looks like: derived from Drift's own
      // column list, so a new column fails it by name until somebody records
      // a decision. Running it on `8761e3e` immediately names two columns
      // nobody has decided about — `provenance` and `provenance_detail`,
      // NFR-A1's "where did this record come from" pair. Neither is money, so
      // this is Low; the point is that the hand-written A8 list could never
      // have surfaced them.
      const Set<String> handled = <String>{
        // compared outright, before enrichment
        'amount_amount', 'amount_currency', 'direction', 'transaction_type',
        // compared AND carried (KHA-87)
        'fee_amount_amount', 'fee_amount_currency', 'fee_amount_minor',
        'converted_amount_amount', 'converted_amount_currency',
        'converted_amount_minor', 'fx_rate', 'fx_rate_date', 'fx_rate_source',
        'remaining_balance_amount', 'remaining_balance_currency',
        'remaining_balance_minor', 'affects_spend', 'internal_transfer_state',
        'internal_transfer_group_id',
        // recomputed derived state
        'conversion_pending',
        // carried descriptive fields
        'merchant_raw_text', 'reference_number', 'counterparty_name',
        'occurred_at', 'instrument_id',
        // P4a (KHA-30/31) — the categorization block. Deliberately neither
        // compared nor carried, and this is a *recorded* decision rather than
        // an omission:
        //
        //  - `category_id` was already on this list, and the merge's own
        //    guard (`transaction_merge.dart`, D-QA-10) **refuses** a merge
        //    whose losing row carries a user category the survivor does not
        //    have, rather than stranding it. P4a leaves that behaviour exactly
        //    as P3b-3 shipped it: refusing asks the user, which is the safe
        //    direction, and rewriting the highest-risk merge path was not
        //    worth the reward of one fewer confirmation.
        //  - `category_source`, `category_confidence` and `category_rule_id`
        //    describe *how* the survivor's own category was decided. Carrying
        //    them from another row would attach the losing row's provenance to
        //    the survivor's category — a statement about a decision that was
        //    never made about it.
        //  - `merchant_id` is derived from `merchant_raw_text`, which the
        //    merge already handles; re-deriving is the categorizer's job, and
        //    copying a merchant identity between rows is the silent merge
        //    AC-D2.3 forbids.
        //
        // None of the four is money, and none can change a total: an
        // uncategorized survivor still appears in the Uncategorized bucket, so
        // AC-C1.3's reconciliation is unaffected either way.
        'category_source', 'category_confidence', 'category_rule_id',
        'merchant_id',
        // KHA-96 / D-QA-20 — the two columns this probe originally surfaced as
        // undecided. The decision is now recorded in `mergeDuplicatePair`: an
        // **explicit noop**, with the absorbed row's value written into the
        // survivor's merge audit entry so NFR-A1 stays answerable. Comparing
        // them would refuse the merge the user most obviously wants (a manual
        // entry plus the bank's later SMS for the same purchase), and carrying
        // them cannot fire at all — `provenance` is NOT NULL with a default, so
        // the survivor never has a gap and a "carry" would be an overwrite,
        // which property 3 forbids outright.
        'provenance', 'provenance_detail',
        // deliberately neither: not money, not a movement identity
        'id', 'amount_minor', 'category_id', 'counterparty_bank_name',
        'time_source', 'instrument_kind', 'instrument_masked_ref',
        'source_message_id', 'rule_pack_id', 'rule_pack_version', 'rule_id',
        'needs_review', 'review_reason', 'possible_duplicate_of_id',
        'merged_into_id', 'merged_from_transaction_id', 'user_edited_fields',
        'is_deleted', 'deleted_at', 'created_at', 'updated_at',
      };
      final Set<String> actual = db.transactions.$columns
          .map((GeneratedColumn<Object> c) => c.name)
          .toSet();
      expect(
        handled.difference(actual),
        isEmpty,
        reason: 'this list has drifted from the schema',
      );
      // INVERTED (was: `<String>{'provenance', 'provenance_detail'}`). With
      // those two decided, this is the forcing function KHA-87's done check
      // asked for: any column added to `transactions` from here on fails this
      // assertion by name until someone records what the merge does with it.
      //
      // The same enumeration now also lives in `transaction_merge_test.dart`,
      // beside the field-vocabulary check, so the forcing function is in the
      // engineer's own suite rather than only in a QA artifact — this copy is
      // kept as the executed audit evidence that the probe was run.
      expect(
        actual.difference(handled),
        isEmpty,
        reason:
            'a column of `transactions` is neither compared, nor carried, nor '
            'on the deliberate-noop list. Decide which it gets, in '
            'transaction_merge.dart — the KHA-87 shape is a MISSING DECISION, '
            'not a missing line of code.',
      );
    });
  });
}

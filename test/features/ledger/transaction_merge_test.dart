/// **ADR-017 D2's enrichment merge.** KHA-64 (second half), AC-A5.2, AC-A5.3,
/// NFR-A2, NFR-A6, risk R-8.
///
/// ---
///
/// This is the highest-risk operation in P3 — *"the only place in the entire
/// product where two records become one"* — so this file is organised around
/// R-8's standard rather than around the code's structure:
///
/// > **Silently deleting a real transaction is worse than an inflated total.**
///
/// Four groups, one per property:
///
///  1. **Never automatic.** A merge without an explicit user confirmation
///     writes nothing, and nothing outside the confirmed service can reach the
///     DAO's merge method.
///  2. **Never destructive.** Both rows survive, both remain traceable to
///     their own source message, and the operation is reversible.
///  3. **Never overwriting.** Enrichment fills gaps only, and never a field
///     the user has edited.
///  4. **Never across different movements.** Two rows that disagree about
///     amount, direction, type, **or any money-bearing column** are refused
///     outright, and a merge cannot build a chain in either direction.
///  5. **Never leaving a column unconsidered** (KHA-87). The last group is a
///     forcing function rather than a behaviour test: it fails when a field
///     is added to the schema's editable vocabulary without a decision about
///     how the merge treats it.
///
/// Group 4 is what stops a mis-tapped merge in the review inbox from making a
/// real purchase disappear into an unrelated one. Group 5 exists because
/// KHA-87's root cause was not a missing line of code but a missing decision:
/// the fee and the converted amount were neither compared nor carried, and
/// nothing anywhere said so out loud.
library;

import 'package:drift/drift.dart' show GeneratedColumn;
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ingestion/duplicate_policy.dart';
import 'package:massrofy/features/ledger/ledger_mapping.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_edit.dart';
import 'package:massrofy/features/ledger/transaction_merge.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../../support/ledger_fixtures.dart';
import '../../support/plain_test_database.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 41);

void main() {
  late AppDatabase db;
  late AuditLogDao auditLogDao;
  late TransactionDao dao;
  late TransactionMergeService service;

  setUp(() {
    db = openPlainTestDatabase();
    auditLogDao = AuditLogDao(db, auditChainKey: _testChainKey);
    dao = TransactionDao(db, auditLogDao);
    service = TransactionMergeService(database: db, transactionDao: dao);
  });

  tearDown(() async => db.close());

  /// The D2 shape: two messages about one movement, one of them terser.
  Future<int> sms({
    String amount = '152.75',
    String? merchant,
    String? reference,
    String direction = 'debit',
    String type = TransactionType.posPurchase,
    required int messageId,
  }) => dao.insertFromParsedSms(
    amount: Money.parse(amount, currency: 'SAR'),
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

  // =========================================================================
  group('R-8 property 1 — a merge is NEVER automatic', () {
    test('confirmedByUser: false writes absolutely nothing', () async {
      final int a = await sms(messageId: 1, merchant: null);
      final int b = await sms(messageId: 2, merchant: 'EXTRA MART');

      final MergeResult result = await service.merge(
        survivorId: a,
        mergedAwayId: b,
        confirmedByUser: false,
      );

      expect(result, isA<MergeNotConfirmed>());
      expect((await dao.byId(b)).isDeleted, isFalse);
      expect((await dao.byId(a)).merchantRawText, isNull);
      expect((await dao.byId(a)).mergedFromTransactionId, isNull);
    });

    test('`DuplicateAction` still has NO delete case — dedup cannot remove a '
        'transaction even in principle', () {
      // KHA-21's done check, restated by KHA-64. This is a structural control:
      // adding a `delete` case would have to happen in duplicate_policy.dart,
      // under the doc comment explaining why it must not, where a reviewer
      // sees it.
      expect(DuplicateAction.values, hasLength(3));
      expect(
        DuplicateAction.values.map((DuplicateAction a) => a.name),
        <String>['accept', 'suppress', 'acceptAndFlag'],
      );
    });

    test('the dedup policy never proposes anything stronger than a flag for a '
        'D2 reference match', () {
      final DuplicateDecision decision = DuplicatePolicy.decide(
        incomingInstrumentRef: '****4821',
        incomingAmount: Money.parse('152.75', currency: 'SAR'),
        incomingOccurredAt: DateTime.utc(2026, 7, 15, 10),
        incomingReferenceNumber: 'REF-9911',
        incomingMerchant: 'EXTRA MART',
        incomingType: TransactionType.posPurchase,
        existing: <DuplicateCandidate>[
          DuplicateCandidate(
            transactionId: 1,
            transactionType: TransactionType.posPurchase,
            instrumentMaskedRef: '****4821',
            amount: Money.parse('152.75', currency: 'SAR'),
            occurredAt: DateTime.utc(2026, 7, 15, 10),
            referenceNumber: 'REF-9911',
          ),
        ],
      );
      expect(decision.tier, DuplicateTier.referenceNumber);
      // Flag, never merge. The merge is the user's to trigger.
      expect(decision.action, DuplicateAction.acceptAndFlag);
    });
  });

  // =========================================================================
  group('R-8 property 2 — a merge NEVER destroys anything', () {
    test('the absorbed row survives, soft-deleted, still carrying its own '
        'source message (NFR-A6: traceable to BOTH messages)', () async {
      final int a = await sms(messageId: 11, merchant: null);
      final int b = await sms(messageId: 22, merchant: 'EXTRA MART');

      await service.merge(
        survivorId: a,
        mergedAwayId: b,
        confirmedByUser: true,
      );

      final TransactionRow survivor = await dao.byId(a);
      final TransactionRow absorbed = await dao.byId(b);

      // Message 11 is reachable from the survivor, message 22 from the
      // absorbed row, and the two rows point at each other. That is the whole
      // of "the merged result remains traceable to both source messages".
      expect(survivor.sourceMessageId, 11);
      expect(absorbed.sourceMessageId, 22);
      expect(survivor.mergedFromTransactionId, b);
      expect(absorbed.mergedIntoId, a);
      expect(absorbed.isDeleted, isTrue);
    });

    test('the period total counts the movement ONCE after the merge, and the '
        'money is not lost', () async {
      final int a = await sms(messageId: 1, amount: '152.75');
      final int b = await sms(messageId: 2, amount: '152.75');

      expect(
        LedgerTotals.spend(
          toLedgerTransactions(await dao.all()),
          period: july2026,
        ).base!.toCanonicalString(),
        '305.5',
        reason:
            'before the merge, the duplicate inflates the total — '
            'visibly, which is the whole ADR-017 bias',
      );

      await service.merge(
        survivorId: a,
        mergedAwayId: b,
        confirmedByUser: true,
      );

      expect(
        LedgerTotals.spend(
          toLedgerTransactions(await dao.all()),
          period: july2026,
        ).base!.toCanonicalString(),
        '152.75',
      );
    });

    test('the merge is REVERSIBLE — undo restores the absorbed row and both '
        'pointers', () async {
      final int a = await sms(messageId: 1);
      final int b = await sms(messageId: 2);
      await service.merge(
        survivorId: a,
        mergedAwayId: b,
        confirmedByUser: true,
      );

      await service.undo(b);

      expect((await dao.byId(b)).isDeleted, isFalse);
      expect((await dao.byId(b)).mergedIntoId, isNull);
      expect((await dao.byId(a)).mergedFromTransactionId, isNull);
      expect(await dao.absorbedTransactionIds(a), isEmpty);
      expect(
        LedgerTotals.spend(
          toLedgerTransactions(await dao.all()),
          period: july2026,
        ).base!.toCanonicalString(),
        '305.5',
      );
    });

    test('KHA-88 / D-QA-7 — the survivor\'s absorbed link is SET-VALUED, and '
        'the scalar column is null exactly when the set is empty', () async {
      // Three alerts for one purchase is ordinary — a POS alert, a "card used"
      // alert and a settlement alert — so a survivor holding two absorbed rows
      // is a normal state that a single scalar column cannot describe.
      //
      // No column was added for this. Each absorbed row already carries
      // `merged_into_id`, so the set was in the schema all along and merely
      // never asked for; `absorbedTransactionIds` asks it. That matters beyond
      // tidiness: `merged_from_transaction_id` is the input to
      // `MergeRefusal.chainWouldForm`, and a lossy input to a safety guard is a
      // defeated guard (KHA-94).
      final int survivor = await sms(messageId: 11);
      final int first = await sms(messageId: 22);
      final int second = await sms(messageId: 33);

      expect(await dao.absorbedTransactionIds(survivor), isEmpty);
      expect((await dao.byId(survivor)).mergedFromTransactionId, isNull);

      await service.merge(
        survivorId: survivor,
        mergedAwayId: first,
        confirmedByUser: true,
      );
      await service.merge(
        survivorId: survivor,
        mergedAwayId: second,
        confirmedByUser: true,
      );

      // Newest first, so `.first` is what the scalar should name.
      expect(await dao.absorbedTransactionIds(survivor), <int>[second, first]);
      expect((await dao.byId(survivor)).mergedFromTransactionId, second);

      // Undoing the MOST RECENT merge re-points the scalar at the earlier one
      // rather than blanking it. Blanking was the bug: the survivor claimed to
      // have absorbed nothing while still holding `first`.
      await service.undo(second);
      expect(await dao.absorbedTransactionIds(survivor), <int>[first]);
      expect((await dao.byId(survivor)).mergedFromTransactionId, first);

      // The audit entry records the genuine new value, not a claim of null, so
      // US-F5 can say "one other duplicate is still merged".
      final AuditEntryRow reversal = (await auditLogDao.queryFor(
        'transaction',
        survivor.toString(),
      )).last;
      expect(reversal.action, 'merge_undo');
      expect(reversal.fieldChangesJson, contains('"$first"'));

      // Undoing the remaining one empties both, together.
      await service.undo(first);
      expect(await dao.absorbedTransactionIds(survivor), isEmpty);
      expect((await dao.byId(survivor)).mergedFromTransactionId, isNull);
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('KHA-96 / O-QA-11 — a merge clears ONLY the review flag that named '
        'this pair; a flag raised by a different question survives', () async {
      // `mergeDuplicatePair` used to write `needsReview: false` on both rows
      // unconditionally, whatever they were flagged for. A survivor flagged as
      // a possible duplicate of a THIRD row, or for an unparsable amount
      // (KHA-74), or as an unproven internal-transfer leg, therefore left the
      // review inbox the moment an unrelated pair was resolved — the inbox
      // quietly losing an item the user was going to be asked about.
      final int survivor = await sms(messageId: 11);
      final int absorbed = await sms(messageId: 22);
      final int third = await sms(messageId: 33, amount: '99.00');

      // The survivor is flagged about a DIFFERENT row.
      await dao.flagAsPossibleDuplicate(
        id: survivor,
        otherId: third,
        reviewReason: 'possible_duplicate',
      );

      await service.merge(
        survivorId: survivor,
        mergedAwayId: absorbed,
        confirmedByUser: true,
      );

      final TransactionRow kept = await dao.byId(survivor);
      expect(
        kept.needsReview,
        isTrue,
        reason:
            'resolving one pair does not answer the question about a third '
            'row — the flag must survive and re-derive',
      );
      expect(kept.reviewReason, 'possible_duplicate');
      expect(kept.possibleDuplicateOfId, third);
      // The merge itself still happened.
      expect(kept.mergedFromTransactionId, absorbed);
    });

    test('KHA-96 / O-QA-11 — the flag that DOES name this pair is cleared on '
        'both rows, so a resolved pair leaves the inbox', () async {
      final int survivor = await sms(messageId: 11);
      final int absorbed = await sms(messageId: 22);
      await dao.flagAsPossibleDuplicate(
        id: survivor,
        otherId: absorbed,
        reviewReason: 'possible_duplicate',
      );
      await dao.flagAsPossibleDuplicate(
        id: absorbed,
        otherId: survivor,
        reviewReason: 'possible_duplicate',
      );

      await service.merge(
        survivorId: survivor,
        mergedAwayId: absorbed,
        confirmedByUser: true,
      );

      expect((await dao.byId(survivor)).needsReview, isFalse);
      expect((await dao.byId(survivor)).reviewReason, isNull);
      expect((await dao.byId(survivor)).possibleDuplicateOfId, isNull);
      // The absorbed row's flag is cleared too. It matters despite the row
      // being soft-deleted: an undo restores it whole, and a question the merge
      // *did* answer should not come back with it.
      expect((await dao.byId(absorbed)).needsReview, isFalse);
    });

    test('KHA-96 / D-QA-20 — a merge across two PROVENANCES keeps the '
        'survivor\'s own and records the absorbed one in the trail', () async {
      // The recorded decision for `provenance` / `provenance_detail`: explicit
      // noop, with the absorbed value written into the survivor's merge audit
      // entry so NFR-A1's "where did this record come from" stays answerable.
      final int survivor = await sms(messageId: 11);
      // A manual entry for the same movement — the case that makes comparing
      // these columns the wrong choice: this is a merge the user obviously
      // wants.
      final int manual = await dao.insertManual(
        amount: Money.parse('152.75', currency: 'SAR'),
        occurredAt: DateTime.utc(2026, 7, 15, 10),
        direction: 'debit',
        transactionType: TransactionType.posPurchase,
        affectsSpend: true,
      );

      expect((await dao.byId(survivor)).provenance, 'sms');
      expect((await dao.byId(manual)).provenance, 'manual');

      expect(
        await service.merge(
          survivorId: survivor,
          mergedAwayId: manual,
          confirmedByUser: true,
        ),
        isA<MergeCompleted>(),
        reason: 'a differing provenance must not refuse the merge',
      );

      // The survivor keeps its own: this method enriches a row, it does not
      // re-create it.
      expect((await dao.byId(survivor)).provenance, 'sms');
      // ...and the absorbed row keeps its own, because nothing is destroyed.
      expect((await dao.byId(manual)).provenance, 'manual');

      // The trail is where the composite fact lives.
      final AuditEntryRow mergeEntry = (await auditLogDao.queryFor(
        'transaction',
        survivor.toString(),
      )).firstWhere((AuditEntryRow e) => e.action == 'merge');
      expect(mergeEntry.fieldChangesJson, contains('absorbedProvenance'));
      expect(mergeEntry.fieldChangesJson, contains('manual'));
    });

    test(
      'both sides keep a full audit trail, and the chain stays intact',
      () async {
        final int a = await sms(messageId: 1, merchant: null);
        final int b = await sms(messageId: 2, merchant: 'EXTRA MART');
        await service.merge(
          survivorId: a,
          mergedAwayId: b,
          confirmedByUser: true,
        );

        expect(
          (await auditLogDao.queryFor(
            'transaction',
            a.toString(),
          )).map((AuditEntryRow e) => e.action),
          <String>['create', 'merge'],
        );
        expect(
          (await auditLogDao.queryFor(
            'transaction',
            b.toString(),
          )).map((AuditEntryRow e) => e.action),
          <String>['create', 'merge'],
        );
        expect(await auditLogDao.verifyChainIntegrity(), isTrue);
      },
    );
  });

  // =========================================================================
  group('R-8 property 3 — enrichment fills gaps, never overwrites', () {
    test('a null field on the survivor is filled from the other row', () async {
      final int a = await sms(messageId: 1, merchant: null, reference: null);
      final int b = await sms(
        messageId: 2,
        merchant: 'EXTRA MART',
        reference: 'REF-9911',
      );

      final MergeResult result = await service.merge(
        survivorId: a,
        mergedAwayId: b,
        confirmedByUser: true,
      );

      expect((result as MergeCompleted).enriched, isTrue);
      final TransactionRow survivor = await dao.byId(a);
      expect(survivor.merchantRawText, 'EXTRA MART');
      expect(survivor.referenceNumber, 'REF-9911');
    });

    test('a NON-null field on the survivor is left alone — two records that '
        'disagree are a question, not a merge input', () async {
      final int a = await sms(messageId: 1, merchant: 'SURVIVOR VALUE');
      final int b = await sms(messageId: 2, merchant: 'OTHER VALUE');

      await service.merge(
        survivorId: a,
        mergedAwayId: b,
        confirmedByUser: true,
      );
      expect((await dao.byId(a)).merchantRawText, 'SURVIVOR VALUE');
    });

    test('a merge that enriches nothing is still a valid merge — removing the '
        'duplicate from the total is the point', () async {
      final int a = await sms(messageId: 1, merchant: 'SAME');
      final int b = await sms(messageId: 2, merchant: 'SAME');

      final MergeResult result = await service.merge(
        survivorId: a,
        mergedAwayId: b,
        confirmedByUser: true,
      );
      expect((result as MergeCompleted).enriched, isFalse);
      expect((await dao.byId(b)).isDeleted, isTrue);
    });

    test('AC-B5.3 — a user-edited field is never enriched over', () async {
      final int a = await sms(messageId: 1, merchant: 'PARSER TEXT');
      await TransactionEditService(database: db, transactionDao: dao).edit(
        a,
        const TransactionEditDraft(
          merchantRawText: Edited<String?>('User corrected'),
        ),
      );
      final int b = await sms(messageId: 2, merchant: 'PARSER TEXT');

      await service.merge(
        survivorId: a,
        mergedAwayId: b,
        confirmedByUser: true,
      );
      expect((await dao.byId(a)).merchantRawText, 'User corrected');
    });

    test('MergeEnrichment cannot express "write null" — a merge is '
        'structurally incapable of deleting information', () {
      // Null in every field means "leave alone"; there is no wrapper that
      // could carry an intentional null. This is the type system holding the
      // R-8 line rather than a code review having to.
      const MergeEnrichment empty = MergeEnrichment();
      expect(empty.isEmpty, isTrue);
      expect(MergeEnrichment.none.isEmpty, isTrue);
    });
  });

  // =========================================================================
  group('R-8 property 4 — two different movements are refused', () {
    test('different amounts are refused (AC-A5.3\'s protection)', () async {
      final int a = await sms(messageId: 1, amount: '152.75');
      final int b = await sms(messageId: 2, amount: '99.00');

      final MergeResult result = await service.merge(
        survivorId: a,
        mergedAwayId: b,
        confirmedByUser: true,
      );
      expect((result as MergeRejected).reason, MergeRefusal.amountDiffers);
      expect((await dao.byId(b)).isDeleted, isFalse);
    });

    test('a debit and a credit are refused — a purchase and its refund are '
        'not duplicates of each other (US-B7)', () async {
      final int a = await sms(messageId: 1, direction: 'debit');
      final int b = await sms(
        messageId: 2,
        direction: 'credit',
        type: TransactionType.refund,
      );

      final MergeResult result = await service.merge(
        survivorId: a,
        mergedAwayId: b,
        confirmedByUser: true,
      );
      // Direction is checked before type, so that is the reason reported.
      expect((result as MergeRejected).reason, MergeRefusal.directionDiffers);
      expect((await dao.byId(b)).isDeleted, isFalse);
    });

    test('different transaction types are refused — merging across types '
        'would silently move money between totals', () async {
      final int a = await sms(messageId: 1, type: TransactionType.posPurchase);
      final int b = await sms(messageId: 2, type: TransactionType.withdrawal);

      final MergeResult result = await service.merge(
        survivorId: a,
        mergedAwayId: b,
        confirmedByUser: true,
      );
      expect((result as MergeRejected).reason, MergeRefusal.typeDiffers);
    });

    test('merging a row with itself is refused', () async {
      final int a = await sms(messageId: 1);
      final MergeResult result = await service.merge(
        survivorId: a,
        mergedAwayId: a,
        confirmedByUser: true,
      );
      expect((result as MergeRejected).reason, MergeRefusal.sameTransaction);
    });

    test('an already-merged row cannot be merged again — no chains, no '
        'resurrection of something that stopped counting', () async {
      final int a = await sms(messageId: 1);
      final int b = await sms(messageId: 2);
      final int c = await sms(messageId: 3);
      await service.merge(
        survivorId: a,
        mergedAwayId: b,
        confirmedByUser: true,
      );

      final MergeResult second = await service.merge(
        survivorId: c,
        mergedAwayId: b,
        confirmedByUser: true,
      );
      expect((second as MergeRejected).reason, MergeRefusal.notLive);
      // b is still merged into a, unchanged.
      expect((await dao.byId(b)).mergedIntoId, a);
    });

    test('...and "no chains" is true in the SURVIVOR direction too — a row '
        'that has absorbed a duplicate cannot itself be merged away '
        '(D-QA-9)', () async {
      // This test's sibling above pins the *absorbed* direction: a
      // soft-deleted row is `notLive`. QA found that the claim in the name —
      // "no chains" — was only half enforced, because a SURVIVOR is still
      // live, so `a -> b` followed by `b -> c` was permitted and orphaned `a`
      // in the middle of the chain.
      //
      // Both directions are asserted, side by side, so a future change cannot
      // satisfy one by breaking the other.
      final int a = await sms(messageId: 1);
      final int b = await sms(messageId: 2);
      final int c = await sms(messageId: 3);

      // b absorbs a, so b is a survivor holding a link.
      expect(
        await service.merge(
          survivorId: b,
          mergedAwayId: a,
          confirmedByUser: true,
        ),
        isA<MergeCompleted>(),
      );

      final MergeResult chained = await service.merge(
        survivorId: c,
        mergedAwayId: b,
        confirmedByUser: true,
      );
      expect((chained as MergeRejected).reason, MergeRefusal.chainWouldForm);

      // Refused means nothing moved: b is live, still records absorbing a, and
      // c gained no link.
      expect((await dao.byId(b)).isDeleted, isFalse);
      expect((await dao.byId(b)).mergedFromTransactionId, a);
      expect((await dao.byId(c)).mergedFromTransactionId, isNull);
    });

    test(
      'a survivor absorbing a SECOND duplicate is still allowed — three '
      'alerts for one purchase is the case the refusal must not catch',
      () async {
        // The chain guard looks at the row being merged *away*, never at the
        // survivor, precisely so this stays legal: a POS alert, a "card used"
        // alert and a settlement alert are three records of one movement.
        final int survivor = await sms(messageId: 1);
        final int first = await sms(messageId: 2);
        final int second = await sms(messageId: 3);

        expect(
          await service.merge(
            survivorId: survivor,
            mergedAwayId: first,
            confirmedByUser: true,
          ),
          isA<MergeCompleted>(),
        );
        expect(
          await service.merge(
            survivorId: survivor,
            mergedAwayId: second,
            confirmedByUser: true,
          ),
          isA<MergeCompleted>(),
        );
        expect((await dao.byId(first)).isDeleted, isTrue);
        expect((await dao.byId(second)).isDeleted, isTrue);
        expect((await dao.byId(survivor)).isDeleted, isFalse);
      },
    );

    test('a missing transaction id is a result, not a crash', () async {
      final int a = await sms(messageId: 1);
      final MergeResult result = await service.merge(
        survivorId: a,
        mergedAwayId: 999999,
        confirmedByUser: true,
      );
      expect(result, isA<MergeTargetMissing>());
    });

    test('a refused merge writes NO audit entry — a refusal is not a '
        'mutation', () async {
      final int a = await sms(messageId: 1, amount: '152.75');
      final int b = await sms(messageId: 2, amount: '99.00');

      await service.merge(
        survivorId: a,
        mergedAwayId: b,
        confirmedByUser: true,
      );

      expect(
        await auditLogDao.queryFor('transaction', a.toString()),
        hasLength(1),
      );
      expect(
        await auditLogDao.queryFor('transaction', b.toString()),
        hasLength(1),
      );
    });
  });

  // =========================================================================
  group('KHA-87 — no field may be "neither compared nor carried"', () {
    test('every user-editable field is either compared outright, carried by '
        'the enrichment, or explicitly refused', () {
      // The root cause of KHA-87 was not a missing line; it was that nothing
      // forced a *decision* about a column. This test is that forcing
      // function, at the field-vocabulary level: adding a value to
      // `TransactionField` without teaching the merge about it fails here,
      // with a message naming the field, rather than shipping as a silent
      // gap-fill hole three releases later.
      //
      // A field may be handled in exactly one of three ways:
      //
      //  - **compared** — a difference makes the two rows different
      //    movements, so `MergePlan.between` refuses long before enrichment
      //    (amount, currency, direction, transactionType);
      //  - **carried** — `MergeEnrichment` can move it, so a user edit on the
      //    absorbed row survives into the survivor's gap;
      //  - **neither** — then a user edit on it must produce
      //    `MergeRefusal.userEditDiffers` rather than being stranded, which is
      //    what `carriableFields` gates.
      const Set<String> comparedOutright = <String>{
        TransactionField.amount,
        TransactionField.currency,
        TransactionField.direction,
        TransactionField.transactionType,
      };
      // The deliberate "neither" list. `categoryId` is here because P4 owns
      // the category tables; when it gains a merge path it moves into
      // `MergePlan.carriableFields` and drops out of here.
      const Set<String> refusedRatherThanCarried = <String>{
        TransactionField.categoryId,
      };

      expect(
        MergePlan.carriableFields.difference(TransactionField.all),
        isEmpty,
        reason: 'carriableFields must name real TransactionField values',
      );
      expect(
        TransactionField.all.difference(<String>{
          ...comparedOutright,
          ...MergePlan.carriableFields,
          ...refusedRatherThanCarried,
        }),
        isEmpty,
        reason:
            'a TransactionField value is handled by none of the three merge '
            'strategies — decide which one it gets, in transaction_merge.dart',
      );
    });

    test('KHA-96 / D-QA-20 — EVERY COLUMN of `transactions`, enumerated from '
        'the schema itself, has a recorded merge decision', () {
      // The sibling test above is a forcing function at the *field-vocabulary*
      // level, and QA verified it works. But `TransactionField` is the
      // user-editable vocabulary and contains **no money column at all**, so
      // KHA-87's own done check — *"the next column added to `transactions`
      // cannot silently join the 'neither compared nor carried' set"* — was
      // being served by a hand-written list of four column names that adding a
      // fifth column would not have disturbed.
      //
      // This is the schema-derived version, promoted here from QA's probe K1.
      // It is driven by `db.transactions.$columns`, so a column added to
      // `transaction_table.dart` fails **by name** until someone writes it into
      // one of the groups below. Run against the tree that shipped P3b-3 it
      // immediately named two columns nobody had decided about (`provenance`,
      // `provenance_detail`) — which is precisely the point: a hand-written
      // list could never have surfaced them.
      //
      // Three legitimate outcomes for a column, and every entry below is in
      // exactly one of them:
      const Set<String> comparedBeforeEnrichment = <String>{
        'amount_amount',
        'amount_currency',
        'direction',
        'transaction_type',
        'affects_spend',
        'internal_transfer_state',
      };
      const Set<String> comparedAndCarried = <String>{
        'fee_amount_amount',
        'fee_amount_currency',
        'fee_amount_minor',
        'converted_amount_amount',
        'converted_amount_currency',
        'converted_amount_minor',
        'fx_rate',
        'fx_rate_date',
        'fx_rate_source',
        'remaining_balance_amount',
        'remaining_balance_currency',
        'remaining_balance_minor',
        'internal_transfer_group_id',
      };
      const Set<String> carried = <String>{
        'merchant_raw_text', 'reference_number', 'counterparty_name',
        'occurred_at', 'instrument_id',
        // Recomputed rather than gap-filled: it is derived state, so a survivor
        // that was waiting for a conversion stops waiting once a merge hands it
        // one. See `MergeEnrichment.conversionPending`.
        'conversion_pending',
      };
      // The deliberate noops. Each of these is a recorded DECISION, and the
      // reason lives at the code that implements it — not here — so this list
      // is a checklist rather than a second copy of the argument.
      const Set<String> deliberateNoop = <String>{
        // P4a's categorization block. `category_id` is *refused* rather than
        // carried when the losing row holds a user category the survivor lacks
        // (the D-QA-10 loop), and the other three describe how the SURVIVOR's
        // own category was decided — carrying them would attach another row's
        // provenance to a decision never made about it.
        'category_id', 'category_source', 'category_confidence',
        'category_rule_id', 'merchant_id',
        // KHA-96 / D-QA-20. NFR-A1's "where did this record come from" pair.
        // The survivor keeps its own: a merge enriches a row, it does not
        // re-create it, so the row was created however it was created. The
        // absorbed row keeps its own too (nothing is destroyed) and the
        // survivor's `merge` audit entry records it when the two differ, so the
        // question stays answerable from the trail. Comparing them would refuse
        // the merge the user most obviously wants — a manual entry plus the
        // bank's later SMS for the same purchase — and carrying them cannot
        // fire, because `provenance` is NOT NULL with a default so the survivor
        // never has a gap.
        'provenance', 'provenance_detail',
        // Identity, bookkeeping and per-row metadata. None of these is money,
        // none is a movement identity, and every one of them is *supposed* to
        // stay attached to the row it describes.
        'id', 'amount_minor', 'counterparty_bank_name', 'time_source',
        'instrument_kind', 'instrument_masked_ref', 'source_message_id',
        'rule_pack_id', 'rule_pack_version', 'rule_id',
        'needs_review', 'review_reason', 'possible_duplicate_of_id',
        'merged_into_id', 'merged_from_transaction_id', 'user_edited_fields',
        'is_deleted', 'deleted_at', 'created_at', 'updated_at',
      };

      final Set<String> decided = <String>{
        ...comparedBeforeEnrichment,
        ...comparedAndCarried,
        ...carried,
        ...deliberateNoop,
      };
      final Set<String> schema = db.transactions.$columns
          .map((GeneratedColumn<Object> column) => column.name)
          .toSet();

      expect(
        decided.difference(schema),
        isEmpty,
        reason:
            'this list names a column that no longer exists — it has drifted '
            'from the schema and is no longer checking what it claims to',
      );
      expect(
        schema.difference(decided),
        isEmpty,
        reason:
            'a column of `transactions` is handled by NONE of the merge\'s '
            'strategies and is on no deliberate-noop list. Decide which one it '
            'gets, in transaction_merge.dart, and add it above. KHA-87\'s root '
            'cause was a missing DECISION, not a missing line of code: the '
            'absorbed row is soft-deleted whole, so an undecided column leaves '
            'the ledger with it.',
      );
    });

    test('a user edit on a field the merge cannot carry is refused, not '
        'stranded on the soft-deleted row', () async {
      final int a = await sms(messageId: 1);
      final int b = await sms(messageId: 2);
      // `a` has no category; `b` has one the user chose. The merge has no way
      // to move it, so it must not proceed as though nothing were lost.
      await TransactionEditService(database: db, transactionDao: dao).edit(
        b,
        const TransactionEditDraft(categoryId: Edited<String?>('groceries')),
      );

      final MergeResult result = await service.merge(
        survivorId: a,
        mergedAwayId: b,
        confirmedByUser: true,
      );
      expect((result as MergeRejected).reason, MergeRefusal.userEditDiffers);
      expect((await dao.byId(b)).isDeleted, isFalse);
    });
  });
}

/// **P3b-2's mutation surface, at the write boundary.** KHA-26, KHA-64,
/// KHA-78, KHA-79.
///
/// The organising question of this file is NFR-A2's: *does every mutation
/// write an append-only audit entry with actor and before/after, inside the
/// same database transaction as the mutation itself?* Every group below asks
/// it of one write path, and the last group asks it of the audit chain as a
/// whole — because an entry that exists but breaks the chain is not evidence
/// of anything.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ledger/internal_transfer.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../../support/plain_test_database.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 11);

void main() {
  late AppDatabase db;
  late AuditLogDao auditLogDao;
  late TransactionDao dao;

  setUp(() {
    db = openPlainTestDatabase();
    auditLogDao = AuditLogDao(db, auditChainKey: _testChainKey);
    dao = TransactionDao(db, auditLogDao);
  });

  tearDown(() async => db.close());

  Future<int> manual({
    String amount = '150.00',
    String currency = 'SAR',
    String direction = 'debit',
    String type = TransactionType.posPurchase,
    String? merchant = 'EXTRA MART',
    int? instrumentId,
    String? reference,
  }) => dao.insertManual(
    amount: Money.parse(amount, currency: currency),
    merchantRawText: merchant,
    occurredAt: DateTime.utc(2026, 7, 15, 10),
    direction: direction,
    transactionType: type,
    affectsSpend: !TransactionType.nonSpendTypes.contains(type),
    instrumentId: instrumentId,
    referenceNumber: reference,
  );

  Future<List<AuditEntryRow>> auditFor(int id) =>
      auditLogDao.queryFor('transaction', id.toString());

  // =========================================================================
  // KHA-79 — the sign-convention guard on create()
  // =========================================================================
  group('KHA-79 — every write path refuses a negative magnitude', () {
    // This test replaces `transaction_dao_test.dart`'s
    // "a negative KWD amount preserves its sign correctly", which was green
    // and pinned the OPPOSITE invariant. Changing it was the point of the
    // issue, not a side effect of it: a guard added while a passing test
    // asserts the guard should not exist is a guard that gets reverted.
    test('create() rejects a negative amount (the gap KHA-79 found)', () {
      // `checkMovementAmount` throws SYNCHRONOUSLY, before the Future is
      // constructed, so this must be `expect(() => ...)` and not
      // `expectLater(future, ...)`. QA flagged this exact trap while writing
      // the reproduction; it is repeated here because the wrong form of this
      // assertion passes vacuously.
      expect(
        () => dao.create(
          amount: Money.parse('-1.500', currency: 'KWD'),
          actor: 'user',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('create() rejecting writes NO row and NO audit entry', () async {
      try {
        await dao.create(
          amount: Money.parse('-50.00', currency: 'SAR'),
          actor: 'user',
        );
      } on ArgumentError {
        // Expected.
      }
      expect(await dao.all(), isEmpty);
      // The original defect's sting was that the bad row came with a
      // *well-formed* audit entry, making it indistinguishable from a
      // legitimate one downstream.
      expect(await auditLogDao.queryFor('transaction', '1'), isEmpty);
    });

    test('create() still accepts zero — a magnitude, not a sign in disguise '
        '(KHA-25: zero and unknown are different facts)', () async {
      final int id = await dao.create(
        amount: Money.parse('0.00', currency: 'SAR'),
        actor: 'user',
      );
      expect((await dao.byId(id)).amountAmount, '0');
    });

    test('insertManual() refuses a negative amount too', () {
      expect(() => manual(amount: '-20.00'), throwsA(isA<ArgumentError>()));
    });

    test('applyUserEdit() refuses to edit an amount to a negative', () async {
      final int id = await manual();
      expect(
        () => dao.applyUserEdit(
          id: id,
          amount: Edited<Money>(Money.parse('-5.00', currency: 'SAR')),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the exception message names the violation and the call site, and '
        'never the figure (NFR-S4)', () {
      try {
        dao.create(
          amount: Money.parse('-999.99', currency: 'SAR'),
          actor: 'user',
        );
        fail('expected an ArgumentError');
      } on ArgumentError catch (error) {
        expect(error.message, contains('create'));
        expect(error.message, contains('negative'));
        // An exception message is a log line waiting to happen.
        expect(error.message, isNot(contains('999.99')));
      }
    });
  });

  // =========================================================================
  // KHA-26 — manual entry (US-B4)
  // =========================================================================
  group('AC-B4.1/B4.3 — insertManual', () {
    test('records provenance `manual` with no source message, which is what '
        'AC-B4.3\'s badge is rendered from', () async {
      final int id = await manual();
      final TransactionRow row = await dao.byId(id);

      expect(row.provenance, 'manual');
      // Not `manual_completion` — that is the hybrid case where a real SMS
      // exists (AC-A4.2). Here there is no message at all.
      expect(row.provenanceDetail, isNull);
      expect(row.sourceMessageId, isNull);
      // Neither SMS time source would be truthful; `received_at_fallback`
      // would be actively wrong, since there was no message to receive.
      expect(row.timeSource, 'user_stated');
    });

    test('cash (no instrument) is a first-class row, not a degraded one '
        '(OQ-19)', () async {
      final int id = await manual(instrumentId: null);
      final TransactionRow row = await dao.byId(id);
      expect(row.instrumentId, isNull);
      expect(row.affectsSpend, isTrue);
      // It is in the live list, so it is in every total computed from it.
      expect(await dao.watchLive().first, hasLength(1));
    });

    test('writes an audit entry with actor `user` and detail `manual_entry` '
        '(NFR-A2)', () async {
      final int id = await manual();
      final List<AuditEntryRow> entries = await auditFor(id);

      expect(entries, hasLength(1));
      expect(entries.single.action, 'create');
      // NFR-A2 distinguishes "the user did this" from "a rule did this".
      expect(entries.single.actor, 'user');
      expect(entries.single.actorDetail, 'manual_entry');

      final List<AuditFieldChange> changes = auditLogDao.decodeFieldChanges(
        entries.single,
      );
      expect(
        changes.map((AuditFieldChange c) => c.field),
        containsAll(<String>['amount', 'currency', 'provenance']),
      );
    });

    test(
      'the amount round-trips as its exact canonical string (NFR-A4)',
      () async {
        final int id = await manual(amount: '1234.567', currency: 'KWD');
        expect((await dao.byId(id)).amountAmount, '1234.567');
        // The non-authoritative `_minor` column uses the currency's REAL
        // exponent (KWD is 3-decimal), never a hard-coded 2.
        expect((await dao.byId(id)).amountMinor, 1234567);
      },
    );
  });

  // =========================================================================
  // KHA-26 — edit (US-B5)
  // =========================================================================
  group('AC-B5.1/B5.2/B5.3 — applyUserEdit', () {
    test(
      'an edited field is written and recorded with a genuine before/after',
      () async {
        final int id = await manual(merchant: 'EXTR4 M4RT');
        await dao.applyUserEdit(
          id: id,
          merchantRawText: const Edited<String?>('EXTRA MART'),
        );

        expect((await dao.byId(id)).merchantRawText, 'EXTRA MART');

        final AuditEntryRow update = (await auditFor(id)).last;
        expect(update.action, 'update');
        expect(update.actor, 'user');
        final AuditFieldChange change = auditLogDao
            .decodeFieldChanges(update)
            .single;
        expect(change.field, TransactionField.merchantRawText);
        // AC-B5.2's "originally detected" value is served from exactly this.
        expect(change.from, 'EXTR4 M4RT');
        expect(change.to, 'EXTRA MART');
      },
    );

    test('AC-B5.3 — the edited field is recorded in user_edited_fields so no '
        'automated write may overwrite it', () async {
      final int id = await manual(merchant: 'EXTR4 M4RT');
      await dao.applyUserEdit(
        id: id,
        merchantRawText: const Edited<String?>('EXTRA MART'),
      );

      final Set<String> protectedFields = decodeUserEditedFields(
        (await dao.byId(id)).userEditedFields,
      );
      expect(protectedFields, <String>{TransactionField.merchantRawText});
    });

    test('Edited(null) CLEARS a field, and is distinguishable from "not '
        'mentioned"', () async {
      final int id = await manual(merchant: 'GHOST MERCHANT');

      // Not mentioned: untouched.
      await dao.applyUserEdit(id: id, categoryId: const Edited<String?>('x'));
      expect((await dao.byId(id)).merchantRawText, 'GHOST MERCHANT');

      // Explicitly cleared.
      await dao.applyUserEdit(
        id: id,
        merchantRawText: const Edited<String?>(null),
      );
      expect((await dao.byId(id)).merchantRawText, isNull);
    });

    test('editing a field to the value it already holds writes nothing — no '
        'row change, no audit entry, no protection', () async {
      final int id = await manual(merchant: 'EXTRA MART');
      final int auditCountBefore = (await auditFor(id)).length;

      await dao.applyUserEdit(
        id: id,
        merchantRawText: const Edited<String?>('EXTRA MART'),
      );

      expect(await auditFor(id), hasLength(auditCountBefore));
      // Crucially the field is NOT marked protected: opening a form and
      // pressing Save is not an expression of intent about ten fields, and
      // treating it as one would freeze the row against all future enrichment.
      expect(
        decodeUserEditedFields((await dao.byId(id)).userEditedFields),
        isEmpty,
      );
    });

    test('several fields changed at once become ONE audit entry with several '
        'field changes', () async {
      final int id = await manual();
      await dao.applyUserEdit(
        id: id,
        merchantRawText: const Edited<String?>('IKEA'),
        transactionType: const Edited<String>(TransactionType.onlinePurchase),
      );

      final AuditEntryRow update = (await auditFor(id)).last;
      expect(auditLogDao.decodeFieldChanges(update), hasLength(2));
      // One user action, one history row — US-F5 is read by a person.
      expect(await auditFor(id), hasLength(2)); // create + this update
    });

    test('editing occurredAt also corrects timeSource, so the row stops '
        'claiming the message stated it', () async {
      final int id = await manual();
      await dao.applyUserEdit(
        id: id,
        occurredAt: Edited<DateTime?>(DateTime.utc(2026, 7, 20, 9)),
      );
      expect((await dao.byId(id)).timeSource, 'user_stated');
    });
  });

  // =========================================================================
  // KHA-26 — soft delete and restore (US-B6, US-B8)
  // =========================================================================
  group('AC-B6/B8 — soft delete and restore', () {
    test('AC-B6.1 — a deleted transaction leaves the live list', () async {
      final int id = await manual();
      expect(await dao.watchLive().first, hasLength(1));

      await dao.softDelete(id: id, actor: 'user');

      expect(await dao.watchLive().first, isEmpty);
      expect(await dao.watchDeleted().first, hasLength(1));
    });

    test('AC-B8.1 — the row is NOT destroyed', () async {
      final int id = await manual();
      await dao.softDelete(id: id, actor: 'user');

      final TransactionRow row = await dao.byId(id);
      expect(row.isDeleted, isTrue);
      // AC-B6.4 wants the *when* readable from the row itself, not only from
      // the audit entry.
      expect(row.deletedAt, isNotNull);
      expect(row.amountAmount, '150');
    });

    test('AC-B8.2 — restoring returns the transaction WITH its full prior '
        'history, because the row id never changed', () async {
      final int id = await manual(merchant: 'ORIGINAL');
      await dao.applyUserEdit(
        id: id,
        merchantRawText: const Edited<String?>('CORRECTED'),
      );
      await dao.softDelete(id: id, actor: 'user');
      await dao.restore(id: id, actor: 'user');

      expect((await dao.byId(id)).isDeleted, isFalse);
      expect((await dao.byId(id)).deletedAt, isNull);
      expect((await dao.byId(id)).merchantRawText, 'CORRECTED');

      // create → update → delete → restore, all against the same entity id.
      // A delete-then-reinsert implementation would have produced a new id
      // and orphaned the first two.
      expect((await auditFor(id)).map((AuditEntryRow e) => e.action), <String>[
        'create',
        'update',
        'delete',
        'restore',
      ]);
    });

    test('the restore audit entry carries an OBSERVED before/after, not a '
        'hard-coded one', () async {
      final int id = await manual();
      await dao.softDelete(id: id, actor: 'user');
      await dao.restore(id: id, actor: 'user');

      final AuditFieldChange change = auditLogDao
          .decodeFieldChanges((await auditFor(id)).last)
          .first;
      expect(change.field, 'isDeleted');
      expect(change.from, 'true');
      expect(change.to, 'false');
    });

    test('AC-B6.4 — the deletion audit entry records actor, timestamp and the '
        'prior value', () async {
      final int id = await manual();
      final DateTime at = DateTime.utc(2026, 7, 20, 8, 30);
      await dao.softDelete(id: id, actor: 'user', now: at);

      final AuditEntryRow entry = (await auditFor(id)).last;
      expect(entry.action, 'delete');
      expect(entry.actor, 'user');
      // Compared in UTC. Drift stores a `DateTimeColumn` as whole Unix
      // seconds and hands it back as a *local* `DateTime`, so comparing the
      // raw value against a UTC literal fails on any machine that is not on
      // UTC — a test that passes in London and fails in Riyadh. The stored
      // instant is identical either way; only the reading's zone differs.
      expect(entry.changedAt.toUtc(), at);
      expect(auditLogDao.decodeFieldChanges(entry).single.from, 'false');
    });
  });

  // =========================================================================
  // KHA-78 — the internal-transfer decision
  // =========================================================================
  group('KHA-78 — setInternalTransferDecision', () {
    test('writes state and group id on BOTH legs, with an audit entry each, '
        'in one database transaction', () async {
      final int out = await manual(type: TransactionType.transferOut);
      final int inbound = await manual(
        type: TransactionType.transferIn,
        direction: 'credit',
      );

      await dao.setInternalTransferDecision(
        transactionIds: <int>[out, inbound],
        state: InternalTransferState.internal,
        groupId: 'itl:$out:$inbound',
      );

      for (final int id in <int>[out, inbound]) {
        final TransactionRow row = await dao.byId(id);
        expect(row.internalTransferState, InternalTransferState.internal);
        expect(row.internalTransferGroupId, 'itl:$out:$inbound');

        final AuditEntryRow entry = (await auditFor(id)).last;
        expect(entry.action, 'update');
        expect(entry.actor, 'user');
        expect(entry.actorDetail, 'internal_transfer_decision');
        expect(
          auditLogDao
              .decodeFieldChanges(entry)
              .map((AuditFieldChange c) => c.field),
          containsAll(<String>[
            'internalTransferState',
            'internalTransferGroupId',
          ]),
        );
      }
    });

    test('the decision clears the review flag — the thing that needed '
        'reviewing has been reviewed', () async {
      final int id = await manual(type: TransactionType.transferOut);
      await dao.flagAsPossibleDuplicate(
        id: id,
        otherId: 999,
        reviewReason: reviewReasonPossibleInternalTransfer,
      );
      expect((await dao.byId(id)).needsReview, isTrue);

      await dao.setInternalTransferDecision(
        transactionIds: <int>[id],
        state: InternalTransferState.external,
      );

      final TransactionRow row = await dao.byId(id);
      expect(row.needsReview, isFalse);
      expect(row.reviewReason, isNull);
    });

    test('a mid-decision failure commits NOTHING — the second leg not '
        'existing rolls the first one back (NFR-R6)', () async {
      final int out = await manual(type: TransactionType.transferOut);

      await expectLater(
        dao.setInternalTransferDecision(
          transactionIds: <int>[out, 999999],
          state: InternalTransferState.internal,
          groupId: 'itl:x',
        ),
        throwsA(anything),
      );

      // The first leg must not have been left decided on its own: a pair
      // half-excluded from spend produces two wrong figures in opposite
      // directions with nothing on screen to explain either.
      expect((await dao.byId(out)).internalTransferState, isNull);
      expect(await auditFor(out), hasLength(1)); // the create only
    });
  });

  // =========================================================================
  // KHA-64 — ADR-017 D2's enrichment merge, at the DAO
  // =========================================================================
  group('KHA-64 / R-8 — mergeDuplicatePair', () {
    test('NOTHING is destroyed: the absorbed row survives, soft-deleted, '
        'pointing at the survivor', () async {
      final int survivor = await manual(merchant: null);
      final int absorbed = await manual(merchant: 'EXTRA MART');

      await dao.mergeDuplicatePair(
        survivorId: survivor,
        mergedAwayId: absorbed,
        actor: 'user',
        enrichment: const MergeEnrichment(merchantRawText: 'EXTRA MART'),
      );

      final TransactionRow away = await dao.byId(absorbed);
      expect(away.isDeleted, isTrue);
      expect(away.mergedIntoId, survivor);
      // R-8: the row and its own source-message reference are still readable.
      expect(away.amountAmount, '150');
    });

    test('the survivor absorbs the missing field and records where it came '
        'from (NFR-A6)', () async {
      final int survivor = await manual(merchant: null, reference: null);
      final int absorbed = await manual(
        merchant: 'EXTRA MART',
        reference: 'REF-9911',
      );

      await dao.mergeDuplicatePair(
        survivorId: survivor,
        mergedAwayId: absorbed,
        actor: 'user',
        enrichment: const MergeEnrichment(
          merchantRawText: 'EXTRA MART',
          referenceNumber: 'REF-9911',
        ),
      );

      final TransactionRow kept = await dao.byId(survivor);
      expect(kept.merchantRawText, 'EXTRA MART');
      expect(kept.referenceNumber, 'REF-9911');
      // The survivor can state its own provenance rather than a report having
      // to go looking for rows that point at it.
      expect(kept.mergedFromTransactionId, absorbed);
    });

    test('BOTH sides get an audit entry — "a merge that loses the merged-away '
        'side\'s history is a defect" (KHA-64)', () async {
      final int survivor = await manual();
      final int absorbed = await manual();

      await dao.mergeDuplicatePair(
        survivorId: survivor,
        mergedAwayId: absorbed,
        actor: 'user',
        enrichment: MergeEnrichment.none,
      );

      expect((await auditFor(survivor)).last.action, 'merge');
      expect((await auditFor(absorbed)).last.action, 'merge');
      expect(
        (await auditFor(survivor)).last.actorDetail,
        'duplicate_merge_survivor',
      );
      expect(
        (await auditFor(absorbed)).last.actorDetail,
        'duplicate_merge_absorbed',
      );
    });

    test('the duplicate flag is cleared on both rows — the question has been '
        'answered', () async {
      final int survivor = await manual();
      final int absorbed = await manual();
      await dao.flagAsPossibleDuplicate(
        id: survivor,
        otherId: absorbed,
        reviewReason: 'possible_duplicate',
      );

      await dao.mergeDuplicatePair(
        survivorId: survivor,
        mergedAwayId: absorbed,
        actor: 'user',
        enrichment: MergeEnrichment.none,
      );

      final TransactionRow kept = await dao.byId(survivor);
      expect(kept.needsReview, isFalse);
      expect(kept.possibleDuplicateOfId, isNull);
    });

    test('restoring the absorbed row UNDOES the merge on both sides', () async {
      final int survivor = await manual();
      final int absorbed = await manual();
      await dao.mergeDuplicatePair(
        survivorId: survivor,
        mergedAwayId: absorbed,
        actor: 'user',
        enrichment: MergeEnrichment.none,
      );

      await dao.restore(id: absorbed, actor: 'user');

      expect((await dao.byId(absorbed)).isDeleted, isFalse);
      expect((await dao.byId(absorbed)).mergedIntoId, isNull);
      expect((await dao.byId(survivor)).mergedFromTransactionId, isNull);
      // The reversal is itself in the history — an undo that left no trace
      // would be its own audit failure.
      expect((await auditFor(absorbed)).last.action, 'restore');
    });

    test(
      'a merge against a non-existent survivor commits nothing (NFR-R6)',
      () async {
        final int absorbed = await manual();

        await expectLater(
          dao.mergeDuplicatePair(
            survivorId: 999999,
            mergedAwayId: absorbed,
            actor: 'user',
            enrichment: MergeEnrichment.none,
          ),
          throwsA(anything),
        );

        expect((await dao.byId(absorbed)).isDeleted, isFalse);
        expect((await dao.byId(absorbed)).mergedIntoId, isNull);
        expect(await auditFor(absorbed), hasLength(1));
      },
    );
  });

  // =========================================================================
  // The audit chain, across the whole surface
  // =========================================================================
  group('NFR-A3 — the hash chain survives every P3b-2 mutation', () {
    test('manual entry, edit, delete, restore, transfer decision and merge '
        'all leave verifyChainIntegrity() true', () async {
      final int a = await manual(merchant: null);
      final int b = await manual(merchant: 'EXTRA MART');

      await dao.applyUserEdit(
        id: a,
        transactionType: const Edited<String>(TransactionType.billPayment),
      );
      await dao.setInternalTransferDecision(
        transactionIds: <int>[a],
        state: InternalTransferState.external,
      );
      await dao.mergeDuplicatePair(
        survivorId: a,
        mergedAwayId: b,
        actor: 'user',
        enrichment: const MergeEnrichment(merchantRawText: 'EXTRA MART'),
      );
      await dao.softDelete(id: a, actor: 'user');
      await dao.restore(id: a, actor: 'user');

      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('the audit trail is still append-only against these new paths — the '
        'SQL triggers hold (ADR-010 layer 2)', () async {
      final int id = await manual();
      expect(await auditFor(id), isNotEmpty);

      await expectLater(
        db.customStatement('DELETE FROM audit_entry;'),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement("UPDATE audit_entry SET actor = 'nobody';"),
        throwsA(anything),
      );
    });
  });
}

/// **US-B5/B6/B8 — edit, soft delete, restore.** KHA-26, AC-B5.1/2/3,
/// AC-B6.1/2/3/4, AC-B8.1/2/3.
///
/// The two tests worth reading first are the AC-B5.3 pair near the bottom.
/// They are the ones that prove *"user intent outranks the parser"* is a
/// property of the data rather than a habit of the code — the merge is made to
/// try to overwrite an edited field, and refuses.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ledger/ledger_mapping.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_edit.dart';
import 'package:massrofy/features/ledger/transaction_merge.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../../support/ledger_fixtures.dart';
import '../../support/plain_test_database.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 31);

void main() {
  late AppDatabase db;
  late AuditLogDao auditLogDao;
  late TransactionDao dao;
  late TransactionEditService service;

  setUp(() {
    db = openPlainTestDatabase();
    auditLogDao = AuditLogDao(db, auditChainKey: _testChainKey);
    dao = TransactionDao(db, auditLogDao);
    service = TransactionEditService(database: db, transactionDao: dao);
  });

  tearDown(() async => db.close());

  /// A row that looks like the parser wrote it, so an "edit" here is genuinely
  /// a user correcting the parser rather than correcting themselves.
  Future<int> parsed({
    String amount = '152.75',
    String? merchant = 'EXTR4 M4RT 0042',
    String? reference,
    int sourceMessageId = 1,
  }) => dao.insertFromParsedSms(
    amount: Money.parse(amount, currency: 'SAR'),
    merchantRawText: merchant,
    occurredAt: DateTime.utc(2026, 7, 15, 10),
    direction: 'debit',
    transactionType: TransactionType.posPurchase,
    affectsSpend: true,
    referenceNumber: reference,
    sourceMessageId: sourceMessageId,
    rulePackId: 'sa-core',
    rulePackVersion: '2026.07.28',
    ruleId: 'baj-pos-purchase-ar',
  );

  group('AC-B5.1 — an edit corrects the value everywhere', () {
    test('correcting a mis-parsed merchant changes it in the ledger and in '
        'every figure derived from it', () async {
      final int id = await parsed(merchant: 'EXTR4 M4RT 0042');

      final TransactionEditResult result = await service.edit(
        id,
        const TransactionEditDraft(
          merchantRawText: Edited<String?>('EXTRA MART'),
        ),
      );

      expect(result, isA<TransactionEditApplied>());
      final LedgerTransaction txn = toLedgerTransactions(
        await dao.all(),
      ).single;
      expect(txn.merchantRawText, 'EXTRA MART');
      // Nothing caches a derived figure (NFR-A6), so "everywhere" needs no
      // invalidation step — this recomputes from the corrected row.
      expect(
        LedgerTotals.spend(<LedgerTransaction>[
          txn,
        ], period: july2026).base!.toCanonicalString(),
        '152.75',
      );
    });

    test('editing the amount changes the period total', () async {
      final int id = await parsed(amount: '152.75');
      await service.edit(
        id,
        const TransactionEditDraft(amountText: Edited<String>('99.00')),
      );

      expect(
        LedgerTotals.spend(
          toLedgerTransactions(await dao.all()),
          period: july2026,
        ).base!.toCanonicalString(),
        '99',
      );
    });

    test('the edited amount is refused if negative — an edit can invert a '
        'movement exactly as an entry can', () async {
      final int id = await parsed();
      final TransactionEditResult result = await service.edit(
        id,
        const TransactionEditDraft(amountText: Edited<String>('-5.00')),
      );

      expect(
        (result as TransactionEditRejected).amountProblem,
        AmountProblemOnEdit.negative,
      );
      expect((await dao.byId(id)).amountAmount, '152.75');
    });

    test('editing a transaction that no longer exists is a result, not a '
        'crash', () async {
      final TransactionEditResult result = await service.edit(
        999999,
        const TransactionEditDraft(
          merchantRawText: Edited<String?>('ANYTHING'),
        ),
      );
      expect(result, isA<TransactionEditTargetMissing>());
    });

    test('saving with nothing changed writes no history entry', () async {
      final int id = await parsed(merchant: 'EXTRA MART');
      final TransactionEditResult result = await service.edit(
        id,
        const TransactionEditDraft(
          merchantRawText: Edited<String?>('EXTRA MART'),
        ),
      );

      expect((result as TransactionEditApplied).changedFields, isEmpty);
      expect(
        await auditLogDao.queryFor('transaction', id.toString()),
        hasLength(1), // the create only
      );
    });
  });

  group('AC-B5.2 — the detail view shows BOTH the original and the edit', () {
    test('the original auto-detected value is recoverable from the audit '
        'trail, with no duplicate column to drift from it', () async {
      final int id = await parsed(merchant: 'EXTR4 M4RT 0042');
      await service.edit(
        id,
        const TransactionEditDraft(
          merchantRawText: Edited<String?>('EXTRA MART'),
        ),
      );

      final TransactionEditHistory history =
          TransactionEditHistory.fromAuditEntries(
            await auditLogDao.queryFor('transaction', id.toString()),
            auditLogDao,
          );

      expect(
        history.originalFor(TransactionField.merchantRawText),
        'EXTR4 M4RT 0042',
      );
      expect((await dao.byId(id)).merchantRawText, 'EXTRA MART');
    });

    test('after THREE edits the "original" is still the parser\'s value, not '
        'the previous edit', () async {
      final int id = await parsed(merchant: 'PARSER VALUE');
      for (final String value in <String>['FIRST', 'SECOND', 'THIRD']) {
        await service.edit(
          id,
          TransactionEditDraft(merchantRawText: Edited<String?>(value)),
        );
      }

      final TransactionEditHistory history =
          TransactionEditHistory.fromAuditEntries(
            await auditLogDao.queryFor('transaction', id.toString()),
            auditLogDao,
          );
      expect(
        history.originalFor(TransactionField.merchantRawText),
        'PARSER VALUE',
      );
    });

    test('a field the user never edited has no "original" — there is one '
        'value, and showing two would be noise', () async {
      final int id = await parsed();
      await service.edit(
        id,
        const TransactionEditDraft(merchantRawText: Edited<String?>('EDITED')),
      );

      final TransactionEditHistory history =
          TransactionEditHistory.fromAuditEntries(
            await auditLogDao.queryFor('transaction', id.toString()),
            auditLogDao,
          );
      expect(history.originalFor(TransactionField.amount), isNull);
    });

    test('a `system_rule` update does not become a claimed "user original" — '
        'that would put words in the user\'s mouth', () async {
      final int id = await parsed();
      await dao.flagAsPossibleDuplicate(
        id: id,
        otherId: 2,
        reviewReason: 'possible_duplicate',
      );

      final TransactionEditHistory history =
          TransactionEditHistory.fromAuditEntries(
            await auditLogDao.queryFor('transaction', id.toString()),
            auditLogDao,
          );
      expect(history.isEmpty, isTrue);
    });
  });

  group('AC-B5.3 — a later automated write must NOT overwrite a user edit', () {
    test(
      'the enrichment merge refuses to fill a field the user has edited, '
      'even when the survivor\'s value would otherwise be replaceable',
      () async {
        // The survivor's merchant was corrected by the user to a deliberately
        // "worse-looking" value. A naive enrichment that preferred a non-null
        // parser value would undo it silently, and the user would never know
        // to look again.
        final int survivor = await parsed(merchant: 'PARSER TEXT');
        await service.edit(
          survivor,
          const TransactionEditDraft(
            merchantRawText: Edited<String?>('My corrected name'),
          ),
        );

        final int other = await parsed(
          merchant: 'PARSER TEXT',
          sourceMessageId: 2,
        );

        final MergeAssessment assessment = MergePlan.between(
          survivor: await dao.byId(survivor),
          mergedAway: await dao.byId(other),
        );
        expect(
          (assessment as MergeAllowed).enrichment.merchantRawText,
          isNull,
          reason: 'a protected field is not copied over, at all',
        );
      },
    );

    test('a user edit that CLEARED a field stays cleared — the merge does not '
        'treat "the user deleted this" as "this is missing"', () async {
      final int survivor = await parsed(merchant: 'WRONG MERCHANT');
      await service.edit(
        survivor,
        const TransactionEditDraft(merchantRawText: Edited<String?>(null)),
      );
      expect((await dao.byId(survivor)).merchantRawText, isNull);

      final int other = await parsed(
        merchant: 'WRONG MERCHANT',
        sourceMessageId: 2,
      );

      final MergeAssessment assessment = MergePlan.between(
        survivor: await dao.byId(survivor),
        mergedAway: await dao.byId(other),
      );
      // The survivor's value IS null, so a null-check alone would happily
      // refill it. The protection list is what stops that.
      expect((assessment as MergeAllowed).enrichment.merchantRawText, isNull);
    });

    test('an UNEDITED null field IS enriched — the protection is targeted, '
        'not a blanket freeze', () async {
      final int survivor = await parsed(merchant: null, reference: null);
      final int other = await parsed(
        merchant: 'EXTRA MART',
        reference: 'REF-42',
        sourceMessageId: 2,
      );

      final MergeAllowed allowed =
          MergePlan.between(
                survivor: await dao.byId(survivor),
                mergedAway: await dao.byId(other),
              )
              as MergeAllowed;
      expect(allowed.enrichment.merchantRawText, 'EXTRA MART');
      expect(allowed.enrichment.referenceNumber, 'REF-42');
    });
  });

  group('AC-B6/B8 — delete and restore through the service', () {
    test('AC-B6.1 — a deleted transaction is out of every total', () async {
      final int id = await parsed(amount: '152.75');
      await service.softDelete(id);

      final PeriodTotals spend = LedgerTotals.spend(
        toLedgerTransactions(await dao.all()),
        period: july2026,
      );
      // Not zero: `PeriodTotals.base` is null when nothing contributed, and
      // null is a different fact from "you spent 0.00" (see period_totals).
      expect(spend.isEmpty, isTrue);
    });

    test(
      'AC-B8.2 — restore brings it back into the total, with its history',
      () async {
        final int id = await parsed(amount: '152.75');
        await service.edit(
          id,
          const TransactionEditDraft(
            merchantRawText: Edited<String?>('CORRECTED'),
          ),
        );
        await service.softDelete(id);
        await service.restore(id);

        expect(
          LedgerTotals.spend(
            toLedgerTransactions(await dao.all()),
            period: july2026,
          ).base!.toCanonicalString(),
          '152.75',
        );
        expect((await dao.byId(id)).merchantRawText, 'CORRECTED');
        // The correction's own history survived the round trip.
        final TransactionEditHistory history =
            TransactionEditHistory.fromAuditEntries(
              await auditLogDao.queryFor('transaction', id.toString()),
              auditLogDao,
            );
        expect(
          history.originalFor(TransactionField.merchantRawText),
          'EXTR4 M4RT 0042',
        );
      },
    );

    test('AC-B8.1 — the deleted row is retained, not destroyed', () async {
      final int id = await parsed();
      await service.softDelete(id);

      // Still addressable, still carrying its source-message reference.
      final TransactionRow row = await dao.byId(id);
      expect(row.isDeleted, isTrue);
      expect(row.sourceMessageId, 1);
    });
  });
}

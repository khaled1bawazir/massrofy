/// **KHA-74 — an unparsable amount must surface, not vanish.** O-QA-1,
/// NFR-A6.
///
/// ---
///
/// The defect QA found by direct SQL manipulation during the P3a adversarial
/// pass: a transaction whose `amount_amount` column cannot be parsed
/// disappeared from every list and every total, with **no error, no flag and
/// no count anywhere**. The user would be shown a smaller number than their
/// real spending and would have no way to discover it.
///
/// NFR-A6 requires every derived figure to trace back to its constituent
/// transactions. A total that quietly excludes one of its constituents does
/// not trace to them; it traces to most of them, which is a different and much
/// less useful property.
///
/// ## Why fix it now, while it is unreachable
///
/// It is reachable today only by editing the database outside the app. The
/// reason to close it in P3b-2 rather than "when it matters" is that P3b-2 is
/// the phase adding write paths — manual entry, the enrichment merge, transfer
/// confirmation — and P7's statement import will add more. A silent-drop
/// behaviour is cheap to fix while it is unreachable and expensive to discover
/// once it is not.
///
/// The tests below construct the corrupt row the same way QA did: by writing
/// the column directly, bypassing `Money` entirely, because that is the only
/// way to produce one.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ledger/ledger_mapping.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../../support/ledger_fixtures.dart';
import '../../support/plain_test_database.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 61);

void main() {
  late AppDatabase db;
  late TransactionDao dao;

  setUp(() {
    db = openPlainTestDatabase();
    dao = TransactionDao(db, AuditLogDao(db, auditChainKey: _testChainKey));
  });

  tearDown(() async => db.close());

  Future<int> healthy({String amount = '100.00'}) => dao.insertManual(
    amount: Money.parse(amount, currency: 'SAR'),
    merchantRawText: 'CORNER SHOP',
    occurredAt: DateTime.utc(2026, 7, 15, 10),
    direction: 'debit',
    transactionType: TransactionType.posPurchase,
    affectsSpend: true,
  );

  /// Corrupts a row's authoritative amount column the only way it can happen:
  /// outside the app's own write path, which always stores
  /// `Money.toCanonicalString()`.
  Future<void> corruptAmount(int id, {String value = 'not-a-number'}) =>
      db.customStatement(
        'UPDATE transactions SET amount_amount = ? WHERE id = ?;',
        <Object?>[value, id],
      );

  group('the row is REPORTED rather than dropped', () {
    test('mapLedgerTransactions returns it as an UnreadableTransaction with '
        'its id and reason', () async {
      final int good = await healthy();
      final int bad = await healthy();
      await corruptAmount(bad);

      final LedgerMappingOutcome outcome = mapLedgerTransactions(
        await dao.all(),
      );

      expect(outcome.transactions, hasLength(1));
      expect(outcome.transactions.single.id, good);
      expect(outcome.hasUnreadable, isTrue);
      expect(outcome.unreadable.single.transactionId, bad);
      expect(
        outcome.unreadable.single.reason,
        UnreadableReason.unparsableAmount,
      );
    });

    test('a healthy ledger reports nothing — the type is not noisy', () async {
      await healthy();
      await healthy(amount: '25.50');

      final LedgerMappingOutcome outcome = mapLedgerTransactions(
        await dao.all(),
      );
      expect(outcome.transactions, hasLength(2));
      expect(outcome.hasUnreadable, isFalse);
    });

    test('an amount whose CURRENCY code is unrecognisable is reported too — '
        'NFR-A5 allows no amount without a valid currency', () async {
      final int bad = await healthy();
      await db.customStatement(
        "UPDATE transactions SET amount_currency = 'XX' WHERE id = ?;",
        <Object?>[bad],
      );

      final LedgerMappingOutcome outcome = mapLedgerTransactions(
        await dao.all(),
      );
      expect(outcome.unreadable.single.transactionId, bad);
    });

    test('the report carries NO amount text — the value is arbitrary stored '
        'bytes and NFR-S4 makes no exception for corrupt ones', () async {
      final int bad = await healthy();
      await corruptAmount(bad, value: 'SECRET-LOOKING-JUNK');

      final UnreadableTransaction reported = mapLedgerTransactions(
        await dao.all(),
      ).unreadable.single;
      expect(reported.toString(), isNot(contains('SECRET-LOOKING-JUNK')));
      expect(reported.toString(), contains('#$bad'));
    });
  });

  group('nothing is repaired, deleted or guessed', () {
    test('the corrupt row is left exactly as found — guessing at what a '
        'corrupted amount meant would be inventing money', () async {
      final int bad = await healthy();
      await corruptAmount(bad);

      mapLedgerTransactions(await dao.all());

      final TransactionRow row = await dao.byId(bad);
      expect(row.amountAmount, 'not-a-number');
      expect(row.isDeleted, isFalse);
    });

    test('the readable rows still produce a correct total — one bad row does '
        'not poison the whole figure', () async {
      await healthy(amount: '100.00');
      await healthy(amount: '25.50');
      final int bad = await healthy(amount: '999.00');
      await corruptAmount(bad);

      final PeriodTotals spend = LedgerTotals.spend(
        toLedgerTransactions(await dao.all()),
        period: july2026,
      );
      expect(spend.base!.toCanonicalString(), '125.5');
    });
  });

  group('the arithmetic path still skips it, and says so out loud', () {
    test('toLedgerTransactions keeps its old behaviour for callers that '
        'genuinely cannot use an unreadable row', () async {
      final int bad = await healthy();
      await corruptAmount(bad);

      // A period total has nothing it can do with a row it cannot read. The
      // change is not that arithmetic now includes it — it is that the
      // omission is now *reported* by `mapLedgerTransactions`, which the
      // review inbox renders, instead of being invisible.
      expect(toLedgerTransactions(await dao.all()), isEmpty);
      expect(mapLedgerTransactions(await dao.all()).unreadable, hasLength(1));
    });

    test('several corrupt rows are all reported, not just the first', () async {
      final int a = await healthy();
      final int b = await healthy();
      await corruptAmount(a);
      await corruptAmount(b, value: '');

      expect(
        mapLedgerTransactions(await dao.all()).unreadable
            .map((UnreadableTransaction u) => u.transactionId)
            .toList()
          ..sort(),
        <int>[a, b],
      );
    });
  });
}

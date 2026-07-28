/// The bank/instrument DAOs against a real database — KHA-23.
///
/// Covers AC-B12.1, AC-B12.3 (at the storage layer), AC-B13.1/2, AC-B14.1,
/// AC-B14.3, AC-B15.1, AC-B3.1, AC-B3.2, and NFR-A2's requirement that every
/// mutation leaves an append-only audit entry.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/bank_dao.dart';
import 'package:massrofy/data/dao/instrument_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';

import '../../support/plain_test_database.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 7);

void main() {
  late AppDatabase db;
  late AuditLogDao auditLogDao;
  late BankDao bankDao;
  late InstrumentDao instrumentDao;

  setUp(() {
    db = openPlainTestDatabase();
    auditLogDao = AuditLogDao(db, auditChainKey: _testChainKey);
    bankDao = BankDao(db, auditLogDao);
    instrumentDao = InstrumentDao(db, auditLogDao);
  });

  tearDown(() async => db.close());

  Future<int> ensureAljazira() => bankDao.ensure(
    canonicalKey: 'bank-aljazira',
    displayNameAr: 'بنك الجزيرة',
    displayNameEn: 'Bank Aljazira',
    aliases: const <String>['BAJ', 'ALJAZIRA'],
  );

  group('AC-B12.1 / AC-B15.1 — auto-creation on first mention', () {
    test(
      'the first mention creates the bank; there is no setup step',
      () async {
        final int id = await ensureAljazira();
        final BankRow? row = await bankDao.byCanonicalKey('bank-aljazira');

        expect(row, isNotNull);
        expect(row!.id, id);
        expect(row.displayNameEn, 'Bank Aljazira');
        expect(row.source, 'rule_pack');
      },
    );

    test('AC-B12.3 — repeated mentions resolve to the SAME row, never a '
        'second bank', () async {
      final int first = await ensureAljazira();
      final int second = await ensureAljazira();
      final int third = await bankDao.ensure(
        canonicalKey: 'bank-aljazira',
        // A different display name arriving later must not fork the entity —
        // identity is the canonical key, never the display string.
        displayNameAr: 'الجزيرة',
        displayNameEn: 'BAJ',
      );

      expect(first, second);
      expect(second, third);
      expect((await bankDao.all()).length, 1);
    });

    test('aliases round-trip through the JSON column', () async {
      await ensureAljazira();
      final BankRow row = (await bankDao.byCanonicalKey('bank-aljazira'))!;
      expect(bankDao.decodeAliases(row), <String>['BAJ', 'ALJAZIRA']);
    });

    test('NFR-A2 — creating a bank writes one append-only audit entry, and '
        'creating it again writes none', () async {
      final int id = await ensureAljazira();
      await ensureAljazira();

      final List<AuditEntryRow> entries = await auditLogDao.queryFor(
        'bank',
        id.toString(),
      );
      expect(entries.length, 1);
      expect(entries.single.action, 'create');
      expect(entries.single.actor, 'parser');
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });
  });

  group('instruments — AC-B13.1/2, AC-B15.1', () {
    test('an account and a card with the same last four coexist as two rows '
        'under one bank', () async {
      final int bankId = await ensureAljazira();

      final int accountId = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.account,
        maskedIdentifier: '****4821',
        refKey: 'bank-aljazira:account:4821',
      );
      final int cardId = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.card,
        maskedIdentifier: '****4821',
        refKey: 'bank-aljazira:card:4821',
        network: 'mada',
      );

      expect(accountId, isNot(cardId));
      expect((await instrumentDao.forBank(bankId)).length, 2);
    });

    test('a second mention of the same instrument resolves, it does not '
        'duplicate', () async {
      final int bankId = await ensureAljazira();
      final int first = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.card,
        maskedIdentifier: '****4821',
        refKey: 'bank-aljazira:card:4821',
      );
      final int second = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.card,
        maskedIdentifier: '****4821',
        refKey: 'bank-aljazira:card:4821',
      );

      expect(first, second);
      expect((await instrumentDao.all()).length, 1);
    });

    test('a later message fills in a field the first one did not state, but '
        'never overwrites one it did', () async {
      final int bankId = await ensureAljazira();
      final int id = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.card,
        maskedIdentifier: '****4821',
        refKey: 'bank-aljazira:card:4821',
      );

      await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.card,
        maskedIdentifier: '****4821',
        refKey: 'bank-aljazira:card:4821',
        network: 'mada',
      );
      expect((await instrumentDao.byId(id)).network, 'mada');

      // A contradicting later observation. The first stands: message arrival
      // order must not decide what the record says.
      await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.card,
        maskedIdentifier: '****4821',
        refKey: 'bank-aljazira:card:4821',
        network: 'visa',
      );
      expect((await instrumentDao.byId(id)).network, 'mada');
    });

    test(
      'the instrument cannot be orphaned — the foreign key is real',
      () async {
        // A bank id that does not exist. `PRAGMA foreign_keys = ON` is set on
        // every connection, so this is rejected by SQLite rather than by
        // application code that could be bypassed.
        await expectLater(
          instrumentDao.ensure(
            bankId: 9999,
            kind: InstrumentKind.card,
            maskedIdentifier: '****0000',
            refKey: 'ghost:card:0000',
          ),
          throwsA(anything),
        );
      },
    );
  });

  group('US-B3 — friendly names', () {
    test('AC-B3.1/B3.2 — a rename changes the label and NOT the match key, so '
        'the next message attaches to the renamed instrument', () async {
      final int bankId = await ensureAljazira();
      final int id = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.card,
        maskedIdentifier: '****4821',
        refKey: 'bank-aljazira:card:4821',
      );

      await instrumentDao.rename(id: id, newName: 'Blue Visa');
      expect((await instrumentDao.byId(id)).friendlyName, 'Blue Visa');

      // The "later SMS carrying that instrument's raw identifier" of AC-B3.2.
      final int resolved = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.card,
        maskedIdentifier: '****4821',
        refKey: 'bank-aljazira:card:4821',
      );

      expect(resolved, id, reason: 'AC-B3.2 — no new instrument was created');
      expect(
        (await instrumentDao.byId(id)).friendlyName,
        'Blue Visa',
        reason: 'and the user edit survived re-ingestion',
      );
      expect((await instrumentDao.all()).length, 1);
    });

    test('clearing the name returns the instrument to being labelled by its '
        'masked identifier (AC-B15.2)', () async {
      final int bankId = await ensureAljazira();
      final int id = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.card,
        maskedIdentifier: '****4821',
        refKey: 'bank-aljazira:card:4821',
      );

      await instrumentDao.rename(id: id, newName: 'Blue Visa');
      await instrumentDao.rename(id: id, newName: '   ');

      expect((await instrumentDao.byId(id)).friendlyName, isNull);
    });

    test('NFR-A2 — a rename writes a before/after audit entry with actor '
        'user', () async {
      final int bankId = await ensureAljazira();
      final int id = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.card,
        maskedIdentifier: '****4821',
        refKey: 'bank-aljazira:card:4821',
      );
      await instrumentDao.rename(id: id, newName: 'Blue Visa');

      final List<AuditEntryRow> entries = await auditLogDao.queryFor(
        'instrument',
        id.toString(),
      );
      final AuditEntryRow renameEntry = entries.last;
      final List<AuditFieldChange> changes = auditLogDao.decodeFieldChanges(
        renameEntry,
      );

      expect(renameEntry.actor, 'user');
      expect(renameEntry.actorDetail, 'rename');
      expect(changes.single.field, 'friendlyName');
      expect(changes.single.from, isNull);
      expect(changes.single.to, 'Blue Visa');
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('renaming to the same value writes no audit entry — the history '
        'stays readable', () async {
      final int bankId = await ensureAljazira();
      final int id = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.card,
        maskedIdentifier: '****4821',
        refKey: 'bank-aljazira:card:4821',
      );
      await instrumentDao.rename(id: id, newName: 'Blue Visa');
      await instrumentDao.rename(id: id, newName: 'Blue Visa');

      final List<AuditEntryRow> entries = await auditLogDao.queryFor(
        'instrument',
        id.toString(),
      );
      expect(entries.length, 2); // create + one rename
    });
  });

  group('US-B14 — the card to settlement-account link', () {
    late int bankId;
    late int cardId;
    late int accountId;

    setUp(() async {
      bankId = await ensureAljazira();
      cardId = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.card,
        maskedIdentifier: '****4821',
        refKey: 'bank-aljazira:card:4821',
      );
      accountId = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.account,
        maskedIdentifier: '****3388',
        refKey: 'bank-aljazira:account:3388',
      );
    });

    test(
      'AC-B14.3 — with no repayment message seen, the link stays null',
      () async {
        expect((await instrumentDao.byId(cardId)).settlementAccountId, isNull);
        expect((await instrumentDao.byId(cardId)).linkSource, isNull);
      },
    );

    test('AC-B14.1 — a repayment observation records the link and its '
        'source', () async {
      final bool changed = await instrumentDao.linkSettlementAccount(
        cardId: cardId,
        accountId: accountId,
        linkSource: InstrumentLinkSource.smsRepayment,
      );

      final InstrumentRow card = await instrumentDao.byId(cardId);
      expect(changed, isTrue);
      expect(card.settlementAccountId, accountId);
      expect(card.linkSource, InstrumentLinkSource.smsRepayment);
      expect(card.linkObservedAt, isNotNull);
    });

    test('a contradicting SMS observation does not overwrite an existing '
        'link', () async {
      final int otherAccount = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.account,
        maskedIdentifier: '****9999',
        refKey: 'bank-aljazira:account:9999',
      );

      await instrumentDao.linkSettlementAccount(
        cardId: cardId,
        accountId: accountId,
        linkSource: InstrumentLinkSource.smsRepayment,
      );
      final bool changed = await instrumentDao.linkSettlementAccount(
        cardId: cardId,
        accountId: otherAccount,
        linkSource: InstrumentLinkSource.smsRepayment,
      );

      expect(changed, isFalse);
      expect((await instrumentDao.byId(cardId)).settlementAccountId, accountId);
    });

    test('the user always outranks an SMS observation', () async {
      final int otherAccount = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.account,
        maskedIdentifier: '****9999',
        refKey: 'bank-aljazira:account:9999',
      );

      await instrumentDao.linkSettlementAccount(
        cardId: cardId,
        accountId: accountId,
        linkSource: InstrumentLinkSource.smsRepayment,
      );
      await instrumentDao.linkSettlementAccount(
        cardId: cardId,
        accountId: otherAccount,
        linkSource: InstrumentLinkSource.user,
      );

      final InstrumentRow card = await instrumentDao.byId(cardId);
      expect(card.settlementAccountId, otherAccount);
      expect(card.linkSource, InstrumentLinkSource.user);
    });

    test('NFR-A2 — the link is audited with a before/after', () async {
      await instrumentDao.linkSettlementAccount(
        cardId: cardId,
        accountId: accountId,
        linkSource: InstrumentLinkSource.smsRepayment,
      );

      final List<AuditEntryRow> entries = await auditLogDao.queryFor(
        'instrument',
        cardId.toString(),
      );
      final AuditEntryRow linkEntry = entries.last;
      final AuditFieldChange change = auditLogDao
          .decodeFieldChanges(linkEntry)
          .single;

      expect(linkEntry.actorDetail, 'settlement_link');
      expect(change.field, 'settlementAccountId');
      expect(change.from, isNull);
      expect(change.to, accountId.toString());
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });
  });
}

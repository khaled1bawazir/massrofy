/// The resolver that turns parsed fields into rows in the tree — KHA-23.
///
/// AC-B12.1, AC-B13.1, AC-B13.2, AC-B14.1, AC-B14.3, AC-B15.1, AC-B1.3.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/bank_dao.dart';
import 'package:massrofy/data/dao/instrument_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ledger/bank_directory.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';
import 'package:massrofy/features/ledger/ledger_entity_resolver.dart';
import 'package:massrofy/features/parsing/parsed_fields.dart';

import '../../support/plain_test_database.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 11);

final BankDirectory _directory = BankDirectory(const <BankProfile>[
  BankProfile(
    canonicalKey: 'bank-aljazira',
    displayNameAr: 'بنك الجزيرة',
    displayNameEn: 'Bank Aljazira',
    aliases: <String>['BAJ'],
  ),
]);

void main() {
  late AppDatabase db;
  late BankDao bankDao;
  late InstrumentDao instrumentDao;
  late LedgerEntityResolver resolver;

  setUp(() {
    db = openPlainTestDatabase();
    final AuditLogDao auditLogDao = AuditLogDao(
      db,
      auditChainKey: _testChainKey,
    );
    bankDao = BankDao(db, auditLogDao);
    instrumentDao = InstrumentDao(db, auditLogDao);
    resolver = LedgerEntityResolver(
      bankDao: bankDao,
      instrumentDao: instrumentDao,
      directory: _directory,
    );
  });

  tearDown(() async => db.close());

  group('AC-B15.1 / AC-B12.1 — the whole tree appears from one message', () {
    test(
      'a purchase creates the bank and the card, with no setup step',
      () async {
        final ResolvedLedgerEntities entities = await resolver
            .resolveForMessage(
              bankCanonicalKey: 'bank-aljazira',
              fields: ParsedFields(
                amount: Money.parse('152.75', currency: 'SAR'),
                instrument: const InstrumentReference(
                  kind: InstrumentKind.card,
                  maskedIdentifier: '****4821',
                  network: 'mada',
                ),
              ),
              firstSeenMessageId: 7,
            );

        expect(entities.bankId, isNotNull);
        expect(entities.instrumentId, isNotNull);

        final BankRow bank = (await bankDao.byCanonicalKey('bank-aljazira'))!;
        expect(bank.displayNameEn, 'Bank Aljazira');
        expect(bank.firstSeenMessageId, 7);

        final InstrumentRow card = await instrumentDao.byId(
          entities.instrumentId!,
        );
        expect(card.kind, InstrumentKind.card);
        expect(card.maskedIdentifier, '****4821');
        expect(card.network, 'mada');
        expect(card.firstSeenMessageId, 7);
      },
    );

    test('a bank no active pack declares is still created, labelled by its '
        'key — a swapped pack must not lose a transaction', () async {
      final ResolvedLedgerEntities entities = await resolver.resolveForMessage(
        bankCanonicalKey: 'bank-retired',
        fields: const ParsedFields(),
      );

      final BankRow bank = (await bankDao.byCanonicalKey('bank-retired'))!;
      expect(entities.bankId, bank.id);
      expect(bank.displayNameEn, 'bank-retired');
    });
  });

  group(
    'AC-B13.1 / AC-B13.2 — the kind comes from the rule, never a guess',
    () {
      test('an account reference and a card reference with the same last four '
          'produce two instruments', () async {
        await resolver.resolveForMessage(
          bankCanonicalKey: 'bank-aljazira',
          fields: const ParsedFields(
            instrument: InstrumentReference(
              kind: InstrumentKind.account,
              maskedIdentifier: '****4821',
            ),
          ),
        );
        await resolver.resolveForMessage(
          bankCanonicalKey: 'bank-aljazira',
          fields: const ParsedFields(
            instrument: InstrumentReference(
              kind: InstrumentKind.card,
              maskedIdentifier: '****4821',
            ),
          ),
        );

        final List<InstrumentRow> all = await instrumentDao.all();
        expect(all.length, 2);
        expect(all.map((InstrumentRow r) => r.kind).toSet(), <String>{
          InstrumentKind.account,
          InstrumentKind.card,
        });
      });
    },
  );

  group('AC-B1.3 — when there is no instrument, there is no instrument', () {
    test('a message naming none resolves the bank and leaves the instrument '
        'null', () async {
      final ResolvedLedgerEntities entities = await resolver.resolveForMessage(
        bankCanonicalKey: 'bank-aljazira',
        fields: const ParsedFields(),
      );

      expect(entities.bankId, isNotNull);
      expect(entities.instrumentId, isNull);
      expect(await instrumentDao.all(), isEmpty);
    });

    test(
      'an identifier with too few digits to key on creates nothing',
      () async {
        final ResolvedLedgerEntities entities = await resolver
            .resolveForMessage(
              bankCanonicalKey: 'bank-aljazira',
              fields: const ParsedFields(
                instrument: InstrumentReference(
                  kind: InstrumentKind.card,
                  maskedIdentifier: '****',
                ),
              ),
            );

        expect(entities.instrumentId, isNull);
        expect(await instrumentDao.all(), isEmpty);
      },
    );

    test('a kind this build does not recognise creates nothing rather than a '
        'mystery instrument', () async {
      final ResolvedLedgerEntities entities = await resolver.resolveForMessage(
        bankCanonicalKey: 'bank-aljazira',
        fields: const ParsedFields(
          instrument: InstrumentReference(
            kind: 'wallet',
            maskedIdentifier: '****4821',
          ),
        ),
      );

      expect(entities.instrumentId, isNull);
      expect(await instrumentDao.all(), isEmpty);
    });
  });

  group('AC-B14.1 — the card-repayment link', () {
    test('a repayment naming a card and an account links them, and records '
        'the source as the SMS', () async {
      final ResolvedLedgerEntities entities = await resolver.resolveForMessage(
        bankCanonicalKey: 'bank-aljazira',
        fields: const ParsedFields(
          instrument: InstrumentReference(
            kind: InstrumentKind.card,
            maskedIdentifier: '****4821',
          ),
          settlementInstrument: InstrumentReference(
            kind: InstrumentKind.account,
            maskedIdentifier: '****3388',
          ),
        ),
        observedAt: DateTime.utc(2026, 7, 20, 8),
      );

      final InstrumentRow card = await instrumentDao.byId(
        entities.instrumentId!,
      );
      expect(card.settlementAccountId, entities.settlementInstrumentId);
      expect(card.linkSource, InstrumentLinkSource.smsRepayment);
      // Drift stores a DateTimeColumn as a Unix timestamp and hands it back
      // in the local zone rather than tagged UTC, so "the same instant" is
      // asserted through `.toUtc()` on both sides (the same convention
      // `audit_log_dao_test.dart` documents).
      expect(card.linkObservedAt!.toUtc(), DateTime.utc(2026, 7, 20, 8));
    });

    test('a message naming two ACCOUNTS creates no settlement link — it says '
        'nothing about card settlement', () async {
      final ResolvedLedgerEntities entities = await resolver.resolveForMessage(
        bankCanonicalKey: 'bank-aljazira',
        fields: const ParsedFields(
          instrument: InstrumentReference(
            kind: InstrumentKind.account,
            maskedIdentifier: '****3388',
          ),
          settlementInstrument: InstrumentReference(
            kind: InstrumentKind.account,
            maskedIdentifier: '****9999',
          ),
        ),
      );

      final InstrumentRow primary = await instrumentDao.byId(
        entities.instrumentId!,
      );
      expect(primary.settlementAccountId, isNull);
    });

    test('AC-B14.3 — an ordinary purchase leaves the link null', () async {
      final ResolvedLedgerEntities entities = await resolver.resolveForMessage(
        bankCanonicalKey: 'bank-aljazira',
        fields: const ParsedFields(
          instrument: InstrumentReference(
            kind: InstrumentKind.card,
            maskedIdentifier: '****4821',
          ),
        ),
      );

      final InstrumentRow card = await instrumentDao.byId(
        entities.instrumentId!,
      );
      expect(card.settlementAccountId, isNull);
      expect(card.linkSource, isNull);
    });
  });

  group('idempotence — this runs on every message', () {
    test('resolving the same message shape twenty times leaves one bank and '
        'one instrument', () async {
      for (int i = 0; i < 20; i++) {
        await resolver.resolveForMessage(
          bankCanonicalKey: 'bank-aljazira',
          fields: const ParsedFields(
            instrument: InstrumentReference(
              kind: InstrumentKind.card,
              maskedIdentifier: '****4821',
            ),
          ),
        );
      }

      expect((await bankDao.all()).length, 1);
      expect((await instrumentDao.all()).length, 1);
    });
  });
}

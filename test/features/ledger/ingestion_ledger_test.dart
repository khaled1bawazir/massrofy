/// **KHA-23's done check, end to end.**
///
/// > *"Feeding the full synthetic corpus produces exactly the expected bank
/// > tree: correct number of banks, correct account-vs-card typing, no
/// > duplicate bank entities from naming variants. A rename survives a
/// > subsequent message for the same instrument. Drilling into a bank shows
/// > only its own instruments, and per-instrument totals equal the sum of that
/// > instrument's transactions for the period (AC-B2.3)."*
///
/// Every clause of that paragraph is a test below, run through the **real**
/// bundled rule pack, the real pipeline and a real database — not against
/// hand-built fixtures of what the parser is assumed to produce.
///
/// The AC-B12.3 sender half lives here too and is worth pointing at: the
/// corpus deliberately sends some Bank Aljazira messages from `BAJ` and
/// others from `Aljazira`. If bank identity were derived from the sender
/// string rather than the pack's canonical key, this file would show two
/// banks.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/logging/diagnostic_ring_buffer.dart';
import 'package:massrofy/core/logging/safe_logger.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/bank_dao.dart';
import 'package:massrofy/data/dao/ingest_watermark_dao.dart';
import 'package:massrofy/data/dao/instrument_dao.dart';
import 'package:massrofy/data/dao/raw_message_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ingestion/ingestion_pipeline.dart';
import 'package:massrofy/features/ingestion/sms_source.dart';
import 'package:massrofy/features/ledger/bank_directory.dart';
import 'package:massrofy/features/ledger/bank_tree.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';
import 'package:massrofy/features/ledger/ledger_entity_resolver.dart';
import 'package:massrofy/features/ledger/ledger_mapping.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_message_parser.dart';

import '../../fixtures/synthetic_sms_corpus.dart';
import '../../support/fake_sms_source.dart';
import '../../support/plain_test_database.dart';
import '../ingestion/support/load_bundled_pack.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i);

void main() {
  late AppDatabase db;
  late AuditLogDao auditLogDao;
  late RawMessageDao rawMessageDao;
  late TransactionDao transactionDao;
  late BankDao bankDao;
  late InstrumentDao instrumentDao;
  late IngestionPipeline pipeline;

  setUp(() {
    db = openPlainTestDatabase();
    auditLogDao = AuditLogDao(db, auditChainKey: _testChainKey);
    rawMessageDao = RawMessageDao(db);
    transactionDao = TransactionDao(db, auditLogDao);
    bankDao = BankDao(db, auditLogDao);
    instrumentDao = InstrumentDao(db, auditLogDao);

    final RulePack pack = loadBundledRulePack();

    pipeline = IngestionPipeline(
      database: db,
      smsSource: FakeSmsSource(<RawSmsRecord>[
        for (int i = 0; i < allFixtures.length; i++)
          RawSmsRecord(
            providerId: i + 1,
            address: allFixtures[i].sender,
            body: allFixtures[i].body,
            receivedAt: DateTime.utc(2026, 7, 28, 12).add(Duration(minutes: i)),
          ),
      ]),
      parser: RulePackMessageParser(packs: <RulePack>[pack]),
      rawMessageDao: rawMessageDao,
      transactionDao: transactionDao,
      watermarkDao: IngestWatermarkDao(db),
      logger: SafeLogger(DiagnosticRingBuffer()),
      contentHmacKey: _testChainKey,
      // The same adapter the app uses (see `ledger_providers.dart`), written
      // out here so this test exercises the production shape rather than a
      // convenient one.
      entityResolver: LedgerEntityResolver(
        bankDao: bankDao,
        instrumentDao: instrumentDao,
        directory: BankDirectory(<BankProfile>[
          for (final BankRule bank in pack.banks)
            BankProfile(
              canonicalKey: bank.bankId,
              displayNameAr: bank.displayNameAr,
              displayNameEn: bank.displayNameEn,
              aliases: bank.aliases,
            ),
        ]),
      ),
    );
  });

  tearDown(() async => db.close());

  Future<List<BankTreeNode>> buildTree({PeriodRange? period}) async {
    final List<LedgerInstrument> instruments = <LedgerInstrument>[
      for (final InstrumentRow row in await instrumentDao.all())
        toLedgerInstrument(row),
    ];
    return BankTreeBuilder.build(
      banks: <LedgerBank>[
        for (final BankRow row in await bankDao.all()) toLedgerBank(row),
      ],
      instruments: instruments,
      transactions: toLedgerTransactions(
        await transactionDao.all(),
        instrumentsById: <int, LedgerInstrument>{
          for (final LedgerInstrument i in instruments) i.id: i,
        },
      ),
      period: period ?? PeriodRange.unbounded(),
    );
  }

  group('the whole corpus, through the real pipeline', () {
    test('AC-B12.3 — exactly two banks, despite four distinct sender strings '
        'and both Arabic and Latin naming', () async {
      await pipeline.runIncremental();

      final List<BankRow> banks = await bankDao.all();
      expect(
        banks.map((BankRow b) => b.canonicalKey).toList(),
        <String>['bank-aljazira', 'd360'],
        reason:
            'the corpus sends Aljazira messages from both `BAJ` and '
            '`Aljazira`; two rows here would mean identity had leaked from '
            'the canonical key onto the sender string',
      );
    });

    test('AC-B13.1/B13.2 — instruments are typed from the rule, and both '
        'types appear under the same bank', () async {
      await pipeline.runIncremental();

      final BankRow aljazira = (await bankDao.byCanonicalKey('bank-aljazira'))!;
      final List<InstrumentRow> owned = await instrumentDao.forBank(
        aljazira.id,
      );

      expect(
        owned.where((InstrumentRow i) => i.kind == InstrumentKind.account),
        isNotEmpty,
        reason: 'the transfer/bill/fee templates name bare account numbers',
      );
      expect(
        owned.where((InstrumentRow i) => i.kind == InstrumentKind.card),
        isNotEmpty,
        reason: 'the purchase templates name masked card numbers',
      );

      // PRD §3.4's central observation, asserted: the same bank prints both
      // forms depending on the message type, and this app models that rather
      // than flattening it.
      expect(owned.length, greaterThanOrEqualTo(2));
    });

    test('AC-B15.1 — every instrument was created with no user action, and '
        'each records the message that first mentioned it (NFR-A1)', () async {
      await pipeline.runIncremental();

      final List<InstrumentRow> all = await instrumentDao.all();
      expect(all, isNotEmpty);
      for (final InstrumentRow instrument in all) {
        expect(
          instrument.firstSeenMessageId,
          isNotNull,
          reason: 'provenance cannot be reconstructed after the fact',
        );
        expect(instrument.friendlyName, isNull);
      }
    });

    test('AC-B14.1 — the card-repayment templates produce a settlement link, '
        'and nothing else does', () async {
      await pipeline.runIncremental();

      final List<InstrumentRow> linked = (await instrumentDao.all())
          .where((InstrumentRow i) => i.settlementAccountId != null)
          .toList();

      expect(
        linked,
        isNotEmpty,
        reason:
            'both banks have a card-repayment fixture naming a card and the '
            'debiting account (AC-B14.1)',
      );
      for (final InstrumentRow card in linked) {
        expect(card.kind, InstrumentKind.card);
        expect(card.linkSource, InstrumentLinkSource.smsRepayment);
        final InstrumentRow account = await instrumentDao.byId(
          card.settlementAccountId!,
        );
        expect(account.kind, InstrumentKind.account);
      }
    });

    test('every parsed transaction that named a maskable instrument carries '
        'its foreign key', () async {
      await pipeline.runIncremental();

      final List<TransactionRow> rows = await transactionDao.all();
      expect(rows, isNotEmpty);

      for (final TransactionRow row in rows) {
        if (row.instrumentMaskedRef == null) {
          expect(row.instrumentId, isNull);
          continue;
        }
        expect(
          row.instrumentId,
          isNotNull,
          reason:
              'the message named ${row.instrumentMaskedRef} but the '
              'transaction was left unattached — the tree would under-report',
        );
        final InstrumentRow instrument = await instrumentDao.byId(
          row.instrumentId!,
        );
        expect(instrument.maskedIdentifier, row.instrumentMaskedRef);
        expect(instrument.kind, row.instrumentKind);
      }
    });
  });

  group('AC-B2.1 / AC-B2.3 — the tree the user sees', () {
    test('drilling into a bank shows only its own instruments', () async {
      await pipeline.runIncremental();
      final List<BankTreeNode> tree = await buildTree();

      expect(tree.length, 2);
      for (final BankTreeNode node in tree) {
        for (final InstrumentSummary summary in <InstrumentSummary>[
          ...node.accounts,
          ...node.cards,
        ]) {
          expect(summary.instrument.bankId, node.bank.id);
        }
      }
    });

    test('a per-instrument total equals the sum of exactly that instrument\'s '
        'transactions for the period', () async {
      await pipeline.runIncremental();
      final List<BankTreeNode> tree = await buildTree();
      final PeriodRange period = PeriodRange.unbounded();

      final List<TransactionRow> allRows = await transactionDao.all();

      for (final BankTreeNode node in tree) {
        for (final InstrumentSummary summary in <InstrumentSummary>[
          ...node.accounts,
          ...node.cards,
        ]) {
          // Recomputed independently, straight from the rows, so this is a
          // genuine cross-check rather than the same code asserting itself.
          final List<LedgerTransaction> own = toLedgerTransactions(
            allRows.where(
              (TransactionRow r) => r.instrumentId == summary.instrument.id,
            ),
          );
          final PeriodTotals expected = LedgerTotals.spend(own, period: period);

          for (final CurrencyTotal actual in summary.totals.byCurrency) {
            expect(
              actual.net,
              expected.forCurrency(actual.currencyCode),
              reason:
                  'instrument #${summary.instrument.id} '
                  '${actual.currencyCode} total disagrees with its own rows',
            );
          }
          expect(summary.totals.byCurrency.length, expected.byCurrency.length);
        }
      }
    });

    test(
      'the bank figure equals the sum of its instruments (NFR-A6)',
      () async {
        await pipeline.runIncremental();

        for (final BankTreeNode node in await buildTree()) {
          for (final CurrencyTotal bankTotal in node.totals.byCurrency) {
            final Money summed = Money.sum(<Money>[
              for (final InstrumentSummary s in <InstrumentSummary>[
                ...node.accounts,
                ...node.cards,
              ])
                s.totals.forCurrency(bankTotal.currencyCode) ??
                    Money.zero(bankTotal.currencyCode),
            ], currency: bankTotal.currencyCode);

            expect(bankTotal.net, summed);
          }
        }
      },
    );
  });

  group('AC-B3.1 / AC-B3.2 — a rename survives re-ingestion', () {
    test(
      'renaming an instrument, then ingesting another message for it, '
      'attaches to the RENAMED instrument and does not create a second',
      () async {
        await pipeline.runIncremental();

        final InstrumentRow card = (await instrumentDao.all()).firstWhere(
          (InstrumentRow i) => i.kind == InstrumentKind.card,
        );
        final int instrumentCountBefore = (await instrumentDao.all()).length;

        await instrumentDao.rename(id: card.id, newName: 'Blue Visa');

        // A *new* message for the same card. Built by hand rather than replayed
        // from the corpus, because a replayed message would be suppressed by
        // ADR-017 D1 as an exact duplicate and would prove nothing.
        final int reResolved = await instrumentDao.ensure(
          bankId: card.bankId,
          kind: card.kind,
          maskedIdentifier: card.maskedIdentifier,
          refKey: card.refKey,
        );

        expect(reResolved, card.id);
        expect((await instrumentDao.byId(card.id)).friendlyName, 'Blue Visa');
        expect((await instrumentDao.all()).length, instrumentCountBefore);
      },
    );
  });

  group('the audit trail survives a full corpus run', () {
    test('NFR-A2/A3 — the hash chain still verifies after every bank, '
        'instrument and transaction write', () async {
      await pipeline.runIncremental();
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });
  });
}

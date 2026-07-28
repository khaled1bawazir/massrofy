/// **P3b-1 end to end** — KHA-27, KHA-28, KHA-29, KHA-70, through the real
/// bundled rule pack, the real ingestion pipeline and a real database.
///
/// The unit suites (`base_currency_test.dart`, `spend_classification_test.dart`,
/// `combined_totals_test.dart`) prove the arithmetic against hand-built
/// transactions. This file proves the other half: that a genuine SMS travelling
/// the whole path — sanitiser, rule pack, parser, FX recording, DAO, schema v4,
/// mapper, classifier, totals — arrives with the values those suites assume.
///
/// It is the difference between "the converter is correct" and "the app
/// converts". Both are needed; only this one would have caught a column that
/// was never written.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/logging/diagnostic_ring_buffer.dart';
import 'package:massrofy/core/logging/safe_logger.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/bank_dao.dart';
import 'package:massrofy/data/dao/ingest_watermark_dao.dart';
import 'package:massrofy/data/dao/instrument_dao.dart';
import 'package:massrofy/data/dao/raw_message_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ingestion/ingestion_pipeline.dart';
import 'package:massrofy/features/ingestion/sms_source.dart';
import 'package:massrofy/features/ledger/base_currency.dart';
import 'package:massrofy/features/ledger/bank_directory.dart';
import 'package:massrofy/features/ledger/bank_tree.dart';
import 'package:massrofy/features/ledger/ledger_entity_resolver.dart';
import 'package:massrofy/features/ledger/ledger_mapping.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_message_parser.dart';

import '../../fixtures/synthetic_sms_corpus.dart';
import '../../support/fake_sms_source.dart';
import '../../support/plain_test_database.dart';
import '../ingestion/support/load_bundled_pack.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i);

void main() {
  late AppDatabase db;
  late TransactionDao transactionDao;
  late BankDao bankDao;
  late InstrumentDao instrumentDao;
  late IngestionPipeline pipeline;

  setUp(() {
    db = openPlainTestDatabase();
    final AuditLogDao auditLogDao = AuditLogDao(
      db,
      auditChainKey: _testChainKey,
    );
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
      rawMessageDao: RawMessageDao(db),
      transactionDao: transactionDao,
      watermarkDao: IngestWatermarkDao(db),
      logger: SafeLogger(DiagnosticRingBuffer()),
      contentHmacKey: _testChainKey,
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

  /// The stored row for the transaction whose merchant/counterparty matches.
  Future<TransactionRow> rowWhere(bool Function(TransactionRow) test) async =>
      (await transactionDao.all()).firstWhere(test);

  Future<List<LedgerTransaction>> ledger() async {
    final List<LedgerInstrument> instruments = <LedgerInstrument>[
      for (final InstrumentRow row in await instrumentDao.all())
        toLedgerInstrument(row),
    ];
    return toLedgerTransactions(
      await transactionDao.all(),
      instrumentsById: <int, LedgerInstrument>{
        for (final LedgerInstrument i in instruments) i.id: i,
      },
    );
  }

  group('KHA-70 — the FX columns are actually written', () {
    test('a message stating the rate stores it verbatim, with the movement '
        'date and source sms_stated', () async {
      await pipeline.runIncremental();

      // D360's online-purchase template prints "Rate 3.7510".
      final TransactionRow row = await rowWhere(
        (TransactionRow r) => r.merchantRawText == 'NORTHWIND SOFTWARE',
      );

      expect(
        row.fxRate,
        '3.7510',
        reason:
            'stored verbatim — re-serialising through Decimal would drop the '
            'trailing zero the bank printed',
      );
      // Compared as an *instant*: drift stores a DateTime as a unix timestamp
      // and hands it back in the device's local zone, so an equality against
      // a `DateTime.utc(...)` literal would fail on any machine that is not
      // at UTC — a test that passes in London and fails in Riyadh.
      expect(row.fxRateDate!.toUtc(), DateTime.utc(2026, 7, 27, 19, 47));
      expect(row.fxRateSource, FxRateSource.smsStated);
      expect(row.conversionPending, isFalse);
    });

    test('a message giving both amounts but no rate stores the IMPLIED rate, '
        'labelled as implied', () async {
      await pipeline.runIncremental();

      // Aljazira's online-purchase template prints "49.99 USD (187.46 SAR)"
      // and no rate at all.
      final TransactionRow row = await rowWhere(
        (TransactionRow r) => r.merchantRawText == 'GLOBAL CLOUD SERVICES',
      );

      expect(row.fxRate, '3.74994998');
      expect(row.fxRateSource, FxRateSource.smsImplied);
      expect(row.fxRateDate!.toUtc(), DateTime.utc(2026, 7, 26, 6, 14));
    });

    test('**KHA-70\'s DAO done-check**: a message stating no rate stores NULL '
        'in every FX column rather than a default', () async {
      await pipeline.runIncremental();

      // A EUR purchase with no conversion and no rate (ADR-009 case 4).
      final TransactionRow row = await rowWhere(
        (TransactionRow r) => r.merchantRawText == 'PARIS BOOKSHOP',
      );

      expect(row.amountCurrency, 'EUR');
      expect(row.convertedAmountAmount, isNull);
      expect(row.fxRate, isNull);
      expect(
        row.fxRateDate,
        isNull,
        reason:
            'NULL, not the transaction date — "we do not know" and "the rate '
            'date is the 26th" are different statements',
      );
      expect(row.fxRateSource, isNull);
      expect(
        row.conversionPending,
        isTrue,
        reason: 'ADR-009 case 4 — excluded from base totals, visibly',
      );
    });

    test('a plain base-currency purchase records no FX at all', () async {
      await pipeline.runIncremental();

      final TransactionRow row = await rowWhere(
        (TransactionRow r) => r.merchantRawText == 'EXTRA MART 0042',
      );

      expect(row.fxRate, isNull);
      expect(row.fxRateDate, isNull);
      expect(row.fxRateSource, isNull);
      expect(row.conversionPending, isFalse);
    });
  });

  group('KHA-28 / KHA-29 — the new message types classify correctly', () {
    test('a refund is stored as a credit', () async {
      await pipeline.runIncremental();

      final TransactionRow row = await rowWhere(
        (TransactionRow r) => r.transactionType == TransactionType.refund,
      );
      expect(row.direction, 'credit');
      expect(
        row.amountAmount,
        '187.46',
        reason:
            'the magnitude is stored positive; the sign lives in `direction` '
            '(lib/core/money/sign_convention.dart)',
      );
    });

    test('AC-B10.1 — a salary message becomes income, not spend', () async {
      await pipeline.runIncremental();

      final TransactionRow row = await rowWhere(
        (TransactionRow r) => r.transactionType == TransactionType.salaryIncome,
      );
      expect(row.direction, 'credit');
      expect(row.affectsSpend, isFalse);

      final PeriodReport report = LedgerTotals.report(
        await ledger(),
        period: PeriodRange.unbounded(),
      );
      // Two salary fixtures (one per bank), 14,500.00 each, plus the two
      // generic incoming transfers the corpus already had (14,500.00 and
      // 9,750.00) — all four are income.
      expect(report.income.base!.toCanonicalString(), '53250');
    });

    test('AC-B10.2 — an ATM withdrawal is a withdrawal, and is in neither '
        'the spend nor the income figure', () async {
      await pipeline.runIncremental();

      final TransactionRow row = await rowWhere(
        (TransactionRow r) => r.transactionType == TransactionType.withdrawal,
      );
      expect(row.affectsSpend, isFalse);

      final PeriodReport report = LedgerTotals.report(
        await ledger(),
        period: PeriodRange.unbounded(),
      );
      // 500.00 from each bank.
      expect(report.cashWithdrawals.base!.toCanonicalString(), '1000');
    });

    test('the corpus contains no internal-transfer pair, and the detector '
        'does not invent one', () async {
      await pipeline.runIncremental();

      final PeriodReport report = LedgerTotals.report(
        await ledger(),
        period: PeriodRange.unbounded(),
      );
      expect(
        report.internalTransfers.isEmpty,
        isTrue,
        reason:
            'the corpus transfers are to named third parties for different '
            'amounts; pairing any of them would be the false-positive that '
            'silently deletes real spend',
      );
    });
  });

  group('AC-B7.2 — a charge and its full refund net to zero', () {
    test("Aljazira's card: 187.46 charged, 187.46 refunded, and the card's "
        'period figure is exactly 0.00 SAR', () async {
      await pipeline.runIncremental();

      final List<BankTreeNode> tree = BankTreeBuilder.build(
        banks: <LedgerBank>[
          for (final BankRow row in await bankDao.all()) toLedgerBank(row),
        ],
        instruments: <LedgerInstrument>[
          for (final InstrumentRow row in await instrumentDao.all())
            toLedgerInstrument(row),
        ],
        transactions: await ledger(),
        period: PeriodRange.unbounded(),
      );

      final BankTreeNode aljazira = tree.firstWhere(
        (BankTreeNode n) => n.bank.canonicalKey == 'bank-aljazira',
      );
      final InstrumentSummary visa = aljazira.cards.firstWhere(
        (InstrumentSummary s) => s.instrument.maskedIdentifier == '****9013',
      );

      //   +187.46  the USD online purchase, at the bank's own conversion
      //   −187.46  the refund of it
      //   ───────
      //      0.00
      // The card repayment on this card is excluded (it settles spend already
      // counted), and the EUR purchase is unconvertible, so neither moves the
      // base figure.
      expect(visa.totals.base!.toCanonicalString(), '0');
      expect(
        visa.totals.base!.isZero,
        isTrue,
        reason:
            'AC-B7.2 asks for exactly zero, and zero here is a computed fact '
            'rather than an empty state — `isEmpty` is false',
      );
      expect(visa.totals.isEmpty, isFalse);

      // …and the EUR purchase is still visible, on its own line.
      expect(visa.totals.unconvertedCount, 1);
      expect(visa.totals.unconverted.single.currencyCode, 'EUR');
    });

    test("D360's card: 450.12 charged, 187.46 refunded, net 262.66 — a "
        'partial refund nets to the difference', () async {
      await pipeline.runIncremental();

      final List<BankTreeNode> tree = BankTreeBuilder.build(
        banks: <LedgerBank>[
          for (final BankRow row in await bankDao.all()) toLedgerBank(row),
        ],
        instruments: <LedgerInstrument>[
          for (final InstrumentRow row in await instrumentDao.all())
            toLedgerInstrument(row),
        ],
        transactions: await ledger(),
        period: PeriodRange.unbounded(),
      );

      final BankTreeNode d360 = tree.firstWhere(
        (BankTreeNode n) => n.bank.canonicalKey == 'd360',
      );
      final InstrumentSummary card = d360.cards.firstWhere(
        (InstrumentSummary s) => s.instrument.maskedIdentifier == '****8821',
      );

      // 450.12 − 187.46 = 262.66
      expect(card.totals.base!.toCanonicalString(), '262.66');
    });
  });
}

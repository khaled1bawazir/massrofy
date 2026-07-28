/// The bank tree — AC-B2.1, AC-B2.2, AC-B2.3, AC-B12.2, AC-B13.3, AC-B14.2,
/// AC-B14.3, AC-B15.2, AC-B3.1, NFR-A6.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/features/ledger/bank_tree.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';

final PeriodRange july2026 = PeriodRange(
  startUtc: DateTime.utc(2026, 7),
  endUtcExclusive: DateTime.utc(2026, 8),
);

const LedgerBank aljazira = LedgerBank(
  id: 1,
  canonicalKey: 'bank-aljazira',
  displayNameAr: 'بنك الجزيرة',
  displayNameEn: 'Bank Aljazira',
);
const LedgerBank d360 = LedgerBank(
  id: 2,
  canonicalKey: 'd360',
  displayNameAr: 'دي ٣٦٠',
  displayNameEn: 'D360 Bank',
);

LedgerInstrument instrument({
  required int id,
  required int bankId,
  required String kind,
  required String masked,
  String? friendlyName,
  int? settlementAccountId,
}) => LedgerInstrument(
  id: id,
  bankId: bankId,
  kind: kind,
  maskedIdentifier: masked,
  friendlyName: friendlyName,
  settlementAccountId: settlementAccountId,
);

LedgerTransaction txn({
  required int id,
  required LedgerInstrument on,
  required String amount,
  String direction = 'debit',
  bool affectsSpend = true,
}) => LedgerTransaction(
  id: id,
  amount: Money.parse(amount, currency: 'SAR'),
  direction: direction,
  transactionType: 'pos_purchase',
  affectsSpend: affectsSpend,
  occurredAt: DateTime.utc(2026, 7, 10, 9),
  instrument: on,
);

void main() {
  final LedgerInstrument salaryAccount = instrument(
    id: 10,
    bankId: 1,
    kind: InstrumentKind.account,
    masked: '****3388',
    friendlyName: 'Salary Account',
  );
  final LedgerInstrument blueVisa = instrument(
    id: 11,
    bankId: 1,
    kind: InstrumentKind.card,
    masked: '****4821',
    friendlyName: 'Blue Visa',
    settlementAccountId: 10,
  );
  final LedgerInstrument unnamedCard = instrument(
    id: 12,
    bankId: 1,
    kind: InstrumentKind.card,
    masked: '****7765',
  );
  final LedgerInstrument d360Account = instrument(
    id: 20,
    bankId: 2,
    kind: InstrumentKind.account,
    masked: '****9911',
  );

  List<BankTreeNode> buildTree() => BankTreeBuilder.build(
    banks: <LedgerBank>[aljazira, d360],
    instruments: <LedgerInstrument>[
      salaryAccount,
      blueVisa,
      unnamedCard,
      d360Account,
    ],
    transactions: <LedgerTransaction>[
      txn(id: 1, on: salaryAccount, amount: '640.00'),
      txn(id: 2, on: blueVisa, amount: '1000.00'),
      txn(id: 3, on: blueVisa, amount: '500.00'),
      txn(id: 4, on: d360Account, amount: '74.50'),
    ],
    period: july2026,
  );

  group('AC-B2.1 — each bank has its own figure and only its own '
      'instruments', () {
    test('a bank node contains no instrument belonging to another bank', () {
      final List<BankTreeNode> tree = buildTree();
      final BankTreeNode aljaziraNode = tree.first;
      final BankTreeNode d360Node = tree.last;

      expect(
        <int>[
          for (final InstrumentSummary s in aljaziraNode.accounts)
            s.instrument.id,
          for (final InstrumentSummary s in aljaziraNode.cards) s.instrument.id,
        ],
        <int>[10, 11, 12],
      );
      expect(
        <int>[
          for (final InstrumentSummary s in d360Node.accounts) s.instrument.id,
        ],
        <int>[20],
      );
    });

    test('each bank total covers only its own transactions', () {
      final List<BankTreeNode> tree = buildTree();
      expect(tree.first.totals.forCurrency('SAR')!.toCanonicalString(), '2140');
      expect(tree.last.totals.forCurrency('SAR')!.toCanonicalString(), '74.5');
    });
  });

  group('AC-B13.3 — account activity and card activity are never merged', () {
    test('accounts and cards are separate collections', () {
      final BankTreeNode node = buildTree().first;
      expect(
        node.accounts.map((InstrumentSummary s) => s.instrument.kind),
        <String>[InstrumentKind.account],
      );
      expect(
        node.cards.map((InstrumentSummary s) => s.instrument.kind),
        <String>[InstrumentKind.card, InstrumentKind.card],
      );
    });
  });

  group('AC-B2.2 / AC-B2.3 — per-instrument figures', () {
    test('two cards at the same bank carry their own respective totals', () {
      final BankTreeNode node = buildTree().first;
      final InstrumentSummary visa = node.cards.first;
      final InstrumentSummary unnamed = node.cards.last;

      expect(visa.totals.forCurrency('SAR')!.toCanonicalString(), '1500');
      expect(
        unnamed.totals.isEmpty,
        isTrue,
        reason:
            'a card with no transactions this period shows "no transactions", '
            'not a confident 0.00',
      );
    });

    test('NFR-A6 — the bank total equals the sum of its instruments, because '
        'both are computed from the same transactions', () {
      final BankTreeNode node = buildTree().first;
      final Money bankTotal = node.totals.forCurrency('SAR')!;
      final Money summed = Money.sum(<Money>[
        for (final InstrumentSummary s in <InstrumentSummary>[
          ...node.accounts,
          ...node.cards,
        ])
          s.totals.forCurrency('SAR') ?? Money.zero('SAR'),
      ], currency: 'SAR');

      expect(bankTotal, summed);
    });
  });

  group('AC-B15.2 / AC-B3.1 — how an instrument is labelled', () {
    test('an auto-created, not-yet-renamed instrument is labelled by its '
        'masked identifier', () {
      final InstrumentSummary unnamed = buildTree().first.cards.last;
      expect(unnamed.isUnnamed, isTrue);
      expect(unnamed.label, '****7765');
    });

    test('a renamed instrument is labelled by its friendly name', () {
      final InstrumentSummary visa = buildTree().first.cards.first;
      expect(visa.isUnnamed, isFalse);
      expect(visa.label, 'Blue Visa');
    });

    test('a whitespace-only name does not count as a name', () {
      final InstrumentSummary summary = InstrumentSummary(
        instrument: instrument(
          id: 99,
          bankId: 1,
          kind: InstrumentKind.card,
          masked: '****0001',
          friendlyName: '   ',
        ),
        totals: PeriodTotals.empty,
      );
      expect(summary.isUnnamed, isTrue);
      expect(summary.label, '****0001');
    });
  });

  group('AC-B14.2 / AC-B14.3 — the settlement link', () {
    test('a linked card carries the account label for context', () {
      final InstrumentSummary visa = buildTree().first.cards.first;
      expect(visa.settlementAccountLabel, 'Salary Account');
    });

    test(
      'an unlinked card carries null — shown as unlinked, never guessed',
      () {
        final InstrumentSummary unnamed = buildTree().first.cards.last;
        expect(unnamed.settlementAccountLabel, isNull);
      },
    );

    test('a link to an account with no friendly name falls back to its masked '
        'identifier rather than to an empty label', () {
      final LedgerInstrument card = instrument(
        id: 30,
        bankId: 2,
        kind: InstrumentKind.card,
        masked: '****1111',
        settlementAccountId: 20,
      );
      final List<BankTreeNode> tree = BankTreeBuilder.build(
        banks: <LedgerBank>[d360],
        instruments: <LedgerInstrument>[d360Account, card],
        transactions: const <LedgerTransaction>[],
        period: july2026,
      );
      expect(tree.single.cards.single.settlementAccountLabel, '****9911');
    });
  });

  group('a bank with no instruments is still shown', () {
    test('hasNoInstruments is true, and the bank is not dropped', () {
      final List<BankTreeNode> tree = BankTreeBuilder.build(
        banks: <LedgerBank>[aljazira],
        instruments: const <LedgerInstrument>[],
        transactions: const <LedgerTransaction>[],
        period: july2026,
      );
      expect(tree.single.hasNoInstruments, isTrue);
    });
  });

  group('bank display names', () {
    test('follow the locale, and fall back rather than render blank', () {
      expect(aljazira.displayName('ar'), 'بنك الجزيرة');
      expect(aljazira.displayName('en'), 'Bank Aljazira');

      const LedgerBank arabicOnly = LedgerBank(
        id: 3,
        canonicalKey: 'x',
        displayNameAr: 'بنك',
        displayNameEn: '',
      );
      expect(arabicOnly.displayName('en'), 'بنك');
    });
  });
}

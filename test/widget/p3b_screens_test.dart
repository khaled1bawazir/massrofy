/// Widget tests for what P3b-1 puts on screen — KHA-27, KHA-28, KHA-29,
/// KHA-70.
///
/// | Surface | Acceptance criteria |
/// |---|---|
/// | S-11's FX block | AC-B9.1, **AC-B9.3 (KHA-70's done check)** |
/// | S-11's internal-transfer state | AC-B11.1, AC-B11.2, design.md §3.3 |
/// | `PeriodTotalsText` | AC-B9.2's "N transactions not converted" |
/// | S-32 Spent vs Kept card | AC-B10.3 |
/// | credit vs debit in a list | AC-B7.3, NFR-U4 |
///
/// Following the existing suites' rules: both locales, and the dense field
/// list at a 2.0 text scale (NFR-U3).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/features/ingestion/review_queue.dart';
import 'package:massrofy/features/ledger/bank_tree.dart';
import 'package:massrofy/features/ledger/internal_transfer.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';
import 'package:massrofy/features/ledger/unparsed_completion.dart';
import 'package:massrofy/presentation/screens/complete_unparsed_screen.dart';
import 'package:massrofy/presentation/screens/instrument_detail_screen.dart';
import 'package:massrofy/presentation/screens/transaction_detail_screen.dart';
import 'package:massrofy/presentation/widgets/ledger_widgets.dart';
import 'package:massrofy/presentation/widgets/spent_vs_kept_card.dart';

import 'p3_screens_test.dart' show useTallSurface, wrap;

LedgerTransaction foreignPurchase({
  String? fxRate,
  DateTime? fxRateDate,
  String? fxRateSource,
  bool conversionPending = false,
  String? convertedAmount = '450.12',
}) => LedgerTransaction(
  id: 1,
  amount: Money.parse('120.00', currency: 'USD'),
  direction: 'debit',
  transactionType: TransactionType.onlinePurchase,
  affectsSpend: true,
  occurredAt: DateTime.utc(2026, 7, 27, 19, 47),
  merchantRawText: 'NORTHWIND SOFTWARE',
  convertedAmount: convertedAmount == null
      ? null
      : Money.parse(convertedAmount, currency: 'SAR'),
  feeAmount: Money.parse('11.25', currency: 'SAR'),
  fxRate: fxRate,
  fxRateDate: fxRateDate,
  fxRateSource: fxRateSource,
  conversionPending: conversionPending,
);

PeriodTotals totals({
  String? base,
  int convertedCount = 0,
  List<UnconvertedGroup> unconverted = const <UnconvertedGroup>[],
  List<CurrencyTotal> byCurrency = const <CurrencyTotal>[],
}) => PeriodTotals(
  base: base == null ? null : Money.parse(base, currency: 'SAR'),
  baseCurrencyCode: 'SAR',
  convertedCount: convertedCount,
  byCurrency: byCurrency,
  unconverted: unconverted,
);

PeriodTotals sar(String amount, {int count = 1}) {
  final Money money = Money.parse(amount, currency: 'SAR');
  return totals(
    base: amount,
    convertedCount: count,
    byCurrency: <CurrencyTotal>[
      CurrencyTotal(currencyCode: 'SAR', net: money, transactionCount: count),
    ],
  );
}

void main() {
  group('S-11 FX block — AC-B9.3 / KHA-70', () {
    testWidgets('**the KHA-70 done check**: a rate is NEVER rendered without '
        'either a rate date or the explicit words "Date unknown"', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);

      // Both halves of the rule, in one test, because the defect was that
      // only the rate was rendered — the failure mode is an *absence*, and an
      // absence has to be asserted against both possible presences.
      for (final (DateTime? date, String expected) in <(DateTime?, String)>[
        (DateTime.utc(2026, 7, 27, 19, 47), '2026-07-27'),
        (null, 'Date unknown'),
      ]) {
        await tester.pumpWidget(
          wrap(
            TransactionDetailScreen(
              transaction: foreignPurchase(
                fxRate: '3.7510',
                fxRateDate: date,
                fxRateSource: 'sms_stated',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('3.7510'), findsOneWidget);
        expect(find.text('Rate date'), findsOneWidget);
        expect(
          find.textContaining(expected),
          findsWidgets,
          reason: 'rate date = $date',
        );
      }
    });

    testWidgets('the rate date row is absent entirely when there is no rate — '
        'an empty FX block teaches the user to skip it', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: LedgerTransaction(
              id: 2,
              amount: Money.parse('152.75', currency: 'SAR'),
              direction: 'debit',
              transactionType: TransactionType.posPurchase,
              affectsSpend: true,
              occurredAt: DateTime.utc(2026, 7, 28, 11, 32),
              merchantRawText: 'EXTRA MART',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rate date'), findsNothing);
      expect(find.text('Exchange rate'), findsNothing);
      expect(find.text('Converted amount'), findsNothing);
    });

    testWidgets('AC-B9.1 — a foreign transaction shows BOTH its native amount '
        'and its converted base-currency amount', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: foreignPurchase(
              fxRate: '3.7510',
              fxRateDate: DateTime.utc(2026, 7, 27, 19, 47),
              fxRateSource: 'sms_stated',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('−120.00 USD'), findsOneWidget);
      expect(find.text('450.12 SAR'), findsOneWidget);
      // …and the fee is shown separately, never folded in (PRD §3.4).
      expect(find.text('11.25 SAR'), findsOneWidget);
    });

    testWidgets('AC-B9.3 — the rate source is stated in words, so the user '
        'can tell a bank-implied rate from one they typed', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: foreignPurchase(
              fxRate: '3.75015003',
              fxRateSource: 'sms_implied',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rate source'), findsOneWidget);
      expect(
        find.text("Implied by the bank's own converted amount"),
        findsOneWidget,
      );
    });

    testWidgets('an unrecognised stored rate source degrades to the explicit '
        'unknown wording, not to a guess (§5.2)', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: foreignPurchase(
              fxRate: '3.7510',
              fxRateSource: 'oracle_of_delphi',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rate source'), findsOneWidget);
      expect(find.text('Not stated in message'), findsWidgets);
    });

    testWidgets('ADR-009 case 4 — an unconverted foreign purchase says so, in '
        'words, rather than quietly vanishing from the total', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: foreignPurchase(
              convertedAmount: null,
              conversionPending: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Not converted to SAR'), findsOneWidget);
      expect(find.textContaining('never invents one'), findsOneWidget);
    });

    testWidgets('the FX block survives a 2.0 text scale without overflowing '
        '(NFR-U3)', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: foreignPurchase(
              fxRate: '3.7510',
              fxRateDate: DateTime.utc(2026, 7, 27, 19, 47),
              fxRateSource: 'sms_stated',
            ),
          ),
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in Arabic RTL', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: foreignPurchase(
              fxRate: '3.7510',
              fxRateSource: 'sms_stated',
            ),
          ),
          locale: 'ar',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('تاريخ سعر الصرف'), findsOneWidget);
      expect(find.text('التاريخ غير معروف'), findsOneWidget);
    });
  });

  group('S-11 internal-transfer state — AC-B11.1/B11.2, design.md §3.3', () {
    LedgerTransaction transferOut() => LedgerTransaction(
      id: 5,
      amount: Money.parse('2000.00', currency: 'SAR'),
      direction: 'debit',
      transactionType: TransactionType.transferOut,
      affectsSpend: true,
      occurredAt: DateTime.utc(2026, 7, 10, 9),
      counterpartyName: 'MY SAVINGS',
    );

    testWidgets('a confirmed internal transfer is labelled in WORDS and shows '
        'no +/− prefix at all', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: transferOut(),
            internalTransferState: InternalTransferState.internal,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // design.md §3.3: bidirectional-arrow icon + the words, and *no* sign —
      // it is neither spend nor income, so a "−" would be a second,
      // contradictory statement next to "excluded from spend".
      expect(find.text('Internal transfer'), findsOneWidget);
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
      expect(find.text('2000.00 SAR'), findsOneWidget);
      expect(find.text('−2000.00 SAR'), findsNothing);
      expect(find.textContaining('Excluded from spend totals'), findsOneWidget);
    });

    testWidgets('an unproven candidate says it is still being counted — '
        'AC-B11.2, risk R-7 made visible', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: transferOut(),
            internalTransferState: InternalTransferState.candidate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Possible internal transfer'), findsOneWidget);
      expect(find.textContaining('Still counted as spend'), findsOneWidget);
      // The sign IS shown here: it is still counted, so it must still look
      // like the debit it is being treated as.
      expect(find.text('−2000.00 SAR'), findsOneWidget);
    });

    testWidgets('an ordinary third-party transfer carries no transfer badge '
        'at all', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(TransactionDetailScreen(transaction: transferOut())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Internal transfer'), findsNothing);
      expect(find.text('Possible internal transfer'), findsNothing);
    });

    testWidgets('a persisted state on the row is used when the caller passes '
        'none — the user\'s own decision is never dropped', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: LedgerTransaction(
              id: 5,
              amount: Money.parse('2000.00', currency: 'SAR'),
              direction: 'debit',
              transactionType: TransactionType.transferOut,
              affectsSpend: true,
              occurredAt: DateTime.utc(2026, 7, 10, 9),
              internalTransferState: InternalTransferState.internal,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Internal transfer'), findsOneWidget);
    });
  });

  group(
    'S-23/24 transaction list — the internal-transfer row (design.md §3.3)',
    () {
      LedgerTransaction transferOut() => LedgerTransaction(
        id: 5,
        amount: Money.parse('2000.00', currency: 'SAR'),
        direction: 'debit',
        transactionType: TransactionType.transferOut,
        affectsSpend: true,
        occurredAt: DateTime.utc(2026, 7, 10, 9),
        counterpartyName: 'MY SAVINGS',
      );

      Widget screen({Map<int, String> states = const <int, String>{}}) =>
          InstrumentDetailScreen(
            summary: InstrumentSummary(
              instrument: const LedgerInstrument(
                id: 10,
                bankId: 1,
                kind: 'account',
                maskedIdentifier: '****3388',
                friendlyName: 'Current Account',
              ),
              totals: sar('800.00'),
            ),
            transactions: <LedgerTransaction>[transferOut()],
            onRename: (_) {},
            internalTransferStates: states,
          );

      testWidgets('a confirmed internal transfer is labelled on the row and '
          'loses its sign — so a user scanning the list can see why it is not '
          'in the total above', (WidgetTester tester) async {
        useTallSurface(tester);
        await tester.pumpWidget(
          wrap(
            screen(states: <int, String>{5: InternalTransferState.internal}),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Internal transfer'), findsOneWidget);
        expect(find.text('2000.00 SAR'), findsOneWidget);
        expect(find.text('−2000.00 SAR'), findsNothing);
      });

      testWidgets(
        'with no state supplied the row renders as an ordinary debit — '
        'under-reporting rather than mislabelling',
        (WidgetTester tester) async {
          useTallSurface(tester);
          await tester.pumpWidget(wrap(screen()));
          await tester.pumpAndSettle();

          expect(find.text('Internal transfer'), findsNothing);
          expect(find.text('−2000.00 SAR'), findsOneWidget);
        },
      );
    },
  );

  group('S-19 — the classification P3b-1 corrected', () {
    final ReviewQueueItem item = ReviewQueueItem(
      rawMessageId: 77,
      sanitizedBody: 'حوالة صادرة إلى شركة',
      sender: 'BAJ',
      receivedAt: DateTime.utc(2026, 7, 20, 9),
      bankId: 'bank-aljazira',
      unparsedReason: 'required_field_missing',
    );

    Future<UnparsedCompletionDraft?> completeAs(
      WidgetTester tester,
      String typeLabel,
    ) async {
      useTallSurface(tester);
      UnparsedCompletionDraft? saved;
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(
            item: item,
            onSave: (UnparsedCompletionDraft draft) => saved = draft,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).first, '2000.00');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(typeLabel).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as transaction'));
      await tester.pumpAndSettle();
      return saved;
    }

    testWidgets('an outgoing transfer completed by hand now COUNTS as spend — '
        'whether it is internal is a property of the pair, which this form '
        'cannot see (AC-B11.2)', (WidgetTester tester) async {
      // Before P3b-1 the form marked every hand-completed `transfer_out` as
      // non-spend, which silently dropped genuine third-party payments from
      // every total.
      final UnparsedCompletionDraft? saved = await completeAs(
        tester,
        'Outgoing transfer',
      );

      expect(saved, isNotNull);
      expect(saved!.affectsSpend, isTrue);
      expect(saved.direction, 'debit');
    });

    testWidgets('AC-B10.1 — salary is offered, and choosing it sets the '
        'direction to credit and excludes it from spend', (
      WidgetTester tester,
    ) async {
      final UnparsedCompletionDraft? saved = await completeAs(
        tester,
        'Salary / income',
      );

      expect(saved!.transactionType, 'salary_income');
      expect(saved.direction, 'credit');
      expect(saved.affectsSpend, isFalse);
    });

    testWidgets('AC-B10.2 — a cash withdrawal is a debit that does not count '
        'as spend', (WidgetTester tester) async {
      final UnparsedCompletionDraft? saved = await completeAs(
        tester,
        'Cash withdrawal',
      );

      expect(saved!.transactionType, 'withdrawal');
      expect(saved.direction, 'debit');
      expect(saved.affectsSpend, isFalse);
    });
  });

  group('AC-B7.3 / NFR-U4 — a credit is distinguishable without colour', () {
    testWidgets('a credit is "+", a debit is "−", and each carries a spoken '
        'label — so the distinction survives greyscale and a screen reader', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Column(
            children: <Widget>[
              SignedAmountText(
                amount: Money.parse('187.46', currency: 'SAR'),
                isCredit: true,
              ),
              SignedAmountText(
                amount: Money.parse('152.75', currency: 'SAR'),
                isCredit: false,
              ),
            ],
          ),
        ),
      );

      expect(find.text('+187.46 SAR'), findsOneWidget);
      expect(find.text('−152.75 SAR'), findsOneWidget);

      final Semantics credit = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.text('+187.46 SAR'),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(credit.properties.label, 'Credit');
    });
  });

  group('AC-B9.2 — the "not converted" line', () {
    testWidgets('a complete total shows the base figure and nothing else', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap(PeriodTotalsText(totals: sar('1140.41'))));

      expect(find.text('−1140.41 SAR'), findsOneWidget);
      expect(find.textContaining('not converted'), findsNothing);
    });

    testWidgets('an incomplete total states how much is missing, and shows '
        'the missing money in its own currency', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          PeriodTotalsText(
            totals: totals(
              base: '1140.41',
              convertedCount: 5,
              byCurrency: <CurrencyTotal>[
                CurrencyTotal(
                  currencyCode: 'SAR',
                  net: Money.parse('952.75', currency: 'SAR'),
                  transactionCount: 2,
                ),
              ],
              unconverted: <UnconvertedGroup>[
                UnconvertedGroup(
                  currencyCode: 'EUR',
                  net: Money.parse('35.00', currency: 'EUR'),
                  transactionCount: 2,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('−1140.41 SAR'), findsOneWidget);
      expect(find.text('−35.00 EUR'), findsOneWidget);
      expect(find.text('2 transactions not converted'), findsOneWidget);
    });

    testWidgets('an empty period says "no transactions", never 0.00', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const PeriodTotalsText(totals: PeriodTotals.empty)),
      );

      expect(find.text('No transactions in this period'), findsOneWidget);
      expect(find.textContaining('0.00'), findsNothing);
    });
  });

  group('S-32 Spent vs Kept — AC-B10.3', () {
    PeriodReport report({
      String? spend = '1140.41',
      String? income = '14500.00',
      String? cash = '500.00',
      String? internal = '2000.00',
      int needsReview = 0,
      bool incomplete = false,
    }) => PeriodReport(
      baseCurrencyCode: 'SAR',
      spend: incomplete
          ? totals(
              base: spend,
              convertedCount: 5,
              byCurrency: <CurrencyTotal>[
                CurrencyTotal(
                  currencyCode: 'SAR',
                  net: Money.parse(spend!, currency: 'SAR'),
                  transactionCount: 5,
                ),
              ],
              unconverted: <UnconvertedGroup>[
                UnconvertedGroup(
                  currencyCode: 'EUR',
                  net: Money.parse('35.00', currency: 'EUR'),
                  transactionCount: 1,
                ),
              ],
            )
          : sar(spend!, count: 5),
      income: income == null ? PeriodTotals.empty : sar(income),
      cashWithdrawals: cash == null ? PeriodTotals.empty : sar(cash),
      internalTransfers: internal == null ? PeriodTotals.empty : sar(internal),
      fees: PeriodTotals.empty,
      needsReviewCount: needsReview,
    );

    testWidgets('every component of the netting is on screen, so the user can '
        'check it (NFR-A6)', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(wrap(SpentVsKeptCard(report: report())));
      await tester.pumpAndSettle();

      expect(find.text('Spent vs kept'), findsOneWidget);
      expect(find.text('Received'), findsOneWidget);
      expect(find.text('Spent'), findsOneWidget);
      expect(find.text('Kept this period'), findsOneWidget);

      // Each side signed by what it *means*, not by the shape of the value.
      // The bug this pins is a salary rendered as "−14500.00 SAR" because it
      // went through the spend convention — a figure that says the exact
      // opposite of the truth.
      expect(find.text('+14500.00 SAR'), findsOneWidget);
      expect(find.text('−1140.41 SAR'), findsOneWidget);
      // 14,500.00 − 1,140.41 = 13,359.59
      expect(find.text('+13359.59 SAR'), findsOneWidget);
    });

    testWidgets('cash withdrawn and internal transfers are shown but NOT '
        'netted — the money is still the user\'s', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(wrap(SpentVsKeptCard(report: report())));
      await tester.pumpAndSettle();

      expect(find.text('Cash withdrawn'), findsOneWidget);
      expect(find.text('Internal transfers excluded'), findsOneWidget);
      // No sign on either (design.md §3.3): a "−" on cash withdrawn would
      // read as spending, which is the reading AC-B10.2 exists to prevent.
      expect(find.text('500.00 SAR'), findsOneWidget);
      expect(find.text('−500.00 SAR'), findsNothing);
      expect(find.text('2000.00 SAR'), findsOneWidget);
      // If cash had been subtracted the net would be 12,859.59.
      expect(find.text('+12859.59 SAR'), findsNothing);
    });

    testWidgets('a period that spent more than it received shows a negative '
        'kept figure rather than clamping to zero', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          SpentVsKeptCard(
            report: report(spend: '2000.00', income: '500'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('−1500.00 SAR'), findsOneWidget);
    });

    testWidgets('with no data at all it says so, rather than showing 0.00', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(const SpentVsKeptCard(report: PeriodReport.empty)),
      );
      await tester.pumpAndSettle();

      expect(find.text('No transactions in this period'), findsWidgets);
      expect(find.textContaining('0.00 SAR'), findsNothing);
    });

    testWidgets('an incomplete report says the figures are incomplete', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(SpentVsKeptCard(report: report(incomplete: true))),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be converted'), findsOneWidget);
    });

    testWidgets('pending review items make the figures provisional, and say '
        'so (AC-B11.2)', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(SpentVsKeptCard(report: report(needsReview: 2))),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('2 transactions need review before these figures are final'),
        findsOneWidget,
      );
    });

    testWidgets('renders in Arabic RTL at a 2.0 text scale without '
        'overflowing (NFR-U3, NFR-U8)', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(SpentVsKeptCard(report: report()), locale: 'ar', textScale: 2.0),
      );
      await tester.pumpAndSettle();

      expect(find.text('المصروف مقابل المتبقي'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

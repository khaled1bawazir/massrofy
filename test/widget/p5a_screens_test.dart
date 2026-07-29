/// **Widget tests for P5a's screens** — KHA-35 (S-08 Home) and KHA-36 (S-10
/// Transaction List, plus the shared `TransactionListItem`).
///
/// | Surface | Acceptance criteria |
/// |---|---|
/// | `MonthTotalCard` | **AC-E1.1**, **AC-E1.3**, and design.md §3.4's loading/error states |
/// | `PeriodSelector` | **AC-E1.4** — the prior month stays viewable, "next" is dead on the current month |
/// | `TransactionListItem` | **AC-B4.3**, **AC-B7.3**, **AC-C4.1**, AC-B11.1, NFR-U4 |
/// | S-10 `TransactionListScreen` | the two empty states, the running total, KHA-74's unreadable note |
///
/// Following the existing suites' rules: **both locales** (Arabic RTL is the
/// primary direction — design.md §3.1), and the dense screens at a **2.0 text
/// scale**, because NFR-U3 requires no truncation at the largest OS font size.
///
/// NFR-M3: every merchant string here is synthetic.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/features/categorization/categories.dart';
import 'package:massrofy/features/categorization/learned_rules.dart';
import 'package:massrofy/features/ledger/internal_transfer.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';
import 'package:massrofy/presentation/screens/transaction_list_screen.dart';
import 'package:massrofy/presentation/widgets/period_widgets.dart';
import 'package:massrofy/presentation/widgets/transaction_list_item.dart';

import 'p3_screens_test.dart' show useTallSurface, wrap;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final PeriodRange july2026 = PeriodRange(
  startUtc: DateTime.utc(2026, 6, 30, 21),
  endUtcExclusive: DateTime.utc(2026, 7, 31, 21),
);

LedgerTransaction row({
  int id = 1,
  String amount = '45.00',
  String direction = 'debit',
  String type = TransactionType.posPurchase,
  String? merchant = 'QANDA FOODS',
  bool needsReview = false,
  String? reviewReason,
  String provenance = TransactionProvenance.sms,
  String? transferState,
  DateTime? at,
}) => LedgerTransaction(
  id: id,
  amount: Money.parse(amount, currency: 'SAR'),
  direction: direction,
  transactionType: type,
  affectsSpend: true,
  occurredAt: at ?? DateTime.utc(2026, 7, 15, 11, 20),
  merchantRawText: merchant,
  needsReview: needsReview,
  reviewReason: reviewReason,
  provenance: provenance,
  internalTransferState: transferState,
);

PeriodTotals totalsOf(String amount, {int count = 1}) => PeriodTotals(
  base: Money.parse(amount, currency: 'SAR'),
  baseCurrencyCode: 'SAR',
  convertedCount: count,
  byCurrency: <CurrencyTotal>[
    CurrencyTotal(
      currencyCode: 'SAR',
      net: Money.parse(amount, currency: 'SAR'),
      transactionCount: count,
    ),
  ],
  unconverted: const <UnconvertedGroup>[],
);

Widget listScreen({
  required List<LedgerTransaction> transactions,
  PeriodTotals? totals,
  bool ledgerHasAnyTransactions = false,
  bool isLoading = false,
  bool hasError = false,
  int unreadableCount = 0,
  bool isCurrentMonth = true,
  Map<int, String> transferStates = const <int, String>{},
  Map<int, CategoryAssignment> assignments = const <int, CategoryAssignment>{},
  void Function(LedgerTransaction)? onOpen,
  VoidCallback? onPrevious,
  VoidCallback? onNext,
}) => TransactionListScreen(
  transactions: transactions,
  totals: totals ?? PeriodTotals.empty,
  period: july2026,
  isCurrentMonth: isCurrentMonth,
  internalTransferStates: transferStates,
  categoryAssignments: assignments,
  ledgerHasAnyTransactions: ledgerHasAnyTransactions,
  unreadableCount: unreadableCount,
  isLoading: isLoading,
  hasError: hasError,
  onOpenTransaction: onOpen,
  onPreviousMonth: onPrevious ?? () {},
  onNextMonth: onNext ?? () {},
  onCurrentMonth: () {},
);

void main() {
  // =======================================================================
  group('MonthTotalCard — AC-E1.1 / AC-E1.3 (KHA-35)', () {
    testWidgets('AC-E1.1 — the current-month figure is on screen with no '
        'navigation, in both locales', (WidgetTester tester) async {
      for (final String locale in <String>['en', 'ar']) {
        await tester.pumpWidget(
          wrap(
            Scaffold(
              body: MonthTotalCard(totals: totalsOf('3214.50', count: 9)),
            ),
            locale: locale,
          ),
        );
        await tester.pump();

        // The `−` is U+2212, not a hyphen: `formatSignedAmount` uses the real
        // minus sign so the figure reads correctly in both directions.
        expect(
          find.text('−3214.50 SAR'),
          findsOneWidget,
          reason: 'locale $locale',
        );
      }
    });

    testWidgets('**AC-E1.3** — an empty month renders an explicit 0.00 AND '
        'the caption that says nothing has been recorded', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const Scaffold(body: MonthTotalCard(totals: PeriodTotals.empty))),
      );
      await tester.pump();

      // The figure answers the ten-second question; the caption stops the user
      // reading it as "you spent nothing". Both, or neither is honest.
      expect(find.byKey(const Key('home.monthTotal.empty')), findsOneWidget);
      expect(find.text('0.00 SAR'), findsOneWidget);
      expect(
        find.text('No transactions recorded yet this month'),
        findsOneWidget,
      );
    });

    testWidgets('while loading, there is NO figure at all — not a 0.00 the '
        'user might read and believe', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const Scaffold(
            body: MonthTotalCard(totals: PeriodTotals.empty, isLoading: true),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('SAR'), findsNothing);
      expect(find.textContaining('0.00'), findsNothing);
    });

    testWidgets('a failed read renders an error, never a reassuring zero', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const Scaffold(
            body: MonthTotalCard(totals: PeriodTotals.empty, hasError: true),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('home.monthTotal.error')), findsOneWidget);
      expect(find.text('0.00 SAR'), findsNothing);
    });

    testWidgets('Arabic RTL at 2.0 text scale — no overflow (NFR-U3/U8)', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          Scaffold(body: MonthTotalCard(totals: totalsOf('12345.67'))),
          locale: 'ar',
          textScale: 2.0,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('هذا الشهر'), findsOneWidget);
    });
  });

  // =======================================================================
  group('PeriodSelector — AC-E1.4 (KHA-35)', () {
    testWidgets('the month is named in the locale, from the RIYADH wall clock '
        'not the UTC start instant', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: PeriodSelector(
              period: july2026,
              isCurrentMonth: true,
              onPreviousMonth: () {},
              onNextMonth: () {},
              onCurrentMonth: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      // `july2026.startUtc` is 2026-06-30T21:00Z. Naming that instant directly
      // would title July's figures "June 2026".
      expect(find.text('July 2026'), findsOneWidget);
    });

    testWidgets('"next month" is disabled on the current month — there is '
        'nothing after now', (WidgetTester tester) async {
      int forwards = 0;
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: PeriodSelector(
              period: july2026,
              isCurrentMonth: true,
              onPreviousMonth: () {},
              onNextMonth: () => forwards++,
              onCurrentMonth: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('period.next')));
      await tester.pump();
      expect(forwards, 0);
      // …and the "back to this month" shortcut is absent, because we are on it.
      expect(find.byKey(const Key('period.current')), findsNothing);
    });

    testWidgets('on an older month, both the forward arrow and the "This '
        'month" shortcut work', (WidgetTester tester) async {
      int forwards = 0;
      int resets = 0;
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: PeriodSelector(
              period: july2026,
              isCurrentMonth: false,
              onPreviousMonth: () {},
              onNextMonth: () => forwards++,
              onCurrentMonth: () => resets++,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('period.next')));
      await tester.tap(find.byKey(const Key('period.current')));
      await tester.pump();

      expect(forwards, 1);
      expect(resets, 1);
    });

    testWidgets('the month label renders in Arabic under RTL', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: PeriodSelector(
              period: july2026,
              isCurrentMonth: true,
              onPreviousMonth: () {},
              onNextMonth: () {},
              onCurrentMonth: () {},
            ),
          ),
          locale: 'ar',
        ),
      );
      await tester.pump();

      final Text label = tester.widget<Text>(
        find.byKey(const Key('period.label')),
      );
      // Not asserting the exact Arabic month name — that belongs to
      // `GlobalMaterialLocalizations`, not to us. What matters is that the
      // label is localised at all rather than falling back to English.
      expect(label.data, isNot('July 2026'));
      expect(label.data, contains('2026'));
    });
  });

  // =======================================================================
  group('TransactionListItem — the row-level ACs (KHA-36)', () {
    testWidgets('**AC-B7.3 / NFR-U4** — a debit and a credit differ in their '
        'SIGN and their semantic label, not only in colour', (
      WidgetTester tester,
    ) async {
      // Semantics are off by default in widget tests; without this handle the
      // screen-reader assertions below would find nothing and pass for the
      // wrong reason once inverted.
      final SemanticsHandle semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: Column(
              children: <Widget>[
                TransactionListItem(transaction: row(id: 1, amount: '45.00')),
                TransactionListItem(
                  transaction: row(
                    id: 2,
                    amount: '9000.00',
                    direction: 'credit',
                    type: TransactionType.salaryIncome,
                    merchant: null,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('−45.00 SAR'), findsOneWidget);
      expect(find.text('+9000.00 SAR'), findsOneWidget);
      // The screen-reader half of the same guarantee. A `RegExp` rather than an
      // exact string because the announced label merges the widget's own label
      // with the figure underneath it — what matters is that the *direction* is
      // spoken at all, not the exact concatenation.
      expect(find.bySemanticsLabel(RegExp('Debit')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Credit')), findsOneWidget);

      // Disposed inside the body, not via `addTearDown`: the framework's
      // "a SemanticsHandle was active at the end of the test" check runs
      // *before* tear-downs, so a deferred dispose fails a test whose
      // assertions all passed.
      semantics.dispose();
    });

    testWidgets('**AC-B4.3** — a manually entered transaction carries an icon '
        'AND the word "Manual"; an SMS-derived one carries neither', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: Column(
              children: <Widget>[
                TransactionListItem(
                  transaction: row(
                    id: 1,
                    provenance: TransactionProvenance.manual,
                    merchant: 'CASH AT SOUQ',
                  ),
                ),
                TransactionListItem(transaction: row(id: 2)),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Manual'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('**AC-C4.1** — a flagged row carries the needs-review badge', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: TransactionListItem(transaction: row(needsReview: true)),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('needsReviewBadge')), findsOneWidget);
      expect(find.text('Needs review'), findsOneWidget);
    });

    testWidgets('AC-B11.1 — a CONFIRMED internal transfer carries no +/− '
        'prefix at all, while a candidate keeps its sign', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: Column(
              children: <Widget>[
                TransactionListItem(
                  transaction: row(id: 1, amount: '2000.00', merchant: null),
                  internalTransferState: InternalTransferState.internal,
                ),
                TransactionListItem(
                  transaction: row(id: 2, amount: '1500.00', merchant: null),
                  internalTransferState: InternalTransferState.candidate,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // A sign would place a movement on a side of the ledger it does not
      // belong to — it is neither spend nor income.
      expect(find.text('2000.00 SAR'), findsOneWidget);
      expect(find.text('−2000.00 SAR'), findsNothing);
      // The candidate is still being counted, so it keeps its sign.
      expect(find.text('−1500.00 SAR'), findsOneWidget);
      expect(find.text('Internal transfer'), findsOneWidget);
    });

    testWidgets('AC-B1.3 — a transaction with no date says so explicitly '
        'rather than rendering a blank line', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: TransactionListItem(
              transaction: LedgerTransaction(
                id: 1,
                amount: Money.parse('12.00', currency: 'SAR'),
                direction: 'debit',
                transactionType: TransactionType.posPurchase,
                affectsSpend: true,
                merchantRawText: 'QANDA FOODS',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Not stated in message'), findsOneWidget);
    });

    testWidgets('a transaction with no merchant and no counterparty falls back '
        'to its TYPE, never to a blank or an invented name', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: TransactionListItem(
              transaction: row(
                merchant: null,
                type: TransactionType.billPayment,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Bill payment'), findsOneWidget);
    });

    testWidgets('tapping the row opens the detail; tapping the chip opens the '
        'correction flow — §6.1\'s two-tap promise from a list', (
      WidgetTester tester,
    ) async {
      int rowTaps = 0;
      int chipTaps = 0;
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: TransactionListItem(
              transaction: row(),
              categoryAssignment: CategoryAssignment(
                category: DefaultCategories.uncategorized,
                band: ConfidenceBand.low,
              ),
              onTap: () => rowTaps++,
              onTapCategory: () => chipTaps++,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Uncategorized'));
      await tester.pump();
      expect(chipTaps, 1);
      expect(rowTaps, 0, reason: 'the chip must not also open the detail');

      await tester.tap(find.text('QANDA FOODS'));
      await tester.pump();
      expect(rowTaps, 1);
    });

    testWidgets('Arabic RTL at 2.0 text scale — three badges wrap rather than '
        'overflow (NFR-U3)', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: TransactionListItem(
              transaction: row(
                needsReview: true,
                provenance: TransactionProvenance.manual,
              ),
              internalTransferState: InternalTransferState.candidate,
              categoryAssignment: CategoryAssignment(
                category: DefaultCategories.uncategorized,
                band: ConfidenceBand.low,
              ),
            ),
          ),
          locale: 'ar',
          textScale: 2.0,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // =======================================================================
  group('S-10 TransactionListScreen (KHA-36)', () {
    testWidgets('the running total renders beside the rows it was computed '
        'from', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          listScreen(
            transactions: <LedgerTransaction>[
              row(id: 1, amount: '45.00'),
              row(id: 2, amount: '310.40', merchant: 'JARIR STORES'),
            ],
            totals: totalsOf('355.40', count: 2),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Total'), findsOneWidget);
      expect(find.text('−355.40 SAR'), findsOneWidget);
      expect(find.text('QANDA FOODS'), findsOneWidget);
      expect(find.text('JARIR STORES'), findsOneWidget);
    });

    testWidgets('**two different empty states**: "nothing ever" and "nothing '
        'this month" are not the same sentence', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(listScreen(transactions: const <LedgerTransaction>[])),
      );
      await tester.pump();
      expect(find.byKey(const Key('txnList.empty')), findsOneWidget);
      expect(find.text('No transactions yet'), findsOneWidget);

      await tester.pumpWidget(
        wrap(
          listScreen(
            transactions: const <LedgerTransaction>[],
            ledgerHasAnyTransactions: true,
          ),
        ),
      );
      await tester.pump();
      // Telling a user with two years of history "you have no transactions"
      // looks exactly like data loss.
      expect(find.byKey(const Key('txnList.emptyForPeriod')), findsOneWidget);
      expect(find.text('Nothing in this month'), findsOneWidget);
    });

    testWidgets('a failed read renders the error state, NOT an empty list', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          listScreen(transactions: const <LedgerTransaction>[], hasError: true),
        ),
      );
      await tester.pump();

      expect(
        find.text('This transaction could not be loaded.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('txnList.empty')), findsNothing);
      // …and no figure at all, for the same reason the month card shows none.
      expect(find.byKey(const Key('txnList.total')), findsNothing);
    });

    testWidgets('while loading, a spinner and no figure', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          listScreen(
            transactions: const <LedgerTransaction>[],
            isLoading: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('txnList.loading')), findsOneWidget);
      expect(find.byKey(const Key('txnList.total')), findsNothing);
    });

    testWidgets('KHA-74 — rows the build cannot read are NAMED, not silently '
        'missing from a shorter list', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          listScreen(
            transactions: <LedgerTransaction>[row()],
            totals: totalsOf('45.00'),
            unreadableCount: 2,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('txnList.unreadable')), findsOneWidget);
      expect(
        find.textContaining('2 transactions could not be read'),
        findsOneWidget,
      );
    });

    testWidgets('tapping a row opens the transaction it belongs to, by id', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      int? opened;
      await tester.pumpWidget(
        wrap(
          listScreen(
            transactions: <LedgerTransaction>[
              row(id: 7, merchant: 'JARIR STORES'),
            ],
            totals: totalsOf('45.00'),
            onOpen: (LedgerTransaction txn) => opened = txn.id,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('JARIR STORES'));
      await tester.pump();
      expect(opened, 7);
    });

    testWidgets('Arabic RTL at 2.0 text scale — the whole screen renders '
        'without overflow (NFR-U3, NFR-U8)', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          listScreen(
            transactions: <LedgerTransaction>[
              row(id: 1, needsReview: true),
              row(
                id: 2,
                amount: '9000.00',
                direction: 'credit',
                type: TransactionType.salaryIncome,
                merchant: null,
              ),
            ],
            totals: totalsOf('355.40', count: 2),
            unreadableCount: 1,
          ),
          locale: 'ar',
          textScale: 2.0,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('المعاملات'), findsOneWidget);
      expect(find.text('الإجمالي'), findsOneWidget);
    });
  });
}

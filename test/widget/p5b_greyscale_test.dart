/// **NFR-U4 on the reports screens** — *"never colour alone"* (KHA-37).
///
/// design.md §3.3 is a table of state → non-colour indicator, and `docs/brand.md`
/// §5.3 adds the clause that binds this phase specifically:
///
/// > *"never a bare, unlabelled colour-only chart."*
///
/// Reports are the one place in this app where a figure could plausibly exist
/// **only** as a pixel height or a swatch colour, so this file checks the
/// distinctions survive with colour removed. It follows the shape of
/// `p5a_greyscale_test.dart`: rather than screenshotting and desaturating, it
/// collects the *strings and icons* each element renders and proves they differ —
/// which is the property greyscale would be testing for, asserted directly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/month_comparison.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/presentation/l10n/generated/app_localizations.dart';
import 'package:massrofy/presentation/theme/app_colors.dart';
import 'package:massrofy/presentation/widgets/report_widgets.dart';

import '../support/ledger_fixtures.dart';

Widget wrap(Widget child, {String locale = 'en'}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: const <LocalizationsDelegate<Object?>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
  home: Scaffold(body: child),
);

/// Every string rendered under [of].
Set<String> textsUnder(Finder of) => <String>{
  for (final Element element
      in find.descendant(of: of, matching: find.byType(Text)).evaluate())
    if ((element.widget as Text).data case final String data) data,
};

PeriodTotals totals(String amount) {
  final Money value = Money.parse(amount, currency: 'SAR');
  return PeriodTotals(
    base: value,
    baseCurrencyCode: 'SAR',
    convertedCount: 1,
    byCurrency: <CurrencyTotal>[
      CurrencyTotal(currencyCode: 'SAR', net: value, transactionCount: 1),
    ],
    unconverted: const <UnconvertedGroup>[],
  );
}

void main() {
  group('AC-E2.1 — a share is text, not a slice size', () {
    testWidgets('the percentage is rendered as words and digits', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BreakdownRow(
            color: AppColors.chartNavy,
            label: 'Groceries',
            totals: totals('250.00'),
            sharePercent: percentShareOf(
              Money.parse('250.00', currency: 'SAR'),
              Money.parse('1000.00', currency: 'SAR'),
            ),
          ),
        ),
      );

      // The share and the figure are both legible with no colour at all. A pie
      // chart whose slices were the only carrier would fail here.
      expect(find.text('25% of the period'), findsOneWidget);
      expect(find.text('−250.00 SAR'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
    });

    testWidgets('the swatch is excluded from the semantics tree', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BreakdownRow(
            color: AppColors.chartGold,
            label: 'Dining & Cafés',
            totals: totals('100.00'),
            sharePercent: 10,
          ),
        ),
      );

      // NFR-U2: announcing "a coloured square" before every row would be noise,
      // and the label already carries everything the swatch reinforces.
      //
      // Asserted as "the swatch has an ExcludeSemantics ancestor" rather than
      // "the tree contains exactly one ExcludeSemantics": Flutter's own widgets
      // use it internally, so a bare type count would be measuring the framework
      // rather than this widget.
      expect(
        find.ancestor(
          of: find.byKey(const Key('breakdownRow.swatch')),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an uncomputable share says so instead of printing 0%', (
      WidgetTester tester,
    ) async {
      // A period whose credits exactly cancelled its debits: the denominator is
      // zero, so there is no share to report. "0%" would claim this category is a
      // vanishing part of a real total.
      expect(
        percentShareOf(
          Money.parse('100.00', currency: 'SAR'),
          Money.parse('0.00', currency: 'SAR'),
        ),
        isNull,
      );

      await tester.pumpWidget(
        wrap(
          BreakdownRow(
            color: AppColors.chartTeal,
            label: 'Groceries',
            totals: totals('100.00'),
          ),
        ),
      );
      expect(find.text('share not available'), findsOneWidget);
    });
  });

  group('AC-E4.1 — the delta reads without colour', () {
    MonthComparison comparison({
      required String current,
      required String prior,
    }) => MonthComparison.of(<LedgerTransaction>[
      tx(id: 1, amount: current, at: DateTime.utc(2026, 7, 15, 12)),
      tx(id: 2, amount: prior, at: DateTime.utc(2026, 6, 15, 12)),
    ], period: july2026);

    testWidgets('spending MORE and spending LESS render different words and '
        'different icons, not just different colours', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          MonthComparisonHeader(
            comparison: comparison(current: '1200.00', prior: '1000.00'),
          ),
        ),
      );
      final Set<String> up = textsUnder(find.byType(MonthComparisonHeader));
      final bool hasTrendingUp = find
          .byIcon(Icons.trending_up)
          .evaluate()
          .isNotEmpty;

      await tester.pumpWidget(
        wrap(
          MonthComparisonHeader(
            comparison: comparison(current: '800.00', prior: '1000.00'),
          ),
        ),
      );
      final Set<String> down = textsUnder(find.byType(MonthComparisonHeader));
      final bool hasTrendingDown = find
          .byIcon(Icons.trending_down)
          .evaluate()
          .isNotEmpty;

      expect(hasTrendingUp, isTrue);
      expect(hasTrendingDown, isTrue);
      expect(
        up.intersection(down).length,
        lessThan(up.length),
        reason:
            'the two directions must differ in TEXT, not only in colour and not '
            'only in a bare signed number — "+200.00" beside two totals is '
            'ambiguous about which direction it belongs to',
      );
      expect(up.any((String s) => s.contains('more than')), isTrue);
      expect(down.any((String s) => s.contains('less than')), isTrue);
    });

    testWidgets('an exactly-equal period says so rather than showing "0.00 '
        'more"', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          MonthComparisonHeader(
            comparison: comparison(current: '1000.00', prior: '1000.00'),
          ),
        ),
      );
      expect(find.textContaining('The same as'), findsOneWidget);
    });
  });

  group('brand.md §5.3 — the bar chart is never colour-only', () {
    testWidgets('every bar announces its figure, and every column is labelled '
        'with its month', (WidgetTester tester) async {
      final MonthComparison comparison = MonthComparison.of(<LedgerTransaction>[
        tx(id: 1, amount: '100.00', at: DateTime.utc(2026, 5, 15, 12)),
        tx(id: 2, amount: '200.00', at: DateTime.utc(2026, 6, 15, 12)),
        tx(id: 3, amount: '300.00', at: DateTime.utc(2026, 7, 15, 12)),
      ], period: july2026);

      await tester.pumpWidget(wrap(MonthTrailChart(bars: comparison.trail)));
      await tester.pump();

      // The month labels — a chart whose axis the user cannot read is decoration.
      for (final String month in <String>[
        'May 2026',
        'June 2026',
        'July 2026',
      ]) {
        expect(find.text(month), findsOneWidget, reason: month);
      }

      // And each bar's figure is on the semantics tree, so a screen-reader user
      // gets the number rather than "a rectangle".
      final SemanticsHandle handle = tester.ensureSemantics();
      for (final String figure in <String>[
        '100.00 SAR',
        '200.00 SAR',
        '300.00 SAR',
      ]) {
        expect(
          find.bySemanticsLabel(figure),
          findsOneWidget,
          reason: 'no bar announces $figure',
        );
      }
      handle.dispose();
    });

    testWidgets('a month with no figure draws NO bar, which is different from a '
        'flat one', (WidgetTester tester) async {
      final MonthComparison comparison = MonthComparison.of(<LedgerTransaction>[
        tx(id: 1, amount: '200.00', at: DateTime.utc(2026, 6, 15, 12)),
        tx(id: 2, amount: '300.00', at: DateTime.utc(2026, 7, 15, 12)),
      ], period: july2026);

      await tester.pumpWidget(wrap(MonthTrailChart(bars: comparison.trail)));
      await tester.pump();

      // May is absent from the data. "We have nothing for this month" and "you
      // spent nothing" are different facts — `PeriodTotals.base`'s nullability
      // exists to keep them apart, and the chart honours it.
      expect(comparison.trail.first.isEmpty, isTrue);
      // Two bars drawn, not three: the empty month contributes no `DecoratedBox`.
      expect(find.byType(DecoratedBox), findsNWidgets(2));
      // …but its column is still labelled, so the gap is explained rather than
      // looking like a rendering bug.
      expect(find.text('May 2026'), findsOneWidget);
    });
  });
}

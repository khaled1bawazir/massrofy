/// **US-E5 — search and filter** (KHA-38). AC-E5.1, AC-E5.2, AC-E5.3, NFR-S4.
///
/// ---
///
/// ## The two things worth testing hard here
///
/// **1. AC-E5.1 across two scripts.** PRD §3.4: merchant names arrive
/// *transliterated into Latin even inside an Arabic message*, and Arabic itself
/// spells the same merchant several ways (`أ`/`ا`, `ة`/`ه`, with and without
/// diacritics or tatweel). KHA-38's done check is explicit: *"Arabic and Latin
/// merchant searches both return the expected fixtures."* A test with one
/// same-script fixture would pass against a naive `contains`.
///
/// **2. AC-E5.2's total.** *"The displayed total reflects the FILTERED SUBSET, not
/// the whole period."* The invariant is that `LedgerTotals.spend` over
/// `filter.apply(...)`'s output equals a hand-computed sum of exactly the rows that
/// came back — asserted here against literals rather than by calling the same
/// function twice.
///
/// **NFR-S4** gets its own group. *"Search queries and results must not be logged
/// — a search history is a record of what the user was looking for in their
/// financial life."* `TransactionFilter.toString` is the most plausible accidental
/// leak (it is what a debugger, an assertion message and an exception all print),
/// so it is asserted to report facet *shapes* and never values.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/core/money/sign_convention.dart';
import 'package:massrofy/features/categorization/categories.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_filter.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

import '../../support/ledger_fixtures.dart';

final CategoryResolver resolver = CategoryResolver.defaults();

/// A transaction with a merchant, a category and (optionally) an instrument.
///
/// `ledger_fixtures.dart`'s `tx` predates P4a and carries neither a merchant nor a
/// category, and adding them there would touch every P3b test. Building the row
/// directly here keeps this file's fixtures readable.
LedgerTransaction row({
  required int id,
  required String amount,
  String? merchant,
  String? counterparty,
  String? categoryId,
  String currency = 'SAR',
  String? convertedAmount,
  bool conversionPending = false,
  int day = 15,
  LedgerInstrument? on,
  String direction = MovementDirection.debit,
  String type = TransactionType.posPurchase,
  DateTime? at,
}) => LedgerTransaction(
  id: id,
  amount: Money.parse(amount, currency: currency),
  direction: direction,
  transactionType: type,
  affectsSpend: true,
  occurredAt: at ?? DateTime.utc(2026, 7, day, 12),
  merchantRawText: merchant,
  counterpartyName: counterparty,
  categoryId: categoryId,
  convertedAmount: convertedAmount == null
      ? null
      : Money.parse(convertedAmount, currency: 'SAR'),
  conversionPending: conversionPending,
  instrument: on,
);

void main() {
  final LedgerInstrument card = instrument(
    id: 11,
    bankId: 1,
    kind: InstrumentKind.card,
    masked: '****4821',
  );
  final LedgerInstrument account = instrument(id: 10, bankId: 1);

  // ---------------------------------------------------------------------
  // The fixture set. Merchant strings deliberately span both scripts and both
  // spellings, per PRD §3.4.
  // ---------------------------------------------------------------------
  final List<LedgerTransaction> ledger = <LedgerTransaction>[
    row(
      id: 1,
      amount: '152.75',
      // Latin, inside what would have been an Arabic message.
      merchant: 'PANDA MARKET 0042',
      categoryId: 'groceries',
      on: card,
      day: 3,
    ),
    row(
      id: 2,
      amount: '48.00',
      // Arabic, with a teh marbuta the user may or may not type.
      merchant: 'مقهى القهوة العربية',
      categoryId: 'dining',
      on: card,
      day: 10,
    ),
    row(
      id: 3,
      amount: '900.00',
      merchant: 'IKEA RIYADH',
      categoryId: 'shopping_retail',
      on: account,
      day: 18,
    ),
    row(
      id: 4,
      amount: '35.50',
      // No merchant at all — a transfer names a payee instead.
      counterparty: 'فاطمة',
      categoryId: null,
      type: TransactionType.transferOut,
      on: account,
      day: 22,
    ),
    row(
      id: 5,
      amount: '20.00',
      currency: 'USD',
      // No converted amount and no rate → ADR-009 case 4. Cannot be compared to
      // an amount bound at all.
      conversionPending: true,
      merchant: 'NOON.COM',
      categoryId: 'shopping_retail',
      on: card,
      day: 25,
    ),
  ];

  FilterOutcome apply(TransactionFilter filter) =>
      filter.apply(ledger, resolver: resolver);

  List<int> idsFrom(FilterOutcome outcome) =>
      outcome.transactions.map((LedgerTransaction t) => t.id).toList();

  group('the neutral filter', () {
    test('matches everything and is not "active"', () {
      expect(TransactionFilter.none.isActive, isFalse);
      expect(TransactionFilter.none.activeFacetCount, 0);
      expect(idsFrom(apply(TransactionFilter.none)), <int>[1, 2, 3, 4, 5]);
    });

    test('a whitespace-only query is not active either', () {
      // Otherwise a user who tapped the space bar would be shown AC-E5.3's
      // filtered-empty copy about a filter that filters nothing.
      const TransactionFilter filter = TransactionFilter(query: '   ');
      expect(filter.isActive, isFalse);
      expect(idsFrom(apply(filter)).length, 5);
    });
  });

  group('AC-E5.1 — merchant search, both scripts', () {
    test('a Latin fragment matches a Latin merchant, case-insensitively', () {
      expect(idsFrom(apply(const TransactionFilter(query: 'panda'))), <int>[1]);
      expect(idsFrom(apply(const TransactionFilter(query: 'PaNdA'))), <int>[1]);
      // A mid-string fragment, not only a prefix.
      expect(idsFrom(apply(const TransactionFilter(query: 'MARKET'))), <int>[
        1,
      ]);
    });

    test('an Arabic fragment matches an Arabic merchant', () {
      expect(idsFrom(apply(const TransactionFilter(query: 'مقهى'))), <int>[2]);
    });

    test('**Arabic orthographic variants match** — the user never has to spell '
        'the merchant the way the bank did', () {
      // The stored name is "مقهى القهوة العربية". Each query below differs from
      // it by exactly one of the folds ADR-008 defines, and a raw `contains`
      // would fail all three.
      for (final String query in <String>[
        // teh marbuta -> heh: "القهوه" for "القهوة".
        'القهوه',
        // alef maksura -> yeh: "مقهي" for "مقهى".
        'مقهي',
        // Arabic diacritics, which a user with a full keyboard may type.
        'الْقَهْوَة',
      ]) {
        expect(
          idsFrom(apply(TransactionFilter(query: query))),
          <int>[2],
          reason: 'query "$query" must fold to the stored merchant name',
        );
      }
    });

    test('Arabic-Indic digits in a query match Western digits in the name', () {
      // "PANDA MARKET 0042" — the store number, typed on an Arabic keypad.
      expect(idsFrom(apply(const TransactionFilter(query: '٠٠٤٢'))), <int>[1]);
    });

    test(
      'a counterparty is searchable, because a transfer has no merchant',
      () {
        expect(idsFrom(apply(const TransactionFilter(query: 'فاطمة'))), <int>[
          4,
        ]);
      },
    );

    test('the transaction TYPE is deliberately not searched', () {
      // Matching the app's own vocabulary would make a query for "purchase"
      // return rows whose merchant the user never named — results they cannot
      // explain and cannot narrow.
      expect(
        idsFrom(apply(const TransactionFilter(query: 'purchase'))),
        isEmpty,
      );
    });

    test('a query matching nothing yields an explicitly FILTERED-empty result '
        '(AC-E5.3)', () {
      final FilterOutcome outcome = apply(
        const TransactionFilter(query: 'zzzz-no-such-merchant'),
      );
      expect(outcome.transactions, isEmpty);
      expect(
        outcome.isFilteredEmpty,
        isTrue,
        reason:
            'this is what tells the screen to say "no transactions match" and '
            'offer a clear action, rather than "you have no transactions" — '
            'which, to a user with five, looks exactly like data loss',
      );
    });
  });

  group('AC-E5.2 — the other three facets', () {
    test('a date range is half-open, and an undated row fails it', () {
      final FilterOutcome outcome = apply(
        TransactionFilter(
          fromUtc: DateTime.utc(2026, 7, 10),
          toUtcExclusive: DateTime.utc(2026, 7, 19),
        ),
      );
      // Row 2 is the 10th (inclusive lower bound), row 3 the 18th. Row 1 (3rd) and
      // rows 4/5 (22nd, 25th) are outside.
      expect(idsFrom(outcome), <int>[2, 3]);

      // A movement the message never dated cannot be asserted to fall inside a
      // window the user chose — the same rule `PeriodRange.contains` applies.
      final LedgerTransaction undated = LedgerTransaction(
        id: 99,
        amount: Money.parse('10.00', currency: 'SAR'),
        direction: MovementDirection.debit,
        transactionType: TransactionType.posPurchase,
        affectsSpend: true,
      );
      expect(
        TransactionFilter(
          fromUtc: DateTime.utc(2026, 7),
          toUtcExclusive: DateTime.utc(2026, 8),
        ).apply(<LedgerTransaction>[undated], resolver: resolver).transactions,
        isEmpty,
      );
    });

    test('a category facet includes Uncategorized as a first-class choice', () {
      expect(
        idsFrom(
          apply(const TransactionFilter(categoryIds: <String>{'groceries'})),
        ),
        <int>[1],
      );
      // Row 4 has a null category id, which resolves to Uncategorized. "Show me
      // what the app could not label" is one of the most useful filters here.
      expect(
        idsFrom(
          apply(
            const TransactionFilter(
              categoryIds: <String>{CategoryIds.uncategorized},
            ),
          ),
        ),
        <int>[4],
      );
    });

    test('an instrument facet selects only that card or account', () {
      expect(
        idsFrom(apply(const TransactionFilter(instrumentIds: <int>{11}))),
        <int>[1, 2, 5],
      );
      expect(
        idsFrom(apply(const TransactionFilter(instrumentIds: <int>{10}))),
        <int>[3, 4],
      );
    });

    test('facets compose as AND, not OR', () {
      final FilterOutcome outcome = apply(
        const TransactionFilter(
          instrumentIds: <int>{11},
          categoryIds: <String>{'dining'},
        ),
      );
      expect(idsFrom(outcome), <int>[2]);
    });

    test('the amount range compares MAGNITUDES, so a credit is not dropped', () {
      final List<LedgerTransaction> withRefund = <LedgerTransaction>[
        ...ledger,
        row(
          id: 6,
          amount: '200.00',
          merchant: 'PANDA MARKET 0042',
          direction: MovementDirection.credit,
          type: TransactionType.refund,
          categoryId: 'groceries',
          on: card,
        ),
      ];
      final FilterOutcome outcome = TransactionFilter(
        minAmount: Money.parse('100.00', currency: 'SAR'),
        maxAmount: Money.parse('300.00', currency: 'SAR'),
      ).apply(withRefund, resolver: resolver);

      // 152.75 and the 200.00 refund. Signing the comparison would drop every
      // credit out of every range — a user filtering "100 to 300" means the size
      // of the movement.
      expect(idsFrom(outcome), <int>[1, 6]);
    });

    test('a row with no base-currency figure is EXCLUDED from an amount range '
        'and COUNTED (ADR-009 case 4)', () {
      final FilterOutcome outcome = apply(
        TransactionFilter(minAmount: Money.parse('1.00', currency: 'SAR')),
      );

      // Row 5 is 20.00 USD with no rate: there is nothing to compare to the
      // bound. Excluding it is the safer direction — including it would put a row
      // the user asked to bound outside their bound.
      expect(idsFrom(outcome), <int>[1, 2, 3, 4]);
      expect(
        outcome.notComparableByAmount,
        1,
        reason:
            'a filter that quietly omits a purchase is the same defect as a '
            'total that quietly omits one — the screen renders this count',
      );
    });

    test('the not-comparable count only blames the AMOUNT facet', () {
      // Row 5 is excluded here by its *category*, not by the amount bound, so
      // reporting it as "could not be compared by amount" would be a different
      // and alarming claim.
      final FilterOutcome outcome = apply(
        TransactionFilter(
          categoryIds: const <String>{'groceries'},
          minAmount: Money.parse('1.00', currency: 'SAR'),
        ),
      );
      expect(idsFrom(outcome), <int>[1]);
      expect(outcome.notComparableByAmount, 0);
    });

    test('a converted foreign row IS comparable, on its own recorded rate', () {
      final List<LedgerTransaction> withConverted = <LedgerTransaction>[
        row(
          id: 7,
          amount: '20.00',
          currency: 'USD',
          convertedAmount: '75.00',
          merchant: 'NOON.COM',
          categoryId: 'shopping_retail',
        ),
      ];
      // Bounded 50–100 SAR. The native figure is 20.00, so a naive implementation
      // comparing the native amount would exclude it; the base figure is 75.00.
      final FilterOutcome outcome = TransactionFilter(
        minAmount: Money.parse('50.00', currency: 'SAR'),
        maxAmount: Money.parse('100.00', currency: 'SAR'),
      ).apply(withConverted, resolver: resolver);

      expect(idsFrom(outcome), <int>[7]);
      expect(outcome.notComparableByAmount, 0);
    });
  });

  group('AC-E5.2 — the total reflects the filtered subset', () {
    test('a filtered total equals a hand-computed sum of the visible rows', () {
      final FilterOutcome outcome = apply(
        const TransactionFilter(instrumentIds: <int>{10}),
      );
      expect(idsFrom(outcome), <int>[3, 4]);

      final PeriodTotals filteredTotal = LedgerTotals.spend(
        outcome.transactions,
        period: july2026,
      );

      // 900.00 + 35.50, added up by hand — the independent oracle. Calling
      // `LedgerTotals` twice and comparing would pass even if it were wrong.
      expect(filteredTotal.base, Money.parse('935.50', currency: 'SAR'));

      // And it is genuinely a SUBSET: the unfiltered period total is larger.
      //
      // 152.75 + 48.00 + 900.00 + 35.50 = 1,136.25. The 20.00 USD row is absent
      // because it has no base-currency figure (ADR-009 case 4) — which is also
      // why `whole.isIncomplete` is true below rather than the figure silently
      // being short.
      final PeriodTotals whole = LedgerTotals.spend(ledger, period: july2026);
      expect(whole.base, Money.parse('1136.25', currency: 'SAR'));
      expect(whole.isIncomplete, isTrue);
      expect(filteredTotal.base! < whole.base!, isTrue);
    });

    test('a search-filtered total is the sum of exactly the matching rows', () {
      final FilterOutcome outcome = apply(
        const TransactionFilter(query: 'IKEA'),
      );
      expect(
        LedgerTotals.spend(outcome.transactions, period: july2026).base,
        Money.parse('900.00', currency: 'SAR'),
      );
    });

    test('an empty filtered result has no figure, rather than a zero', () {
      final FilterOutcome outcome = apply(
        const TransactionFilter(query: 'nothing-matches-this'),
      );
      final PeriodTotals totals = LedgerTotals.spend(
        outcome.transactions,
        period: july2026,
      );
      // `null`, not `Money.zero`. "Nothing matched" and "the matches sum to zero"
      // are different facts, and `PeriodTotalsText` renders them differently.
      expect(totals.base, isNull);
      expect(totals.isEmpty, isTrue);
    });
  });

  group('facet counting, for the filter button badge', () {
    test('a date range counts once even with both ends set', () {
      expect(
        TransactionFilter(
          fromUtc: DateTime.utc(2026, 7),
          toUtcExclusive: DateTime.utc(2026, 8),
        ).activeFacetCount,
        1,
      );
    });

    test('an amount range counts once even with both bounds set', () {
      expect(
        TransactionFilter(
          minAmount: Money.parse('1.00', currency: 'SAR'),
          maxAmount: Money.parse('2.00', currency: 'SAR'),
        ).activeFacetCount,
        1,
      );
    });

    test('several categories still count as one facet', () {
      expect(
        const TransactionFilter(
          categoryIds: <String>{'groceries', 'dining'},
        ).activeFacetCount,
        1,
      );
    });

    test('all five facets together count five', () {
      expect(
        TransactionFilter(
          query: 'panda',
          fromUtc: DateTime.utc(2026, 7),
          categoryIds: const <String>{'groceries'},
          instrumentIds: const <int>{11},
          maxAmount: Money.parse('500.00', currency: 'SAR'),
        ).activeFacetCount,
        5,
      );
    });
  });

  group('copyWith can REMOVE a bound, not only change one', () {
    test('clearDateRange and clearAmountRange actually clear', () {
      final TransactionFilter filter = TransactionFilter(
        query: 'panda',
        fromUtc: DateTime.utc(2026, 7),
        toUtcExclusive: DateTime.utc(2026, 8),
        minAmount: Money.parse('1.00', currency: 'SAR'),
      );

      // Without the explicit flags this would be impossible: `null` already means
      // "leave unchanged" for an optional named parameter.
      final TransactionFilter cleared = filter.copyWith(
        clearDateRange: true,
        clearAmountRange: true,
      );
      expect(cleared.fromUtc, isNull);
      expect(cleared.toUtcExclusive, isNull);
      expect(cleared.minAmount, isNull);
      expect(cleared.maxAmount, isNull);
      // The query survives, because only the named ranges were cleared.
      expect(cleared.query, 'panda');
      expect(cleared.activeFacetCount, 1);
    });
  });

  group('NFR-S4 — the filter never carries its own values into a string', () {
    test('toString reports facet SHAPES, never the query, merchant, amount or '
        'date', () {
      final TransactionFilter filter = TransactionFilter(
        query: 'my divorce lawyer',
        fromUtc: DateTime.utc(2026, 7, 3),
        categoryIds: const <String>{'health_pharmacy'},
        instrumentIds: const <int>{11},
        minAmount: Money.parse('4500.00', currency: 'SAR'),
      );

      final String rendered = filter.toString();

      // A `toString` is what a debugger, an assertion message and an uncaught
      // exception all print, which makes it the most plausible accidental route
      // for a search term into a diagnostic file the user may later share
      // (ADR-015). The same discipline `LedgerTransaction.toString` follows.
      expect(rendered, isNot(contains('divorce')));
      expect(rendered, isNot(contains('4500')));
      expect(rendered, isNot(contains('2026-07-03')));
      expect(rendered, isNot(contains('health_pharmacy')));
      // What it DOES say is enough to debug with.
      expect(rendered, contains('facets: 5'));
      expect(rendered, contains('query: set'));
      expect(rendered, contains('dates: set'));
      expect(rendered, contains('amount: set'));
    });

    test('an unset filter says "unset" rather than printing empties', () {
      final String rendered = TransactionFilter.none.toString();
      expect(rendered, contains('facets: 0'));
      expect(rendered, contains('query: unset'));
      expect(rendered, contains('dates: unset'));
      expect(rendered, contains('amount: unset'));
    });
  });
}

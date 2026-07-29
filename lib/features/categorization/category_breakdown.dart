/// **AC-C1.3 — the category-sum invariant**, and the type that makes it hard
/// to break.
///
/// > *The sum of all category totals, **including Uncategorized**, must equal
/// > the overall period total. Any category operation that can break that
/// > invariant is a defect.*
///
/// `docs/build-plan.md` calls this *"a reconciliation guarantee, not a display
/// detail"*, and this build has been burned twice by money going missing from
/// a total with no signal (KHA-74, KHA-87). So the invariant is not left to a
/// test to notice after the fact — it is a property of how the numbers are
/// produced.
///
/// ## How it is guaranteed rather than checked
///
/// [CategoryBreakdown.of] does **not** re-implement any arithmetic. It:
///
///  1. computes the internal-transfer analysis **once, over the whole set**
///     (getting this wrong is, per `period_totals.dart`, "the most plausible
///     way to reintroduce AC-B11.1 as a bug" — a transfer's two legs must be
///     judged together, and a per-category slice contains one leg and not the
///     other);
///  2. partitions the transactions by their resolved category;
///  3. calls **the same** `LedgerTotals.spend` on each partition and on the
///     whole set, passing that one shared analysis down.
///
/// Every transaction lands in exactly one partition, every partition is
/// summed by the same function under the same rules, and `Money` addition is
/// exact (ADR-002) and associative. The parts therefore sum to the whole by
/// construction, not by coincidence — and [reconciles] re-checks it anyway,
/// because a guarantee worth having is worth asserting.
///
/// ## Why "every transaction lands in exactly one partition" is the load-bearing
/// half
///
/// It is what makes the four category operations safe:
///
///  - **create** — a new category has no transactions, so it adds an empty
///    partition and moves nothing;
///  - **rename** — changes a name, never an id, so no transaction moves at all
///    (AC-C3.4);
///  - **delete-with-reassign** — moves transactions from one partition to
///    another; the union is unchanged;
///  - **delete-with-uncategorize** — moves them into the *Uncategorized*
///    partition, which is in the sum, exactly as AC-C1.3 insists.
///
/// A design in which Uncategorized were *excluded* from the breakdown would
/// fail on the fourth operation and would look right on the first three, which
/// is why the AC names it explicitly.
///
/// ## What this is a breakdown *of*
///
/// **Spend** — `PeriodReport.spend`, the same figure the home screen and the
/// bank pages show. Not "every movement": income, cash withdrawals and
/// internal transfers are not spending (US-B10/B11), and adding them to a
/// spend breakdown would produce category slices that sum to something no
/// screen displays. Money-movement categories therefore normally appear here
/// with an empty total, and that is correct rather than a bug.
library;

import '../../core/money/money.dart';
import '../ledger/internal_transfer.dart';
import '../ledger/ledger_transaction.dart';
import '../ledger/period_totals.dart';
import 'categories.dart';

/// One category's slice of the period.
final class CategoryTotal {
  final Category category;

  /// The same [PeriodTotals] shape every other figure in the app uses —
  /// including its per-currency breakdown and its "not converted" honesty
  /// line, so a category slice can never look more certain than the total it
  /// came from.
  final PeriodTotals totals;

  /// How many of the period's transactions carry this category — **all of
  /// them, not only the ones inside [totals]**.
  ///
  /// The two differ on purpose. [totals] is a *spend* figure, so it excludes
  /// income, cash withdrawals and internal transfers (US-B10/B11); this count
  /// is what the user would see if they tapped the slice and got a list. A
  /// money-movement category therefore typically shows a count with no
  /// figure, which is the honest rendering of "three transactions, none of
  /// them spending" — not a discrepancy.
  ///
  /// NFR-A6's traceability in its cheapest form: a figure with a count beside
  /// it can be checked.
  final int transactionCount;

  const CategoryTotal({
    required this.category,
    required this.totals,
    required this.transactionCount,
  });

  bool get isEmpty => transactionCount == 0;

  @override
  String toString() => 'CategoryTotal(${category.id}, n=$transactionCount)';
}

/// A period's spend, split by category, with the overall figure it must sum
/// to.
final class CategoryBreakdown {
  /// One entry per category that has at least one transaction in the period,
  /// **plus Uncategorized whenever it has any**, ordered by the design's
  /// category order.
  final List<CategoryTotal> categories;

  /// The overall period spend — `PeriodReport.spend`, computed by exactly the
  /// same function over exactly the same transactions.
  final PeriodTotals total;

  final String baseCurrencyCode;

  const CategoryBreakdown({
    required this.categories,
    required this.total,
    required this.baseCurrencyCode,
  });

  static const CategoryBreakdown empty = CategoryBreakdown(
    categories: <CategoryTotal>[],
    total: PeriodTotals.empty,
    baseCurrencyCode: 'SAR',
  );

  /// **AC-C1.3, as a runtime assertion.** True when the category slices sum to
  /// [total] in the base currency.
  ///
  /// Compares [Money] values, never doubles: ADR-002's whole point is that
  /// this comparison is exact, so a "reconciles within a rounding tolerance"
  /// version of this method would be both unnecessary and a lie about what the
  /// arithmetic guarantees.
  ///
  /// Null base figures are handled as the absence they are: if nothing could
  /// be converted, both sides are null and the answer is true — there is no
  /// figure to disagree about. If one side has a figure and the other does
  /// not, that is a genuine failure and this returns false.
  bool get reconciles {
    final List<Money> parts = <Money>[
      for (final CategoryTotal slice in categories)
        if (slice.totals.base != null) slice.totals.base!,
    ];
    if (total.base == null) {
      return parts.isEmpty;
    }
    if (parts.isEmpty) {
      return false;
    }
    return Money.sum(parts, currency: baseCurrencyCode) == total.base;
  }

  /// The count of transactions that are in the period but carry no category —
  /// what design S-29 shows on the always-present Uncategorized row.
  int get uncategorizedCount => categories
      .where((CategoryTotal slice) => slice.category.isUncategorized)
      .fold<int>(
        0,
        (int running, CategoryTotal slice) => running + slice.transactionCount,
      );

  /// Splits [transactions] by category for [period].
  ///
  /// [resolver] maps a stored `category_id` — including null and including an
  /// id that no longer resolves — onto a real category. That is what makes
  /// AC-C1.1's *"never a blank"* true here as well as on a detail screen: a
  /// breakdown cannot contain an unnamed slice.
  ///
  /// [includeEmptyCategories] adds a zero row for every known category, which
  /// a picker or a chart legend may want; it does not change any figure and
  /// does not affect [reconciles], since an empty slice contributes a null
  /// base.
  static CategoryBreakdown of(
    Iterable<LedgerTransaction> transactions, {
    required PeriodRange period,
    required CategoryResolver resolver,
    String baseCurrencyCode = 'SAR',
    bool includeEmptyCategories = false,
  }) {
    final List<LedgerTransaction> live = <LedgerTransaction>[
      for (final LedgerTransaction txn in transactions)
        if (!txn.isDeleted) txn,
    ];

    // Step 1 — one analysis for the whole set. See the library comment.
    final InternalTransferAnalysis analysis = InternalTransferDetector.analyze(
      live,
    );

    // Step 2 — partition. `resolve` never returns null, so there is no
    // "everything else" bucket and nothing can fall out of the partitioning.
    final Map<String, List<LedgerTransaction>> byCategory =
        <String, List<LedgerTransaction>>{};
    for (final LedgerTransaction txn in live) {
      final Category category = resolver.resolve(txn.categoryId);
      byCategory.putIfAbsent(category.id, () => <LedgerTransaction>[]).add(txn);
    }

    // Step 3 — the same function, on each part and on the whole.
    final PeriodTotals total = LedgerTotals.spend(
      live,
      period: period,
      baseCurrencyCode: baseCurrencyCode,
      transfers: analysis,
    );

    final List<CategoryTotal> slices = <CategoryTotal>[];
    for (final Category category in resolver.all) {
      final List<LedgerTransaction> members =
          byCategory.remove(category.id) ?? const <LedgerTransaction>[];
      if (members.isEmpty && !includeEmptyCategories) {
        continue;
      }
      slices.add(
        _sliceFor(
          category,
          members,
          period: period,
          baseCurrencyCode: baseCurrencyCode,
          analysis: analysis,
        ),
      );
    }

    // Anything left in the map points at a category the resolver does not
    // know, which `resolve` has already mapped to Uncategorized — so this loop
    // is unreachable in practice. It is written anyway, and appends rather
    // than discards, because "unreachable" is a claim about today's callers
    // and a dropped partition would silently break the invariant this whole
    // file exists to hold.
    for (final List<LedgerTransaction> orphans in byCategory.values) {
      slices.add(
        _sliceFor(
          DefaultCategories.uncategorized,
          orphans,
          period: period,
          baseCurrencyCode: baseCurrencyCode,
          analysis: analysis,
        ),
      );
    }

    return CategoryBreakdown(
      categories: slices,
      total: total,
      baseCurrencyCode: baseCurrencyCode,
    );
  }

  static CategoryTotal _sliceFor(
    Category category,
    List<LedgerTransaction> members, {
    required PeriodRange period,
    required String baseCurrencyCode,
    required InternalTransferAnalysis analysis,
  }) {
    final PeriodTotals totals = LedgerTotals.spend(
      members,
      period: period,
      baseCurrencyCode: baseCurrencyCode,
      // The shared analysis — never re-derived from this slice, which holds
      // one leg of a transfer and not the other.
      transfers: analysis,
    );
    return CategoryTotal(
      category: category,
      totals: totals,
      transactionCount: members
          .where((LedgerTransaction txn) => period.contains(txn.occurredAt))
          .length,
    );
  }
}

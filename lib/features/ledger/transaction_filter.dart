/// **US-E5 — search and filter** (KHA-38). AC-E5.1, AC-E5.2, AC-E5.3, NFR-S4.
///
/// ---
///
/// ## A pure value type, and why that is the whole design
///
/// Every rule about *which* transactions the user is looking at lives here, in
/// one immutable value with no widgets, no providers and no database in it. Three
/// things follow, and each of them is an acceptance criterion:
///
///  - **AC-E5.2's total cannot disagree with AC-E5.2's list.** The screen filters
///    once, hands the resulting list to `LedgerTotals.spend`, and renders the same
///    list underneath the figure. There is no second predicate and no second
///    query, so *"the displayed total reflects the filtered subset"* is true by
///    construction rather than by two code paths agreeing (NFR-A6).
///  - **It is testable without an app.** A filter is the kind of thing that is
///    subtly wrong at the edges (an inclusive end date, an amount range against a
///    foreign-currency row), and edges are cheap to pin on a value type.
///  - **NFR-S4 is satisfiable by inspection.** *"Search queries and results must
///    not be logged — a search history is a record of what the user was looking
///    for in their financial life."* This file imports no logger, and [toString]
///    below deliberately reports only which facets are set, never the query text.
///    That makes the guarantee checkable by reading one file instead of auditing
///    every call site.
///
/// ## What "matches the merchant" means across two scripts (AC-E5.1)
///
/// PRD §3.4 notes that merchant names arrive **transliterated into Latin even
/// inside an Arabic message**, so a Saudi user searching their own spending
/// legitimately types either script — and Arabic itself spells the same merchant
/// several ways (`أ`/`ا`, `ة`/`ه`, with and without diacritics or tatweel).
/// Matching on raw substrings would fail all of that.
///
/// So both sides go through [CanonicalText.fold] — the *same* folding the
/// merchant-rule engine uses to decide that two SMS name one shop (ADR-008 steps
/// 1–3: digit families, bidi controls, tatweel, diacritics, Arabic letter
/// variants, Latin case). Reusing it rather than writing a second normaliser is
/// the point: two definitions of "the same string" is how a search silently stops
/// agreeing with the categorisation the user already taught the app.
///
/// The fold is a **match key and never display text** (it has lost `ة`/`ه` and
/// letter case), which is why nothing here is ever rendered — the screens show
/// `merchantRawText`.
///
/// ## The amount range and the currency it is in
///
/// An amount range typed into a form is in **one** currency, and a ledger can
/// hold several (NFR-A5). Silently comparing `20.00` against a `20.00 USD` row
/// would be the "mixed currencies summed without a stated conversion" mistake
/// wearing a different hat. So:
///
///  - the bounds are compared against the transaction's **base-currency** figure,
///    derived by `BaseCurrencyConverter` from the rate the transaction's own
///    record carries — exactly the figure every total on every screen is built
///    from;
///  - a transaction that has **no** base figure (ADR-009 case 4 — a foreign
///    purchase whose message quoted no rate) cannot be compared at all. It is
///    excluded from the result and counted on [FilterOutcome.notComparableByAmount],
///    so the screen states the omission rather than quietly shortening the list.
///    Excluding it is the safer direction: including it would put a row the user
///    asked to bound outside their bound.
///
/// ## Dart notes for a newcomer
///
/// `final class` means "usable but not subclassable" — this is a value, not a
/// hierarchy. [copyWith] is the standard Dart idiom for "the same value with one
/// field changed", which is how a `StatefulWidget` mutates a filter without ever
/// mutating the object it already handed to a child. `Set` (rather than `List`)
/// for the category/instrument facets because membership, not order, is the
/// question being asked.
library;

import '../../core/money/money.dart';
import '../../core/text/canonical_text.dart';
import '../categorization/categories.dart';
import 'base_currency.dart';
import 'ledger_transaction.dart';
import 'period_totals.dart';

/// The facets a user can set. Every field's "unset" value is the empty/absent
/// one, so [TransactionFilter.none] is genuinely neutral.
final class TransactionFilter {
  /// AC-E5.1's merchant-name fragment, as the user typed it.
  ///
  /// Stored raw (not folded) so the search field can show it back verbatim;
  /// folding happens at comparison time in [matches].
  final String query;

  /// AC-E5.2's date range, as UTC instants. Half-open `[from, toExclusive)`,
  /// matching [PeriodRange] — an inclusive-both-ends range is how a transaction
  /// gets counted in two buckets at once.
  final DateTime? fromUtc;
  final DateTime? toUtcExclusive;

  /// Resolved category ids. May include [CategoryIds.uncategorized], which is a
  /// first-class choice: "show me what the app could not label" is one of the
  /// most useful filters this screen offers (US-C5's bulk-categorize flow starts
  /// there).
  final Set<String> categoryIds;

  /// Instrument (card/account) row ids.
  final Set<int> instrumentIds;

  /// Inclusive bounds on the **base-currency magnitude** — see the library
  /// comment on why this is not the native amount.
  final Money? minAmount;
  final Money? maxAmount;

  const TransactionFilter({
    this.query = '',
    this.fromUtc,
    this.toUtcExclusive,
    this.categoryIds = const <String>{},
    this.instrumentIds = const <int>{},
    this.minAmount,
    this.maxAmount,
  });

  /// The neutral filter: matches everything, and [isActive] is false.
  static const TransactionFilter none = TransactionFilter();

  /// True when anything is set, i.e. when the screen must offer AC-E5.3's
  /// "clear" affordance and must label an empty result as *filtered*-empty
  /// rather than as "you have no transactions".
  ///
  /// A query of only whitespace does **not** count: it filters nothing, and
  /// treating it as active would show the filtered-empty state to a user who had
  /// merely tapped the space bar.
  bool get isActive =>
      query.trim().isNotEmpty ||
      fromUtc != null ||
      toUtcExclusive != null ||
      categoryIds.isNotEmpty ||
      instrumentIds.isNotEmpty ||
      minAmount != null ||
      maxAmount != null;

  /// How many facets are set — the number on the filter button's badge.
  ///
  /// A date range counts once even when both ends are set, and so does an amount
  /// range: the user set *one* range, and reporting "2 filters" for one control
  /// would misdescribe what they did.
  int get activeFacetCount =>
      (query.trim().isEmpty ? 0 : 1) +
      (fromUtc == null && toUtcExclusive == null ? 0 : 1) +
      (categoryIds.isEmpty ? 0 : 1) +
      (instrumentIds.isEmpty ? 0 : 1) +
      (minAmount == null && maxAmount == null ? 0 : 1);

  TransactionFilter copyWith({
    String? query,
    DateTime? fromUtc,
    DateTime? toUtcExclusive,
    Set<String>? categoryIds,
    Set<int>? instrumentIds,
    Money? minAmount,
    Money? maxAmount,
    bool clearDateRange = false,
    bool clearAmountRange = false,
  }) => TransactionFilter(
    query: query ?? this.query,
    // The explicit `clear*` flags exist because `null` already means "leave
    // unchanged" for an optional named parameter, so there would otherwise be no
    // way to *remove* a bound. Two booleans beat a sentinel value nobody
    // remembers.
    fromUtc: clearDateRange ? null : (fromUtc ?? this.fromUtc),
    toUtcExclusive: clearDateRange
        ? null
        : (toUtcExclusive ?? this.toUtcExclusive),
    categoryIds: categoryIds ?? this.categoryIds,
    instrumentIds: instrumentIds ?? this.instrumentIds,
    minAmount: clearAmountRange ? null : (minAmount ?? this.minAmount),
    maxAmount: clearAmountRange ? null : (maxAmount ?? this.maxAmount),
  );

  /// Whether [transaction] passes every set facet.
  ///
  /// [resolvedCategory] is supplied rather than looked up, for the reason
  /// `CategoryBreakdown` gives: `null` in the column means *Uncategorized*, and
  /// the only thing that knows the resolution is [CategoryResolver]. Passing it
  /// in keeps this file free of a category lookup it would have to keep in step.
  ///
  /// [baseAmount] is the transaction's base-currency figure, or null when it has
  /// none — see [FilterOutcome] for how the null case is reported rather than
  /// hidden.
  bool matches(
    LedgerTransaction transaction, {
    required Category resolvedCategory,
    required Money? baseAmount,
  }) {
    if (!_matchesQuery(transaction)) {
      return false;
    }
    if (!_matchesDateRange(transaction.occurredAt)) {
      return false;
    }
    if (categoryIds.isNotEmpty && !categoryIds.contains(resolvedCategory.id)) {
      return false;
    }
    if (instrumentIds.isNotEmpty &&
        !instrumentIds.contains(transaction.instrument?.id)) {
      return false;
    }
    return _matchesAmount(baseAmount);
  }

  /// AC-E5.1, across both scripts. See the library comment.
  bool _matchesQuery(LedgerTransaction transaction) {
    final String needle = CanonicalText.fold(query.trim());
    if (needle.isEmpty) {
      return true;
    }
    // The merchant first, then the counterparty: a transfer has no merchant but
    // does have a payee, and a user searching for "Fatimah" after sending her
    // money is asking the same question as one searching for "Panda".
    // `transactionType` is deliberately NOT searched — matching the app's own
    // vocabulary would make a query for "fee" return rows whose merchant the
    // user never named.
    for (final String? candidate in <String?>[
      transaction.merchantRawText,
      transaction.counterpartyName,
      transaction.counterpartyBankName,
    ]) {
      if (candidate != null && CanonicalText.fold(candidate).contains(needle)) {
        return true;
      }
    }
    return false;
  }

  /// Half-open, and an **undated** transaction fails a set date range.
  ///
  /// The same rule [PeriodRange.contains] applies, for the same reason: a
  /// movement the message never dated cannot be asserted to fall inside a window
  /// the user chose. It is still in the ledger and still findable by merchant.
  bool _matchesDateRange(DateTime? occurredAt) {
    if (fromUtc == null && toUtcExclusive == null) {
      return true;
    }
    if (occurredAt == null) {
      return false;
    }
    final DateTime at = occurredAt.toUtc();
    if (fromUtc != null && at.isBefore(fromUtc!)) {
      return false;
    }
    if (toUtcExclusive != null && !at.isBefore(toUtcExclusive!)) {
      return false;
    }
    return true;
  }

  /// Compares the **magnitude**, because the stored amount is a magnitude and
  /// the sign lives in `direction` (`sign_convention.dart`).
  ///
  /// A user filtering "between 100 and 500" means the size of the movement; a
  /// 200.00 refund is as much a 200.00 movement as a 200.00 purchase, and
  /// signing the comparison would drop every credit out of every range.
  bool _matchesAmount(Money? baseAmount) {
    if (minAmount == null && maxAmount == null) {
      return true;
    }
    if (baseAmount == null) {
      // ADR-009 case 4 — nothing to compare. Excluded here and *counted* by
      // [FilterOutcome], never dropped silently.
      return false;
    }
    final Money magnitude = baseAmount.abs;
    if (minAmount != null && magnitude < minAmount!.abs) {
      return false;
    }
    if (maxAmount != null && magnitude > maxAmount!.abs) {
      return false;
    }
    return true;
  }

  /// Applies this filter to [transactions], preserving their order.
  ///
  /// Returns a [FilterOutcome] rather than a bare list so the two things the
  /// screen must disclose travel with the result instead of being recomputed:
  /// how many rows were dropped for having no comparable amount, and whether the
  /// filter was active at all.
  FilterOutcome apply(
    Iterable<LedgerTransaction> transactions, {
    required CategoryResolver resolver,
    String baseCurrencyCode = BaseCurrency.defaultCode,
  }) {
    final List<LedgerTransaction> kept = <LedgerTransaction>[];
    int notComparable = 0;
    final bool boundsAmount = minAmount != null || maxAmount != null;

    for (final LedgerTransaction txn in transactions) {
      final Money? base = BaseCurrencyConverter.forTransaction(
        txn,
        baseCurrencyCode: baseCurrencyCode,
      ).value;
      if (matches(
        txn,
        resolvedCategory: resolver.resolve(txn.categoryId),
        baseAmount: base,
      )) {
        kept.add(txn);
        continue;
      }
      // Only counted when the amount facet is what excluded it, and only when
      // every *other* facet passed — otherwise a row the user filtered out by
      // category would be reported as "could not be compared by amount", which
      // is a different and alarming claim.
      if (boundsAmount &&
          base == null &&
          _matchesQuery(txn) &&
          _matchesDateRange(txn.occurredAt) &&
          (categoryIds.isEmpty ||
              categoryIds.contains(resolver.resolve(txn.categoryId).id)) &&
          (instrumentIds.isEmpty ||
              instrumentIds.contains(txn.instrument?.id))) {
        notComparable += 1;
      }
    }

    return FilterOutcome(
      transactions: kept,
      notComparableByAmount: notComparable,
      wasActive: isActive,
    );
  }

  /// **NFR-S4.** Reports *which* facets are set and never their values — no
  /// query text, no merchant, no amount, no date.
  ///
  /// This is not decoration. A `toString` is what ends up in a debugger, an
  /// assertion message, an exception and (by accident) a log line, and a search
  /// query is a record of what the user was looking for in their financial life.
  /// The same discipline `LedgerTransaction.toString` follows for the same
  /// reason (ADR-015).
  @override
  String toString() =>
      'TransactionFilter(facets: $activeFacetCount, '
      'query: ${query.trim().isEmpty ? 'unset' : 'set'}, '
      'dates: ${fromUtc == null && toUtcExclusive == null ? 'unset' : 'set'}, '
      'categories: ${categoryIds.length}, '
      'instruments: ${instrumentIds.length}, '
      'amount: ${minAmount == null && maxAmount == null ? 'unset' : 'set'})';
}

/// A filtered list, plus what the screen has to admit about it.
final class FilterOutcome {
  /// The rows that matched, in the order they were given.
  final List<LedgerTransaction> transactions;

  /// How many rows an **amount** bound excluded because the app has no
  /// base-currency figure for them (ADR-009 case 4).
  ///
  /// Rendered as an explicit line, exactly like `PeriodTotals.unconverted`'s
  /// *"N transactions not converted"*. A filter that silently omits a purchase
  /// is the same defect as a total that silently omits one.
  final int notComparableByAmount;

  /// Whether the filter that produced this was active — decides between AC-E5.3's
  /// filtered-empty copy and the ordinary "nothing here yet" copy.
  final bool wasActive;

  const FilterOutcome({
    required this.transactions,
    required this.notComparableByAmount,
    required this.wasActive,
  });

  static const FilterOutcome empty = FilterOutcome(
    transactions: <LedgerTransaction>[],
    notComparableByAmount: 0,
    wasActive: false,
  );

  /// **AC-E5.3** — the filter ran, matched nothing, and the user needs different
  /// words plus a way out.
  bool get isFilteredEmpty => wasActive && transactions.isEmpty;

  @override
  String toString() =>
      'FilterOutcome(n=${transactions.length}, '
      'notComparable=$notComparableByAmount, active=$wasActive)';
}

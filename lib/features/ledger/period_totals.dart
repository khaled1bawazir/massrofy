/// Period totals for a bank or an instrument — AC-B2.1, AC-B2.2, AC-B2.3,
/// NFR-A4, NFR-A6, ADR-002, ADR-009.
///
/// ## Four rules, and each one is somebody's acceptance criterion
///
/// 1. **Arithmetic happens in Dart over [Money], never in SQL.** ADR-002 is
///    blunt that no total may be produced by `SUM()` over the `_minor`
///    column: that column is a non-authoritative integer kept for indexing,
///    and summing it would silently truncate any currency whose real exponent
///    differs from what the writer assumed. CI greps for `SUM(`/`AVG(` for
///    exactly this reason.
///
/// 2. **Currencies are never mixed** (ADR-009: *"never sum across
///    currencies"*). A total is therefore a set of per-currency figures, not
///    one number. Converting to a base currency needs a rate, and inventing a
///    rate is forbidden — KHA-27 owns conversion, and this file deliberately
///    does not pre-empt it. Until then, showing "1,240.00 SAR and 45.00 USD"
///    is honest; showing "1,408.75" would not be.
///
/// 3. **A credit reduces spend** (US-B7, AC-B7.1). Refunds subtract; they
///    never add. The sign lives in `direction`, so it is applied here rather
///    than assumed to be baked into the stored amount.
///
/// 4. **Nothing is cached** (NFR-A6: *"no derived figure may exist that
///    cannot be traced back to its constituent transactions"*). Every figure
///    this file returns is computed from a list of transactions the caller
///    can also display, which is what makes a total auditable rather than
///    merely plausible.
library;

import '../../core/money/money.dart';
import 'ledger_transaction.dart';

/// A half-open time window `[startUtc, endUtcExclusive)`.
///
/// Half-open on purpose: a transaction at exactly midnight on the first of
/// the month belongs to that month and to no other. Inclusive-both-ends
/// ranges are how a transaction gets counted in two months at once.
final class PeriodRange {
  final DateTime startUtc;
  final DateTime endUtcExclusive;

  const PeriodRange({required this.startUtc, required this.endUtcExclusive});

  /// A range covering everything — used where a screen shows "all time"
  /// rather than a month.
  factory PeriodRange.unbounded() => PeriodRange(
    startUtc: DateTime.utc(1970),
    endUtcExclusive: DateTime.utc(9999),
  );

  /// A transaction with no date at all is **excluded** from every bounded
  /// period. It is not lost — it is still in the ledger and still visible —
  /// but silently placing an undated movement in "this month" would put a
  /// figure in a total the user cannot verify against anything.
  bool contains(DateTime? at) {
    if (at == null) {
      return false;
    }
    final DateTime utc = at.toUtc();
    return !utc.isBefore(startUtc) && utc.isBefore(endUtcExclusive);
  }
}

/// The net figure for one currency.
final class CurrencyTotal {
  final String currencyCode;

  /// Net spend: debits minus credits, over transactions that count toward
  /// spend. May be negative in a month with more refunds than purchases —
  /// which is a real thing that happens and must not be clamped to zero.
  final Money net;

  /// How many transactions produced [net]. NFR-A6's traceability in its
  /// cheapest form: a total with a count next to it can be checked.
  final int transactionCount;

  const CurrencyTotal({
    required this.currencyCode,
    required this.net,
    required this.transactionCount,
  });

  @override
  String toString() => 'CurrencyTotal($currencyCode, n=$transactionCount)';
}

/// One or more per-currency figures. Empty when nothing matched.
final class PeriodTotals {
  /// Ordered: the currency with the most transactions first, so the user's
  /// everyday currency leads and a single foreign purchase does not.
  final List<CurrencyTotal> byCurrency;

  const PeriodTotals(this.byCurrency);

  static const PeriodTotals empty = PeriodTotals(<CurrencyTotal>[]);

  bool get isEmpty => byCurrency.isEmpty;

  /// The figure for [currencyCode], or null when nothing in the period used
  /// it. Null is "no transactions", which a caller renders as an empty state
  /// — deliberately not `Money.zero`, which would claim the user spent
  /// nothing when in truth we have nothing to show.
  Money? forCurrency(String currencyCode) {
    final String wanted = currencyCode.toUpperCase();
    for (final CurrencyTotal total in byCurrency) {
      if (total.currencyCode == wanted) {
        return total.net;
      }
    }
    return null;
  }
}

/// Computes [PeriodTotals] from transactions.
abstract final class LedgerTotals {
  /// Net spend over [transactions] within [period].
  ///
  /// Excluded, each for a stated reason:
  ///  - soft-deleted rows (US-B8 — a deleted transaction is out of every
  ///    total until restored),
  ///  - `affectsSpend == false` (US-B10/B11 — internal transfers, income and
  ///    card repayment are money movements, not spending; counting a card
  ///    repayment would double-count the purchases it settles),
  ///  - anything outside [period], including undated rows (see
  ///    [PeriodRange.contains]).
  ///
  /// The fee component is **not** added in. PRD §3.4 keeps it as its own
  /// field precisely so it stays visible; a later reporting decision may
  /// choose to show "spend + fees", and it can do so explicitly with
  /// [feesFor]. Silently folding it into every total would make the fee
  /// invisible again, which is what having the field is meant to prevent.
  static PeriodTotals spend(
    Iterable<LedgerTransaction> transactions, {
    required PeriodRange period,
  }) {
    final Map<String, List<Money>> buckets = <String, List<Money>>{};

    for (final LedgerTransaction txn in transactions) {
      if (txn.isDeleted || !txn.affectsSpend) {
        continue;
      }
      if (!period.contains(txn.occurredAt)) {
        continue;
      }
      // A credit reduces spend (rule 3 above). Negating the Money keeps the
      // subtraction in exact decimal arithmetic rather than branching on
      // sign at every call site.
      final Money signed = txn.isCredit ? -txn.amount : txn.amount;
      buckets.putIfAbsent(signed.currencyCode, () => <Money>[]).add(signed);
    }

    return _foldBuckets(buckets);
  }

  /// The FX/international fees charged in [period], per currency.
  ///
  /// Separate from [spend] on purpose — see the note there. Fees ride on a
  /// transaction but are their own cost, and the product exists to answer
  /// "where does my money go", which includes this.
  static PeriodTotals feesFor(
    Iterable<LedgerTransaction> transactions, {
    required PeriodRange period,
  }) {
    final Map<String, List<Money>> buckets = <String, List<Money>>{};

    for (final LedgerTransaction txn in transactions) {
      final Money? fee = txn.feeAmount;
      if (fee == null || txn.isDeleted) {
        continue;
      }
      if (!period.contains(txn.occurredAt)) {
        continue;
      }
      buckets.putIfAbsent(fee.currencyCode, () => <Money>[]).add(fee);
    }

    return _foldBuckets(buckets);
  }

  static PeriodTotals _foldBuckets(Map<String, List<Money>> buckets) {
    final List<CurrencyTotal> totals =
        <CurrencyTotal>[
          for (final MapEntry<String, List<Money>> entry in buckets.entries)
            CurrencyTotal(
              currencyCode: entry.key,
              // `Money.sum` is the single sanctioned aggregation point (ADR-002)
              // and throws `CurrencyMismatchError` if a value of the wrong
              // currency ever reached this bucket.
              net: Money.sum(entry.value, currency: entry.key),
              transactionCount: entry.value.length,
            ),
        ]..sort((CurrencyTotal a, CurrencyTotal b) {
          final int byCount = b.transactionCount.compareTo(a.transactionCount);
          // Ties broken alphabetically so the order is stable across rebuilds —
          // a total list that reshuffles between frames looks like data changing.
          return byCount != 0
              ? byCount
              : a.currencyCode.compareTo(b.currencyCode);
        });

    return PeriodTotals(totals);
  }
}

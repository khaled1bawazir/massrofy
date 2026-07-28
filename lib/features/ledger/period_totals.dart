/// Period totals — AC-B2.1/2/3, **AC-B7.1/B7.2, AC-B9.2, AC-B10.3, AC-B11.1**,
/// NFR-A4, NFR-A5, NFR-A6, ADR-002, ADR-009.
///
/// ---
///
/// ## Five rules, and each one is somebody's acceptance criterion
///
/// 1. **Arithmetic happens in Dart over [Money], never in SQL.** ADR-002 is
///    blunt that no total may be produced by `SUM()` over the `_minor`
///    column: that column is a non-authoritative integer kept for indexing,
///    and summing it would silently truncate any currency whose real exponent
///    differs from what the writer assumed. CI greps for `SUM(`/`AVG(` for
///    exactly this reason.
///
/// 2. **Currencies are never mixed implicitly** (NFR-A5, ADR-009). A total is
///    therefore *two* things at once: a per-currency native breakdown, which
///    is always exact, and a base-currency figure built **only** from
///    conversions each transaction itself recorded. Anything that cannot be
///    converted from its own record is left out of the base figure and
///    counted on [PeriodTotals.unconverted] — ADR-009's *"show an explicit
///    line 'N transactions not converted' so reconciliation is visibly
///    incomplete rather than silently wrong"*.
///
/// 3. **A credit reduces spend** (US-B7, AC-B7.1). Refunds subtract; they
///    never add. The sign lives in `direction` (see `sign_convention.dart`),
///    so it is applied here — once — rather than assumed to be baked into the
///    stored amount.
///
/// 4. **Moving money to yourself is not spending** (US-B11, AC-B11.1). An
///    internal transfer is excluded before any other consideration, and no
///    rule-pack flag can put it back. See `spend_classification.dart`.
///
/// 5. **Nothing is cached** (NFR-A6: *"no derived figure may exist that
///    cannot be traced back to its constituent transactions"*). Every figure
///    here is computed from a list of transactions the caller can also
///    display, which is what makes a total auditable rather than merely
///    plausible.
///
/// ## Why the three concerns live in one function
///
/// Conversion, netting and exclusion are not three passes that happen to run
/// together — they interact. A refund in a foreign currency has to be
/// converted *and then* subtracted, on the rate its own record carries, not
/// the original purchase's. An internal transfer that is later refunded must
/// be excluded on both legs. Computing them separately and adding up the
/// answers gives a number that is right for each rule and wrong overall,
/// which is precisely why `docs/build-plan.md` groups KHA-27/28/29 into one
/// PR. [LedgerTotals.report] is the single place all three meet, and
/// `test/features/ledger/combined_totals_test.dart` is the test that pins
/// them meeting correctly.
library;

import '../../core/money/money.dart';
import '../../core/money/sign_convention.dart';
import 'base_currency.dart';
import 'internal_transfer.dart';
import 'ledger_transaction.dart';
import 'spend_classification.dart';

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

/// The net figure for one currency, in that currency.
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

/// One currency's worth of transactions that could **not** be converted into
/// the base currency (ADR-009 case 4).
///
/// This type exists so the omission is a value the UI must render rather than
/// a silence it can forget. `PeriodTotalsText` shows it as *"+2 transactions
/// not converted"* directly under the figure.
final class UnconvertedGroup {
  final String currencyCode;

  /// The net figure in the transaction's **own** currency — still exact, and
  /// still shown, because the user's money did not stop existing just because
  /// the app has no rate for it.
  final Money net;

  final int transactionCount;

  const UnconvertedGroup({
    required this.currencyCode,
    required this.net,
    required this.transactionCount,
  });

  @override
  String toString() => 'UnconvertedGroup($currencyCode, n=$transactionCount)';
}

/// A figure for a period: the base-currency total, the exact per-currency
/// breakdown behind it, and everything that had to be left out.
final class PeriodTotals {
  /// The base-currency net figure, or `null` when **nothing** in the period
  /// could be expressed in the base currency.
  ///
  /// Null, not `Money.zero`. Zero would claim the user spent nothing; null
  /// says there is nothing to show — different facts, and the UI renders them
  /// differently (see `PeriodTotalsText`).
  final Money? base;

  final String baseCurrencyCode;

  /// How many transactions are inside [base].
  final int convertedCount;

  /// Per-currency native figures, ordered with the currency carrying the most
  /// transactions first, so the user's everyday currency leads and a single
  /// foreign purchase does not. Ties break alphabetically so the order is
  /// stable across rebuilds — a total list that reshuffles between frames
  /// looks like data changing.
  final List<CurrencyTotal> byCurrency;

  /// AC-B9.2's honesty clause: what is missing from [base] and why the user
  /// should not treat it as complete.
  final List<UnconvertedGroup> unconverted;

  const PeriodTotals({
    required this.base,
    required this.baseCurrencyCode,
    required this.convertedCount,
    required this.byCurrency,
    required this.unconverted,
  });

  static const PeriodTotals empty = PeriodTotals(
    base: null,
    baseCurrencyCode: BaseCurrency.defaultCode,
    convertedCount: 0,
    byCurrency: <CurrencyTotal>[],
    unconverted: <UnconvertedGroup>[],
  );

  bool get isEmpty => byCurrency.isEmpty;

  /// True when [base] omits something the user needs to know about.
  bool get isIncomplete => unconverted.isNotEmpty;

  /// How many transactions are missing from [base].
  int get unconvertedCount => unconverted.fold<int>(
    0,
    (int running, UnconvertedGroup group) => running + group.transactionCount,
  );

  /// The exact figure for [currencyCode], or null when nothing in the period
  /// used it. Null is "no transactions", deliberately not `Money.zero`.
  Money? forCurrency(String currencyCode) {
    final String wanted = currencyCode.toUpperCase();
    for (final CurrencyTotal total in byCurrency) {
      if (total.currencyCode == wanted) {
        return total.net;
      }
    }
    return null;
  }

  @override
  String toString() =>
      'PeriodTotals($baseCurrencyCode, n=$convertedCount, '
      'unconverted=$unconvertedCount)';
}

/// Everything a period is made of — the shape S-32 "Spent vs Kept" renders
/// (AC-B10.3) and the shape the bank/instrument pages take their headline
/// figure from.
///
/// Each component is its own [PeriodTotals] rather than a single blended
/// number, because AC-B10.3 asks for spend *netted against* income, and a
/// user cannot check that netting unless both sides are visible.
final class PeriodReport {
  final String baseCurrencyCode;

  /// AC-B2.1 — net spend: purchases, bills, fees and third-party transfers
  /// out, **minus** refunds, **excluding** internal transfers, income, cash
  /// withdrawals and card repayments.
  final PeriodTotals spend;

  /// AC-B10.1 — salary and third-party incoming transfers.
  final PeriodTotals income;

  /// AC-B10.2 — cash taken out. Neither spend nor income; reported on its own
  /// line because it is money that has stopped being traceable, not money
  /// that has gone.
  final PeriodTotals cashWithdrawals;

  /// AC-B11.1 — what was excluded as internal, shown so the exclusion is
  /// auditable rather than a silent gap (NFR-A6).
  ///
  /// Counts the **outgoing** leg of each pair only: one movement, one figure.
  /// See the note at the exclusion branch in [LedgerTotals.report].
  final PeriodTotals internalTransfers;

  /// PRD §3.4's FX/international fees, kept as their own figure and
  /// deliberately **not** added into [spend] — see [LedgerTotals.report].
  final PeriodTotals fees;

  /// How many transactions in the period the app could not classify
  /// confidently, or that are unproven internal-transfer candidates
  /// (AC-B11.2). A non-zero value means the figures above are provisional and
  /// the UI must say so.
  final int needsReviewCount;

  const PeriodReport({
    required this.baseCurrencyCode,
    required this.spend,
    required this.income,
    required this.cashWithdrawals,
    required this.internalTransfers,
    required this.fees,
    required this.needsReviewCount,
  });

  static const PeriodReport empty = PeriodReport(
    baseCurrencyCode: BaseCurrency.defaultCode,
    spend: PeriodTotals.empty,
    income: PeriodTotals.empty,
    cashWithdrawals: PeriodTotals.empty,
    internalTransfers: PeriodTotals.empty,
    fees: PeriodTotals.empty,
    needsReviewCount: 0,
  );

  /// **AC-B10.3 — "spent vs kept".** Income minus net spend, in the base
  /// currency. Positive means the user kept money this period.
  ///
  /// ## When this is null, and why the distinction is not pedantic
  ///
  /// A missing base figure means one of two very different things, and only
  /// one of them can be treated as zero:
  ///
  ///  - **The component has no transactions.** Nothing was received this
  ///    month → income genuinely contributes zero to the netting.
  ///  - **The component has transactions but none could be converted.** Every
  ///    purchase was in a currency the messages quoted no rate for. Treating
  ///    that as zero would report *"you kept 14,500.00 SAR"* to someone who
  ///    spent all of it — a number that looks authoritative and is the
  ///    opposite of the truth.
  ///
  /// So the second case returns null, and the card renders the empty-state
  /// words instead of a figure. Cash withdrawals are **not** subtracted from
  /// either — the money is still the user's; it is reported on its own line
  /// so a user who wants to treat it as spent can see it and decide.
  Money? get netKept {
    final Money zero = Money.zero(baseCurrencyCode);
    final Money? spent = _contributionOf(spend, zero);
    final Money? earned = _contributionOf(income, zero);
    if (spent == null || earned == null) {
      return null;
    }
    if (spend.isEmpty && income.isEmpty) {
      // Nothing at all happened. "You kept 0.00" would claim we measured
      // something; the caller renders "no transactions in this period".
      return null;
    }
    return earned - spent;
  }

  /// A component's contribution to the netting: its base figure, `zero` when
  /// it is genuinely empty, or **null** when it holds transactions the app
  /// could not convert.
  static Money? _contributionOf(PeriodTotals totals, Money zero) {
    if (totals.base != null) {
      return totals.base;
    }
    return totals.isEmpty ? zero : null;
  }

  /// True when any component omits an unconvertible transaction, so a screen
  /// can label the whole report as incomplete rather than only one line.
  bool get isIncomplete =>
      spend.isIncomplete ||
      income.isIncomplete ||
      cashWithdrawals.isIncomplete ||
      internalTransfers.isIncomplete ||
      fees.isIncomplete;
}

/// Computes period figures from transactions.
abstract final class LedgerTotals {
  /// The full period breakdown.
  ///
  /// Excluded from **every** figure here, each for a stated reason:
  ///  - soft-deleted rows (US-B8 — a deleted transaction is out of every
  ///    total until restored),
  ///  - anything outside [period], including undated rows (see
  ///    [PeriodRange.contains]).
  ///
  /// [transfers] carries the internal-transfer analysis. When omitted it is
  /// derived from [transactions] — which is correct only if [transactions] is
  /// the **whole** set. A per-instrument slice contains one leg of a transfer
  /// and not the other, so callers that slice must analyse the full set first
  /// and pass the result down; `BankTreeBuilder` does exactly that, and
  /// getting it wrong is the most plausible way to reintroduce AC-B11.1 as a
  /// bug.
  ///
  /// **Fees are not added into [PeriodReport.spend].** PRD §3.4 keeps the fee
  /// as its own field precisely so it stays visible; a later reporting
  /// decision may choose to show "spend + fees", and it can do so explicitly
  /// from [PeriodReport.fees]. Silently folding it in would make the fee
  /// invisible again, which is what having the field is meant to prevent.
  static PeriodReport report(
    Iterable<LedgerTransaction> transactions, {
    required PeriodRange period,
    String baseCurrencyCode = BaseCurrency.defaultCode,
    InternalTransferAnalysis? transfers,
  }) {
    final List<LedgerTransaction> live = <LedgerTransaction>[
      for (final LedgerTransaction txn in transactions)
        if (!txn.isDeleted) txn,
    ];
    final InternalTransferAnalysis analysis =
        transfers ?? InternalTransferDetector.analyze(live);

    final _Accumulator spend = _Accumulator(baseCurrencyCode);
    final _Accumulator income = _Accumulator(baseCurrencyCode);
    final _Accumulator withdrawals = _Accumulator(baseCurrencyCode);
    final _Accumulator internal = _Accumulator(baseCurrencyCode);
    final _Accumulator fees = _Accumulator(baseCurrencyCode);
    int needsReview = 0;

    for (final LedgerTransaction txn in live) {
      if (!period.contains(txn.occurredAt)) {
        continue;
      }

      final SpendClassification classification = SpendClassification.of(
        txn,
        transfers: analysis,
      );
      if (classification.needsReview) {
        needsReview += 1;
      }

      // The fee rides on a transaction of any class — including a refunded
      // foreign purchase, whose fee the bank does not always return. It is
      // accumulated for every non-deleted, in-period row rather than only for
      // spend rows, because "what did FX cost me this month" is a question
      // about all of them.
      _addFee(fees, txn, baseCurrencyCode);

      switch (classification.movementClass) {
        case MovementClass.spend:
        case MovementClass.spendCredit:
          // Rule 3: the sign comes from `direction`, applied once, here.
          _add(spend, txn, baseCurrencyCode, signed: true);
        case MovementClass.income:
          // Income is accumulated as a magnitude: an "income" figure that
          // went negative because the credits were stored as credits would be
          // nonsense on screen.
          _add(income, txn, baseCurrencyCode, signed: false);
        case MovementClass.cashWithdrawal:
          _add(withdrawals, txn, baseCurrencyCode, signed: false);
        case MovementClass.excluded:
          // **Only the outgoing leg**, and the reason is reconciliation.
          //
          // An internal transfer is two rows for one movement. Summing both
          // would report "4,000.00 excluded" for a 2,000.00 transfer — twice
          // the money that actually moved, and a figure that reconciles with
          // nothing. What the user needs is the amount by which the spend
          // total differs from a naive sum of their debits, which is exactly
          // the outgoing leg. The incoming leg was never in spend to begin
          // with (NFR-A6: a figure the user can check).
          if (classification.exclusionReason ==
                  ExclusionReason.internalTransfer &&
              txn.direction == MovementDirection.debit) {
            _add(internal, txn, baseCurrencyCode, signed: false);
          }
      }
    }

    return PeriodReport(
      baseCurrencyCode: baseCurrencyCode,
      spend: spend.build(),
      income: income.build(),
      cashWithdrawals: withdrawals.build(),
      internalTransfers: internal.build(),
      fees: fees.build(),
      needsReviewCount: needsReview,
    );
  }

  /// Net spend for [period] — the figure AC-B2.1/B2.2/B2.3 put next to a bank
  /// or an instrument. A thin wrapper over [report] so there is exactly one
  /// implementation of "what counts".
  static PeriodTotals spend(
    Iterable<LedgerTransaction> transactions, {
    required PeriodRange period,
    String baseCurrencyCode = BaseCurrency.defaultCode,
    InternalTransferAnalysis? transfers,
  }) => report(
    transactions,
    period: period,
    baseCurrencyCode: baseCurrencyCode,
    transfers: transfers,
  ).spend;

  /// The FX/international fees charged in [period].
  ///
  /// Separate from [spend] on purpose — see the note on [report]. Fees ride
  /// on a transaction but are their own cost, and the product exists to
  /// answer "where does my money go", which includes this.
  static PeriodTotals feesFor(
    Iterable<LedgerTransaction> transactions, {
    required PeriodRange period,
    String baseCurrencyCode = BaseCurrency.defaultCode,
  }) => report(
    transactions,
    period: period,
    baseCurrencyCode: baseCurrencyCode,
  ).fees;

  static void _add(
    _Accumulator into,
    LedgerTransaction txn,
    String baseCurrencyCode, {
    required bool signed,
  }) {
    final Money native = signed
        ? signedForSpend(txn.amount, direction: txn.direction)
        : txn.amount;
    final BaseCurrencyAmount converted = BaseCurrencyConverter.forTransaction(
      txn,
      baseCurrencyCode: baseCurrencyCode,
    );
    final Money? base = converted.value == null
        ? null
        : (signed
              ? signedForSpend(converted.value!, direction: txn.direction)
              : converted.value);
    into.add(native: native, base: base);
  }

  static void _addFee(
    _Accumulator into,
    LedgerTransaction txn,
    String baseCurrencyCode,
  ) {
    final Money? fee = txn.feeAmount;
    if (fee == null) {
      return;
    }
    final BaseCurrencyAmount converted =
        BaseCurrencyConverter.feeForTransaction(
          txn,
          baseCurrencyCode: baseCurrencyCode,
        );
    into.add(native: fee, base: converted.value);
  }
}

/// Collects native and base figures for one component of the report.
///
/// Split out because the same five steps — bucket by currency, sum exactly,
/// sum the base side, count what could not be converted, sort — happen for
/// spend, income, withdrawals, internal transfers and fees. Five copies of
/// this loop is five places for the netting to drift.
final class _Accumulator {
  final String baseCurrencyCode;
  final Map<String, List<Money>> _native = <String, List<Money>>{};
  final List<Money> _base = <Money>[];
  final Map<String, List<Money>> _unconverted = <String, List<Money>>{};

  _Accumulator(this.baseCurrencyCode);

  void add({required Money native, required Money? base}) {
    _native.putIfAbsent(native.currencyCode, () => <Money>[]).add(native);
    if (base == null) {
      _unconverted
          .putIfAbsent(native.currencyCode, () => <Money>[])
          .add(native);
      return;
    }
    _base.add(base);
  }

  PeriodTotals build() {
    final List<CurrencyTotal> byCurrency = _fold(_native);
    return PeriodTotals(
      // `Money.sum` is the single sanctioned aggregation point (ADR-002) and
      // throws `CurrencyMismatchError` if a value of the wrong currency ever
      // reached this bucket — the type system enforcing NFR-A5 at runtime as
      // well as at compile time.
      base: _base.isEmpty ? null : Money.sum(_base, currency: baseCurrencyCode),
      baseCurrencyCode: baseCurrencyCode,
      convertedCount: _base.length,
      byCurrency: byCurrency,
      unconverted: <UnconvertedGroup>[
        for (final CurrencyTotal total in _fold(_unconverted))
          UnconvertedGroup(
            currencyCode: total.currencyCode,
            net: total.net,
            transactionCount: total.transactionCount,
          ),
      ],
    );
  }

  static List<CurrencyTotal> _fold(Map<String, List<Money>> buckets) =>
      <CurrencyTotal>[
        for (final MapEntry<String, List<Money>> entry in buckets.entries)
          CurrencyTotal(
            currencyCode: entry.key,
            net: Money.sum(entry.value, currency: entry.key),
            transactionCount: entry.value.length,
          ),
      ]..sort((CurrencyTotal a, CurrencyTotal b) {
        final int byCount = b.transactionCount.compareTo(a.transactionCount);
        return byCount != 0
            ? byCount
            : a.currencyCode.compareTo(b.currencyCode);
      });
}

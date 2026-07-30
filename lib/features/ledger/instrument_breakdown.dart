/// **S-30 — the per-card breakdown** (KHA-37, US-E3, AC-E3.1, AC-E3.2, NFR-A6).
///
/// > AC-E3.1 — *"a per-card breakdown for a selected period, each card with its
/// > total."*
/// > AC-E3.2 — *"the card breakdown totals sum to the period total shown
/// > elsewhere in the app."*
///
/// ---
///
/// ## The line that makes AC-E3.2 true, and it is not the arithmetic
///
/// A naive per-card breakdown does **not** sum to the period total, and nobody
/// notices until a user checks. `test/features/ledger/totals_reconciliation_test.dart`
/// already pins why, and calls it *"the one place the chain deliberately does not
/// close"*:
///
/// > *"a cash transaction — one with no instrument at all — is in the period
/// > total but under no bank."*
///
/// Cash (US-B4, OQ-19) is a first-class payment method with no card and no
/// account. A footer that added up the cards and printed the result as *"Total"*
/// would print a number smaller than the one Home shows, on the screen whose
/// entire job is to make the period total traceable. The user's only available
/// conclusion would be that the app has lost some of their spending.
///
/// So [unassigned] exists: an explicit slice for everything with no instrument,
/// rendered as its own row. With it, [reconciles] is a genuine identity —
/// *cards + accounts + cash = the period total* — rather than an approximation
/// with a documented exception. That is NFR-A6's *"no derived figure that cannot
/// be traced back to its constituent transactions"* applied to a footer.
///
/// ## One definition of "an instrument's total", reused
///
/// The per-instrument figures are **not** recomputed here. [of] calls
/// `BankTreeBuilder.build`, which is the same code that produces the figure on
/// S-22 (Bank Detail) and S-23/S-24 (Account/Card Detail), and which P5a's
/// reconciliation test already exercises over 200 generated ledgers. A second
/// implementation would be a second chance to disagree with the screen the user
/// drills into from here.
///
/// The internal-transfer analysis is computed **once**, over the whole set, and
/// passed down — into the tree *and* into the cash slice *and* into the grand
/// total. `period_totals.dart` names getting this wrong as *"the most plausible
/// way to reintroduce AC-B11.1 as a bug"*: a transfer's two legs sit on two
/// different instruments, so any figure derived from a slice must be handed the
/// verdict rather than allowed to work it out.
///
/// ## Why every instrument appears, including the ones with no activity
///
/// The approved mockup (`docs/mockups/reports.html`, S-30) shows a card with
/// `0.00` on it. That is deliberate and worth keeping: a card the user holds and
/// did not use this month is information, and hiding it would leave them
/// wondering whether the app had forgotten the card or they had forgotten the
/// spending. An empty slice contributes a null base figure, so it changes no
/// arithmetic (see `PeriodTotals.base`'s null-is-not-zero note).
library;

import '../../core/money/money.dart';
import 'bank_tree.dart';
import 'base_currency.dart';
import 'internal_transfer.dart';
import 'ledger_transaction.dart';
import 'period_totals.dart';

/// One instrument's row on S-30.
final class InstrumentSlice {
  /// The bank this instrument belongs to — carried so the row can be labelled
  /// *"Blue Visa · Bank Aljazira"*. Two banks can each issue a `•••• 4821`, and
  /// a breakdown that showed only the masked identifier would be ambiguous
  /// exactly where the user is trying to reconcile against a statement.
  final LedgerBank bank;

  final InstrumentSummary summary;

  /// How many of the period's transactions hit this instrument — **all of them**,
  /// not only the ones inside [InstrumentSummary.totals].
  ///
  /// The two differ for the same reason `CategoryTotal.transactionCount` differs
  /// from its figure: the total is a *spend* figure and excludes income, cash
  /// withdrawals and internal transfers (US-B10/B11), while the count is what the
  /// user would see if they tapped through. A salary account therefore shows
  /// activity with little or no spend, which is honest rather than inconsistent.
  final int transactionCount;

  const InstrumentSlice({
    required this.bank,
    required this.summary,
    required this.transactionCount,
  });

  /// AC-B15.2 / AC-B3.1 — the friendly name once the user has set one, otherwise
  /// the masked identifier.
  String get label => summary.label;

  bool get isCard => summary.instrument.kind == 'card';

  @override
  String toString() =>
      'InstrumentSlice(#${summary.instrument.id}, n=$transactionCount)';
}

/// A period's spend, split by instrument, with the figure it must sum to.
final class InstrumentBreakdown {
  /// Accounts first, then cards, grouped by bank — the same order S-22's
  /// segmented control uses (the account funds the cards, so it leads).
  final List<InstrumentSlice> instruments;

  /// **Everything with no instrument at all**: cash (US-B4) and any SMS-derived
  /// row whose message named too few digits to key on. See the library comment
  /// for why this row is what makes AC-E3.2 hold.
  final PeriodTotals unassigned;

  /// How many transactions are behind [unassigned].
  final int unassignedCount;

  /// The period total — `LedgerTotals.spend` over the whole set, i.e. literally
  /// the figure Home and S-10 show.
  final PeriodTotals total;

  final String baseCurrencyCode;

  const InstrumentBreakdown({
    required this.instruments,
    required this.unassigned,
    required this.unassignedCount,
    required this.total,
    required this.baseCurrencyCode,
  });

  static const InstrumentBreakdown empty = InstrumentBreakdown(
    instruments: <InstrumentSlice>[],
    unassigned: PeriodTotals.empty,
    unassignedCount: 0,
    total: PeriodTotals.empty,
    baseCurrencyCode: BaseCurrency.defaultCode,
  );

  /// True when nothing at all happened in the period.
  bool get isEmpty =>
      total.isEmpty &&
      instruments.every(
        (InstrumentSlice slice) => slice.summary.totals.isEmpty,
      );

  /// True when [unassigned] has anything in it, i.e. when the cash row must be
  /// rendered. Hidden when zero — an always-present "Cash 0.00" row on an
  /// account-only ledger is noise, and unlike *Uncategorized* (AC-E2.3) there is
  /// no completeness claim riding on it.
  bool get hasUnassigned => unassignedCount > 0;

  /// **AC-E3.2, as a runtime assertion.**
  ///
  /// Compares [Money] values, never doubles: ADR-002 makes the arithmetic exact,
  /// so a tolerance would only hide a real disagreement. Null bases are handled
  /// as the absence they are, exactly as `CategoryBreakdown.reconciles` does — if
  /// nothing could be converted, both sides are null and there is no figure to
  /// disagree about.
  bool get reconciles {
    final List<Money> parts = <Money>[
      for (final InstrumentSlice slice in instruments)
        if (slice.summary.totals.base != null) slice.summary.totals.base!,
      if (unassigned.base != null) unassigned.base!,
    ];
    if (total.base == null) {
      return parts.isEmpty;
    }
    if (parts.isEmpty) {
      return false;
    }
    return Money.sum(parts, currency: baseCurrencyCode) == total.base;
  }

  /// Splits [transactions] by instrument for [period].
  ///
  /// [banks] and [instruments] are the full sets, so an instrument with no
  /// activity still gets a row (see the library comment).
  static InstrumentBreakdown of(
    List<LedgerTransaction> transactions, {
    required PeriodRange period,
    required List<LedgerBank> banks,
    required List<LedgerInstrument> instruments,
    String baseCurrencyCode = BaseCurrency.defaultCode,
  }) {
    final List<LedgerTransaction> live = <LedgerTransaction>[
      for (final LedgerTransaction txn in transactions)
        if (!txn.isDeleted) txn,
    ];

    // ONE analysis, over the whole set, shared by every figure below.
    final InternalTransferAnalysis transfers = InternalTransferDetector.analyze(
      live,
    );

    final List<BankTreeNode> tree = BankTreeBuilder.build(
      banks: banks,
      instruments: instruments,
      transactions: live,
      period: period,
      baseCurrencyCode: baseCurrencyCode,
      transfers: transfers,
    );

    // Counts per instrument, over the period only — the tree does not carry
    // them, and deriving them here from the same `live` list keeps them in step
    // with the figures beside them.
    final Map<int, int> countsByInstrument = <int, int>{};
    final List<LedgerTransaction> withoutInstrument = <LedgerTransaction>[];
    int unassignedCount = 0;
    for (final LedgerTransaction txn in live) {
      final int? instrumentId = txn.instrument?.id;
      if (instrumentId == null) {
        withoutInstrument.add(txn);
        if (period.contains(txn.occurredAt)) {
          unassignedCount += 1;
        }
        continue;
      }
      if (period.contains(txn.occurredAt)) {
        countsByInstrument[instrumentId] =
            (countsByInstrument[instrumentId] ?? 0) + 1;
      }
    }

    final List<InstrumentSlice> slices = <InstrumentSlice>[];
    for (final BankTreeNode node in tree) {
      for (final InstrumentSummary summary in <InstrumentSummary>[
        ...node.accounts,
        ...node.cards,
      ]) {
        slices.add(
          InstrumentSlice(
            bank: node.bank,
            summary: summary,
            transactionCount: countsByInstrument[summary.instrument.id] ?? 0,
          ),
        );
      }
    }

    return InstrumentBreakdown(
      instruments: slices,
      unassigned: LedgerTotals.spend(
        withoutInstrument,
        period: period,
        baseCurrencyCode: baseCurrencyCode,
        transfers: transfers,
      ),
      unassignedCount: unassignedCount,
      total: LedgerTotals.spend(
        live,
        period: period,
        baseCurrencyCode: baseCurrencyCode,
        transfers: transfers,
      ),
      baseCurrencyCode: baseCurrencyCode,
    );
  }
}

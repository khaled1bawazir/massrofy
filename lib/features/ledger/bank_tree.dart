/// The bank → account/card tree the banks screens render — US-B2, US-B12,
/// US-B13, AC-B2.1, AC-B2.2, AC-B2.3, AC-B12.2, AC-B13.3.
///
/// ## Why accounts and cards are two lists, not one list with a type column
///
/// AC-B13.3 requires account activity and card activity to be *"distinguishable,
/// not merged into one undifferentiated list"*, and design.md S-22 gives them
/// a segmented control rather than a mixed list with badges. Modelling them as
/// two separate collections here means a screen cannot accidentally render
/// them merged — the shape of the data matches the shape of the requirement.
///
/// ## Totals are computed, never stored
///
/// Every total on this tree comes from [LedgerTotals] over the transactions
/// the same screen can list. NFR-A6 forbids a derived figure that cannot be
/// traced to its constituents, and a persisted `bank.total` column is exactly
/// how such a figure drifts out of agreement with the ledger and stays wrong
/// silently.
library;

import 'base_currency.dart';
import 'instrument_identity.dart';
import 'internal_transfer.dart';
import 'ledger_transaction.dart';
import 'period_totals.dart';

/// One bank, as displayed.
final class LedgerBank {
  final int id;
  final String canonicalKey;
  final String displayNameAr;
  final String displayNameEn;

  const LedgerBank({
    required this.id,
    required this.canonicalKey,
    required this.displayNameAr,
    required this.displayNameEn,
  });

  /// The name to show for [languageCode] (`ar` or anything else → English).
  ///
  /// Falls back to the other language rather than to an empty string: a bank
  /// row created from a pack that declared only one name must still be
  /// labelled with something the user recognises.
  String displayName(String languageCode) {
    final String preferred = languageCode == 'ar'
        ? displayNameAr
        : displayNameEn;
    if (preferred.trim().isNotEmpty) {
      return preferred;
    }
    return languageCode == 'ar' ? displayNameEn : displayNameAr;
  }

  @override
  String toString() => 'LedgerBank(#$id, $canonicalKey)';
}

/// One bank with its instruments and its period figures.
final class BankTreeNode {
  final LedgerBank bank;

  /// AC-B13.3 — kept apart by construction.
  final List<InstrumentSummary> accounts;
  final List<InstrumentSummary> cards;

  /// AC-B2.1/AC-B12.2 — the bank's combined figure for the period.
  final PeriodTotals totals;

  const BankTreeNode({
    required this.bank,
    required this.accounts,
    required this.cards,
    required this.totals,
  });

  /// True when this bank has been created but nothing has landed under it
  /// yet — possible when a message resolved a bank but named no instrument
  /// it could key on. The banks screen shows the bank rather than hiding it:
  /// a bank whose messages the app cannot fully read is exactly the thing the
  /// user should be able to see.
  bool get hasNoInstruments => accounts.isEmpty && cards.isEmpty;
}

/// One account or card with its own period figures (AC-B2.2, AC-B2.3).
final class InstrumentSummary {
  final LedgerInstrument instrument;

  /// AC-B2.3 — equals the sum of exactly this instrument's transactions for
  /// the period, and there is a test that asserts precisely that.
  final PeriodTotals totals;

  /// AC-B14.2 — the linked settlement account's label, or null for "not
  /// linked" (AC-B14.3). Resolved here rather than in the widget so the
  /// screen never has to look another instrument up mid-build.
  final String? settlementAccountLabel;

  const InstrumentSummary({
    required this.instrument,
    required this.totals,
    this.settlementAccountLabel,
  });

  /// **AC-B15.2 / AC-B3.1.** The label for this instrument: its friendly name
  /// once the user has given it one, otherwise the masked identifier so an
  /// auto-created instrument is still identifiable.
  ///
  /// The masked identifier is passed through unchanged here; the widget layer
  /// formats it as `•••• 4821` (see `core/text/masking.dart`), keeping the
  /// bullet styling in one place.
  String get label => (friendlyName ?? '').trim().isEmpty
      ? instrument.maskedIdentifier
      : friendlyName!;

  String? get friendlyName => instrument.friendlyName;

  /// True when the user has not renamed this instrument yet — the state
  /// design.md calls `auto-created-unnamed`.
  bool get isUnnamed => (friendlyName ?? '').trim().isEmpty;
}

/// Assembles the tree from flat inputs.
abstract final class BankTreeBuilder {
  /// Groups [instruments] under [banks] and computes every figure from
  /// [transactions], all for [period].
  ///
  /// Instruments whose `bankId` matches no supplied bank are dropped rather
  /// than shown under a placeholder — that can only happen if a caller passed
  /// an inconsistent slice, and inventing a "Other" bank would put real money
  /// under a fictional entity. The foreign key makes it unreachable from the
  /// database.
  static List<BankTreeNode> build({
    required List<LedgerBank> banks,
    required List<LedgerInstrument> instruments,
    required List<LedgerTransaction> transactions,
    required PeriodRange period,
    String baseCurrencyCode = BaseCurrency.defaultCode,
  }) {
    // **AC-B11.1 depends on this line being here and not one level down.**
    //
    // The two legs of an internal transfer live on two *different*
    // instruments, so a detector run per instrument would never see a pair
    // and every internal transfer would be counted as spend. It is analysed
    // once over the whole set and the result is handed to each per-instrument
    // total below — see `LedgerTotals.report`'s note on slicing.
    final InternalTransferAnalysis transfers = InternalTransferDetector.analyze(
      transactions,
    );

    // Transactions grouped by instrument id once, rather than filtering the
    // whole list per instrument — with a few thousand transactions and a
    // handful of instruments the difference is real on a mid-range phone.
    final Map<int, List<LedgerTransaction>> byInstrument =
        <int, List<LedgerTransaction>>{};
    for (final LedgerTransaction txn in transactions) {
      final int? instrumentId = txn.instrument?.id;
      if (instrumentId == null) {
        continue;
      }
      byInstrument
          .putIfAbsent(instrumentId, () => <LedgerTransaction>[])
          .add(txn);
    }

    final Map<int, LedgerInstrument> instrumentById = <int, LedgerInstrument>{
      for (final LedgerInstrument instrument in instruments)
        instrument.id: instrument,
    };

    return <BankTreeNode>[
      for (final LedgerBank bank in banks)
        _nodeFor(
          bank: bank,
          instruments: instruments
              .where((LedgerInstrument i) => i.bankId == bank.id)
              .toList(growable: false),
          instrumentById: instrumentById,
          byInstrument: byInstrument,
          period: period,
          baseCurrencyCode: baseCurrencyCode,
          transfers: transfers,
        ),
    ];
  }

  static BankTreeNode _nodeFor({
    required LedgerBank bank,
    required List<LedgerInstrument> instruments,
    required Map<int, LedgerInstrument> instrumentById,
    required Map<int, List<LedgerTransaction>> byInstrument,
    required PeriodRange period,
    required String baseCurrencyCode,
    required InternalTransferAnalysis transfers,
  }) {
    final List<InstrumentSummary> accounts = <InstrumentSummary>[];
    final List<InstrumentSummary> cards = <InstrumentSummary>[];
    final List<LedgerTransaction> bankTransactions = <LedgerTransaction>[];

    for (final LedgerInstrument instrument in instruments) {
      final List<LedgerTransaction> own =
          byInstrument[instrument.id] ?? const <LedgerTransaction>[];
      bankTransactions.addAll(own);

      final InstrumentSummary summary = InstrumentSummary(
        instrument: instrument,
        totals: LedgerTotals.spend(
          own,
          period: period,
          baseCurrencyCode: baseCurrencyCode,
          transfers: transfers,
        ),
        settlementAccountLabel: _labelForSettlement(
          instrument.settlementAccountId,
          instrumentById,
        ),
      );

      if (instrument.kind == InstrumentKind.card) {
        cards.add(summary);
      } else {
        accounts.add(summary);
      }
    }

    return BankTreeNode(
      bank: bank,
      accounts: accounts,
      cards: cards,
      // Computed over the same transactions the per-instrument figures came
      // from, so "the bank total equals the sum of its instruments" is true
      // by construction rather than by two independent queries agreeing.
      totals: LedgerTotals.spend(
        bankTransactions,
        period: period,
        baseCurrencyCode: baseCurrencyCode,
        transfers: transfers,
      ),
    );
  }

  static String? _labelForSettlement(
    int? settlementAccountId,
    Map<int, LedgerInstrument> instrumentById,
  ) {
    if (settlementAccountId == null) {
      return null; // AC-B14.3 — unlinked, never guessed.
    }
    final LedgerInstrument? account = instrumentById[settlementAccountId];
    if (account == null) {
      return null;
    }
    final String? friendly = account.friendlyName;
    return (friendly ?? '').trim().isEmpty
        ? account.maskedIdentifier
        : friendly!;
  }
}

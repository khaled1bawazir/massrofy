/// Builders for the P3b-1 ledger tests (KHA-27, KHA-28, KHA-29, KHA-70).
///
/// [LedgerTransaction] has twenty-odd fields, almost all of them nullable, and
/// a test that constructs one inline buries its actual subject under twelve
/// lines of `null`. These builders default everything to "an ordinary SAR card
/// purchase in July 2026" so each test states only what it is about — which is
/// also what makes a reviewer able to see, at a glance, which fact a test is
/// really pinning.
library;

import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';

/// The period every fixture below sits inside unless it says otherwise.
final PeriodRange july2026 = PeriodRange(
  startUtc: DateTime.utc(2026, 7),
  endUtcExclusive: DateTime.utc(2026, 8),
);

/// An instrument belonging to the user. Every instrument row in the real
/// database is one of these — created from a message about the user's own
/// account (US-B15) — which is what makes "both legs hit known instruments"
/// equivalent to "both sides are mine" in `internal_transfer.dart`.
LedgerInstrument instrument({
  required int id,
  int bankId = 1,
  String kind = 'account',
  String masked = '****3388',
}) => LedgerInstrument(
  id: id,
  bankId: bankId,
  kind: kind,
  maskedIdentifier: masked,
);

/// One transaction, with everything defaulted to the ordinary case.
LedgerTransaction tx({
  required int id,
  required String amount,
  String currency = 'SAR',
  String direction = 'debit',
  String type = TransactionType.posPurchase,
  bool affectsSpend = true,
  bool isDeleted = false,
  DateTime? at,
  String? convertedAmount,
  String convertedCurrency = 'SAR',
  String? fee,
  String feeCurrency = 'SAR',
  String? fxRate,
  DateTime? fxRateDate,
  String? fxRateSource,
  bool conversionPending = false,
  String? reference,
  LedgerInstrument? on,
  String? transferState,
}) => LedgerTransaction(
  id: id,
  amount: Money.parse(amount, currency: currency),
  direction: direction,
  transactionType: type,
  affectsSpend: affectsSpend,
  isDeleted: isDeleted,
  occurredAt: at ?? DateTime.utc(2026, 7, 15, 10),
  convertedAmount: convertedAmount == null
      ? null
      : Money.parse(convertedAmount, currency: convertedCurrency),
  feeAmount: fee == null ? null : Money.parse(fee, currency: feeCurrency),
  fxRate: fxRate,
  fxRateDate: fxRateDate,
  fxRateSource: fxRateSource,
  conversionPending: conversionPending,
  referenceNumber: reference,
  instrument: on,
  internalTransferState: transferState,
);

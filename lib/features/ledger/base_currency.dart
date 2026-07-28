/// Turning a native-currency transaction into a base-currency figure —
/// KHA-27, KHA-70, US-B9, AC-B9.1, AC-B9.2, AC-B9.3, NFR-A5, ADR-009.
///
/// ---
///
/// ## The rule that shapes this whole file
///
/// > **Never invent a rate** (ADR-009). Prefer what the SMS stated; where it
/// > stated nothing, say so and leave the transaction out of the base total
/// > — visibly.
///
/// NFR-A5 puts it as a correctness guard: *"two amounts in different
/// currencies must NEVER be summed without a stated conversion"*. `Money`
/// already makes the accidental version impossible — adding 49.99 USD to
/// 152.75 SAR throws [CurrencyMismatchError] — so the remaining risk is the
/// *deliberate* version: someone reaching for a plausible rate to make a
/// total come out. There is no code path here that produces a rate from
/// anything other than the transaction's own recorded data.
///
/// ## The four cases, in the order they are tried
///
/// | # | Situation | Result | `fxRateSource` |
/// |---|---|---|---|
/// | 1 | Native currency **is** the base currency | the amount itself | — |
/// | 2 | The message printed the converted amount (PRD §3.4's parenthesised form) | that figure, unchanged | `sms_implied` |
/// | 3 | The message printed a rate but no converted amount | `MoneyConverter.convert` with that rate | `sms_stated` |
/// | 4 | Foreign currency, nothing else | **unavailable** — excluded from the base total and counted on an explicit "not converted" line | `null`, `conversionPending = true` |
///
/// Case 2 is preferred over case 3 deliberately, and ADR-009 says why: the
/// bank's own converted figure is *what actually hit the account*. A figure
/// we recompute from a printed rate can differ by a halala from the one the
/// user can see on their statement, and a spending tracker that disagrees
/// with the bank by a halala is a spending tracker nobody believes.
///
/// Case 4 is the one that takes discipline. ADR-009's instruction is to
/// *"show an explicit line 'N transactions not converted' so reconciliation
/// is visibly incomplete rather than silently wrong"* — see
/// `PeriodTotals.unconverted`. A total that quietly omits a purchase is worse
/// than one that says it is incomplete.
///
/// ## AC-B9.3 and the rate date (KHA-70)
///
/// Every conversion this file produces carries an [ExchangeRate] with a rate
/// value, a rate **date** and a source, so the detail screen can show all
/// three. The date may be `null` — see [ExchangeRate.rateDate] for why that
/// is a legitimate value and not a hole — and the UI must then say *"date
/// unknown"* in words rather than rendering an undated rate as though it were
/// authoritative. That was defect D-QA-2 / KHA-70 in its entirety.
library;

import 'package:decimal/decimal.dart';

import '../../core/money/currency_exponents.dart';
import '../../core/money/exchange_rate.dart';
import '../../core/money/money.dart';
import '../../core/money/money_converter.dart';
import 'ledger_transaction.dart';

/// The currency period totals are expressed in.
///
/// ADR-009: *"Base currency defaults to SAR, user-configurable."* The
/// configurable half is a settings surface that does not exist yet, so the
/// default lives here as a named constant rather than being spelled `'SAR'`
/// in a dozen call sites — which is what makes it a one-line change when the
/// setting arrives, and what makes a hard-coded `'SAR'` anywhere else a
/// review finding.
abstract final class BaseCurrency {
  static const String defaultCode = 'SAR';
}

/// How a base-currency figure was arrived at.
enum ConversionBasis {
  /// The transaction was already in the base currency. No conversion, no
  /// rate, nothing to distrust.
  native,

  /// The bank printed the converted amount and we used it verbatim.
  bankSuppliedAmount,

  /// We applied a rate the message stated.
  statedRate,

  /// No conversion is possible from what was recorded (ADR-009 case 4).
  unavailable,
}

/// The base-currency view of one amount.
final class BaseCurrencyAmount {
  /// The figure in the base currency, or `null` when [basis] is
  /// [ConversionBasis.unavailable].
  ///
  /// Null rather than `Money.zero`: a purchase we cannot convert did not cost
  /// nothing. This is the same explicit-unknown discipline AC-B1.3 applies to
  /// fields, applied to a derived figure.
  final Money? value;

  final ConversionBasis basis;

  /// The rate used or implied, with its date and source (AC-B9.3). Null for
  /// [ConversionBasis.native] (there is no rate) and for
  /// [ConversionBasis.unavailable] (there is none to show).
  final ExchangeRate? rate;

  const BaseCurrencyAmount._(this.value, this.basis, this.rate);

  bool get isAvailable => value != null;

  /// True when this amount is missing from the base total and the user must
  /// be told so — ADR-009's "N transactions not converted" line.
  bool get isPending => basis == ConversionBasis.unavailable;

  @override
  String toString() => 'BaseCurrencyAmount(${basis.name})';
}

/// Converts transactions and their components into the base currency.
abstract final class BaseCurrencyConverter {
  /// The number of fractional digits an implied rate is derived to.
  ///
  /// ADR-009: *"derive `impliedRate = base / foreign` as a `Rational`, display
  /// to 8 dp"*. Eight is enough that re-multiplying the rate by the native
  /// amount reproduces the bank's converted figure for any realistic amount,
  /// and the derivation is only ever used for **display** — the converted
  /// amount itself comes from the bank, never from re-multiplying.
  static const int impliedRateScale = 8;

  /// The base-currency figure for [transaction]'s own amount.
  static BaseCurrencyAmount forTransaction(
    LedgerTransaction transaction, {
    String baseCurrencyCode = BaseCurrency.defaultCode,
  }) => _convert(
    amount: transaction.amount,
    convertedAmount: transaction.convertedAmount,
    fxRate: transaction.fxRate,
    fxRateDate: transaction.fxRateDate,
    fxRateSource: transaction.fxRateSource,
    baseCurrencyCode: baseCurrencyCode,
  );

  /// The base-currency figure for [transaction]'s FX/international fee.
  ///
  /// The fee is converted through the **same recorded rate as its parent
  /// transaction**, because that is the only rate this record has. In
  /// practice a bank charges the fee in the base currency already (both
  /// fixtures in the corpus do), so this almost always lands in case 1 — but
  /// "almost always" is not an invariant, and a fee in a third currency must
  /// not be silently added to a base-currency total (NFR-A5).
  static BaseCurrencyAmount feeForTransaction(
    LedgerTransaction transaction, {
    String baseCurrencyCode = BaseCurrency.defaultCode,
  }) {
    final Money? fee = transaction.feeAmount;
    if (fee == null) {
      return const BaseCurrencyAmount._(
        null,
        ConversionBasis.unavailable,
        null,
      );
    }
    return _convert(
      amount: fee,
      // The bank's converted *amount* belongs to the purchase, not to the
      // fee, so it is deliberately not offered here — only the rate is.
      convertedAmount: null,
      fxRate: transaction.fxRate,
      fxRateDate: transaction.fxRateDate,
      fxRateSource: transaction.fxRateSource,
      baseCurrencyCode: baseCurrencyCode,
    );
  }

  static BaseCurrencyAmount _convert({
    required Money amount,
    required Money? convertedAmount,
    required String? fxRate,
    required DateTime? fxRateDate,
    required String? fxRateSource,
    required String baseCurrencyCode,
  }) {
    final String base = baseCurrencyCode.toUpperCase();

    // --- Case 1: already there -------------------------------------------
    if (amount.currencyCode == base) {
      return BaseCurrencyAmount._(amount, ConversionBasis.native, null);
    }

    // --- Case 2: the bank did the conversion for us ----------------------
    if (convertedAmount != null && convertedAmount.currencyCode == base) {
      return BaseCurrencyAmount._(
        convertedAmount,
        ConversionBasis.bankSuppliedAmount,
        _impliedRate(
          native: amount,
          converted: convertedAmount,
          statedRate: fxRate,
          rateDate: fxRateDate,
          source: fxRateSource,
        ),
      );
    }

    // --- Case 3: a stated rate -------------------------------------------
    final Decimal? rateValue = _parseRate(fxRate);
    if (rateValue != null && rateValue > Decimal.zero) {
      final ExchangeRate rate = ExchangeRate(
        fromCurrency: amount.currencyCode,
        toCurrency: base,
        rate: rateValue,
        rateDate: fxRateDate,
        source: _sourceFrom(fxRateSource) ?? ExchangeRateSource.smsStated,
      );
      return BaseCurrencyAmount._(
        MoneyConverter.convert(
          amount,
          rate: rate,
          targetExponent: minorUnitExponentFor(base),
        ),
        ConversionBasis.statedRate,
        rate,
      );
    }

    // --- Case 4: nothing to convert with ---------------------------------
    return const BaseCurrencyAmount._(null, ConversionBasis.unavailable, null);
  }

  /// Derives the rate the bank's own figures imply, purely so AC-B9.3 has
  /// something to display. Never used to produce the converted amount.
  static ExchangeRate? _impliedRate({
    required Money native,
    required Money converted,
    required String? statedRate,
    required DateTime? rateDate,
    required String? source,
  }) {
    if (native.amount == Decimal.zero) {
      // A zero magnitude is a legal amount (see `sign_convention.dart` — zero
      // and unknown are different facts, KHA-25), so this division genuinely
      // can be reached. There is no rate implied by "0 USD became 0 SAR", and
      // returning null gives the UI an honest "no rate to show" rather than a
      // crash or an invented figure.
      return null;
    }
    final Decimal? stated = _parseRate(statedRate);
    final Decimal value =
        stated ??
        (converted.amount / native.amount).toDecimal(
          scaleOnInfinitePrecision: impliedRateScale,
        );
    return ExchangeRate(
      fromCurrency: native.currencyCode,
      toCurrency: converted.currencyCode,
      rate: value,
      rateDate: rateDate,
      source:
          _sourceFrom(source) ??
          (stated == null
              ? ExchangeRateSource.smsImplied
              : ExchangeRateSource.smsStated),
    );
  }

  /// Parses the stored rate string. Returns null — rather than throwing — for
  /// anything unparseable, so one malformed legacy row degrades into "not
  /// converted" instead of taking down a whole period's totals (NFR-R5).
  static Decimal? _parseRate(String? raw) {
    final String trimmed = (raw ?? '').trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      return Decimal.parse(trimmed);
    } on FormatException {
      return null;
    }
  }

  /// Maps the stored `fx_rate_source` string onto its enum. Unknown values
  /// return null so the caller falls back to what it can infer, per §5.2's
  /// forward-compatibility rule.
  static ExchangeRateSource? _sourceFrom(String? stored) => switch (stored) {
    FxRateSource.smsImplied => ExchangeRateSource.smsImplied,
    FxRateSource.smsStated => ExchangeRateSource.smsStated,
    FxRateSource.user => ExchangeRateSource.user,
    FxRateSource.carriedForward => ExchangeRateSource.carriedForward,
    _ => null,
  };
}

/// What the ingestion path should **store** in the FX columns for one parsed
/// message — KHA-70's *"have the parser populate them where the message states
/// or implies them, and leave them explicitly unknown where it does not"*.
///
/// Kept next to [BaseCurrencyConverter] on purpose: the code that writes the
/// rate and the code that reads it back have to agree about what each source
/// value means, and a hundred lines apart is close enough to notice.
final class FxRecording {
  /// Exact decimal string, or null when there is no rate to record.
  final String? rate;

  final DateTime? rateDate;

  /// One of [FxRateSource]'s values, or null when there is no rate.
  final String? source;

  /// ADR-009 case 4 — see `Transactions.conversionPending`.
  final bool conversionPending;

  const FxRecording({
    this.rate,
    this.rateDate,
    this.source,
    this.conversionPending = false,
  });

  /// Nothing to record: the transaction is in the base currency.
  static const FxRecording none = FxRecording();

  /// Derives what to store from what the message actually contained.
  ///
  /// ## Why [occurredAtFromMessage] and not the transaction's `occurredAt`
  ///
  /// The rate date is set to the moment the message says the movement
  /// happened, because a bank quotes the conversion it applied *at that
  /// moment* in the same sentence as the amount. That is an inference the
  /// message supports, and it is labelled as such through [source]
  /// (`sms_implied` / `sms_stated`) so a user inspecting the rate can see
  /// where the date came from.
  ///
  /// But it is only honest when the message stated a time at all. Where the
  /// pipeline fell back to the SMS **delivery** time (architecture §7.4's
  /// `received_at_fallback`), that timestamp is a fact about our phone, not
  /// about the bank's conversion — so the caller passes `null` here and the
  /// rate date stays unknown. That distinction is the difference between
  /// KHA-70 being fixed and being papered over.
  static FxRecording forParsedMessage({
    required Money amount,
    required Money? convertedAmount,
    required String? statedRate,
    required DateTime? occurredAtFromMessage,
    String baseCurrencyCode = BaseCurrency.defaultCode,
  }) {
    final String base = baseCurrencyCode.toUpperCase();
    if (amount.currencyCode == base) {
      return none;
    }

    final Decimal? stated = BaseCurrencyConverter._parseRate(statedRate);
    if (stated != null && stated > Decimal.zero) {
      return FxRecording(
        // Stored **verbatim** (trimmed), not re-serialised through `Decimal`.
        // `Decimal.parse('3.7510').toString()` is `3.751`, and dropping that
        // trailing zero would mean the rate the user inspects is not quite
        // the rate the bank printed — a small thing that undermines exactly
        // the traceability AC-B9.3 asks for. The parse above is a validity
        // check, not a normalisation step.
        rate: statedRate!.trim(),
        rateDate: occurredAtFromMessage,
        source: FxRateSource.smsStated,
      );
    }

    if (convertedAmount != null &&
        convertedAmount.currencyCode == base &&
        amount.amount != Decimal.zero) {
      return FxRecording(
        rate: (convertedAmount.amount / amount.amount)
            .toDecimal(
              scaleOnInfinitePrecision: BaseCurrencyConverter.impliedRateScale,
            )
            .toString(),
        rateDate: occurredAtFromMessage,
        source: FxRateSource.smsImplied,
      );
    }

    // Foreign currency, and the message gave us nothing to convert with.
    // ADR-009 forbids inventing a rate, so this is recorded as an explicit
    // gap the totals will report rather than a hole they will hide.
    return const FxRecording(conversionPending: true);
  }
}

/// The persisted values of `Transaction.fx_rate_source` (architecture §4.2,
/// ADR-009's table) — KHA-70.
///
/// String constants for the same reason as everywhere else here: this is the
/// column's stored vocabulary, and [ExchangeRateSource] is its in-memory
/// counterpart. The two are mapped in exactly one place
/// ([BaseCurrencyConverter._sourceFrom] and [FxRateSource.forEnum]).
abstract final class FxRateSource {
  /// The message gave both amounts; the rate is derived from them.
  static const String smsImplied = 'sms_implied';

  /// The message printed the rate.
  static const String smsStated = 'sms_stated';

  /// The user typed it.
  static const String user = 'user';

  /// The most recent known rate for the pair, carried forward and marked as
  /// such. No code path produces this yet — it arrives with the manual-rate
  /// entry surface. The value exists now because ADR-009 defines it and
  /// because a stored vocabulary that grows later is a migration.
  static const String carriedForward = 'carried_forward';

  static const Set<String> all = <String>{
    smsImplied,
    smsStated,
    user,
    carriedForward,
  };

  static bool isKnown(String value) => all.contains(value);

  /// The stored spelling for [source].
  static String forEnum(ExchangeRateSource source) => switch (source) {
    ExchangeRateSource.smsImplied => smsImplied,
    ExchangeRateSource.smsStated => smsStated,
    ExchangeRateSource.user => user,
    ExchangeRateSource.carriedForward => carriedForward,
  };
}

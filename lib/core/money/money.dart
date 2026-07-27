import 'package:decimal/decimal.dart';

import 'currency_mismatch_error.dart';
import 'numeral_normalizer.dart';

/// An exact-decimal, currency-tagged amount of money.
///
/// ## Why this class exists (`docs/architecture.md` ADR-002)
/// Dart's binary IEEE-754 floating-point number type cannot represent money
/// exactly — `0.1 + 0.2 != 0.3` under that representation — and NFR-A4 bans
/// floating point for money outright, everywhere, for a banking app. `Money`
/// wraps an arbitrary-precision [Decimal] (from `package:decimal`, itself
/// backed by [BigInt], so it never loses precision) together with an ISO
/// 4217 currency code, and makes several mistakes *impossible to write*,
/// not just discouraged:
///
///  - You cannot construct a `Money` from a floating-point value — there is
///    no such factory.
///  - You cannot read a `Money` back out as a floating-point value — there
///    is no such conversion method.
///  - You cannot add, subtract, or compare two `Money` values of different
///    currencies "by accident" — every such operation throws
///    [CurrencyMismatchError] unless you explicitly convert first (see
///    `money_converter.dart`).
///
/// ### A note for readers new to Dart
/// This is a **value object**: every field is `final` (the object can never
/// be mutated after construction), and `==`/`hashCode` are overridden so two
/// `Money` instances with the same amount and currency are equal *by value*,
/// not by identity (unlike the default `Object.==`, which compares
/// references). The default, unnamed constructor is written as `Money._` —
/// the leading underscore makes it *private to this library* (this file),
/// so code anywhere else, including other files in this very package, can
/// only ever create a `Money` through one of the named `factory`
/// constructors below (`Money.parse`, `Money.fromMinorUnits`, `Money.zero`).
/// That is what turns "please always use the safe constructors" from a
/// convention into a compile-time guarantee.
class Money implements Comparable<Money> {
  /// The exact decimal amount. Never a floating-point value, never rounded
  /// on construction — only rounded explicitly and deliberately (see
  /// `MoneyConverter.convert`, which documents its own rounding rule).
  final Decimal amount;

  /// ISO 4217 currency code, always stored upper-case (e.g. `SAR`, `USD`).
  final String currencyCode;

  const Money._(this.amount, this.currencyCode);

  /// Parses [value] as a decimal amount in [currency].
  ///
  /// [value] is passed through [normalizeNumerals] first, so Arabic-Indic
  /// digits, the Arabic decimal separator, and thousands separators (Arabic
  /// or ASCII) are all accepted — exactly what a bank SMS or a manual-entry
  /// text field may contain.
  ///
  /// Throws [FormatException] if the normalised string is not a valid
  /// decimal literal. Throws [ArgumentError] if [currency] is not a 3-letter
  /// code.
  factory Money.parse(String value, {required String currency}) {
    final String normalized = normalizeNumerals(value);
    final Decimal decimal = Decimal.parse(normalized);
    return Money._(decimal, _normalizeCurrencyCode(currency));
  }

  /// Like [Money.parse], but returns `null` instead of throwing on invalid
  /// input. Intended for the parser pipeline (ADR-007), where a failed
  /// extraction must route the message to the review queue rather than
  /// crash the ingestion isolate (NFR-R5: "a parse failure on one SMS must
  /// not prevent processing of others").
  static Money? tryParse(String value, {required String currency}) {
    try {
      return Money.parse(value, currency: currency);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// Builds a [Money] from an integer count of minor units (e.g. halalas)
  /// given the currency's decimal [exponent] (SAR/USD = 2, KWD/BHD/JOD = 3,
  /// JPY = 0). This exists for the `*_minor INTEGER` companion column ADR-002
  /// defines for indexing/range-filtering — **never** for arithmetic; the
  /// non-negotiable rule is that no total is ever produced by summing minor
  /// units in SQL. See `docs/architecture.md` ADR-002.
  factory Money.fromMinorUnits(
    int minorUnits, {
    required String currency,
    int exponent = 2,
  }) {
    final bool negative = minorUnits < 0;
    final String digits = minorUnits.abs().toString().padLeft(
      exponent + 1,
      '0',
    );
    final String wholePart = digits.substring(0, digits.length - exponent);
    final String fractionPart = exponent == 0
        ? ''
        : '.${digits.substring(digits.length - exponent)}';
    final Decimal decimal = Decimal.parse(
      '${negative ? '-' : ''}$wholePart$fractionPart',
    );
    return Money._(decimal, _normalizeCurrencyCode(currency));
  }

  /// A zero amount in [currency]. Useful as the starting accumulator for
  /// [Money.sum] and for "no transactions yet" empty states (AC-E1.3).
  factory Money.zero(String currency) =>
      Money._(Decimal.zero, _normalizeCurrencyCode(currency));

  /// Sums [values], which must all share [currency]. Throws
  /// [CurrencyMismatchError] on the first mismatched element.
  ///
  /// This is the **only** sanctioned place list-of-`Money` aggregation
  /// happens: in Dart, over `Money`, never as a SQL `SUM()`/`AVG()` over a
  /// `_minor` column (ADR-002's non-negotiable rule; also enforced by
  /// `.github/scripts/check_money_type_ban.sh` against `.drift` files).
  static Money sum(Iterable<Money> values, {required String currency}) {
    final String normalizedCurrency = _normalizeCurrencyCode(currency);
    Money total = Money.zero(normalizedCurrency);
    for (final Money value in values) {
      total = total + value; // throws CurrencyMismatchError on mismatch
    }
    return total;
  }

  Money operator +(Money other) {
    _assertSameCurrency('add', other);
    return Money._(amount + other.amount, currencyCode);
  }

  Money operator -(Money other) {
    _assertSameCurrency('subtract', other);
    return Money._(amount - other.amount, currencyCode);
  }

  /// Unary negation — flips the sign, keeps the currency. Used, for example,
  /// to represent a refund as the inverse of its original charge (US-B7).
  Money operator -() => Money._(-amount, currencyCode);

  bool operator <(Money other) {
    _assertSameCurrency('compare', other);
    return amount < other.amount;
  }

  bool operator <=(Money other) {
    _assertSameCurrency('compare', other);
    return amount <= other.amount;
  }

  bool operator >(Money other) {
    _assertSameCurrency('compare', other);
    return amount > other.amount;
  }

  bool operator >=(Money other) {
    _assertSameCurrency('compare', other);
    return amount >= other.amount;
  }

  @override
  int compareTo(Money other) {
    _assertSameCurrency('compare', other);
    return amount.compareTo(other.amount);
  }

  void _assertSameCurrency(String operation, Money other) {
    if (currencyCode != other.currencyCode) {
      throw CurrencyMismatchError(operation, currencyCode, other.currencyCode);
    }
  }

  /// True if this amount is strictly negative.
  bool get isNegative => amount.sign < 0;

  /// True if this amount is exactly zero.
  bool get isZero => amount == Decimal.zero;

  /// Absolute value, same currency.
  Money get abs => Money._(amount.abs(), currencyCode);

  /// The canonical decimal string, e.g. `"1234.50"` — this is exactly what
  /// is persisted in the authoritative `<name>_amount TEXT` column (ADR-002)
  /// and it round-trips exactly through [Money.parse]. Deliberately named
  /// differently from [toString] (see below) so a value can only be
  /// serialised or displayed by a call that says so explicitly.
  String toCanonicalString() => amount.toString();

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.amount == amount &&
      other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(amount, currencyCode);

  /// Deliberately redacted. `Money` must never leak an exact figure through
  /// an accidental string interpolation in a log line, an exception message,
  /// or a debug print — that is precisely the failure mode ADR-015's
  /// `SafeLogger` exists to prevent, and overriding `toString()` here closes
  /// the gap even for code that doesn't go through `SafeLogger` at all (e.g.
  /// a stray `'Total: $money'` string). Use [toCanonicalString] (storage) or
  /// a dedicated display-formatting function (presentation layer) when a
  /// value must genuinely be shown — never rely on `toString()` for that.
  @override
  String toString() => 'Money(<redacted>, $currencyCode)';

  static String _normalizeCurrencyCode(String currency) {
    final String upper = currency.trim().toUpperCase();
    if (upper.length != 3 || !RegExp(r'^[A-Z]{3}$').hasMatch(upper)) {
      throw ArgumentError.value(
        currency,
        'currency',
        'must be a 3-letter ISO 4217 code (e.g. "SAR")',
      );
    }
    return upper;
  }
}

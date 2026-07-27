import 'package:decimal/decimal.dart';

import 'exchange_rate.dart';
import 'money.dart';

/// The **only** sanctioned way to combine [Money] values of different
/// currencies (`docs/architecture.md` ADR-002: "cross-currency arithmetic is
/// possible only through `MoneyConverter.convert`, which requires an
/// explicit rate carrying a rate value, a rate date, and a source").
///
/// This is a class with only static members and a private constructor —
/// idiomatic Dart for "a namespace of related functions that should never be
/// instantiated." (An alternative some Dart code uses is a top-level
/// function; a class reads slightly better here because a second helper may
/// join it later, e.g. batch conversion.)
class MoneyConverter {
  const MoneyConverter._();

  /// Converts [money] into `rate.toCurrency`, rounding **HALF_UP** to
  /// [targetExponent] fractional digits — the rounding mode ADR-002
  /// mandates for conversion results. [money]'s own stored value is never
  /// mutated or rounded; only the *result* of this conversion is rounded.
  ///
  /// Throws [ArgumentError] if `money.currencyCode` does not match
  /// `rate.fromCurrency` — converting through the wrong rate is exactly the
  /// kind of silent error ADR-002/NFR-A5 exist to prevent.
  static Money convert(
    Money money, {
    required ExchangeRate rate,
    int targetExponent = 2,
  }) {
    if (money.currencyCode != rate.fromCurrency) {
      throw ArgumentError(
        'ExchangeRate.fromCurrency (${rate.fromCurrency}) does not match '
        "Money's currency (${money.currencyCode}) — refusing to convert "
        'through a mismatched rate.',
      );
    }
    final Decimal converted = money.amount * rate.rate;
    final Decimal rounded = _roundHalfUp(converted, targetExponent);
    return Money.parse(rounded.toString(), currency: rate.toCurrency);
  }

  /// Rounds [value] to [exponent] fractional digits using HALF_UP
  /// (round-half-away-from-zero), implemented explicitly over [BigInt]
  /// rather than relying on `Decimal.round()`'s "round half to even for
  /// ties" default behaviour, since ADR-002 specifically mandates HALF_UP
  /// for FX conversion results.
  static Decimal _roundHalfUp(Decimal value, int exponent) {
    // Shift the decimal point right by `exponent` places so the digit we
    // need to round on becomes the ones place, then look at what's left
    // over below that.
    final Decimal shifted = value.shift(exponent);
    final BigInt truncated = shifted.toBigInt();
    final Decimal remainder = (shifted - Decimal.fromBigInt(truncated)).abs();
    final bool roundAwayFromZero = remainder >= Decimal.parse('0.5');

    BigInt roundedUnscaled = truncated;
    if (roundAwayFromZero) {
      roundedUnscaled += shifted.sign < 0 ? -BigInt.one : BigInt.one;
    }

    // Shift back left to restore the original scale.
    return Decimal.fromBigInt(roundedUnscaled).shift(-exponent);
  }
}

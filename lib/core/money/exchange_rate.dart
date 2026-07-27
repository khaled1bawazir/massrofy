import 'package:decimal/decimal.dart';

/// Where an [ExchangeRate] came from — carried on every converted amount so
/// a user can always answer "why is this number what it is" (AC-B9.3),
/// per `docs/architecture.md` ADR-009.
enum ExchangeRateSource {
  /// The SMS gave both the foreign amount and the converted base amount;
  /// the rate is *derived* (`base / foreign`), never invented.
  smsImplied,

  /// The SMS stated the rate explicitly.
  smsStated,

  /// The user entered a rate manually (ADR-009: never invented by the app).
  user,

  /// The most recent known rate for the pair, carried forward and visibly
  /// marked as such (ADR-009) — used only when nothing better exists.
  carriedForward,
}

/// A recorded, traceable currency conversion rate.
///
/// Every field exists so a converted amount is always traceable back to
/// *why* it has the value it does — never an invisible, invented number
/// (ADR-009: "prefer what the SMS states; never invent a rate").
class ExchangeRate {
  /// ISO 4217 code of the currency being converted from.
  final String fromCurrency;

  /// ISO 4217 code of the currency being converted to.
  final String toCurrency;

  /// Units of [toCurrency] per 1 unit of [fromCurrency].
  final Decimal rate;

  /// The date this rate applies to (not necessarily "today" — see
  /// [ExchangeRateSource.carriedForward]).
  final DateTime rateDate;

  final ExchangeRateSource source;

  const ExchangeRate({
    required this.fromCurrency,
    required this.toCurrency,
    required this.rate,
    required this.rateDate,
    required this.source,
  });
}

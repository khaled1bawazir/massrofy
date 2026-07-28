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
  ///
  /// **Nullable, and `required` at the same time — that combination is
  /// deliberate (KHA-70, AC-B9.3).** A rate whose date the message never
  /// stated is a real and common case, and the two alternatives are both
  /// worse:
  ///
  ///  - defaulting it to "today" fabricates a fact the user would then see
  ///    rendered as authoritative, which is the exact failure KHA-70 was
  ///    raised for;
  ///  - refusing to build the rate at all would throw away a rate the bank
  ///    genuinely printed.
  ///
  /// So the date may be `null`, meaning *"the source did not date this
  /// rate"*, and every display of a rate must then say so in words — see
  /// `AppLocalizations.txnFxRateDateUnknown`. Keeping the parameter
  /// `required` forces each construction site to make that call consciously
  /// rather than inheriting a default.
  final DateTime? rateDate;

  final ExchangeRateSource source;

  const ExchangeRate({
    required this.fromCurrency,
    required this.toCurrency,
    required this.rate,
    required this.rateDate,
    required this.source,
  });
}

/// ISO 4217 minor-unit exponent lookup.
///
/// `docs/architecture.md` ADR-002 says it plainly: *"the exponent varies by
/// currency (SAR 2, KWD/BHD/JOD 3, JPY 0)"* — so any code deriving a
/// minor-units integer from a [Money] amount (the non-authoritative
/// `_minor INTEGER` column ADR-002 defines purely for indexing/range
/// filters) must look the exponent up per-currency, never assume `2`
/// unconditionally. This file is the single shared lookup so that
/// assumption only has to be correct in one place.
///
/// Only currencies whose exponent differs from the overwhelmingly common
/// default of 2 need an entry below — [minorUnitExponentFor] falls back to
/// `2` for every ISO 4217 code not listed here, which is correct for the
/// large majority of currencies (including SAR, the app's default/base
/// currency per ADR-009) without needing an exhaustive 180-entry table.
const Map<String, int> _nonDefaultMinorUnitExponents = <String, int>{
  // Zero-decimal currencies — ISO 4217 defines no minor unit at all for
  // these; a "cents" column would be meaningless.
  'BIF': 0, // Burundian franc
  'CLP': 0, // Chilean peso
  'DJF': 0, // Djiboutian franc
  'GNF': 0, // Guinean franc
  'ISK': 0, // Icelandic krona
  'JPY': 0, // Japanese yen — ADR-002's own example
  'KMF': 0, // Comorian franc
  'KRW': 0, // South Korean won
  'PYG': 0, // Paraguayan guarani
  'RWF': 0, // Rwandan franc
  'UGX': 0, // Ugandan shilling
  'UYI': 0, // Uruguay peso en unidades indexadas
  'VND': 0, // Vietnamese dong
  'VUV': 0, // Vanuatu vatu
  'XAF': 0, // Central African CFA franc
  'XOF': 0, // West African CFA franc
  'XPF': 0, // CFP franc
  // Three-decimal currencies — several are neighbouring-GCC/Arab currencies
  // this app's Saudi-market SMS may plausibly encounter (foreign-currency
  // transactions, ADR-009), so these matter in practice, not just for
  // completeness.
  'BHD': 3, // Bahraini dinar
  'IQD': 3, // Iraqi dinar
  'JOD': 3, // Jordanian dinar — ADR-002's own example
  'KWD': 3, // Kuwaiti dinar — ADR-002's own example
  'LYD': 3, // Libyan dinar
  'OMR': 3, // Omani rial
  'TND': 3, // Tunisian dinar
  // Four-decimal currency — the one ISO 4217 outlier beyond 0/2/3.
  'CLF': 4, // Unidad de Fomento (Chile)
};

/// Returns the ISO 4217 minor-unit exponent for [currencyCode] (e.g. `2`
/// for `SAR`/`USD`, `3` for `KWD`, `0` for `JPY`) — case-insensitive, so
/// callers can pass a currency code however it happens to be cased.
///
/// Falls back to `2` for any code not in the (deliberately small,
/// exceptions-only) table above.
int minorUnitExponentFor(String currencyCode) =>
    _nonDefaultMinorUnitExponents[currencyCode.toUpperCase()] ?? 2;

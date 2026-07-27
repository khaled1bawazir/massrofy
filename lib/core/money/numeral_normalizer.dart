/// Normalises the numeral and separator conventions that a bank SMS — or a
/// user typing on an Arabic-locale keyboard — may use, into the plain ASCII
/// decimal form `Decimal.parse` understands.
///
/// If you are new to Dart: this file has no classes, only top-level
/// functions and `const` data — that's fine and idiomatic for a small, pure,
/// stateless utility like this one. Being pure (no side effects, same input
/// always gives the same output) is exactly what makes it trivial to unit
/// test and safe to call from anywhere: the parser (ADR-007), manual-entry
/// forms, and `Money.parse` itself all share this one implementation so the
/// normalisation rule can never drift between call sites.
library;

/// Arabic-Indic digits ٠-٩ (U+0660-0669) and Extended Arabic-Indic digits
/// ۰-۹ (U+06F0-06F9) mapped to their ASCII '0'-'9' equivalents.
///
/// Per `docs/architecture.md` ADR-002: "map Arabic-Indic digits ٠-٩
/// (U+0660–0669) and Extended Arabic-Indic ۰-۹ (U+06F0–06F9) to ASCII."
const Map<int, String> _digitMap = <int, String>{
  0x0660: '0',
  0x0661: '1',
  0x0662: '2',
  0x0663: '3',
  0x0664: '4',
  0x0665: '5',
  0x0666: '6',
  0x0667: '7',
  0x0668: '8',
  0x0669: '9',
  0x06F0: '0',
  0x06F1: '1',
  0x06F2: '2',
  0x06F3: '3',
  0x06F4: '4',
  0x06F5: '5',
  0x06F6: '6',
  0x06F7: '7',
  0x06F8: '8',
  0x06F9: '9',
};

/// Arabic decimal separator ٫ (U+066B) — becomes the ASCII '.'.
const int _arabicDecimalSeparator = 0x066B;

/// Arabic thousands separator ٬ (U+066C) — stripped, along with the ASCII
/// thousands separator ',', per ADR-002.
const int _arabicThousandsSeparator = 0x066C;
const int _asciiComma = 0x002C; // ','

/// Bidi control characters (LRM, RLM, ALM) that must never survive into a
/// numeral string headed for `Decimal.parse` — ADR-002 names these three
/// explicitly (U+200E, U+200F, U+061C).
const List<int> _bidiControls = <int>[0x200E, 0x200F, 0x061C];

/// Returns [input] with:
///  - Arabic-Indic / Extended Arabic-Indic digits mapped to ASCII 0-9,
///  - the Arabic decimal separator mapped to '.',
///  - Arabic and ASCII thousands separators stripped,
///  - bidi control characters stripped,
///  - surrounding whitespace trimmed.
///
/// This does **not** validate that the result is a well-formed number —
/// that is `Decimal.parse`'s job (see `money.dart`). This function only
/// normalises *representation*, never rounds or otherwise changes value.
String normalizeNumerals(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (_bidiControls.contains(rune)) {
      continue; // strip silently — never part of a numeral's value
    }
    if (rune == _arabicThousandsSeparator || rune == _asciiComma) {
      continue; // thousands separators carry no value; strip both forms
    }
    if (rune == _arabicDecimalSeparator) {
      buffer.write('.');
      continue;
    }
    final mappedDigit = _digitMap[rune];
    if (mappedDigit != null) {
      buffer.write(mappedDigit);
      continue;
    }
    buffer.writeCharCode(rune);
  }
  return buffer.toString().trim();
}

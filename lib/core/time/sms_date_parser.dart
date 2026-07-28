/// Parses the small, fixed set of date/time layouts that bank SMS actually
/// print, from a rule pack's declarative `format` string.
///
/// ## Why this is hand-written instead of `package:intl`'s `DateFormat`
///
/// Three reasons, in order of weight:
///
/// 1. **Two-digit years.** A bank SMS routinely prints `dd/MM/yy`. `DateFormat`
///    resolves `yy` through a locale-dependent pivot the caller does not
///    control. For a ledger, "which century is 26?" must be an explicit,
///    reviewable decision in our own code, not an implementation detail of a
///    formatting library. See [_resolveTwoDigitYear].
/// 2. **Strictness.** We need "did not parse" to be a *value* the pipeline can
///    route to the review queue (NFR-A7), not an exception thrown from deep
///    inside a third-party parser on a background isolate.
/// 3. **Rule packs are untrusted-ish.** ADR-007 allows the user to import a
///    rule pack. Feeding an arbitrary imported `format` string into a
///    full-featured formatter widens the attack surface for no gain; this
///    parser understands exactly seven tokens and treats everything else as a
///    literal.
///
/// ## Supported tokens
///
/// | Token  | Meaning                    |
/// |--------|----------------------------|
/// | `yyyy` | four-digit year            |
/// | `yy`   | two-digit year (see below) |
/// | `MM`   | zero-padded month, 01-12   |
/// | `dd`   | zero-padded day, 01-31     |
/// | `HH`   | zero-padded hour, 00-23    |
/// | `mm`   | zero-padded minute, 00-59  |
/// | `ss`   | zero-padded second, 00-59  |
///
/// Any other character in the pattern must appear literally in the input.
/// Deliberately absent: month *names*, 12-hour clocks with AM/PM, and
/// single-character (non-padded) tokens. If a real bank turns out to use one,
/// add it here **with a fixture**, rather than reaching for a general-purpose
/// formatter — the closed token set is the point.
library;

/// The result of parsing an SMS date field.
///
/// A sealed hierarchy rather than a nullable `DateTime` so the *reason* for a
/// failure survives to the review queue, where the user is shown why a
/// message could not be understood.
sealed class SmsDateParseResult {
  const SmsDateParseResult();
}

/// A wall-clock reading successfully extracted from the message. It carries
/// **no** timezone: the SMS did not state one, and inventing one here would
/// hide the assumption. `RiyadhCalendar.riyadhLocalToUtc` applies the
/// documented `Asia/Riyadh` assumption at the call site, where the
/// `timeSource` marker is recorded alongside it (architecture §7.4).
final class SmsDateParsed extends SmsDateParseResult {
  final DateTime localWallClock;
  const SmsDateParsed(this.localWallClock);
}

/// The value did not match the pattern, or matched but was not a real date
/// (31 February, hour 25, ...).
final class SmsDateUnparsed extends SmsDateParseResult {
  final String reason;
  const SmsDateUnparsed(this.reason);
}

abstract final class SmsDateParser {
  /// Two-digit years are resolved into the window
  /// `[_twoDigitYearBase, _twoDigitYearBase + 99]`.
  ///
  /// Set to 2000 rather than a sliding pivot: a bank transaction SMS is, by
  /// construction, about a recent event, and this app's entire data horizon
  /// is the 21st century. A sliding window would make the same fixture parse
  /// differently depending on the year the test is run — an unacceptable
  /// property for a regression corpus (NFR-M2).
  static const int _twoDigitYearBase = 2000;

  /// Longest-token-first, so `yyyy` is never mis-read as `yy` + literal `yy`.
  static const List<String> _tokens = <String>[
    'yyyy',
    'yy',
    'MM',
    'dd',
    'HH',
    'mm',
    'ss',
  ];

  /// Parses [value] against [pattern]. Never throws.
  static SmsDateParseResult parse(String value, String pattern) {
    // Field accumulators. `-1` means "not present in the pattern", which is
    // distinct from "present and zero" — an important distinction for hour,
    // where 0 is a legitimate value.
    int year = -1;
    int month = -1;
    int day = -1;
    int hour = 0;
    int minute = 0;
    int second = 0;

    int valueIndex = 0;
    int patternIndex = 0;

    while (patternIndex < pattern.length) {
      final String? token = _tokenAt(pattern, patternIndex);

      if (token == null) {
        // Literal character: it must match the input exactly.
        if (valueIndex >= value.length ||
            value[valueIndex] != pattern[patternIndex]) {
          return SmsDateUnparsed(
            'literal mismatch at pattern offset $patternIndex',
          );
        }
        patternIndex += 1;
        valueIndex += 1;
        continue;
      }

      final int width = token.length;
      if (valueIndex + width > value.length) {
        return SmsDateUnparsed('value ended inside token "$token"');
      }
      final String digits = value.substring(valueIndex, valueIndex + width);
      final int? parsed = int.tryParse(digits);
      if (parsed == null) {
        return SmsDateUnparsed('token "$token" got non-numeric "$digits"');
      }

      switch (token) {
        case 'yyyy':
          year = parsed;
        case 'yy':
          year = _resolveTwoDigitYear(parsed);
        case 'MM':
          month = parsed;
        case 'dd':
          day = parsed;
        case 'HH':
          hour = parsed;
        case 'mm':
          minute = parsed;
        case 'ss':
          second = parsed;
      }

      patternIndex += width;
      valueIndex += width;
    }

    if (valueIndex != value.length) {
      return const SmsDateUnparsed('trailing characters after pattern');
    }
    if (year < 0 || month < 0 || day < 0) {
      return const SmsDateUnparsed('pattern omits year, month, or day');
    }

    // Range checks before constructing, because Dart's DateTime constructor
    // silently *rolls over* out-of-range components — DateTime(2026, 2, 31)
    // quietly becomes 3 March. For a ledger, a date that quietly becomes a
    // different date is worse than no date at all, so we reject instead.
    if (month < 1 || month > 12) return SmsDateUnparsed('month $month');
    if (day < 1 || day > 31) return SmsDateUnparsed('day $day');
    if (hour > 23) return SmsDateUnparsed('hour $hour');
    if (minute > 59) return SmsDateUnparsed('minute $minute');
    if (second > 59) return SmsDateUnparsed('second $second');

    final DateTime candidate = DateTime(year, month, day, hour, minute, second);
    if (candidate.month != month || candidate.day != day) {
      return SmsDateUnparsed('$year-$month-$day is not a real date');
    }

    return SmsDateParsed(candidate);
  }

  /// Returns the token starting at [index], or `null` if a literal starts
  /// there.
  static String? _tokenAt(String pattern, int index) {
    for (final String token in _tokens) {
      if (pattern.startsWith(token, index)) {
        return token;
      }
    }
    return null;
  }

  static int _resolveTwoDigitYear(int twoDigits) =>
      _twoDigitYearBase + twoDigits;
}

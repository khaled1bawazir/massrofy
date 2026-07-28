/// A single, injectable source of "now", plus the `Asia/Riyadh` period
/// arithmetic the product's calendar-month rules depend on.
///
/// ## Why the app never calls `DateTime.now()` directly
///
/// `docs/architecture.md` §7.4 requires a "single `Clock` abstraction in
/// `core/time/` so tests can freeze it". That is not test convenience for its
/// own sake — several of this product's rules are *defined* against wall-clock
/// boundaries:
///
///  - AC-A3.1: the historical import starts at "the start of the current
///    calendar month".
///  - AC-E1.4 / OQ-12: "calendar month" is computed in **Asia/Riyadh**, not
///    UTC, so a purchase at 23:30 on the 31st does not silently fall into the
///    next month.
///
/// A test that cannot pin "now" cannot assert either of those without being
/// flaky on the last day of a month, which is exactly when they matter most.
///
/// ## The Asia/Riyadh simplification, stated honestly
///
/// The architecture names `package:timezone`. This file instead hard-codes a
/// **fixed +03:00 offset** and no daylight-saving transitions. That is not a
/// shortcut around a hard problem — it is the correct model for this one
/// zone: Saudi Arabia has observed UTC+03:00 continuously since 1947 and has
/// never operated DST. Hard-coding it avoids shipping and initialising an
/// IANA database inside a background ingestion isolate that has a
/// ~10-second budget (ADR-006), for zero behavioural difference.
///
/// **If this app is ever localised to a zone with DST, this file must be
/// replaced with `package:timezone` rather than extended.** The constant
/// below is deliberately named so that assumption is greppable.
library;

/// The fixed UTC offset of Asia/Riyadh. See the library doc comment above
/// for why a constant is correct here and where it stops being correct.
const Duration riyadhUtcOffset = Duration(hours: 3);

/// Wraps the ambient notion of "now" so it can be replaced in tests.
///
/// For readers new to Dart: `abstract interface class` declares a pure
/// contract — it has no fields and no implementation, and other classes
/// `implements` it. That is the Dart 3 way of saying "this exists to be
/// substituted", and it is what lets a widget or unit test pass a
/// [FixedClock] wherever production passes a [SystemClock].
abstract interface class Clock {
  /// The current instant, in UTC. Always UTC — a `DateTime` carrying a local
  /// offset that varies by the machine running the test is a bug generator.
  DateTime nowUtc();
}

/// The production implementation: the device clock.
final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// A clock frozen at a chosen instant, for tests.
final class FixedClock implements Clock {
  final DateTime _instantUtc;

  FixedClock(DateTime instant) : _instantUtc = instant.toUtc();

  @override
  DateTime nowUtc() => _instantUtc;
}

/// Calendar arithmetic in `Asia/Riyadh`, expressed as UTC instants.
///
/// Every method here takes and returns **UTC** `DateTime`s, because that is
/// what the database stores (architecture §7.4: "store UTC instants plus the
/// original offset"). The Riyadh-ness lives entirely inside the arithmetic,
/// never in the stored value — mixing local `DateTime`s into persistence is
/// how period totals start disagreeing with the transactions they summarise.
abstract final class RiyadhCalendar {
  /// The UTC instant at which the current calendar month began in Riyadh.
  ///
  /// This is the lower bound of the historical import (AC-A3.1). Worked
  /// example: at 2026-07-01T00:30 UTC it is already 03:30 on 1 July in
  /// Riyadh, so the month began at 2026-06-30T21:00Z — *before* the current
  /// UTC instant's own UTC month boundary. Getting this backwards would drop
  /// the first three hours of every month's SMS on the floor.
  static DateTime startOfCurrentMonthUtc(DateTime nowUtc) {
    final DateTime riyadhNow = nowUtc.add(riyadhUtcOffset);
    final DateTime riyadhMonthStart = DateTime.utc(
      riyadhNow.year,
      riyadhNow.month,
    );
    return riyadhMonthStart.subtract(riyadhUtcOffset);
  }

  /// Interprets [local] — a wall-clock reading with no offset, which is what
  /// most bank SMS print — as a Riyadh local time, and returns the
  /// corresponding UTC instant.
  ///
  /// Callers must record `timeSource = sms_local_assumed` alongside the
  /// result (architecture §7.4), so a later "that timestamp looks odd" is
  /// explainable rather than mysterious.
  static DateTime riyadhLocalToUtc(DateTime local) {
    return DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
    ).subtract(riyadhUtcOffset);
  }
}

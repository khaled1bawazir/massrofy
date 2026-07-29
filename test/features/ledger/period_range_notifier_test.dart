/// **AC-E1.4 — "periods are calendar months; on the 1st the total resets and
/// the prior month remains viewable"** (KHA-35, OQ-12).
///
/// Two halves that pull against each other, which is why they get their own
/// test file: the rollover must happen *by itself*, and it must **not** happen
/// to a user who has deliberately paged back to look at an older month.
///
/// The clock is injected everywhere (`now:`) rather than mocked globally, so
/// "the month boundary passes" is a parameter rather than a wall-clock wait —
/// KHA-35's done-check asks for month-boundary behaviour "verified by clock
/// manipulation", and this is the cheapest honest form of that.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:massrofy/core/time/clock.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/presentation/providers/ledger_providers.dart';

void main() {
  group('RiyadhCalendar.monthWindowUtc — where a month starts (OQ-12)', () {
    test('a month begins at Riyadh midnight, which is 21:00 UTC the day '
        'before', () {
      final (DateTime start, DateTime end) = RiyadhCalendar.monthWindowUtc(
        DateTime.utc(2026, 7, 15, 12),
      );

      // 2026-07-01T00:00 in Riyadh (+03:00) is 2026-06-30T21:00Z. Using the
      // UTC month boundary instead would file every transaction between
      // midnight and 03:00 on the 1st under the previous month — the
      // limitation P3a documented here and P5a closes.
      expect(start, DateTime.utc(2026, 6, 30, 21));
      expect(end, DateTime.utc(2026, 7, 31, 21));
    });

    test('at 01:00 Riyadh on the 1st — 22:00 UTC on the last day of the '
        'previous month — the window is already the NEW month', () {
      final (DateTime start, DateTime end) = RiyadhCalendar.monthWindowUtc(
        DateTime.utc(2026, 6, 30, 22),
      );
      expect(start, DateTime.utc(2026, 6, 30, 21));
      expect(end, DateTime.utc(2026, 7, 31, 21));
    });

    test('December rolls into January of the next year, and January back into '
        'the previous December', () {
      final (
        DateTime decStart,
        DateTime decEnd,
      ) = RiyadhCalendar.monthWindowUtc(
        DateTime.utc(2026, 12, 10),
        monthOffset: 0,
      );
      expect(decStart, DateTime.utc(2026, 11, 30, 21));
      expect(decEnd, DateTime.utc(2026, 12, 31, 21));

      final (DateTime janStart, _) = RiyadhCalendar.monthWindowUtc(
        DateTime.utc(2026, 12, 10),
        monthOffset: 1,
      );
      expect(janStart, DateTime.utc(2026, 12, 31, 21));

      final (DateTime backStart, _) = RiyadhCalendar.monthWindowUtc(
        DateTime.utc(2027, 1, 10),
        monthOffset: -1,
      );
      expect(backStart, DateTime.utc(2026, 11, 30, 21));
    });

    test('the window is half-open, so a transaction at the boundary instant '
        'belongs to exactly one month', () {
      final (DateTime julyStart, DateTime julyEnd) =
          RiyadhCalendar.monthWindowUtc(DateTime.utc(2026, 7, 15));
      final PeriodRange july = PeriodRange(
        startUtc: julyStart,
        endUtcExclusive: julyEnd,
      );
      final (DateTime augStart, DateTime augEnd) =
          RiyadhCalendar.monthWindowUtc(DateTime.utc(2026, 8, 15));
      final PeriodRange august = PeriodRange(
        startUtc: augStart,
        endUtcExclusive: augEnd,
      );

      expect(july.contains(julyEnd), isFalse);
      expect(august.contains(julyEnd), isTrue);
      expect(july.endUtcExclusive, august.startUtc);
    });
  });

  group('PeriodRangeNotifier — AC-E1.4', () {
    late ProviderContainer container;
    late PeriodRangeNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
      notifier = container.read(ledgerPeriodProvider.notifier);
    });

    test('starts on the current calendar month and says so', () {
      expect(notifier.isCurrentMonth, isTrue);
      expect(
        container.read(ledgerPeriodProvider).startUtc,
        PeriodRangeNotifier.currentCalendarMonth().startUtc,
      );
    });

    test('paging back one month pins the period and stops calling it the '
        'current month', () {
      final DateTime before = container.read(ledgerPeriodProvider).startUtc;
      notifier.shiftMonths(-1);

      expect(notifier.isCurrentMonth, isFalse);
      expect(
        container.read(ledgerPeriodProvider).endUtcExclusive,
        before,
        reason:
            'the previous month must end exactly where the current one '
            'begins, or a transaction falls into a gap between them',
      );
    });

    test('paging forward back onto the live month re-arms the rollover', () {
      notifier.shiftMonths(-1);
      expect(notifier.isCurrentMonth, isFalse);
      notifier.shiftMonths(1);
      expect(notifier.isCurrentMonth, isTrue);
    });

    test('**the rollover**: on the 1st, a resume moves the period to the new '
        'month', () {
      // The notifier was built with "now". Simulate the app having been open
      // across a month boundary by resuming with a clock a month later.
      final PeriodRange before = container.read(ledgerPeriodProvider);
      final DateTime nextMonth = RiyadhCalendar.toRiyadhWallClock(
        before.endUtcExclusive,
      ).add(const Duration(days: 2));

      notifier.refreshIfTrackingCurrentMonth(now: nextMonth);

      final PeriodRange after = container.read(ledgerPeriodProvider);
      expect(after.startUtc, before.endUtcExclusive);
      expect(after.startUtc.isAfter(before.startUtc), isTrue);
    });

    test('**the other half**: a user who paged back to an older month is NOT '
        'dragged forward by a resume', () {
      notifier.shiftMonths(-1);
      final PeriodRange chosen = container.read(ledgerPeriodProvider);

      notifier.refreshIfTrackingCurrentMonth(
        now: DateTime.now().add(const Duration(days: 90)),
      );

      expect(
        container.read(ledgerPeriodProvider).startUtc,
        chosen.startUtc,
        reason:
            'AC-E1.4 requires the prior month to remain viewable; a resume '
            'that silently jumped the user back to "now" would take away the '
            'thing they navigated to look at',
      );
    });

    test('a resume within the same month changes nothing', () {
      final PeriodRange before = container.read(ledgerPeriodProvider);
      notifier.refreshIfTrackingCurrentMonth(now: DateTime.now());
      expect(container.read(ledgerPeriodProvider).startUtc, before.startUtc);
    });

    test('showCurrentMonth jumps back and re-arms the rollover', () {
      notifier.shiftMonths(-3);
      expect(notifier.isCurrentMonth, isFalse);

      notifier.showCurrentMonth();

      expect(notifier.isCurrentMonth, isTrue);
      expect(
        container.read(ledgerPeriodProvider).startUtc,
        PeriodRangeNotifier.currentCalendarMonth().startUtc,
      );
    });

    test('setRange pins an arbitrary window and stops the rollover', () {
      notifier.setRange(
        PeriodRange(
          startUtc: DateTime.utc(2026, 3),
          endUtcExclusive: DateTime.utc(2026, 4),
        ),
      );
      expect(notifier.isCurrentMonth, isFalse);
      notifier.refreshIfTrackingCurrentMonth(
        now: DateTime.now().add(const Duration(days: 400)),
      );
      expect(
        container.read(ledgerPeriodProvider).startUtc,
        DateTime.utc(2026, 3),
      );
    });

    test('shifting repeatedly from a boundary-start period does not drift', () {
      // `shiftMonths` works from `state.startUtc`, which is 21:00 on the last
      // day of the previous month. Shifting from that instant naively would be
      // off by one; the notifier adds a day first. Twelve hops there and twelve
      // back must land exactly where they started.
      final PeriodRange start = container.read(ledgerPeriodProvider);
      for (int i = 0; i < 12; i++) {
        notifier.shiftMonths(-1);
      }
      for (int i = 0; i < 12; i++) {
        notifier.shiftMonths(1);
      }
      expect(container.read(ledgerPeriodProvider).startUtc, start.startUtc);
      expect(notifier.isCurrentMonth, isTrue);
    });
  });
}

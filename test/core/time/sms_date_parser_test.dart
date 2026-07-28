import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/time/clock.dart';
import 'package:massrofy/core/time/sms_date_parser.dart';

void main() {
  DateTime parsed(String value, String pattern) {
    final SmsDateParseResult result = SmsDateParser.parse(value, pattern);
    expect(result, isA<SmsDateParsed>(), reason: 'expected "$value" to parse');
    return (result as SmsDateParsed).localWallClock;
  }

  void expectUnparsed(String value, String pattern) {
    expect(
      SmsDateParser.parse(value, pattern),
      isA<SmsDateUnparsed>(),
      reason: '"$value" must NOT parse against "$pattern"',
    );
  }

  group('the two layouts the bundled rule pack uses', () {
    test('dd-MM-yy HH:mm (Bank Aljazira)', () {
      expect(
        parsed('28-07-26 14:32', 'dd-MM-yy HH:mm'),
        DateTime(2026, 7, 28, 14, 32),
      );
    });

    test('dd/MM/yyyy HH:mm (D360)', () {
      expect(
        parsed('28/07/2026 15:10', 'dd/MM/yyyy HH:mm'),
        DateTime(2026, 7, 28, 15, 10),
      );
    });
  });

  group('two-digit years resolve deterministically', () {
    test('26 means 2026, and the rule does not depend on today', () {
      // A sliding pivot would make the SAME fixture parse differently
      // depending on the year the suite runs — an unacceptable property for
      // a regression corpus (NFR-M2).
      expect(parsed('01-01-26 00:00', 'dd-MM-yy HH:mm').year, 2026);
      expect(parsed('01-01-99 00:00', 'dd-MM-yy HH:mm').year, 2099);
      expect(parsed('01-01-00 00:00', 'dd-MM-yy HH:mm').year, 2000);
    });
  });

  group('an impossible date is REJECTED, never silently rolled over', () {
    test('31 February does not become 3 March', () {
      // Dart's own `DateTime(2026, 2, 31)` quietly returns 3 March. For a
      // ledger, a date that quietly becomes a different date is worse than
      // no date at all — the transaction lands in the wrong month and every
      // total is wrong with no visible cause.
      expect(DateTime(2026, 2, 31).month, 3); // the behaviour we guard against
      expectUnparsed('31-02-26 10:00', 'dd-MM-yy HH:mm');
    });

    test('month 13, day 00, hour 25, minute 61 are all rejected', () {
      expectUnparsed('01-13-26 10:00', 'dd-MM-yy HH:mm');
      expectUnparsed('00-01-26 10:00', 'dd-MM-yy HH:mm');
      expectUnparsed('01-01-26 25:00', 'dd-MM-yy HH:mm');
      expectUnparsed('01-01-26 10:61', 'dd-MM-yy HH:mm');
    });

    test('29 February in a leap year IS accepted', () {
      expect(parsed('29-02-28 10:00', 'dd-MM-yy HH:mm').day, 29);
    });
  });

  group('malformed input is a value, not an exception', () {
    // NFR-R5: a parse failure must route the message to the review queue, not
    // throw out of a background isolate and end the whole batch.
    test(
      'a literal mismatch',
      () => expectUnparsed('28/07/26 14:32', 'dd-MM-yy HH:mm'),
    );
    test('too short', () => expectUnparsed('28-07', 'dd-MM-yy HH:mm'));
    test(
      'trailing junk',
      () => expectUnparsed('28-07-26 14:32Z', 'dd-MM-yy HH:mm'),
    );
    test(
      'non-numeric in a token',
      () => expectUnparsed('AB-07-26 14:32', 'dd-MM-yy HH:mm'),
    );
    test('a pattern with no date part', () => expectUnparsed('14:32', 'HH:mm'));

    test('every failure carries a reason', () {
      final SmsDateParseResult result = SmsDateParser.parse(
        '31-02-26 10:00',
        'dd-MM-yy HH:mm',
      );
      expect((result as SmsDateUnparsed).reason, isNotEmpty);
    });
  });

  group('yyyy is never mis-read as yy plus a literal', () {
    test('longest-token-first matching', () {
      expect(parsed('2026-07-28 00:00', 'yyyy-MM-dd HH:mm').year, 2026);
    });
  });

  group('Asia/Riyadh interpretation (architecture §7.4)', () {
    test('a bank wall-clock reading becomes a UTC instant three hours '
        'earlier', () {
      // The SMS says 14:32 with no offset. Bank SMS in Saudi Arabia are local
      // time, so the app interprets them as Asia/Riyadh (+03:00) and records
      // `timeSource = sms_local_assumed` alongside, so an odd-looking
      // timestamp is explainable later rather than mysterious.
      final DateTime wallClock = parsed('28-07-26 14:32', 'dd-MM-yy HH:mm');
      expect(
        RiyadhCalendar.riyadhLocalToUtc(wallClock),
        DateTime.utc(2026, 7, 28, 11, 32),
      );
    });

    test('the offset is fixed — Saudi Arabia has never observed DST', () {
      // Mid-winter and mid-summer must produce the same offset. If this ever
      // fails, `core/time/clock.dart` must be replaced with
      // `package:timezone` rather than patched.
      for (final int month in <int>[1, 7]) {
        expect(
          RiyadhCalendar.riyadhLocalToUtc(
            DateTime(2026, month, 15, 12),
          ).difference(DateTime.utc(2026, month, 15, 12)),
          const Duration(hours: -3),
        );
      }
    });
  });
}

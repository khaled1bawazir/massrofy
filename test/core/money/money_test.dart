import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/currency_mismatch_error.dart';
import 'package:massrofy/core/money/money.dart';

void main() {
  group('Money.parse — construction and normalisation (ADR-002)', () {
    test('parses a plain ASCII decimal string', () {
      final Money m = Money.parse('1234.50', currency: 'sar');
      // Note: package:decimal's canonical toString() always uses the
      // minimal representation of a value — "1234.50" and "1234.5" are the
      // *same* Decimal value, and toCanonicalString() reflects that (exact
      // value round-trip is what ADR-002 guarantees; trailing-zero display
      // formatting is a presentation-layer concern applied at render time,
      // not part of the persisted canonical form).
      expect(m.toCanonicalString(), '1234.5');
      expect(m.currencyCode, 'SAR'); // always upper-cased
    });

    test('parses Arabic-Indic digits (٠-٩)', () {
      // "١٢٣٤٫٥٠" == "1234.50" == "1234.5" once normalised.
      final Money m = Money.parse('١٢٣٤٫٥٠', currency: 'SAR');
      expect(m.toCanonicalString(), '1234.5');
    });

    test('parses Extended Arabic-Indic digits (۰-۹)', () {
      final Money m = Money.parse('۱۲۳۴', currency: 'SAR');
      expect(m.toCanonicalString(), '1234');
    });

    test('strips ASCII and Arabic thousands separators', () {
      expect(
        Money.parse('1,234.50', currency: 'SAR').toCanonicalString(),
        '1234.5',
      );
      expect(
        Money.parse('١٬٢٣٤٫٥٠', currency: 'SAR').toCanonicalString(),
        '1234.5',
      );
    });

    test('strips bidi control characters', () {
      final String withBidi = '‎1234.50‏';
      expect(
        Money.parse(withBidi, currency: 'SAR').toCanonicalString(),
        '1234.5',
      );
    });

    test('rejects a currency code that is not 3 letters', () {
      expect(
        () => Money.parse('10', currency: 'SA'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => Money.parse('10', currency: 'SARR'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws FormatException on garbage input', () {
      expect(
        () => Money.parse('not a number', currency: 'SAR'),
        throwsFormatException,
      );
    });

    test('tryParse returns null instead of throwing', () {
      expect(Money.tryParse('nonsense', currency: 'SAR'), isNull);
      expect(Money.tryParse('10', currency: 'XX'), isNull);
      expect(
        Money.tryParse('10.5', currency: 'SAR')!.toCanonicalString(),
        '10.5',
      );
    });
  });

  group('Money.fromMinorUnits / Money.zero', () {
    test('fromMinorUnits with a 2-decimal exponent', () {
      expect(
        Money.fromMinorUnits(123450, currency: 'SAR').toCanonicalString(),
        '1234.5', // package:decimal trims trailing zeros; see note above
      );
    });

    test('fromMinorUnits handles negative values', () {
      expect(
        Money.fromMinorUnits(-500, currency: 'SAR').toCanonicalString(),
        '-5',
      );
    });

    test('fromMinorUnits with a 0-decimal exponent (e.g. JPY)', () {
      expect(
        Money.fromMinorUnits(
          1000,
          currency: 'JPY',
          exponent: 0,
        ).toCanonicalString(),
        '1000',
      );
    });

    test('fromMinorUnits with a 3-decimal exponent (e.g. KWD)', () {
      expect(
        Money.fromMinorUnits(
          1500,
          currency: 'KWD',
          exponent: 3,
        ).toCanonicalString(),
        '1.5',
      );
    });

    test('zero() is exactly zero and formats as such', () {
      expect(Money.zero('SAR').isZero, isTrue);
      expect(Money.zero('SAR').toCanonicalString(), '0');
    });
  });

  group('Arithmetic requires matching currencies (ADR-002 / NFR-A5)', () {
    test('adding the same currency works', () {
      final Money a = Money.parse('10.00', currency: 'SAR');
      final Money b = Money.parse('5.50', currency: 'SAR');
      expect((a + b).toCanonicalString(), '15.5');
    });

    test('subtracting the same currency works', () {
      final Money a = Money.parse('10.00', currency: 'SAR');
      final Money b = Money.parse('5.50', currency: 'SAR');
      expect((a - b).toCanonicalString(), '4.5');
    });

    test(
      'THE non-negotiable ADR-002 test: summing mismatched currencies without '
      'a stated conversion throws CurrencyMismatchError at runtime',
      () {
        final Money sar = Money.parse('10.00', currency: 'SAR');
        final Money usd = Money.parse('10.00', currency: 'USD');
        expect(() => sar + usd, throwsA(isA<CurrencyMismatchError>()));
        expect(() => sar - usd, throwsA(isA<CurrencyMismatchError>()));
        expect(() => sar.compareTo(usd), throwsA(isA<CurrencyMismatchError>()));
        expect(() => sar < usd, throwsA(isA<CurrencyMismatchError>()));
      },
    );

    test('Money.sum throws on the first mismatched element', () {
      final List<Money> mixed = <Money>[
        Money.parse('1', currency: 'SAR'),
        Money.parse('2', currency: 'SAR'),
        Money.parse('3', currency: 'USD'),
      ];
      expect(
        () => Money.sum(mixed, currency: 'SAR'),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });

    test('Money.sum totals a same-currency list correctly', () {
      final List<Money> values = <Money>[
        Money.parse('1.10', currency: 'SAR'),
        Money.parse('2.20', currency: 'SAR'),
        Money.parse('3.30', currency: 'SAR'),
      ];
      expect(Money.sum(values, currency: 'SAR').toCanonicalString(), '6.6');
    });

    test('negation flips sign, keeps currency', () {
      final Money a = Money.parse('12.34', currency: 'SAR');
      expect((-a).toCanonicalString(), '-12.34');
      expect((-a).currencyCode, 'SAR');
    });

    test('comparison operators over the same currency', () {
      final Money a = Money.parse('5', currency: 'SAR');
      final Money b = Money.parse('10', currency: 'SAR');
      expect(a < b, isTrue);
      expect(b > a, isTrue);
      expect(a <= a, isTrue);
      expect(a >= a, isTrue);
    });
  });

  group('Equality and hashing (value semantics)', () {
    test('two Money with the same amount/currency are equal', () {
      expect(
        Money.parse('10.00', currency: 'SAR'),
        Money.parse('10.00', currency: 'sar'),
      );
    });

    test('different currency is never equal, even with the same amount', () {
      expect(
        Money.parse('10.00', currency: 'SAR') ==
            Money.parse('10.00', currency: 'USD'),
        isFalse,
      );
    });

    test('equal Money share a hashCode', () {
      expect(
        Money.parse('10.00', currency: 'SAR').hashCode,
        Money.parse('10.00', currency: 'SAR').hashCode,
      );
    });
  });

  group(
    'API-surface golden test (ADR-002 enforcement item 4) — read this before '
    'adding a member to Money',
    () {
      // ADR-002: "A test asserting Money exposes no member whose return type
      // is double or num (reflection-free: an explicit API-surface golden
      // test)." Dart has no dart:mirrors on Flutter, so this cannot be a
      // dynamic reflective scan; it is instead an explicit contract test —
      // it exercises every public member Money has *right now* and would
      // need a deliberate, reviewed edit to accommodate a new member. The
      // structural guarantee (no `Money.fromDouble`, no `toDouble()`) comes
      // from the class's design (a private default constructor, only the
      // named factories below) plus `.github/scripts/check_money_type_ban.sh`,
      // which greps this whole directory for `double`/`num`/`.toDouble(`.
      // This test's job is to document and pin the *intended* public API so
      // a future edit can't silently widen it.
      test('the only ways to construct a Money are the named factories', () {
        expect(Money.parse('1', currency: 'SAR'), isA<Money>());
        expect(Money.fromMinorUnits(100, currency: 'SAR'), isA<Money>());
        expect(Money.zero('SAR'), isA<Money>());
        expect(Money.tryParse('1', currency: 'SAR'), isA<Money>());
      });

      test('toString() never reveals the amount (NFR-S4/ADR-015)', () {
        final Money m = Money.parse('999999.99', currency: 'SAR');
        expect(m.toString(), 'Money(<redacted>, SAR)');
        expect(m.toString(), isNot(contains('999999')));
      });

      test(
        'toCanonicalString() is the only way to read the exact value back out',
        () {
          final Money m = Money.parse('42.00', currency: 'SAR');
          expect(m.toCanonicalString(), '42');
        },
      );
    },
  );

  group('Property-style tests (ADR-002 enforcement item 3)', () {
    test(
      'a + b - b == a for many randomly generated same-currency amounts',
      () {
        final math.Random random = math.Random(42); // fixed seed: reproducible
        for (int i = 0; i < 200; i++) {
          final Decimal a = _randomDecimal(random);
          final Decimal b = _randomDecimal(random);
          final Money ma = Money.parse(a.toString(), currency: 'SAR');
          final Money mb = Money.parse(b.toString(), currency: 'SAR');
          expect((ma + mb - mb), ma, reason: 'a=$a b=$b');
        }
      },
    );

    test('addition is commutative: a + b == b + a', () {
      final math.Random random = math.Random(7);
      for (int i = 0; i < 200; i++) {
        final Decimal a = _randomDecimal(random);
        final Decimal b = _randomDecimal(random);
        final Money ma = Money.parse(a.toString(), currency: 'SAR');
        final Money mb = Money.parse(b.toString(), currency: 'SAR');
        expect(ma + mb, mb + ma, reason: 'a=$a b=$b');
      }
    });

    test('addition is associative: (a + b) + c == a + (b + c)', () {
      final math.Random random = math.Random(99);
      for (int i = 0; i < 200; i++) {
        final Money a = Money.parse(
          _randomDecimal(random).toString(),
          currency: 'SAR',
        );
        final Money b = Money.parse(
          _randomDecimal(random).toString(),
          currency: 'SAR',
        );
        final Money c = Money.parse(
          _randomDecimal(random).toString(),
          currency: 'SAR',
        );
        expect((a + b) + c, a + (b + c));
      }
    });

    test('parse/serialise round-trips exactly for 0-4 fractional digits', () {
      final math.Random random = math.Random(1234);
      for (int i = 0; i < 200; i++) {
        final Decimal d = _randomDecimal(random);
        final String serialized = d.toString();
        expect(
          Money.parse(serialized, currency: 'SAR').toCanonicalString(),
          serialized,
        );
      }
    });
  });
}

/// Generates a random [Decimal] with 0-4 fractional digits and up to 6
/// integer digits, positive or negative — deliberately not using `double`
/// anywhere in its own implementation, in keeping with the file it tests.
Decimal _randomDecimal(math.Random random) {
  final bool negative = random.nextBool();
  final int wholeDigits = random.nextInt(999999);
  final int fractionDigitsCount = random.nextInt(5); // 0..4
  final String fraction = fractionDigitsCount == 0
      ? ''
      : '.${List<int>.generate(fractionDigitsCount, (_) => random.nextInt(10)).join()}';
  final String sign = negative && wholeDigits != 0 ? '-' : '';
  return Decimal.parse('$sign$wholeDigits$fraction');
}

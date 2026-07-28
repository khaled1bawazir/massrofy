/// The sign convention — KHA-28, defect O-QA-2, US-B7.
///
/// The convention is stated in full in
/// `lib/core/money/sign_convention.dart`. This file pins the two halves that
/// code can actually get wrong: what counts as a valid magnitude, and where
/// the sign is applied.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/core/money/sign_convention.dart';

void main() {
  group('an amount is a magnitude', () {
    test('a negative amount is rejected — O-QA-2', () {
      // The defect this closes: a typed "-50" was accepted on S-19 and
      // silently became a credit, because the aggregation applied the stored
      // sign *and* the direction. Two ways to say "credit", one of them
      // invisible.
      expect(
        violationForAmount(Money.parse('-50.00', currency: 'SAR')),
        AmountViolation.negative,
      );
    });

    test('zero is VALID — it is a different fact from unknown (KHA-25)', () {
      // Deliberately asserted rather than left implicit. A future reading of
      // "amounts must be positive" that swept zero up with negatives would
      // break `unparsed_completion_test.dart`'s zero case and quietly change
      // what a zero-value authorisation means.
      expect(violationForAmount(Money.zero('SAR')), isNull);
    });

    test('an ordinary positive amount is valid', () {
      expect(
        violationForAmount(Money.parse('152.75', currency: 'SAR')),
        isNull,
      );
    });

    test('checkMovementAmount throws, and names neither the figure nor the '
        'currency (NFR-S4 — an exception message is a log line waiting to '
        'happen)', () {
      Object? thrown;
      try {
        checkMovementAmount(
          Money.parse('-1234.56', currency: 'SAR'),
          context: 'unit test',
        );
      } on ArgumentError catch (error) {
        thrown = error;
      }

      expect(thrown, isA<ArgumentError>());
      expect(thrown.toString(), contains('negative'));
      expect(thrown.toString(), isNot(contains('1234.56')));
    });
  });

  group('the sign is applied in exactly one place', () {
    final Money hundred = Money.parse('100.00', currency: 'SAR');

    test('a debit contributes positively to spend', () {
      expect(
        signedForSpend(
          hundred,
          direction: MovementDirection.debit,
        ).toCanonicalString(),
        '100',
      );
    });

    test('a credit contributes negatively to spend (AC-B7.1)', () {
      expect(
        signedForSpend(
          hundred,
          direction: MovementDirection.credit,
        ).toCanonicalString(),
        '-100',
      );
    });

    test('an unrecognised direction is treated as a debit — the conservative '
        'direction to be wrong in', () {
      // An over-stated total is visible on screen and correctable; an
      // under-stated one is invisible. (Callers are expected to have excluded
      // such a transaction already — `spend_classification.dart` does.)
      expect(
        signedForSpend(hundred, direction: 'sideways').toCanonicalString(),
        '100',
      );
    });

    test('negation keeps the currency, so nothing can drift across '
        'currencies while changing sign', () {
      final Money usd = Money.parse('49.99', currency: 'USD');
      expect(
        signedForSpend(usd, direction: MovementDirection.credit).currencyCode,
        'USD',
      );
    });
  });

  group('the direction vocabulary is closed', () {
    test('only debit and credit are known', () {
      expect(MovementDirection.isKnown('debit'), isTrue);
      expect(MovementDirection.isKnown('credit'), isTrue);
      expect(MovementDirection.isKnown('DEBIT'), isFalse);
      expect(MovementDirection.isKnown('reversal'), isFalse);
    });
  });
}

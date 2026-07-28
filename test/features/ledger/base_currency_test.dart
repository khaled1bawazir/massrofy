/// Base-currency conversion — KHA-27, KHA-70, US-B9, AC-B9.1/2/3, NFR-A5,
/// ADR-009.
///
/// Every figure here is a pinned decimal string, and the hand-calculation is
/// written into the test where the number is not obvious. A loose matcher on
/// a converted amount is exactly how a spending tracker ends up disagreeing
/// with the bank by a halala and nobody notices for a month.
library;

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/exchange_rate.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/features/ledger/base_currency.dart';

import '../../support/ledger_fixtures.dart';

void main() {
  group('case 1 — the transaction is already in the base currency', () {
    test('the amount is used unchanged, with no rate at all', () {
      final BaseCurrencyAmount converted = BaseCurrencyConverter.forTransaction(
        tx(id: 1, amount: '152.75'),
      );

      expect(converted.basis, ConversionBasis.native);
      expect(converted.value!.toCanonicalString(), '152.75');
      expect(
        converted.rate,
        isNull,
        reason: 'there is no conversion, so there is no rate to distrust',
      );
    });
  });

  group("case 2 — the bank printed its own converted amount (ADR-009's "
      'preferred source)', () {
    test('the bank figure is used verbatim, not recomputed', () {
      // PRD §3.4's parenthesised form: USD 120.00 (SAR 450.12).
      final BaseCurrencyAmount converted = BaseCurrencyConverter.forTransaction(
        tx(
          id: 1,
          amount: '120.00',
          currency: 'USD',
          convertedAmount: '450.12',
          fxRate: '3.7510',
          fxRateDate: DateTime.utc(2026, 7, 27, 19, 47),
          fxRateSource: FxRateSource.smsStated,
        ),
      );

      expect(converted.basis, ConversionBasis.bankSuppliedAmount);
      // 120 × 3.7510 is 450.12 exactly here, but the point is that the figure
      // comes from the *message*: if the two ever disagreed, the bank's
      // number is what actually hit the account and must win.
      expect(converted.value!.toCanonicalString(), '450.12');
      expect(converted.value!.currencyCode, 'SAR');
    });

    test('the rate is derived for display when the message printed none — '
        'AC-B9.3', () {
      // 187.46 / 49.99 = 3.7499499899… — derived to ADR-009's 8 dp and used
      // ONLY for display. Note it is *not* the round 3.75 the bank probably
      // applied before its own rounding, which is precisely why the converted
      // amount comes from the message rather than from re-multiplying this.
      final BaseCurrencyAmount converted = BaseCurrencyConverter.forTransaction(
        tx(
          id: 1,
          amount: '49.99',
          currency: 'USD',
          convertedAmount: '187.46',
          fxRateSource: FxRateSource.smsImplied,
        ),
      );

      expect(converted.value!.toCanonicalString(), '187.46');
      expect(converted.rate!.source, ExchangeRateSource.smsImplied);
      expect(converted.rate!.rate, Decimal.parse('3.74994998'));
      expect(
        converted.rate!.rateDate,
        isNull,
        reason:
            'this fixture stored no rate date, and an undated rate must stay '
            'undated rather than acquire a plausible one (KHA-70)',
      );
    });
  });

  group('case 3 — the message stated a rate but no converted amount', () {
    test(
      'the rate is applied, rounded HALF_UP to the base currency exponent',
      () {
        // 35.00 EUR × 4.1234 = 144.3190 → 144.32 at SAR's two decimals.
        final BaseCurrencyAmount converted =
            BaseCurrencyConverter.forTransaction(
              tx(
                id: 1,
                amount: '35.00',
                currency: 'EUR',
                fxRate: '4.1234',
                fxRateDate: DateTime.utc(2026, 7, 26, 9),
                fxRateSource: FxRateSource.smsStated,
              ),
            );

        expect(converted.basis, ConversionBasis.statedRate);
        expect(converted.value!.toCanonicalString(), '144.32');
        expect(converted.rate!.rateDate, DateTime.utc(2026, 7, 26, 9));
        expect(converted.rate!.source, ExchangeRateSource.smsStated);
      },
    );

    test('a malformed stored rate degrades to "not converted", never to a '
        'crash or a guess (NFR-R5)', () {
      final BaseCurrencyAmount converted = BaseCurrencyConverter.forTransaction(
        tx(id: 1, amount: '35.00', currency: 'EUR', fxRate: 'about four'),
      );
      expect(converted.basis, ConversionBasis.unavailable);
      expect(converted.value, isNull);
    });

    test('a zero or negative stored rate is refused — it would convert real '
        'money into nothing', () {
      for (final String bad in <String>['0', '-3.75']) {
        expect(
          BaseCurrencyConverter.forTransaction(
            tx(id: 1, amount: '35.00', currency: 'EUR', fxRate: bad),
          ).basis,
          ConversionBasis.unavailable,
          reason: 'rate "$bad"',
        );
      }
    });
  });

  group('case 4 — foreign currency, nothing to convert with (ADR-009)', () {
    test('no rate is invented; the value is explicitly unavailable', () {
      final BaseCurrencyAmount converted = BaseCurrencyConverter.forTransaction(
        tx(id: 1, amount: '35.00', currency: 'EUR', conversionPending: true),
      );

      expect(converted.basis, ConversionBasis.unavailable);
      expect(converted.isPending, isTrue);
      expect(
        converted.value,
        isNull,
        reason:
            'null, not Money.zero — a purchase we cannot convert did not cost '
            'nothing',
      );
      expect(converted.rate, isNull);
    });
  });

  group('NFR-A5 — the base currency is a parameter, not an assumption', () {
    test('converting into a non-SAR base works, and a SAR transaction is then '
        'the one that needs converting', () {
      // The guard against a hard-coded 'SAR' anywhere in the conversion path.
      //
      // The numbers are also chosen to demonstrate ADR-002's mandated
      // rounding mode: 10.01 × 0.5 = 5.005 exactly, which HALF_UP takes to
      // 5.01. Dart's default `Decimal.round()` is half-to-**even** and would
      // give 5.00 — a one-halala difference that compounds across a month.
      final BaseCurrencyAmount sarIntoUsd =
          BaseCurrencyConverter.forTransaction(
            tx(id: 1, amount: '10.01', fxRate: '0.5'),
            baseCurrencyCode: 'USD',
          );

      expect(sarIntoUsd.value!.toCanonicalString(), '5.01');
      expect(sarIntoUsd.value!.currencyCode, 'USD');

      final BaseCurrencyAmount usdIntoUsd =
          BaseCurrencyConverter.forTransaction(
            tx(id: 2, amount: '100.00', currency: 'USD'),
            baseCurrencyCode: 'USD',
          );
      expect(usdIntoUsd.basis, ConversionBasis.native);
    });
  });

  group('the FX fee converts on its own terms (PRD §3.4)', () {
    test('a fee already in the base currency is used as-is', () {
      final BaseCurrencyAmount fee = BaseCurrencyConverter.feeForTransaction(
        tx(
          id: 1,
          amount: '120.00',
          currency: 'USD',
          convertedAmount: '450.12',
          fee: '11.25',
        ),
      );

      expect(fee.basis, ConversionBasis.native);
      expect(fee.value!.toCanonicalString(), '11.25');
    });

    test('a transaction with no fee yields no figure — not a zero one', () {
      final BaseCurrencyAmount fee = BaseCurrencyConverter.feeForTransaction(
        tx(id: 1, amount: '152.75'),
      );
      expect(fee.value, isNull);
    });

    test('a fee in a third currency with no rate is NOT silently added to a '
        'base-currency total (NFR-A5)', () {
      final BaseCurrencyAmount fee = BaseCurrencyConverter.feeForTransaction(
        tx(
          id: 1,
          amount: '120.00',
          currency: 'USD',
          fee: '2.00',
          feeCurrency: 'EUR',
        ),
      );
      expect(fee.basis, ConversionBasis.unavailable);
    });
  });

  group('FxRecording — what ingestion stores (KHA-70)', () {
    test('a base-currency transaction records no FX at all', () {
      final FxRecording fx = FxRecording.forParsedMessage(
        amount: Money.parse('152.75', currency: 'SAR'),
        convertedAmount: null,
        statedRate: null,
        occurredAtFromMessage: DateTime.utc(2026, 7, 28, 11, 32),
      );

      expect(fx.rate, isNull);
      expect(fx.rateDate, isNull);
      expect(fx.source, isNull);
      expect(fx.conversionPending, isFalse);
    });

    test('a stated rate is stored with the movement date and source '
        'sms_stated', () {
      final FxRecording fx = FxRecording.forParsedMessage(
        amount: Money.parse('120.00', currency: 'USD'),
        convertedAmount: Money.parse('450.12', currency: 'SAR'),
        statedRate: '3.7510',
        occurredAtFromMessage: DateTime.utc(2026, 7, 27, 19, 47),
      );

      expect(fx.rate, '3.7510');
      expect(fx.rateDate, DateTime.utc(2026, 7, 27, 19, 47));
      expect(fx.source, FxRateSource.smsStated);
      expect(fx.conversionPending, isFalse);
    });

    test('a message with both amounts but no rate stores the IMPLIED rate, '
        'labelled as implied', () {
      // 187.46 / 49.99, to ADR-009's 8 dp.
      final FxRecording fx = FxRecording.forParsedMessage(
        amount: Money.parse('49.99', currency: 'USD'),
        convertedAmount: Money.parse('187.46', currency: 'SAR'),
        statedRate: null,
        occurredAtFromMessage: DateTime.utc(2026, 7, 26, 6, 14),
      );

      expect(fx.rate, '3.74994998');
      expect(fx.source, FxRateSource.smsImplied);
      expect(fx.rateDate, DateTime.utc(2026, 7, 26, 6, 14));
    });

    test('**the KHA-70 case**: when the message stated no time, the rate date '
        'stays NULL rather than becoming our phone\'s delivery time', () {
      // The pipeline passes `fields.occurredAtUtc`, not the `received_at`
      // fallback, precisely so this stays unknown. A delivery timestamp is a
      // fact about our phone, not about the bank's conversion.
      final FxRecording fx = FxRecording.forParsedMessage(
        amount: Money.parse('49.99', currency: 'USD'),
        convertedAmount: Money.parse('187.46', currency: 'SAR'),
        statedRate: null,
        occurredAtFromMessage: null,
      );

      expect(fx.rate, '3.74994998');
      expect(fx.source, FxRateSource.smsImplied);
      expect(fx.rateDate, isNull);
    });

    test('a foreign amount with neither a conversion nor a rate is recorded '
        'as conversionPending, with no invented rate', () {
      final FxRecording fx = FxRecording.forParsedMessage(
        amount: Money.parse('35.00', currency: 'EUR'),
        convertedAmount: null,
        statedRate: null,
        occurredAtFromMessage: DateTime.utc(2026, 7, 26, 9),
      );

      expect(fx.conversionPending, isTrue);
      expect(fx.rate, isNull);
      expect(fx.rateDate, isNull);
      expect(fx.source, isNull);
    });

    test('a converted amount in a currency that is NOT the base currency does '
        'not count as a conversion', () {
      // A USD purchase whose message printed a EUR equivalent tells us
      // nothing about SAR. Recording it as converted would put a EUR figure
      // in a SAR total.
      final FxRecording fx = FxRecording.forParsedMessage(
        amount: Money.parse('120.00', currency: 'USD'),
        convertedAmount: Money.parse('110.00', currency: 'EUR'),
        statedRate: null,
        occurredAtFromMessage: DateTime.utc(2026, 7, 27),
      );

      expect(fx.conversionPending, isTrue);
      expect(fx.rate, isNull);
    });
  });
}

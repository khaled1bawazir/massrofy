import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/exchange_rate.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/core/money/money_converter.dart';

void main() {
  group('MoneyConverter.convert (ADR-002 / ADR-009)', () {
    test('converts using the stated rate and rounds HALF_UP to 2 decimals', () {
      final Money usd = Money.parse('10.00', currency: 'USD');
      final ExchangeRate rate = ExchangeRate(
        fromCurrency: 'USD',
        toCurrency: 'SAR',
        rate: Decimal.parse('3.75'),
        rateDate: DateTime.utc(2026, 1, 1),
        source: ExchangeRateSource.smsStated,
      );

      final Money converted = MoneyConverter.convert(usd, rate: rate);
      expect(converted.currencyCode, 'SAR');
      // package:decimal's canonical toString() trims trailing zeros — see
      // the note in money_test.dart; "37.5" and "37.50" are the same value.
      expect(converted.toCanonicalString(), '37.5');
    });

    test('rounds a genuine half-way case away from zero (HALF_UP)', () {
      // 1 * 1.125 = 1.125 -> rounds to 1.13 at 2 decimals (HALF_UP), not 1.12.
      final Money one = Money.parse('1', currency: 'USD');
      final ExchangeRate rate = ExchangeRate(
        fromCurrency: 'USD',
        toCurrency: 'SAR',
        rate: Decimal.parse('1.125'),
        rateDate: DateTime.utc(2026, 1, 1),
        source: ExchangeRateSource.user,
      );
      expect(
        MoneyConverter.convert(one, rate: rate).toCanonicalString(),
        '1.13',
      );
    });

    test('rounds a negative half-way case away from zero too', () {
      final Money negative = Money.parse('-1', currency: 'USD');
      final ExchangeRate rate = ExchangeRate(
        fromCurrency: 'USD',
        toCurrency: 'SAR',
        rate: Decimal.parse('1.125'),
        rateDate: DateTime.utc(2026, 1, 1),
        source: ExchangeRateSource.user,
      );
      expect(
        MoneyConverter.convert(negative, rate: rate).toCanonicalString(),
        '-1.13',
      );
    });

    test('does not round when the result already has fewer decimals', () {
      final Money usd = Money.parse('4.00', currency: 'USD');
      final ExchangeRate rate = ExchangeRate(
        fromCurrency: 'USD',
        toCurrency: 'SAR',
        rate: Decimal.parse('3.75'),
        rateDate: DateTime.utc(2026, 1, 1),
        source: ExchangeRateSource.smsImplied,
      );
      expect(MoneyConverter.convert(usd, rate: rate).toCanonicalString(), '15');
    });

    test(
      'refuses to convert through a rate whose fromCurrency does not match '
      "the Money's own currency (ADR-002: never through a mismatched rate)",
      () {
        final Money sar = Money.parse('10.00', currency: 'SAR');
        final ExchangeRate usdToSarRate = ExchangeRate(
          fromCurrency: 'USD',
          toCurrency: 'SAR',
          rate: Decimal.parse('3.75'),
          rateDate: DateTime.utc(2026, 1, 1),
          source: ExchangeRateSource.smsStated,
        );
        expect(
          () => MoneyConverter.convert(sar, rate: usdToSarRate),
          throwsArgumentError,
        );
      },
    );

    test('the original Money is never mutated by a conversion', () {
      final Money usd = Money.parse('10.00', currency: 'USD');
      final ExchangeRate rate = ExchangeRate(
        fromCurrency: 'USD',
        toCurrency: 'SAR',
        rate: Decimal.parse('3.75'),
        rateDate: DateTime.utc(2026, 1, 1),
        source: ExchangeRateSource.smsStated,
      );
      MoneyConverter.convert(usd, rate: rate);
      expect(usd.toCanonicalString(), '10');
      expect(usd.currencyCode, 'USD');
    });
  });

  group('ExchangeRate — traceability (AC-B9.3)', () {
    test('carries rate, rate date, and source together', () {
      final ExchangeRate rate = ExchangeRate(
        fromCurrency: 'USD',
        toCurrency: 'SAR',
        rate: Decimal.parse('3.75'),
        rateDate: DateTime.utc(2026, 1, 1),
        source: ExchangeRateSource.smsImplied,
      );
      expect(rate.rate.toString(), '3.75');
      expect(rate.rateDate, DateTime.utc(2026, 1, 1));
      expect(rate.source, ExchangeRateSource.smsImplied);
    });
  });
}

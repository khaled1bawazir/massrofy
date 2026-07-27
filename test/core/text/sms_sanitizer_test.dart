import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/text/sms_sanitizer.dart';

void main() {
  group('SmsSanitizer — PAN redaction (Luhn-valid 13-19 digit runs)', () {
    test('a Luhn-valid 16-digit PAN is masked to ****<last4>', () {
      // 4111111111111111 is the well-known Luhn-valid Visa test PAN.
      const String body =
          'Purchase of 45.00 SAR on card 4111111111111111 at Panda';
      final SanitizedSmsText result = SmsSanitizer.sanitize(body);
      expect(result.value, isNot(contains('4111111111111111')));
      expect(result.value, contains('****1111'));
      expect(result.panRedacted, isTrue);
    });

    test('a full PAN-like string must NEVER be persisted or logged unmarked '
        '(this is the P1 required assertion)', () {
      const String fullPan = '4111111111111111';
      final SanitizedSmsText result = SmsSanitizer.sanitize(
        'card $fullPan charged 10.00 SAR',
      );
      expect(result.value.contains(fullPan), isFalse);
    });

    test(
      'a non-Luhn-valid long digit run (e.g. a reference number) is left alone',
      () {
        // 1234567890123456 fails Luhn.
        const String body = 'Ref number 1234567890123456 transfer completed';
        final SanitizedSmsText result = SmsSanitizer.sanitize(body);
        expect(result.value, contains('1234567890123456'));
        expect(result.panRedacted, isFalse);
      },
    );

    test(
      'digit runs shorter than 13 or longer than 19 are not PAN candidates',
      () {
        const String body = 'Amount 123456789012 and 12345678901234567890';
        final SanitizedSmsText result = SmsSanitizer.sanitize(body);
        // Neither run length (12, 20) is in the [13,19] PAN window.
        expect(result.value, contains('123456789012'));
        expect(result.value, contains('12345678901234567890'));
      },
    );
  });

  group('SmsSanitizer — CVV/PIN/OTP redaction', () {
    test('redacts a CVV following the English keyword', () {
      final SanitizedSmsText result = SmsSanitizer.sanitize('Your CVV is 123');
      expect(result.value, isNot(contains('123')));
      expect(result.value, contains('[REDACTED]'));
    });

    test('redacts an OTP following the English keyword', () {
      final SanitizedSmsText result = SmsSanitizer.sanitize(
        'OTP: 445566 do not share',
      );
      expect(result.value, isNot(contains('445566')));
      expect(result.value, contains('[REDACTED]'));
    });

    test('redacts a verification code following the Arabic keyword', () {
      final SanitizedSmsText result = SmsSanitizer.sanitize(
        'رمز التحقق هو 998877',
      );
      expect(result.value, isNot(contains('998877')));
      expect(result.value, contains('[REDACTED]'));
    });

    // --- OTP under-redaction fix — the digits-before-keyword direction ---
    // A very common real-world Arabic OTP phrasing puts the code BEFORE the
    // keyword ("123456 is your verification code"), which the
    // keyword-then-digits pattern alone would never match at all — a
    // genuine, silent under-redaction gap, not a cosmetic one.
    test('redacts an OTP that appears BEFORE the Arabic keyword (the common '
        '"<code> هو رمز التحقق" phrasing)', () {
      final SanitizedSmsText result = SmsSanitizer.sanitize(
        '445566 هو رمز التحقق الخاص بك، لا تشاركه مع أحد',
      );
      expect(result.value, isNot(contains('445566')));
      expect(result.value, contains('[REDACTED]'));
    });

    test('redacts an OTP that appears BEFORE the English keyword '
        '("123456 is your verification code")', () {
      final SanitizedSmsText result = SmsSanitizer.sanitize(
        '123456 is your verification code, valid for 5 minutes',
      );
      expect(result.value, isNot(contains('123456')));
      expect(result.value, contains('[REDACTED]'));
    });

    test('redacts a one-time password using the "one-time password" '
        'synonym, keyword-then-digits', () {
      final SanitizedSmsText result = SmsSanitizer.sanitize(
        'Your one-time password is 778899',
      );
      expect(result.value, isNot(contains('778899')));
      expect(result.value, contains('[REDACTED]'));
    });

    test(
      'redacts a code using the Arabic "رمز الدخول" (access code) synonym',
      () {
        final SanitizedSmsText result = SmsSanitizer.sanitize(
          'رمز الدخول: 112233',
        );
        expect(result.value, isNot(contains('112233')));
        expect(result.value, contains('[REDACTED]'));
      },
    );
  });

  group('SmsSanitizer — Saudi IBAN redaction', () {
    test('masks a Saudi IBAN to SA**…<last4>', () {
      const String iban = 'SA0380000000608010167519'; // SA + 22 digits
      final SanitizedSmsText result = SmsSanitizer.sanitize(
        'Transfer to $iban completed',
      );
      expect(result.value, isNot(contains(iban)));
      expect(result.value, contains('SA**…7519'));
    });
  });

  group('SmsSanitizer — non-sensitive text is preserved', () {
    test(
      'an ordinary purchase message with no sensitive data is unchanged',
      () {
        const String body = 'Purchase of 45.00 SAR at Panda Foods today';
        final SanitizedSmsText result = SmsSanitizer.sanitize(body);
        expect(result.value, body);
        expect(result.panRedacted, isFalse);
      },
    );
  });

  group('SanitizedSmsText — ingestion-boundary type enforcement (ADR-013)', () {
    test('is only constructible via SmsSanitizer.sanitize', () {
      // There is no `SanitizedSmsText(...)` constructor to call here — the
      // fact that this file cannot write `SanitizedSmsText('raw text')`
      // directly (it would not compile) is the actual enforcement; this
      // test documents and exercises the one sanctioned construction path.
      final SanitizedSmsText result = SmsSanitizer.sanitize('hello');
      expect(result, isA<SanitizedSmsText>());
    });
  });
}

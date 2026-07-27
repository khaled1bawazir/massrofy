import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/text/sms_sanitizer.dart';

/// Every digit character [SmsSanitizer] is expected to understand: ASCII
/// `0-9`, Eastern Arabic-Indic `٠-٩` (U+0660-U+0669), and Extended/Persian
/// Arabic-Indic `۰-۹` (U+06F0-U+06F9).
///
/// Asserting `isNot(contains(_anyDigitPattern))` is deliberately stricter
/// than asserting the original code string is absent: it catches a *partial*
/// leak (one surviving digit of a longer code), which is exactly the bug the
/// regression tests below exist for. `contains()` accepts a `Pattern`, and
/// `RegExp` implements `Pattern`, so this composes directly with matchers.
final RegExp _anyDigitPattern = RegExp(r'[0-9\u0660-\u0669\u06F0-\u06F9]');

/// Rewrites the ASCII digits of [ascii] as Eastern Arabic-Indic numerals,
/// leaving every other character alone. Done programmatically rather than by
/// pasting Arabic-Indic literals so the test's intent (and the ASCII value
/// being converted) stays readable in a diff and can't be mistyped.
String _toArabicIndic(String ascii) => ascii.replaceAllMapped(
  RegExp(r'[0-9]'),
  (Match m) => String.fromCharCode(0x0660 + (m.group(0)!.codeUnitAt(0) - 0x30)),
);

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

    // --- OTP under-redaction fix — the OVERFLOW-DIGIT leak ----------------
    //
    // The digit-matching quantifier used to be bounded (`\d{3,8}`), which
    // does not merely "fail to match" a longer code — it matches a
    // fixed-width slice of it and publishes the remainder in cleartext.
    // Both directions leaked, at opposite ends:
    //
    //   "OTP: 123456789 is your code" -> "OTP: [REDACTED]9 is your code"
    //   "123456789 is your OTP"       -> "1[REDACTED] is your OTP"
    //
    // A leaked digit of a live one-time code is a real disclosure, and it
    // is written permanently into the message table. These tests pin the
    // exact expected output (not merely "contains [REDACTED]"), because
    // "contains" is precisely the assertion shape that let the original
    // leak pass as green.
    test('redacts a 9-digit code ENTIRELY when the keyword comes first — no '
        'trailing digit survives', () {
      final SanitizedSmsText result = SmsSanitizer.sanitize(
        'OTP: 123456789 is your code',
      );
      expect(result.value, 'OTP: [REDACTED] is your code');
      expect(result.value, isNot(contains('9')));
    });

    test('redacts a 9-digit code ENTIRELY when the digits come first — no '
        'leading digit survives', () {
      final SanitizedSmsText result = SmsSanitizer.sanitize(
        '123456789 is your OTP',
      );
      expect(result.value, '[REDACTED] is your OTP');
      expect(result.value, isNot(contains('1')));
    });

    // A property-style sweep rather than a single length: OTP lengths vary
    // by bank (4, 5, 6, 8...), so "raise the upper bound to 9" would have
    // been a non-fix. Nothing shorter or longer may leak a single digit, in
    // either phrasing, in either digit family.
    test('no code length from 3 to 20 digits leaks ANY digit, in either '
        'phrasing or digit family', () {
      for (int length = 3; length <= 20; length++) {
        final String asciiCode = List<String>.generate(
          length,
          (int i) => '${(i + 1) % 10}',
        ).join();
        final String arabicIndicCode = _toArabicIndic(asciiCode);

        for (final String code in <String>[asciiCode, arabicIndicCode]) {
          for (final String message in <String>[
            'OTP: $code is your code',
            '$code is your OTP',
            'رمز التحقق هو $code',
            '$code هو رمز التحقق الخاص بك',
          ]) {
            final SanitizedSmsText result = SmsSanitizer.sanitize(message);
            expect(
              result.value,
              isNot(contains(_anyDigitPattern)),
              reason:
                  'length $length leaked a digit from "$message" -> '
                  '"${result.value}"',
            );
            expect(result.value, contains('[REDACTED]'));
          }
        }
      }
    });

    // --- Arabic-Indic numerals --------------------------------------------
    //
    // Dart's `\d` is ASCII-only, so the previous patterns could not match
    // Eastern Arabic-Indic digits at all — an OTP written "١٢٣٤٥٦" was
    // stored completely in the clear. This product is Arabic-first
    // (docs/PRD.md §3.4: one sample bank's messages are fully Arabic), and
    // docs/brand.md's "Western numerals" rule governs UI *rendering* only,
    // not what a bank puts on the wire — so the sanitizer must handle both.
    test('redacts an Arabic-Indic OTP after an Arabic keyword', () {
      final SanitizedSmsText result = SmsSanitizer.sanitize(
        'رمز التحقق هو ١٢٣٤٥٦ لا تشاركه',
      );
      expect(result.value, isNot(contains('١')));
      expect(result.value, contains('[REDACTED]'));
    });

    test('redacts an Arabic-Indic OTP placed BEFORE an Arabic keyword', () {
      final SanitizedSmsText result = SmsSanitizer.sanitize(
        '١٢٣٤٥٦ هو رمز التحقق الخاص بك',
      );
      expect(result.value, isNot(contains(_anyDigitPattern)));
      expect(result.value, contains('[REDACTED]'));
    });

    test(
      'redacts Extended/Persian Arabic-Indic digits (U+06F0-U+06F9) too',
      () {
        final SanitizedSmsText result = SmsSanitizer.sanitize(
          'رمز الدخول: ۱۲۳۴۵۶۷۸۹',
        );
        expect(result.value, isNot(contains(_anyDigitPattern)));
        expect(result.value, contains('[REDACTED]'));
      },
    );
  });

  group('SmsSanitizer — PAN detection is digit-family agnostic', () {
    // The Luhn check used to decode digits with `codeUnit - 0x30`, which is
    // ASCII-only arithmetic: on '٥' (U+0665) it produces 1589, so an
    // Arabic-Indic PAN could never checksum and was never redacted. Same
    // class of leak as the OTP one above, on the more sensitive field.
    test('redacts a Luhn-valid PAN written in Arabic-Indic numerals', () {
      final String pan = _toArabicIndic('4111111111111111');
      final SanitizedSmsText result = SmsSanitizer.sanitize(
        'شراء بالبطاقة $pan بمبلغ ٤٥ ريال',
      );
      expect(result.panRedacted, isTrue);
      expect(result.value, isNot(contains(pan)));
      expect(result.value, contains('****${_toArabicIndic('1111')}'));
    });
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

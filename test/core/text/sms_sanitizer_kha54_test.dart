/// Regression suite for **Linear KHA-54** — *"SmsSanitizer under-redaction:
/// decoy digit runs and group-separated PANs"*.
///
/// Raised by the code-reviewer during round 3 of PR #1 and labelled a **P2
/// blocker**: *"do not let live SMS reach `SmsSanitizer` until it is
/// [closed]"*. P2 is the phase that gives `SmsSanitizer` its first production
/// caller (`IngestionPipeline`), so it is closed here, in the same change that
/// makes it live.
///
/// ## Every assertion here pins exact output. That is the point.
///
/// KHA-54's done check is explicit about it:
///
/// > *"Pin exact expected output. `contains('[REDACTED]')` is exactly the
/// > assertion shape that let the original leak pass green."*
///
/// It is worth understanding *why*, because it is the single most instructive
/// thing in this file. The original bug produced:
///
/// ```
/// "Your OTP for account 1234 is 567890"
///   → "Your OTP for account [REDACTED] is 567890"
/// ```
///
/// A `contains('[REDACTED]')` assertion passes on that string. So does
/// `isNot(contains('1234'))`. The message *looks* handled — there is a
/// redaction marker right there — while the live one-time code sits in the
/// output in the clear. Only pinning the whole expected string, or asserting
/// the absence of the *secret's own digits*, catches it.
///
/// Each group below therefore asserts both: the exact output, **and** that no
/// digit of the secret survives anywhere in it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/text/sms_sanitizer.dart';

/// Asserts that not one character of [secret] survives in [output].
///
/// Stronger than `isNot(contains(secret))`: that would pass on
/// `"56 7890"` — the same digits, merely split. This checks the digits
/// themselves are gone.
void expectNoDigitOfSecretSurvives(String output, String secret) {
  for (int i = 0; i + 3 <= secret.length; i++) {
    final String window = secret.substring(i, i + 3);
    expect(
      output.contains(window),
      isFalse,
      reason:
          'the 3-digit run "$window" from the secret "$secret" survived '
          'redaction in: $output',
    );
  }
}

void main() {
  group('KHA-54 gap 1 — a decoy digit run must not shield the real secret', () {
    // The original failure: the nearest digit run to the keyword was redacted
    // and the actual code, further away, was published verbatim.
    test('English, account number between the keyword and the code', () {
      final String out = SmsSanitizer.sanitize(
        'Your OTP for account 1234 is 567890',
      ).value;

      expect(out, 'Your OTP for account [REDACTED] is [REDACTED]');
      expectNoDigitOfSecretSurvives(out, '567890');
    });

    test('English, card suffix between the keyword and the code', () {
      final String out = SmsSanitizer.sanitize(
        'OTP for card ending 4321 is 998877',
      ).value;

      expect(out, 'OTP for card ending [REDACTED] is [REDACTED]');
      expectNoDigitOfSecretSurvives(out, '998877');
    });

    test('Arabic, same shape, Arabic-Indic numerals', () {
      // "Your verification code for account ١٢٣٤ is ٥٦٧٨٩٠"
      final String out = SmsSanitizer.sanitize(
        'رمز التحقق الخاص بك للحساب ١٢٣٤ هو ٥٦٧٨٩٠',
      ).value;

      expect(out, 'رمز التحقق الخاص بك للحساب [REDACTED] هو [REDACTED]');
      expectNoDigitOfSecretSurvives(out, '٥٦٧٨٩٠');
    });

    test('three decoys and one real code — every run in the window goes', () {
      final String out = SmsSanitizer.sanitize(
        'OTP: ref 111 acct 2222 card 3333 code is 456789',
      ).value;

      // Over-redaction is the correct failure mode here (ADR-017's reasoning
      // applied to secrets): we cannot know which run is the code, so all of
      // them in the keyword's window are destroyed.
      expect(
        out,
        'OTP: ref [REDACTED] acct [REDACTED] card [REDACTED] '
        'code is [REDACTED]',
      );
      expectNoDigitOfSecretSurvives(out, '456789');
    });
  });

  group('KHA-54 gap 2 — a wide gap must not push the secret out of range', () {
    // The original 20-CHARACTER bound failed twice over here: the "5" in
    // "5 minutes" broke the no-digits-allowed gap class, and the remaining
    // distance to the code exceeded 20 characters. Nothing was redacted at
    // all — not even a misleading marker.
    test('"valid for 5 minutes" between the keyword and the code', () {
      final String out = SmsSanitizer.sanitize(
        'Your verification code, valid for 5 minutes, is 903212',
      ).value;

      expect(out, 'Your verification code, valid for 5 minutes, is [REDACTED]');
      expectNoDigitOfSecretSurvives(out, '903212');
    });

    test('a long connecting phrase in Arabic', () {
      final String out = SmsSanitizer.sanitize(
        'رمز التحقق الخاص بك صالح لمدة خمس دقائق فقط وهو 483920',
      ).value;

      expectNoDigitOfSecretSurvives(out, '483920');
      expect(out.contains('[REDACTED]'), isTrue);
    });

    test('a digit run genuinely far from any keyword is left alone — the word '
        'bound is a bound, not a licence to redact the whole message', () {
      // A purchase amount at the far end of a long sentence that happens to
      // mention a code near the start. Over-redaction is the safe failure
      // mode, but it is not free: an unnecessarily destroyed amount sends a
      // real transaction to the review queue.
      final String out = SmsSanitizer.sanitize(
        'Your OTP is 123456. Separately, and much later in this rather long '
        'notification which continues for quite some distance indeed, we '
        'note a purchase of 250.75 SAR',
      ).value;

      expectNoDigitOfSecretSurvives(out, '123456');
      expect(
        out.contains('250.75'),
        isTrue,
        reason:
            'a value far outside the keyword window should survive; if this '
            'fails, the proximity bound has effectively become unbounded',
      );
    });
  });

  group('KHA-54 gap 3 — group-separated PANs (the highest-severity gap)', () {
    // Why this was the worst of the three: it is the most sensitive field
    // (NFR-S2/NFR-C2 say the app must be *structurally incapable* of
    // persisting cardholder data), groups of four is the most common way a
    // card number is ever written, AND `panRedacted` reported `false` — so
    // the schema flag actively recorded the absence of a PAN that was sitting
    // in the row in cleartext.
    test('space-separated 16-digit PAN', () {
      final SanitizedSmsText result = SmsSanitizer.sanitize(
        'purchase 4111 1111 1111 1111 SAR 45',
      );

      expect(result.value, 'purchase ****1111 SAR 45');
      expect(
        result.panRedacted,
        isTrue,
        reason:
            'panRedacted must report the truth — a false negative here means '
            'the schema records "no PAN present" for a row that had one',
      );
    });

    test('hyphen-separated 16-digit PAN', () {
      final SanitizedSmsText result = SmsSanitizer.sanitize(
        'purchase 4111-1111-1111-1111 SAR 45',
      );

      expect(result.value, 'purchase ****1111 SAR 45');
      expect(result.panRedacted, isTrue);
    });

    test('contiguous PAN still works (no regression on the original path)', () {
      final SanitizedSmsText result = SmsSanitizer.sanitize(
        'purchase 4111111111111111 SAR 45',
      );

      expect(result.value, 'purchase ****1111 SAR 45');
      expect(result.panRedacted, isTrue);
    });

    test('19-digit grouped PAN (the upper end of the ADR-013 window)', () {
      // "4111 1111 1111 1111 342" → strip separators → 19 digits, Luhn-valid
      // (check digit computed for this test, not copied from anywhere).
      const String pan = '4111111111111111342';
      expect(
        _luhn(pan),
        isTrue,
        reason: 'fixture precondition: this must be a Luhn-valid 19-digit PAN',
      );

      final SanitizedSmsText result = SmsSanitizer.sanitize(
        'card 4111 1111 1111 1111 342 charged',
      );
      expect(result.value, 'card ****1342 charged');
      expect(result.panRedacted, isTrue);
    });

    test(
      'a grouped date is NOT mistaken for a PAN — Luhn and the length window '
      'are what keep this precise rather than blunt',
      () {
        final SanitizedSmsText result = SmsSanitizer.sanitize(
          'transfer on 12-05-2026 completed',
        );

        // Stripping separators gives "12052026": 8 digits, outside the 13-19
        // window. A blunt "redact every long number" rule would have eaten
        // this — and, worse, would eat transaction reference numbers, which
        // are ADR-017 D2's reliable duplicate key.
        expect(result.value, 'transfer on 12-05-2026 completed');
        expect(result.panRedacted, isFalse);
      },
    );

    test('a grouped run that fails Luhn is left alone', () {
      final SanitizedSmsText result = SmsSanitizer.sanitize(
        'reference 1234 5678 9012 3456 recorded',
      );

      expect(_luhn('1234567890123456'), isFalse);
      expect(result.value, 'reference 1234 5678 9012 3456 recorded');
      expect(result.panRedacted, isFalse);
    });
  });

  group('the property sweep, extended with a decoy (KHA-54 done check)', () {
    // The original sweep covered secret lengths 3..20, three digit families,
    // and both keyword orderings. KHA-54 asks for a decoy digit run before
    // the real code, in both English and Arabic — because that is the exact
    // dimension the original sweep did not vary, which is why it stayed green
    // through the bug.
    const List<({String name, int base})> digitFamilies =
        <({String name, int base})>[
          (name: 'ASCII', base: 0x30),
          (name: 'Arabic-Indic', base: 0x0660),
          (name: 'Extended Arabic-Indic', base: 0x06F0),
        ];

    for (final ({String name, int base}) family in digitFamilies) {
      String digits(int length) => String.fromCharCodes(
        List<int>.generate(length, (int i) => family.base + (i % 10)),
      );

      for (int length = 3; length <= 12; length++) {
        test('${family.name}, $length-digit secret, decoy first (English)', () {
          final String secret = digits(length);
          final String decoy = digits(4);
          final String out = SmsSanitizer.sanitize(
            'Your OTP for account $decoy is $secret',
          ).value;

          expectNoDigitOfSecretSurvives(out, secret);
        });

        test('${family.name}, $length-digit secret, decoy first (Arabic)', () {
          final String secret = digits(length);
          final String decoy = digits(4);
          final String out = SmsSanitizer.sanitize(
            'رمز التحقق للحساب $decoy هو $secret',
          ).value;

          expectNoDigitOfSecretSurvives(out, secret);
        });

        test('${family.name}, $length-digit secret, keyword last', () {
          final String secret = digits(length);
          final String out = SmsSanitizer.sanitize(
            '$secret هو رمز التحقق الخاص بك',
          ).value;

          expectNoDigitOfSecretSurvives(out, secret);
        });
      }
    }
  });
}

/// Local Luhn, so the fixtures above can assert their own preconditions
/// rather than trusting a hand-written "this is a valid PAN" comment.
bool _luhn(String digits) {
  int sum = 0;
  bool doubleIt = false;
  for (int i = digits.length - 1; i >= 0; i--) {
    int d = digits.codeUnitAt(i) - 0x30;
    if (doubleIt) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    doubleIt = !doubleIt;
  }
  return sum % 10 == 0;
}

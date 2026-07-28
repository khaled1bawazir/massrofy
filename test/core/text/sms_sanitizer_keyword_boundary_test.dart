/// Regression tests for **B4** — `_secretKeywordPattern` had no word
/// boundary, so the three-letter Latin secret keywords matched *inside
/// unrelated words*.
///
/// ## What the defect actually was
///
/// `PIN` matched inside `SHOPPING`, `SHIPPING`, `SPINNEYS`, `TOPPING`,
/// `ALPINE` and `PINEAPPLE`; `OTP` matched inside `OTPARK`. Because
/// `SmsSanitizer`'s §13.6 sweep destroys **every** 3+ digit run within 12
/// words of a keyword, a single spurious match wrecked a whole legitimate
/// transaction message:
///
/// ```text
/// in : Purchase of SAR 137.50 at SPINNEYS RIYADH card ending 4321
/// out: Purchase of SAR [REDACTED].50 at SPINNEYS RIYADH card ending [REDACTED]
/// ```
///
/// ## Why this is a correctness bug and not ADR-013's safe over-redaction
///
/// ADR-013 §13.6 accepts over-redaction as the safe failure mode, but it
/// bounds that acceptance explicitly: the sweep "can only fire in a message
/// that contains a secret keyword at all". A supermarket receipt contains no
/// secret, so the defect **invalidated the ADR's own stated bound** rather
/// than exercising it.
///
/// And the damage is not cosmetic. The two fields destroyed above — the
/// amount and the card suffix — are exactly the fields ADR-017's D2 and D3
/// duplicate detection compare. A security rule was silently corrupting the
/// ledger's dedup inputs.
///
/// ## Why the fix is not `\b`
///
/// Dart's `\b` is defined against `\w` = `[A-Za-z0-9_]`, which is ASCII. Every
/// Arabic letter is a non-word character to it, so `\b` would break the
/// Arabic half of the keyword list — turning a text-mangling bug into a
/// *leak* in the product's primary locale. The fix is
/// `SmsSanitizer._isTokenBounded`, a script-aware check written in Dart.
///
/// ## The half of this file that matters most
///
/// The false-positive tests below are the reported defect. The **true
/// positive** tests are what stop the fix from being worse than the bug: a
/// boundary that is too strict does not mangle a merchant name, it writes a
/// live PIN into the database forever. The Arabic clitic cases (`الرمز`,
/// `رمزك`) are the specific trap — Arabic attaches its definite article and
/// its possessive suffixes to the word with no space, so an adjacent Arabic
/// letter is ordinary morphology, not a fragment.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/text/sms_sanitizer.dart';

/// The reviewer's exact repro sentence, parameterised by merchant name.
///
/// Kept as one template so every false-positive case is byte-for-byte the
/// message that was reported, differing only in the word that used to trip
/// the keyword match.
String purchaseAt(String merchant) =>
    'Purchase of SAR 137.50 at $merchant card ending 4321';

/// Every Latin word reported as producing a false positive, with the keyword
/// it spuriously matched.
const Map<String, String> falsePositiveWords = <String, String>{
  'SPINNEYS RIYADH': 'PIN',
  'SHOPPING CENTRE': 'PIN',
  'SHIPPING CO': 'PIN',
  'TOPPING HOUSE': 'PIN',
  'ALPINE CAFE': 'PIN',
  'PINEAPPLE JUICE': 'PIN',
  'OTPARK GARAGE': 'OTP',
};

void main() {
  group('B4 — a Latin keyword inside a longer word is not a keyword', () {
    // Exact-output assertions, not `isNot(contains('[REDACTED]'))`. The PR
    // that introduced this file's sibling tests makes the point already:
    // `contains`-shaped assertions are precisely what let the original
    // KHA-54 leak pass green. Here the requirement is stronger and simpler —
    // the sanitiser must return the message **unchanged**.
    for (final MapEntry<String, String> entry in falsePositiveWords.entries) {
      test('"${entry.key}" does not match ${entry.value} — message is '
          'returned unchanged', () {
        final String input = purchaseAt(entry.key);
        final SanitizedSmsText out = SmsSanitizer.sanitize(input);

        expect(
          out.value,
          input,
          reason:
              '"${entry.value}" was matched inside "${entry.key}", and the '
              'proximity sweep then destroyed every digit run near it',
        );
        expect(
          out.panRedacted,
          isFalse,
          reason: 'there is no PAN in this message',
        );
      });
    }

    test('the reviewer\'s exact repro — the amount and the card suffix both '
        'survive intact', () {
      // Spelled out separately from the loop above because *which* fields
      // were destroyed is the reason this was a blocker rather than a
      // cosmetic complaint: ADR-017 D2 compares amounts and D3 compares
      // instrument references. Losing them does not merely look wrong, it
      // breaks duplicate detection downstream.
      final SanitizedSmsText out = SmsSanitizer.sanitize(
        'Purchase of SAR 137.50 at SPINNEYS RIYADH card ending 4321',
      );

      expect(
        out.value,
        'Purchase of SAR 137.50 at SPINNEYS RIYADH card ending 4321',
      );
      expect(out.value, contains('137.50'), reason: 'ADR-017 D2 needs this');
      expect(out.value, contains('4321'), reason: 'ADR-017 D3 needs this');
      expect(out.value, isNot(contains('[REDACTED]')));
    });

    test('case-insensitivity does not reopen the hole — lower-case merchant '
        'names are equally unaffected', () {
      // The keyword pattern is `caseSensitive: false`, so the boundary check
      // has to hold for both cases or the fix only covers shouty templates.
      const String input = 'purchase at Spinneys and Pineapple Cafe, SAR 137';
      expect(SmsSanitizer.sanitize(input).value, input);
    });

    test('a keyword fragment at the very start or very end of the message is '
        'still rejected — the no-neighbour edge cases', () {
      // `PINEAPPLE` has no left neighbour; `ALPINE` has no right neighbour.
      // Both are the branches where `_isTokenBounded` skips a bounds check,
      // so both need pinning.
      const String startsWith = 'PINEAPPLE order 4521 confirmed';
      const String endsWith = 'order 4521 confirmed at ALPINE';

      expect(SmsSanitizer.sanitize(startsWith).value, startsWith);
      expect(SmsSanitizer.sanitize(endsWith).value, endsWith);
    });

    test('OTPIN contains neither OTP nor PIN as a token', () {
      // The one case where rejecting a match could in principle hide a
      // second, real keyword that started inside it: `allMatches` is
      // non-overlapping, so once `OTP` is matched and rejected the scan
      // resumes past it and never considers `PIN` at offset 1. That is
      // correct here — `PIN` would be rejected too, for having a Latin letter
      // on its left — and this test is what says so out loud.
      const String input = 'ref OTPIN 4521';
      expect(SmsSanitizer.sanitize(input).value, input);
    });
  });

  group('B4 — genuine Latin keywords still redact (do not trade a false '
      'positive for a leak)', () {
    test('a standalone PIN keyword still destroys the nearby code', () {
      final SanitizedSmsText out = SmsSanitizer.sanitize('Your PIN is 1234');
      expect(out.value, 'Your PIN is [REDACTED]');
    });

    test('a standalone OTP keyword still destroys the nearby code', () {
      final SanitizedSmsText out = SmsSanitizer.sanitize(
        'Your OTP is 445566, do not share it',
      );
      expect(out.value, 'Your OTP is [REDACTED], do not share it');
    });

    test('CVV still redacts', () {
      expect(
        SmsSanitizer.sanitize('CVV 123 for verification').value,
        'CVV [REDACTED] for verification',
      );
    });

    test('keyword and code run together with no separator still redacts — '
        'digits are deliberately NOT a boundary', () {
      // `PIN1234` / `OTP445566` are real bank template shapes. Had the fix
      // treated a digit as a word character (as `\w`-based `\b` does), this
      // would have stopped matching and a live code would be persisted. This
      // test is the guard on that specific over-correction.
      //
      // Note the keyword itself survives: §13.6 destroys the *digit run*, not
      // the word that identified it. `PIN` carries no secret.
      expect(SmsSanitizer.sanitize('PIN1234').value, 'PIN[REDACTED]');
      expect(SmsSanitizer.sanitize('OTP445566 now').value, 'OTP[REDACTED] now');
    });

    test('multi-word Latin keywords still redact', () {
      expect(
        SmsSanitizer.sanitize('Your verification code is 903212').value,
        'Your verification code is [REDACTED]',
      );
      expect(
        SmsSanitizer.sanitize('one-time password: 778899').value,
        'one-time password: [REDACTED]',
      );
      expect(
        SmsSanitizer.sanitize('access code 4477 expires soon').value,
        'access code [REDACTED] expires soon',
      );
    });

    test('the KHA-54 decoy cases are untouched by the boundary fix', () {
      // Both of these are the original reason the sweep exists. A boundary
      // check applied at the wrong layer could easily have regressed them,
      // so they are re-asserted here rather than only in the KHA-54 file.
      expect(
        SmsSanitizer.sanitize('Your OTP for account 1234 is 567890').value,
        'Your OTP for account [REDACTED] is [REDACTED]',
      );
      expect(
        SmsSanitizer.sanitize(
          'Your verification code, valid for 5 minutes, is 903212',
        ).value,
        'Your verification code, valid for 5 minutes, is [REDACTED]',
      );
    });
  });

  group(
    'B4 — Arabic keywords still redact, including with clitics attached',
    () {
      // ## Why this group is the one that must not be skimmed
      //
      // Arabic is the product's primary locale (`docs/design.md` §3.1). It
      // attaches the definite article `ال` and possessive suffixes such as `ـك`
      // directly to the noun with **no space**, so an Arabic letter pressed
      // against a keyword is normal grammar, not evidence of a fragment.
      //
      // An ASCII `\b`, or a boundary rule that treated "any letter in any
      // script" as a blocker, would stop every one of these from matching — and
      // the failure mode there is a live PIN written to the database in
      // cleartext, which is silent and permanent. That is strictly worse than
      // the mangled-merchant-name bug being fixed.

      test('a bare Arabic keyword redacts', () {
        expect(
          SmsSanitizer.sanitize('رمز التحقق هو 123456').value,
          'رمز التحقق هو [REDACTED]',
        );
      });

      test(
        'the definite article prefix ال does not break the match — الرمز',
        () {
          // `الرمز` = "the code". The keyword `رمز` sits with the Arabic letter
          // `ل` immediately to its left. This redacted before the fix and must
          // still redact after it.
          expect(
            SmsSanitizer.sanitize('الرمز السري 4321').value,
            'الرمز السري [REDACTED]',
          );
        },
      );

      test('a possessive suffix does not break the match — رمزك', () {
        // `رمزك` = "your code": an Arabic letter immediately to the *right* of
        // the keyword. Covers the opposite boundary from `الرمز` above.
        expect(
          SmsSanitizer.sanitize('رمزك السري هو 4321').value,
          'رمزك السري هو [REDACTED]',
        );
      });

      test('the remaining Arabic keywords redact', () {
        expect(
          SmsSanitizer.sanitize('الرقم السري 4321').value,
          'الرقم السري [REDACTED]',
        );
        expect(
          SmsSanitizer.sanitize('كلمة المرور 778899').value,
          'كلمة المرور [REDACTED]',
        );
        expect(
          SmsSanitizer.sanitize('رمز الدخول 5566').value,
          'رمز الدخول [REDACTED]',
        );
        expect(
          SmsSanitizer.sanitize('رمز التفعيل 5566').value,
          'رمز التفعيل [REDACTED]',
        );
      });

      test(
        'Arabic keyword with an Arabic-Indic numeral code still redacts',
        () {
          // The digit family and the boundary check are independent rules, and
          // this is the intersection: an Arabic-script message with an
          // Arabic-Indic code, where both have to be right at once.
          const String arabicIndicCode = '١٢٣٤٥٦';
          expect(
            SmsSanitizer.sanitize('رمز التحقق هو $arabicIndicCode').value,
            'رمز التحقق هو [REDACTED]',
          );
        },
      );

      test(
        'Arabic punctuation IS a boundary, and does not prevent a match',
        () {
          // The Arabic comma `،` (U+060C) sits in the Arabic block but is not a
          // letter. `_boundaryClass` must classify it as `other`, not as an
          // Arabic letter — this pins that the range endpoints were not widened
          // to the whole U+0600-U+06FF block out of convenience.
          expect(
            SmsSanitizer.sanitize('عميلنا العزيز، رمز التحقق 123456').value,
            'عميلنا العزيز، رمز التحقق [REDACTED]',
          );
        },
      );
    },
  );

  group('B4 — the fix does not disturb the other §13 rules', () {
    test('a PAN inside a message containing a false-positive word is still '
        'redacted', () {
      // The boundary fix touches only the §13.6 keyword sweep. §13.4's PAN
      // rule has no keyword dependency and must be unaffected — including in
      // a message that previously tripped the false positive.
      final SanitizedSmsText out = SmsSanitizer.sanitize(
        'SPINNEYS purchase 4539 1488 0343 6467 SAR 45',
      );
      expect(out.panRedacted, isTrue);
      expect(out.value, 'SPINNEYS purchase ****6467 SAR 45');
    });

    test('an IBAN inside a message containing a false-positive word is still '
        'redacted', () {
      final SanitizedSmsText out = SmsSanitizer.sanitize(
        'ALPINE transfer from SA0380000000608010167519 done',
      );
      expect(out.value, 'ALPINE transfer from SA**…7519 done');
    });
  });
}

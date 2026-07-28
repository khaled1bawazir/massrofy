/// The **ADR-013 v1.1 (§13.1–§13.8)** testing obligations — the normative
/// redaction spec, promoted from a one-line-per-pattern sketch after KHA-54
/// showed that three separate under-redaction defects all fitted inside the
/// old wording.
///
/// Two of the fixtures here reproduce defects the solution-architect found
/// **while ratifying** the KHA-54 fix (architecture §8.1 **H-14**). Both are
/// the same failure mode KHA-54 gap 3 was: a full, live PAN or account number
/// surviving in cleartext, with `panRedacted` cheerfully reporting `false`.
///
/// ## Why the previous corpus missed them
///
/// This is the instructive part, and it generalises well beyond this file.
/// Every KHA-54 grouped-PAN fixture happened to write the card number with a
/// non-digit token immediately after it:
///
/// ```text
/// 'purchase 4111 1111 1111 1111 SAR 45'
///                                ^^^ this is the only reason it passed
/// ```
///
/// The implementation tested only the *maximal* separator-joined digit
/// sequence. `SAR` terminated that sequence at exactly the right place, so
/// the maximal sequence *was* the PAN and the check succeeded. Move the
/// currency code, or drop it, and the sequence becomes 18 digits, fails Luhn,
/// and the whole PAN is returned untouched:
///
/// ```text
/// 'purchase 4111 1111 1111 1111 45'   -> returned verbatim, PAN and all
/// ```
///
/// A corpus can be large, exact-output-asserted, and still test only the
/// shape it happened to be written in. §13.4's longest-window-first,
/// then-backtrack scan is the fix; these fixtures are what hold it in place.
///
/// ## Invisible characters are built from code points, never pasted
///
/// Several fixtures below turn on a NO-BREAK SPACE, a NARROW NO-BREAK SPACE,
/// a RIGHT-TO-LEFT MARK or a SOFT HYPHEN. Every one is written as
/// `String.fromCharCode(0x…)` rather than embedded literally, for the same
/// reason `SmsSanitizer` writes its character classes as escapes: a literal
/// would be invisible in review, indistinguishable from an ordinary space,
/// and silently destroyed by any tool that re-encodes the file. A test whose
/// meaning depends on a character nobody can see is a test that will
/// eventually be "fixed" by deleting the character.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/text/sms_sanitizer.dart';

/// A Luhn-valid 16-digit test PAN, chosen so that **no 3-digit window of its
/// first 12 digits also appears in its last 4**.
///
/// That property is what makes [expectPanBodyDestroyed] meaningful. The
/// classic `4111 1111 1111 1111` cannot be used here: §13.4 mandates
/// retaining the last four digits (`****1111`), and every 3-digit window of
/// that card is `111` — so "no window of the secret survives" is
/// unsatisfiable for it by construction, and the assertion would fail on
/// perfectly correct output.
const String testPan = '4539148803436467';
const String testPanLast4 = '6467';

// The §13.3 separator set and the §13.2 ignorables, by code point.
final String nbsp = String.fromCharCode(0x00A0);
final String narrowNbsp = String.fromCharCode(0x202F);
final String enDash = String.fromCharCode(0x2013);
final String rlm = String.fromCharCode(0x200F);
final String softHyphen = String.fromCharCode(0x00AD);

/// The test PAN in four groups, joined by [separator].
String groupedPan(String separator) =>
    <String>['4539', '1488', '0343', '6467'].join(separator);

/// Asserts that the redactable body of [pan] — everything except the last 4
/// digits, which §13.4 deliberately retains — is gone from [output].
///
/// Stronger than `isNot(contains(pan))`, which would pass on the same digits
/// merely split by a space.
void expectPanBodyDestroyed(String output, String pan) {
  final String body = pan.substring(0, pan.length - 4);
  for (int i = 0; i + 3 <= body.length; i++) {
    final String window = body.substring(i, i + 3);
    expect(
      output.contains(window),
      isFalse,
      reason:
          'the 3-digit run "$window" from the PAN "$pan" survived redaction '
          'in: $output',
    );
  }
}

/// Asserts that not one 3-digit window of [secret] survives in [output] —
/// for secrets where nothing at all is retained.
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
  group('§13.4 — the grouped-PAN scan backtracks (H-14 defect 1)', () {
    test('a grouped PAN followed immediately by another grouped number is '
        'still redacted — the exact case the old greedy scan let through', () {
      // The maximal digit-group sequence here is
      // "4539 1488 0343 6467 45" = 18 digits, which fails Luhn. The old
      // implementation gave up at that point and returned the text
      // untouched. §13.4 requires shrinking the window and trying again,
      // which finds the 16-digit PAN inside it.
      final SanitizedSmsText out = SmsSanitizer.sanitize(
        'purchase ${groupedPan(' ')} 45',
      );

      expect(out.value, 'purchase ****$testPanLast4 45');
      expect(
        out.panRedacted,
        isTrue,
        reason:
            'the schema flag must not record the absence of a PAN that was '
            'sitting in the row in cleartext',
      );
      expectPanBodyDestroyed(out.value, testPan);
    });

    test('a grouped number BEFORE the PAN is handled too — the PAN is found '
        'wherever in the sequence it sits', () {
      // "45 4539 1488 0343 6467" — 18 digits maximally, with the PAN as the
      // rightmost 16. The 14-digit window to its left is enumerated first
      // and fails Luhn, which is precisely the point: Luhn is what makes the
      // widened scan precise rather than merely aggressive.
      final SanitizedSmsText out = SmsSanitizer.sanitize(
        'ref 45 ${groupedPan(' ')} done',
      );

      expect(out.value, 'ref 45 ****$testPanLast4 done');
      expect(out.panRedacted, isTrue);
      expectPanBodyDestroyed(out.value, testPan);
    });

    test('hyphen-grouped, with a trailing group', () {
      final SanitizedSmsText out = SmsSanitizer.sanitize(
        'card ${groupedPan('-')}-99 charged',
      );

      expect(out.value, 'card ****$testPanLast4-99 charged');
      expect(out.panRedacted, isTrue);
      expectPanBodyDestroyed(out.value, testPan);
    });

    test(
      'a PAN separated by NBSP — an invisible separator is not a bypass',
      () {
        final SanitizedSmsText out = SmsSanitizer.sanitize(
          'purchase ${groupedPan(nbsp)} SAR 45',
        );

        expect(out.value, 'purchase ****$testPanLast4 SAR 45');
        expect(out.panRedacted, isTrue);
        expectPanBodyDestroyed(out.value, testPan);
      },
    );

    test(
      'narrow NBSP and en dash are separators too (§13.3, the full set)',
      () {
        final SanitizedSmsText narrow = SmsSanitizer.sanitize(
          'card ${groupedPan(narrowNbsp)} ok',
        );
        expect(narrow.value, 'card ****$testPanLast4 ok');
        expect(narrow.panRedacted, isTrue);

        final SanitizedSmsText dashed = SmsSanitizer.sanitize(
          'card ${groupedPan(enDash)} ok',
        );
        expect(dashed.value, 'card ****$testPanLast4 ok');
        expect(dashed.panRedacted, isTrue);
      },
    );
  });

  group('§13.2 — bidi controls inside a digit sequence are not a bypass', () {
    test('a RIGHT-TO-LEFT MARK between two groups of a card number does not '
        'defeat the grouped-PAN rule', () {
      // The realistic Arabic-template case, and why §13.2 exists at all:
      // sanitisation runs on the RAW body, before SmsTextNormalizer strips
      // bidi controls, so this file has to strip them itself. One U+200F
      // here splits the digit-group sequence in two, and without the §13.2
      // matching view the whole PAN survives.
      final SanitizedSmsText out = SmsSanitizer.sanitize(
        'شراء 4539 1488$rlm 0343 6467 SAR 45',
      );

      expect(out.panRedacted, isTrue);
      expectPanBodyDestroyed(out.value, testPan);
    });

    test('a soft hyphen inside a contiguous PAN does not defeat it either', () {
      final SanitizedSmsText out = SmsSanitizer.sanitize(
        'card 45391488${softHyphen}03436467 charged',
      );

      expect(out.panRedacted, isTrue);
      expectPanBodyDestroyed(out.value, testPan);
    });

    test('bidi marks OUTSIDE a redacted span survive — the stored text still '
        'looks like what the bank sent (AC-B1.2)', () {
      final String message =
          '$rlm'
          'شراء بمبلغ 152.75 ريال';
      final SanitizedSmsText out = SmsSanitizer.sanitize(message);

      expect(
        out.value,
        message,
        reason:
            'the ignorable characters are removed from the MATCHING view '
            'only; nothing was redacted here, so nothing may change',
      );
    });
  });

  group('§13.5 — grouped Saudi IBANs (H-14 defect 2)', () {
    test('the conventional print form is matched — it was not matched at all '
        'before', () {
      // 'SA03 8000 0000 6080 1016 7519' is how a Saudi IBAN is actually
      // printed and typed. The contiguous-only SA[digits]{22} pattern did
      // not match it, so the grouped form survived in full.
      final SanitizedSmsText out = SmsSanitizer.sanitize(
        'transfer to SA03 8000 0000 6080 1016 7519 completed',
      );

      expect(out.value, 'transfer to SA**…7519 completed');
      expectNoDigitOfSecretSurvives(out.value, '038000000060801016');
    });

    test('the contiguous form still works — the widening must not regress '
        'what already passed', () {
      final SanitizedSmsText out = SmsSanitizer.sanitize(
        'IBAN SA0380000000608010167519 ok',
      );

      expect(out.value, 'IBAN SA**…7519 ok');
    });

    test('hyphen- and NBSP-grouped IBANs are matched', () {
      expect(
        SmsSanitizer.sanitize('to SA03-8000-0000-6080-1016-7519 now').value,
        'to SA**…7519 now',
      );

      final String grouped = <String>[
        '03',
        '8000',
        '0000',
        '6080',
        '1016',
        '7519',
      ].join(nbsp);
      expect(
        SmsSanitizer.sanitize('to SA$grouped now').value,
        'to SA**…7519 now',
      );
    });

    test('an IBAN followed immediately by another number is still matched — '
        'the same backtracking hazard as the PAN case', () {
      final SanitizedSmsText out = SmsSanitizer.sanitize(
        'to SA03 8000 0000 6080 1016 7519 45 done',
      );

      expect(
        out.value,
        'to SA**…7519 45 done',
        reason:
            'the digit COUNT is what terminates the IBAN, not the next '
            'non-digit token — so a trailing number cannot hide it',
      );
      expectNoDigitOfSecretSurvives(out.value, '038000000060801016');
    });

    test('"SAR" is not an IBAN prefix — the currency code must survive', () {
      // Guards the over-redaction direction. `SA` is the first two letters
      // of `SAR`, which appears in essentially every message this app will
      // ever see.
      const String message = 'Purchase SAR 152.75 at EXTRA MART';

      expect(SmsSanitizer.sanitize(message).value, message);
    });
  });

  group('§13.4 precision — numbers that must SURVIVE', () {
    // ADR-013's required fixtures are not all about recall. A rule that
    // redacts everything is not "safe": it destroys transaction amounts and
    // reference numbers, and a destroyed reference number defeats ADR-017
    // D2's duplicate detection. These pin the other side.

    test('a grouped date is left alone', () {
      const String message = 'on 28-07-2026 14:32 at MERCHANT';
      final SanitizedSmsText out = SmsSanitizer.sanitize(message);

      expect(out.value, message);
      expect(out.panRedacted, isFalse);
    });

    test('a grouped reference number that is not Luhn-valid is left alone — '
        'this is what Luhn is FOR', () {
      // 16 digits, grouped exactly like a card number, but not Luhn-valid.
      // A blunt "redact every long number" rule would destroy it and break
      // ADR-017 D2, which uses the reference number as its dedup key.
      const String message = 'ref 1234 5678 9012 3456 posted';
      final SanitizedSmsText out = SmsSanitizer.sanitize(message);

      expect(out.value, message);
      expect(out.panRedacted, isFalse);
    });

    test('an amount is never fused across the full stop (§13.3 excludes "." '
        'deliberately)', () {
      const String message = 'Purchase 4539.1488 at SHOP';
      final SanitizedSmsText out = SmsSanitizer.sanitize(message);

      expect(
        out.value,
        message,
        reason:
            'including "." in the separator set would let two halves of an '
            'amount fuse into a PAN-shaped candidate and destroy a real '
            'transaction amount',
      );
    });

    test('a newline is not a separator either — fields are not fused', () {
      // Two 8-digit fields on separate lines. Joined, they are exactly the
      // Luhn-valid test PAN; §13.3 excludes newline precisely so that
      // unrelated fields cannot fuse into one.
      const String message = 'card:45391488\nref:03436467';
      final SanitizedSmsText out = SmsSanitizer.sanitize(message);

      expect(out.value, message);
      expect(out.panRedacted, isFalse);
    });

    test('a full-length SMS that is one enormous digit-group sequence is '
        'handled without blowing the ingestion budget', () {
      // §13.4's window enumeration is O(groups²). A 1600-character SMS of
      // nothing but two-digit groups is the worst input it can be given —
      // ~530 groups, ~140k windows — and it is the shape an adversarial or
      // simply strange message would take.
      //
      // No timing assertion here, because a wall-clock bound on a shared CI
      // runner is a flaky test pretending to be a guarantee. What this pins
      // is that the path terminates and stays correct; the cost is bounded
      // by the prefix-sum length check in `_findPanSpans`, which took the
      // measured worst case from 675 ms to 17 ms. A regression to
      // exponential behaviour would hang this test rather than slow it.
      final String message = List<String>.generate(530, (_) => '11').join(' ');

      final SanitizedSmsText out = SmsSanitizer.sanitize(message);

      expect(
        out.value,
        message,
        reason: 'no window of it is a Luhn-valid 13-19 digit number',
      );
      expect(out.panRedacted, isFalse);
    });

    test('two separators in a row do not join two numbers (§13.3)', () {
      const String message = 'a 45391488  03436467 b';
      final SanitizedSmsText out = SmsSanitizer.sanitize(message);

      expect(out.value, message);
      expect(out.panRedacted, isFalse);
    });
  });

  group(
    '§13.7 — the rule pack redacts its named group, or the whole match',
    () {
      test('a pattern declaring (?<secret>…) redacts only that group, leaving '
          'the amount next to it intact', () {
        final SanitizedSmsText out = SmsSanitizer.sanitize(
          'Code 4471 for SAR 25.00',
          extraRedactPatterns: <RegExp>[RegExp(r'Code (?<secret>\d{3,8})')],
        );

        expect(
          out.value,
          'Code [REDACTED] for SAR 25.00',
          reason:
              'the bank knows its own template, so it can point at the secret '
              'precisely instead of destroying the amount beside it',
        );
      });

      test('a pattern with no named group redacts the whole match', () {
        final SanitizedSmsText out = SmsSanitizer.sanitize(
          'Code 4471 for SAR 25.00',
          extraRedactPatterns: <RegExp>[RegExp(r'Code \d{3,8}')],
        );

        expect(out.value, '[REDACTED] for SAR 25.00');
      });

      test('an AMBIGUOUS named group falls back to the whole match — guessing '
          'the wrong occurrence would leave the real secret in place', () {
        // The captured text "4471" also appears earlier inside the match, so
        // its position cannot be recovered from the group's text alone. The
        // safe resolution is to destroy the lot.
        final SanitizedSmsText out = SmsSanitizer.sanitize(
          'ref 4471 code 4471 end',
          extraRedactPatterns: <RegExp>[
            RegExp(r'ref 4471 code (?<secret>\d{4})'),
          ],
        );

        expect(out.value, '[REDACTED] end');
      });

      test(
        'the generic passes still run first — a rule pack cannot switch them '
        'off by saying nothing',
        () {
          final SanitizedSmsText out = SmsSanitizer.sanitize(
            'purchase ${groupedPan(' ')} 45',
            extraRedactPatterns: <RegExp>[RegExp('never matches anything')],
          );

          expect(out.value, 'purchase ****$testPanLast4 45');
          expect(out.panRedacted, isTrue);
        },
      );
    },
  );
}

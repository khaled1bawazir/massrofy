/// **KHA-146 — the parser must carry what it read into the review queue.**
///
/// The defect, stated as the two cases this file keeps apart:
///
///  - **(b)** a rule's gate matched, its extraction regex matched, several
///    fields came out with values, and then ONE `requiredFields` entry was
///    missing. The message is correctly routed to Needs Review — and until
///    KHA-146 every value that HAD extracted was discarded on the way, so the
///    completion form started blank and the user retyped an amount, a merchant
///    and a card the app had already read correctly.
///  - **(a)** no rule recognised the message at all. Nothing was extracted, so
///    there is nothing honest to pre-fill and a blank form is correct.
///
/// Conflating those two is how "we understood nothing" would start pre-filling
/// a form, so both are asserted, in the same file, against the same bank.
///
/// ## NFR-M3
///
/// Every message body and every rule used here is **fabricated** — see
/// `test/support/kha146_synthetic_pack.dart`, which is shared with the
/// pipeline and widget tests so all three reason about the same fixture.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/text/sms_sanitizer.dart';
import 'package:massrofy/core/text/sms_text_normalizer.dart';
import 'package:massrofy/features/parsing/parse_outcome.dart';
import 'package:massrofy/features/parsing/partial_extraction.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_message_parser.dart';

import '../../support/kha146_synthetic_pack.dart';

const String _missingOneRequiredField = syntheticMissingOneRequiredField;
const String _complete = syntheticComplete;
const String _noRuleMatches = syntheticNoRuleMatches;

ParseOutcome _parse(RulePackMessageParser parser, String body) {
  final SanitizedSmsText sanitized = SmsSanitizer.sanitize(body);
  return parser.parse(
    sanitized: sanitized,
    normalizedBody: SmsTextNormalizer.normalize(sanitized.value),
    sender: syntheticSender,
  );
}

void main() {
  late RulePackMessageParser parser;

  setUp(() {
    parser = RulePackMessageParser(packs: <RulePack>[syntheticRulePack()]);
  });

  group('the fixture itself is sound', () {
    test('the same shape WITH the required field parses into a transaction — '
        'so a failure below is the missing field, not a broken rule', () {
      final ParseOutcome outcome = _parse(parser, _complete);

      expect(outcome, isA<ParsedMessage>());
      final ParsedMessage parsed = outcome as ParsedMessage;
      expect(parsed.fields.amount?.amount.toString(), '152.75');
      expect(parsed.fields.merchantRawText, 'SAMPLE MARKET 7');
      expect(parsed.fields.instrument?.maskedIdentifier, '****4821');
    });
  });

  group('case (b) — regex matched, requiredFields failed', () {
    test('routes to the review queue for the right reason, naming only the '
        'field that genuinely failed', () {
      final ParseOutcome outcome = _parse(parser, _missingOneRequiredField);

      expect(outcome, isA<UnparsedMessage>());
      final UnparsedMessage unparsed = outcome as UnparsedMessage;
      expect(unparsed.reason, UnparsedReason.requiredFieldMissing);
      expect(
        unparsed.missingFields,
        <String>['remainingBalance'],
        reason:
            'exactly one field failed. If this list grows, the fixture has '
            'drifted and the assertions below stop meaning what they say.',
      );
    });

    test('carries EVERY successfully-extracted field through — this is the '
        'defect, in one assertion', () {
      final UnparsedMessage unparsed =
          _parse(parser, _missingOneRequiredField) as UnparsedMessage;
      final PartialExtraction? partial = unparsed.partialExtraction;

      expect(
        partial,
        isNotNull,
        reason:
            'before KHA-146 this was discarded at the requiredFields check, '
            'and the completion form had nothing but raw text to work from',
      );
      expect(partial!.amountText, '152.75');
      expect(partial.currencyCode, 'SAR');
      expect(partial.merchantRawText, 'SAMPLE MARKET 7');
      expect(partial.instrumentKind, 'card');
      expect(
        partial.instrumentMaskedRef,
        '****4821',
        reason:
            'masked to last-4 by InstrumentMask before it could ever reach '
            'this object — there is no path here that holds a fuller '
            'identifier (NFR-S2)',
      );
      expect(partial.occurredAtUtc, isNotNull);
      expect(
        partial.transactionType,
        'pos_purchase',
        reason:
            'the "transaction type word" the message opened with. KHA-146 '
            'observed the user having to re-pick this from a 12-item dropdown '
            'for a message that stated it plainly.',
      );
      expect(partial.missingFields, <String>['remainingBalance']);
      expect(partial.hasAnyValue, isTrue);
    });

    test('the amount is the exact decimal the bank printed, not a rounded '
        'double (ADR-002)', () {
      final UnparsedMessage unparsed =
          _parse(parser, _missingOneRequiredField) as UnparsedMessage;

      expect(unparsed.partialExtraction!.amountText, '152.75');
      expect(
        double.tryParse(unparsed.partialExtraction!.amountText!),
        isNotNull,
        reason: 'sanity: it is still a number, just carried as exact text',
      );
    });

    test('the partial extraction never leaks an amount or a merchant into a '
        'log line (NFR-S4)', () {
      final UnparsedMessage unparsed =
          _parse(parser, _missingOneRequiredField) as UnparsedMessage;
      final String rendered = '${unparsed.partialExtraction}';

      expect(rendered, isNot(contains('152.75')));
      expect(rendered, isNot(contains('SAMPLE MARKET')));
      expect(rendered, isNot(contains('4821')));
    });
  });

  group('case (a) — no rule matched at all', () {
    test('still reaches the review queue (NFR-A7) but carries NOTHING to '
        'pre-fill, so the form is correctly blank', () {
      final ParseOutcome outcome = _parse(parser, _noRuleMatches);

      expect(outcome, isA<UnparsedMessage>());
      final UnparsedMessage unparsed = outcome as UnparsedMessage;
      expect(unparsed.reason, UnparsedReason.noRuleMatched);
      expect(
        unparsed.partialExtraction,
        isNull,
        reason:
            'nothing was ever extracted. A non-null value here — even an '
            'empty one — would make "we understood nothing" indistinguishable '
            'from "we understood most of it", and the form would start '
            'announcing a pre-fill it did not do.',
      );
    });

    test('a rule whose gate matches but whose extraction regex does not is '
        'also case (a)', () {
      // The gate is the word "purchase"; the extraction regex needs the full
      // shape. This body passes the first and fails the second — a partial
      // template change at the bank (risk R-4). Nothing was extracted, so
      // nothing is carried.
      final ParseOutcome outcome = _parse(
        parser,
        'purchase declined — please contact SYNTHBANK.',
      );

      final UnparsedMessage unparsed = outcome as UnparsedMessage;
      expect(unparsed.reason, UnparsedReason.extractionRegexFailed);
      expect(unparsed.partialExtraction, isNull);
    });
  });

  group('PartialExtraction survives the round trip through storage', () {
    test('encode then decode returns every value unchanged', () {
      final UnparsedMessage unparsed =
          _parse(parser, _missingOneRequiredField) as UnparsedMessage;
      final PartialExtraction original = unparsed.partialExtraction!;

      final PartialExtraction? restored = PartialExtraction.tryDecode(
        original.encode(),
      );

      expect(restored, isNotNull);
      expect(restored!.amountText, original.amountText);
      expect(restored.currencyCode, original.currencyCode);
      expect(restored.merchantRawText, original.merchantRawText);
      expect(restored.instrumentKind, original.instrumentKind);
      expect(restored.instrumentMaskedRef, original.instrumentMaskedRef);
      expect(restored.occurredAtUtc, original.occurredAtUtc);
      expect(restored.transactionType, original.transactionType);
      expect(restored.missingFields, original.missingFields);
    });

    test('an unreadable stored value decodes to null rather than throwing — a '
        'blank form costs typing, a half-decoded one costs a wrong total', () {
      expect(PartialExtraction.tryDecode(null), isNull);
      expect(PartialExtraction.tryDecode(''), isNull);
      expect(PartialExtraction.tryDecode('not json at all'), isNull);
      expect(PartialExtraction.tryDecode('[1,2,3]'), isNull);
      expect(
        PartialExtraction.tryDecode('{"v":99,"amount":"1.00"}'),
        isNull,
        reason:
            'a future encoding is not decoded best-effort: a newer build could '
            'give a key a different meaning, and reinterpreting it as this '
            'version\'s meaning is how a currency ends up in an amount field',
      );
    });

    test('an amount without its currency is dropped, not paired with whatever '
        'the form defaults to (NFR-A5)', () {
      final PartialExtraction? restored = PartialExtraction.tryDecode(
        '{"v":1,"amount":"152.75"}',
      );

      expect(restored, isNotNull);
      expect(restored!.amountText, isNull);
      expect(restored.currencyCode, isNull);
    });

    test('an empty string in storage reads as unknown, never as a value '
        '(AC-B1.3)', () {
      final PartialExtraction? restored = PartialExtraction.tryDecode(
        '{"v":1,"merchant":"","transactionType":"   "}',
      );

      expect(restored!.merchantRawText, isNull);
      expect(restored.transactionType, isNull);
      expect(restored.hasAnyValue, isFalse);
    });
  });
}

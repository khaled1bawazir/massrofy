/// **The P2 exit check** (`docs/build-plan.md` §P2):
///
/// > *"the synthetic fixture corpus covering both banks and all nine observed
/// > message types parses to expected output in automated tests; no fixture is
/// > silently discarded (NFR-A7)."*
///
/// Both halves are asserted here, and the second half is the one that is easy
/// to get wrong. A test suite that only checks "did the good messages parse?"
/// will happily stay green while a message disappears — which is precisely
/// the failure this product cannot tolerate, because the user's trust rests
/// on "nothing is missing" (Linear KHA-22).
///
/// The bundled rule pack is loaded from the **real asset file**, not from an
/// inline copy, so a broken regex or a typo'd transform name in
/// `assets/rule_packs/sa-core.json` fails this suite rather than surfacing on
/// a device.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/text/sms_sanitizer.dart';
import 'package:massrofy/core/text/sms_text_normalizer.dart';
import 'package:massrofy/features/parsing/parse_outcome.dart';
import 'package:massrofy/features/parsing/parsed_fields.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_loader.dart';
import 'package:massrofy/features/parsing/rule_pack_message_parser.dart';

import '../../fixtures/synthetic_sms_corpus.dart';

/// The nine message types PRD §3.4 observed. Named here as a constant so the
/// "all nine, for both banks" claim in the exit check is asserted rather than
/// eyeballed.
const Set<String> _nineObservedMessageTypes = <String>{
  'pos_purchase',
  'online_purchase',
  'transfer_out',
  'transfer_in',
  'bill_payment',
  'card_repayment',
  'fee',
  'account_debit',
  'installment',
};

void main() {
  late RulePack pack;
  late RulePackMessageParser parser;

  setUpAll(() {
    // Read the asset straight off disk. `flutter_test` can load assets via
    // rootBundle, but that requires the binding and an asset manifest; a
    // plain file read keeps this suite a fast pure-Dart test while still
    // exercising the exact bytes that ship in the APK.
    final String json = File(
      'assets/rule_packs/sa-core.json',
    ).readAsStringSync();
    pack = RulePackLoader.parse(json);
    parser = RulePackMessageParser(packs: <RulePack>[pack]);
  });

  ParseOutcome run(SmsFixture fixture) {
    // Mirrors the production pipeline's ordering exactly (ADR-006 data flow):
    // resolve redaction patterns from the sender, sanitise, normalise, parse.
    final List<RegExp> redact = parser.redactionPatternsForSender(
      fixture.sender,
    );
    final SanitizedSmsText sanitized = SmsSanitizer.sanitize(
      fixture.body,
      extraRedactPatterns: redact,
    );
    return parser.parse(
      sanitized: sanitized,
      normalizedBody: SmsTextNormalizer.normalize(sanitized.value),
      sender: fixture.sender,
    );
  }

  group('bundled rule pack', () {
    test('loads, and declares both sampled banks', () {
      expect(pack.packId, 'sa-core');
      expect(pack.schemaVersion, RulePackLoader.supportedSchemaVersion);
      expect(pack.banks.map((BankRule b) => b.bankId).toSet(), <String>{
        'bank-aljazira',
        'd360',
      });
    });

    test('every bank covers all nine observed message types (PRD §3.4)', () {
      for (final BankRule bank in pack.banks) {
        final Set<String> covered = bank.messageRules
            .where((MessageRule r) => r.intent == RuleIntent.transaction)
            .map((MessageRule r) => r.messageType)
            .toSet();
        expect(
          covered,
          containsAll(_nineObservedMessageTypes),
          reason:
              'bank "${bank.bankId}" is missing rules for '
              '${_nineObservedMessageTypes.difference(covered)}',
        );
      }
    });

    test('every bank can recognise OTP, marketing and balance noise', () {
      for (final BankRule bank in pack.banks) {
        final Set<String> ignored = bank.messageRules
            .where((MessageRule r) => r.intent == RuleIntent.ignore)
            .map((MessageRule r) => r.messageType)
            .toSet();
        expect(
          ignored,
          containsAll(<String>{'otp', 'marketing', 'balance_info'}),
          reason: 'bank "${bank.bankId}" cannot classify all noise types',
        );
      }
    });

    test('ignore rules outrank every transaction rule (AC-A2.1 ordering)', () {
      // The bug this guards against is specific and it is the worst one in
      // the classifier: an OTP whose text happens to contain a transaction
      // keyword being turned into a transaction. Rules are pre-sorted by
      // the loader, so asserting the *minimum* ignore priority exceeds the
      // *maximum* transaction priority proves no reordering can produce it.
      for (final BankRule bank in pack.banks) {
        final Iterable<int> ignorePriorities = bank.messageRules
            .where((MessageRule r) => r.intent == RuleIntent.ignore)
            .map((MessageRule r) => r.priority);
        final Iterable<int> txPriorities = bank.messageRules
            .where((MessageRule r) => r.intent == RuleIntent.transaction)
            .map((MessageRule r) => r.priority);
        expect(
          ignorePriorities.reduce((int a, int b) => a < b ? a : b),
          greaterThan(txPriorities.reduce((int a, int b) => a > b ? a : b)),
          reason: 'bank "${bank.bankId}"',
        );
      }
    });
  });

  group('NFR-A7 — nothing is silently discarded', () {
    // This runs over EVERY fixture, including the deliberately-unparseable
    // ones. There is no fifth outcome; `ParseOutcome` is sealed so the switch
    // below would not compile if one were added without a decision here.
    for (final SmsFixture fixture in allFixtures) {
      test('${fixture.id} lands in exactly one defined outcome', () {
        final ParseOutcome outcome = run(fixture);

        final String landedIn = switch (outcome) {
          NotFinancialSender() => 'discarded_non_financial_sender',
          IgnoredMessage() => 'counter_row_no_body',
          ParsedMessage() => 'transaction',
          UnparsedMessage() => 'review_queue',
        };

        // Restating the invariant in the assertion rather than only in a
        // comment: a financial message is a transaction or a review item.
        // Never nothing.
        if (fixture.expect != ExpectedOutcome.notFinancial) {
          expect(
            landedIn,
            anyOf('transaction', 'review_queue', 'counter_row_no_body'),
            reason:
                'a message from a known financial sender vanished — this is '
                'a defect by AC-A4.4, not a tolerable edge case',
          );
        }
      });
    }
  });

  group('Bank Aljazira (Arabic templates)', () {
    for (final SmsFixture fixture in aljaziraFixtures) {
      test(fixture.id, () => _assertFixture(fixture, run(fixture)));
    }
  });

  group('D360 (English templates)', () {
    for (final SmsFixture fixture in d360Fixtures) {
      test(fixture.id, () => _assertFixture(fixture, run(fixture)));
    }
  });

  group('non-financial senders (AC-A2.3, NFR-P4)', () {
    for (final SmsFixture fixture in nonFinancialFixtures) {
      test(fixture.id, () => _assertFixture(fixture, run(fixture)));
    }
  });

  group('classifier behaviour that only shows up in combination', () {
    test('AC-A2.4 — a genuine purchase produces exactly one transaction, and '
        'the same body from a lookalike sender produces none', () {
      const SmsFixture genuine = SmsFixture(
        id: 'x',
        sender: 'D360',
        body:
            'D360: Purchase of SAR 89.00 with Mada Debit Card ending 4472 '
            'at BALAD COFFEE ROASTERS on 28/07/2026 15:10',
        expect: ExpectedOutcome.parsed,
      );
      expect(run(genuine), isA<ParsedMessage>());

      const SmsFixture impostor = SmsFixture(
        id: 'y',
        sender: 'D360Rewards',
        body:
            'D360: Purchase of SAR 89.00 with Mada Debit Card ending 4472 '
            'at BALAD COFFEE ROASTERS on 28/07/2026 15:10',
        expect: ExpectedOutcome.notFinancial,
      );
      expect(run(impostor), isA<NotFinancialSender>());
    });

    test(
      'the FX fee is never folded into the spend amount (KHA-19, PRD §3.4)',
      () {
        final ParsedMessage parsed =
            run(d360Fixtures.firstWhere((SmsFixture f) => f.id.contains('fx')))
                as ParsedMessage;
        // 120.00 USD purchase; 450.12 SAR converted; 11.25 SAR fee. The
        // failure this pins is "amount == 461.37" — fee silently added to
        // the purchase, which would overstate the merchant's charge and hide
        // the fee from every report.
        expect(parsed.fields.amount!.toCanonicalString(), '120');
        expect(parsed.fields.convertedAmount!.toCanonicalString(), '450.12');
        expect(parsed.fields.feeAmount!.toCanonicalString(), '11.25');
        expect(parsed.fields.feeAmount!.currencyCode, 'SAR');
      },
    );

    test(
      'card repayment does not count as spend (US-B10/B11, architecture §4.2)',
      () {
        for (final SmsFixture fixture in <SmsFixture>[
          aljaziraFixtures.firstWhere(
            (SmsFixture f) => f.id.contains('card-repayment'),
          ),
          d360Fixtures.firstWhere(
            (SmsFixture f) => f.id.contains('card-repayment'),
          ),
        ]) {
          final ParsedMessage parsed = run(fixture) as ParsedMessage;
          expect(parsed.affectsSpend, isFalse, reason: fixture.id);
          // …and it links the card to the account that settles it. This is
          // the only automatic source of that link (AC-B14.1).
          expect(parsed.fields.settlementInstrument, isNotNull);
          expect(parsed.fields.instrument!.kind, 'card');
          expect(parsed.fields.settlementInstrument!.kind, 'account');
        }
      },
    );

    test('AC-B1.3 — an absent field is null, never zero or blank', () {
      final ParsedMessage bare =
          run(
                aljaziraFixtures.firstWhere(
                  (SmsFixture f) => f.id.contains('bare-account-debit'),
                ),
              )
              as ParsedMessage;
      // A bare debit names no merchant and no counterparty. The temptation
      // is to default these to ''; that would later normalise into a
      // merchant key of '' and match every other blank merchant.
      expect(bare.fields.merchantRawText, isNull);
      expect(bare.fields.counterpartyName, isNull);
      expect(bare.fields.referenceNumber, isNull);
      expect(bare.fields.feeAmount, isNull);
    });

    test(
      'AC-A4.2 — a matched rule with a missing required field goes to review '
      'with the rule identified, not to a zero-amount transaction',
      () {
        final UnparsedMessage outcome =
            run(
                  aljaziraFixtures.firstWhere(
                    (SmsFixture f) => f.id.contains('missing-amount'),
                  ),
                )
                as UnparsedMessage;
        expect(outcome.reason, UnparsedReason.extractionRegexFailed);
        expect(outcome.rule?.bankId, 'bank-aljazira');
      },
    );

    test('no rule matched at a known bank still names the bank, so the review '
        'item is attributable (R-4 diagnosability)', () {
      final UnparsedMessage outcome =
          run(
                aljaziraFixtures.firstWhere(
                  (SmsFixture f) => f.id.contains('unknown-template'),
                ),
              )
              as UnparsedMessage;
      expect(outcome.reason, UnparsedReason.noRuleMatched);
      expect(outcome.rule?.bankId, 'bank-aljazira');
      expect(outcome.rule?.messageType, 'unknown');
    });
  });

  group('NFR-M3 — the corpus contains no real bank SMS', () {
    test('this is a process control, restated as a test that fails loudly', () {
      // There is no automated way to prove a string was invented. What CAN
      // be asserted is that every fixture uses the invented account suffixes
      // and reference numbers this file declares — so a future edit that
      // pastes in a real message, with real digits, breaks a test whose name
      // says exactly why that is forbidden.
      const Set<String> inventedIdentifiers = <String>{
        '4821',
        '9013',
        '3388',
        '4472',
        '8821',
        '1157',
      };
      for (final SmsFixture fixture in allFixtures) {
        if (fixture.instrumentMasked == null) continue;
        final String last4 = fixture.instrumentMasked!.replaceAll('*', '');
        expect(
          inventedIdentifiers,
          contains(last4),
          reason:
              'fixture "${fixture.id}" uses an identifier that is not one of '
              'this corpus\'s invented ones. If this is a real bank SMS, it '
              'must not be committed (NFR-M3).',
        );
      }
    });
  });
}

/// Asserts one fixture's full expectation set against one outcome.
///
/// Every comparison is an exact literal. `isNotNull` and `contains` are
/// deliberately avoided for values: a corpus whose assertions are loose is a
/// corpus that goes green while the parser reports 1520.00 instead of 152.00.
void _assertFixture(SmsFixture fixture, ParseOutcome outcome) {
  switch (fixture.expect) {
    case ExpectedOutcome.notFinancial:
      expect(outcome, isA<NotFinancialSender>(), reason: fixture.id);

    case ExpectedOutcome.ignored:
      expect(outcome, isA<IgnoredMessage>(), reason: fixture.id);
      final IgnoredMessage ignored = outcome as IgnoredMessage;
      expect(ignored.rule.ruleId, fixture.ruleId);
      expect(ignored.rule.messageType, fixture.messageType);
      expect(ignored.classification, fixture.classification);

    case ExpectedOutcome.unparsed:
      expect(outcome, isA<UnparsedMessage>(), reason: fixture.id);

    case ExpectedOutcome.parsed:
      expect(outcome, isA<ParsedMessage>(), reason: fixture.id);
      final ParsedMessage parsed = outcome as ParsedMessage;
      final ParsedFields f = parsed.fields;

      expect(
        parsed.rule.ruleId,
        fixture.ruleId,
        reason: '${fixture.id} ruleId',
      );
      expect(parsed.rule.messageType, fixture.messageType);
      expect(parsed.rule.bankId, isNotEmpty);
      expect(parsed.direction, fixture.direction);
      expect(parsed.affectsSpend, fixture.affectsSpend);

      expect(f.amount?.toCanonicalString(), fixture.amount);
      expect(f.amount?.currencyCode, fixture.currency);
      expect(f.convertedAmount?.toCanonicalString(), fixture.convertedAmount);
      expect(f.convertedAmount?.currencyCode, fixture.convertedCurrency);
      expect(f.feeAmount?.toCanonicalString(), fixture.feeAmount);
      expect(f.feeAmount?.currencyCode, fixture.feeCurrency);
      expect(f.exchangeRate, fixture.exchangeRate);
      expect(f.remainingBalance?.toCanonicalString(), fixture.remainingBalance);

      expect(f.merchantRawText, fixture.merchant);
      expect(f.instrument?.maskedIdentifier, fixture.instrumentMasked);
      expect(f.instrument?.kind, fixture.instrumentKind);
      expect(f.instrument?.network, fixture.instrumentNetwork);
      expect(f.instrument?.cardType, fixture.instrumentCardType);
      expect(
        f.settlementInstrument?.maskedIdentifier,
        fixture.settlementMasked,
      );

      expect(
        f.occurredAtUtc?.toIso8601String(),
        fixture.occurredAtUtc,
        reason: '${fixture.id}: Asia/Riyadh (+03:00) interpretation',
      );
      expect(f.referenceNumber, fixture.referenceNumber);
      expect(f.counterpartyName, fixture.counterpartyName);
      expect(f.counterpartyBankName, fixture.counterpartyBankName);
      expect(f.billerCode, fixture.billerCode);
      expect(f.invoiceNumber, fixture.invoiceNumber);
  }
}

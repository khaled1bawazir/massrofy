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
import 'package:massrofy/features/ledger/transaction_types.dart';
import 'package:massrofy/features/parsing/parse_outcome.dart';
import 'package:massrofy/features/parsing/parsed_fields.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_loader.dart';
import 'package:massrofy/features/parsing/rule_pack_message_parser.dart';

import '../../fixtures/synthetic_sms_corpus.dart';

/// The banks whose **message templates** were sampled in PRD §3.4, and which
/// therefore owe a full set of `messageRules` — all nine observed transaction
/// types and all three noise types.
const Set<String> _fullyTemplatedBanks = <String>{'bank-aljazira', 'd360'};

/// The banks KHA-136 templated from a **live structural sampling round**, and
/// what each one is held to.
///
/// ## Why this set exists rather than "everything with rules owes nine types"
///
/// The filter this suite used to apply was "has any `messageRules`", which
/// meant the first rule a bank gained immediately put it on the hook for all
/// nine PRD §3.4 message types. That is the right bar for a bank whose whole
/// template set was sampled, and the wrong bar for these four: on 2026-07-30
/// the human described the shapes of the messages **they actually had**, which
/// was one type for `nera`, three for `stc-bank`, two for `sab`, and — for
/// `al-rajhi` — an OTP and no transaction at all.
///
/// Meeting a nine-type bar for those banks would mean inventing seven
/// templates from imagination, and a guessed *extraction* regex is the single
/// most dangerous thing in this repository: it silently writes a **wrong
/// amount**, where a missing rule merely produces a review item the user can
/// see and complete (AC-A6.5). KHA-136 exists precisely to stop that.
///
/// So the bar is per-bank and exact — not "at least these", but **these and
/// nothing else**. Adding a type without recording it here fails; quietly
/// dropping one fails too. That keeps this an assertion rather than an
/// exemption.
const Map<String, ({Set<String> transactionTypes, Set<String> ignoreTypes})>
_partiallyTemplatedBanks =
    <String, ({Set<String> transactionTypes, Set<String> ignoreTypes})>{
      // One card-purchase type observed. No noise sample at all, so no ignore
      // rule: keywords guessed for an ignore rule either never fire, or fire
      // on something that should have been a transaction.
      'nera': (
        transactionTypes: <String>{'pos_purchase'},
        ignoreTypes: <String>{},
      ),
      // An OTP and nothing else. The transaction gap is deliberate and is the
      // reason this map is a map rather than a list of names.
      'al-rajhi': (transactionTypes: <String>{}, ignoreTypes: <String>{'otp'}),
      // Inward SARIE transfer, transfer out, and the P2P "Pay X" payment
      // (which is also a `transfer_out`), plus the two OTP shapes.
      'stc-bank': (
        transactionTypes: <String>{'transfer_in', 'transfer_out'},
        ignoreTypes: <String>{'otp'},
      ),
      // The bilingual bank: one purchase type in two languages, plus an
      // incoming-transfer deposit and a biometric-login notification.
      'sab': (
        transactionTypes: <String>{'pos_purchase', 'transfer_in'},
        ignoreTypes: <String>{'security_notification'},
      ),
    };

/// The banks that still have a confirmed sender and **no templates at all**.
///
/// That is a complete, shippable state per AC-A6.5 — the message still reaches
/// the review queue with its sanitised text — not a stub. `saib` is here
/// because no message of any kind was observed for it.
const Set<String> _senderOnlyBanks = <String>{'saib'};

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

  /// Every bank that declares at least one message rule.
  Iterable<BankRule> templatedBanks() =>
      pack.banks.where((BankRule b) => b.messageRules.isNotEmpty);

  Set<String> typesOf(BankRule bank, RuleIntent intent) => bank.messageRules
      .where((MessageRule r) => r.intent == intent)
      .map((MessageRule r) => r.messageType)
      .toSet();

  BankRule bankById(String bankId) =>
      pack.banks.firstWhere((BankRule b) => b.bankId == bankId);

  group('bundled rule pack', () {
    test('every bank is deliberately classified as fully templated, partially '
        'templated, or sender-only', () {
      // The point of this assertion: a bank cannot drift between categories
      // unnoticed. Emptying a sampled bank's rules, or giving a sender-only
      // bank its first rule, must be a decision recorded in this file rather
      // than something that silently changes which checks below apply.
      expect(
        templatedBanks().map((BankRule b) => b.bankId).toSet(),
        _fullyTemplatedBanks.union(_partiallyTemplatedBanks.keys.toSet()),
        reason:
            'a bank gained or lost its templates without being reclassified '
            'here — which would silently change the bar it is held to',
      );
      for (final String bankId in _senderOnlyBanks) {
        expect(
          bankById(bankId).messageRules,
          isEmpty,
          reason:
              'no message sample exists for "$bankId". Zero rules is the '
              'correct state (AC-A6.5): the message still reaches Needs '
              'Review. A guessed template would silently write a wrong '
              'amount instead.',
        );
      }
    });

    test('loads, and declares every configured bank', () {
      expect(pack.packId, 'sa-core');
      expect(pack.schemaVersion, RulePackLoader.supportedSchemaVersion);
      expect(
        pack.banks.map((BankRule b) => b.bankId).toSet(),
        _fullyTemplatedBanks
            .union(_partiallyTemplatedBanks.keys.toSet())
            .union(_senderOnlyBanks),
        reason:
            'the pack must declare all seven banks the reporting user '
            'actually receives SMS from (KHA-128)',
      );
    });

    test('every sampled bank covers all nine observed message types '
        '(PRD §3.4)', () {
      for (final String bankId in _fullyTemplatedBanks) {
        final Set<String> covered = typesOf(
          bankById(bankId),
          RuleIntent.transaction,
        );
        expect(
          covered,
          containsAll(_nineObservedMessageTypes),
          reason:
              'bank "$bankId" is missing rules for '
              '${_nineObservedMessageTypes.difference(covered)}',
        );
      }
    });

    test('every sampled bank can recognise OTP, marketing and balance '
        'noise', () {
      for (final String bankId in _fullyTemplatedBanks) {
        expect(
          typesOf(bankById(bankId), RuleIntent.ignore),
          containsAll(<String>{'otp', 'marketing', 'balance_info'}),
          reason: 'bank "$bankId" cannot classify all noise types',
        );
      }
    });

    test('each KHA-136 bank covers exactly the message types that were '
        'actually observed for it — no more, no fewer', () {
      // Exact set equality in both directions, deliberately. `containsAll`
      // would let a template invented from imagination slip in beside the
      // observed ones, which is the failure mode KHA-136 was opened to
      // prevent; and it would let an observed one be deleted.
      _partiallyTemplatedBanks.forEach((
        String bankId,
        ({Set<String> transactionTypes, Set<String> ignoreTypes}) expected,
      ) {
        final BankRule bank = bankById(bankId);
        expect(
          typesOf(bank, RuleIntent.transaction),
          expected.transactionTypes,
          reason:
              '"$bankId" transaction coverage changed. If a real sample '
              'arrived, update the map and add a pinned fixture; if not, the '
              'new rule is a guess and must not ship.',
        );
        expect(
          typesOf(bank, RuleIntent.ignore),
          expected.ignoreTypes,
          reason: '"$bankId" ignore coverage changed',
        );
      });
    });

    test('ignore rules outrank every transaction rule (AC-A2.1 ordering)', () {
      // The bug this guards against is specific and it is the worst one in
      // the classifier: an OTP whose text happens to contain a transaction
      // keyword being turned into a transaction. Rules are pre-sorted by
      // the loader, so asserting the *minimum* ignore priority exceeds the
      // *maximum* transaction priority proves no reordering can produce it.
      //
      // Both lists are checked for emptiness first: a bank may legitimately
      // have only ignore rules (`al-rajhi` — an OTP sample and no transaction
      // sample) or only transaction rules (`nera`), and `reduce` throws on an
      // empty iterable. There is no ordering to get wrong when there is only
      // one kind of rule.
      for (final BankRule bank in templatedBanks()) {
        final List<int> ignorePriorities = bank.messageRules
            .where((MessageRule r) => r.intent == RuleIntent.ignore)
            .map((MessageRule r) => r.priority)
            .toList();
        final List<int> txPriorities = bank.messageRules
            .where((MessageRule r) => r.intent == RuleIntent.transaction)
            .map((MessageRule r) => r.priority)
            .toList();
        if (ignorePriorities.isEmpty || txPriorities.isEmpty) continue;
        expect(
          ignorePriorities.reduce((int a, int b) => a < b ? a : b),
          greaterThan(txPriorities.reduce((int a, int b) => a > b ? a : b)),
          reason: 'bank "${bank.bankId}"',
        );
      }
    });

    test('every ignore rule sits in the high-priority band, so a bank with '
        'no transaction rules today is still safe when it gets one', () {
      // The per-bank ordering check above is vacuous for a bank that has only
      // ignore rules — and that is exactly when an ignore rule written at a
      // low priority would look fine and then be outranked by the first
      // transaction rule someone adds later. Pinning the band closes that.
      for (final BankRule bank in pack.banks) {
        for (final MessageRule rule in bank.messageRules) {
          if (rule.intent != RuleIntent.ignore) continue;
          expect(
            rule.priority,
            greaterThanOrEqualTo(880),
            reason:
                '"${rule.ruleId}" is an ignore rule below the 880-910 band '
                'every other one in this pack occupies',
          );
        }
      }
    });

    test('every transaction rule names a type this build understands', () {
      // A `messageType` outside the closed vocabulary is not a load error —
      // §5.2 forward-compatibility requires an unknown type to degrade
      // gracefully — but for a BUNDLED rule it is a typo, and a silent one:
      // an unknown type is excluded from spend totals, so a real purchase
      // would be recorded, listed, and invisible in the only number the
      // product exists to show.
      for (final BankRule bank in pack.banks) {
        for (final MessageRule rule in bank.messageRules) {
          if (rule.intent != RuleIntent.transaction) continue;
          expect(
            TransactionType.isKnown(rule.messageType),
            isTrue,
            reason:
                '"${rule.ruleId}" declares messageType '
                '"${rule.messageType}", which is not in TransactionType.all',
          );
        }
      }
    });

    test('rule ids are unique across the whole pack', () {
      // A rule id is what a review item, a stored transaction and the
      // parser-health panel all name. Two rules sharing one makes every such
      // report ambiguous.
      final List<String> ids = <String>[
        for (final BankRule bank in pack.banks)
          for (final MessageRule rule in bank.messageRules) rule.ruleId,
      ];
      expect(ids.toSet(), hasLength(ids.length));
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

  group('nera (KHA-136, English label:value)', () {
    for (final SmsFixture fixture in neraFixtures) {
      test(fixture.id, () => _assertFixture(fixture, run(fixture)));
    }
  });

  group('AlRajhi (KHA-136, OTP only — no transaction sample yet)', () {
    for (final SmsFixture fixture in alRajhiFixtures) {
      test(fixture.id, () => _assertFixture(fixture, run(fixture)));
    }
  });

  group('STC Bank (KHA-136, English label-per-line)', () {
    for (final SmsFixture fixture in stcBankFixtures) {
      test(fixture.id, () => _assertFixture(fixture, run(fixture)));
    }
  });

  group('SAIB (KHA-136, sender-only by design)', () {
    for (final SmsFixture fixture in saibFixtures) {
      test(fixture.id, () => _assertFixture(fixture, run(fixture)));
    }
  });

  group('SAB (KHA-136, bilingual)', () {
    for (final SmsFixture fixture in sabFixtures) {
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

    test('KHA-136 — an STC "Pay X" and its own OTP are ONE transaction, not '
        'two', () {
      // The defect this pins is a doubled amount, which is the worst kind
      // this app can produce because it looks entirely plausible in a list.
      // One logical payment arrives as two SMS; the OTP half quotes the same
      // payee, the same amount and the same reference. Both are fed here, in
      // the order a phone would deliver them.
      final ParseOutcome payment = run(
        stcBankFixtures.firstWhere(
          (SmsFixture f) =>
              f.id.contains('p2p-payment') && !f.id.contains('otp'),
        ),
      );
      final ParseOutcome otpHalf = run(
        stcBankFixtures.firstWhere(
          (SmsFixture f) => f.id.contains('p2p-payment-otp'),
        ),
      );

      expect(payment, isA<ParsedMessage>());
      expect(
        (payment as ParsedMessage).fields.amount!.toCanonicalString(),
        '75',
      );

      expect(
        otpHalf,
        isA<IgnoredMessage>(),
        reason:
            'the OTP half names an amount and a payee. If it ever parses, '
            'this payment is counted twice and the period total is wrong by '
            'exactly its value.',
      );
      expect((otpHalf as IgnoredMessage).rule.ruleId, 'stc-payment-otp');
    });

    test('every rule in the pack signs and classifies its type the way the '
        'ledger expects', () {
      // The one kind of mistake in a rule pack that silently corrupts a real
      // total rather than producing a visible failure: a credit written as a
      // debit, or an incoming transfer flagged as spend.
      //
      // The oracle is deliberately NOT this file's own opinion and not the
      // fixture's declared expectation either — it is
      // `TransactionType.creditTypes` / `nonSpendTypes`, which is what the
      // ledger layer and the manual-entry form use. If the pack and the
      // ledger ever disagree about what a `transfer_in` is, one of them is
      // wrong about the user's money; this makes them agree by construction.
      //
      // It runs over EVERY parsed fixture in the corpus, not only the new
      // banks, so an old rule cannot drift either.
      for (final SmsFixture fixture in allFixtures) {
        if (fixture.expect != ExpectedOutcome.parsed) continue;
        final ParsedMessage parsed = run(fixture) as ParsedMessage;
        final String type = parsed.rule.messageType;

        expect(
          parsed.direction,
          TransactionType.creditTypes.contains(type) ? 'credit' : 'debit',
          reason: '${fixture.id}: "$type" has the wrong sign',
        );
        expect(
          parsed.affectsSpend,
          !TransactionType.nonSpendTypes.contains(type),
          reason:
              '${fixture.id}: "$type" disagrees with the ledger about '
              'whether it is spend. An incoming transfer, a salary, a cash '
              'withdrawal and a card repayment are not spend (US-B10/B11, '
              'AC-B10.1/2); a purchase, an outgoing payment and a refund '
              'are — a refund because it reduces the total, not because it '
              'adds to it.',
        );
      }
    });

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
        // KHA-136: one invented suffix per newly-templated bank, so a real
        // one pasted in later stands out here instead of blending in.
        '6034', // nera card
        '5566', // STC Bank account
        '7788', // SAB card
        '1122', // SAB account
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

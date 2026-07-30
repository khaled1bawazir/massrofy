/// The synthetic bank KHA-146's tests are built around, in one place.
///
/// Shared by the parser test, the pipeline test and the widget test so all
/// three reason about **the same** rule and the same message shapes. If the
/// fixture drifts, it drifts for all of them at once, rather than one file
/// quietly proving something about a rule the others no longer use.
///
/// ## NFR-M3 — everything here is fabricated
///
/// `SYNTHBANK` is not a real institution. No real bank SMS is reproduced,
/// quoted or paraphrased from any device. The bodies are merely bank-*shaped*:
/// a type word, a card, a merchant, an amount, a date and a balance — which is
/// the structure KHA-146's live evidence describes, without reproducing it.
///
/// ## Why the rule requires the balance
///
/// [syntheticMissingOneRequiredField] omits exactly one required field, and it
/// is the LAST thing the template prints. That is the experimental design: it
/// is the only field that can fail, so anything else still blank downstream is
/// the defect under test rather than a fixture artefact.
library;

import 'package:massrofy/features/parsing/rule_pack.dart';

/// The sender id the synthetic bank is recognised by.
const String syntheticSender = 'SYNTHBANK';

/// The synthetic bank's canonical key, as the pipeline stores it.
const String syntheticBankId = 'synthbank';

/// Case (b): every field extracts except the required `remainingBalance`.
const String syntheticMissingOneRequiredField =
    'purchase 152.75 SAR card 4821 at SAMPLE MARKET 7 on 30/07/26 09:14';

/// The control: the same shape WITH the balance, which parses cleanly. Without
/// it, a green case-(b) test could be passing because the rule never works.
const String syntheticComplete =
    'purchase 152.75 SAR card 4821 at SAMPLE MARKET 7 on 30/07/26 09:14 '
    'balance 3100.00';

/// Case (a): from the same recognised bank, matching no rule's gate at all.
const String syntheticNoRuleMatches =
    'Your statement for July is ready in the SYNTHBANK app.';

/// A rule that reads type, amount, currency, merchant, card and date, and
/// requires an amount **and** a remaining balance.
MessageRule syntheticPurchaseRule() => MessageRule(
  ruleId: 'synthbank.pos_purchase',
  priority: 100,
  messageType: 'pos_purchase',
  intent: RuleIntent.transaction,
  match: RuleMatch(anyOf: <RegExp>[RegExp('purchase')]),
  regex: RegExp(
    r'purchase\s+(?<amount>[\d.,]+)\s+(?<currency>[A-Z]{3})\s+'
    r'card\s+(?<card>\d{4})\s+at\s+(?<merchant>[A-Z0-9 ]+?)\s+on\s+'
    r'(?<when>\d{2}/\d{2}/\d{2}\s+\d{2}:\d{2})'
    r'(?:\s+balance\s+(?<balance>[\d.,]+))?',
  ),
  extract: const <String, FieldExtraction>{
    'amount': FieldExtraction(group: 'amount'),
    'currency': FieldExtraction(group: 'currency'),
    'merchant': FieldExtraction(
      group: 'merchant',
      transforms: <String>['trim'],
    ),
    'instrumentRef': FieldExtraction(
      group: 'card',
      instrumentKind: 'card',
      maskPolicy: 'last4',
    ),
    'occurredAt': FieldExtraction(
      group: 'when',
      format: 'dd/MM/yy HH:mm',
      timezone: 'Asia/Riyadh',
    ),
    'remainingBalance': FieldExtraction(group: 'balance'),
  },
  sign: RuleSign.debit,
  affectsSpend: true,
  requiredFields: const <String>['amount', 'remainingBalance'],
  redact: const <RegExp>[],
);

RulePack syntheticRulePack() => RulePack(
  schemaVersion: 1,
  packId: 'synthetic-test',
  packVersion: '2026.07.30',
  locales: const <String>['en'],
  banks: <BankRule>[
    BankRule(
      bankId: syntheticBankId,
      displayNameAr: 'بنك تجريبي',
      displayNameEn: 'Synth Bank',
      aliases: const <String>[],
      senderPatterns: <RegExp>[RegExp('^$syntheticSender\$')],
      messageRules: <MessageRule>[syntheticPurchaseRule()],
    ),
  ],
);

/// The generic rule engine — ADR-007's *"the engine is generic; banks are
/// data"* made real.
///
/// Read `rule_pack.dart` first for the data model, and `parse_outcome.dart`
/// for why the result type is sealed. This file is only the evaluator.
///
/// ## The evaluation order is the classifier (ADR-007, and this is subtle)
///
/// There is no separate "financial vs noise" classifier component in this
/// codebase, and that is deliberate rather than an omission. ADR-007 states
/// it directly: *"Evaluation order (deterministic, and this ordering is
/// itself the classifier for US-A2)"*. Epic A's five classification criteria
/// fall out of the four steps below:
///
/// | Criterion | Step that satisfies it |
/// |---|---|
/// | AC-A2.3 non-financial sender → no transaction | step 2, sender resolution |
/// | AC-A2.1 OTP from a bank → no transaction | step 3, an `intent: ignore` rule at high priority |
/// | AC-A2.2 marketing from a bank → no transaction | step 3, likewise |
/// | AC-A2.5 balance-info → no *spending* transaction | step 3, likewise |
/// | AC-A2.4 genuine purchase → exactly one transaction | step 3, first match wins |
///
/// Building a second, independent classifier alongside this would create two
/// places that can disagree about what a message is. One of them would
/// eventually win an argument it should have lost, and a real purchase would
/// be dropped as marketing. One ordered evaluation, one answer.
///
/// ## The 250 ms per-rule budget
///
/// ADR-007 requires a per-rule timeout to contain catastrophic backtracking
/// in a malformed **imported** pack. Dart's `RegExp` runs synchronously on
/// the isolate and cannot be interrupted mid-match, so a true preemptive
/// timeout is not achievable without moving each rule into its own isolate —
/// which would cost far more than it saves for a per-message workload. What
/// is implemented instead, and this is stated plainly rather than dressed up:
///
///  - a **budget check between rules**, so a pack of 200 slow rules cannot
///    monopolise the ingestion worker's ~10-second window; and
///  - **load-time rejection** of the regex constructs that actually cause
///    catastrophic backtracking (nested unbounded quantifiers) — see
///    `rule_pack_loader.dart`.
///
/// Prevention at load time is the real mitigation; the budget is the backstop.
/// The residual risk — a single pathological regex that passes the load-time
/// screen — is recorded in the PR for this phase rather than papered over.
library;

import '../../core/money/money.dart';
import '../../core/text/sms_sanitizer.dart';
import '../../core/time/clock.dart';
import '../../core/time/sms_date_parser.dart';
import 'field_transforms.dart';
import 'message_parser.dart';
import 'parse_outcome.dart';
import 'parsed_fields.dart';
import 'partial_extraction.dart';
import 'rule_pack.dart';

final class RulePackMessageParser implements MessageParser {
  /// Every active pack. Bundled first, then imported — a later pack's bank
  /// can shadow an earlier one only by matching the same sender, and first
  /// match wins, so bundled rules take precedence unless a user deliberately
  /// imports a replacement. Ordering is the loader's responsibility.
  final List<RulePack> packs;

  /// Total wall-clock budget for evaluating one message across all rules.
  /// See the library doc comment for exactly what this does and does not
  /// guarantee.
  final Duration perMessageBudget;

  const RulePackMessageParser({
    required this.packs,
    this.perMessageBudget = const Duration(milliseconds: 250),
  });

  @override
  List<RegExp> redactionPatternsForSender(String sender) {
    final _BankMatch? bank = _resolveBank(sender);
    if (bank == null) {
      return const <RegExp>[];
    }
    // Union of every rule's `redact[]` for this bank. We cannot yet know
    // which rule will match — that needs the body, which must be sanitised
    // *before* we are allowed to look at it for storage purposes — so the
    // conservative choice is to apply all of the bank's patterns. Consistent
    // with ADR-013: over-redact rather than risk persisting a credential.
    return <RegExp>[
      for (final MessageRule rule in bank.bank.messageRules) ...rule.redact,
    ];
  }

  /// KHA-133 / AC-A6.1 — sender resolution on its own, with no body involved.
  ///
  /// Delegates to the same [_resolveBank] that [parse] step 2 uses, so a
  /// caller can never be told "this sender belongs to bank X" by one path and
  /// something different by the other. See [MessageParser.bankIdForSender] for
  /// why the port needs this at all.
  @override
  String? bankIdForSender(String sender) => _resolveBank(sender)?.bank.bankId;

  @override
  ParseOutcome parse({
    required SanitizedSmsText sanitized,
    required String normalizedBody,
    required String sender,
  }) {
    // --- Step 2: resolve the bank from the SENDER, not from the body ------
    //
    // Sender-first is what makes AC-A2.3 cheap and absolute: a message from
    // a person or a delivery service never reaches rule evaluation at all,
    // so no amount of transaction-looking text in a personal message ("I'll
    // pay you 250 SAR tomorrow") can produce a transaction.
    //
    // Step 1, normalisation, has already happened in the pipeline — see
    // `message_parser.dart` for why it lives there and not here.
    final _BankMatch? matched = _resolveBank(sender);
    if (matched == null) {
      return const NotFinancialSender();
    }

    final Stopwatch budget = Stopwatch()..start();

    // --- Step 3: first matching rule by descending priority wins ----------
    for (final MessageRule rule in matched.bank.messageRules) {
      if (budget.elapsed > perMessageBudget) {
        // Out of budget with rules still unevaluated. The message is from a
        // known financial sender, so NFR-A7 forbids dropping it: it goes to
        // the review queue, where the user can see it and act.
        return UnparsedMessage(
          reason: UnparsedReason.ruleTimedOut,
          rule: _reference(matched, rule),
        );
      }

      if (!rule.match.matches(normalizedBody)) {
        continue;
      }

      if (rule.intent == RuleIntent.ignore) {
        return IgnoredMessage(
          rule: _reference(matched, rule),
          classification: _classificationFor(rule.messageType),
        );
      }

      return _extract(matched, rule, normalizedBody);
    }

    // --- Step 4: known bank, no rule matched ------------------------------
    //
    // "Never discarded" (AC-A4.4, NFR-A7). This branch is the single most
    // important line in the file: it is what makes it true that a bank
    // changing its SMS template degrades the product into "you have things
    // to review" rather than into "your totals are quietly wrong".
    return UnparsedMessage(
      reason: UnparsedReason.noRuleMatched,
      rule: RuleReference(
        packId: matched.pack.packId,
        packVersion: matched.pack.packVersion,
        bankId: matched.bank.bankId,
        ruleId: '',
        messageType: 'unknown',
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Bank resolution
  // -------------------------------------------------------------------------

  _BankMatch? _resolveBank(String sender) {
    final String trimmedSender = sender.trim();
    for (final RulePack pack in packs) {
      for (final BankRule bank in pack.banks) {
        for (final RegExp pattern in bank.senderPatterns) {
          if (pattern.hasMatch(trimmedSender)) {
            return _BankMatch(pack, bank);
          }
        }
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Extraction
  // -------------------------------------------------------------------------

  ParseOutcome _extract(
    _BankMatch matched,
    MessageRule rule,
    String normalizedBody,
  ) {
    final RuleReference reference = _reference(matched, rule);

    final RegExp? extractionRegex = rule.regex;
    if (extractionRegex == null) {
      // A transaction rule with no extraction regex can satisfy no required
      // field; treat it as a rule-authoring error surfaced through the
      // review queue rather than as a crash.
      return UnparsedMessage(
        reason: UnparsedReason.extractionRegexFailed,
        rule: reference,
      );
    }

    final RegExpMatch? match = extractionRegex.firstMatch(normalizedBody);
    if (match == null) {
      // The gate said yes, the extraction said no. Almost always a partial
      // template change at the bank (R-4), and exactly the signal a
      // maintainer needs: the rule id is carried through.
      return UnparsedMessage(
        reason: UnparsedReason.extractionRegexFailed,
        rule: reference,
      );
    }

    final _Extractor extractor = _Extractor(match, rule.extract);

    final String? currency = extractor.text('currency');
    final ParsedFields fields = ParsedFields(
      amount: extractor.money('amount', currency),
      convertedAmount: extractor.money(
        'convertedAmount',
        extractor.text('convertedCurrency') ?? currency,
      ),
      feeAmount: extractor.money(
        'feeAmount',
        extractor.text('feeCurrency') ?? currency,
      ),
      exchangeRate: extractor.text('exchangeRate'),
      remainingBalance: extractor.money(
        'remainingBalance',
        extractor.text('remainingBalanceCurrency') ?? currency,
      ),
      merchantRawText: extractor.text('merchant'),
      instrument: extractor.instrument('instrumentRef'),
      settlementInstrument: extractor.instrument('settlementRef'),
      occurredAtUtc: extractor.dateTimeUtc('occurredAt'),
      timeSource: extractor.hasSpec('occurredAt')
          // The bank printed a wall-clock reading with no offset; we
          // interpret it as Asia/Riyadh and say so (architecture §7.4). The
          // pipeline substitutes `received_at_fallback` when this is null.
          ? (extractor.dateTimeUtc('occurredAt') == null
                ? null
                : 'sms_local_assumed')
          : null,
      referenceNumber: extractor.text('referenceNumber'),
      counterpartyName: extractor.text('counterpartyName'),
      counterpartyBankName: extractor.text('counterpartyBankName'),
      billerCode: extractor.text('billerCode'),
      invoiceNumber: extractor.text('invoiceNumber'),
    );

    // --- requiredFields: the line between a transaction and a review item --
    final Set<String> present = fields.presentFieldNames;
    final List<String> missing = rule.requiredFields
        .where((String field) => !present.contains(field))
        .toList();

    if (missing.isNotEmpty) {
      // A half-populated transaction is never invented. AC-A4.2 promises the
      // user gets to fill in the gap themselves, from the original text.
      //
      // **KHA-146:** but "fill in the gap" is not "retype everything". By this
      // line `fields` already holds every value the regex read successfully —
      // it was computed above, before the check, and until KHA-146 it was
      // discarded right here. Carrying it through is the whole fix: the user
      // is asked for the field that genuinely failed, not for the four that
      // did not. It stays explicitly unconfirmed all the way to the form (see
      // `partial_extraction.dart`); nothing on this path writes a transaction.
      return UnparsedMessage(
        reason: UnparsedReason.requiredFieldMissing,
        rule: reference,
        missingFields: missing,
        partialExtraction: PartialExtraction.fromParsedFields(
          fields,
          // The rule's declared type — the "transaction type word" the message
          // opened with, which the form otherwise makes the user pick again
          // from a twelve-item dropdown.
          transactionType: rule.messageType,
          missingFields: missing,
        ),
      );
    }

    return ParsedMessage(
      rule: reference,
      fields: fields,
      direction: rule.sign == RuleSign.debit ? 'debit' : 'credit',
      affectsSpend: rule.affectsSpend,
    );
  }

  RuleReference _reference(_BankMatch matched, MessageRule rule) =>
      RuleReference(
        packId: matched.pack.packId,
        packVersion: matched.pack.packVersion,
        bankId: matched.bank.bankId,
        ruleId: rule.ruleId,
        messageType: rule.messageType,
      );

  /// Maps a rule's `messageType` onto the `RawMessage.classification`
  /// vocabulary the schema stores (architecture §4.2).
  ///
  /// The default is `ignored_info` rather than a throw: a *newer imported
  /// pack* may name an ignore type this build has never heard of, and the
  /// forward-compatibility rule in §5.2 says unknown values must degrade
  /// gracefully. Degrading to "we ignored something informational, body not
  /// retained" is the privacy-safe direction to degrade in.
  static String _classificationFor(String messageType) => switch (messageType) {
    'otp' => 'ignored_otp',
    'marketing' => 'ignored_marketing',
    _ => 'ignored_info',
  };
}

/// A bank found in a pack, carrying both so provenance can name the pack.
final class _BankMatch {
  final RulePack pack;
  final BankRule bank;
  const _BankMatch(this.pack, this.bank);
}

/// Pulls typed values out of one regex match according to the rule's
/// declared field specs.
///
/// Split out as its own tiny class purely for readability: without it,
/// `_extract` becomes a 150-line method where the interesting logic (what
/// happens when a field is missing) is buried in null-handling noise.
final class _Extractor {
  final RegExpMatch _match;
  final Map<String, FieldExtraction> _specs;

  const _Extractor(this._match, this._specs);

  bool hasSpec(String field) => _specs.containsKey(field);

  /// The raw captured string for [field] after its declared transforms, or
  /// `null` when the field is not declared, the group did not participate in
  /// the match, or the result is empty.
  ///
  /// Empty-becomes-null is deliberate and is AC-B1.3 in one line: a capture
  /// group that matched nothing must read as *unknown*, not as an empty
  /// merchant name that would later be normalised into a merchant key of
  /// `''` and match every other blank merchant in the database.
  String? text(String field) {
    final FieldExtraction? spec = _specs[field];
    if (spec == null) {
      return null;
    }
    if (spec.literal != null) {
      return spec.literal;
    }

    final String? captured = _groupOrNull(spec.group);
    if (captured == null) {
      return null;
    }
    final String transformed = FieldTransforms.applyAll(
      captured,
      spec.transforms,
    );
    return transformed.isEmpty ? null : transformed;
  }

  /// A [Money] for [field] in [currency].
  ///
  /// Returns `null` — routing the message to the review queue if this field
  /// was required — rather than throwing, when either the amount or the
  /// currency is missing or malformed. `Money.tryParse` exists precisely for
  /// this call site (see its doc comment): NFR-R5 forbids one bad message
  /// from taking down the batch.
  ///
  /// **There is no path here that produces a zero amount from a failed
  /// parse.** A transaction of 0.00 that should have been 250.00 is invisible
  /// in a list and wrong in a total; a missing amount is visible in the
  /// review queue.
  Money? money(String field, String? currency) {
    final String? raw = text(field);
    if (raw == null || currency == null || currency.isEmpty) {
      return null;
    }
    return Money.tryParse(raw, currency: currency);
  }

  /// An [InstrumentReference], masked to last-4 by [InstrumentMask].
  InstrumentReference? instrument(String field) {
    final FieldExtraction? spec = _specs[field];
    if (spec == null) {
      return null;
    }
    final String? captured = text(field);
    if (captured == null) {
      return null;
    }
    final String? masked = InstrumentMask.maskLast4(captured);
    if (masked == null) {
      return null;
    }
    return InstrumentReference(
      kind: spec.instrumentKind ?? 'account',
      maskedIdentifier: masked,
      network: text('${field}Network'),
      cardType: text('${field}Type'),
    );
  }

  /// A UTC instant for [field], interpreting the message's wall clock as
  /// `Asia/Riyadh` (architecture §7.4).
  DateTime? dateTimeUtc(String field) {
    final FieldExtraction? spec = _specs[field];
    final String? raw = text(field);
    if (spec == null || raw == null || spec.format == null) {
      return null;
    }
    final SmsDateParseResult result = SmsDateParser.parse(raw, spec.format!);
    return switch (result) {
      SmsDateParsed(:final DateTime localWallClock) =>
        RiyadhCalendar.riyadhLocalToUtc(localWallClock),
      SmsDateUnparsed() => null,
    };
  }

  /// `RegExpMatch.namedGroup` **throws** for a group name the pattern does
  /// not declare, which would turn a rule-pack typo into a crashed ingestion
  /// run. Catching it here converts that into "field absent" — which routes
  /// to the review queue if the field was required, i.e. visibly, rather
  /// than by taking down the batch (NFR-R5).
  String? _groupOrNull(String name) {
    try {
      return _match.namedGroup(name);
    } on ArgumentError {
      return null;
    }
  }
}

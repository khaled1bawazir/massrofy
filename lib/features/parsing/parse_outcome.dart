/// The **complete** set of things that can happen to a message, expressed as
/// a sealed type.
///
/// ## Why this being *sealed* is a correctness feature, not a style choice
///
/// NFR-A7 and AC-A4.4 make one promise the whole product's trustworthiness
/// rests on: **a message judged financial is either turned into a transaction
/// or placed in the review queue. It is never silently discarded.** Linear
/// KHA-22 states it plainly — if a financial message is neither, *that is a
/// defect*.
///
/// `docs/architecture.md` §5.4 spells out the same idea in the port
/// signature, with a pointed comment:
///
/// ```dart
/// // ParseOutcome = Parsed(fields, ruleRef) | Ignored(reason) | Unparsed(reason)
/// //                                          ^ never a fourth "dropped" case
/// ```
///
/// A Dart `sealed class` can only be extended inside this library, so the
/// compiler knows the full set of subtypes. Any `switch` over a
/// [ParseOutcome] that forgets a case **fails to compile**. That turns "we
/// promised never to drop a message" from a code-review vigilance exercise
/// into a property the toolchain checks on every build. If someone later
/// wants to add a "dropped" case, they have to come here and add it in the
/// open — which is exactly the conversation that should happen.
///
/// ## A note for readers new to Dart
///
/// `sealed` implies `abstract` (you cannot instantiate [ParseOutcome]
/// itself) and restricts subclassing to this file. `final class` on each
/// subtype means nothing outside can extend *those* either. Together they
/// make this a closed algebraic type — the Dart equivalent of a Kotlin
/// `sealed interface` or a Rust `enum` with payloads.
library;

import 'parsed_fields.dart';

/// Which pack, version, and rule produced an outcome — NFR-A1 provenance.
/// Recorded on every transaction so "why is this number what it is?" is
/// answerable months later, and so a rule change can be correlated with a
/// change in output.
final class RuleReference {
  final String packId;
  final String packVersion;
  final String bankId;
  final String ruleId;
  final String messageType;

  const RuleReference({
    required this.packId,
    required this.packVersion,
    required this.bankId,
    required this.ruleId,
    required this.messageType,
  });

  @override
  bool operator ==(Object other) =>
      other is RuleReference &&
      other.packId == packId &&
      other.packVersion == packVersion &&
      other.bankId == bankId &&
      other.ruleId == ruleId &&
      other.messageType == messageType;

  @override
  int get hashCode =>
      Object.hash(packId, packVersion, bankId, ruleId, messageType);

  @override
  String toString() => 'RuleReference($packId@$packVersion/$bankId/$ruleId)';
}

/// Base of the closed outcome set. See the library doc comment.
sealed class ParseOutcome {
  const ParseOutcome();
}

/// The sender matched no bank in any active pack.
///
/// Per NFR-P4 and architecture §4.2's retention rules this means **no row at
/// all**: the message is not indexed, not counted, not stored, not even as a
/// timestamp. A personal message from a friend leaves no trace in this app,
/// which is a promise the transparency screen (US-F4) makes out loud.
final class NotFinancialSender extends ParseOutcome {
  const NotFinancialSender();
}

/// A known financial sender, recognised as noise: OTP, marketing, or a
/// balance-only informational message (AC-A2.1, A2.2, A2.5).
///
/// The body is **destroyed**. A row is written with `sanitizedBody = NULL`,
/// carrying only bank, classification and timestamp, so the parser-health
/// panel (ADR-015) can say "we ignored 14 OTPs this month" without retaining
/// one character of any of them.
final class IgnoredMessage extends ParseOutcome {
  final RuleReference rule;

  /// The `RawMessage.classification` value to store: `ignored_otp`,
  /// `ignored_marketing`, or `ignored_info`.
  final String classification;

  const IgnoredMessage({required this.rule, required this.classification});
}

/// A financial message that produced a usable set of fields.
final class ParsedMessage extends ParseOutcome {
  final RuleReference rule;
  final ParsedFields fields;

  /// `debit` or `credit`, from the rule's declared `sign`.
  final String direction;

  /// Whether this movement counts toward "money spent" (US-B10/B11).
  final bool affectsSpend;

  const ParsedMessage({
    required this.rule,
    required this.fields,
    required this.direction,
    required this.affectsSpend,
  });
}

/// A message from a **known financial sender** that could not be turned into
/// a transaction — either no rule matched it, or a rule matched but a
/// `requiredFields` entry came out empty.
///
/// This is the safety net, and it is the reason this product can be trusted:
/// the message goes to the review queue **with its sanitised text** so the
/// user can see it and fill in what the parser missed (US-A4, AC-A4.1,
/// AC-A4.2). It is emphatically not an error case to be logged and forgotten.
final class UnparsedMessage extends ParseOutcome {
  /// Non-null when a rule matched but its required fields were not all
  /// satisfied — that rule's identity is still worth recording, because it
  /// tells a maintainer *which* template drifted (R-4, NFR-M1).
  final RuleReference? rule;

  /// Machine-readable reason, from [UnparsedReason]. Never free text: this
  /// value reaches the parser-health panel and must be aggregatable.
  final String reason;

  /// Which declared `requiredFields` were missing, when that is why. Empty
  /// when no rule matched at all.
  final List<String> missingFields;

  const UnparsedMessage({
    required this.reason,
    this.rule,
    this.missingFields = const <String>[],
  });
}

/// The closed vocabulary of [UnparsedMessage.reason].
abstract final class UnparsedReason {
  /// The bank was recognised, but none of its rules matched the text. Usually
  /// means the bank changed a template (R-4).
  static const String noRuleMatched = 'no_rule_matched';

  /// A rule matched and its gate passed, but its extraction regex did not
  /// match the body — a rule authoring bug, or a partial template change.
  static const String extractionRegexFailed = 'extraction_regex_failed';

  /// A rule matched and extracted, but one or more `requiredFields` were
  /// absent. See [UnparsedMessage.missingFields].
  static const String requiredFieldMissing = 'required_field_missing';

  /// The rule's regex exceeded ADR-007's per-rule time budget and was
  /// abandoned. Contains a malformed imported pack rather than hanging the
  /// ingestion isolate.
  static const String ruleTimedOut = 'rule_timed_out';
}

/// The port the ingestion pipeline codes against — `docs/architecture.md`
/// §5.4 Contract C:
///
/// ```dart
/// abstract interface class MessageParser {   // features/parsing → ingestion
///   ParseOutcome parse(SanitizedSmsText text, String sender);
/// }
/// ```
///
/// ## Why the pipeline depends on this and not on the engine class
///
/// Two reasons, and only one of them is testing.
///
/// 1. **Module boundary.** Architecture §3's dependency rule says features
///    talk through ports, never through each other's internals.
///    `features/ingestion` knowing the shape of a `RulePack` would make a
///    rule-schema change an ingestion change.
/// 2. **Tests get to be about one thing.** A pipeline test that needs "a
///    message that fails to parse" can hand in a two-line fake instead of
///    authoring a rule pack that fails in the right way. Conversely the
///    parser's own tests need no database.
///
/// ## Note on the signature: it deviates from §5.4, deliberately
///
/// The ADR sketches `parse(SanitizedSmsText, String sender)`. This interface
/// takes the **normalised** text as a separate argument, because normalisation
/// (ADR-007 step 1) must happen exactly once per message and its result is
/// also needed by the dedup HMAC (ADR-017 D1). Recomputing it inside the
/// parser would mean the parser and the dedup key could disagree about what
/// "the same message" is — a subtle way to make duplicate suppression
/// unreliable. The pipeline normalises once and passes the result down.
library;

import '../../core/text/sms_sanitizer.dart';
import 'parse_outcome.dart';

abstract interface class MessageParser {
  /// Classifies and parses one message.
  ///
  /// [sanitized] is post-redaction text (ADR-013) — the type makes it
  /// impossible to pass raw text here by accident. [normalizedBody] is that
  /// same text after `SmsTextNormalizer.normalize`. [sender] is the SMS
  /// originating address, used for bank resolution.
  ///
  /// **Must never throw.** NFR-R5 requires that a parse failure on one SMS
  /// not prevent processing of the others; every failure mode is a value in
  /// the [ParseOutcome] hierarchy instead.
  ParseOutcome parse({
    required SanitizedSmsText sanitized,
    required String normalizedBody,
    required String sender,
  });

  /// The redaction patterns the bank matching [sender] declares (ADR-007
  /// `redact[]`), for `SmsSanitizer` to apply.
  ///
  /// This exists because of an ordering constraint that is easy to get
  /// backwards: sanitisation must happen **before** anything is persisted,
  /// but choosing the right per-bank patterns requires knowing which bank
  /// sent the message — which is sender-based, not body-based. So the
  /// pipeline resolves the bank from the sender first, asks for its patterns,
  /// sanitises, and only then parses. Returns an empty list for an unknown
  /// sender (whose body is about to be discarded entirely anyway).
  List<RegExp> redactionPatternsForSender(String sender);
}

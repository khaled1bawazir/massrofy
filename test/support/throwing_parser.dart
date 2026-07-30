import 'package:massrofy/core/text/sms_sanitizer.dart';
import 'package:massrofy/features/parsing/message_parser.dart';
import 'package:massrofy/features/parsing/parse_outcome.dart';

/// A [MessageParser] that delegates to a real one but **throws** for messages
/// from one chosen sender.
///
/// ## Why this exists, and why it throws rather than returns
///
/// `ParseOutcome` already models every way a message can fail to *parse* —
/// unknown sender, no matching rule, missing required field. None of those is
/// what this fake simulates. This is an **internal defect**: a bug in the
/// parser, a malformed rule pack that slipped the loader's checks, an
/// unexpected `null`. That distinction matters, because the two are handled by
/// completely different machinery:
///
///  - a parse *verdict* is data, routed by the exhaustive `switch`;
///  - an *exception* is a failure, caught by the pipeline's per-message
///    try/catch and counted as `failedWithError`.
///
/// The invariant that hangs off `failedWithError` is the important one: no
/// cursor — neither `IngestionPipeline`'s forward watermark nor
/// `HistoricalImporter`'s backfill cursor — may advance past a message that
/// threw, or that message is never read again. Both paths run the same
/// pipeline, so both need to be tested against the same fake.
///
/// Shared between `ingestion_pipeline_test.dart` and
/// `historical_importer_test.dart` deliberately: two copies of a fake drift
/// apart, and then one path is verified against a stricter simulation of
/// failure than the other.
final class ThrowingParser implements MessageParser {
  final MessageParser _inner;

  /// Messages whose `sender` equals this value throw instead of parsing.
  final String throwForSender;

  const ThrowingParser(this._inner, {required this.throwForSender});

  @override
  List<RegExp> redactionPatternsForSender(String sender) =>
      _inner.redactionPatternsForSender(sender);

  /// Delegated, deliberately **not** made to throw. This fake simulates a
  /// defect while *parsing a body*; sender resolution is body-free and is what
  /// the re-scan uses to decide which messages to hand to the pipeline at all.
  /// Making it throw here would mean the throwing message never reached the
  /// pipeline, and the `failedWithError` invariants these tests exist to prove
  /// would silently stop being exercised.
  @override
  String? bankIdForSender(String sender) => _inner.bankIdForSender(sender);

  @override
  ParseOutcome parse({
    required SanitizedSmsText sanitized,
    required String normalizedBody,
    required String sender,
  }) {
    if (sender == throwForSender) {
      throw StateError('simulated parser failure');
    }
    return _inner.parse(
      sanitized: sanitized,
      normalizedBody: normalizedBody,
      sender: sender,
    );
  }
}

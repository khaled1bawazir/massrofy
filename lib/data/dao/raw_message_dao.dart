import 'package:drift/drift.dart';

import '../../core/text/sms_sanitizer.dart';
import '../db/app_database.dart';
import '../db/tables/raw_message_table.dart';

part 'raw_message_dao.g.dart';

/// ADR-013's ingestion-boundary enforcement, expressed as a DAO signature:
/// [insert] takes a [SanitizedSmsText], never a plain `String`. There is no
/// way to write an unsanitised SMS body into the `raw_message` table — the
/// call simply will not compile if you try to pass a `String` where a
/// [SanitizedSmsText] is required.
@DriftAccessor(tables: [RawMessages])
class RawMessageDao extends DatabaseAccessor<AppDatabase>
    with _$RawMessageDaoMixin {
  RawMessageDao(super.attachedDatabase);

  /// Stores a message that was (or might yet be) a transaction — i.e. it
  /// has body text to keep, already redacted by [SmsSanitizer].
  ///
  /// [contentHmac] is the D1-exact dedup key (ADR-017) — computed by the
  /// caller (the future P2 ingestion pipeline) over the *normalised* body,
  /// sender, and timestamp, never over the redacted display text, so
  /// dedup semantics don't shift if a redaction rule changes later.
  Future<int> insert({
    String? smsProviderId,
    required String sender,
    required DateTime receivedAt,
    required SanitizedSmsText sanitizedText,
    required String contentHmac,
    String? bankId,
    required String classification,
  }) {
    return into(rawMessages).insert(
      RawMessagesCompanion.insert(
        smsProviderId: Value<String?>(smsProviderId),
        sender: sender,
        receivedAt: receivedAt,
        sanitizedBody: Value<String?>(sanitizedText.value),
        contentHmac: contentHmac,
        bankId: Value<String?>(bankId),
        classification: classification,
        panRedacted: Value<bool>(sanitizedText.panRedacted),
      ),
    );
  }

  /// Stores a content-free row for a message classified `intent: ignore`
  /// (OTP/marketing/info) from a known financial sender — NFR-P4's precise
  /// rule: "financial sender + intent:ignore -> row with sanitizedBody =
  /// NULL. Bank, classification, and timestamp only." There is no
  /// [SanitizedSmsText] parameter here at all, because there is no content
  /// to sanitize-and-keep in the first place.
  Future<int> insertIgnoredNoContent({
    String? smsProviderId,
    required String sender,
    required DateTime receivedAt,
    required String contentHmac,
    String? bankId,
    required String classification,
  }) {
    return into(rawMessages).insert(
      RawMessagesCompanion.insert(
        smsProviderId: Value<String?>(smsProviderId),
        sender: sender,
        receivedAt: receivedAt,
        contentHmac: contentHmac,
        bankId: Value<String?>(bankId),
        classification: classification,
      ),
    );
  }

  /// Looks up a message by its dedup key — the D1-exact carrier-retry
  /// check (ADR-017): if a row already exists for this HMAC, the incoming
  /// SMS is a duplicate delivery and should be suppressed silently.
  Future<RawMessageRow?> findByContentHmac(String contentHmac) {
    return (select(rawMessages)
          ..where((RawMessages t) => t.contentHmac.equals(contentHmac)))
        .getSingleOrNull();
  }

  Future<List<RawMessageRow>> all() => select(rawMessages).get();
}

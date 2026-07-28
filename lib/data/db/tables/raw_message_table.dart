import 'package:drift/drift.dart';

/// Raw (redacted) SMS storage — ADR-013, NFR-P4, AC-B1.2, US-A4.
///
/// **This table can only ever be written to through `RawMessageDao.insert`,
/// which requires a `SanitizedSmsText` (see `lib/core/text/sms_sanitizer.dart`)
/// — never a plain `String`.** There is no code path in this app that can
/// compile a call inserting an unsanitised body into [sanitizedBody].
@DataClassName('RawMessageRow')
class RawMessages extends Table {
  @override
  String get tableName => 'raw_message';

  IntColumn get id => integer().autoIncrement()();

  /// The Android SMS content-provider row id, when known — `UNIQUE` so a
  /// re-scan (AC-A3.3) can never create a duplicate row for the same
  /// underlying message.
  TextColumn get smsProviderId => text().nullable().unique()();

  TextColumn get sender => text()();

  DateTimeColumn get receivedAt => dateTime()();

  /// Redacted text, or `NULL`.
  ///
  /// Per ADR-013/NFR-P4's precise retention rule: a message from a **known
  /// financial sender** classified `intent: ignore` (OTP/marketing/info)
  /// gets a row with `sanitizedBody = NULL` — bank, classification, and
  /// timestamp only, for the parser-health panel, with **no content at
  /// all**. A message that was parsed or is unparsed-but-financial keeps
  /// its (already redacted) text, because AC-B1.2 lets the user verify a
  /// parse and AC-A4.1 needs the raw-but-sanitised text in the review
  /// queue. (A non-financial sender gets **no row at all** — that decision
  /// happens before this DAO is ever called, in the P2 ingestion pipeline.)
  TextColumn get sanitizedBody => text().nullable()();

  /// `HMAC-SHA256(k, normalisedBody‖sender‖smsTimestamp)`, `UNIQUE` — the
  /// D1-exact carrier-retry dedup key (ADR-017). Storing an HMAC rather
  /// than the text keeps this dedup index non-reversible.
  TextColumn get contentHmac => text().unique()();

  TextColumn get bankId => text().nullable()();

  /// `'financial_parsed' | 'financial_unparsed' | 'ignored_otp' |
  /// 'ignored_marketing' | 'ignored_info'`.
  TextColumn get classification => text()();

  BoolColumn get panRedacted => boolean().withDefault(const Constant(false))();

  /// US-A4's "not a transaction" dismissal. A dismissed row leaves the review
  /// queue but is **kept**, so the same message re-read from the provider on
  /// a later sweep is not resurrected as a new review item.
  BoolColumn get dismissedAsNotTransaction =>
      boolean().withDefault(const Constant(false))();

  // --- P2 additions (ADR-007 step 4 diagnostics) ---------------------------
  //
  // Architecture §4.2 lists `RawMessage` without these two. They are a small,
  // deliberate extension rather than a divergence: without them the review
  // queue can show the user *that* a message was not understood but not
  // *why*, and the parser-health panel (ADR-015) cannot tell "the bank
  // changed a template" apart from "the amount was missing" — which are very
  // different maintenance signals (risk R-4).
  //
  // Both are diagnostics about the parse, not content: they hold rule ids and
  // enum values, never message text or figures (NFR-S4).

  /// One of `UnparsedReason`'s constants, or `NULL` when the message parsed
  /// or was ignored.
  TextColumn get unparsedReason => text().nullable()();

  /// The `ruleId` that matched but could not complete, when there was one.
  /// `NULL` when no rule matched at all.
  TextColumn get unparsedRuleId => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

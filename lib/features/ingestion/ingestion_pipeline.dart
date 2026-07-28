/// The end-to-end ingestion pipeline — ADR-006's data flow, in one place.
///
/// ```
/// SMS arrives
///    │  [Kotlin] SmsReceiver — wake only, carries no content       ADR-006
///    ▼
/// WorkManager expedited job ──► background FlutterEngine
///    ▼
/// ingestion: read content://sms/inbox WHERE date > watermark       ADR-006
///    ▼
/// SmsSanitizer ── redact PAN/CVV/PIN → SanitizedSmsText            ADR-013
///    ▼
/// parsing: resolve bank → match rule → extract fields              ADR-007
///    ├─ no financial sender ────────────► discard, retain nothing   NFR-P4
///    ├─ intent:ignore ──────────────────► counter row only, no body NFR-P4
///    ├─ no rule / missing required ─────► review queue + text       US-A4
///    ▼
/// dedup (D1 suppress / D2 flag / D3 flag)                          ADR-017
///    ▼
/// ledger: upsert transaction   ┐ single DB txn,
///         + audit entry        ├ advances the
///         + advance watermark  ┘ watermark atomically
/// ```
///
/// ## The three invariants this class exists to hold
///
/// **1. Nothing from a financial sender is ever lost (NFR-A7, AC-A4.4).**
/// The `switch` over `ParseOutcome` is exhaustive because that type is
/// sealed — a fifth outcome would not compile until it is handled here. There
/// is no `default:` branch, deliberately.
///
/// **2. The watermark advances in the same transaction as the writes
/// (ADR-006).** Not "shortly after". Each message is one unit of work:
/// `database.transaction(...)` wraps its raw-message row, its transaction row,
/// its audit entry and the watermark advance, so all four commit together or
/// none of them do. See [IngestionPipeline.processAll] for the two distinct
/// crash windows this closes — one of which loses a financial message
/// permanently, because D1 dedup keys off the raw-message row that a
/// half-finished write leaves behind.
///
/// **3. One bad message never stops the batch (NFR-R5).** Every message is
/// processed inside its own try/catch. A malformed message from one bank must
/// not prevent another bank's purchase from being recorded — and on a
/// background isolate, an uncaught exception takes the whole run down.
///
/// ## Background ingestion is suspended while the app is locked — **ADR-018**
///
/// This section used to describe an unresolved ADR gap. It is resolved:
/// `docs/architecture.md` **ADR-018** (architecture v1.1, resolving KHA-56)
/// ratified the behaviour below as the design. It is not a stub, not a
/// placeholder, and not waiting on anybody.
///
/// **The conflict ADR-018 settles.** ADR-005 makes the app lock
/// *cryptographic*: the DB Master Key is unwrapped only through a Keystore
/// key created with `setUserAuthenticationRequired(true)`, under a 5-second
/// authentication validity window. A background isolate woken by an SMS
/// broadcast has no user present and no recent authentication, so it
/// **cannot open the database** — not sometimes, *never*. Since the lock
/// grace default is 0 s, the app is locked from the moment the user leaves
/// it, which makes the locked case the **normal** case rather than an edge
/// one. ADR-006 assumed the worker could write; ADR-005 guarantees it cannot;
/// v1.0 never noticed.
///
/// **What ADR-018 decided.** A background run is a no-op: it MUST NOT advance
/// the watermark, and it MUST report *success* to WorkManager rather than
/// failure, because retrying would burn the backoff budget on a condition
/// only a human unlocking the phone can clear. ADR-018 explicitly rejected
/// the alternative that would have delivered locked-state ingestion — a
/// second Keystore key with `setUserAuthenticationRequired(false)` guarding
/// an "ingest inbox" — on the grounds that it buys no durability (the SMS
/// content provider is already the durable queue, which is exactly why
/// ADR-006's receiver carries no content), buys latency no user is awake to
/// observe, and turns "nothing in this app is readable without
/// authentication" into a claim needing a footnote. Plaintext staging and
/// weakening the lock were rejected outright.
///
/// **Read the implementation precisely.** As shipped,
/// `runBackgroundIngestion()` in `background_entrypoint.dart` is an
/// **unconditional** no-op — it returns success without attempting to open
/// the database at all. It is *not* conditional on the lock state, so ADR-006
/// Layer 1 performs zero ingestion in every case, including the unlocked one,
/// and the wake path is the only part of Layer 1 that ships. That is a
/// superset of what ADR-018 decision 1 requires and is strictly safe in the
/// same way: the watermark never moves, so nothing can be lost. All actual
/// ingestion is done by Layer 2's foreground/post-unlock sweep, which runs
/// this identical pipeline over everything since the watermark.
///
/// **What this costs, stated as the architecture states it.** Latency, not
/// data. NFR-R1's "single-digit seconds from SMS arrival" now holds only
/// while the app is unlocked; while locked it becomes "single-digit seconds
/// **from unlock**, with nothing lost and nothing silently reordered". That
/// is a genuine reduction against the PRD's wording, and it is on the record
/// as **H-13** rather than quietly reinterpreted.
///
/// **Two consequences that are easy to get wrong.** ADR-006's Layer 3
/// foreground service is re-scoped, not a workaround: it keeps the *wake
/// signal* alive on hostile OEMs but **cannot open the database either**, so
/// it MUST NOT be made default-on on NFR-R1 grounds (H-6). And ADR-018
/// decision 3 makes a post-unlock sweep part of the unlock transition, with
/// the home screen showing an explicit "updating" state — a stale month total
/// rendered confidently as final is worse than an honest spinner, for a
/// product whose success criterion is that the user trusts the numbers.
library;

import '../../core/logging/log_event.dart';
import '../../core/logging/safe_logger.dart';
import '../../core/money/money.dart';
import '../../core/text/sms_sanitizer.dart';
import '../../core/text/sms_text_normalizer.dart';
import '../../data/dao/ingest_watermark_dao.dart';
import '../../data/dao/raw_message_dao.dart';
import '../../data/dao/transaction_dao.dart';
import '../../data/db/app_database.dart';
import '../parsing/message_parser.dart';
import '../parsing/parse_outcome.dart';
import '../parsing/parsed_fields.dart';
import 'content_hmac.dart';
import 'duplicate_policy.dart';
import 'sms_source.dart';

/// `LogEvent.category` labels used by this file.
///
/// ADR-015 requires the category to be a compile-time constant at the call
/// site, never built from runtime data — constants make that checkable by
/// reading one place instead of every call.
const String _logMessageFailed = 'ingestion.message_failed';
const String _logDuplicateSuppressed = 'ingestion.duplicate_suppressed';

/// Counts from one run. Counts only — no content, so this is safe to log and
/// safe to show in the parser-health panel (ADR-015).
final class IngestionRunResult {
  final int examined;
  final int transactionsWritten;
  final int flaggedAsPossibleDuplicate;
  final int suppressedAsExactDuplicate;
  final int routedToReviewQueue;
  final int ignoredAsNoise;
  final int discardedNonFinancialSender;
  final int failedWithError;

  const IngestionRunResult({
    this.examined = 0,
    this.transactionsWritten = 0,
    this.flaggedAsPossibleDuplicate = 0,
    this.suppressedAsExactDuplicate = 0,
    this.routedToReviewQueue = 0,
    this.ignoredAsNoise = 0,
    this.discardedNonFinancialSender = 0,
    this.failedWithError = 0,
  });

  /// Every examined message must be accounted for by exactly one bucket.
  ///
  /// This is NFR-A7 expressed as arithmetic, and there is a test that asserts
  /// it after every run. A message that fell through some unhandled path
  /// would make this sum come up short — which is a far more reliable alarm
  /// than hoping someone notices a missing row.
  bool get isFullyAccountedFor =>
      examined ==
      transactionsWritten +
          flaggedAsPossibleDuplicate +
          suppressedAsExactDuplicate +
          routedToReviewQueue +
          ignoredAsNoise +
          discardedNonFinancialSender +
          failedWithError;

  IngestionRunResult _plus({
    int examined = 0,
    int transactionsWritten = 0,
    int flaggedAsPossibleDuplicate = 0,
    int suppressedAsExactDuplicate = 0,
    int routedToReviewQueue = 0,
    int ignoredAsNoise = 0,
    int discardedNonFinancialSender = 0,
    int failedWithError = 0,
  }) => IngestionRunResult(
    examined: this.examined + examined,
    transactionsWritten: this.transactionsWritten + transactionsWritten,
    flaggedAsPossibleDuplicate:
        this.flaggedAsPossibleDuplicate + flaggedAsPossibleDuplicate,
    suppressedAsExactDuplicate:
        this.suppressedAsExactDuplicate + suppressedAsExactDuplicate,
    routedToReviewQueue: this.routedToReviewQueue + routedToReviewQueue,
    ignoredAsNoise: this.ignoredAsNoise + ignoredAsNoise,
    discardedNonFinancialSender:
        this.discardedNonFinancialSender + discardedNonFinancialSender,
    failedWithError: this.failedWithError + failedWithError,
  );

  @override
  String toString() =>
      'IngestionRunResult(examined: $examined, written: $transactionsWritten, '
      'flagged: $flaggedAsPossibleDuplicate, '
      'suppressed: $suppressedAsExactDuplicate, '
      'review: $routedToReviewQueue, ignored: $ignoredAsNoise, '
      'nonFinancial: $discardedNonFinancialSender, errors: $failedWithError)';
}

final class IngestionPipeline {
  final AppDatabase database;
  final SmsSource smsSource;
  final MessageParser parser;
  final RawMessageDao rawMessageDao;
  final TransactionDao transactionDao;
  final IngestWatermarkDao watermarkDao;
  final SafeLogger logger;

  /// The Keystore-held key for the D1 content HMAC (ADR-017). See
  /// `content_hmac.dart` for why this is keyed rather than a plain digest.
  final List<int> contentHmacKey;

  /// How many messages one call will process. ADR-006 gives the
  /// broadcast-triggered worker roughly a 10-second budget; a first sweep on
  /// a device with thousands of messages must not try to do it all at once,
  /// because being killed mid-run would mean never finishing.
  final int batchLimit;

  /// How many batches one [runIncremental] call will drain before stopping.
  ///
  /// `batchLimit * maxBatchesPerRun` is the real per-run ceiling. Ten batches
  /// of a hundred covers any realistic backlog in one sweep, while still
  /// bounding a pathological first run so the expedited worker is not killed
  /// mid-way through work it could have finished across two wakes.
  final int maxBatchesPerRun;

  const IngestionPipeline({
    required this.database,
    required this.smsSource,
    required this.parser,
    required this.rawMessageDao,
    required this.transactionDao,
    required this.watermarkDao,
    required this.logger,
    required this.contentHmacKey,
    this.batchLimit = 100,
    this.maxBatchesPerRun = 10,
  });

  /// The incremental path: everything newer than the watermark.
  ///
  /// Called from the broadcast-triggered worker (ADR-006 Layer 1), the
  /// 15-minute periodic sweep (Layer 2), on app foreground, and after boot.
  /// **All four call exactly this method** — one code path, so a bug cannot
  /// exist on the rare path and not the common one, and the self-healing
  /// property is automatic rather than a special case.
  Future<IngestionRunResult> runIncremental() async {
    IngestionRunResult total = const IngestionRunResult();

    // Drain in batches rather than processing exactly one.
    //
    // A single batch would mean a user coming back after a week with 300 new
    // messages sees only the first `batchLimit` of them, and the rest only
    // trickle in one sweep at a time. `maxBatchesPerRun` still bounds the
    // work so an expedited worker cannot blow through ADR-006's ~10-second
    // budget on a first run over a huge inbox — whatever is left is picked up
    // by the next sweep, because the watermark says exactly where to resume.
    for (int batchNumber = 0; batchNumber < maxBatchesPerRun; batchNumber++) {
      final IngestWatermarkRow row = await watermarkDao.current();
      final List<RawSmsRecord> batch = await smsSource.readSince(
        IngestCursor(
          lastProcessedProviderId: row.lastProcessedSmsProviderId,
          lastProcessedDate: row.lastProcessedSmsDate,
        ),
        limit: batchLimit,
      );
      if (batch.isEmpty) {
        break;
      }

      final IngestionRunResult batchResult = await processAll(
        batch,
        advanceWatermark: true,
      );
      total = _merge(total, batchResult);

      // A failure stops the watermark advancing (see `processAll`), so
      // continuing would re-read the same batch forever. Stop and let the
      // next sweep retry.
      if (batchResult.failedWithError > 0) {
        break;
      }
    }

    return total;
  }

  /// Processes [records] in order, oldest first.
  ///
  /// [advanceWatermark] is false for the historical import, which walks
  /// *backwards in time* through already-delivered messages and must not move
  /// the incremental watermark — doing so would skip everything that arrived
  /// while the import was running.
  Future<IngestionRunResult> processAll(
    List<RawSmsRecord> records, {
    required bool advanceWatermark,
  }) async {
    IngestionRunResult result = const IngestionRunResult();

    // ## The subtle bug this flag exists to prevent
    //
    // Messages are processed oldest-first and the watermark is monotonic. So
    // if message #5 throws and message #6 then succeeds, advancing the
    // watermark to 6 would move it **past** the failed #5 — and because the
    // next sweep only reads `_id > watermark`, #5 would never be read again.
    // It would be lost silently and permanently, which is exactly what NFR-A7
    // forbids, and it would look like nothing went wrong.
    //
    // So: once anything in this run fails, the watermark stops advancing for
    // the rest of the run. The messages after the failure are still
    // **processed** (NFR-R5 — one bad message must not stop the batch), and
    // the next sweep re-reads from the failure onwards. Re-reading is
    // harmless: ADR-017 D1's UNIQUE constraints suppress anything already
    // written. Losing a message is not harmless, so the trade is easy.
    bool advancingIsSafe = advanceWatermark;

    for (final RawSmsRecord record in records) {
      try {
        // ## One message = one database transaction
        //
        // ADR-006 requires the watermark to advance "in the same database
        // transaction as the writes it produced". This is where that is made
        // literally true, and it is worth understanding *why* it is not merely
        // tidiness — there are two crash windows here and they are not equally
        // harmless:
        //
        //  1. Crash between the last write and the watermark advance. Benign:
        //     the message is re-read next sweep and ADR-017 D1 suppresses it.
        //     This is the window everyone thinks of, and it is the safe one.
        //  2. Crash between `rawMessageDao.insert` and
        //     `transactionDao.insertFromParsedSms`. **Not benign.** The
        //     raw-message row — and therefore the `content_hmac` D1 dedups
        //     on — is already committed, so the next sweep sees "already
        //     processed" and suppresses the message. The transaction row is
        //     never written, and never will be. A financial message is lost
        //     silently: the NFR-A7 failure, arriving through the dedup
        //     mechanism that is supposed to protect us.
        //
        // Wrapping the unit of work closes window 2 and makes window 1 moot.
        // Drift rolls the transaction back on a throw and rethrows, so the
        // `catch` below still sees the error and still counts it — a failed
        // message now leaves *no* partial trace at all, which is what makes
        // retrying it on the next run correct rather than merely hopeful.
        //
        // The parse happens inside the transaction too. That is deliberate:
        // the unit of work is "everything this app concluded about this
        // message", and a local single-writer SQLite transaction held across a
        // few milliseconds of regex costs nothing.
        result = await database.transaction(
          () => _processOne(record, result, advanceWatermark: advancingIsSafe),
        );
      } catch (_) {
        // The caught error is deliberately discarded rather than logged: an
        // exception thrown from deep inside a parse routinely carries the
        // offending text in its `message`, and this log line goes into a
        // buffer the user may later share (ADR-015, NFR-S4). The provider id
        // is enough to find the message again on the device; the text is not
        // ours to copy into a diagnostic file.
        logger.warning(
          LogEvent(
            category: _logMessageFailed,
            entityId: record.providerId.toString(),
          ),
        );
        result = result._plus(examined: 1, failedWithError: 1);
        advancingIsSafe = false;
      }
    }

    return result;
  }

  IngestionRunResult _merge(IngestionRunResult a, IngestionRunResult b) =>
      IngestionRunResult(
        examined: a.examined + b.examined,
        transactionsWritten: a.transactionsWritten + b.transactionsWritten,
        flaggedAsPossibleDuplicate:
            a.flaggedAsPossibleDuplicate + b.flaggedAsPossibleDuplicate,
        suppressedAsExactDuplicate:
            a.suppressedAsExactDuplicate + b.suppressedAsExactDuplicate,
        routedToReviewQueue: a.routedToReviewQueue + b.routedToReviewQueue,
        ignoredAsNoise: a.ignoredAsNoise + b.ignoredAsNoise,
        discardedNonFinancialSender:
            a.discardedNonFinancialSender + b.discardedNonFinancialSender,
        failedWithError: a.failedWithError + b.failedWithError,
      );

  Future<IngestionRunResult> _processOne(
    RawSmsRecord record,
    IngestionRunResult running, {
    required bool advanceWatermark,
  }) async {
    // --- Step 0: sanitise BEFORE anything else can see the body -----------
    //
    // Ordering note that is easy to get backwards: the per-bank `redact[]`
    // patterns depend on knowing the bank, which is resolved from the
    // *sender*, not the body. So we can pick the right patterns without ever
    // having looked at the text — which is what lets sanitisation come first
    // (ADR-013's "at the ingestion boundary") rather than after parsing.
    final List<RegExp> bankRedaction = parser.redactionPatternsForSender(
      record.address,
    );
    final SanitizedSmsText sanitized = SmsSanitizer.sanitize(
      record.body,
      extraRedactPatterns: bankRedaction,
    );

    // ADR-007 step 1, done exactly once. The result feeds both the parser and
    // the dedup HMAC, so the two can never disagree about what "the same
    // message" is.
    final String normalized = SmsTextNormalizer.normalize(sanitized.value);

    final ParseOutcome outcome = parser.parse(
      sanitized: sanitized,
      normalizedBody: normalized,
      sender: record.address,
    );

    final String contentHmac = ContentHmac.compute(
      key: contentHmacKey,
      normalizedBody: normalized,
      sender: record.address,
      smsTimestampUtc: record.receivedAt,
    );

    // The exhaustive switch. `ParseOutcome` is sealed, so adding a case
    // upstream without handling it here is a compile error — which is how
    // "we never silently drop a message" is enforced by the toolchain rather
    // than by vigilance.
    return switch (outcome) {
      // --- NFR-P4's strictest clause: no row at all ----------------------
      //
      // Not even a timestamp. A personal message from a friend leaves no
      // trace in this app whatsoever — a promise the transparency screen
      // (US-F4) makes out loud. Note the watermark still advances: the
      // message *was* examined and there is nothing to come back for.
      NotFinancialSender() => await _finish(
        record,
        running._plus(examined: 1, discardedNonFinancialSender: 1),
        advanceWatermark: advanceWatermark,
      ),

      // --- Known bank, recognised noise: counter row, NO body ------------
      IgnoredMessage(:final String classification) => await _withDedupGuard(
        contentHmac: contentHmac,
        record: record,
        running: running,
        advanceWatermark: advanceWatermark,
        onNew: () async {
          await rawMessageDao.insertIgnoredNoContent(
            smsProviderId: record.providerId.toString(),
            sender: record.address,
            receivedAt: record.receivedAt,
            contentHmac: contentHmac,
            bankId: outcome.rule.bankId,
            classification: classification,
          );
          return running._plus(examined: 1, ignoredAsNoise: 1);
        },
      ),

      // --- Known bank, not understood: the review queue ------------------
      //
      // The safety net (US-A4, AC-A4.1). The sanitised text IS retained here,
      // because AC-A4.2 requires the user to be able to read the original and
      // fill in what the parser missed.
      UnparsedMessage(:final String reason, :final RuleReference? rule) =>
        await _withDedupGuard(
          contentHmac: contentHmac,
          record: record,
          running: running,
          advanceWatermark: advanceWatermark,
          onNew: () async {
            await rawMessageDao.insert(
              smsProviderId: record.providerId.toString(),
              sender: record.address,
              receivedAt: record.receivedAt,
              sanitizedText: sanitized,
              contentHmac: contentHmac,
              bankId: rule?.bankId,
              classification: 'financial_unparsed',
              unparsedReason: reason,
              unparsedRuleId: rule?.ruleId.isEmpty ?? true
                  ? null
                  : rule!.ruleId,
            );
            return running._plus(examined: 1, routedToReviewQueue: 1);
          },
        ),

      // --- A transaction -------------------------------------------------
      ParsedMessage() => await _withDedupGuard(
        contentHmac: contentHmac,
        record: record,
        running: running,
        advanceWatermark: advanceWatermark,
        onNew: () async => _writeTransaction(
          record: record,
          sanitized: sanitized,
          contentHmac: contentHmac,
          parsed: outcome,
          running: running,
        ),
      ),
    };
  }

  /// ADR-017 **D1**, applied uniformly to every stored outcome.
  ///
  /// D1 is enforced by two `UNIQUE` constraints — `raw_message
  /// .sms_provider_id` and `raw_message.content_hmac` — so it holds at the
  /// database layer, against any writer, not merely against this method. The
  /// pre-check here exists to make the common case cheap and to produce a
  /// clean count; the constraint is what makes it *correct*.
  ///
  /// The two keys catch different things and both are needed:
  ///  - `sms_provider_id` — a re-scan of the same inbox row (AC-A3.3). This
  ///    is what makes the historical import safe to restart at any point.
  ///  - `content_hmac` — a **carrier redelivery**, which arrives as a *new*
  ///    provider row with identical content (AC-A5.1).
  Future<IngestionRunResult> _withDedupGuard({
    required String contentHmac,
    required RawSmsRecord record,
    required IngestionRunResult running,
    required bool advanceWatermark,
    required Future<IngestionRunResult> Function() onNew,
  }) async {
    final existing = await rawMessageDao.findByContentHmac(contentHmac);
    if (existing != null) {
      // "Suppress silently, but write a diagnostic event recording the
      // suppression" (ADR-017 D1). Silent to the *user*; never silent to the
      // audit of what the app did, or "where did my transaction go?" becomes
      // unanswerable.
      logger.info(
        LogEvent(
          category: _logDuplicateSuppressed,
          entityId: record.providerId.toString(),
        ),
      );
      return _finish(
        record,
        running._plus(examined: 1, suppressedAsExactDuplicate: 1),
        advanceWatermark: advanceWatermark,
      );
    }

    final IngestionRunResult next = await onNew();
    return _finish(record, next, advanceWatermark: advanceWatermark);
  }

  /// Writes the raw message, runs ADR-017's D2/D3 tiers, and writes the
  /// transaction — all inside **one** database transaction with the watermark
  /// advance that follows in [_finish].
  Future<IngestionRunResult> _writeTransaction({
    required RawSmsRecord record,
    required SanitizedSmsText sanitized,
    required String contentHmac,
    required ParsedMessage parsed,
    required IngestionRunResult running,
  }) async {
    final ParsedFields fields = parsed.fields;
    final Money? amount = fields.amount;
    if (amount == null) {
      // Defensive: a ParsedMessage with no amount should be impossible,
      // because every transaction rule in the bundled pack lists `amount` in
      // `requiredFields`. An *imported* pack (ADR-007's answer to R-11) is
      // not obliged to, though — so rather than trust it, route to the review
      // queue. A zero-amount transaction is the one outcome that must never
      // happen: it is invisible in a list and wrong in every total.
      await rawMessageDao.insert(
        smsProviderId: record.providerId.toString(),
        sender: record.address,
        receivedAt: record.receivedAt,
        sanitizedText: sanitized,
        contentHmac: contentHmac,
        bankId: parsed.rule.bankId,
        classification: 'financial_unparsed',
        unparsedReason: UnparsedReason.requiredFieldMissing,
        unparsedRuleId: parsed.rule.ruleId,
      );
      return running._plus(examined: 1, routedToReviewQueue: 1);
    }

    // `occurredAt` may be absent if an imported pack does not require it;
    // fall back to the delivery time and *say so* via `timeSource`, rather
    // than leaving the transaction undated and invisible to every period
    // report (architecture §7.4).
    final DateTime occurredAt = fields.occurredAtUtc ?? record.receivedAt;
    final String timeSource = fields.occurredAtUtc == null
        ? 'received_at_fallback'
        : (fields.timeSource ?? 'sms_local_assumed');

    final DuplicateDecision decision = await _evaluateDuplicates(
      fields: fields,
      amount: amount,
      occurredAt: occurredAt,
      messageType: parsed.rule.messageType,
    );

    final int rawMessageId = await rawMessageDao.insert(
      smsProviderId: record.providerId.toString(),
      sender: record.address,
      receivedAt: record.receivedAt,
      sanitizedText: sanitized,
      contentHmac: contentHmac,
      bankId: parsed.rule.bankId,
      classification: 'financial_parsed',
    );

    final int transactionId = await transactionDao.insertFromParsedSms(
      amount: amount,
      convertedAmount: fields.convertedAmount,
      feeAmount: fields.feeAmount,
      fxRate: fields.exchangeRate,
      merchantRawText: fields.merchantRawText,
      occurredAt: occurredAt,
      timeSource: timeSource,
      direction: parsed.direction,
      transactionType: parsed.rule.messageType,
      affectsSpend: parsed.affectsSpend,
      referenceNumber: fields.referenceNumber,
      instrumentKind: fields.instrument?.kind,
      instrumentMaskedRef: fields.instrument?.maskedIdentifier,
      sourceMessageId: rawMessageId,
      rulePackId: parsed.rule.packId,
      rulePackVersion: parsed.rule.packVersion,
      ruleId: parsed.rule.ruleId,
      needsReview: decision.action == DuplicateAction.acceptAndFlag,
      reviewReason: decision.reviewReason,
      possibleDuplicateOfId: decision.matchedTransactionId,
    );

    if (decision.action == DuplicateAction.acceptAndFlag &&
        decision.matchedTransactionId != null) {
      // Flag the *counterpart* too, so the pair is visible from either side.
      // Note: both rows remain in the list and in every total until the user
      // decides. Never auto-removed (ADR-017, and Linear KHA-21's done check
      // asks for a test that this is so).
      await transactionDao.flagAsPossibleDuplicate(
        id: decision.matchedTransactionId!,
        otherId: transactionId,
        reviewReason: decision.reviewReason ?? ReviewReason.possibleDuplicate,
      );
      return running._plus(examined: 1, flaggedAsPossibleDuplicate: 1);
    }

    return running._plus(examined: 1, transactionsWritten: 1);
  }

  Future<DuplicateDecision> _evaluateDuplicates({
    required ParsedFields fields,
    required Money amount,
    required DateTime occurredAt,
    required String messageType,
  }) async {
    final List<TransactionRow> rows = await transactionDao
        .duplicateCandidatesSince(
          occurredAt.subtract(DuplicatePolicy.heuristicWindow),
        );

    return DuplicatePolicy.decide(
      incomingInstrumentRef: fields.instrument?.maskedIdentifier,
      incomingAmount: amount,
      incomingOccurredAt: occurredAt,
      incomingReferenceNumber: fields.referenceNumber,
      incomingMerchant: fields.merchantRawText,
      incomingType: messageType,
      existing: <DuplicateCandidate>[
        for (final TransactionRow row in rows)
          DuplicateCandidate(
            transactionId: row.id,
            transactionType: row.transactionType,
            instrumentMaskedRef: row.instrumentMaskedRef,
            amount: Money.tryParse(
              row.amountAmount,
              currency: row.amountCurrency,
            ),
            occurredAt: row.occurredAt,
            referenceNumber: row.referenceNumber,
            merchantRawText: row.merchantRawText,
          ),
      ],
    );
  }

  /// Advances the watermark past [record].
  ///
  /// Always reached from inside the per-message `database.transaction(...)`
  /// opened in [processAll], so this update and the writes that preceded it
  /// commit as one — see that method for the crash window this closes. Drift
  /// routes a DAO call made inside a `transaction()` block on the same
  /// `AppDatabase` to the transaction's executor, which is why the DAOs need
  /// no explicit handle passed to them.
  ///
  /// The `advanceTo` update is *also* monotonic in SQL, so two overlapping
  /// sweeps cannot rewind each other regardless.
  Future<IngestionRunResult> _finish(
    RawSmsRecord record,
    IngestionRunResult result, {
    required bool advanceWatermark,
  }) async {
    if (advanceWatermark) {
      await watermarkDao.advanceTo(
        smsProviderId: record.providerId,
        smsDate: record.receivedAt,
      );
    }
    return result;
  }
}

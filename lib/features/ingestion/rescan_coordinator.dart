/// **KHA-133 — "check my banks again": re-scanning already-swept history
/// after the rule pack was widened.**
///
/// Normative spec: `docs/architecture.md` ADR-006, the `KHA-133 decision`
/// subsection (items **(A)–(F)**). Read that before changing anything here;
/// almost every line below is a decision recorded there rather than a choice
/// made in this file.
///
/// ---
///
/// ## The trap this exists to escape
///
/// Three separately-correct behaviours compose into one that is not:
///
/// 1. `IngestionPipeline._processOne`'s `NotFinancialSender` arm **advances
///    the watermark** for a message it discarded ("examined, nothing to come
///    back for" — right, in isolation).
/// 2. `IngestionPipeline.runIncremental` only ever reads
///    `_id > lastProcessedSmsProviderId`.
/// 3. `HistoricalImporter.runOrResume` returns immediately once
///    `importState == completed`, which is deliberately terminal.
///
/// Together: **a rule-pack fix can only ever affect the future.** KHA-128
/// shipped correct `senderPatterns` for seven real banks, and recovered
/// nothing already in the user's inbox, because every one of those messages
/// had already been examined under the wrong patterns, discarded, and left
/// behind the watermark. The only recovery the app otherwise offers is "clear
/// app data", which destroys the transactions that *are* correct and, per
/// ADR-004/ADR-012, can cost the whole encrypted store. That is a data-loss
/// event wearing a recovery path's clothes.
///
/// ## Why re-scanning cannot double-count (the property that makes this safe)
///
/// This is the part worth being sure about, because getting it wrong shows up
/// as the user's money being counted twice. Verified against the code, not
/// assumed — ADR-006's Q1 table:
///
/// | What happened the first time | Rows it left | What the re-scan does |
/// |---|---|---|
/// | `NotFinancialSender` — **KHA-133's whole population** | **none at all**: the arm goes straight to `_finish` and never enters `_withDedupGuard`, so there is no `sms_provider_id` row and no `content_hmac` | the write is a **first** write. There is nothing to double-count because dedup was never given anything to catch |
/// | parsed / unparsed / ignored | a `raw_message` row carrying **both** D1 UNIQUE keys | the pre-check hits and the message is counted `suppressedAsExactDuplicate`; no second row, no second transaction |
///
/// Both halves hold, and they hold for *opposite* reasons — which is why the
/// dedup-safety tests assert both, separately.
///
/// The one real hole in that argument was that `_withDedupGuard` pre-checked
/// only `content_hmac`, and `content_hmac` is a function of the active pack
/// (it hashes text sanitised with the bank's `redact[]`). Closed by item (F)
/// before this file existed — see `RawMessageDao.findBySmsProviderId`.
///
/// ## Privacy: re-reading is not re-retaining
///
/// ADR-006 Q2, stated rather than left implicit. NFR-P4 governs what the
/// **database retains**, not what the ingestion isolate may momentarily read —
/// the same reading ADR-007 v1.5 already established. And a re-scan reads
/// strictly *less* than the sweep this app runs every fifteen minutes:
/// [recheckAllBanks] resolves each in-window sender **and stops there** unless
/// it belongs to a bank the pack already recognises. A message from a friend
/// is never sanitised, never normalised, never regex-evaluated, and never
/// handed to the pipeline at all — see the `bankIdForSender` filter in
/// [_walk], which is the entire mechanism.
///
/// ## What this is NOT
///
/// - **Not automatic.** ADR-006 Q3 rejected re-scanning on pack change: on a
///   side-loaded build that means every APK install silently re-walks the
///   month and back-dates transactions. A user who did not ask cannot tell a
///   recovered transaction from a wrong one.
/// - **Not a second pipeline.** Item (A): every message goes through
///   `IngestionPipeline.processAll` — the identical call
///   `HistoricalImporter._walk` makes. ADR-006's self-healing property comes
///   entirely from there being one path.
/// - **Not an `importState` reset.** Item (G2) forbids it by name. It is two
///   lines and it is dedup-safe and it is still refused, because it re-opens a
///   state made terminal on purpose and creates a second recovery path that
///   would diverge from this one.
/// - **Not "full history".** Item (C)'s window is the ground the import
///   already covered. A message from a previous month was never in scope and
///   still is not.
///
/// ## Relationship to US-A6 (KHA-129)
///
/// This is a deliberate *subset* of the mechanism the Banks & Senders screen
/// must build regardless (AC-A6.10's "check again", pointed at banks that were
/// configured wrongly rather than at a newly linked sender). Nothing here is
/// thrown away when US-A6 lands: that screen scopes the same coordinator to
/// one bank. The per-bank entry point ([recheckBank]) is already here for it.
///
/// **One half of item (D) is not yet reachable, and that is not an omission.**
/// The item defines the sender set as "each distinct in-window sender tested
/// against that bank's pack `senderPatterns` **and user links**". User-linked
/// senders (AC-A6.3) are US-A6's feature and **do not exist in the schema
/// yet** — there is nothing to consult. When they land, the single place that
/// changes is `MessageParser.bankIdForSender`, because that is the only thing
/// this file asks about a sender. No change is needed here.
library;

import '../../core/logging/log_event.dart';
import '../../core/logging/safe_logger.dart';
import '../../core/time/clock.dart';
import '../../data/dao/audit_log_dao.dart';
import '../../data/dao/ingest_watermark_dao.dart';
import '../parsing/message_parser.dart';
import 'ingestion_pipeline.dart';
import 'sms_source.dart';

/// `LogEvent.category` labels. Compile-time constants at the call site, never
/// built from runtime data (ADR-015).
const String _logRescanStarted = 'ingestion.rescan_started';
const String _logRescanFinished = 'ingestion.rescan_finished';

/// ADR-010 audit vocabulary for the re-check. `entityType` is the *ingestion
/// run itself* rather than any one transaction, because the thing being
/// explained is "why did three weeks of transactions appear at once".
const String rescanAuditEntityType = 'ingestion';
const String rescanAuditEntityId = 'rescan';
const String rescanAuditAction = 'rescan';

/// What one re-scan did, in a shape the UI can render without knowing anything
/// about ingestion.
///
/// Wraps [IngestionRunResult] rather than replacing it — item (E) says to
/// return the existing counts — and adds the two facts a *result screen* needs
/// that a *pipeline run* has no reason to carry: how far back we looked, and
/// how many messages were in that window before the bank filter narrowed it.
final class RescanResult {
  /// The pipeline's own counts, over the messages that were actually
  /// re-examined. `counts.examined` is "how many bank messages we re-read";
  /// `counts.transactionsWritten` is the number the user is really asking
  /// about.
  final IngestionRunResult counts;

  /// Item (C)'s lower bound — `min(importFromDate, startOfCurrentMonthUtc)`.
  /// Shown to the user so "nothing new found" is unambiguous about *what
  /// ground* was covered.
  final DateTime windowFromUtc;

  /// Every message in the window, including the ones whose sender belongs to
  /// no known bank and were therefore never opened.
  ///
  /// `messagesInWindow - counts.examined` is exactly the number of messages
  /// this run looked at the sender of and nothing else — the privacy claim in
  /// this file's header, as an arithmetic identity rather than a promise.
  final int messagesInWindow;

  const RescanResult({
    required this.counts,
    required this.windowFromUtc,
    required this.messagesInWindow,
  });

  /// Nothing changed. Drives the "Nothing new found" copy.
  ///
  /// Deliberately *not* `counts.examined == 0`: a re-scan that re-examined 200
  /// messages and suppressed all 200 as already-known found nothing new, and
  /// telling the user "200 messages checked" without "0 added" would read as
  /// though something happened.
  bool get foundNothingNew =>
      counts.transactionsWritten == 0 &&
      counts.flaggedAsPossibleDuplicate == 0 &&
      counts.routedToReviewQueue == 0;

  /// Transactions the user can now see that they could not before — the
  /// flagged-as-possible-duplicate ones included, because those are written
  /// rows that appear in the list (ADR-017 never auto-removes them).
  int get newTransactions =>
      counts.transactionsWritten + counts.flaggedAsPossibleDuplicate;

  /// Items added to the Needs Review inbox. A recovered message from a bank
  /// whose `messageRules` are still empty lands here rather than as a
  /// transaction, and that is a *success* for this feature: the message is no
  /// longer invisible.
  int get newReviewItems => counts.routedToReviewQueue;

  @override
  String toString() =>
      'RescanResult(window: ${windowFromUtc.toIso8601String()}, '
      'inWindow: $messagesInWindow, $counts)';
}

/// Item (A): the one mechanism, the one code path.
final class RescanCoordinator {
  final SmsSource smsSource;
  final IngestionPipeline pipeline;
  final IngestWatermarkDao watermarkDao;

  /// Used **only** for [MessageParser.bankIdForSender] — this class never
  /// parses a body itself. Body parsing belongs to the pipeline, and having
  /// exactly one parser call here is what keeps the privacy claim checkable by
  /// reading the file.
  final MessageParser parser;

  /// Item (E): the re-check is recorded as a **user action** (ADR-010).
  final AuditLogDao auditLogDao;

  final Clock clock;
  final SafeLogger logger;

  /// Messages read per chunk. Same size and same reason as
  /// `HistoricalImporter.chunkSize`: a chunk boundary is a yield point that
  /// lets the UI isolate breathe, so the app stays responsive (NFR-R3) while
  /// a month of inbox is walked.
  final int chunkSize;

  const RescanCoordinator({
    required this.smsSource,
    required this.pipeline,
    required this.watermarkDao,
    required this.parser,
    required this.auditLogDao,
    required this.clock,
    required this.logger,
    this.chunkSize = 50,
  });

  /// **The action behind the "Check my banks again" button.**
  ///
  /// Item (D): *"'Check all banks again' is permitted as this same call looped
  /// over the known banks… it is a loop, **not** a second mechanism and **not**
  /// a global blanket re-scan."* Expressed here as one walk with an
  /// any-known-bank filter rather than N walks over the same inbox, which is
  /// the same set of messages read once instead of seven times — identical
  /// scope, a seventh of the work.
  ///
  /// Safe to run repeatedly. That is a hard requirement, not a nicety: the
  /// user's most likely second action after "Nothing new found" is to press it
  /// again. See this file's header for why re-running cannot double-count.
  ///
  /// [shouldContinue] is polled between chunks so the caller can stop cleanly
  /// when the screen is dismissed. Stopping early is always safe — this
  /// operation persists no cursor, so there is nothing to leave inconsistent.
  Future<RescanResult> recheckAllBanks({bool Function()? shouldContinue}) {
    return _run(
      isTargetSender: (String sender) => parser.bankIdForSender(sender) != null,
      scopeLabel: 'all',
      shouldContinue: shouldContinue,
    );
  }

  /// The per-bank form — AC-A6.10 proper, for US-A6's Banks & Senders screen.
  ///
  /// Shipped now because it is the *same call* with a narrower predicate, and
  /// because item (D) specifies the mechanism as bank-scoped with "all banks"
  /// as the loop over it. Building the general form later, from the special
  /// case, is how two code paths get created.
  Future<RescanResult> recheckBank(
    String bankId, {
    bool Function()? shouldContinue,
  }) {
    return _run(
      isTargetSender: (String sender) =>
          parser.bankIdForSender(sender) == bankId,
      scopeLabel: bankId,
      shouldContinue: shouldContinue,
    );
  }

  // ---------------------------------------------------------------------
  // The walk
  // ---------------------------------------------------------------------

  Future<RescanResult> _run({
    required bool Function(String sender) isTargetSender,
    required String scopeLabel,
    bool Function()? shouldContinue,
  }) async {
    final DateTime from = await _windowStart();

    // A count, never content (ADR-015) — and a count of the *window*, not of
    // what was opened.
    final int inWindow = await smsSource.countRange(from: from);
    logger.info(LogEvent(category: _logRescanStarted, count: inWindow));

    final IngestionRunResult counts = await _walk(
      from: from,
      isTargetSender: isTargetSender,
      shouldContinue: shouldContinue,
    );

    final RescanResult result = RescanResult(
      counts: counts,
      windowFromUtc: from,
      messagesInWindow: inWindow,
    );

    await _recordUserAction(scopeLabel: scopeLabel, result: result);
    logger.info(
      LogEvent(category: _logRescanFinished, count: counts.transactionsWritten),
    );
    return result;
  }

  /// **Item (C): `min(importFromDate, startOfCurrentMonthUtc(now))`.**
  ///
  /// Not a freshly computed start-of-month, and the difference is not
  /// cosmetic. `importFromDate` was frozen into the watermark row when the
  /// import began; an import that started on the 30th of last month
  /// legitimately covered ground that "the 1st of the current month" now
  /// excludes. **A re-scan must never cover less than the import it is
  /// correcting** — otherwise the messages most in need of recovery are
  /// exactly the ones it skips.
  ///
  /// `min` rather than "the stored one if present": if the stored date is
  /// somehow *later* than this month's start (a clock change, a restored
  /// backup), the wider of the two is still the safe answer.
  Future<DateTime> _windowStart() async {
    // Read only. This method — and this class — never call a watermark *write*
    // method, which is how item (B)'s "neither cursor moves" is enforced by
    // the call graph rather than by an argument that has to be passed
    // correctly. `grep -n 'watermarkDao\.' rescan_coordinator.dart` returns
    // exactly one line, and it is this one.
    // `.toUtc()` is load-bearing, not defensive tidying. Drift's sqlite3
    // backend stores a `DateTimeColumn` as a Unix timestamp and hands it back
    // as a **local-flagged** `DateTime` — the right instant, the wrong flag.
    // Comparisons are unaffected (Dart compares instants), but the screen
    // shifts this value into Riyadh wall-clock time before printing it, and
    // shifting an already-local value prints a date up to a day out. Normalise
    // once, here, so every consumer gets what the field name promises.
    final DateTime? imported = (await watermarkDao.current()).importFromDate
        ?.toUtc();
    final DateTime monthStart = RiyadhCalendar.startOfCurrentMonthUtc(
      clock.nowUtc(),
    );
    if (imported == null) {
      return monthStart;
    }
    return imported.isBefore(monthStart) ? imported : monthStart;
  }

  Future<IngestionRunResult> _walk({
    required DateTime from,
    required bool Function(String sender) isTargetSender,
    bool Function()? shouldContinue,
  }) async {
    IngestionRunResult total = const IngestionRunResult();
    int position = 0;

    while (true) {
      if (shouldContinue != null && !shouldContinue()) {
        // A clean stop needs no bookkeeping at all — item (B): a re-scan is a
        // transient operation, not persisted state. Contrast
        // `HistoricalImporter._walk`, which must `pauseImport()` here.
        return total;
      }

      final List<RawSmsRecord> chunk = await smsSource.readRange(
        from: from,
        afterProviderId: position,
        limit: chunkSize,
      );
      if (chunk.isEmpty) {
        break;
      }

      // ## The privacy filter, and it is the whole of it
      //
      // Only messages whose sender resolves to a bank in scope are handed to
      // the pipeline. Everything else is dropped **here**, after reading the
      // sender string and before anything reads the body — which is exactly
      // the depth the hard sender gate already goes to on every one of the
      // app's ordinary sweeps.
      //
      // `parser.bankIdForSender` is a pure function of the sender and the
      // active packs, so this is also the point at which a widened rule pack
      // starts mattering: a sender that resolved to nothing before KHA-128 and
      // resolves to `bank-aljazira` now is admitted here for the first time.
      final List<RawSmsRecord> inScope = <RawSmsRecord>[
        for (final RawSmsRecord record in chunk)
          if (isTargetSender(record.address)) record,
      ];

      if (inScope.isNotEmpty) {
        total = _merge(
          total,
          await pipeline.processAll(
            inScope,
            // **Item (B), and the single most important argument in this
            // file.** The incremental watermark is not ours to move: it says
            // "how far forward have we got", and this walk is deliberately
            // re-treading ground behind it. Moving it would skip everything
            // that arrived while the re-scan ran.
            advanceWatermark: false,
          ),
        );
      }

      // ## Why a failure does NOT stop this walk, unlike the import's
      //
      // `HistoricalImporter._walk` stops on `failedWithError` because its
      // cursor is **persisted**, and advancing a persisted cursor past a
      // message that threw loses that message permanently (NFR-A7).
      //
      // This walk persists nothing. `position` dies with the method, so there
      // is no cursor to corrupt and the NFR-A7 argument simply does not apply.
      // What *would* apply if we copied the stop is worse: a message that
      // fails deterministically would abort every future re-scan at the same
      // point, so the recovery the user pressed the button for would never
      // reach the messages behind it — and pressing it again would fail
      // identically, forever. So NFR-R5 governs here instead ("one bad message
      // never stops the batch"), and the failure count is carried to the UI
      // rather than swallowed.
      final int nextPosition = chunk.last.providerId;
      if (nextPosition <= position) {
        // Unreachable against a source honouring `afterProviderId`, and a
        // cheap guarantee that a misbehaving one cannot spin this loop
        // forever on a device.
        break;
      }
      position = nextPosition;
    }

    return total;
  }

  /// **Item (E)**: *"Record the re-check as a user action (ADR-010) … Not
  /// optional: a re-scan makes weeks-old transactions appear at once, and
  /// retroactive numbers with no stated cause are worse than no numbers."*
  ///
  /// Counts only — no sender, no body, no transaction text. The audit trail is
  /// answering "why did July change?", which needs quantities and a cause, not
  /// content.
  ///
  /// Written **after** the walk so the recorded counts are the real ones. A
  /// crash mid-walk therefore records nothing, which is the right direction to
  /// be wrong in: an audit entry claiming a re-scan that did not finish would
  /// be a false explanation, and this trail's only value is that it is true.
  Future<void> _recordUserAction({
    required String scopeLabel,
    required RescanResult result,
  }) {
    return auditLogDao.append(
      entityType: rescanAuditEntityType,
      entityId: rescanAuditEntityId,
      action: rescanAuditAction,
      // ADR-010's vocabulary. `user`, not `parser`: the whole point of the
      // decision was that this happens because somebody asked for it.
      actor: 'user',
      actorDetail: scopeLabel,
      changedAt: clock.nowUtc(),
      fieldChanges: <AuditFieldChange>[
        AuditFieldChange(
          field: 'windowFromUtc',
          to: result.windowFromUtc.toIso8601String(),
        ),
        AuditFieldChange(
          field: 'messagesInWindow',
          to: result.messagesInWindow.toString(),
        ),
        AuditFieldChange(
          field: 'messagesExamined',
          to: result.counts.examined.toString(),
        ),
        AuditFieldChange(
          field: 'transactionsAdded',
          to: result.newTransactions.toString(),
        ),
        AuditFieldChange(
          field: 'reviewItemsAdded',
          to: result.newReviewItems.toString(),
        ),
        AuditFieldChange(
          field: 'duplicatesSuppressed',
          to: result.counts.suppressedAsExactDuplicate.toString(),
        ),
        AuditFieldChange(
          field: 'failed',
          to: result.counts.failedWithError.toString(),
        ),
      ],
    );
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
}

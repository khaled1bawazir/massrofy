/// **KHA-157 (E) — clearing up after the flood, on the user's word.**
///
/// Normative spec: `docs/architecture.md` ADR-006, the `KHA-157 decision`
/// subsection, item **(E)**. Read it before changing anything here.
///
/// ---
///
/// ## What happened, and what is left to do about it
///
/// The incremental sweep used to read `_id > 0` on a fresh install — every SMS
/// the device had ever received — because nothing seeded ADR-006's watermark
/// away from its default of zero. On the first real device that ran it, **424
/// messages from months and years outside AC-A3.1's window** landed in the
/// Needs Review inbox. The seed in `IngestionPipeline.runIncremental` stops
/// that happening again; it does nothing about the rows already sitting there.
///
/// ## Two things this deliberately is not
///
/// **Not an automatic migration.** Item (E) rejects deleting these rows on
/// upgrade outright: a silent bulk deletion of user-visible financial rows
/// during an app update is a worse failure than the flood it cleans up, and
/// nothing in the data can tell an item the user has already acted on from one
/// they have not. So the app *offers*; the user decides.
///
/// **Not a watermark correction.** There is nothing to correct. The flood
/// advanced the watermark past the whole inbox as it went, so on the affected
/// device it is accidentally already at the high-water mark — the seed's guard
/// sees a non-null date and does nothing — and `advanceTo`'s monotonic `WHERE`
/// would refuse a backwards correction regardless.
///
/// ## Why this cannot re-flood, which is what makes deleting safe
///
/// Deleting a `raw_message` row normally means the next sweep re-ingests the
/// message (the row carries ADR-017 D1's dedup keys). Not these rows, and the
/// argument is a bound rather than a hope. Every row this touches is older than
/// [OutOfWindowDiscard.windowStartUtc], and both of the app's only two ways of
/// reaching backwards stop at or after that line:
///
///  - the **incremental** sweep reads `_id >` the watermark, which the flood
///    itself already pushed above every one of these rows;
///  - KHA-133's **re-scan** reads from `min(importFromDate,
///    startOfCurrentMonthUtc(now))` — and that expression *is* the cutoff used
///    here, computed by the same code, so the bound is identical by
///    construction rather than by two functions happening to agree.
///
/// ## Scope: the unparsed queue, and nothing else
///
/// Only still-pending items in the "Not understood" tab — `raw_message` rows
/// classified `financial_unparsed` and not yet dismissed. **No transaction is
/// ever deleted here.** A message the parser understood became a transaction
/// and is the user's financial record; item (E)'s objection to silently
/// deleting user-visible financial rows applies with full force to those, and
/// they are out of scope for this action entirely.
library;

import '../../core/logging/log_event.dart';
import '../../core/logging/safe_logger.dart';
import '../../core/time/clock.dart';
import '../../data/dao/audit_log_dao.dart';
import '../../data/dao/ingest_watermark_dao.dart';
import '../../data/dao/raw_message_dao.dart';
import '../../data/db/app_database.dart';
import 'review_queue.dart';

/// `LogEvent.category` labels. Compile-time constants at the call site, never
/// built from runtime data (ADR-015).
const String _logDiscardPerformed = 'ingestion.out_of_window_discard';

/// ADR-010 audit vocabulary, following `RescanCoordinator`'s pattern:
/// `entityType` is the **ingestion run itself** rather than any one message,
/// because the thing being explained is "why did 424 items disappear from my
/// review inbox at once", which is not a fact about any single row.
const String outOfWindowDiscardAuditEntityType = 'ingestion';
const String outOfWindowDiscardAuditEntityId = 'out_of_window_discard';
const String outOfWindowDiscardAuditAction = 'discard_out_of_window';

/// The action behind the "discard them" button.
final class OutOfWindowDiscard {
  final AppDatabase database;
  final RawMessageDao rawMessageDao;
  final IngestWatermarkDao watermarkDao;

  /// Item (E): the discard is recorded as a **user action** (ADR-010).
  final AuditLogDao auditLogDao;

  final Clock clock;
  final SafeLogger logger;

  const OutOfWindowDiscard({
    required this.database,
    required this.rawMessageDao,
    required this.watermarkDao,
    required this.auditLogDao,
    required this.clock,
    required this.logger,
  });

  /// **The cutoff: `min(importFromDate, startOfCurrentMonthUtc(now))`.**
  ///
  /// Byte-for-byte the same expression as `RescanCoordinator._windowStart`,
  /// and that is the point rather than a coincidence. The safety argument for
  /// deleting these rows is *"no future read can reach them"*, and the only
  /// read that reaches backwards at all is the re-scan. Using a different —
  /// even a slightly wider — bound here would leave a band of rows the discard
  /// deletes and the re-scan would happily re-ingest, so the message would
  /// reappear and the button would look broken.
  ///
  /// `importFromDate` is the value frozen when the historical import began; an
  /// import started on the 30th of last month legitimately covered ground that
  /// "the 1st of this month" now excludes. `min` takes the wider of the two,
  /// which is the safe direction: it deletes less.
  ///
  /// `.toUtc()` is load-bearing, not tidying — Drift's sqlite3 backend returns
  /// a `DateTimeColumn` as a **local-flagged** `DateTime` (the right instant,
  /// the wrong flag), and the screen shifts this value into Riyadh wall-clock
  /// time before printing it. Shifting an already-local value prints a date up
  /// to a day out, on the one label the user is asked to trust before
  /// deleting.
  Future<DateTime> windowStartUtc() async {
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

  /// How many still-pending review items fall outside the window, for the
  /// banner. Never renders anything on its own.
  Future<OutOfWindowReviewSummary> summary() async {
    final DateTime from = await windowStartUtc();
    return OutOfWindowReviewSummary(
      itemCount: await rawMessageDao.countPendingReviewReceivedBefore(from),
      windowStartUtc: from,
    );
  }

  /// Deletes them, and records that it did. Returns the number removed.
  ///
  /// ## One transaction, and the count is measured inside it
  ///
  /// The count, the delete and the audit entry commit together or not at all.
  /// That matters in the direction people usually forget: an audit entry
  /// claiming a discard that then rolled back is a *false* explanation, and
  /// this trail's entire value is that it is true. Drift's `delete().go()`
  /// returns the number of rows it actually removed, so the audited figure is
  /// what the database did rather than what a separate `SELECT COUNT(*)` saw a
  /// moment earlier.
  ///
  /// ## The cutoff is recomputed here rather than passed in
  ///
  /// The screen holds a cutoff from whenever it last built, and the user may
  /// have left the confirmation dialog open across a month boundary. Deleting
  /// against a stale bound could remove a message that is now inside the
  /// window. Recomputing costs one indexed read and removes the whole class of
  /// problem.
  Future<int> discardOutOfWindowReviewItems() async {
    final DateTime from = await windowStartUtc();

    final int deleted = await database.transaction(() async {
      final int removed = await rawMessageDao.deletePendingReviewReceivedBefore(
        from,
      );
      if (removed == 0) {
        // Nothing happened, so nothing is recorded. An audit entry saying
        // "discarded 0" is noise in a trail whose readability is the reason
        // ADR-010 keeps it append-only.
        return 0;
      }

      await auditLogDao.append(
        entityType: outOfWindowDiscardAuditEntityType,
        entityId: outOfWindowDiscardAuditEntityId,
        action: outOfWindowDiscardAuditAction,
        // ADR-010's vocabulary. `user`, not `parser` and not `system`: item
        // (E)'s whole argument is that this happens because somebody asked
        // for it.
        actor: 'user',
        changedAt: clock.nowUtc(),
        // Counts and a bound. No sender, no body, no message text — the trail
        // answers "why did my review inbox empty?", which needs a quantity and
        // a cause, not content (NFR-S4).
        fieldChanges: <AuditFieldChange>[
          AuditFieldChange(field: 'windowStartUtc', to: from.toIso8601String()),
          AuditFieldChange(field: 'reviewItemsDiscarded', to: '$removed'),
        ],
      );
      return removed;
    });

    logger.info(LogEvent(category: _logDiscardPerformed, count: deleted));
    return deleted;
  }
}

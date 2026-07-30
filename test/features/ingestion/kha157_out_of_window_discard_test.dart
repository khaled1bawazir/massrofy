/// **KHA-157 (E) — the user-triggered, date-bounded discard.**
///
/// Normative spec: `docs/architecture.md` ADR-006, the `KHA-157 decision`
/// subsection, item **(E)**.
///
/// ---
///
/// The seed stops the flood recurring. It does nothing about the 424 rows
/// already in the reporting device's Needs Review inbox, and item (E) refuses
/// to delete them automatically — *"a silent bulk deletion of user-visible
/// financial rows during an app update is a worse failure than the flood"*.
/// So the app offers, and this file pins what the offer is allowed to touch.
///
/// The tests are organised around the four things that could go wrong, in
/// descending order of how bad they would be:
///
///  1. it deletes something **inside** the window (data loss);
///  2. it deletes something the user has **already acted on** (data loss,
///     harder to notice);
///  3. it deletes and the rows **come back** (the fix looks broken);
///  4. it deletes and nothing records that it did (ADR-010).
///
/// NFR-M3: every message body here is fabricated.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/logging/diagnostic_ring_buffer.dart';
import 'package:massrofy/core/logging/safe_logger.dart';
import 'package:massrofy/core/text/sms_sanitizer.dart';
import 'package:massrofy/core/time/clock.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/ingest_watermark_dao.dart';
import 'package:massrofy/data/dao/raw_message_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ingestion/out_of_window_discard.dart';
import 'package:massrofy/features/ingestion/review_queue.dart';

import '../../support/plain_test_database.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 11);

/// "Now" for every test here: 30 July 2026, 09:00 UTC. The Riyadh calendar
/// month therefore began at 2026-06-30T21:00Z — the three-hour offset that
/// `RiyadhCalendar` exists for, and which the cutoff must respect.
final DateTime _nowUtc = DateTime.utc(2026, 7, 30, 9);
final DateTime _windowStart = RiyadhCalendar.startOfCurrentMonthUtc(_nowUtc);

void main() {
  late AppDatabase db;
  late RawMessageDao rawMessageDao;
  late IngestWatermarkDao watermarkDao;
  late AuditLogDao auditLogDao;
  late OutOfWindowDiscard discard;

  setUp(() {
    db = openPlainTestDatabase();
    rawMessageDao = RawMessageDao(db);
    watermarkDao = IngestWatermarkDao(db);
    auditLogDao = AuditLogDao(db, auditChainKey: _testChainKey);
    discard = OutOfWindowDiscard(
      database: db,
      rawMessageDao: rawMessageDao,
      watermarkDao: watermarkDao,
      auditLogDao: auditLogDao,
      clock: FixedClock(_nowUtc),
      logger: SafeLogger(DiagnosticRingBuffer()),
    );
  });

  tearDown(() async => db.close());

  /// One pending review-queue row, i.e. what the flood produced.
  Future<int> unparsedAt(DateTime receivedAt, {String tag = 'a'}) =>
      rawMessageDao.insert(
        smsProviderId: '${receivedAt.millisecondsSinceEpoch}-$tag',
        sender: 'D360',
        receivedAt: receivedAt,
        sanitizedText: SmsSanitizer.sanitize(
          'D360: Purchase of SAR 41.00 with Mada Debit Card ending 4472 '
          'at SYNTHETIC STORE $tag',
        ),
        contentHmac: 'hmac-${receivedAt.millisecondsSinceEpoch}-$tag',
        bankId: 'bank-d360',
        classification: 'financial_unparsed',
        unparsedReason: 'no_rule_matched',
      );

  /// A message the parser DID understand — it became a transaction, and is not
  /// this feature's business at any date.
  Future<int> parsedAt(DateTime receivedAt, {String tag = 'p'}) =>
      rawMessageDao.insert(
        smsProviderId: '${receivedAt.millisecondsSinceEpoch}-$tag',
        sender: 'D360',
        receivedAt: receivedAt,
        sanitizedText: SmsSanitizer.sanitize('D360: understood message $tag'),
        contentHmac: 'hmac-${receivedAt.millisecondsSinceEpoch}-$tag',
        bankId: 'bank-d360',
        classification: 'financial_parsed',
      );

  final DateTime longAgo = DateTime.utc(2025, 11, 4, 8);
  final DateTime alsoLongAgo = DateTime.utc(2026, 2, 17, 13);
  final DateTime inWindow = DateTime.utc(2026, 7, 12, 10);

  group('the cutoff', () {
    test(
      'is the start of the Riyadh calendar month when no import has run',
      () async {
        expect(await discard.windowStartUtc(), _windowStart);
        expect(
          _windowStart,
          DateTime.utc(2026, 6, 30, 21),
          reason:
              'a Riyadh month begins at 21:00 UTC on the last day of the '
              'previous month — the same three-hour correction AC-A3.1 applies',
        );
      },
    );

    test('widens to importFromDate when the import began EARLIER, so the '
        'discard never reaches ground the re-scan can still cover', () async {
      // An import started on the 28th of the previous month legitimately
      // covered ground that "the 1st of this month" now excludes. `min` of the
      // two is the safe answer: it deletes less.
      final DateTime earlier = DateTime.utc(2026, 6, 28);
      await watermarkDao.beginImport(
        fromDate: earlier,
        totalCandidates: 0,
        startCursor: 0,
      );

      expect(await discard.windowStartUtc(), earlier);
    });

    test('does NOT narrow when importFromDate is later than the month start — '
        'a clock change must not widen what gets deleted', () async {
      final DateTime later = DateTime.utc(2026, 7, 20);
      await watermarkDao.beginImport(
        fromDate: later,
        totalCandidates: 0,
        startCursor: 0,
      );

      expect(await discard.windowStartUtc(), _windowStart);
    });
  });

  group('the summary', () {
    test('counts only pending review items from before the window', () async {
      await unparsedAt(longAgo, tag: '1');
      await unparsedAt(alsoLongAgo, tag: '2');
      await unparsedAt(inWindow, tag: '3');

      final OutOfWindowReviewSummary summary = await discard.summary();
      expect(summary.itemCount, 2);
      expect(summary.windowStartUtc, _windowStart);
      expect(summary.hasItems, isTrue);
    });

    test(
      'is empty on a healthy install, so the banner never appears',
      () async {
        await unparsedAt(inWindow);

        expect((await discard.summary()).hasItems, isFalse);
      },
    );

    test(
      'a message received exactly AT the window start is inside it',
      () async {
        await unparsedAt(_windowStart);

        expect(
          (await discard.summary()).itemCount,
          0,
          reason:
              'the bound is strictly `<`. An off-by-one here deletes a message '
              'the import was supposed to cover.',
        );
      },
    );
  });

  group('the discard', () {
    test('removes the out-of-window pending items and nothing else', () async {
      final int old1 = await unparsedAt(longAgo, tag: '1');
      final int old2 = await unparsedAt(alsoLongAgo, tag: '2');
      final int recent = await unparsedAt(inWindow, tag: '3');
      final int understood = await parsedAt(longAgo, tag: 'p1');

      expect(await discard.discardOutOfWindowReviewItems(), 2);

      expect(await rawMessageDao.byId(old1), isNull);
      expect(await rawMessageDao.byId(old2), isNull);
      expect(
        await rawMessageDao.byId(recent),
        isNotNull,
        reason: 'inside the window — never this action\'s business',
      );
      expect(
        await rawMessageDao.byId(understood),
        isNotNull,
        reason:
            'a message the parser understood became a transaction. Item (E) '
            'rejects deleting user-visible financial rows, and that applies '
            'with full force to the record behind one.',
      );
    });

    test('**leaves an already-dismissed message alone** — the user acted on '
        'it, and this action must not silently undo that', () async {
      final int dismissed = await unparsedAt(longAgo, tag: 'd');
      await rawMessageDao.dismissAsNotTransaction(dismissed);

      expect(await discard.discardOutOfWindowReviewItems(), 0);
      expect(
        await rawMessageDao.byId(dismissed),
        isNotNull,
        reason:
            'item (E) scopes this to STILL-PENDING items precisely because '
            'nothing in the data can tell an item the user has acted on from '
            'one they have not — so the ones they have are excluded by the '
            'predicate rather than by judgement',
      );
    });

    test('empties the review queue the screen renders', () async {
      await unparsedAt(longAgo, tag: '1');
      await unparsedAt(alsoLongAgo, tag: '2');
      expect(await rawMessageDao.watchReviewQueue().first, hasLength(2));

      await discard.discardOutOfWindowReviewItems();

      expect(await rawMessageDao.watchReviewQueue().first, isEmpty);
      expect((await discard.summary()).hasItems, isFalse);
    });

    test(
      'is safe to run twice — the second is a no-op, not an error',
      () async {
        await unparsedAt(longAgo);

        expect(await discard.discardOutOfWindowReviewItems(), 1);
        expect(await discard.discardOutOfWindowReviewItems(), 0);
      },
    );

    test('does not move either watermark cursor', () async {
      await unparsedAt(longAgo);
      final IngestWatermarkRow before = await watermarkDao.current();

      await discard.discardOutOfWindowReviewItems();

      final IngestWatermarkRow after = await watermarkDao.current();
      expect(
        after.lastProcessedSmsProviderId,
        before.lastProcessedSmsProviderId,
      );
      expect(after.lastProcessedSmsDate, before.lastProcessedSmsDate);
      expect(after.importCursor, before.importCursor);
      expect(
        after.importState,
        before.importState,
        reason:
            'this action removes rows. It is not an ingestion run and has no '
            'business claiming to be one.',
      );
    });
  });

  group('the audit trail (ADR-010)', () {
    test('records the discard as a USER action, with counts and the bound but '
        'no message content', () async {
      await unparsedAt(longAgo, tag: '1');
      await unparsedAt(alsoLongAgo, tag: '2');

      await discard.discardOutOfWindowReviewItems();

      final List<AuditEntryRow> entries = await auditLogDao.queryFor(
        outOfWindowDiscardAuditEntityType,
        outOfWindowDiscardAuditEntityId,
      );
      expect(entries, hasLength(1));
      expect(entries.single.action, outOfWindowDiscardAuditAction);
      expect(
        entries.single.actor,
        'user',
        reason: 'the whole argument for (E) is that somebody asked for it',
      );

      final String changes = entries.single.fieldChangesJson;
      expect(changes, contains('reviewItemsDiscarded'));
      expect(changes, contains('2'));
      expect(changes, contains(_windowStart.toIso8601String()));
      expect(
        changes,
        isNot(contains('SYNTHETIC STORE')),
        reason:
            'counts and a bound, never content — the trail answers "why did '
            'my review inbox empty?" (NFR-S4)',
      );
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('writes NO entry when there was nothing to discard — a trail full of '
        '"discarded 0" is a trail nobody reads', () async {
      await unparsedAt(inWindow);

      await discard.discardOutOfWindowReviewItems();

      expect(
        await auditLogDao.queryFor(
          outOfWindowDiscardAuditEntityType,
          outOfWindowDiscardAuditEntityId,
        ),
        isEmpty,
      );
    });
  });
}

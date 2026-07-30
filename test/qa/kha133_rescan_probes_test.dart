/// **QA adversarial probes for KHA-133 — PR #46, head `17e3444`.**
///
/// These are *not* a re-statement of the engineer's own suite
/// (`test/features/ingestion/rescan_coordinator_test.dart`, 23 tests, all
/// passing). They exist to attack the parts of the feature that suite does not
/// reach, chosen because this PR writes **money rows over ground the app has
/// already walked** — the one operation in this build where a mistake shows up
/// as the user's July total being wrong.
///
/// Each probe below states the property it attacks and why the existing suite
/// does not already cover it.
///
///  - **P1** — item (F)'s counterfactual. The engineer's `item (F)` test asserts
///    `failedWithError == 0` *with* the fix in place. That assertion also passes
///    if the hmac never drifted at all, i.e. if the whole premise were false and
///    `findByContentHmac` were still doing all the work. P1 proves the premise
///    independently: it computes both hmacs and shows they differ, then shows
///    the content-hmac lookup **misses** and the provider-id lookup **hits**.
///    Without that, the item (F) test is not evidence that the new key is
///    load-bearing.
///  - **P2** — the ordinary sweep running **concurrently with** a re-scan. The
///    suite tests the two *sequentially* in both orders. Overlapping them is a
///    genuinely different surface: both call `processAll` against the same
///    database, and the dedup guard is a check-then-insert.
///  - **P3** — a re-scan while the historical import is **mid-flight**
///    (`paused`, with a real cursor). The suite only covers `completed`, which
///    is the state with nothing left to corrupt.
///  - **P4** — item (C)'s `min()`, behaviourally. The engineer's suite **does**
///    cover the branch itself (its `item (C)` test sets `importFromDate` to 25
///    June and asserts `windowFromUtc`), so this is a complement rather than a
///    gap: P4 adds the *consequence* — that a message sitting in the extra
///    ground the `min()` opens up is actually re-examined, and that a message
///    older than the window is still excluded when both are in one inbox.
///  - **P5** — the new `sms_provider_id` pre-check exercised through the live
///    pipeline rather than through a redact change: the same inbox row seen
///    twice with different text. This is the path that used to throw.
///  - **P6** — business oracle: the number the screen shows the user must equal
///    the number of transaction rows that actually appeared, recomputed from
///    the database rather than from the pipeline's own counters.
///  - **P7** — item (B) as a source-level guard: no watermark *write* method is
///    even named in the coordinator.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/logging/diagnostic_ring_buffer.dart';
import 'package:massrofy/core/logging/safe_logger.dart';
import 'package:massrofy/core/text/sms_sanitizer.dart';
import 'package:massrofy/core/text/sms_text_normalizer.dart';
import 'package:massrofy/core/time/clock.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/ingest_watermark_dao.dart';
import 'package:massrofy/data/dao/raw_message_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ingestion/content_hmac.dart';
import 'package:massrofy/features/ingestion/ingestion_pipeline.dart';
import 'package:massrofy/features/ingestion/rescan_coordinator.dart';
import 'package:massrofy/features/ingestion/sms_source.dart';
import 'package:massrofy/features/parsing/message_parser.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_loader.dart';
import 'package:massrofy/features/parsing/rule_pack_message_parser.dart';

import '../support/fake_sms_source.dart';
import '../support/plain_test_database.dart';
import '../support/watermark_seed.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i);

/// Late July 2026, matching the engineer's suite so fixtures land in-window.
final DateTime _now = DateTime.utc(2026, 7, 28, 18);

/// The real bundled pack, with named banks' `senderPatterns` / `redact[]`
/// swapped. Mutating the shipped JSON rather than hand-writing a fixture keeps
/// every rule and priority exactly as it ships.
RulePack _pack({
  Map<String, List<String>> senderPatterns = const <String, List<String>>{},
  Map<String, List<String>> redact = const <String, List<String>>{},
}) {
  final Map<String, Object?> json =
      jsonDecode(File('assets/rule_packs/sa-core.json').readAsStringSync())
          as Map<String, Object?>;

  for (final Object? bank in json['banks']! as List<Object?>) {
    final Map<String, Object?> bankMap = bank! as Map<String, Object?>;
    final String bankId = bankMap['bankId']! as String;
    if (senderPatterns.containsKey(bankId)) {
      bankMap['senderPatterns'] = senderPatterns[bankId];
    }
    if (redact.containsKey(bankId)) {
      for (final Object? rule in bankMap['messageRules']! as List<Object?>) {
        (rule! as Map<String, Object?>)['redact'] = redact[bankId];
      }
    }
  }
  return RulePackLoader.parse(jsonEncode(json));
}

/// Before KHA-128: Aljazira's sender pattern matches nothing a device sends,
/// so its messages are discarded and the watermark advances past them.
RulePackMessageParser _parserBefore() => RulePackMessageParser(
  packs: <RulePack>[
    _pack(
      senderPatterns: <String, List<String>>{
        'bank-aljazira': <String>[r'^THIS-NEVER-MATCHES$'],
        'al-rajhi': <String>[r'^NOR-DOES-THIS$'],
      },
    ),
  ],
);

/// After KHA-128: the pack exactly as shipped.
RulePackMessageParser _parserAfter() =>
    RulePackMessageParser(packs: <RulePack>[_pack()]);

const String _aljaziraPurchaseBody =
    'شراء\n'
    'بطاقة:مدى-****4821\n'
    'مبلغ:152.75 SAR\n'
    'لدى:EXTRA MART 0042\n'
    'في:28-07-26 14:32';

const String _aljaziraSecondBody =
    'شراء\n'
    'بطاقة:مدى-****4821\n'
    'مبلغ:64.00 SAR\n'
    'لدى:TAMIMI MARKETS\n'
    'في:27-07-26 09:15';

const String _personalBody = 'Are we still on for lunch tomorrow?';

RawSmsRecord _record({
  required int id,
  required String sender,
  required String body,
  DateTime? receivedAt,
}) => RawSmsRecord(
  providerId: id,
  address: sender,
  body: body,
  receivedAt:
      receivedAt ?? DateTime.utc(2026, 7, 20, 10).add(Duration(minutes: id)),
);

List<RawSmsRecord> _inbox() => <RawSmsRecord>[
  _record(id: 1, sender: 'BAJ', body: _aljaziraPurchaseBody),
  _record(id: 2, sender: 'MOM', body: _personalBody),
  _record(id: 4, sender: 'BAJ', body: _aljaziraSecondBody),
];

void main() {
  late AppDatabase db;
  late AuditLogDao auditLogDao;
  late RawMessageDao rawMessageDao;
  late TransactionDao transactionDao;
  late IngestWatermarkDao watermarkDao;
  late SafeLogger logger;

  setUp(() async {
    db = openPlainTestDatabase();
    auditLogDao = AuditLogDao(db, auditChainKey: _testChainKey);
    rawMessageDao = RawMessageDao(db);
    transactionDao = TransactionDao(db, auditLogDao);
    watermarkDao = IngestWatermarkDao(db);
    logger = SafeLogger(DiagnosticRingBuffer());
    // KHA-157: these probes exercise the KHA-133 re-scan, which never moves
    // the incremental watermark. Seeding at the beginning keeps the ordinary
    // sweep each probe runs first behaving as it did.
    await seedWatermarkAtBeginning(watermarkDao);
  });

  tearDown(() async => db.close());

  IngestionPipeline pipelineWith(MessageParser parser, SmsSource source) =>
      IngestionPipeline(
        database: db,
        smsSource: source,
        parser: parser,
        rawMessageDao: rawMessageDao,
        transactionDao: transactionDao,
        watermarkDao: watermarkDao,
        logger: logger,
        contentHmacKey: _testChainKey,
      );

  RescanCoordinator coordinatorWith(MessageParser parser, SmsSource source) =>
      RescanCoordinator(
        smsSource: source,
        pipeline: pipelineWith(parser, source),
        watermarkDao: watermarkDao,
        parser: parser,
        auditLogDao: auditLogDao,
        clock: FixedClock(_now),
        logger: logger,
      );

  Future<int> transactionCount() async =>
      (await transactionDao.select(transactionDao.transactions).get()).length;

  /// Recomputes a message's `content_hmac` exactly the way
  /// `IngestionPipeline._processOne` does, under whichever pack [parser]
  /// carries. This is the whole point of P1: the hmac is a *function of the
  /// pack*, and this reproduces that dependency rather than asserting it.
  String hmacUnder(MessageParser parser, RawSmsRecord record) {
    final SanitizedSmsText sanitized = SmsSanitizer.sanitize(
      record.body,
      extraRedactPatterns: parser.redactionPatternsForSender(record.address),
    );
    return ContentHmac.compute(
      key: _testChainKey,
      normalizedBody: SmsTextNormalizer.normalize(sanitized.value),
      sender: record.address,
    );
  }

  // =====================================================================
  // P1 — item (F): prove the premise, then prove the new key is what saves it
  // =====================================================================
  group('P1 item (F): the content_hmac really does drift with redact[]', () {
    test(
      'a redact[] change moves the hmac, so findByContentHmac MISSES and only '
      'findBySmsProviderId still identifies the stored row',
      () async {
        final FakeSmsSource source = FakeSmsSource(_inbox());

        // Store everything under the shipped pack (all redact arrays empty).
        await pipelineWith(_parserAfter(), source).runIncremental();
        expect(await transactionCount(), 2);

        final RawSmsRecord msg = _inbox().first; // providerId 1, BAJ
        final MessageParser shipped = _parserAfter();
        final MessageParser redacting = RulePackMessageParser(
          packs: <RulePack>[
            _pack(
              redact: <String, List<String>>{
                'bank-aljazira': <String>['EXTRA MART|TAMIMI MARKETS'],
              },
            ),
          ],
        );

        final String storedHmac = hmacUnder(shipped, msg);
        final String driftedHmac = hmacUnder(redacting, msg);

        // (a) The architect's premise, asserted rather than trusted. If these
        //     were equal, item (F) would be solving a problem that does not
        //     exist and its regression test would be vacuous.
        expect(
          driftedHmac,
          isNot(storedHmac),
          reason:
              'ADR-006 Q1 claims content_hmac is a function of the active '
              "pack's redact[]. If this fails, that premise is wrong.",
        );

        // (b) The old pre-check misses the drifted message entirely...
        expect(
          await rawMessageDao.findByContentHmac(driftedHmac),
          isNull,
          reason:
              'the content-hmac key cannot recognise the row it wrote once '
              'the pack changed — this is the hole item (F) describes',
        );

        // (c) ...and the row is unmistakably still there, findable only by the
        //     key this PR added. This is what converts an unhandled UNIQUE
        //     violation into a counted `suppressedAsExactDuplicate`.
        final RawMessageRow? byProviderId = await rawMessageDao
            .findBySmsProviderId('1');
        expect(byProviderId, isNotNull);
        expect(byProviderId!.contentHmac, storedHmac);
      },
    );
  });

  // =====================================================================
  // P2 — the race the engineer's suite does not cover
  // =====================================================================
  group('P2 concurrency: an ordinary sweep overlapping a re-scan', () {
    test(
      'a live incremental sweep running CONCURRENTLY with a re-scan over the '
      'same inbox still writes each transaction exactly once',
      () async {
        // Why this is a distinct surface from the suite's sequential tests:
        // `_withDedupGuard` is a check-then-insert, and both entry points run
        // it against the same database. If the pre-check of run B lands
        // between the pre-check and the insert of run A, both would believe
        // the message is new. The engineer's tests run the two strictly one
        // after the other, so they can never produce that interleaving.
        //
        // Ground state: everything was discarded under the old patterns, so
        // there is real work for both runs to find and race over.
        final FakeSmsSource source = FakeSmsSource(_inbox());
        await pipelineWith(_parserBefore(), source).runIncremental();
        expect(await transactionCount(), 0);

        // Deliberately NOT awaited in sequence — both futures are in flight at
        // once and interleave at every `await` inside the pipeline.
        final Future<IngestionRunResult> sweep = pipelineWith(
          _parserAfter(),
          source,
        ).runIncremental();
        final Future<RescanResult> rescan = coordinatorWith(
          _parserAfter(),
          source,
        ).recheckAllBanks();

        final List<Object> both = await Future.wait(<Future<Object>>[
          sweep,
          rescan,
        ]);
        final IngestionRunResult sweepResult = both[0] as IngestionRunResult;
        final RescanResult rescanResult = both[1] as RescanResult;

        // The money property. Two purchases exist in the inbox; two rows must
        // exist in the ledger, no matter how the two runs interleaved.
        expect(
          await transactionCount(),
          2,
          reason: 'overlapping runs must not double-count',
        );

        // Neither run may have crashed its way to that number.
        expect(sweepResult.failedWithError, 0);
        expect(rescanResult.counts.failedWithError, 0);
        expect(sweepResult.isFullyAccountedFor, isTrue);
        expect(rescanResult.counts.isFullyAccountedFor, isTrue);

        // And nothing was lost: a third run finds nothing left to do.
        final RescanResult after = await coordinatorWith(
          _parserAfter(),
          source,
        ).recheckAllBanks();
        expect(after.foundNothingNew, isTrue);
        expect(await transactionCount(), 2);
      },
    );

    test('the concurrent sweep still owns the watermark: it advances, and the '
        're-scan does not hold it back', () async {
      // The mirror of the above. `advanceWatermark` is a per-call flag, and
      // the two calls disagree about it while overlapping. The sweep must
      // still get its watermark advance.
      final FakeSmsSource source = FakeSmsSource(_inbox());

      final Future<IngestionRunResult> sweep = pipelineWith(
        _parserAfter(),
        source,
      ).runIncremental();
      final Future<RescanResult> rescan = coordinatorWith(
        _parserAfter(),
        source,
      ).recheckAllBanks();
      await Future.wait(<Future<Object>>[sweep, rescan]);

      expect(
        (await watermarkDao.current()).lastProcessedSmsProviderId,
        4,
        reason:
            'the ordinary sweep must still reach the end of the inbox even '
            'when a re-scan is interleaved with it',
      );
      expect(await transactionCount(), 2);
    });
  });

  // =====================================================================
  // P3 — a re-scan during a MID-FLIGHT import, not a completed one
  // =====================================================================
  group('P3 item (B): a re-scan during an unfinished historical import', () {
    test(
      'a paused, half-finished import keeps its exact cursor and state across '
      'a re-scan, and still resumes correctly afterwards',
      () async {
        // The engineer's suite only re-scans over a `completed` import — the
        // state with nothing left to lose. A `paused` import carries a live
        // cursor and a progress count, which is the state a stray write would
        // actually damage.
        final FakeSmsSource source = FakeSmsSource(_inbox());

        await watermarkDao.beginImport(
          fromDate: DateTime.utc(2026, 7),
          totalCandidates: 3,
          startCursor: 0,
        );
        await watermarkDao.recordImportProgress(cursor: 2, processedCount: 1);
        await watermarkDao.pauseImport();

        final IngestWatermarkRow before = await watermarkDao.current();
        expect(before.importState, importStatePaused);
        expect(before.importCursor, 2);
        expect(before.importProcessedCount, 1);

        await coordinatorWith(_parserAfter(), source).recheckAllBanks();

        final IngestWatermarkRow after = await watermarkDao.current();
        expect(
          after.importState,
          importStatePaused,
          reason: 'item (B): a re-scan writes no import state, in any state',
        );
        expect(after.importCursor, before.importCursor);
        expect(after.importProcessedCount, before.importProcessedCount);
        expect(after.importTotalCandidates, before.importTotalCandidates);
        expect(after.importFromDate, before.importFromDate);
      },
    );
  });

  // =====================================================================
  // P4 — item (C)'s min(), on the branch that widens the window
  // =====================================================================
  group('P4 item (C): the window is the WIDER of the two candidates', () {
    test(
      'an importFromDate earlier than the month start widens the window, and a '
      'message in that extra ground is re-examined',
      () async {
        // "A re-scan must never cover less than the import it is correcting."
        // The engineer's `item (C)` test already pins `windowFromUtc` itself
        // for an early `importFromDate`. What it does not assert is that the
        // extra ground is then actually *walked*: a correct window paired with
        // a walk that still started at the month boundary would satisfy it.
        // This probe closes that by putting a June message in a July inbox.
        final DateTime earlyImport = DateTime.utc(2026, 6, 10);
        final DateTime monthStart = RiyadhCalendar.startOfCurrentMonthUtc(_now);
        expect(
          earlyImport.isBefore(monthStart),
          isTrue,
          reason: 'precondition: the stored date must be the wider one',
        );

        // A bank message from mid-June: inside the import's ground, outside a
        // freshly computed start-of-current-month.
        final RawSmsRecord june = _record(
          id: 7,
          sender: 'BAJ',
          body: _aljaziraPurchaseBody,
          receivedAt: DateTime.utc(2026, 6, 20, 12),
        );
        final FakeSmsSource source = FakeSmsSource(<RawSmsRecord>[
          june,
          ..._inbox(),
        ]);

        await watermarkDao.beginImport(
          fromDate: earlyImport,
          totalCandidates: 4,
          startCursor: 0,
        );

        final RescanResult result = await coordinatorWith(
          _parserAfter(),
          source,
        ).recheckAllBanks();

        expect(
          result.windowFromUtc,
          earlyImport,
          reason: 'item (C) takes the min of the two, not the month start',
        );
        expect(
          result.messagesInWindow,
          4,
          reason: 'the June message must be inside the window',
        );
        expect(
          result.counts.examined,
          3,
          reason: 'all three BAJ messages, including the June one',
        );
      },
    );

    test('a message OLDER than the window is never touched', () async {
      // The other side of item (C): "nobody should read 'check again' as
      // 'full history'". A May message must stay invisible.
      final RawSmsRecord may = _record(
        id: 6,
        sender: 'BAJ',
        body: _aljaziraPurchaseBody,
        receivedAt: DateTime.utc(2026, 5, 4, 9),
      );
      final FakeSmsSource source = FakeSmsSource(<RawSmsRecord>[
        may,
        ..._inbox(),
      ]);

      final RescanResult result = await coordinatorWith(
        _parserAfter(),
        source,
      ).recheckAllBanks();

      expect(result.messagesInWindow, 3, reason: 'May is outside the window');
      expect(result.counts.examined, 2, reason: 'only the two July BAJ rows');
      expect(await transactionCount(), 2);
    });
  });

  // =====================================================================
  // P5 — the new pre-check, through the live pipeline
  // =====================================================================
  group('P5 the sms_provider_id pre-check under a live run', () {
    test('the same inbox row seen twice with DIFFERENT text is suppressed, not '
        'counted as a failure', () async {
      // This is the pre-check's own path, reached without touching redact[].
      // Two records share providerId 1 and differ in body, so their hmacs
      // differ and only the provider-id key can catch the second. Before
      // this PR that second insert hit the UNIQUE constraint and was counted
      // `failedWithError` — which in an ordinary sweep also stalls the
      // watermark.
      final FakeSmsSource source = FakeSmsSource(<RawSmsRecord>[
        _record(id: 1, sender: 'BAJ', body: _aljaziraPurchaseBody),
        _record(id: 1, sender: 'BAJ', body: _aljaziraSecondBody),
      ]);

      final RescanResult result = await coordinatorWith(
        _parserAfter(),
        source,
      ).recheckAllBanks();

      expect(
        result.counts.failedWithError,
        0,
        reason:
            'a repeated provider id must be suppressed by the pre-check, '
            'not thrown by the UNIQUE constraint',
      );
      expect(result.counts.suppressedAsExactDuplicate, 1);
      expect(result.counts.transactionsWritten, 1);
      expect(await transactionCount(), 1);
      expect(result.counts.isFullyAccountedFor, isTrue);
    });
  });

  // =====================================================================
  // P6 — business oracle: the number on screen is the number in the ledger
  // =====================================================================
  group('P6 oracle: the reported count equals the real ledger delta', () {
    test('newTransactions equals the independently measured row delta, and the '
        'recovered amounts sum to the corpus figures', () async {
      // "A total appeared" is not a pass. The screen's headline number is
      // `RescanResult.newTransactions`, which is derived from the pipeline's
      // own counters — so it is exactly the number that would still look
      // right if the counters were wrong. Recompute it from the database.
      final FakeSmsSource source = FakeSmsSource(_inbox());
      await pipelineWith(_parserBefore(), source).runIncremental();

      final int before = await transactionCount();
      expect(before, 0);

      final RescanResult result = await coordinatorWith(
        _parserAfter(),
        source,
      ).recheckAllBanks();

      final List<TransactionRow> rows = await transactionDao
          .select(transactionDao.transactions)
          .get();

      expect(
        result.newTransactions,
        rows.length - before,
        reason:
            'the headline the user is shown must equal the number of rows '
            'that actually appeared',
      );

      // And the money itself, recomputed by hand from the two fixtures:
      // 152.75 + 64.00 = 216.75 SAR.
      final List<String> amounts =
          rows.map((TransactionRow r) => r.amountAmount).toList()..sort();
      expect(amounts, <String>['152.75', '64']);
      expect(
        rows.every((TransactionRow r) => r.amountCurrency == 'SAR'),
        isTrue,
      );
    });
  });

  // =====================================================================
  // P7 — item (B) as a source-level guard
  // =====================================================================
  group('P7 item (B): no watermark write is even reachable', () {
    test(
      'rescan_coordinator.dart names no watermark mutation method at all',
      () {
        // The behavioural tests prove the watermark did not move in the cases
        // they exercise. This proves there is no code path that *could* move
        // it, which is the stronger claim and the one the ADR actually makes
        // ("enforced by the call graph rather than by an argument that has to
        // be passed correctly").
        final String source = File(
          'lib/features/ingestion/rescan_coordinator.dart',
        ).readAsStringSync();

        // Strip doc comments: several of these names appear in prose that
        // explains why they are NOT called.
        final String code = source
            .split('\n')
            .where((String l) => !l.trimLeft().startsWith('//'))
            .join('\n');

        for (final String writeMethod in <String>[
          'advanceTo',
          'beginImport',
          'recordImportProgress',
          'completeImport',
          'pauseImport',
        ]) {
          expect(
            code.contains(writeMethod),
            isFalse,
            reason: 'item (B): the re-scan must never call $writeMethod',
          );
        }

        // Exactly one watermark call, and it is the documented read.
        final Iterable<RegExpMatch> calls = RegExp(
          r'watermarkDao\.(\w+)',
        ).allMatches(code);
        expect(calls.map((RegExpMatch m) => m.group(1)).toList(), <String>[
          'current',
        ]);
      },
    );
  });
}

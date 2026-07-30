/// **KHA-133 — the re-scan, against a real database and the real rule pack.**
///
/// Three properties carry this feature, and each has its own group below:
///
///  1. **It cannot double-count.** The re-scan writes money rows over ground
///     the app has already walked. If this is wrong, the user's July total is
///     wrong, and it is wrong in the direction that looks like fraud. This is
///     the group with the most tests, deliberately.
///  2. **It moves neither cursor** (ADR-006 item (B)). A re-scan that nudged
///     the incremental watermark would silently skip everything that arrived
///     while it ran; one that reset `importState` would re-open a state made
///     terminal on purpose.
///  3. **It actually recovers the real case.** The end-to-end group replays
///     precisely what happened to the human: messages examined and discarded
///     under wrong sender patterns, the patterns then corrected (KHA-128), and
///     the messages still invisible — until this button.
///
/// Everything runs against `openPlainTestDatabase()` and the **real** bundled
/// `sa-core.json`, because a fixture copy of the rules would let the tests
/// keep passing while the shipped parser was broken.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/logging/diagnostic_ring_buffer.dart';
import 'package:massrofy/core/logging/safe_logger.dart';
import 'package:massrofy/core/text/sms_sanitizer.dart';
import 'package:massrofy/core/time/clock.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/ingest_watermark_dao.dart';
import 'package:massrofy/data/dao/raw_message_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ingestion/historical_importer.dart';
import 'package:massrofy/features/ingestion/ingestion_pipeline.dart';
import 'package:massrofy/features/ingestion/rescan_coordinator.dart';
import 'package:massrofy/features/ingestion/sms_source.dart';
import 'package:massrofy/features/parsing/message_parser.dart';
import 'package:massrofy/features/parsing/parse_outcome.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_loader.dart';
import 'package:massrofy/features/parsing/rule_pack_message_parser.dart';

import '../../support/fake_sms_source.dart';
import '../../support/plain_test_database.dart';
import '../../support/watermark_seed.dart';

final List<int> _testChainKey = List<int>.generate(32, (int i) => i);

/// "Now" for every test here: late July 2026, so
/// `startOfCurrentMonthUtc` lands on 1 July and the fixtures below sit inside
/// the window.
final DateTime _now = DateTime.utc(2026, 7, 28, 18);

// ---------------------------------------------------------------------------
// Rule-pack fixtures: the same real pack, with senders bent on purpose
// ---------------------------------------------------------------------------

/// The bundled pack, optionally with some banks' `senderPatterns` and/or
/// `redact[]` arrays replaced.
///
/// Mutating the **real** pack's JSON rather than hand-writing a miniature one
/// keeps every rule, priority and regex exactly as shipped — the only
/// difference between the "before KHA-128" and "after KHA-128" parsers below
/// is the one field that actually changed in KHA-128.
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

/// The world **before** KHA-128: Aljazira's and Al Rajhi's sender patterns
/// match nothing a real device ever sends, so their messages are classified
/// `NotFinancialSender`, discarded, and the watermark advances past them.
RulePackMessageParser _parserBeforeKha128() => RulePackMessageParser(
  packs: <RulePack>[
    _pack(
      senderPatterns: <String, List<String>>{
        'bank-aljazira': <String>[r'^THIS-NEVER-MATCHES$'],
        'al-rajhi': <String>[r'^NOR-DOES-THIS$'],
      },
    ),
  ],
);

/// The world **after** KHA-128: the pack exactly as it ships.
RulePackMessageParser _parserAfterKha128() =>
    RulePackMessageParser(packs: <RulePack>[_pack()]);

// ---------------------------------------------------------------------------
// Inbox fixtures
// ---------------------------------------------------------------------------

/// A real Bank Aljazira POS purchase — copied from the synthetic corpus, which
/// pins it as `baj-01-pos-purchase` / 152.75 SAR.
const String _aljaziraPurchaseBody =
    'شراء\n'
    'بطاقة:مدى-****4821\n'
    'مبلغ:152.75 SAR\n'
    'لدى:EXTRA MART 0042\n'
    'في:28-07-26 14:32';

/// Aljazira again, a different amount, so the two are distinct messages under
/// both D1 keys.
const String _aljaziraSecondPurchaseBody =
    'شراء\n'
    'بطاقة:مدى-****4821\n'
    'مبلغ:64.00 SAR\n'
    'لدى:TAMIMI MARKETS\n'
    'في:27-07-26 09:15';

/// Al Rajhi is in the shipped pack with `senderPatterns` and an **empty**
/// `messageRules` list (KHA-128 added the sender, not the rules). So a
/// recovered Al Rajhi message becomes a *needs-review* item rather than a
/// transaction — which is the second half of what this feature must produce.
const String _alRajhiBody = 'عملية شراء بمبلغ 300.00 ريال لدى NOON';

/// A message from a person. It must never be opened by anything in this file.
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

/// The inbox every test starts from: two bank messages that KHA-128 was
/// written to recover, one bank message that can only reach the review queue,
/// and one message from a friend.
List<RawSmsRecord> _inbox() => <RawSmsRecord>[
  _record(id: 1, sender: 'BAJ', body: _aljaziraPurchaseBody),
  _record(id: 2, sender: 'MOM', body: _personalBody),
  _record(id: 3, sender: 'Al Rajhi Bank', body: _alRajhiBody),
  _record(id: 4, sender: 'BAJ', body: _aljaziraSecondPurchaseBody),
];

// ---------------------------------------------------------------------------
// A parser that records which bodies it was asked to look at
// ---------------------------------------------------------------------------

/// Wraps a real parser and records every sender whose **body** was parsed.
///
/// This is how the privacy claim in `rescan_coordinator.dart` is asserted
/// rather than asserted-about: ADR-006 Q2 says the re-scan looks at a
/// non-bank message's *sender string and stops there*. A test that only
/// checked "no row was written for MOM" would pass even if the coordinator
/// had sanitised, normalised and regex-evaluated her message first.
final class _RecordingParser implements MessageParser {
  final MessageParser _inner;
  final List<String> parsedSenders = <String>[];

  _RecordingParser(this._inner);

  @override
  ParseOutcome parse({
    required SanitizedSmsText sanitized,
    required String normalizedBody,
    required String sender,
  }) {
    parsedSenders.add(sender);
    return _inner.parse(
      sanitized: sanitized,
      normalizedBody: normalizedBody,
      sender: sender,
    );
  }

  @override
  List<RegExp> redactionPatternsForSender(String sender) =>
      _inner.redactionPatternsForSender(sender);

  @override
  String? bankIdForSender(String sender) => _inner.bankIdForSender(sender);
}

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
    // KHA-157: the subject is the KHA-133 re-scan, which never touches the incremental watermark. Seed at the beginning so the ordinary sweep these cases run first behaves as it did.
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

  Future<int> rawMessageCount() async => (await rawMessageDao.all()).length;

  // =======================================================================
  // 1. Dedup safety — the money-relevant property
  // =======================================================================
  group('dedup safety: a re-scan can never double-count', () {
    test(
      'running it twice over the same inbox writes each transaction exactly once',
      () async {
        final FakeSmsSource source = FakeSmsSource(_inbox());
        final RescanCoordinator coordinator = coordinatorWith(
          _parserAfterKha128(),
          source,
        );

        final RescanResult first = await coordinator.recheckAllBanks();
        final int afterFirst = await transactionCount();
        final int rawsAfterFirst = await rawMessageCount();

        final RescanResult second = await coordinator.recheckAllBanks();

        // The first run does real work: two Aljazira purchases become
        // transactions, the Al Rajhi message becomes a review item.
        expect(first.counts.transactionsWritten, 2);
        expect(first.counts.routedToReviewQueue, 1);
        expect(afterFirst, 2);

        // The second run examines exactly the same messages and writes
        // nothing. Asserted three ways on purpose — the count of rows, the
        // count of *new* rows, and the pipeline's own accounting — because a
        // dedup bug that produced a second transaction while reporting zero
        // would pass any one of them alone.
        expect(await transactionCount(), afterFirst);
        expect(await rawMessageCount(), rawsAfterFirst);
        expect(second.counts.transactionsWritten, 0);
        expect(second.counts.routedToReviewQueue, 0);
        expect(second.counts.suppressedAsExactDuplicate, 3);
        expect(second.counts.failedWithError, 0);
        expect(second.foundNothingNew, isTrue);

        // NFR-A7's arithmetic: nothing fell through an unhandled path.
        expect(first.counts.isFullyAccountedFor, isTrue);
        expect(second.counts.isFullyAccountedFor, isTrue);
      },
    );

    test('ten consecutive re-scans are indistinguishable from one', () async {
      // The user's most likely reaction to "Nothing new found" is to press it
      // again. And again. This is the blunt version of the property, and it is
      // here because the subtle version above could pass with an off-by-one
      // that only shows up on the third run.
      final FakeSmsSource source = FakeSmsSource(_inbox());
      final RescanCoordinator coordinator = coordinatorWith(
        _parserAfterKha128(),
        source,
      );

      await coordinator.recheckAllBanks();
      final int settled = await transactionCount();

      for (int i = 0; i < 9; i++) {
        await coordinator.recheckAllBanks();
      }

      expect(settled, 2);
      expect(await transactionCount(), settled);
      expect(await rawMessageCount(), 3);
    });

    test(
      'a message already stored by the ORDINARY sweep is suppressed, not rewritten',
      () async {
        // The other direction: the normal path wrote the rows, and the
        // re-scan walks over them. This is the case that actually happens on
        // a real device, where most of the window was ingested correctly and
        // only some senders were missed.
        final FakeSmsSource source = FakeSmsSource(_inbox());
        final IngestionPipeline pipeline = pipelineWith(
          _parserAfterKha128(),
          source,
        );

        final IngestionRunResult sweep = await pipeline.runIncremental();
        expect(sweep.transactionsWritten, 2);
        final int afterSweep = await transactionCount();

        final RescanResult rescan = await coordinatorWith(
          _parserAfterKha128(),
          source,
        ).recheckAllBanks();

        expect(rescan.counts.suppressedAsExactDuplicate, 3);
        expect(rescan.counts.transactionsWritten, 0);
        expect(await transactionCount(), afterSweep);
      },
    );

    test(
      'a discarded message leaves NO row, so its recovery is a first write — '
      'and only ever happens once',
      () async {
        // ADR-006 Q1's first table row, asserted directly. The
        // `NotFinancialSender` arm never enters the dedup guard, so there is
        // deliberately nothing for D1 to catch — which is why the *second*
        // half of this test matters more than the first.
        final FakeSmsSource source = FakeSmsSource(_inbox());

        await pipelineWith(_parserBeforeKha128(), source).runIncremental();

        // Nothing at all was retained for the two Aljazira messages.
        expect(await rawMessageCount(), 0);
        expect(await transactionCount(), 0);

        final RescanCoordinator coordinator = coordinatorWith(
          _parserAfterKha128(),
          source,
        );
        await coordinator.recheckAllBanks();
        expect(await transactionCount(), 2);

        final RescanResult again = await coordinator.recheckAllBanks();
        expect(again.counts.transactionsWritten, 0);
        expect(await transactionCount(), 2);
      },
    );

    test('item (F): a duplicate whose content_hmac drifted with the pack is '
        'SUPPRESSED, not reported as a failure', () async {
      // The one real hole ADR-006 Q1 found, and the reason
      // `findBySmsProviderId` exists.
      //
      // `contentHmac` hashes the body *after* the bank's `redact[]` patterns
      // have been applied, so it is a function of the pack, not of the
      // message. Change a `redact[]` and an already-stored message hashes
      // differently: the `content_hmac` pre-check misses, the insert hits
      // the `sms_provider_id` UNIQUE constraint, Drift throws, and a
      // completely benign duplicate is counted `failedWithError` — which
      // stops the watermark and shows the user a stalled pipeline.
      //
      // Every `redact` array in the shipped pack is `[]` today, so this is
      // latent. It goes live the first time any pack adds one. This test is
      // what makes sure it stays closed.
      final FakeSmsSource source = FakeSmsSource(_inbox());

      // Sweep 1: the pack as shipped (no redaction).
      await pipelineWith(_parserAfterKha128(), source).runIncremental();
      final int before = await rawMessageCount();
      expect(before, 3);

      // Sweep 2: same messages, same provider ids, but the pack now redacts
      // part of the body — so every recomputed hmac differs from the stored
      // one.
      final RulePackMessageParser withRedaction = RulePackMessageParser(
        packs: <RulePack>[
          _pack(
            redact: <String, List<String>>{
              'bank-aljazira': <String>['EXTRA MART|TAMIMI MARKETS'],
            },
          ),
        ],
      );

      final RescanResult result = await coordinatorWith(
        withRedaction,
        source,
      ).recheckAllBanks();

      expect(
        result.counts.failedWithError,
        0,
        reason: 'a redact[] change must not turn benign duplicates into errors',
      );
      expect(result.counts.suppressedAsExactDuplicate, 3);
      expect(await rawMessageCount(), before);
      expect(await transactionCount(), 2);
    });

    test(
      'findBySmsProviderId never matches a row that has no provider id',
      () async {
        // Manual entries (US-B4) store a `raw_message`-less transaction, and
        // other rows can carry a NULL `sms_provider_id`. SQL `=` is never true
        // against NULL, but the pre-check is new and this is one line to pin.
        await rawMessageDao.insert(
          smsProviderId: null,
          sender: 'BAJ',
          receivedAt: _now,
          sanitizedText: SmsSanitizer.sanitize('some body'),
          contentHmac: 'hmac-with-no-provider-id',
          classification: 'financial_parsed',
        );

        expect(await rawMessageDao.findBySmsProviderId('1'), isNull);

        // …and a re-scan therefore still records message #1 normally.
        final FakeSmsSource source = FakeSmsSource(_inbox());
        final RescanResult result = await coordinatorWith(
          _parserAfterKha128(),
          source,
        ).recheckAllBanks();
        expect(result.counts.transactionsWritten, 2);
      },
    );
  });

  // =======================================================================
  // 2. Neither cursor moves — ADR-006 item (B)
  // =======================================================================
  group('item (B): the re-scan disturbs no cursor', () {
    test('the incremental watermark is byte-for-byte unchanged', () async {
      final FakeSmsSource source = FakeSmsSource(_inbox());

      // Put the watermark somewhere real first: the ordinary sweep runs, sees
      // everything, and parks at message #4.
      await pipelineWith(_parserBeforeKha128(), source).runIncremental();

      final IngestWatermarkRow before = await watermarkDao.current();
      expect(
        before.lastProcessedSmsProviderId,
        4,
        reason:
            'precondition: the discard branch advanced the watermark — '
            'this is the trap KHA-133 exists to escape',
      );

      await coordinatorWith(_parserAfterKha128(), source).recheckAllBanks();

      final IngestWatermarkRow after = await watermarkDao.current();
      expect(
        after.lastProcessedSmsProviderId,
        before.lastProcessedSmsProviderId,
      );
      expect(after.lastProcessedSmsDate, before.lastProcessedSmsDate);
    });

    test(
      'the watermark does not move even when the re-scan writes transactions',
      () async {
        // The failure this guards against is not "the number changed" but
        // "the number changed *because we wrote rows*" — the pipeline's
        // `advanceWatermark` flag is per-message and threaded through
        // `_finish`, so a write path and a discard path could disagree.
        final FakeSmsSource source = FakeSmsSource(_inbox());
        await pipelineWith(_parserBeforeKha128(), source).runIncremental();
        final IngestWatermarkRow before = await watermarkDao.current();

        final RescanResult result = await coordinatorWith(
          _parserAfterKha128(),
          source,
        ).recheckAllBanks();

        expect(result.counts.transactionsWritten, 2);
        expect(
          (await watermarkDao.current()).lastProcessedSmsProviderId,
          before.lastProcessedSmsProviderId,
        );
      },
    );

    test('a message arriving DURING the window is still picked up by the next '
        'ordinary sweep', () async {
      // The consequence of the property above, stated as behaviour rather
      // than as a field value: if the re-scan had advanced the watermark to
      // the newest message it read, anything that arrived in the meantime
      // would be skipped forever.
      final List<RawSmsRecord> inbox = _inbox();
      final FakeSmsSource source = FakeSmsSource(inbox);

      await pipelineWith(_parserBeforeKha128(), source).runIncremental();
      await coordinatorWith(_parserAfterKha128(), source).recheckAllBanks();

      // A new message lands after the re-scan.
      final FakeSmsSource withNew = FakeSmsSource(<RawSmsRecord>[
        ...inbox,
        _record(
          id: 5,
          sender: 'BAJ',
          body: _aljaziraPurchaseBody.replaceAll('152.75', '19.50'),
          receivedAt: DateTime.utc(2026, 7, 28, 17),
        ),
      ]);

      final IngestionRunResult sweep = await pipelineWith(
        _parserAfterKha128(),
        withNew,
      ).runIncremental();

      expect(sweep.examined, 1);
      expect(sweep.transactionsWritten, 1);
    });

    test(
      'importState, importCursor and importFromDate are untouched',
      () async {
        final FakeSmsSource source = FakeSmsSource(_inbox());

        await watermarkDao.beginImport(
          fromDate: DateTime.utc(2026, 7),
          totalCandidates: 4,
          startCursor: 0,
        );
        await watermarkDao.recordImportProgress(cursor: 4, processedCount: 4);
        await watermarkDao.completeImport();

        final IngestWatermarkRow before = await watermarkDao.current();
        expect(before.importState, importStateCompleted);

        await coordinatorWith(_parserAfterKha128(), source).recheckAllBanks();

        final IngestWatermarkRow after = await watermarkDao.current();
        expect(
          after.importState,
          importStateCompleted,
          reason: 'item (G2) forbids re-opening the terminal import state',
        );
        expect(after.importCursor, before.importCursor);
        expect(after.importFromDate, before.importFromDate);
        expect(after.importProcessedCount, before.importProcessedCount);
        expect(after.importTotalCandidates, before.importTotalCandidates);
      },
    );

    test(
      'a completed historical import stays a no-op after a re-scan',
      () async {
        // If the re-scan had reset `importState` as a shortcut, this would
        // suddenly start re-walking the month.
        final FakeSmsSource source = FakeSmsSource(_inbox());
        final HistoricalImporter importer = HistoricalImporter(
          smsSource: source,
          pipeline: pipelineWith(_parserAfterKha128(), source),
          watermarkDao: watermarkDao,
          clock: FixedClock(_now),
          logger: logger,
        );

        await importer.runOrResume();
        await coordinatorWith(_parserAfterKha128(), source).recheckAllBanks();

        final IngestionRunResult afterRescan = await importer.runOrResume();
        expect(afterRescan.examined, 0);
      },
    );
  });

  // =======================================================================
  // 3. End-to-end — exactly what happened to the human
  // =======================================================================
  group('end-to-end: the KHA-128 recovery scenario', () {
    test('a message discarded under old sender patterns is recovered after the '
        'pack widens — and widening ALONE recovers nothing', () async {
      final FakeSmsSource source = FakeSmsSource(_inbox());

      // --- Act 1: July, before KHA-128 ------------------------------------
      // Every bank message is examined, matched against wrong sender
      // patterns, discarded, and the watermark advances past it.
      final IngestionRunResult beforeFix = await pipelineWith(
        _parserBeforeKha128(),
        source,
      ).runIncremental();

      expect(beforeFix.examined, 4);
      expect(beforeFix.discardedNonFinancialSender, 4);
      expect(await transactionCount(), 0);

      // --- Act 2: KHA-128 ships the corrected patterns --------------------
      // This is the whole point of KHA-133: the fix is forward-only. The
      // sweep now recognises BAJ perfectly well and still finds nothing,
      // because everything is behind the watermark.
      final IngestionRunResult afterFix = await pipelineWith(
        _parserAfterKha128(),
        source,
      ).runIncremental();

      expect(
        afterFix.examined,
        0,
        reason:
            'the corrected rule pack can only ever affect the future — this '
            'assertion IS the bug KHA-133 reports',
      );
      expect(await transactionCount(), 0);

      // --- Act 3: the user taps "Check my banks again" --------------------
      final RescanResult recovery = await coordinatorWith(
        _parserAfterKha128(),
        source,
      ).recheckAllBanks();

      // Both Aljazira purchases come back as transactions…
      expect(recovery.newTransactions, 2);
      expect(await transactionCount(), 2);

      // …and the Al Rajhi message, whose bank is now recognised but whose
      // `messageRules` are still empty, comes back as a review item. Both
      // outcomes are successes: the message is no longer invisible.
      expect(recovery.newReviewItems, 1);
      expect(recovery.foundNothingNew, isFalse);

      // The numbers the screen shows.
      expect(recovery.counts.examined, 3);
      expect(recovery.messagesInWindow, 4);

      // --- Act 4: pressing it again finds nothing -------------------------
      final RescanResult again = await coordinatorWith(
        _parserAfterKha128(),
        source,
      ).recheckAllBanks();
      expect(again.foundNothingNew, isTrue);
      expect(await transactionCount(), 2);
    });

    test('the recovered transaction carries the right money', () async {
      // "It recovered something" is not the same claim as "it recovered the
      // right thing". 152.75 + 64.00 from the corpus fixtures.
      final FakeSmsSource source = FakeSmsSource(_inbox());
      await pipelineWith(_parserBeforeKha128(), source).runIncremental();
      await coordinatorWith(_parserAfterKha128(), source).recheckAllBanks();

      final List<TransactionRow> rows = await transactionDao
          .select(transactionDao.transactions)
          .get();
      final List<String> amounts =
          rows.map((TransactionRow r) => r.amountAmount).toList()..sort();

      expect(amounts, <String>['152.75', '64']);
      expect(
        rows.every((TransactionRow r) => r.amountCurrency == 'SAR'),
        isTrue,
      );
    });
  });

  // =======================================================================
  // 4. Scope and privacy — ADR-006 items (C) and (D), Q2
  // =======================================================================
  group('scope: what the re-scan is and is not allowed to read', () {
    test(
      'a non-bank sender\'s body is never parsed — only the sender string is '
      'looked at',
      () async {
        final FakeSmsSource source = FakeSmsSource(_inbox());
        final _RecordingParser parser = _RecordingParser(_parserAfterKha128());

        await coordinatorWith(parser, source).recheckAllBanks();

        expect(parser.parsedSenders, isNot(contains('MOM')));
        expect(parser.parsedSenders, <String>['BAJ', 'Al Rajhi Bank', 'BAJ']);
      },
    );

    test(
      'a non-bank message is not even counted as a discard, because it never '
      'reached the pipeline',
      () async {
        final FakeSmsSource source = FakeSmsSource(_inbox());
        final RescanResult result = await coordinatorWith(
          _parserAfterKha128(),
          source,
        ).recheckAllBanks();

        // `discardedNonFinancialSender` counts messages the *pipeline*
        // discarded. Zero here is the evidence that the filter ran earlier —
        // and `messagesInWindow - examined == 1` is the same fact from the
        // other side.
        expect(result.counts.discardedNonFinancialSender, 0);
        expect(result.messagesInWindow - result.counts.examined, 1);
      },
    );

    test(
      'item (C): the window is min(importFromDate, start of current month) — '
      'a re-scan never covers less than the import it corrects',
      () async {
        // An import that began on 25 June legitimately covered late June. A
        // freshly computed "start of the current month" would now exclude it,
        // and the messages most in need of recovery would be exactly the ones
        // skipped.
        final DateTime june25 = DateTime.utc(2026, 6, 25);
        await watermarkDao.beginImport(
          fromDate: june25,
          totalCandidates: 0,
          startCursor: 0,
        );

        final FakeSmsSource source = FakeSmsSource(<RawSmsRecord>[
          _record(
            id: 1,
            sender: 'BAJ',
            body: _aljaziraPurchaseBody,
            receivedAt: DateTime.utc(2026, 6, 26, 9),
          ),
        ]);

        final RescanResult result = await coordinatorWith(
          _parserAfterKha128(),
          source,
        ).recheckAllBanks();

        expect(result.windowFromUtc, june25);
        expect(
          result.windowFromUtc.isUtc,
          isTrue,
          reason:
              'Drift hands back a local-flagged DateTime; the screen shifts '
              'this value into Riyadh wall-clock time before printing it, so a '
              'stale flag prints a date up to a day out',
        );
        expect(result.counts.transactionsWritten, 1);
      },
    );

    test(
      'item (C): with no stored import date the window is the current month, '
      'and older messages stay out of scope',
      () async {
        final FakeSmsSource source = FakeSmsSource(<RawSmsRecord>[
          _record(
            id: 1,
            sender: 'BAJ',
            body: _aljaziraPurchaseBody,
            receivedAt: DateTime.utc(2026, 5, 3, 9),
          ),
        ]);

        final RescanResult result = await coordinatorWith(
          _parserAfterKha128(),
          source,
        ).recheckAllBanks();

        expect(result.counts.examined, 0);
        expect(result.messagesInWindow, 0);
        expect(
          result.foundNothingNew,
          isTrue,
          reason:
              '"check again" is not "full history" — ADR-006 says so plainly',
        );
      },
    );

    test('recheckBank narrows to one bank', () async {
      // The per-bank form US-A6 will use. Same walk, narrower predicate.
      final FakeSmsSource source = FakeSmsSource(_inbox());
      final RescanResult result = await coordinatorWith(
        _parserAfterKha128(),
        source,
      ).recheckBank('al-rajhi');

      expect(result.counts.examined, 1);
      expect(result.counts.routedToReviewQueue, 1);
      expect(result.counts.transactionsWritten, 0);
      expect(await transactionCount(), 0);
    });

    test('an unknown bank id re-scans nothing at all', () async {
      final FakeSmsSource source = FakeSmsSource(_inbox());
      final RescanResult result = await coordinatorWith(
        _parserAfterKha128(),
        source,
      ).recheckBank('no-such-bank');

      expect(result.counts.examined, 0);
      expect(await rawMessageCount(), 0);
    });

    test('shouldContinue stops the walk cleanly and leaves no state', () async {
      final FakeSmsSource source = FakeSmsSource(_inbox());
      final IngestWatermarkRow before = await watermarkDao.current();

      final RescanResult result = await coordinatorWith(
        _parserAfterKha128(),
        source,
      ).recheckAllBanks(shouldContinue: () => false);

      expect(result.counts.examined, 0);
      final IngestWatermarkRow after = await watermarkDao.current();
      expect(after.importState, before.importState);
      expect(
        after.lastProcessedSmsProviderId,
        before.lastProcessedSmsProviderId,
      );
    });
  });

  // =======================================================================
  // 5. Item (E) — the user is told, and so is the audit trail
  // =======================================================================
  group('item (E): the re-check is reported and recorded', () {
    test('an audit entry records the re-check as a USER action', () async {
      final FakeSmsSource source = FakeSmsSource(_inbox());
      await pipelineWith(_parserBeforeKha128(), source).runIncremental();
      await coordinatorWith(_parserAfterKha128(), source).recheckAllBanks();

      final List<AuditEntryRow> entries = await auditLogDao.queryFor(
        rescanAuditEntityType,
        rescanAuditEntityId,
      );

      expect(entries, hasLength(1));
      expect(entries.single.action, rescanAuditAction);
      expect(entries.single.actor, 'user');

      final List<Object?> changes =
          jsonDecode(entries.single.fieldChangesJson) as List<Object?>;
      final Map<String, String?> byField = <String, String?>{
        for (final Object? change in changes)
          (change! as Map<String, Object?>)['field']! as String:
              (change as Map<String, Object?>)['to'] as String?,
      };

      expect(byField['transactionsAdded'], '2');
      expect(byField['reviewItemsAdded'], '1');
      expect(byField['messagesExamined'], '3');
      expect(byField['failed'], '0');
    });

    test('the audit trail stays verifiable after a re-scan', () async {
      // ADR-010's chain covers every append, including this one. A re-scan
      // writes transactions *and* its own entry, so it is a genuine chance to
      // fork the chain.
      final FakeSmsSource source = FakeSmsSource(_inbox());
      await coordinatorWith(_parserAfterKha128(), source).recheckAllBanks();
      await coordinatorWith(_parserAfterKha128(), source).recheckAllBanks();

      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('foundNothingNew is about NEW rows, not about work done', () async {
      // A run that re-examined 200 messages and suppressed all 200 found
      // nothing new. Reporting "200 messages checked" without "0 added"
      // would read as though something had happened.
      final FakeSmsSource source = FakeSmsSource(_inbox());
      final RescanCoordinator coordinator = coordinatorWith(
        _parserAfterKha128(),
        source,
      );
      await coordinator.recheckAllBanks();

      final RescanResult second = await coordinator.recheckAllBanks();
      expect(second.counts.examined, 3);
      expect(second.foundNothingNew, isTrue);
      expect(second.newTransactions, 0);
    });
  });
}

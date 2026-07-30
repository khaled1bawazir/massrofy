/// **QA probes for KHA-128 / PR #43 — independent verification of the sender gate.**
///
/// These are the qa-tester's own probes, deliberately NOT a rewrite of
/// `test/features/parsing/sender_recognition_test.dart` or
/// `test/features/ingestion/sender_only_bank_review_test.dart`. They exist to
/// check the engineer's claims by a *different path*, with *different data*,
/// because a test written by the same person who wrote the fix can share the
/// fix's blind spot.
///
/// Five things are verified here that the shipped tests do not do:
///
/// 1. **A different oracle for "which bank owns this sender".** The shipped
///    suite resolves the bank with its own helper that re-walks
///    `pack.banks` / `pack.senderPatterns`. That helper is a *reimplementation*
///    of `RulePackMessageParser._resolveBank`, so if the two ever disagree the
///    test is measuring the copy. These probes read the `bankId` back out of
///    the real [ParseOutcome] the production parser returns, which is the only
///    value the pipeline actually stores.
/// 2. **The `\s` claim is asserted, not asserted-in-a-comment.** The pack's
///    `_readme` justifies `^D360\s*Bank$` over `^D360 Bank$` by claiming `\s`
///    "also covers the non-breaking space an Arabic-locale device can
///    deliver". Nothing in the shipped tests exercises a U+00A0. That is a
///    load-bearing claim about the regex flavour, so it gets a test.
/// 3. **Sender-spoofing probes.** The SMS `address` field is attacker-influenced
///    in the sense that anyone can send SMS with a chosen alphanumeric sender
///    id. `^…$` anchoring is the entire defence, so multi-line, NUL,
///    zero-width, bidi and regex-metacharacter senders are probed against it.
/// 4. **Duplicate re-ingestion of a *sender-only* bank's message.** The
///    shipped pipeline test proves one message lands in review. It does not
///    prove a second delivery of the same message does not create a second
///    review item — which is the failure the user would actually see (a review
///    queue that grows every sweep).
/// 5. **Cross-bank sender collisions.** With seven banks and first-match-wins
///    resolution, two banks claiming one string is a reordering bug that no
///    single-bank test can see.
///
/// ## NFR-M3
///
/// Every message body in this file is **fabricated by QA** for this file, and
/// is deliberately different text from the engineer's fixtures. No real bank
/// SMS is reproduced, quoted or paraphrased. Sender ids are real public brand
/// strings and are the thing under test.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/logging/diagnostic_ring_buffer.dart';
import 'package:massrofy/core/logging/safe_logger.dart';
import 'package:massrofy/core/text/sms_sanitizer.dart';
import 'package:massrofy/core/text/sms_text_normalizer.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/ingest_watermark_dao.dart';
import 'package:massrofy/data/dao/raw_message_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ingestion/ingestion_pipeline.dart';
import 'package:massrofy/features/ingestion/sms_source.dart';
import 'package:massrofy/features/ledger/bank_directory.dart';
import 'package:massrofy/features/parsing/parse_outcome.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_message_parser.dart';

import '../features/ingestion/support/load_bundled_pack.dart';
import '../support/fake_sms_source.dart';
import '../support/plain_test_database.dart';
import '../support/watermark_seed.dart';

final List<int> _qaKey = List<int>.generate(32, (int i) => 200 - i);

/// Invisible / control characters used in the spoofing probes, named as
/// escapes so the source stays greppable and reviewable — a literal
/// zero-width space in a test file is unreadable and easy to lose in a rebase.
const String _nbsp = '\u00A0'; // non-breaking space
const String _zwsp = '\u200B'; // zero-width space
const String _rlo = '\u202E'; // right-to-left override
const String _nul = '\u0000'; // NUL

/// The seven strings the human read off their own phone (KHA-128 comment,
/// 2026-07-30), mapped to the `bankId` each MUST resolve to.
///
/// Written out literally here rather than derived from the pack: an
/// expectation derived from the data under test passes whatever the data says.
const Map<String, String> _confirmedSenders = <String, String>{
  'Jazira Bank': 'bank-aljazira',
  'nera': 'nera',
  'D360 Bank': 'd360',
  'AlRajhi Bank': 'al-rajhi',
  'STC Bank': 'stc-bank',
  'SAIB': 'saib',
  'SAB': 'sab',
};

/// The patterns that existed BEFORE KHA-128. They were guesses, but the fix is
/// supposed to be purely additive — a silent narrowing here would lose
/// messages from whichever variant a carrier actually delivers.
const Map<String, String> _preExistingSenders = <String, String>{
  'BAJ': 'bank-aljazira',
  'Aljazira': 'bank-aljazira',
  'AlJazira': 'bank-aljazira',
  'BankAlJazira': 'bank-aljazira',
  'D360': 'd360',
  'D360Bank': 'd360',
  'D-360': 'd360',
};

/// QA's own synthetic bodies for the five sender-only banks — different text
/// from the engineer's fixtures on purpose, so the pipeline result is not an
/// artefact of one particular string. None of these matches any template in
/// the pack.
const Map<String, String> _qaSyntheticBodies = <String, String>{
  'nera': 'nera notice: purchase approved 137.55 SAR, ref QA-N-4410.',
  'AlRajhi Bank':
      'AlRajhi Bank notice: 1,204.35 SAR withdrawn from acct 0011 on 30/07/26.',
  'STC Bank': 'STC Bank notice: transfer out 9.05 SAR to QA TEST PAYEE.',
  'SAIB': 'SAIB notice: SAR 88.00 charged, terminal QA-TERM-7, ref SB-2299.',
  'SAB': 'SAB notice: debit SAR 3,000.00 to QA SAMPLE MERCHANT, ref AB-0001.',
};

void main() {
  late RulePack pack;
  late RulePackMessageParser parser;

  setUpAll(() {
    pack = loadBundledRulePack();
    parser = RulePackMessageParser(packs: <RulePack>[pack]);
  });

  // ---------------------------------------------------------------------------
  // Oracle: run the REAL parser and read the bankId out of its outcome.
  // ---------------------------------------------------------------------------

  /// Parses a body that contains no token any rule keys on, so the only thing
  /// under test is sender resolution, and returns the `bankId` the production
  /// parser attributed the message to — or `null` if it decided the sender is
  /// not financial.
  ///
  /// This deliberately does NOT re-walk `pack.banks`. It asks the code that
  /// ships.
  String? bankIdFromRealParser(String sender) {
    const String neutralBody = 'qa neutral token';
    final SanitizedSmsText sanitized = SmsSanitizer.sanitize(
      neutralBody,
      extraRedactPatterns: parser.redactionPatternsForSender(sender),
    );
    final ParseOutcome outcome = parser.parse(
      sanitized: sanitized,
      normalizedBody: SmsTextNormalizer.normalize(sanitized.value),
      sender: sender,
    );
    return switch (outcome) {
      NotFinancialSender() => null,
      UnparsedMessage(:final RuleReference? rule) => rule?.bankId,
      IgnoredMessage(:final RuleReference rule) => rule.bankId,
      ParsedMessage(:final RuleReference rule) => rule.bankId,
    };
  }

  group('QA-P1 — the seven confirmed senders, via the production parser', () {
    _confirmedSenders.forEach((String sender, String expectedBankId) {
      test('"$sender" -> $expectedBankId (exact string off the device)', () {
        expect(
          bankIdFromRealParser(sender),
          expectedBankId,
          reason:
              'this is the literal sender id the human confirmed. A null here '
              'is the KHA-128 defect: every message from $expectedBankId is '
              'discarded with no trace at all (NFR-P4), which is what produced '
              'the reported 0.00 SAR with an empty review queue.',
        );
      });

      // Casing is a property of the carrier's delivery, not of the bank, and
      // the loader compiles patterns `caseSensitive: false`. Probed with a
      // genuinely mixed case as well as all-upper/all-lower, because an
      // accidentally case-sensitive character class can survive one of those.
      test('"$sender" survives arbitrary casing', () {
        final String alternating = String.fromCharCodes(<int>[
          for (int i = 0; i < sender.length; i++)
            i.isEven
                ? sender.toUpperCase().codeUnitAt(i)
                : sender.toLowerCase().codeUnitAt(i),
        ]);
        expect(bankIdFromRealParser(alternating), expectedBankId);
        expect(bankIdFromRealParser(sender.toUpperCase()), expectedBankId);
        expect(bankIdFromRealParser(sender.toLowerCase()), expectedBankId);
      });

      // The pipeline hands the parser `record.address` verbatim; a content
      // provider can return it padded. `_resolveBank` trims, and that is
      // asserted here rather than assumed.
      test('"$sender" survives surrounding whitespace from the provider', () {
        expect(bankIdFromRealParser('  $sender\t'), expectedBankId);
        expect(bankIdFromRealParser('$sender\n'), expectedBankId);
      });
    });
  });

  group('QA-P2 — the fix is ADDITIVE: pre-KHA-128 patterns still match', () {
    _preExistingSenders.forEach((String sender, String expectedBankId) {
      test('"$sender" still -> $expectedBankId', () {
        expect(
          bankIdFromRealParser(sender),
          expectedBankId,
          reason:
              'KHA-128 widens the gate. If a guessed-but-possibly-real '
              'alternative was dropped while widening, this fix trades one '
              'silent message loss for another.',
        );
      });
    });
  });

  group('QA-P3 — the `\\s` claim in the pack _readme is really true', () {
    // The pack justifies `^D360\s*Bank$` over `^D360 Bank$` by claiming `\s`
    // covers "the non-breaking space an Arabic-locale device can deliver".
    // Nothing in the shipped tests exercises U+00A0, so QA asserts it: if Dart
    // `\s` did not include NBSP, the comment would be wrong AND the extra
    // widening would buy nothing.
    test('a non-breaking space inside a brand name still matches', () {
      expect(bankIdFromRealParser('D360${_nbsp}Bank'), 'd360');
      expect(bankIdFromRealParser('Jazira${_nbsp}Bank'), 'bank-aljazira');
      expect(bankIdFromRealParser('STC${_nbsp}Bank'), 'stc-bank');
      expect(bankIdFromRealParser('Al${_nbsp}Rajhi${_nbsp}Bank'), 'al-rajhi');
    });

    test('the no-space and double-space spellings match too', () {
      expect(bankIdFromRealParser('D360Bank'), 'd360');
      expect(bankIdFromRealParser('JaziraBank'), 'bank-aljazira');
      expect(bankIdFromRealParser('STCBank'), 'stc-bank');
      expect(bankIdFromRealParser('AlRajhiBank'), 'al-rajhi');
      expect(bankIdFromRealParser('D360  Bank'), 'd360');
      expect(bankIdFromRealParser('Jazira   Bank'), 'bank-aljazira');
    });
  });

  group('QA-P4 — widening did not make the gate promiscuous', () {
    // A false positive here is not cosmetic: a matched sender means the
    // message body is SANITISED AND PERSISTED to the review queue. So every
    // near-miss that wrongly matches is a privacy defect (NFR-P4), not just a
    // wrong label. `^…$` anchoring is the whole defence.
    for (final String lookalike in <String>[
      // Telecom STC, which sends OTPs and marketing and is not the bank.
      'STC',
      'stc',
      'STC KSA',
      'STCPay',
      'STC Pay',
      'STC-Bank-Offers',
      // A bank's own rewards/marketing short code is a different sender id.
      'D360Rewards',
      'D360 Rewards',
      'JaziraBankOffers',
      'Jazira Bank Offers',
      // SABB (Saudi British Bank) is a DIFFERENT real bank from SAB. A match
      // here would attribute one bank's messages to another.
      'SABB',
      'SABB Bank',
      // The three single-token confirmed senders have no `…\s*Bank`
      // alternative, unlike the four multi-token ones. That is correct as
      // shipped — widening speculatively is the guessing KHA-128 exists to
      // stop — but it is asserted here so the residual risk recorded as
      // O-QA-12 in `docs/defects.md` is backed by a measurement rather than
      // by a reading of the pack.
      'SAB Bank',
      'SAIB Bank',
      'nera Bank',
      'SA',
      'AB',
      'NOTSAB',
      'SAB2',
      // Sub/superstrings of the other new banks.
      'nerabank',
      'nera bank',
      'anera',
      'SAIBB',
      'MYSAIB',
      'AlRajhi',
      'Rajhi Bank',
      'AlRajhi Capital',
      // Ordinary non-bank senders, including the empty sender.
      'ARAMEX',
      'MYFRIEND',
      '+966500000000',
      '4444',
      '',
    ]) {
      test('"$lookalike" is attributed to no bank', () {
        expect(
          bankIdFromRealParser(lookalike),
          isNull,
          reason:
              'a wrong sender match persists a non-financial message body to '
              'the review queue — an NFR-P4 breach, not a mislabel.',
        );
      });
    }
  });

  group('QA-P5 — sender spoofing against the `^…\$` anchors', () {
    // Anyone can send an SMS with a chosen alphanumeric sender id. The anchors
    // are the only thing standing between a crafted sender and the app
    // treating the message as a bank's. These probe the anchor semantics
    // themselves rather than the brand strings.
    final Map<String, String> hostileSenders = <String, String>{
      // Dart `$` without `multiLine` should match end-of-input only, so a real
      // bank id followed by a newline and more text must NOT match. If Dart
      // used Perl's "before a final newline" semantics this would match.
      r'bank id then newline then payload': 'SAB\nDROP TABLE transactions',
      r'bank id then newline then another bank id': 'SAB\nnera',
      r'payload then newline then bank id': 'nera\nSAB',
      r'CRLF after bank id': 'SAIB\r\nx',
      // Regex metacharacters supplied AS the sender.
      'the pattern itself as a sender': r'^SAB$',
      'match-anything': '.*',
      'single-char wildcard': 'SA.',
      'wildcard inside': 'S.B',
      'alternation': 'SAB|nera',
      'capture group': '(SAB)',
      'greedy suffix': 'SAB.*',
      // SQL / command / JNDI injection shapes in the sender field. These must
      // be rejected at the gate; the DAO's parameterised statements are the
      // second line of defence, not the first.
      'sql injection': "SAB'; DROP TABLE raw_message;--",
      'sql tautology': 'SAB" OR "1"="1',
      'shell injection': 'SAB; rm -rf /',
      'jndi lookup': r'SAB${jndi:ldap://x/y}',
      // Zero-width and bidi controls, which render invisibly next to a real
      // brand name — a human proof-reading the sender id cannot see these.
      'zero-width space inside': 'SA${_zwsp}B',
      'zero-width space trailing': 'SAB$_zwsp',
      'zero-width space leading': '${_zwsp}SAB',
      'bidi override appended': 'SAB$_rlo',
      'zero-width inside D360': 'D360${_zwsp}Bank',
      // Arabic-Indic digits standing in for the Latin ones in D360. A
      // `unicode: true` pattern must not treat them as equivalent.
      'arabic-indic digits': 'D٣٦٠ Bank',
      // NUL bytes, which have crashed regex engines in other stacks.
      'trailing NUL': 'SAB$_nul',
      'leading NUL': '$_nul SAB',
      'NUL inside': 'SA${_nul}B',
      // Very long sender, in case a pattern were unanchored at one end.
      'bank id buried in a long sender':
          'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXSABXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
    };

    hostileSenders.forEach((String label, String hostile) {
      test('hostile sender ($label) matches no bank, and does not throw', () {
        expect(
          bankIdFromRealParser(hostile),
          isNull,
          reason:
              'the `^…\$` anchors are the entire sender gate. If a crafted '
              'sender can impersonate a bank, an attacker chooses what this '
              'app persists and shows the user as a bank message.',
        );
      });
    });
  });

  // ---------------------------------------------------------------------------
  // End-to-end: the "matched sender, no template" path through the real
  // pipeline and a real database.
  // ---------------------------------------------------------------------------

  group('QA-P6 — a sender-only bank end to end (AC-A6.5)', () {
    late AppDatabase db;
    late RawMessageDao rawMessageDao;
    late TransactionDao transactionDao;
    late IngestWatermarkDao watermarkDao;

    setUp(() async {
      db = openPlainTestDatabase();
      rawMessageDao = RawMessageDao(db);
      transactionDao = TransactionDao(
        db,
        AuditLogDao(db, auditChainKey: _qaKey),
      );
      watermarkDao = IngestWatermarkDao(db);
      // KHA-157: the subject is ADR-007's sender gate, not where the sweep
      // starts. Seed at the beginning so each probe's fixture inbox is read.
      await seedWatermarkAtBeginning(watermarkDao);
    });

    tearDown(() async => db.close());

    IngestionPipeline pipelineOver(List<RawSmsRecord> inbox) =>
        IngestionPipeline(
          database: db,
          smsSource: FakeSmsSource(inbox),
          parser: parser,
          rawMessageDao: rawMessageDao,
          transactionDao: transactionDao,
          watermarkDao: watermarkDao,
          logger: SafeLogger(DiagnosticRingBuffer()),
          contentHmacKey: _qaKey,
        );

    RawSmsRecord rec(int id, String sender, String body) => RawSmsRecord(
      providerId: id,
      address: sender,
      body: body,
      receivedAt: DateTime.utc(2026, 7, 30, 11).add(Duration(minutes: id)),
    );

    // One test per bank rather than one loop assertion, so a single bank
    // regressing names itself in the CI output.
    _qaSyntheticBodies.forEach((String sender, String body) {
      test('$sender: QA\'s own synthetic message reaches Needs Review with '
          'its text intact', () async {
        final IngestionRunResult result = await pipelineOver(<RawSmsRecord>[
          rec(7, sender, body),
        ]).runIncremental();

        expect(result.examined, 1);
        expect(result.routedToReviewQueue, 1);
        expect(
          result.discardedNonFinancialSender,
          0,
          reason: 'the KHA-128 regression in one number',
        );
        expect(
          result.failedWithError,
          0,
          reason:
              'an empty `messageRules` must fall through the rule loop, not '
              'throw. A 1 here means the message is retried forever behind '
              'NFR-R5\'s per-message catch.',
        );
        expect(result.transactionsWritten, 0);
        expect(result.isFullyAccountedFor, isTrue, reason: '$result');

        final List<RawMessageRow> queue = await rawMessageDao
            .watchReviewQueue()
            .first;
        expect(queue, hasLength(1));
        expect(queue.single.sender, sender);
        expect(queue.single.classification, 'financial_unparsed');
        expect(queue.single.unparsedReason, 'no_rule_matched');
        expect(
          queue.single.unparsedRuleId,
          isNull,
          reason:
              'no rule matched, so no rule id — an empty string here would '
              'read as a real rule in the parser-health panel',
        );

        // The business oracle for "text intact": the amount digits the user
        // needs in order to complete this row by hand must still be readable
        // in the stored text. A review item whose amount was redacted away is
        // not completable (AC-A4.2), which would make AC-A6.5's whole
        // argument — "a sender-only bank is immediately useful" — false.
        final String? stored = queue.single.sanitizedBody;
        expect(stored, isNotNull);
        final String expectedAmount = RegExp(
          r'[\d,]+\.\d{2}',
        ).firstMatch(body)!.group(0)!;
        expect(
          stored,
          contains(expectedAmount),
          reason:
              'the user completes this row by reading the original amount '
              '($expectedAmount). If sanitisation removed it, the review '
              'queue is not a usable fallback for a template-less bank.',
        );

        // The watermark must move past a message that produced no
        // transaction, or every subsequent sweep re-reads it forever.
        expect((await watermarkDao.current()).lastProcessedSmsProviderId, 7);
        expect(await transactionDao.all(), isEmpty);
      });
    });

    test(
      'all five sender-only banks in one sweep produce exactly five review '
      'items, and a non-bank sender in the same sweep leaves no row',
      () async {
        final List<RawSmsRecord> inbox = <RawSmsRecord>[];
        int id = 0;
        _qaSyntheticBodies.forEach((String sender, String body) {
          inbox.add(rec(++id, sender, body));
        });
        inbox.add(rec(++id, 'MYFRIEND', 'coffee at 5? my treat, 60 SAR max'));

        final IngestionRunResult result = await pipelineOver(
          inbox,
        ).runIncremental();

        expect(result.examined, 6);
        expect(result.routedToReviewQueue, 5);
        expect(
          result.discardedNonFinancialSender,
          1,
          reason:
              'exactly the friend. A 0 would mean the counter cannot move and '
              'the assertions above prove nothing; a 6 is the shipped defect.',
        );
        expect(result.failedWithError, 0);
        expect(result.isFullyAccountedFor, isTrue, reason: '$result');

        final Set<String> stored = (await rawMessageDao.all())
            .map((RawMessageRow r) => r.sender)
            .toSet();
        expect(stored, containsAll(_qaSyntheticBodies.keys));
        expect(
          stored,
          isNot(contains('MYFRIEND')),
          reason:
              'NFR-P4: a personal message leaves no row at all, not even a '
              'timestamp — unchanged by this fix. The friend\'s body even '
              'contains "SAR", so this also re-proves AC-A2.3: the sender gate, '
              'not the body, decides.',
        );
      },
    );
  });

  group('QA-P7 — re-ingesting the same sender-only message does not grow the '
      'review queue', () {
    late AppDatabase db;
    late RawMessageDao rawMessageDao;
    late TransactionDao transactionDao;
    late IngestWatermarkDao watermarkDao;

    setUp(() async {
      db = openPlainTestDatabase();
      rawMessageDao = RawMessageDao(db);
      transactionDao = TransactionDao(
        db,
        AuditLogDao(db, auditChainKey: _qaKey),
      );
      watermarkDao = IngestWatermarkDao(db);
      // KHA-157: the subject is ADR-007's sender gate, not where the sweep
      // starts. Seed at the beginning so each probe's fixture inbox is read.
      await seedWatermarkAtBeginning(watermarkDao);
    });

    tearDown(() async => db.close());

    IngestionPipeline pipelineOver(List<RawSmsRecord> inbox) =>
        IngestionPipeline(
          database: db,
          smsSource: FakeSmsSource(inbox),
          parser: parser,
          rawMessageDao: rawMessageDao,
          transactionDao: transactionDao,
          watermarkDao: watermarkDao,
          logger: SafeLogger(DiagnosticRingBuffer()),
          contentHmacKey: _qaKey,
        );

    final RawSmsRecord original = RawSmsRecord(
      providerId: 12,
      address: 'SAIB',
      body: _qaSyntheticBodies['SAIB']!,
      receivedAt: DateTime.utc(2026, 7, 30, 12, 34),
    );

    test('the same provider row processed twice (watermark rewind / restored '
        'SMS db) yields ONE review item', () async {
      final IngestionPipeline pipeline = pipelineOver(<RawSmsRecord>[original]);
      await pipeline.runIncremental();

      final IngestionRunResult second = await pipeline.processAll(
        <RawSmsRecord>[original],
        advanceWatermark: false,
      );

      expect(
        second.suppressedAsExactDuplicate,
        1,
        reason:
            'ADR-017 D1 keys on the raw-message row, so it must cover the '
            'unparsed path exactly as it covers the parsed one. If it did '
            'not, a template-less bank would accumulate a duplicate review '
            'item on every rescan — the visible symptom the user would '
            'report next.',
      );
      expect(second.routedToReviewQueue, 0);
      expect(await rawMessageDao.watchReviewQueue().first, hasLength(1));
    });

    test('a carrier redelivery — identical content, NEW provider id — also '
        'yields ONE review item', () async {
      final RawSmsRecord redelivered = RawSmsRecord(
        providerId: 99,
        address: original.address,
        body: original.body,
        receivedAt: original.receivedAt,
      );

      final IngestionRunResult result = await pipelineOver(<RawSmsRecord>[
        original,
        redelivered,
      ]).runIncremental();

      expect(result.examined, 2);
      expect(result.routedToReviewQueue, 1);
      expect(
        result.suppressedAsExactDuplicate,
        1,
        reason:
            'the content HMAC, not the provider id, is what catches this — '
            'and it is computed from the sanitised+normalised body, which the '
            'unparsed path also produces.',
      );
      expect(result.isFullyAccountedFor, isTrue, reason: '$result');
      expect(await rawMessageDao.watchReviewQueue().first, hasLength(1));
    });
  });

  group('QA-P8 — pack-level invariants a data-only change can break', () {
    test('no two banks claim the same sender string, for any of the seven '
        'confirmed ids or the pre-existing alternatives', () {
      // First-match-wins means an overlap would silently attribute a bank's
      // messages to whichever entry happens to be earlier in the file — a
      // reordering bug waiting to happen, and invisible in any single-bank
      // test.
      final Map<String, String> all = <String, String>{
        ..._confirmedSenders,
        ..._preExistingSenders,
      };
      all.forEach((String sender, String expected) {
        final List<String> claimants = <String>[
          for (final BankRule bank in pack.banks)
            if (bank.senderPatterns.any(
              (RegExp p) => p.hasMatch(sender.trim()),
            ))
              bank.bankId,
        ];
        expect(claimants, <String>[
          expected,
        ], reason: '"$sender" must be claimed by exactly one bank');
      });
    });

    test('every bank id is unique and every bank declares at least one sender '
        'pattern', () {
      final List<String> ids = pack.banks
          .map((BankRule b) => b.bankId)
          .toList();
      expect(ids.toSet(), hasLength(ids.length), reason: 'duplicate bankId');
      for (final BankRule bank in pack.banks) {
        expect(
          bank.senderPatterns,
          isNotEmpty,
          reason:
              '${bank.bankId} with no sender pattern is unreachable data — '
              'it can never match anything, so its rules can never fire',
        );
      }
    });
  });

  group('QA-P9 — adding banks did not collide the BankDirectory name index', () {
    // Discovered by following the data, not the diff: `bankDirectoryProvider`
    // turns every bank in the pack into a `BankProfile`, and
    // `BankDirectory._byNormalizedName` is built as a **map literal over all
    // profiles' canonicalKey + both display names + every alias**. A map
    // literal is last-write-wins, so if two banks normalise to the same key
    // one silently shadows the other and `resolveByName` (AC-B12.3) returns
    // the wrong bank — with no error and no existing test.
    //
    // This PR went from 2 banks to 7, each with display names and aliases, so
    // it is the first change that could plausibly trip it. It does not. The
    // probe is kept because KHA-136 adds more banks to the same file, and this
    // is the invariant nobody would think to re-check.
    late BankDirectory directory;

    setUp(() {
      directory = BankDirectory(<BankProfile>[
        for (final BankRule bank in pack.banks)
          BankProfile(
            canonicalKey: bank.bankId,
            displayNameAr: bank.displayNameAr,
            displayNameEn: bank.displayNameEn,
            aliases: bank.aliases,
          ),
      ]);
    });

    test('no name, display name or alias of one bank normalises onto '
        'another bank', () {
      final Map<String, Set<String>> ownersOfKey = <String, Set<String>>{};
      for (final BankRule bank in pack.banks) {
        for (final String name in <String>[
          bank.bankId,
          bank.displayNameAr,
          bank.displayNameEn,
          ...bank.aliases,
        ]) {
          final String key = normalizeBankName(name);
          if (key.isEmpty) {
            continue;
          }
          (ownersOfKey[key] ??= <String>{}).add(bank.bankId);
        }
      }

      final Map<String, Set<String>> collisions = <String, Set<String>>{
        for (final MapEntry<String, Set<String>> e in ownersOfKey.entries)
          if (e.value.length > 1) e.key: e.value,
      };
      expect(
        collisions,
        isEmpty,
        reason:
            'each of these normalised keys is claimed by more than one bank. '
            '`BankDirectory` resolves it to whichever bank is LAST in the '
            'pack, silently — so one bank\'s name would resolve to the other '
            'bank\'s ledger tree (AC-B12.3).',
      );
    });

    test('every one of the seven banks is resolvable by its own English '
        'display name and its own bankId', () {
      // The positive half: the index must not merely be collision-free, it
      // must actually contain each bank. An empty index is trivially
      // collision-free.
      for (final BankRule bank in pack.banks) {
        expect(
          directory.resolveByName(bank.displayNameEn),
          bank.bankId,
          reason: '${bank.displayNameEn} must resolve to ${bank.bankId}',
        );
        expect(directory.resolveByName(bank.bankId), bank.bankId);
        expect(directory.byCanonicalKey(bank.bankId), isNotNull);
      }
    });
  });
}

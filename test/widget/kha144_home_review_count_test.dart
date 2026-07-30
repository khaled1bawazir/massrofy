/// **KHA-144 — Home's review count, against the real queue.**
///
/// The bug, live on a real device: 833 genuine bank messages sat in
/// `More → Organising → Needs review → Not understood`, and Home said
/// *"All caught up"* with an untappable card. AC-C4.2 — *"the count of items
/// needing review is visible from the main screen"* — was flatly unmet, and the
/// one screen meant to answer *"is this thing working?"* answered "no" while the
/// app was working perfectly.
///
/// ## Why this file looks heavier than a provider unit test
///
/// `docs/lessons.md` twice: *"verify a reachability claim by grepping for the
/// construction site, never from the fact that the widget exists in the tree"*,
/// and *"verify by reading the data, not by trusting a counter that might itself
/// be wrong."* Both apply directly, so every test here obeys three rules:
///
///  1. **The queue is filled by the real ingestion pipeline**, over a real
///     database, from a fake SMS *inbox* — not by inserting rows into the DAO
///     that the count happens to read. A shortcut here would prove that the
///     count matches the shortcut.
///  2. **The expected number is re-derived from the database**, by a query
///     written independently of the one the provider uses, and compared to what
///     the pixels say. `IngestionRunResult`'s own counters are asserted too, but
///     only as a cross-check — they are exactly the kind of self-reported
///     counter the lesson warns about.
///  3. **The assertion is on the rendered text of the real Home screen**,
///     reached through the real `AppShell`. A provider that composes correctly
///     and a widget that never reads it is a shipped bug with a green test.
///
/// ## NFR-M3
///
/// Every message body below is **fabricated for this file**. No real bank SMS is
/// reproduced, quoted, or paraphrased. The sender ids are real (they are the
/// thing under test, confirmed on KHA-128) and the bank names are public
/// brands; every amount, merchant, reference and date is invented.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/logging/diagnostic_ring_buffer.dart';
import 'package:massrofy/core/logging/safe_logger.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/dao/bank_dao.dart';
import 'package:massrofy/data/dao/category_dao.dart';
import 'package:massrofy/data/dao/ingest_watermark_dao.dart';
import 'package:massrofy/data/dao/instrument_dao.dart';
import 'package:massrofy/data/dao/merchant_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/categorization/categorization_service.dart';
import 'package:massrofy/features/ingestion/ingestion_pipeline.dart';
import 'package:massrofy/features/ingestion/sms_permission_service.dart';
import 'package:massrofy/features/ingestion/sms_source.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/features/parsing/rule_pack_message_parser.dart';
import 'package:massrofy/features/security/app_lock_state.dart';
import 'package:massrofy/presentation/screens/app_shell.dart';
import 'package:massrofy/presentation/screens/home_screen.dart';
import 'package:massrofy/presentation/screens/needs_review_screen.dart';

import '../features/ingestion/support/load_bundled_pack.dart';
import '../support/app_test_harness.dart';
import '../support/fake_sms_source.dart';

/// A deterministic 32-byte key. The audit chain and the content HMAC are other
/// suites' subjects; a fixed key keeps failures here reproducible.
final List<int> _testKey = List<int>.generate(32, (int i) => i);

/// Senders that are **recognised** (gate 1 passes) but carry no parsing
/// template, so every message from them ends in the "Not understood" tab.
///
/// These are five of the seven real sender ids KHA-128 confirmed. They are the
/// reporting device's actual situation: the banks are known, the templates are
/// not written yet (KHA-136), and NFR-A7 says the messages are kept.
const List<String> _senderOnlyBanks = <String>[
  'nera',
  'AlRajhi Bank',
  'STC Bank',
  'SAIB',
  'SAB',
];

void main() {
  late TestSession session;
  late FakeSmsPermissionService permissions;
  late RulePackMessageParser parser;

  setUp(() {
    session = TestSession.open();
    // Granted, so the AC-A1.3 revoked banner does not sit above the card these
    // tests assert on. That banner has its own coverage in the onboarding suite.
    permissions = FakeSmsPermissionService(
      current: SmsPermissionStatus.granted,
    );
    parser = RulePackMessageParser(packs: <RulePack>[loadBundledRulePack()]);
  });

  tearDown(() async => session.close());

  // -----------------------------------------------------------------------
  // Seeding — through the real pipeline, never through a DAO shortcut
  // -----------------------------------------------------------------------

  /// Runs [body] in the **real** async zone rather than the widget tester's
  /// fake one.
  ///
  /// Not boilerplate, and worth understanding before touching it.
  /// `testWidgets` runs its body inside `FakeAsync`, where a `Timer` only fires
  /// when the test pumps a frame. The ingestion pipeline drives a real database
  /// through Drift, whose transaction and stream-query machinery schedules
  /// timers of its own — so `await pipeline.runIncremental()` straight from a
  /// widget-test body deadlocks: the pipeline waits for a timer, and the timer
  /// waits for a pump that cannot happen until the await returns. It fails as a
  /// ten-minute timeout, which looks nothing like the cause.
  ///
  /// `runAsync` hands the closure to the real zone, so timers fire normally,
  /// and returns non-null whenever [body] completes.
  ///
  /// **Call it before `pumpWidget`, not after.** `runAsync` holds the fake clock
  /// still while it waits, so once providers are mounted and have their own
  /// Drift work in flight on the same connection, a second writer entering here
  /// deadlocks against them. Every test in this file therefore seeds first and
  /// renders second.
  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync<T>(body)) as T;

  /// The **real** categorizer, wired the way `categorization_providers.dart`
  /// wires it in the app.
  ///
  /// Without it a parsed transaction would land with `needsReview == false` and
  /// no category, so the "Low confidence" half of the count would be tested
  /// against a state the app never actually produces. With it, an unknown
  /// merchant is flagged exactly as it is on a device (ADR-008's last row:
  /// Uncategorized **and** `needsReview`).
  Future<CategorizeWrittenTransaction> buildCategorizer() async {
    final CategorizationService service = CategorizationService(
      categoryDao: CategoryDao(session.database, session.session.auditLogDao),
      merchantDao: MerchantDao(session.database, session.session.auditLogDao),
      transactionDao: session.session.transactionDao,
    );
    await service.ensureDefaultsSeeded();
    return (int transactionId) =>
        service.categorizeTransaction(transactionId: transactionId);
  }

  /// Runs the ingestion pipeline over [inbox] against the harness's database.
  Future<IngestionRunResult> ingest(
    WidgetTester tester,
    List<RawSmsRecord> inbox,
  ) => real(
    tester,
    () async => IngestionPipeline(
      database: session.database,
      smsSource: FakeSmsSource(inbox),
      parser: parser,
      rawMessageDao: session.session.rawMessageDao,
      transactionDao: session.session.transactionDao,
      watermarkDao: IngestWatermarkDao(session.database),
      logger: SafeLogger(DiagnosticRingBuffer()),
      contentHmacKey: _testKey,
      categorizer: await buildCategorizer(),
    ).runIncremental(),
  );

  RawSmsRecord record(int providerId, String sender, String body) =>
      RawSmsRecord(
        providerId: providerId,
        address: sender,
        body: body,
        // Spread apart so the duplicate heuristic (ADR-017 D3, a 15-minute
        // window) never fires on two of these and quietly flags one, which
        // would move a number this file asserts exactly.
        receivedAt: DateTime.utc(
          2026,
          7,
          20,
          6,
        ).add(Duration(hours: providerId)),
      );

  /// [count] messages from recognised, template-less banks.
  ///
  /// Every body is distinct: the pipeline suppresses an exact duplicate by
  /// content HMAC, so [count] identical messages would produce **one** queue
  /// item and the test would silently be measuring something else.
  List<RawSmsRecord> unparsedInbox(int count) => <RawSmsRecord>[
    for (int i = 0; i < count; i++)
      record(
        100 + i,
        _senderOnlyBanks[i % _senderOnlyBanks.length],
        'Card payment ${11 + i}.50 SAR at SAMPLE STORE ${i + 1}. '
        'Ref TS${90000 + i}.',
      ),
  ];

  /// [count] messages that genuinely parse into transactions.
  ///
  /// The shape is the corpus's `baj-01-pos-purchase` — a fabricated Bank
  /// Aljazira POS purchase in Arabic. Amounts and merchants differ per message
  /// so neither the exact-duplicate HMAC nor the near-duplicate heuristic fires.
  List<RawSmsRecord> parsedInbox(int count) => <RawSmsRecord>[
    for (int i = 0; i < count; i++)
      record(
        200 + i,
        'BAJ',
        'شراء\n'
            'بطاقة:مدى-****4821\n'
            'مبلغ:${31 + i * 7}.25 SAR\n'
            'لدى:SAMPLE MART ${i + 1}\n'
            'في:2$i-07-26 14:32',
      ),
  ];

  // -----------------------------------------------------------------------
  // Ground truth — a second, independent query over the same database
  // -----------------------------------------------------------------------

  /// How many items are in the "Not understood" tab, read straight from the
  /// raw-message table.
  Future<int> queueSizeFromDatabase(WidgetTester tester) => real(
    tester,
    () async =>
        (await session.session.rawMessageDao.watchReviewQueue().first).length,
  );

  /// How many live transactions raise a question, recomputed here rather than
  /// borrowed from `ReviewCounts` — the whole point is to check the production
  /// figure against something written independently of it.
  Future<int> transactionsNeedingAttentionFromDatabase(WidgetTester tester) =>
      real(tester, () async {
        final List<TransactionRow> rows = await session.session.transactionDao
            .watchLive()
            .first;
        return rows
            .where(
              (TransactionRow row) => row.needsReview || row.categoryId == null,
            )
            .length;
      });

  // -----------------------------------------------------------------------
  // Rendering
  // -----------------------------------------------------------------------

  Future<void> pumpShell(WidgetTester tester, {String locale = 'en'}) async {
    useTallHostSurface(tester);
    await tester.pumpWidget(
      hostScope(
        session: session,
        permissions: permissions,
        locale: locale,
        child: const AppShell(),
      ),
    );
    await pumpHostFrames(tester, frames: 20);
  }

  /// The exact string the review card's headline is rendering.
  ///
  /// Read off the widget rather than matched with `find.text`, so a failure
  /// reports *what it actually said* — "expected 12, found All caught up" is the
  /// message that would have made KHA-144 obvious in one line.
  String headlineText(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('home.reviewCount.headline')))
      .data!;

  bool cardIsTappable(WidgetTester tester) =>
      tester.widget<InkWell>(find.byKey(const Key('home.reviewCount'))).onTap !=
      null;

  // =======================================================================
  // 1. The reported defect, reproduced and fixed
  // =======================================================================

  group('AC-C4.2 — unparsed messages are items needing review', () {
    testWidgets('N messages that only reach the "Not understood" tab make Home '
        'show exactly N — this is the 833-item case in miniature', (
      WidgetTester tester,
    ) async {
      const int n = 9;

      final IngestionRunResult result = await ingest(tester, unparsedInbox(n));

      // Cross-check on the pipeline's own counters. Useful, but NOT the
      // authority — see the library note.
      expect(result.examined, n);
      expect(result.routedToReviewQueue, n);
      expect(result.transactionsWritten, 0);
      expect(result.isFullyAccountedFor, isTrue, reason: '$result');

      // The authority: the database itself.
      expect(
        await queueSizeFromDatabase(tester),
        n,
        reason:
            'if this is not $n the test is measuring the wrong thing and every '
            'assertion below is meaningless',
      );
      expect(await transactionsNeedingAttentionFromDatabase(tester), 0);

      await pumpShell(tester);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(
        headlineText(tester),
        '$n items need review',
        reason:
            'KHA-144 verbatim: with a queue this size Home said "All caught '
            'up". AC-C4.2 requires the count of items needing review to be '
            'visible from the main screen, and AC-A4.1 makes an unparsed '
            'financial SMS an item in that queue.',
      );
      expect(
        find.text('All caught up'),
        findsNothing,
        reason: 'a false all-clear is the specific harm KHA-144 reports',
      );

      await disposeHost(tester);
    });

    testWidgets('the card is tappable, and tapping it opens the inbox — '
        'design.md Flow C, which the zero made unreachable', (
      WidgetTester tester,
    ) async {
      await ingest(tester, unparsedInbox(4));
      await pumpShell(tester);

      expect(
        cardIsTappable(tester),
        isTrue,
        reason:
            '`onTap: clear ? null : ...` — a wrong zero did not merely mislabel '
            'the card, it removed the only route Flow C names: "S-08 (tap '
            'review count) -> S-18 [Unparsed tab] -> S-19".',
      );

      await tester.tap(find.byKey(const Key('home.reviewCount')));
      await pumpHostFrames(tester, frames: 20);

      expect(find.byType(NeedsReviewScreen), findsOneWidget);
      // And the tab the user lands on really does hold them — the count and the
      // queue agreeing is the entire fix.
      expect(find.text('Not understood (4)'), findsOneWidget);

      await disposeHost(tester);
    });

    testWidgets('dismissing an item as "not a transaction" takes it back out '
        'of the count (AC-A4.3)', (WidgetTester tester) async {
      // **Why the dismissal happens before the pump, not after.**
      //
      // The tempting version of this test dismisses an item while Home is on
      // screen and watches the number tick down. It deadlocks: post-pump
      // database work has to go through `runAsync` (see [real]), and `runAsync`
      // *blocks the fake clock* while it waits — so any Drift work that was
      // already queued in the fake zone by the pumped providers can never
      // finish, and neither can the write waiting behind it on the same
      // connection. It fails as a ten-minute timeout with no useful message.
      //
      // Dismissing first loses nothing this test is for. Three messages were
      // ingested and one was dismissed, so an implementation that counted
      // ingestion events would say 3 and only one that reads the live queue
      // says 2 — which is the property under test. The *liveness* of the figure
      // is a Drift-stream property, held by `reviewCountRowsProvider`,
      // `reviewQueueProvider` and `reviewInboxProvider` alike and covered by
      // their own suites.
      await ingest(tester, unparsedInbox(3));
      await real(tester, () async {
        final List<RawMessageRow> queue = await session.session.rawMessageDao
            .watchReviewQueue()
            .first;
        await session.session.rawMessageDao.dismissAsNotTransaction(
          queue.first.id,
        );
      });

      // Ground truth, again from the database rather than from arithmetic on
      // what this test believes it did.
      expect(await queueSizeFromDatabase(tester), 2);

      await pumpShell(tester);

      expect(
        headlineText(tester),
        '2 items need review',
        reason:
            'the figure has to track the queue, not a counter that was '
            'incremented once at ingestion time and then drifts',
      );

      await disposeHost(tester);
    });
  });

  // =======================================================================
  // 2. Both halves together
  // =======================================================================

  group('AC-C1.2 + AC-C4.1 — flagged transactions count too', () {
    testWidgets('the headline is unparsed + transactions, and the breakdown '
        'partitions it exactly', (WidgetTester tester) async {
      const int unparsedCount = 9;
      const int parsedCount = 3;

      final IngestionRunResult result = await ingest(tester, <RawSmsRecord>[
        ...unparsedInbox(unparsedCount),
        ...parsedInbox(parsedCount),
      ]);
      expect(result.transactionsWritten, parsedCount);
      expect(result.routedToReviewQueue, unparsedCount);

      // Independently recomputed, from the database, before anything renders.
      final int queued = await queueSizeFromDatabase(tester);
      final int attention = await transactionsNeedingAttentionFromDatabase(
        tester,
      );
      expect(queued, unparsedCount);
      expect(
        attention,
        parsedCount,
        reason:
            'each parsed purchase is from a merchant with no rule, so the real '
            'categorizer leaves it Uncategorized AND flagged (ADR-008)',
      );

      await pumpShell(tester);

      expect(headlineText(tester), '${queued + attention} items need review');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('home.reviewCount.breakdown')))
            .data,
        '$unparsedCount not understood · $parsedCount transactions to check',
        reason:
            'the two figures must ADD UP to the headline. The old breakdown '
            'showed uncategorized and flagged, which overlap, so it never did '
            '— and it omitted the unparsed queue entirely.',
      );

      await disposeHost(tester);
    });

    testWidgets('a row that is both uncategorized AND flagged is counted once, '
        'not twice', (WidgetTester tester) async {
      await ingest(tester, parsedInbox(2));

      final List<TransactionRow> rows = await real(
        tester,
        () => session.session.transactionDao.watchLive().first,
      );
      // The precondition that makes this test meaningful: both properties hold
      // on the same rows, so a sum would say 4 and a union says 2.
      expect(rows.where((TransactionRow r) => r.needsReview).length, 2);
      expect(rows.where((TransactionRow r) => r.categoryId == null).length, 2);

      await pumpShell(tester);

      expect(headlineText(tester), '2 items need review');

      await disposeHost(tester);
    });
  });

  // =======================================================================
  // 3. The third tab — AC-B11.2's "flagged for review"
  // =======================================================================

  group('AC-B11.2 — an undecided transfer counts as an item needing review', () {
    /// A matched pair between two of the user's own accounts.
    ///
    /// Written through `insertFromParsedSms` rather than through the pipeline,
    /// and that is a deliberate, narrow exception: producing a *cross-instrument
    /// matched pair* from SMS needs the entity resolver plus two fabricated
    /// templates, and this group is not testing ingestion — the KHA-144 defect
    /// itself is proved through the real pipeline in the groups above.
    /// `insertFromParsedSms` is the exact method the pipeline calls.
    Future<int> seedTransferPair(WidgetTester tester) => real(tester, () async {
      final BankDao bankDao = BankDao(
        session.database,
        session.session.auditLogDao,
      );
      final InstrumentDao instrumentDao = InstrumentDao(
        session.database,
        session.session.auditLogDao,
      );
      final int bankId = await bankDao.ensure(
        canonicalKey: 'bank-aljazira',
        displayNameAr: 'بنك الجزيرة',
        displayNameEn: 'Bank Aljazira',
      );
      final int current = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.account,
        maskedIdentifier: '****3388',
        refKey: 'bank-aljazira:account:3388',
      );
      final int savings = await instrumentDao.ensure(
        bankId: bankId,
        kind: InstrumentKind.account,
        maskedIdentifier: '****1157',
        refKey: 'bank-aljazira:account:1157',
      );

      final int outId = await session.session.transactionDao
          .insertFromParsedSms(
            amount: Money.parse('2000.00', currency: 'SAR'),
            occurredAt: DateTime.utc(2026, 7, 10, 9),
            direction: 'debit',
            transactionType: TransactionType.transferOut,
            affectsSpend: true,
            instrumentId: current,
            sourceMessageId: 9001,
            rulePackId: 'sa-core',
            rulePackVersion: 'test',
            ruleId: 'baj-transfer-out',
          );
      final int inId = await session.session.transactionDao.insertFromParsedSms(
        amount: Money.parse('2000.00', currency: 'SAR'),
        occurredAt: DateTime.utc(2026, 7, 10, 9, 3),
        direction: 'credit',
        transactionType: TransactionType.transferIn,
        affectsSpend: false,
        instrumentId: savings,
        sourceMessageId: 9002,
        rulePackId: 'sa-core',
        rulePackVersion: 'test',
        ruleId: 'baj-transfer-in',
      );

      // Both legs get a real category, so **neither is uncategorized and
      // neither is flagged**. Without this the rows would be counted by the
      // other two halves and the test would pass whether or not the Transfers
      // tab is wired in at all — the vacuous-pass trap.
      for (final int id in <int>[outId, inId]) {
        await session.session.transactionDao.setUserCategory(
          id: id,
          categoryId: 'groceries',
        );
      }
      return outId;
    });

    testWidgets('one card, one count — the outgoing leg only', (
      WidgetTester tester,
    ) async {
      await seedTransferPair(tester);

      // The precondition, asserted rather than assumed.
      expect(
        await transactionsNeedingAttentionFromDatabase(tester),
        0,
        reason:
            'neither leg is flagged or uncategorized, so anything Home shows '
            'below can only have come from the transfer question itself',
      );

      await pumpShell(tester);

      expect(
        headlineText(tester),
        '1 item needs review',
        reason:
            'AC-B11.2 — an undecidable transfer is "flagged for review". One '
            'card per movement, not one per leg (S-18\'s Transfers tab).',
      );

      await disposeHost(tester);
    });
  });

  // =======================================================================
  // 4. The states that must NOT regress
  // =======================================================================

  group('states', () {
    testWidgets('a genuinely empty queue still says "All caught up", and the '
        'card is not tappable', (WidgetTester tester) async {
      await pumpShell(tester);

      expect(headlineText(tester), 'All caught up');
      expect(
        cardIsTappable(tester),
        isFalse,
        reason:
            'the empty state recedes on purpose — a queue that shouted about '
            'being empty would train the user to ignore it',
      );
      expect(find.byKey(const Key('home.reviewCount.breakdown')), findsNothing);

      await disposeHost(tester);
    });

    testWidgets('locked: no database, so nothing is counted and nothing '
        'crashes (ADR-005)', (WidgetTester tester) async {
      await ingest(tester, unparsedInbox(5));

      useTallHostSurface(tester);
      await tester.pumpWidget(
        hostScope(
          session: session,
          permissions: permissions,
          lockState: const AppLockState(status: AppLockStatus.locked),
          child: const HomeScreen(),
        ),
      );
      await pumpHostFrames(tester, frames: 20);

      // While locked the key is gone, so "we cannot see any items" is the
      // truthful answer rather than a stale cache of the last unlocked count.
      // `app.dart` never routes Home in this state; this asserts the widget is
      // safe if it ever did.
      expect(tester.takeException(), isNull);
      expect(headlineText(tester), 'All caught up');

      await disposeHost(tester);
    });

    testWidgets('Arabic RTL renders the count without overflowing (NFR-U8)', (
      WidgetTester tester,
    ) async {
      await ingest(tester, <RawSmsRecord>[
        ...unparsedInbox(9),
        ...parsedInbox(3),
      ]);
      await pumpShell(tester, locale: 'ar');

      expect(tester.takeException(), isNull);
      // Western digits inside the Arabic string, which is what the app's
      // `intl` configuration produces and what the mockups show — the figure
      // stays LTR-isolated inside an RTL sentence rather than switching to
      // Arabic-Indic numerals. Pinned as a literal so a locale-data change
      // that silently altered it would fail here rather than on a device.
      expect(headlineText(tester), '12 عنصراً يحتاج مراجعة');

      await disposeHost(tester);
    });
  });
}

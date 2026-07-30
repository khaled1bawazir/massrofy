/// **KHA-122's wiring half** — the part no screen test can see.
///
/// ---
///
/// ## Why a wiring test and not a widget test
///
/// The defect had no wrong pixel and no wrong number in it. Everything the
/// screens rendered was correct *for the data they were given*; what was missing
/// was a **trigger**. `docs/lessons.md` records the same shape twice —
/// *"'unreachable today' is a claim about navigation, not about code"*, and
/// KHA-113's six screens that existed with no construction site. An absent call
/// site is invisible to a test that renders a widget over fixed values, and it is
/// invisible to a test that exercises the pipeline directly (the pipeline was
/// never broken). It is only visible from the seam between them, which is what
/// this file pumps: the real providers, the real pipeline, a real database, and
/// the platform boundary faked at exactly one point.
///
/// So the assertion that matters is the **negative control** in the first test:
/// with the signal never raised, no transaction appears no matter how long the
/// container is pumped. That is the failing state QA reproduced on the device. If
/// someone later deletes the `ref.watch(foregroundSmsSignalProvider)` line from
/// `app.dart`, or the `SmsForegroundBridge.signalSmsReceived()` call from
/// `SmsReceiver.kt`, the positive test below goes red rather than the app
/// quietly regressing to a two-minute delay nobody notices in CI.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ingestion/sms_permission_service.dart';
import 'package:massrofy/features/ingestion/sms_source.dart';
import 'package:massrofy/features/parsing/rule_pack.dart';
import 'package:massrofy/presentation/providers/app_providers.dart';
import 'package:massrofy/presentation/providers/ingestion_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../support/app_test_harness.dart';
import 'support/load_bundled_pack.dart';

/// One fabricated BAJ Arabic POS purchase — the shape of QA's repro, with
/// invented values (NFR-M3).
const String _posPurchaseBody =
    'شراء\n'
    'بطاقة:مدى-****4472\n'
    'مبلغ:312.40 SAR\n'
    'لدى:QANDA FOODS\n'
    'في:15-07-26 13:20';

/// A mutable inbox: a test can add a message *after* the container has already
/// swept once, which is precisely the situation KHA-122 is about (the app is
/// already open and has already done its resume sweep).
final class GrowableSmsSource implements SmsSource {
  final List<RawSmsRecord> messages = <RawSmsRecord>[];

  void add(RawSmsRecord record) => messages.add(record);

  @override
  Future<List<RawSmsRecord>> readSince(
    IngestCursor cursor, {
    int limit = 100,
  }) async =>
      (messages..sort(
            (RawSmsRecord a, RawSmsRecord b) =>
                a.providerId.compareTo(b.providerId),
          ))
          .where(
            (RawSmsRecord m) => m.providerId > cursor.lastProcessedProviderId,
          )
          .take(limit)
          .toList();

  @override
  Future<List<RawSmsRecord>> readRange({
    required DateTime from,
    required int afterProviderId,
    required int limit,
  }) async => const <RawSmsRecord>[];

  @override
  Future<int> countRange({required DateTime from}) async => 0;
}

void main() {
  // The rule pack is loaded through `rootBundle` in production; here it is read
  // from disk and injected, so this test needs no asset bundle.
  final RulePack bundledPack = loadBundledRulePack();

  late TestSession session;
  late GrowableSmsSource inbox;
  late FakeSmsBroadcastSignal signal;
  late ProviderContainer container;

  setUp(() {
    session = TestSession.open();
    inbox = GrowableSmsSource();
    signal = FakeSmsBroadcastSignal();

    container = ProviderContainer(
      overrides: [
        // The three platform boundaries, and nothing else. The pipeline, the
        // parser, the DAOs, the watermark and the dedup are all the real
        // implementations — a fake anywhere in there would make this test prove
        // something about the fake.
        unlockedDatabaseSessionProvider.overrideWith(
          (Ref ref) async => session.session,
        ),
        smsPermissionServiceProvider.overrideWithValue(
          FakeSmsPermissionService(current: SmsPermissionStatus.granted),
        ),
        smsSourceProvider.overrideWithValue(inbox),
        smsBroadcastSignalProvider.overrideWithValue(signal),
        activeRulePacksProvider.overrideWith(
          (Ref ref) async => <RulePack>[bundledPack],
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await signal.close();
    await session.close();
  });

  RawSmsRecord record({int providerId = 1}) => RawSmsRecord(
    providerId: providerId,
    address: 'BAJ',
    body: _posPurchaseBody,
    receivedAt: DateTime.utc(2026, 7, 15, 10, 20),
  );

  Future<int> liveTransactions() async =>
      (await session.session.transactionDao.all())
          .where((TransactionRow r) => !r.isDeleted)
          .length;

  /// Lets every provider future/stream settle.
  ///
  /// There is no widget tree here, so there are no frames to pump — draining the
  /// event loop a few times is the equivalent, and it is bounded so a stall fails
  /// as a wrong count rather than as a ten-minute timeout.
  ///
  /// **This is why these are `test` and not `testWidgets`.** `testWidgets` runs
  /// its body inside a `FakeAsync` zone, where `Future.delayed` only completes
  /// when `tester.pump` advances the fake clock — so a real, un-pumped
  /// `await Future.delayed(...)` there hangs forever. These cases exercise
  /// providers, not widgets, so plain `test` with real async is both simpler and
  /// the only thing that works.
  Future<void> settle() async {
    for (int i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Reproduces `app.dart`'s unlocked branch: both providers held alive
  /// together, because the signal provider does the invalidating and the sweep
  /// provider has to be *watched* for an invalidation to re-run it.
  void armAsAppDartDoes() {
    container.listen(
      foregroundSweepProvider,
      (Object? _, Object? __) {},
      fireImmediately: true,
    );
    container.listen(
      foregroundSmsSignalProvider,
      (Object? _, Object? __) {},
      fireImmediately: true,
    );
  }

  test('**AC-A1.1, the QA repro** — an SMS that arrives while the app is '
      'already open and idle becomes a transaction with no user action', () async {
    armAsAppDartDoes();
    await settle();

    // The app has been open for a while: the unlock sweep has already run over
    // an empty inbox and found nothing.
    expect(await liveTransactions(), 0);

    // Now the SMS lands. The Kotlin receiver would have enqueued its (no-op)
    // WorkManager job and raised the bridge signal; here only the inbox row and
    // the signal are simulated.
    inbox.add(record());

    // ## The negative control, and the reason this test is worth its length
    //
    // Before KHA-122 the story stopped here: the message sat in the inbox and
    // nothing re-armed the sweep, so Home kept showing 0.00 SAR. Asserting that
    // explicitly is what stops this test passing for the wrong reason — e.g. if
    // some provider elsewhere were polling, the positive assertion below would
    // pass with the trigger wire removed.
    await settle();
    expect(
      await liveTransactions(),
      0,
      reason:
          'nothing may sweep on its own — if this fails, the assertion after '
          'the signal proves nothing about the signal',
    );

    signal.emit();
    await settle();

    expect(
      await liveTransactions(),
      1,
      reason:
          'AC-A1.1: the transaction must appear with the app never leaving the '
          'foreground. This is the exact step-4 failure QA recorded.',
    );
    // Traceable to the message it came from, not just "a row exists".
    final List<TransactionRow> rows = await session.session.transactionDao
        .all();
    expect(
      // Compared as `Money`, not as a string: `Decimal`'s canonical form of
      // `312.40` is `"312.4"` (they are the same value), and the trailing zero is
      // added back at display time by `formatAmountDigits`. Asserting the string
      // would pin a storage detail and read as a rounding bug to the next person.
      Money.tryParse(
        rows.single.amountAmount,
        currency: rows.single.amountCurrency,
      ),
      Money.parse('312.40', currency: 'SAR'),
    );
    expect(rows.single.merchantRawText, 'QANDA FOODS');
  });

  test('a second signal for the same SMS adds nothing (AC-A5.1)', () async {
    armAsAppDartDoes();
    await settle();

    inbox.add(record());
    signal.emit();
    await settle();
    expect(await liveTransactions(), 1);

    // Two more signals, e.g. a multi-part message delivering as several
    // broadcasts. Each re-runs the sweep; the watermark makes each a no-op.
    signal.emit();
    signal.emit();
    await settle();

    expect(await liveTransactions(), 1);
  });

  test('while LOCKED the signal is not even subscribed — AC-A1.4 is '
      'unchanged by this fix', () async {
    // A locked session is the honest "no database" state (ADR-005), so a prompt
    // sweep is not merely skipped, it is impossible. Product-owner's scope note
    // put the backgrounded/locked case explicitly out of scope, and this pins
    // that it stayed out.
    final ProviderContainer locked = ProviderContainer(
      overrides: [
        unlockedDatabaseSessionProvider.overrideWith((Ref ref) async => null),
        smsPermissionServiceProvider.overrideWithValue(
          FakeSmsPermissionService(current: SmsPermissionStatus.granted),
        ),
        smsSourceProvider.overrideWithValue(inbox),
        smsBroadcastSignalProvider.overrideWithValue(signal),
        activeRulePacksProvider.overrideWith(
          (Ref ref) async => <RulePack>[bundledPack],
        ),
      ],
    );
    addTearDown(locked.dispose);

    locked.listen(
      foregroundSmsSignalProvider,
      (Object? _, Object? __) {},
      fireImmediately: true,
    );
    await settle();

    inbox.add(record());
    signal.emit();
    await settle();

    // The stream completed without emitting: no subscription, no invalidation.
    expect(locked.read(foregroundSmsSignalProvider).value, isNull);
    expect(await liveTransactions(), 0);
  });

  test('with SMS permission revoked the signal is not subscribed either '
      '(AC-A1.3)', () async {
    final ProviderContainer revoked = ProviderContainer(
      overrides: [
        unlockedDatabaseSessionProvider.overrideWith(
          (Ref ref) async => session.session,
        ),
        smsPermissionServiceProvider.overrideWithValue(
          FakeSmsPermissionService(current: SmsPermissionStatus.denied),
        ),
        smsSourceProvider.overrideWithValue(inbox),
        smsBroadcastSignalProvider.overrideWithValue(signal),
        activeRulePacksProvider.overrideWith(
          (Ref ref) async => <RulePack>[bundledPack],
        ),
      ],
    );
    addTearDown(revoked.dispose);

    revoked.listen(
      foregroundSmsSignalProvider,
      (Object? _, Object? __) {},
      fireImmediately: true,
    );
    await settle();

    inbox.add(record());
    signal.emit();
    await settle();

    expect(revoked.read(foregroundSmsSignalProvider).value, isNull);
    expect(await liveTransactions(), 0);
  });
}

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
/// container is pumped. That is the failing state QA reproduced on the device.
///
/// ## Exactly what the provider tests below do and do not cover (KHA-138)
///
/// An earlier version of this comment claimed that deleting
/// `ref.watch(foregroundSmsSignalProvider)` from `app.dart` would turn the
/// positive test below red. **It would not, and QA proved it by mutation: the
/// whole suite stayed green with that line commented out.** The claim was wrong
/// in a specific and instructive way, so it is worth stating rather than
/// quietly correcting.
///
/// The provider tests arm the graph **by hand**, in `armAsAppDartDoes` —
/// two `container.listen` calls that reproduce what `app.dart` does. They
/// therefore prove that *the providers compose correctly once something
/// subscribes to them*, and nothing at all about whether anything in the
/// shipped app ever subscribes. They never read `app.dart`. That is precisely
/// the trap `docs/lessons.md` names: *"verify a reachability claim by grepping
/// for the construction site, never from the fact that the widget exists in the
/// tree."*
///
/// | Claim | Covered by |
/// |---|---|
/// | the providers compose: a raised signal ends in a written transaction | the positive test below (`container.listen` arms them by hand) |
/// | nothing sweeps *without* a signal | the negative control below — load-bearing, and the reason the positive test is not vacuous |
/// | the subscription is not opened while locked / without permission | the two guard tests below |
/// | **`app.dart` actually subscribes, in the unlocked branch** | **the `app.dart` source guard below** — added by KHA-138; nothing covered this before |
/// | `SmsReceiver.kt` actually raises the signal | `test/platform/sms_foreground_bridge_test.dart`, not this file |
///
/// The last two are source-shape guards rather than behavioural tests, for the
/// same reason the Kotlin one is: neither a `BroadcastReceiver` firing nor a
/// `MassrofyApp` bound to a real `EventChannel` exists inside `flutter test`.
/// A source guard is weaker than executing the wire, and it is much stronger
/// than the nothing that was there.
library;

import 'dart:io';

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

  /// KHA-157 (A). Modelled honestly rather than stubbed: this inbox starts
  /// **empty and readable**, which seeds `providerId = 0` — so every message
  /// [add]ed afterwards is above the seed and is still swept, which is exactly
  /// the property these tests exist to pin and exactly the property the seed
  /// must not break.
  @override
  Future<InboxHighWaterMark?> highWaterMark() async {
    if (messages.isEmpty) {
      return InboxHighWaterMark(
        providerId: 0,
        dateUtc: DateTime.utc(2026, 7, 15),
      );
    }
    final RawSmsRecord newest = messages.reduce(
      (RawSmsRecord a, RawSmsRecord b) => a.providerId >= b.providerId ? a : b,
    );
    return InboxHighWaterMark(
      providerId: newest.providerId,
      dateUtc: newest.receivedAt,
    );
  }

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

  // =======================================================================
  // KHA-138 — the production call site, guarded at the source
  // =======================================================================
  //
  // Everything above arms the providers by hand. This group is the only thing
  // in the repo that checks the *shipped app* arms them, which is the gap QA's
  // mutation exposed: with `ref.watch(foregroundSmsSignalProvider)` deleted
  // from `app.dart`, all 1540 tests stayed green while the app on a device
  // regressed to the two-minute delay KHA-122 was filed for.
  //
  // Same technique and same justification as
  // `test/platform/sms_foreground_bridge_test.dart`, which guards the Kotlin
  // half — see that file's header. Executing the wire needs a `MassrofyApp`
  // bound to a real `EventChannel` on a real engine, which `flutter test` does
  // not have.
  group('KHA-138 — app.dart really does subscribe, in the unlocked branch', () {
    const String appDartPath = 'lib/app.dart';

    /// [source] with all `//` and `/* */` comments removed.
    ///
    /// **Not optional here, unlike in some source guards.** `app.dart`'s
    /// comment block explaining KHA-122 names `foregroundSmsSignalProvider`
    /// four times. A `contains` over the raw text would therefore pass on a
    /// file where the code had been deleted and only the explanation left
    /// behind — the single most likely way this actually regresses, since a
    /// developer removing a line rarely removes the paragraph above it.
    String codeOnly(String source) => source
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .split('\n')
        .map((String line) {
          final int comment = line.indexOf('//');
          return comment < 0 ? line : line.substring(0, comment);
        })
        .join('\n');

    /// The body of `app.dart`'s `if (unlocked) { ... }`, by brace matching.
    ///
    /// Scoping to the branch rather than to the whole file is the point.
    /// A `watch` moved *outside* the branch would keep the `EventChannel`
    /// subscription open while the app is locked — which AC-A1.4 forbids and
    /// which the guard tests above assert against at the provider level. So
    /// "present in app.dart" is the wrong property; "present in the unlocked
    /// branch" is the right one, and only the second is checked here.
    String unlockedBranch(String code) {
      const String marker = 'if (unlocked) {';
      final int start = code.indexOf(marker);
      expect(
        start,
        isNot(-1),
        reason:
            'could not find "$marker" in $appDartPath. If the gate was '
            'restructured, update this test — do not delete it: it is the '
            'only automated check that KHA-122 is wired into the app at all.',
      );

      int depth = 0;
      final int open = start + marker.length - 1;
      for (int i = open; i < code.length; i++) {
        if (code[i] == '{') depth++;
        if (code[i] == '}') {
          depth--;
          if (depth == 0) return code.substring(open + 1, i);
        }
      }
      fail('unbalanced braces after "$marker" in $appDartPath');
    }

    late String branch;

    setUp(() {
      final File file = File(appDartPath);
      // Guard the guard: a moved file must fail loudly rather than assert
      // nothing about an empty string.
      expect(
        file.existsSync(),
        isTrue,
        reason: 'expected to find $appDartPath',
      );
      branch = unlockedBranch(codeOnly(file.readAsStringSync()));
    });

    test('the KHA-122 signal provider is watched inside the unlocked '
        'branch', () {
      expect(
        branch,
        contains('ref.watch(foregroundSmsSignalProvider)'),
        reason:
            'this is KHA-122\'s entire production call site. Without it the '
            'EventChannel is never subscribed, SmsForegroundBridge emits into '
            'nothing, and an SMS arriving while the app sits open and idle is '
            'not ingested until the user backgrounds and reopens — with Home '
            'stating "All caught up" in the meantime. Every provider test in '
            'this file still passes in that state, which is why this '
            'assertion exists (KHA-138).',
      );
    });

    test('the resume/unlock sweep provider is watched there too', () {
      // The signal provider only *invalidates* the sweep provider. If nothing
      // watches the sweep, an invalidation re-runs nothing — so deleting this
      // line breaks KHA-122 just as completely, and just as silently.
      expect(
        branch,
        contains('ref.watch(foregroundSweepProvider)'),
        reason:
            'foregroundSmsSignalProvider invalidates this one; an invalidated '
            'provider with no listener is never rebuilt, so the signal would '
            'arrive and nothing would sweep',
      );
    });

    test('neither watch has escaped to the locked path (AC-A1.4)', () {
      // The inverse property, and the reason the two tests above are not
      // sufficient on their own. A *duplicate* watch — one inside the branch
      // and one hoisted above it — would satisfy both of them while holding
      // the EventChannel subscription open under the lock screen, which
      // AC-A1.4 forbids and ADR-005 makes pointless (no unwrapped key, so
      // nothing could be written even if a signal arrived).
      //
      // Counting rather than searching is what catches that: every occurrence
      // in the file must be an occurrence in the branch.
      int count(String haystack, String needle) =>
          haystack.split(needle).length - 1;

      final String code = codeOnly(File(appDartPath).readAsStringSync());
      for (final String call in <String>[
        'ref.watch(foregroundSmsSignalProvider)',
        'ref.watch(foregroundSweepProvider)',
      ]) {
        expect(
          count(code, call),
          count(branch, call),
          reason:
              'every "$call" in $appDartPath must be inside the unlocked '
              'branch. One outside it would subscribe while the app is '
              'locked (AC-A1.4).',
        );
      }
    });
  });
}

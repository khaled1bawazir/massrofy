/// **Widget tests for KHA-133's "check my banks again" screen.**
///
/// Two halves, and both are needed for different reasons:
///
///  1. **Render tests** over `RecheckBanksScreen` directly, one per state.
///     Every state design.md §3.4 asks for is here — idle, loading, result
///     (found / empty), locked, unauthorized, error — because a state that is
///     built but never rendered in a test is a state nobody has looked at.
///  2. **A wiring test** through the real `AppShell` → More menu → route →
///     host → providers. `docs/lessons.md`: *"verify a reachability claim by
///     grepping for the construction site, never from the fact that the widget
///     exists in the tree."* KHA-113 found six screens that existed and could
///     not be reached; this is how this one avoids being the seventh.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/features/ingestion/ingestion_pipeline.dart';
import 'package:massrofy/features/ingestion/rescan_coordinator.dart';
import 'package:massrofy/features/ingestion/sms_permission_service.dart';
import 'package:massrofy/presentation/providers/rescan_providers.dart';
import 'package:massrofy/presentation/screens/app_shell.dart';
import 'package:massrofy/presentation/screens/recheck_banks_screen.dart';

import '../support/app_test_harness.dart';

/// A result shaped like the one the human's own recovery would produce.
RescanResult _result({
  int written = 0,
  int review = 0,
  int suppressed = 0,
  int failed = 0,
  int examined = 41,
}) => RescanResult(
  counts: IngestionRunResult(
    examined: examined,
    transactionsWritten: written,
    routedToReviewQueue: review,
    suppressedAsExactDuplicate: suppressed,
    failedWithError: failed,
  ),
  windowFromUtc: DateTime.utc(2026, 6, 30, 21),
  messagesInWindow: 63,
);

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    RescanState state, {
    String locale = 'en',
    VoidCallback? onRecheck,
  }) async {
    useTallHostSurface(tester);
    await tester.pumpWidget(
      wrapHost(
        RecheckBanksScreen(state: state, onRecheck: onRecheck ?? () {}),
        locale: locale,
      ),
    );
    await tester.pump();
  }

  group('states', () {
    testWidgets('idle offers the action and explains what it covers', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, const RescanIdle());

      expect(find.byKey(const Key('recheckBanks.action')), findsOneWidget);

      // The two facts ADR-006 requires the user be told before they press it:
      // nothing is double-counted, and the range is the import's, not all
      // history.
      expect(find.textContaining('Nothing is counted twice'), findsOneWidget);
      expect(
        find.textContaining('same date range as the first import'),
        findsOneWidget,
      );
    });

    testWidgets('the button is disabled when the host passes no callback', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapHost(
          const RecheckBanksScreen(state: RescanIdle(), onRecheck: null),
        ),
      );
      await tester.pump();

      final FilledButton button = tester.widget<FilledButton>(
        find.byKey(const Key('recheckBanks.action')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('tapping the action calls back exactly once', (
      WidgetTester tester,
    ) async {
      int calls = 0;
      await pumpScreen(tester, const RescanIdle(), onRecheck: () => calls++);

      await tester.tap(find.byKey(const Key('recheckBanks.action')));
      await tester.pump();

      expect(calls, 1);
    });

    testWidgets('running shows an indeterminate bar and no action button', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, const RescanRunning());

      expect(find.byKey(const Key('recheckBanks.running')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('recheckBanks.action')), findsNothing);
    });

    testWidgets('a result that found transactions says how many', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        RescanSucceeded(_result(written: 12, examined: 41)),
      );

      expect(find.byKey(const Key('recheckBanks.result')), findsOneWidget);
      expect(find.text('Found 12 new transactions'), findsOneWidget);
      // "how many messages were re-examined", asked for explicitly.
      expect(
        find.textContaining('41 bank messages re-checked'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('recheckBanks.again')), findsOneWidget);
    });

    testWidgets('a single recovered transaction reads as singular', (
      WidgetTester tester,
    ) async {
      // "Found 1 new transactions" on the headline of a screen whose entire
      // job is explaining retroactive numbers is exactly the sloppiness that
      // costs trust in the numbers themselves.
      await pumpScreen(tester, RescanSucceeded(_result(written: 1, review: 1)));

      expect(find.text('Found 1 new transaction'), findsOneWidget);
      expect(find.textContaining('1 of them needs review'), findsOneWidget);
    });

    testWidgets('"Check again" on a result re-runs, it does not just clear', (
      WidgetTester tester,
    ) async {
      int runs = 0;
      await pumpScreen(
        tester,
        RescanSucceeded(_result(written: 2)),
        onRecheck: () => runs++,
      );

      await tester.tap(find.byKey(const Key('recheckBanks.again')));
      await tester.pump();
      expect(runs, 1);
    });

    testWidgets('review items are named, so the user knows where they went', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, RescanSucceeded(_result(written: 9, review: 3)));

      expect(find.textContaining('3 of them need review'), findsOneWidget);
    });

    testWidgets('an empty result says so plainly, and names the window', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, RescanSucceeded(_result(suppressed: 41)));

      expect(find.text('Nothing new found'), findsOneWidget);
      // The Riyadh-shifted window start: 30 June 21:00 UTC IS 1 July in
      // Riyadh, and printing the raw UTC instant would say "Jun 30" for a
      // window that begins on 1 July. Asserted both ways round, because
      // "contains Jul 1" alone would also pass a string that said both.
      expect(find.textContaining('Jul 1'), findsOneWidget);
      expect(find.textContaining('Jun 30'), findsNothing);
    });

    testWidgets('a partial failure is disclosed rather than hidden', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, RescanSucceeded(_result(written: 4, failed: 2)));

      expect(
        find.textContaining('2 messages could not be read'),
        findsOneWidget,
      );
    });

    testWidgets('review and failure lines are absent when their counts are 0', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, RescanSucceeded(_result(written: 4)));

      expect(find.textContaining('need review'), findsNothing);
      expect(find.textContaining('could not be read'), findsNothing);
    });

    testWidgets('locked: ADR-005 copy, and NO retry button', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, const RescanFailed(RescanFailureReason.locked));

      expect(find.byKey(const Key('recheckBanks.failure')), findsOneWidget);
      expect(find.textContaining('The app locked'), findsOneWidget);
      // Retrying cannot work until the user unlocks; a button that cannot
      // succeed is worse than no button.
      expect(find.byKey(const Key('recheckBanks.retry')), findsNothing);
    });

    testWidgets('unauthorized: AC-A1.3 copy, and no retry button', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const RescanFailed(RescanFailureReason.permissionDenied),
      );

      expect(find.textContaining('cannot read your messages'), findsOneWidget);
      expect(find.byKey(const Key('recheckBanks.retry')), findsNothing);
    });

    testWidgets('error: honest copy, reassurance, and a retry', (
      WidgetTester tester,
    ) async {
      int retries = 0;
      await pumpScreen(
        tester,
        const RescanFailed(RescanFailureReason.unexpectedError),
        onRecheck: () => retries++,
      );

      expect(find.textContaining('Something went wrong'), findsOneWidget);
      // The sentence that matters: the user's first fear on seeing an error
      // from a button that rewrites history is that it broke something.
      expect(
        find.textContaining('existing transactions are unaffected'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('recheckBanks.retry')));
      await tester.pump();
      // Retry re-runs the re-check itself; it does not merely clear the card
      // and make the user find the button again.
      expect(retries, 1);
    });

    testWidgets('renders in Arabic RTL without overflow (NFR-U8)', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        RescanSucceeded(_result(written: 12, review: 3, failed: 1)),
        locale: 'ar',
      );

      expect(tester.takeException(), isNull);
      expect(find.text('افحص بنوكي مرة أخرى'), findsOneWidget);
    });

    testWidgets('survives a 2x text scale (NFR-U7)', (
      WidgetTester tester,
    ) async {
      useTallHostSurface(tester);
      await tester.pumpWidget(
        wrapHost(
          RecheckBanksScreen(
            state: RescanSucceeded(_result(written: 12, review: 3)),
            onRecheck: () {},
          ),
          textScale: 2.0,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('wiring', () {
    late TestSession session;
    late FakeSmsPermissionService permissions;

    setUp(() {
      session = TestSession.open();
      permissions = FakeSmsPermissionService(
        current: SmsPermissionStatus.granted,
      );
    });

    tearDown(() async => session.close());

    testWidgets(
      'the More menu actually constructs the screen (KHA-113 lesson)',
      (WidgetTester tester) async {
        useTallHostSurface(tester);
        await tester.pumpWidget(
          hostScope(
            session: session,
            permissions: permissions,
            child: const AppShell(),
          ),
        );
        await pumpHostFrames(tester);

        await tester.tap(find.byKey(const Key('nav.more')));
        await pumpHostFrames(tester);

        await tester.tap(find.byKey(const Key('more.recheckBanks')));
        await pumpHostFrames(tester);

        expect(find.byType(RecheckBanksScreen), findsOneWidget);
        expect(find.byKey(const Key('recheckBanks.action')), findsOneWidget);

        await disposeHost(tester);
      },
    );

    testWidgets(
      'with SMS permission revoked, pressing it reports the unauthorized '
      'state rather than claiming nothing was found',
      (WidgetTester tester) async {
        // The failure this guards against is the quiet one: with no `READ_SMS`
        // there is nothing to read, so a naive implementation would run, find
        // zero messages, and tell the user "Nothing new found" — which is
        // indistinguishable from "your data is fine".
        permissions.current = SmsPermissionStatus.denied;

        useTallHostSurface(tester);
        await tester.pumpWidget(
          hostScope(
            session: session,
            permissions: permissions,
            child: const AppShell(),
          ),
        );
        await pumpHostFrames(tester);

        await tester.tap(find.byKey(const Key('nav.more')));
        await pumpHostFrames(tester);
        await tester.tap(find.byKey(const Key('more.recheckBanks')));
        await pumpHostFrames(tester);

        await tester.tap(find.byKey(const Key('recheckBanks.action')));
        await pumpHostFrames(tester);

        expect(
          find.textContaining('cannot read your messages'),
          findsOneWidget,
        );
        expect(find.text('Nothing new found'), findsNothing);

        await disposeHost(tester);
      },
    );
  });
}

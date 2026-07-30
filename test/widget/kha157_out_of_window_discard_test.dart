/// **KHA-157 (E) — the discard offer on S-18, as a real journey.**
///
/// Item (E) is a **new UI surface**, not a silent backend cleanup: the human
/// has 424 rows in their Needs Review inbox right now, and this banner is how
/// they get cleaned up. So it is tested the way a screen is tested — rendered,
/// tapped, confirmed, and re-read — in **both locales**, at a 2.0 text scale,
/// and through the real `NeedsReviewHost` with real providers over a real
/// database, not only against the leaf widget.
///
/// The states asserted, per design.md §3.4:
///
/// | State | Case |
/// |---|---|
/// | absent | healthy install — nothing out of window |
/// | populated | the offer, with its count and its date |
/// | confirm | the dialog, and **cancel writes nothing** |
/// | after | the rows are gone and the offer disappears |
/// | locked | no session → no button behind the offer |
///
/// NFR-M3: every message body here is fabricated.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/text/sms_sanitizer.dart';
import 'package:massrofy/core/time/clock.dart';
import 'package:massrofy/data/dao/raw_message_dao.dart';
import 'package:massrofy/features/ingestion/review_queue.dart';
import 'package:massrofy/features/ingestion/sms_permission_service.dart';
import 'package:massrofy/features/security/app_lock_state.dart';
import 'package:massrofy/presentation/screens/categorization_routes.dart';
import 'package:massrofy/presentation/screens/needs_review_screen.dart';

import '../support/app_test_harness.dart';
import 'p3_screens_test.dart' show useTallSurface, wrap;

/// Well before any plausible current window — the point of the whole feature.
final DateTime _longAgo = DateTime.utc(2025, 11, 4, 8);
final DateTime _alsoLongAgo = DateTime.utc(2026, 2, 17, 13);

/// The date the banner names — 21:00 UTC on 30 June, which is **1 July** in
/// Riyadh. Chosen precisely because the two differ: a label built from the raw
/// UTC instant would say 30 June, and the assertions below can tell.
final DateTime _windowStart = DateTime.utc(2026, 6, 30, 21);

/// What the journey group below pretends "now" is — **KHA-161**.
///
/// Mid-July 2026. This instant and every fixture date in this file form one
/// contract:
///
///  * it is inside the same Riyadh calendar month as [_windowStart], so the
///    window the real code computes is the window the fixtures were written
///    against;
///  * it is *after* [_inWindow], so the scenario is physically coherent — a
///    device holds messages that have already arrived, not future ones;
///  * [_longAgo] and [_alsoLongAgo] stay far below the window, which is the
///    whole point of the feature under test.
///
/// All three are asserted by the last test in this file ("the pinned clock,
/// the window and the in-window fixture agree"), so re-dating any one of them
/// fails loudly there instead of quietly re-classifying a fixture inside a
/// journey test.
final DateTime _pinnedNowUtc = DateTime.utc(2026, 7, 15, 12);

/// A message that arrived *inside* the current window: the control row that
/// must survive the discard, and the sole occupant of the "healthy install"
/// case. Named rather than repeated so it cannot drift away from
/// [_pinnedNowUtc] at one of its two call sites.
final DateTime _inWindow = DateTime.utc(2026, 7, 12, 10);

OutOfWindowReviewSummary _summary(int count) =>
    OutOfWindowReviewSummary(itemCount: count, windowStartUtc: _windowStart);

ReviewQueueItem _item(int id, DateTime receivedAt) => ReviewQueueItem(
  rawMessageId: id,
  sanitizedBody: 'D360: Purchase of SAR 41.00 at SYNTHETIC STORE $id',
  sender: 'D360',
  receivedAt: receivedAt,
);

void main() {
  // =========================================================================
  // The leaf widget — every state, both locales, 2.0 text scale
  // =========================================================================
  group('S-18 out-of-window discard offer', () {
    Widget screen({
      OutOfWindowReviewSummary? summary,
      Future<void> Function()? onDiscard,
      String locale = 'en',
      double textScale = 1.0,
    }) => wrap(
      NeedsReviewScreen(
        unparsed: <ReviewQueueItem>[_item(1, _longAgo), _item(2, _alsoLongAgo)],
        flagged: const <FlaggedTransactionItem>[],
        onFillInDetails: (_) {},
        onNotATransaction: (_) {},
        onOpenFlagged: (_) {},
        outOfWindow: summary,
        onDiscardOutOfWindow: onDiscard,
      ),
      locale: locale,
      textScale: textScale,
    );

    testWidgets('is ABSENT on a healthy install — a null summary and a zero '
        'summary both render nothing', (WidgetTester tester) async {
      useTallSurface(tester);

      await tester.pumpWidget(screen());
      expect(find.byKey(const Key('needsReview.outOfWindow')), findsNothing);

      await tester.pumpWidget(screen(summary: _summary(0)));
      await tester.pump();
      expect(
        find.byKey(const Key('needsReview.outOfWindow')),
        findsNothing,
        reason:
            'the banner is for flooded devices. On every healthy install it '
            'must never appear at all.',
      );
    });

    testWidgets('shows the count and the WINDOW DATE, so the offer is '
        'checkable rather than a number to be trusted', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        screen(summary: _summary(424), onDiscard: () async {}),
      );
      await tester.pump();

      expect(find.byKey(const Key('needsReview.outOfWindow')), findsOneWidget);
      expect(find.textContaining('424'), findsWidgets);

      // **The Riyadh shift, asserted as the user would check it.** The window
      // opens at 21:00 UTC on 30 June, which is 1 July in Riyadh. Printing the
      // raw UTC instant would name **30 June** — the wrong day, on the one
      // date the user is asked to check before agreeing to a deletion. So the
      // assertion is both halves: the right date is present and the wrong one
      // is absent, because "contains Jul 1" alone would also pass a string
      // that said "30 Jun – Jul 1".
      expect(
        find.textContaining('July 1, 2026'),
        findsWidgets,
        reason: 'the label must name the Riyadh day, not the UTC one',
      );
      expect(
        find.textContaining('June 30'),
        findsNothing,
        reason:
            'naming 30 June would be the un-shifted UTC instant — the exact '
            'trap `recheck_banks_screen.dart` documents for this same value',
      );
      expect(
        find.byKey(const Key('needsReview.outOfWindowDiscard')),
        findsOneWidget,
      );
    });

    testWidgets('renders NO button when there is nothing behind it (locked)', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(screen(summary: _summary(12)));
      await tester.pump();

      expect(find.byKey(const Key('needsReview.outOfWindow')), findsOneWidget);
      expect(
        find.byKey(const Key('needsReview.outOfWindowDiscard')),
        findsNothing,
        reason:
            'an action is never offered without something behind it — the '
            'same discipline the merge button follows',
      );
    });

    testWidgets('**asks before deleting, and CANCEL discards nothing**', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      int calls = 0;
      await tester.pumpWidget(
        screen(summary: _summary(424), onDiscard: () async => calls++),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('needsReview.outOfWindowDiscard')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('not affected'),
        findsOneWidget,
        reason:
            'the fear this dialog has to answer is "will this delete my '
            'transactions?" — so it answers it explicitly',
      );

      await tester.tap(find.byKey(const Key('needsReview.outOfWindowCancel')));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('confirming calls the discard exactly once', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      int calls = 0;
      await tester.pumpWidget(
        screen(summary: _summary(424), onDiscard: () async => calls++),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('needsReview.outOfWindowDiscard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('needsReview.outOfWindowConfirm')));
      await tester.pumpAndSettle();

      expect(calls, 1);
    });

    testWidgets('renders in Arabic RTL (NFR-U8) and at a 2.0 text scale '
        'without overflowing (NFR-U3)', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        screen(
          summary: _summary(424),
          onDiscard: () async {},
          locale: 'ar',
          textScale: 2.0,
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('needsReview.outOfWindow')), findsOneWidget);
      expect(
        Directionality.of(
          tester.element(find.byKey(const Key('needsReview.outOfWindow'))),
        ),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  // The real journey, through NeedsReviewHost over a real database
  // =========================================================================
  group('the journey: 424 rows in, banner tapped, rows gone', () {
    late TestSession session;

    setUp(() => session = TestSession.open());
    tearDown(() async => session.close());

    /// **KHA-161: these tests must not depend on today's date.**
    ///
    /// Unlike the leaf-widget group above — which hands the screen a summary it
    /// built itself — this group renders the *real* `NeedsReviewHost`, so the
    /// cutoff is computed by the code under test from
    /// `RiyadhCalendar.startOfCurrentMonthUtc(clock.nowUtc())`. With the real
    /// `SystemClock` that cutoff advances every month while the fixtures below
    /// stay hard-dated July 2026, so from 1 August in Riyadh
    /// (`2026-07-31T21:00Z`) [_inWindow] falls *below* the window: the healthy
    /// install grows a banner it asserts is absent, and the cleanup journey's
    /// surviving control row is deleted along with the rest.
    ///
    /// Pinning the clock is the whole fix. Nothing else about these tests —
    /// their subject, their fixtures, their assertions — changes.
    Widget host({
      AppLockState lockState = const AppLockState(
        status: AppLockStatus.unlocked,
      ),
    }) => hostScope(
      session: session,
      permissions: FakeSmsPermissionService(
        current: SmsPermissionStatus.granted,
      ),
      lockState: lockState,
      clock: FixedClock(_pinnedNowUtc),
      child: const NeedsReviewHost(autoConfirmDelay: Duration.zero),
    );

    /// One pending review row, exactly as the flood produced them.
    Future<void> flooded(RawMessageDao dao, int n, DateTime at) => dao.insert(
      smsProviderId: 'p$n',
      sender: 'D360',
      receivedAt: at,
      sanitizedText: SmsSanitizer.sanitize(
        'D360: Purchase of SAR ${20 + n}.00 at SYNTHETIC STORE $n',
      ),
      contentHmac: 'hmac-$n',
      bankId: 'bank-d360',
      classification: 'financial_unparsed',
      unparsedReason: 'no_rule_matched',
    );

    testWidgets(
      '**the human\'s cleanup, end to end** — the offer appears over '
      'the real queue, confirming deletes the rows, and the offer goes away',
      (WidgetTester tester) async {
        useTallSurface(tester);
        final RawMessageDao dao = session.session.rawMessageDao;

        // Three out-of-window rows and one legitimate in-window row. The
        // in-window one is the control: it must survive.
        await tester.runAsync(() async {
          await flooded(dao, 1, _longAgo);
          await flooded(dao, 2, _alsoLongAgo);
          await flooded(dao, 3, DateTime.utc(2026, 3, 9, 7));
          await flooded(dao, 4, _inWindow);
        });

        await tester.pumpWidget(host());
        await pumpHostFrames(tester);

        expect(
          find.byKey(const Key('needsReview.outOfWindow')),
          findsOneWidget,
          reason:
              'the banner has to be reachable from the real host, not just '
              'constructible — a provider that composes correctly and a screen '
              'that never reads it is a shipped bug with a green test',
        );
        expect(find.textContaining('3'), findsWidgets);

        await tester.tap(
          find.byKey(const Key('needsReview.outOfWindowDiscard')),
        );
        await pumpHostFrames(tester);
        await tester.tap(
          find.byKey(const Key('needsReview.outOfWindowConfirm')),
        );
        await pumpHostFrames(tester, frames: 20);

        // The database is the oracle, not the pixels.
        final List<dynamic> remaining =
            await tester.runAsync(() => dao.watchReviewQueue().first)
                as List<dynamic>;
        expect(
          remaining,
          hasLength(1),
          reason: 'only the in-window message survives',
        );

        expect(
          find.byKey(const Key('needsReview.outOfWindow')),
          findsNothing,
          reason:
              'the offer must disappear once taken, or it sits there offering '
              'to delete rows that are already gone',
        );

        await disposeHost(tester);
      },
    );

    testWidgets(
      'is absent on a healthy install reached through the real host',
      (WidgetTester tester) async {
        useTallSurface(tester);
        await tester.runAsync(
          () => flooded(session.session.rawMessageDao, 9, _inWindow),
        );

        await tester.pumpWidget(host());
        await pumpHostFrames(tester);

        expect(find.byKey(const Key('needsReview.outOfWindow')), findsNothing);

        await disposeHost(tester);
      },
    );

    testWidgets('shows no discard button while the app is LOCKED — ADR-005 '
        'means there is no database to delete from', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);

      await tester.pumpWidget(
        host(lockState: const AppLockState(status: AppLockStatus.locked)),
      );
      await pumpHostFrames(tester);

      expect(
        find.byKey(const Key('needsReview.outOfWindowDiscard')),
        findsNothing,
      );

      await disposeHost(tester);
    });
  });

  // =========================================================================
  // The fixture contract itself — KHA-161
  // =========================================================================

  /// Guards the arithmetic the group above now depends on, so that a future
  /// re-dating fails *here*, with a one-line explanation, instead of surfacing
  /// as "the banner appeared and I don't know why" in a journey test.
  ///
  /// This asserts nothing about the app's behaviour; it asserts that the
  /// fixtures still describe the situation their names claim. That is worth a
  /// test rather than a comment because the original defect was precisely a
  /// prose assumption ("these dates are in the current window") that no
  /// assertion held to account.
  test('the pinned clock, the window and the in-window fixture agree', () {
    expect(
      RiyadhCalendar.startOfCurrentMonthUtc(_pinnedNowUtc),
      _windowStart,
      reason:
          'the pinned "now" must sit in the same Riyadh calendar month the '
          'banner fixtures name, or the real cutoff and _windowStart diverge',
    );
    expect(
      _inWindow.isAfter(_windowStart) && _inWindow.isBefore(_pinnedNowUtc),
      isTrue,
      reason:
          'the surviving control row must be inside the window AND already '
          'have arrived by the pinned instant',
    );
    for (final DateTime old in <DateTime>[_longAgo, _alsoLongAgo]) {
      expect(
        old.isBefore(_windowStart),
        isTrue,
        reason: 'the flood fixtures are the ones the offer exists to remove',
      );
    }
  });
}

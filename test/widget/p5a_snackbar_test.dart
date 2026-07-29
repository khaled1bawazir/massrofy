/// **KHA-115 — the correction snackbar that never went away.**
///
/// QA's emulator walk found it on screen for ~9 minutes across four route
/// changes, carrying a live *Undo* that silently reverted a three-row category
/// correction and deleted the learned rule behind it when it was tapped by
/// accident.
///
/// ## The regression these tests actually pin
///
/// The issue's suggested cause was a never-completing entry animation. It was
/// not that. Flutter's `SnackBar` constructor does:
///
/// ```dart
/// persist = persist ?? action != null;
/// ```
///
/// and `ScaffoldMessengerState.build`'s dismissal timer does:
///
/// ```dart
/// if (snackBar.persist) { return; }   // fires on time, does nothing
/// ```
///
/// So **any** actionable snackbar is immortal unless `persist: false` is passed
/// explicitly. The first test below is the one that would have caught the
/// original defect, and it fails if anyone ever drops that argument.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/presentation/widgets/scoped_snack_bar.dart';

import 'p3_screens_test.dart' show wrap;

/// A screen that raises a scoped snackbar and can push another route over
/// itself — the exact shape `correctTransactionCategory` has in production.
class _Raiser extends StatelessWidget {
  final VoidCallback? onUndo;

  const _Raiser({this.onUndo});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: <Widget>[
        ElevatedButton(
          key: const Key('raise'),
          onPressed: () => showScopedSnackBar(
            context: context,
            message: 'Updated 3 transactions from QANDA COFFEE',
            actionLabel: onUndo == null ? null : 'Undo',
            onAction: onUndo,
            duration: kScopedSnackBarDuration,
          ),
          child: const Text('raise'),
        ),
        ElevatedButton(
          key: const Key('push'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: Center(child: Text('another screen'))),
            ),
          ),
          child: const Text('push'),
        ),
      ],
    ),
  );
}

void main() {
  testWidgets('**the regression** — an actionable snackbar auto-dismisses. '
      'Before KHA-115 it did not, because SnackBar defaults persist to '
      '`action != null`', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(_Raiser(onUndo: () {})));
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // entry animation

    expect(
      find.text('Updated 3 transactions from QANDA COFFEE'),
      findsOneWidget,
    );
    expect(find.text('Undo'), findsOneWidget);

    // Wait out the duration plus the exit animation.
    await tester.pump(kScopedSnackBarDuration);
    await tester.pumpAndSettle();

    expect(
      find.text('Updated 3 transactions from QANDA COFFEE'),
      findsNothing,
      reason:
          'the bar must dismiss itself. This is the assertion that fails if '
          '`persist: false` is ever dropped from showScopedSnackBar',
    );
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('a snackbar with NO action also dismisses — the control case, so '
      'the test above is known to be about the action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(const _Raiser()));
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Updated 3 transactions'), findsOneWidget);

    await tester.pump(kScopedSnackBarDuration);
    await tester.pumpAndSettle();
    expect(find.textContaining('Updated 3 transactions'), findsNothing);
  });

  testWidgets('**the second harm** — pushing another route dismisses the bar, '
      'so a stale Undo cannot float over an unrelated screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(_Raiser(onUndo: () {})));
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('push')));
    await tester.pumpAndSettle();

    expect(find.text('another screen'), findsOneWidget);
    expect(
      find.text('Undo'),
      findsNothing,
      reason:
          'QA watched this bar survive four route changes; the Undo it carried '
          'rewrites the ledger and has no business being reachable from a '
          'screen that knows nothing about the correction',
    );
  });

  testWidgets('and even if it were still reachable, the Undo is INERT once its '
      'own route is no longer current', (WidgetTester tester) async {
    // Belt and braces, deliberately. Dismissal is the behaviour a user sees;
    // this is the *guarantee*, and it has to hold for navigation shapes the
    // dismissal does not cover.
    //
    // A dialog is exactly such a shape, and a realistic one: a `DialogRoute` is
    // a `PopupRoute`, and `MaterialRouteTransitionMixin.canTransitionTo`
    // returns false for it — so the route underneath never runs its
    // `secondaryAnimation` and the bar genuinely survives, while
    // `route.isCurrent` is nonetheless false.
    int undos = 0;
    late BuildContext raiserContext;

    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (BuildContext context) {
            raiserContext = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );

    showScopedSnackBar(
      context: raiserContext,
      message: 'Updated 3 transactions',
      actionLabel: 'Undo',
      onAction: () => undos++,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    unawaited(
      showDialog<void>(
        context: raiserContext,
        builder: (_) => const AlertDialog(content: Text('a dialog')),
      ),
    );
    await tester.pumpAndSettle();

    // Still there — which is the premise of this test, not an oversight.
    expect(find.text('Undo'), findsOneWidget);

    // Invoked the way a stray tap would, bypassing the modal barrier that
    // would otherwise swallow the gesture in a test.
    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pump();

    expect(
      undos,
      0,
      reason:
          'an Undo that outlives its context must do nothing rather than '
          'revert work the user is no longer looking at',
    );
  });

  testWidgets('going BACK also dismisses the bar — a pop does not move '
      'secondaryAnimation, so it is a separate path', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (BuildContext context) => Scaffold(
            body: ElevatedButton(
              key: const Key('go'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => _Raiser(onUndo: () {})),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('go')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Undo'), findsOneWidget);

    // `tester.pageBack()` looks for a back *button*, and `_Raiser` has no
    // AppBar to put one in. Popping the navigator directly is the same event.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('the Undo DOES fire while its own route is still current', (
    WidgetTester tester,
  ) async {
    // The inverse of the test above — without it, "the action never runs"
    // would pass just as happily.
    int undos = 0;
    await tester.pumpWidget(wrap(_Raiser(onUndo: () => undos++)));
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Undo'));
    await tester.pump();

    expect(undos, 1);
  });

  testWidgets('a second correction replaces the first bar rather than queueing '
      'behind it', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(_Raiser(onUndo: () {})));
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pumpAndSettle();

    // One bar, not two stacked. Queueing would make the user wait out both.
    expect(find.text('Undo'), findsOneWidget);

    await tester.pump(kScopedSnackBarDuration);
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
  });
}

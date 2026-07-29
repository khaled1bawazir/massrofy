/// **KHA-115 — the one place this app is allowed to show a SnackBar with an
/// action, and the reason that rule exists.**
///
/// ---
///
/// ## The defect, and its real root cause
///
/// QA's KHA-112 emulator walk found the category-correction snackbar sitting on
/// screen for **~9 minutes across four route changes**, carrying a live *Undo*
/// that silently reverted a three-row correction *and* deleted the learned rule
/// behind it when it was tapped by accident. The issue suggested the entry
/// animation might never be reporting `AnimationStatus.completed`, which is one
/// way `ScaffoldMessenger` can fail to arm its dismissal timer. It is not what
/// happened here.
///
/// The actual cause is a single line in the Flutter SDK
/// (`material/snack_bar.dart`, `SnackBar`'s constructor):
///
/// ```dart
/// persist = persist ?? action != null;
/// ```
///
/// and its consequence in `material/scaffold.dart`
/// (`ScaffoldMessengerState.build`):
///
/// ```dart
/// _snackBarTimer = Timer(snackBar.duration, () {
///   if (snackBar.persist) {
///     return;              // <-- the bar is never hidden
///   }
///   hideCurrentSnackBar(reason: SnackBarClosedReason.timeout);
/// });
/// ```
///
/// **Any `SnackBar` carrying a `SnackBarAction` defaults to `persist: true`,
/// i.e. it is immortal until the action or the close icon is tapped.** The
/// timer *did* fire, on time, and deliberately did nothing. That is why the
/// obvious remedy — passing an explicit `duration` — would not have fixed it on
/// its own, and it is why this file passes `persist: false` explicitly rather
/// than relying on any default.
///
/// (Historically this behaviour was gated on `accessibleNavigation`, i.e. it
/// only applied under TalkBack; it is now unconditional. The app's pubspec
/// pins `flutter: ">=3.44.0"` because `SnackBar.persist` has to exist for this
/// file to compile — see the note there.)
///
/// ## The second half: an Undo must not outlive the screen that offered it
///
/// `ScaffoldMessenger` lives **above** the `Navigator` (`MaterialApp` inserts
/// it there), so a snackbar deliberately survives pushes and pops. That is the
/// right default for "Saved", and the wrong one for an action that rewrites the
/// ledger: the offer to undo a correction made on the review inbox is
/// meaningless — and dangerous — while the user is looking at the category
/// manager.
///
/// So [showScopedSnackBar] binds the bar to the route that raised it:
///
///  1. it is **hidden** as soon as another route is pushed over that route, and
///  2. its action is **inert** if it is somehow reached while the owning route
///     is not the current one.
///
/// Two independent mechanisms on purpose. (1) is the behaviour the user sees;
/// (2) is the guarantee, and it holds even if (1) is defeated by some future
/// navigation shape nobody has thought of yet. In a money app the cheap
/// belt-and-braces is worth having.
///
/// ## Flutter notes for a newcomer
///
/// - `ModalRoute.of(context)` is the route the calling widget is inside.
///   `route.isCurrent` is true only while it is the topmost route.
/// - `route.secondaryAnimation` is the animation that runs when **another**
///   route is pushed *over* this one (as opposed to `route.animation`, which
///   runs when this route itself enters). Watching its status is the precise
///   way to hear "something has just covered me".
/// - `ScaffoldFeatureController.closed` is a `Future` that completes when the
///   bar has finished its exit animation, whatever caused it.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

/// How long an actionable snackbar stays up.
///
/// Material's default is 4 seconds, which is tuned for a bar with no action.
/// This one asks the user to notice an outcome *and* decide whether to undo it,
/// so it gets a little longer — still short enough that it cannot be mistaken
/// for a permanent part of the screen, which is exactly what went wrong in
/// KHA-115.
const Duration kScopedSnackBarDuration = Duration(seconds: 6);

/// Shows a snackbar that **always auto-dismisses** and whose optional action is
/// scoped to the route that raised it.
///
/// [message] is the body. [actionLabel] and [onAction] must be supplied
/// together or not at all; supplying neither produces a plain informational
/// bar.
///
/// Returns the controller so a caller can await [ScaffoldFeatureController.closed]
/// (a widget test does exactly that). Callers that do not care may ignore it.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showScopedSnackBar({
  required BuildContext context,
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = kScopedSnackBarDuration,
}) {
  assert(
    (actionLabel == null) == (onAction == null),
    'an action needs both a label and a callback, or neither',
  );

  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  // The route that "owns" this bar. Null when the caller is not inside a
  // route at all (only really possible in a test harness), in which case there
  // is nothing to scope to and the bar behaves as an ordinary timed snackbar.
  final ModalRoute<Object?>? owner = ModalRoute.of(context);

  // One bar at a time. Without this, a rapid second correction stacks behind
  // the first and the user waits out both.
  messenger.hideCurrentSnackBar();

  final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> controller =
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: duration,
          // **The KHA-115 fix.** Never omit this on a bar that has an action:
          // the SDK default is `action != null`, i.e. "stay forever".
          persist: false,
          action: actionLabel == null || onAction == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  onPressed: () {
                    // Guarantee (2). A stale Undo does nothing rather than
                    // rewriting the ledger from under a screen that knows
                    // nothing about it.
                    if (owner == null || owner.isCurrent) {
                      onAction();
                    }
                  },
                ),
        ),
      );

  // Tracked by us rather than read from the controller, because
  // `ScaffoldFeatureController.close()` asserts that its bar is still the
  // messenger's current one — calling it after something else has taken over
  // is a debug-mode crash. `ScaffoldMessengerState.hideCurrentSnackBar()`
  // carries no such assertion, so that is what [dismiss] uses, and this flag
  // keeps us from calling it for a bar that has already gone.
  bool alreadyClosed = false;
  controller.closed.whenComplete(() => alreadyClosed = true);

  void dismiss() {
    if (alreadyClosed) {
      return;
    }
    alreadyClosed = true;
    messenger.hideCurrentSnackBar();
  }

  final Animation<double>? covered = owner?.secondaryAnimation;
  if (covered != null) {
    void onCovered(AnimationStatus status) {
      // `forward` is "a route is being pushed over me"; `completed` is "one
      // already is". `reverse`/`dismissed` are the *uncovering* directions and
      // must be ignored — this bar is very often shown while a modal sheet
      // (the category picker) is still animating away, and reacting to that
      // would dismiss the bar before it was ever readable.
      if (status == AnimationStatus.forward ||
          status == AnimationStatus.completed) {
        dismiss();
      }
    }

    covered.addStatusListener(onCovered);
    controller.closed.whenComplete(
      () => covered.removeStatusListener(onCovered),
    );
  }

  // The other way a route stops being the one on screen: the user goes back.
  // `secondaryAnimation` does not move for a pop (that is `animation`
  // reversing), so this is a genuinely separate case rather than belt and
  // braces. `dismiss` is idempotent, so the two paths cannot fight.
  //
  // The closure is retained until the route is popped, which for the app's
  // root route is "never" — a few bytes, and the alternative (a listener that
  // has to be unregistered) costs more than it saves.
  unawaited(owner?.popped.then((Object? _) => dismiss()));

  return controller;
}

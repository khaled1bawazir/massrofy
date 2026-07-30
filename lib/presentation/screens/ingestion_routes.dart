/// **The construction site for KHA-133's re-check screen.**
///
/// Same shape and same reason as `ledger_routes.dart` and
/// `categorization_routes.dart`, which both quote the lesson this file exists
/// to honour:
///
/// > *"'unreachable today' is a claim about **navigation**, not about code — it
/// > expires the moment someone adds a route, silently."*
/// > *"verify a reachability claim by grepping for the construction site, never
/// > from the fact that the widget exists in the tree."*
///
/// So: a reachability question about [RecheckBanksScreen] is answered by
/// grepping for [openRecheckBanks], and by nothing else. It is called from the
/// More menu's App section (`app_shell.dart`).
///
/// ## Host, not screen
///
/// [RecheckBanksHost] is the only place a provider is read. The screen itself
/// is a pure render widget over values — see its header for why that is worth
/// the extra class.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/rescan_providers.dart';
import 'recheck_banks_screen.dart';

/// Opens KHA-133's "check my banks again" action.
Future<void> openRecheckBanks(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const RecheckBanksHost()));

/// ## Two consequences of the controller outliving this route, both deliberate
///
/// `rescanControllerProvider` is app-scoped, not screen-scoped, so:
///
///  1. **Navigating away does not cancel a run.** The walk finishes and its
///     result is waiting when the user comes back. That is the right trade for
///     an operation whose whole purpose is recovering data — abandoning it
///     half-done would leave *some* of the user's July recovered and give them
///     no way to tell which. (`RescanCoordinator.recheckAllBanks` does accept a
///     `shouldContinue` predicate for the case where cancelling is wanted;
///     US-A6's screen is where that will earn its keep.)
///  2. **A finished result survives a lock/unlock cycle.** It is a true record
///     of a run that did happen, and it names the window it covered, so it
///     cannot be misread as live — but it is worth knowing it is not cleared.
class RecheckBanksHost extends ConsumerWidget {
  const RecheckBanksHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RescanState state = ref.watch(rescanControllerProvider);

    return RecheckBanksScreen(
      state: state,
      // Disabled while a walk is in flight. The controller drops a re-entrant
      // call anyway (see `RescanController.run`), but a button that visibly
      // does nothing when tapped invites a user to tap it repeatedly and
      // conclude the app is broken.
      onRecheck: state is RescanRunning
          ? null
          : () => ref.read(rescanControllerProvider.notifier).run(),
    );
  }
}

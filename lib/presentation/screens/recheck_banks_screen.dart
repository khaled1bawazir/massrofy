/// **"Check my banks again" — KHA-133's recovery action.**
///
/// Spec: `docs/architecture.md` ADR-006, the `KHA-133 decision` subsection,
/// item **(E)** ("the result is reported to the user"). Mechanism:
/// `lib/features/ingestion/rescan_coordinator.dart`.
///
/// ---
///
/// ## Why this is a plain screen and not the Banks & Senders panel
///
/// US-A6 (KHA-129) designs a full self-service screen — per-bank sender lists,
/// a parser-health panel, "unrecognised senders", the lot — and it is already
/// approved and waiting on its own dispatch. This is **not** that screen, and
/// deliberately does not borrow its layout.
///
/// The human's decision was to ship the *recovery* ahead of the *surface*,
/// because the mechanism is a genuine subset of what US-A6 must build anyway
/// (AC-A6.10's "check again", pointed at banks that were configured with wrong
/// patterns rather than at a newly linked sender). So this screen hosts one
/// action and explains it honestly, and US-A6 later dresses the same
/// coordinator in its real design. Nothing here is scaffolding to be thrown
/// away; it is one row in the More menu that will keep working.
///
/// ## A pure render widget over values
///
/// Consistent with every other screen in this app (`banks_screen.dart`,
/// `transaction_detail_screen.dart`): no provider is read here. The
/// `RecheckBanksHost` in `ingestion_routes.dart` watches state and hands this
/// widget values plus callbacks. That is what keeps the widget test a real
/// render test — every state below can be built directly, with no fake
/// database — and what keeps ADR-005's guarantee checkable, since a screen
/// that reads nothing cannot read something the lock has not unlocked.
///
/// ## Every state design.md §3.4 asks for
///
/// | State | Rendered as |
/// |---|---|
/// | idle | explanation + enabled button |
/// | loading (running) | progress indicator, button disabled |
/// | result — found something | counts, per item (E) |
/// | result — empty | "Nothing new found", with the window named |
/// | locked / session expired | ADR-005 copy, no button |
/// | unauthorized (SMS permission revoked) | AC-A1.3 copy, no button |
/// | error | honest failure copy + retry |
library;

import 'package:flutter/material.dart';

import '../../core/time/clock.dart';
import '../../features/ingestion/rescan_coordinator.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/rescan_providers.dart';
import '../theme/app_colors.dart';

class RecheckBanksScreen extends StatelessWidget {
  /// What to render. See [RescanState] for why the locked and
  /// permission-revoked cases are states rather than errors.
  final RescanState state;

  /// Starts a re-check. **One callback for all three buttons** — the primary
  /// action, "Check again" on a result, and "Check again" after an error are
  /// the same operation, and re-running is safe by design (this is the whole
  /// point of the idempotence property).
  ///
  /// Null when the action is not available at all, which is how "no button on
  /// the locked screen" is expressed as a *type* rather than as a condition
  /// each card has to remember to check.
  final VoidCallback? onRecheck;

  const RecheckBanksScreen({
    required this.state,
    required this.onRecheck,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(l10n.recheckBanksTitle)),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 32),
        children: <Widget>[
          const _Explanation(),
          const SizedBox(height: 16),
          // The exhaustive switch is the point: `RescanState` is sealed, so a
          // state added later will not compile until this screen decides what
          // to show for it. That is how "every state is handled" stays true
          // after the next person edits it, rather than being true only today.
          switch (state) {
            RescanIdle() => _ActionButton(onPressed: onRecheck),
            RescanRunning() => const _RunningCard(),
            RescanSucceeded(:final RescanResult result) => _ResultCard(
              result: result,
              onRecheckAgain: onRecheck,
            ),
            RescanFailed(:final RescanFailureReason reason) => _FailureCard(
              reason: reason,
              // Only an unexpected error is worth retrying. Locked and
              // permission-revoked need the user to do something outside this
              // screen first, and a button that cannot succeed is worse than
              // no button.
              onRetry: reason == RescanFailureReason.unexpectedError
                  ? onRecheck
                  : null,
            ),
          },
        ],
      ),
    );
  }
}

/// What the action does, before it is pressed.
///
/// The wording carries two facts the user cannot otherwise know, and both are
/// required rather than decorative:
///
///  - **what it covers** — item (C)'s window is the ground the original import
///    covered, *not* full history. "Nobody should read 'check again' as 'full
///    history'" (ADR-006). Promising more than the mechanism does would make
///    an empty result look like a bug.
///  - **that it cannot duplicate anything** — the single most likely worry
///    about a button labelled "scan my messages again", and it is answerable
///    with a flat "no", so it is answered up front instead of in a FAQ nobody
///    reads.
class _Explanation extends StatelessWidget {
  const _Explanation();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.recheckBanksIntroTitle,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.recheckBanksIntroBody,
              style: text.bodySmall?.copyWith(color: AppColors.ink500),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.recheckBanksSafeNote,
              style: text.bodySmall?.copyWith(color: AppColors.ink500),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _ActionButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return FilledButton.icon(
      key: const Key('recheckBanks.action'),
      onPressed: onPressed,
      icon: const Icon(Icons.refresh),
      label: Text(l10n.recheckBanksAction),
    );
  }
}

/// The loading state.
///
/// An indeterminate bar, not a percentage: the coordinator persists no cursor
/// and reports no progress (item (B) — it is a transient operation), so any
/// percentage this screen showed would be invented. A month of messages takes
/// seconds; a fake progress bar would be a worse trade than an honest spinner.
class _RunningCard extends StatelessWidget {
  const _RunningCard();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Card(
      key: const Key('recheckBanks.running'),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(l10n.recheckBanksRunning),
          ],
        ),
      ),
    );
  }
}

/// Item (E): *"a re-scan makes weeks-old transactions appear at once, and
/// retroactive numbers with no stated cause are worse than no numbers."*
///
/// So this card always states three things — what was covered, what was found,
/// and where the found things went — even in the empty case.
class _ResultCard extends StatelessWidget {
  final RescanResult result;

  /// Null only if the action became unavailable between the run finishing and
  /// this frame — e.g. the app locked while the result was on screen.
  final VoidCallback? onRecheckAgain;

  const _ResultCard({required this.result, required this.onRecheckAgain});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    // Localised, and shifted into Riyadh wall-clock time first: a Riyadh
    // calendar month begins at 21:00 UTC on the last day of the previous
    // month, so naming the raw UTC instant would print "30 June" for a window
    // that starts on 1 July (`formatPeriodMonthLabel` documents the same trap).
    final String since = MaterialLocalizations.of(
      context,
    ).formatMediumDate(RiyadhCalendar.toRiyadhWallClock(result.windowFromUtc));

    return Card(
      key: const Key('recheckBanks.result'),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  result.foundNothingNew
                      ? Icons.check_circle_outline
                      : Icons.auto_awesome_outlined,
                  color: AppColors.ink500,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.foundNothingNew
                        ? l10n.recheckBanksNothingNew
                        : l10n.recheckBanksFound(result.newTransactions),
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // "How many messages were re-examined", asked for explicitly.
            // `counts.examined` is the number of bank messages actually
            // re-read — not `messagesInWindow`, which includes the ones this
            // run only ever saw the sender of.
            Text(
              l10n.recheckBanksExamined(result.counts.examined, since),
              style: text.bodySmall?.copyWith(color: AppColors.ink500),
            ),

            // Only shown when non-zero. A recovered message from a bank whose
            // rules cannot yet parse it lands in Needs Review — which is a
            // success for this feature (the message is no longer invisible),
            // but only if the user is told where it went.
            if (result.newReviewItems > 0) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                l10n.recheckBanksNeedReview(result.newReviewItems),
                style: text.bodySmall?.copyWith(color: AppColors.ink500),
              ),
            ],

            // Item (E) again, in the direction that is easy to omit: a run
            // that hit errors examined less than it claims to have, and
            // hiding that would make an incomplete recovery look complete.
            if (result.counts.failedWithError > 0) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                l10n.recheckBanksSomeFailed(result.counts.failedWithError),
                style: text.bodySmall?.copyWith(color: AppColors.warningText),
              ),
            ],

            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('recheckBanks.again'),
              onPressed: onRecheckAgain,
              child: Text(l10n.recheckBanksAgain),
            ),
          ],
        ),
      ),
    );
  }
}

/// The three ways this can not produce a result. Two of them are ordinary
/// states rather than faults, and the copy says so.
class _FailureCard extends StatelessWidget {
  final RescanFailureReason reason;

  /// Null for [RescanFailureReason.locked] and
  /// [RescanFailureReason.permissionDenied]: retrying changes nothing until
  /// the user unlocks the app or grants the permission, and a retry button
  /// that cannot work is worse than none.
  final VoidCallback? onRetry;

  const _FailureCard({required this.reason, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    final String body = switch (reason) {
      RescanFailureReason.locked => l10n.recheckBanksLocked,
      RescanFailureReason.permissionDenied => l10n.recheckBanksNoPermission,
      RescanFailureReason.unexpectedError => l10n.recheckBanksError,
    };

    return Card(
      key: const Key('recheckBanks.failure'),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.info_outline, color: AppColors.ink500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    body,
                    style: text.bodySmall?.copyWith(color: AppColors.ink500),
                  ),
                ),
              ],
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('recheckBanks.retry'),
                onPressed: onRetry,
                child: Text(l10n.recheckBanksAgain),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

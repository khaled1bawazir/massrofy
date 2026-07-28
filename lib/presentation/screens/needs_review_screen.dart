import 'package:flutter/material.dart';

import '../../features/ingestion/duplicate_policy.dart';
import '../../features/ingestion/review_queue.dart';
import '../../features/parsing/parse_outcome.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';

/// **S-18 — Needs Review Inbox.** Mockup: `docs/mockups/needs-review.html`.
///
/// ## Two tabs, never conflated — and that is a design decision with teeth
///
/// design.md S-18 specifies *"Two tabs — Unparsed SMS vs. Low-confidence —
/// never conflated"*, and the reason is that the two need different things
/// from the user:
///
///  - **Not understood** — the app is missing *facts*. The user reads the
///    original message and supplies what the parser could not extract
///    (AC-A4.2). Or says "not a transaction" and it leaves the queue.
///  - **Low confidence** — the app has the facts and needs a *judgement*:
///    "are these two charges the same thing?" (ADR-017 D2/D3), "is this
///    transfer to your own account?" (AC-B11.2).
///
/// Merging them would present a message with no amount next to a transaction
/// with a perfectly good amount, under one heading, and make both harder to
/// act on.
///
/// ## The empty state is deliberately reassuring, not amber
///
/// "Nothing needs review right now" with a success-toned check. This queue
/// existing at all is the product admitting it is imperfect; an empty one is
/// good news and should look like it. An amber "0 items" would read as a
/// warning about nothing.
///
/// ## Scope note
///
/// The S-19 "complete the details" form and the duplicate-merge action are
/// wired as callbacks here, not implemented. They write a full `Transaction`,
/// which needs the P3 domain model (instrument resolution, category
/// assignment). What P2 owns and delivers is the guarantee that **the message
/// is in this list at all** — the NFR-A7 half — plus the dismissal path.
class NeedsReviewScreen extends StatelessWidget {
  final List<ReviewQueueItem> unparsed;
  final List<FlaggedTransactionItem> flagged;

  /// Opens S-19 for an unparsed message (AC-A4.2).
  final void Function(ReviewQueueItem item) onFillInDetails;

  /// US-A4's dismissal. Marks the row dismissed — never deletes it; see
  /// `review_queue.dart` for why.
  final void Function(ReviewQueueItem item) onNotATransaction;

  /// Opens a flagged transaction for the user's judgement.
  final void Function(FlaggedTransactionItem item) onOpenFlagged;

  const NeedsReviewScreen({
    required this.unparsed,
    required this.flagged,
    required this.onFillInDetails,
    required this.onNotATransaction,
    required this.onOpenFlagged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // `DefaultTabController` supplies the controller the TabBar and TabBarView
    // share. Under Arabic RTL, Flutter mirrors tab order automatically because
    // the whole subtree inherits `Directionality` from the app locale — which
    // is why nothing here hard-codes an order (design.md §3.1).
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: Text(l10n.needsReviewTitle),
          bottom: TabBar(
            tabs: <Widget>[
              Tab(text: l10n.needsReviewTabUnparsed(unparsed.length)),
              Tab(text: l10n.needsReviewTabLowConfidence(flagged.length)),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            if (unparsed.isEmpty)
              const _EmptyState()
            else
              ListView.builder(
                padding: const EdgeInsetsDirectional.all(16),
                itemCount: unparsed.length,
                itemBuilder: (BuildContext context, int index) => _UnparsedCard(
                  item: unparsed[index],
                  onFillInDetails: onFillInDetails,
                  onNotATransaction: onNotATransaction,
                ),
              ),
            if (flagged.isEmpty)
              const _EmptyState()
            else
              ListView.builder(
                padding: const EdgeInsetsDirectional.all(16),
                itemCount: flagged.length,
                itemBuilder: (BuildContext context, int index) =>
                    _FlaggedRow(item: flagged[index], onOpen: onOpenFlagged),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.task_alt, size: 44, color: AppColors.success),
            const SizedBox(height: 12),
            Text(
              l10n.needsReviewEmpty,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.needsReviewEmptyBody,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.ink500),
            ),
          ],
        ),
      ),
    );
  }
}

/// One unparsed message: the original (sanitised) text, why it failed, and
/// the two actions.
class _UnparsedCard extends StatelessWidget {
  final ReviewQueueItem item;
  final void Function(ReviewQueueItem) onFillInDetails;
  final void Function(ReviewQueueItem) onNotATransaction;

  const _UnparsedCard({
    required this.item,
    required this.onFillInDetails,
    required this.onNotATransaction,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 12),
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // AC-A4.1: the raw text is shown so the user can see exactly what
          // the parser saw. It is safe to render because it was redacted at
          // the ingestion boundary (ADR-013), not here.
          Text(item.sanitizedBody, style: text.bodyMedium),
          const SizedBox(height: 8),
          Text(
            l10n.needsReviewReceivedFrom(
              // A short, locale-independent rendering. Full date/time
              // formatting arrives with the reporting work in P5; using it
              // here would pull a formatting dependency into P2 for one line.
              item.receivedAt.toLocal().toIso8601String().substring(0, 16),
              item.sender,
            ),
            style: text.bodySmall?.copyWith(color: AppColors.ink500),
          ),
          if (item.unparsedReason != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              _reasonText(l10n, item.unparsedReason!),
              style: text.bodySmall?.copyWith(color: AppColors.ink700),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  onPressed: () => onFillInDetails(item),
                  child: Text(l10n.needsReviewFillInDetails),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onNotATransaction(item),
                  child: Text(l10n.needsReviewNotATransaction),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Turns an `UnparsedReason` constant into plain language.
  ///
  /// The two cases genuinely differ for the user: "did not match any known
  /// format" means the bank changed something and the app needs a rule update
  /// (risk R-4); "some details were missing" means this particular message
  /// was unusually terse and one entry will fix it.
  String _reasonText(AppLocalizations l10n, String reason) => switch (reason) {
    UnparsedReason.noRuleMatched => l10n.needsReviewReasonNoRule,
    _ => l10n.needsReviewReasonMissingField,
  };
}

/// One flagged transaction — the "low confidence" tab.
class _FlaggedRow extends StatelessWidget {
  final FlaggedTransactionItem item;
  final void Function(FlaggedTransactionItem) onOpen;

  const _FlaggedRow({required this.item, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return ListTile(
      onTap: () => onOpen(item),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.help_outline, color: AppColors.ink500),
      title: Text(item.merchantRawText ?? '—', style: text.bodyLarge),
      subtitle:
          item.reviewReason == ReviewReason.possibleDuplicate ||
              item.reviewReason == ReviewReason.possibleAuthorisationPosting
          // NFR-U4: the flag is an icon **and** a word, never a colour alone,
          // so it survives greyscale and colour-vision differences.
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.flag_outlined, size: 14),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    l10n.needsReviewPossibleDuplicate,
                    style: text.bodySmall,
                  ),
                ),
              ],
            )
          : null,
      // The amount is rendered from the exact decimal string, never from a
      // parsed float (ADR-002/NFR-A4).
      trailing: Text(
        '${item.amount} ${item.currencyCode}',
        style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

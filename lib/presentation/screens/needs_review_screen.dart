import 'package:flutter/material.dart';

import '../../features/ingestion/duplicate_policy.dart';
import '../../features/ingestion/review_queue.dart';
import '../../features/ledger/internal_transfer.dart';
import '../../features/ledger/ledger_mapping.dart';
import '../../features/parsing/parse_outcome.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';

/// **S-18 — Needs Review Inbox.** Mockup: `docs/mockups/needs-review.html`.
///
/// ## Three tabs now, and the reason is the same one that gave us two
///
/// design.md S-18 specifies *"Two tabs — Unparsed SMS vs. Low-confidence —
/// never conflated"*, because the two ask the user for different things. P3b-2
/// adds a third for the same reason rather than in spite of it: S-18's own
/// inventory says this screen *"hosts possible-duplicate (AC-A5.2) **and
/// ambiguous-transfer (AC-B11.2)** review cards"*, and those two are not the
/// same question.
///
///  - **Not understood** — the app is missing *facts*. The user reads the
///    original message and supplies what the parser could not extract
///    (AC-A4.2), or says "not a transaction" and it leaves the queue.
///  - **Low confidence** — the app has the facts and needs a *judgement about
///    its own data*: "are these two charges the same thing?" (ADR-017 D2/D3).
///  - **Transfers** — the app needs a fact about the world it can never
///    observe: "is the account this money went to yours?" (AC-B11.2). No
///    parser improvement could ever answer it, which is exactly why it is the
///    user's to answer and why it gets its own place rather than a footnote.
///
/// ## The data-problem banner sits above all three (KHA-74)
///
/// A transaction whose stored amount cannot be read is missing from **every**
/// total, not from one tab's worth of them, so it is announced above the tabs
/// where it cannot be missed by someone browsing a different tab. Before
/// P3b-2 such a row was dropped in silence and the user's monthly figure was
/// simply, invisibly, too small — see `ledger_mapping.dart`.
///
/// ## The empty state is deliberately reassuring, not amber
///
/// "Nothing needs review right now" with a success-toned check. This queue
/// existing at all is the product admitting it is imperfect; an empty one is
/// good news and should look like it. An amber "0 items" would read as a
/// warning about nothing.
class NeedsReviewScreen extends StatelessWidget {
  final List<ReviewQueueItem> unparsed;
  final List<FlaggedTransactionItem> flagged;

  /// AC-B11.2's transfers (KHA-78 candidates and KHA-80 unpairables).
  final List<TransferReviewItem> transfers;

  /// KHA-74. Empty in every healthy install.
  final List<UnreadableTransaction> unreadable;

  /// Opens S-19 for an unparsed message (AC-A4.2).
  final void Function(ReviewQueueItem item) onFillInDetails;

  /// US-A4's dismissal. Marks the row dismissed — never deletes it; see
  /// `review_queue.dart` for why.
  final void Function(ReviewQueueItem item) onNotATransaction;

  /// Opens a flagged transaction for the user's judgement.
  final void Function(FlaggedTransactionItem item) onOpenFlagged;

  /// **ADR-017 D2 / KHA-64.** The explicit user confirmation that a flagged
  /// pair is one transaction. Null when the flag carries no counterpart to
  /// merge with, in which case no merge button is offered at all — the action
  /// is never presented without a target.
  final void Function(FlaggedTransactionItem item)? onMergeDuplicate;

  /// AC-A5.3 — "these really are two separate purchases". Clears the flag and
  /// leaves both rows in every total.
  final void Function(FlaggedTransactionItem item)? onKeepBothDuplicates;

  /// **KHA-78.** Records the user's verdict on a transfer.
  final void Function(TransferReviewItem item, bool isOwnAccount)?
  onTransferVerdict;

  const NeedsReviewScreen({
    required this.unparsed,
    required this.flagged,
    required this.onFillInDetails,
    required this.onNotATransaction,
    required this.onOpenFlagged,
    this.transfers = const <TransferReviewItem>[],
    this.unreadable = const <UnreadableTransaction>[],
    this.onMergeDuplicate,
    this.onKeepBothDuplicates,
    this.onTransferVerdict,
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
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: Text(l10n.needsReviewTitle),
          bottom: TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: l10n.needsReviewTabUnparsed(unparsed.length)),
              Tab(text: l10n.needsReviewTabLowConfidence(flagged.length)),
              Tab(text: l10n.needsReviewTabTransfers(transfers.length)),
            ],
          ),
        ),
        body: Column(
          children: <Widget>[
            if (unreadable.isNotEmpty) _DataProblemBanner(items: unreadable),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _TabList<ReviewQueueItem>(
                    items: unparsed,
                    builder: (ReviewQueueItem item) => _UnparsedCard(
                      item: item,
                      onFillInDetails: onFillInDetails,
                      onNotATransaction: onNotATransaction,
                    ),
                  ),
                  _TabList<FlaggedTransactionItem>(
                    items: flagged,
                    builder: (FlaggedTransactionItem item) => _FlaggedCard(
                      item: item,
                      onOpen: onOpenFlagged,
                      onMerge: onMergeDuplicate,
                      onKeepBoth: onKeepBothDuplicates,
                    ),
                  ),
                  _TabList<TransferReviewItem>(
                    items: transfers,
                    builder: (TransferReviewItem item) =>
                        _TransferCard(item: item, onVerdict: onTransferVerdict),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One tab's body: the empty state, or the list. Extracted because all three
/// tabs share it exactly, and three copies of an `if (isEmpty)` is three
/// chances for one of them to render a blank screen instead.
class _TabList<T> extends StatelessWidget {
  final List<T> items;
  final Widget Function(T item) builder;

  const _TabList({required this.items, required this.builder});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyState();
    }
    return ListView.builder(
      padding: const EdgeInsetsDirectional.all(16),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) => builder(items[index]),
    );
  }
}

/// **KHA-74** — the ledger holds a row this build cannot read.
///
/// Rendered above the tabs, in the error tone, because unlike everything else
/// on this screen it is not a decision the user can make: it is a statement
/// that a number they are being shown elsewhere is incomplete. It is the one
/// item here the app is apologising for rather than asking about.
class _DataProblemBanner extends StatelessWidget {
  final List<UnreadableTransaction> items;

  const _DataProblemBanner({required this.items});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsetsDirectional.all(16),
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // NFR-U4: icon AND words. The severity never travels by colour
              // alone.
              const Icon(
                Icons.report_gmailerrorred_outlined,
                size: 18,
                color: AppColors.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.reviewDataProblemTitle,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.reviewDataProblemCount(items.length),
            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          for (final UnreadableTransaction item in items)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 4),
              child: Text(
                // The row id only. The unreadable value itself is never
                // rendered — NFR-S4 makes no exception for strings that happen
                // to be corrupt, and putting arbitrary stored bytes on screen
                // is how one ends up in a screenshot or an a11y tree.
                l10n.reviewDataProblemBody(item.transactionId),
                style: text.bodySmall?.copyWith(color: AppColors.ink700),
              ),
            ),
        ],
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

    return _ReviewCard(
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

/// One flagged transaction — the "low confidence" tab, which for now means
/// ADR-017's possible duplicates.
///
/// **KHA-64 wires the merge action that P2 shipped as a bare callback.** The
/// copy states what a merge actually does before the user commits to it —
/// *"merging keeps one and files the other under Recently deleted — nothing is
/// destroyed"* — because risk R-8's whole argument is that the user must never
/// be able to lose a real transaction by tapping something. Telling them the
/// operation is reversible is part of making that true in practice rather than
/// only in the database.
class _FlaggedCard extends StatelessWidget {
  final FlaggedTransactionItem item;
  final void Function(FlaggedTransactionItem) onOpen;
  final void Function(FlaggedTransactionItem)? onMerge;
  final void Function(FlaggedTransactionItem)? onKeepBoth;

  const _FlaggedCard({
    required this.item,
    required this.onOpen,
    this.onMerge,
    this.onKeepBoth,
  });

  bool get _isDuplicateFlag =>
      item.reviewReason == ReviewReason.possibleDuplicate ||
      item.reviewReason == ReviewReason.possibleAuthorisationPosting;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    // A merge needs something to merge *with*. Without a counterpart the
    // action is not offered at all, rather than offered and then failing.
    final bool canMerge =
        _isDuplicateFlag &&
        item.possibleDuplicateOfId != null &&
        onMerge != null;

    return _ReviewCard(
      children: <Widget>[
        // Deliberately a `Row` inside an `InkWell`, not a `ListTile`.
        // `ListTile` paints its background and ink splash onto the nearest
        // `Material` ancestor, so putting one inside `_ReviewCard`'s
        // `DecoratedBox` makes both invisible — Flutter asserts on exactly
        // that, and it is a real defect rather than a pedantic one: the row
        // would silently stop showing any tap feedback.
        InkWell(
          key: Key('needsReview.flagged.${item.transactionId}'),
          onTap: () => onOpen(item),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.help_outline, color: AppColors.ink500),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(item.merchantRawText ?? '—', style: text.bodyLarge),
                    if (_isDuplicateFlag) ...<Widget>[
                      const SizedBox(height: 2),
                      // NFR-U4: the flag is an icon **and** a word, never a
                      // colour alone, so it survives greyscale and
                      // colour-vision differences.
                      Row(
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
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // The amount is rendered from the exact decimal string, never
              // from a parsed float (ADR-002/NFR-A4).
              Text(
                '${item.amount} ${item.currencyCode}',
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (canMerge) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            l10n.reviewDuplicateTitle,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.reviewDuplicateBody,
            style: text.bodySmall?.copyWith(color: AppColors.ink700),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  key: Key('needsReview.merge.${item.transactionId}'),
                  onPressed: () => onMerge!(item),
                  child: Text(l10n.reviewDuplicateMerge),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: Key('needsReview.keepBoth.${item.transactionId}'),
                  // AC-A5.3: two genuine identical purchases on the same day.
                  // This choice must be exactly as easy as merging — the app
                  // has no idea which is right, so the UI must not imply it.
                  onPressed: onKeepBoth == null
                      ? null
                      : () => onKeepBoth!(item),
                  child: Text(l10n.reviewDuplicateKeepBoth),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// **AC-B11.2 — "is this account yours?"** KHA-78 (paired candidates) and
/// KHA-80 (unpairable near-matches).
///
/// The heading is a question, not a warning, because the app genuinely does
/// not know and should not imply that the user has done something wrong. The
/// body explains what is currently happening to the figure ("still counted as
/// spend"), which is the fact that makes the decision worth making.
class _TransferCard extends StatelessWidget {
  final TransferReviewItem item;
  final void Function(TransferReviewItem, bool)? onVerdict;

  const _TransferCard({required this.item, this.onVerdict});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return _ReviewCard(
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.swap_horiz, size: 18, color: AppColors.ink500),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.txnBadgeInternalTransferCandidate,
                style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${item.amount} ${item.currencyCode}',
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        if (item.counterpartyName != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(item.counterpartyName!, style: text.bodyMedium),
        ],
        const SizedBox(height: 8),
        Text(
          l10n.reviewTransferCandidateTitle,
          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          _explanation(l10n),
          style: text.bodySmall?.copyWith(color: AppColors.ink700),
        ),
        const SizedBox(height: 10),
        if (item.isPair)
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  key: Key('needsReview.transferConfirm.${item.transactionId}'),
                  onPressed: onVerdict == null
                      ? null
                      : () => onVerdict!(item, true),
                  child: Text(l10n.reviewTransferConfirm),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: Key('needsReview.transferReject.${item.transactionId}'),
                  onPressed: onVerdict == null
                      ? null
                      : () => onVerdict!(item, false),
                  child: Text(l10n.reviewTransferReject),
                ),
              ),
            ],
          )
        else
          // KHA-80: no second leg, so "yes, my own account" is not offered.
          // Excluding one leg while its partner — in another currency, or on
          // an unidentified instrument — carried on counting would produce a
          // Spent-vs-Kept figure that reconciles with nothing. Dismissing is
          // safe: it changes no total, it only stops the app asking again.
          OutlinedButton(
            key: Key('needsReview.transferDismiss.${item.transactionId}'),
            onPressed: onVerdict == null ? null : () => onVerdict!(item, false),
            child: Text(l10n.reviewTransferDismiss),
          ),
      ],
    );
  }

  /// The sentence that explains *this* transfer's situation.
  ///
  /// Three distinct cases, three distinct sentences — KHA-80 asks for exactly
  /// this: *"a cross-currency near-match is a different sentence from 'we
  /// found a partner but cannot prove it'"*.
  String _explanation(AppLocalizations l10n) =>
      switch (item.unpairableReasonKey) {
        TransferReviewReasonKey.crossCurrency =>
          l10n.reviewTransferCrossCurrency,
        TransferReviewReasonKey.unresolvedInstrument =>
          l10n.reviewTransferUnresolvedInstrument,
        _ => l10n.txnInternalTransferCandidateNote,
      };
}

/// The shared card chrome for every item on this screen.
class _ReviewCard extends StatelessWidget {
  final List<Widget> children;

  const _ReviewCard({required this.children});

  @override
  Widget build(BuildContext context) {
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
        children: children,
      ),
    );
  }
}

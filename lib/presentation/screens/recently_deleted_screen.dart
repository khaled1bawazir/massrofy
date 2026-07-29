import 'package:flutter/material.dart';

import '../../features/ledger/ledger_transaction.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/ledger_widgets.dart';

/// **S-44 — Recently Deleted.** KHA-26, US-B8, AC-B8.1, AC-B8.2, AC-B8.3.
///
/// ## Why this screen is the proof that deletion is soft
///
/// AC-B8.1 says a deleted transaction *"moves to a 'Recently deleted' view and
/// is NOT destroyed"*. Without a screen, "soft delete" is an implementation
/// detail the user has no way to observe or benefit from — and a user who
/// believes deletion is permanent behaves differently: they hesitate, or they
/// avoid deleting a wrong row at all and leave their totals wrong instead.
/// The list existing is what makes the reversibility real.
///
/// The intro line states both halves out loud: these are not counted in any
/// total (AC-B6.1), and only Erase Everything removes them for good
/// (AC-B8.3). Saying the second part here matters — it is the one place the
/// user is thinking about deletion, so it is the right place to be clear that
/// this list is *not* what "erase everything" leaves behind.
///
/// ## Merged rows live here too, and say so
///
/// ADR-017 D2's merge soft-deletes the absorbed transaction rather than
/// destroying it (risk R-8). Those rows surface here labelled *"Merged into
/// transaction #N"* instead of as something the user deleted — otherwise a
/// merge would look like data loss in the one screen built to reassure the
/// user that nothing is lost. Restoring such a row undoes the merge, which
/// `TransactionDao.restore` handles by clearing both sides' merge pointers.
class RecentlyDeletedScreen extends StatelessWidget {
  /// Soft-deleted transactions, most recently deleted first.
  final List<LedgerTransaction> deleted;

  /// Transaction id → the survivor it was merged into, for the rows that were
  /// removed by a merge rather than by a delete. Absent for ordinary deletes.
  final Map<int, int> mergedInto;

  final void Function(LedgerTransaction transaction) onRestore;

  const RecentlyDeletedScreen({
    required this.deleted,
    required this.onRestore,
    this.mergedInto = const <int, int>{},
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(l10n.recentlyDeletedTitle)),
      body: deleted.isEmpty
          ? _EmptyState(l10n: l10n)
          : ListView(
              padding: const EdgeInsetsDirectional.all(16),
              children: <Widget>[
                Text(
                  l10n.recentlyDeletedIntro,
                  style: text.bodySmall?.copyWith(color: AppColors.ink500),
                ),
                const SizedBox(height: 16),
                for (final LedgerTransaction transaction in deleted)
                  _DeletedRow(
                    transaction: transaction,
                    mergedIntoId: mergedInto[transaction.id],
                    onRestore: onRestore,
                  ),
              ],
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AppLocalizations l10n;

  const _EmptyState({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.delete_outline, size: 44, color: AppColors.ink500),
            const SizedBox(height: 12),
            Text(
              l10n.recentlyDeletedEmpty,
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.recentlyDeletedEmptyBody,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: AppColors.ink500),
            ),
          ],
        ),
      ),
    );
  }
}

/// The `RecentlyDeletedItem` row from design.md's component library.
class _DeletedRow extends StatelessWidget {
  final LedgerTransaction transaction;
  final int? mergedIntoId;
  final void Function(LedgerTransaction) onRestore;

  const _DeletedRow({
    required this.transaction,
    required this.onRestore,
    this.mergedIntoId,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final DateTime? deletedAt = transaction.deletedAt;

    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 12),
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink100),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  transaction.merchantRawText ??
                      transactionTypeLabel(l10n, transaction.transactionType),
                  style: text.bodyLarge,
                ),
                const SizedBox(height: 2),
                SignedAmountText(
                  amount: transaction.amount,
                  isCredit: transaction.isCredit,
                ),
                const SizedBox(height: 4),
                Text(
                  // AC-B6.4 wants the *when* of a deletion visible. A merged
                  // row says why it left instead, because "deleted" would
                  // misdescribe what the user actually did.
                  mergedIntoId != null
                      ? l10n.recentlyDeletedMergedInto(mergedIntoId!)
                      : l10n.recentlyDeletedOn(
                          deletedAt == null
                              ? '—'
                              : formatShortDateTime(deletedAt),
                        ),
                  style: text.bodySmall?.copyWith(color: AppColors.ink500),
                ),
              ],
            ),
          ),
          TextButton(
            key: Key('recentlyDeleted.restore.${transaction.id}'),
            onPressed: () => onRestore(transaction),
            child: Text(l10n.txnRestoreAction),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../features/ledger/bank_tree.dart';
import '../../features/ledger/instrument_identity.dart';
import '../../features/ledger/ledger_transaction.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/ledger_widgets.dart';

/// **S-23 / S-24 — Account Detail and Card Detail.** Mockup:
/// `docs/mockups/banks.html`. KHA-23, US-B2, US-B3, US-B14, AC-B2.3,
/// AC-B3.1, AC-B14.2, AC-B14.3, AC-B15.2.
///
/// One screen for both kinds, because the only difference between them is the
/// settlement-account row — and giving them two implementations would mean
/// two places for the total to be computed differently.
///
/// ## AC-B2.3, stated precisely
///
/// *"only that instrument's transactions are listed and the total equals the
/// sum of those transactions for the period."* Both halves come from the same
/// [InstrumentSummary]: the figure was computed by `LedgerTotals.spend` over
/// exactly the list this screen renders. There is no second query and no
/// cached column, so the two cannot disagree (NFR-A6).
///
/// ## AC-B14.3 is a *neutral* state, not an error
///
/// A card with no known settlement account shows "Not linked to a settlement
/// account yet" in ordinary body text — no warning colour, no alert icon.
/// Nothing is wrong; the app simply has not seen a repayment message. Styling
/// it as a problem would push the user to "fix" something that is not broken,
/// and the only way to fix it would be to guess.
class InstrumentDetailScreen extends StatelessWidget {
  final InstrumentSummary summary;

  /// This instrument's own transactions, newest first — the same list the
  /// figure in [InstrumentSummary.totals] was computed from.
  final List<LedgerTransaction> transactions;

  /// Opens S-25. US-B3's rename; the change propagates everywhere because
  /// every screen reads the instrument's `friendlyName` from one row
  /// (AC-B3.1), and the next SMS still matches on `refKey` (AC-B3.2).
  final void Function(String? newName) onRename;

  final void Function(LedgerTransaction transaction)? onOpenTransaction;

  const InstrumentDetailScreen({
    required this.summary,
    required this.transactions,
    required this.onRename,
    this.onOpenTransaction,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final bool isCard = summary.instrument.kind == InstrumentKind.card;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: summary.isUnnamed
            ? MaskedIdentifierText(
                maskedIdentifier: summary.instrument.maskedIdentifier,
              )
            : Text(summary.label),
        actions: <Widget>[
          TextButton(
            onPressed: () => _openRenameSheet(context),
            child: Text(l10n.instrumentRenameAction),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.all(16),
        children: <Widget>[
          _IdentityCard(summary: summary, isCard: isCard),
          const SizedBox(height: 16),
          Text(
            l10n.bankTotalThisPeriod,
            style: text.bodySmall?.copyWith(color: AppColors.ink500),
          ),
          const SizedBox(height: 4),
          PeriodTotalsText(totals: summary.totals, style: text.headlineSmall),
          const SizedBox(height: 20),
          Text(
            l10n.instrumentRecentTransactions,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (transactions.isEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 16),
              child: Text(
                l10n.instrumentNoTransactions,
                style: text.bodySmall?.copyWith(color: AppColors.ink500),
              ),
            )
          else
            for (final LedgerTransaction txn in transactions)
              _TransactionRow(
                transaction: txn,
                onTap: onOpenTransaction == null
                    ? null
                    : () => onOpenTransaction!(txn),
              ),
        ],
      ),
    );
  }

  /// **S-25 — Rename sheet.** A modal bottom sheet rather than a dialog: it
  /// is a single text field, and a sheet keeps the instrument visible behind
  /// it so the user can see which one they are naming.
  Future<void> _openRenameSheet(BuildContext context) async {
    final String? result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _RenameSheet(
        maskedIdentifier: summary.instrument.maskedIdentifier,
        initialName: summary.friendlyName ?? '',
      ),
    );

    if (result != null) {
      // An empty string is passed through rather than swallowed: it means
      // "clear the name", and the DAO turns it back into null so the
      // instrument returns to being labelled by its masked identifier
      // (AC-B15.2).
      onRename(result);
    }
  }
}

/// The sheet's body.
///
/// A `StatefulWidget` purely so it can **own** its `TextEditingController`
/// and dispose it in `dispose()`. Creating the controller in the calling
/// method and disposing it after `showModalBottomSheet` returns looks
/// equivalent and is not: the sheet's exit animation is still running at that
/// point, the `TextField` rebuilds during it, and Flutter throws *"A
/// TextEditingController was used after being disposed"*. Letting the widget
/// that uses the controller own its lifetime removes the race entirely.
class _RenameSheet extends StatefulWidget {
  final String maskedIdentifier;
  final String initialName;

  const _RenameSheet({
    required this.maskedIdentifier,
    required this.initialName,
  });

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        // Lifts the sheet above the keyboard. Without this the Save button
        // sits under the on-screen keyboard on a short device and the user
        // cannot reach it.
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.instrumentRenameTitle,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          MaskedIdentifierText(
            maskedIdentifier: widget.maskedIdentifier,
            style: text.bodySmall?.copyWith(color: AppColors.ink500),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.instrumentRenameFieldLabel,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_controller.text),
              child: Text(l10n.instrumentRenameSave),
            ),
          ),
        ],
      ),
    );
  }
}

/// The identity block: kind, masked identifier, network/type, and — for a
/// card — the settlement-account link or its explicit absence.
class _IdentityCard extends StatelessWidget {
  final InstrumentSummary summary;
  final bool isCard;

  const _IdentityCard({required this.summary, required this.isCard});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsetsDirectional.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                isCard ? Icons.credit_card : Icons.account_balance_wallet,
                size: 18,
                color: AppColors.ink700,
              ),
              const SizedBox(width: 8),
              Text(
                instrumentKindLabel(l10n, summary.instrument.kind),
                style: text.bodyMedium,
              ),
              const SizedBox(width: 8),
              MaskedIdentifierText(
                maskedIdentifier: summary.instrument.maskedIdentifier,
                style: text.bodyMedium?.copyWith(color: AppColors.ink700),
              ),
            ],
          ),
          if (summary.isUnnamed) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              l10n.instrumentUnnamed,
              style: text.bodySmall?.copyWith(color: AppColors.ink500),
            ),
          ],
          if (isCard) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                const Icon(Icons.link, size: 16, color: AppColors.ink500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    // AC-B14.2 when linked, AC-B14.3 when not — and the
                    // unlinked wording is neutral by design.
                    summary.settlementAccountLabel == null
                        ? l10n.instrumentNotLinked
                        : l10n.instrumentLinkedTo(
                            summary.settlementAccountLabel!,
                          ),
                    style: text.bodySmall?.copyWith(color: AppColors.ink700),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One transaction row — design.md's `TransactionListItem`, reduced to what
/// this screen needs.
class _TransactionRow extends StatelessWidget {
  final LedgerTransaction transaction;
  final VoidCallback? onTap;

  const _TransactionRow({required this.transaction, this.onTap});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      title: Text(
        transaction.merchantRawText ??
            transaction.counterpartyName ??
            transactionTypeLabel(l10n, transaction.transactionType),
        style: text.bodyLarge,
      ),
      subtitle: Text(
        transaction.occurredAt == null
            ? l10n.fieldNotStatedInMessage
            : formatShortDateTime(transaction.occurredAt!),
        style: text.bodySmall?.copyWith(color: AppColors.ink500),
      ),
      trailing: SignedAmountText(
        amount: transaction.amount,
        isCredit: transaction.isCredit,
        style: text.bodyMedium,
      ),
    );
  }
}

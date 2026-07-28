import 'package:flutter/material.dart';

import '../../features/ledger/ledger_transaction.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/ledger_widgets.dart';

/// **S-11 — Transaction Detail.** Mockup: `docs/mockups/transaction-detail.html`.
/// KHA-25, US-B1, AC-B1.1, AC-B1.2, AC-B1.3, AC-B1.4.
///
/// ## The four acceptance criteria, and where each one lives in this file
///
/// | AC | Where |
/// |---|---|
/// | **B1.1** amount, currency, merchant/payee, date-time, card/account, type all displayed | the field list in [_Fields] |
/// | **B1.2** the original SMS text is viewable so the user can verify the parse | [_OriginalMessagePanel] |
/// | **B1.3** an absent field reads as explicitly unknown | every row goes through `DetailFieldRow`, which renders *"Not stated in message"* for null |
/// | **B1.4** the amount matches the source exactly, no rounding | `SignedAmountText` prints `Money.toCanonicalString()`; nothing here parses, formats or rounds a figure |
///
/// ## Why this screen takes a value type and not an id
///
/// It is a `StatelessWidget` over a [LedgerTransaction], with the original
/// message text passed in separately. No database, no provider, no async. That
/// keeps the widget test a pure render test — and, more importantly, means
/// this screen cannot accidentally read something the app lock has not
/// unlocked: the data reaches it only through a caller that already went
/// through `unlockedDatabaseSessionProvider` (ADR-005).
///
/// ## Banking-domain notes this screen inherits
///
/// It renders raw SMS content, so it sits behind the app lock (NFR-S3), shows
/// only masked identifiers (NFR-S2 — and the text it displays was already
/// redacted at the ingestion boundary by ADR-013, so there is no PAN left in
/// it to leak into a screenshot or an accessibility tree), and logs nothing
/// (NFR-S4).
class TransactionDetailScreen extends StatefulWidget {
  final LedgerTransaction transaction;

  /// The bank's display name, resolved by the caller. Null when the source
  /// message's bank is no longer known to any active rule pack.
  final String? bankDisplayName;

  /// The sanitised body of the source message (AC-B1.2). Null for a manual
  /// entry — there is no original text, and the panel says so rather than
  /// rendering an empty box.
  final String? originalMessageText;

  /// **Not here, deliberately: Edit, Delete and Restore.** design.md's S-11
  /// carries all three, and KHA-26 (P3b) implements them. Rendering buttons
  /// now, wired to nothing, would be worse than their absence — a delete
  /// affordance that silently does nothing in a banking app is a trust
  /// failure, not a stub. The deleted-state banner *is* here, because a
  /// transaction deleted by any path must never look live.
  const TransactionDetailScreen({
    required this.transaction,
    this.bankDisplayName,
    this.originalMessageText,
    super.key,
  });

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  /// The `SmsOriginalTextPanel` starts collapsed (design.md §5). The raw text
  /// is the most sensitive thing on the screen, so it is one deliberate tap
  /// away rather than on display by default over someone's shoulder.
  bool _originalExpanded = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final LedgerTransaction txn = widget.transaction;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(l10n.transactionDetailTitle)),
      body: ListView(
        padding: const EdgeInsetsDirectional.all(16),
        children: <Widget>[
          if (txn.isDeleted) const _DeletedBanner(),
          _Header(transaction: txn),
          const SizedBox(height: 16),
          _Fields(
            transaction: txn,
            bankDisplayName: widget.bankDisplayName ?? l10n.txnUnknownBank,
          ),
          const SizedBox(height: 8),
          _OriginalMessagePanel(
            text: widget.originalMessageText,
            expanded: _originalExpanded,
            onToggle: () =>
                setState(() => _originalExpanded = !_originalExpanded),
          ),
        ],
      ),
    );
  }
}

/// US-B8's deleted state: the transaction is still readable, and it is
/// unmistakable that it counts toward nothing.
class _DeletedBanner extends StatelessWidget {
  const _DeletedBanner();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 12),
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: AppColors.ink100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.delete_outline, size: 18, color: AppColors.ink700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.txnDeletedBanner,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Merchant/payee, the signed amount, and the state badges.
class _Header extends StatelessWidget {
  final LedgerTransaction transaction;

  const _Header({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    // The headline is the merchant, or the counterparty on a transfer (PRD
    // §3.4 — a transfer has no merchant but does have a payee), or the
    // transaction type when neither was stated. It is never blank, and it is
    // never an invented placeholder like "Unknown merchant" that could be
    // mistaken for a real name.
    final String headline =
        transaction.merchantRawText ??
        transaction.counterpartyName ??
        transactionTypeLabel(l10n, transaction.transactionType);

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
          Text(
            headline,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          SignedAmountText(
            amount: transaction.amount,
            isCredit: transaction.isCredit,
            style: text.headlineSmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              // AC-B4.3 — a user-entered transaction is visually distinct
              // from an SMS-derived one, by icon and word (NFR-U4).
              if (transaction.isUserEntered)
                const _Badge(
                  icon: Icons.edit_outlined,
                  labelKey: _BadgeKind.manual,
                ),
              if (transaction.needsReview)
                const _Badge(
                  icon: Icons.flag_outlined,
                  labelKey: _BadgeKind.needsReview,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _BadgeKind { manual, needsReview }

class _Badge extends StatelessWidget {
  final IconData icon;
  final _BadgeKind labelKey;

  const _Badge({required this.icon, required this.labelKey});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String label = switch (labelKey) {
      _BadgeKind.manual => l10n.txnBadgeManual,
      _BadgeKind.needsReview => l10n.txnBadgeNeedsReview,
    };
    final bool isWarning = labelKey == _BadgeKind.needsReview;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: isWarning ? AppColors.secondaryTint10 : AppColors.ink100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            size: 14,
            color: isWarning ? AppColors.warningText : AppColors.ink700,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isWarning ? AppColors.warningText : AppColors.ink700,
            ),
          ),
        ],
      ),
    );
  }
}

/// AC-B1.1's field list, plus the multi-currency and provenance fields.
class _Fields extends StatelessWidget {
  final LedgerTransaction transaction;
  final String bankDisplayName;

  const _Fields({required this.transaction, required this.bankDisplayName});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final LedgerTransaction txn = transaction;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 16,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink100),
      ),
      child: Column(
        children: <Widget>[
          DetailFieldRow(
            label: l10n.txnFieldDateTime,
            // Null here is a real case: a message can state no time and the
            // pipeline records that rather than inventing one.
            value: txn.occurredAt == null
                ? null
                : formatShortDateTime(txn.occurredAt!),
          ),
          DetailFieldRow(
            label: l10n.txnFieldInstrument,
            valueWidget: _instrumentValue(context, l10n),
          ),
          DetailFieldRow(
            label: l10n.txnFieldType,
            value: transactionTypeLabel(l10n, txn.transactionType),
          ),
          DetailFieldRow(
            label: l10n.txnFieldMerchant,
            value: txn.merchantRawText,
          ),
          // Transfers only. A purchase has no counterparty *concept*, so
          // showing "Not stated in message" there would invent a question the
          // message was never asked. When either half is present — i.e. this
          // really is a transfer — both rows render, and the missing half
          // reads as explicitly unknown (AC-B1.3).
          if (txn.counterpartyName != null ||
              txn.counterpartyBankName != null) ...<Widget>[
            DetailFieldRow(
              label: l10n.txnFieldCounterparty,
              value: txn.counterpartyName,
            ),
            DetailFieldRow(
              label: l10n.txnFieldCounterpartyBank,
              value: txn.counterpartyBankName,
            ),
          ],
          DetailFieldRow(
            label: l10n.txnFieldReference,
            value: txn.referenceNumber,
          ),
          // The FX block. Shown only for a transaction that actually carried
          // any of it — on a plain SAR purchase these three rows would be
          // three "not stated"s that tell the user nothing.
          if (txn.convertedAmount != null ||
              txn.feeAmount != null ||
              txn.fxRate != null) ...<Widget>[
            DetailFieldRow(
              label: l10n.txnFieldConvertedAmount,
              value: txn.convertedAmount == null
                  ? null
                  : '${formatAmountDigits(txn.convertedAmount!)} '
                        '${txn.convertedAmount!.currencyCode}',
            ),
            DetailFieldRow(
              label: l10n.txnFieldFxFee,
              value: txn.feeAmount == null
                  ? null
                  : '${formatAmountDigits(txn.feeAmount!)} '
                        '${txn.feeAmount!.currencyCode}',
            ),
            DetailFieldRow(label: l10n.txnFieldExchangeRate, value: txn.fxRate),
          ],
          if (txn.remainingBalance != null)
            DetailFieldRow(
              label: l10n.txnFieldRemainingBalance,
              value:
                  '${formatAmountDigits(txn.remainingBalance!)} '
                  '${txn.remainingBalance!.currencyCode}',
            ),
          DetailFieldRow(
            label: l10n.txnFieldSource,
            value: _provenanceLabel(l10n),
          ),
        ],
      ),
    );
  }

  /// AC-B1.1's "card/account identifier".
  ///
  /// Three genuinely different states, and the difference matters:
  ///  - resolved instrument → its friendly name or its masked identifier
  ///    (AC-B15.2);
  ///  - no resolved instrument but the message printed one → show what the
  ///    message said, so the user is not told "unknown" about something they
  ///    can read in the original text;
  ///  - neither → `null`, which `DetailFieldRow` renders as explicitly
  ///    unknown (AC-B1.3).
  Widget? _instrumentValue(BuildContext context, AppLocalizations l10n) {
    final LedgerInstrument? instrument = transaction.instrument;
    if (instrument != null) {
      final String? friendly = instrument.friendlyName;
      if ((friendly ?? '').trim().isNotEmpty) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(child: Text(friendly!)),
            const SizedBox(width: 6),
            MaskedIdentifierText(
              maskedIdentifier: instrument.maskedIdentifier,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.ink500),
            ),
          ],
        );
      }
      return MaskedIdentifierText(
        maskedIdentifier: instrument.maskedIdentifier,
      );
    }

    final String? fromMessage = transaction.instrumentMaskedRefFromMessage;
    if (fromMessage != null) {
      return MaskedIdentifierText(maskedIdentifier: fromMessage);
    }
    return null; // → "Not stated in message"
  }

  /// NFR-A1's provenance, in words.
  ///
  /// The manual-completion case is deliberately its own sentence rather than
  /// being collapsed into "manual": the message is real and still linked, and
  /// a user who later asks "where did this number come from?" deserves the
  /// true answer, which is "from you, reading that message".
  String _provenanceLabel(AppLocalizations l10n) {
    if (transaction.provenanceDetail == ProvenanceDetail.manualCompletion) {
      return l10n.txnSourceSmsCompletedByYou(bankDisplayName);
    }
    return switch (transaction.provenance) {
      TransactionProvenance.manual => l10n.txnSourceManual,
      TransactionProvenance.statement => l10n.txnSourceStatement,
      _ => l10n.txnSourceSms(bankDisplayName),
    };
  }
}

/// **AC-B1.2** — the collapsible original-message panel (design.md's
/// `SmsOriginalTextPanel`).
///
/// This is the feature that makes the whole product auditable to its user:
/// every parsed number can be checked against the sentence it came from. It
/// is also why raw SMS text is retained at all (build-plan §5), and why that
/// text is redacted before storage rather than before display.
class _OriginalMessagePanel extends StatelessWidget {
  final String? text;
  final bool expanded;
  final VoidCallback onToggle;

  const _OriginalMessagePanel({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;

    if (text == null) {
      // A manual entry has no original message. Saying so is better than an
      // expander that opens onto nothing.
      return Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: 12),
        child: Text(
          l10n.txnNoOriginalSms,
          style: textTheme.bodySmall?.copyWith(color: AppColors.ink500),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextButton.icon(
          onPressed: onToggle,
          icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
          label: Text(
            expanded ? l10n.txnHideOriginalSms : l10n.txnShowOriginalSms,
          ),
        ),
        if (expanded)
          Container(
            width: double.infinity,
            padding: const EdgeInsetsDirectional.all(12),
            decoration: BoxDecoration(
              color: AppColors.ink100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(text!, style: textTheme.bodyMedium),
          ),
      ],
    );
  }
}

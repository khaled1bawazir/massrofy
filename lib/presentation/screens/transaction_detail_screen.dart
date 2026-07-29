import 'package:flutter/material.dart';

import '../../features/ledger/base_currency.dart';
import '../../features/ledger/internal_transfer.dart';
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

  /// **AC-B11.1/AC-B11.2** — `internal` | `candidate` | `external`, resolved
  /// by the caller.
  ///
  /// Passed in rather than derived here for a reason worth stating: an
  /// internal transfer is a property of a *pair*, and this screen only ever
  /// holds one leg. A widget that tried to work it out for itself would
  /// always answer "not internal", which is precisely the bug US-B11 warns
  /// about. The caller runs `InternalTransferDetector` over the whole ledger
  /// and hands the answer down; when it passes nothing, the transaction's own
  /// persisted state is used.
  final String? internalTransferState;

  /// **KHA-26 / US-B5** — opens S-20 in edit mode. Null leaves the action off
  /// the screen entirely; P3a's note below is why that is the right default.
  final VoidCallback? onEdit;

  /// **KHA-26 / US-B6** — soft-deletes, *after* this screen has obtained the
  /// AC-B6.2 confirmation. The caller performs the write; this screen owns the
  /// dialog, because the confirmation is a presentation obligation and putting
  /// it in the service would make it skippable by any other caller.
  final VoidCallback? onDelete;

  /// **KHA-26 / US-B8** — restores a soft-deleted transaction (AC-B8.2).
  /// Offered only when the transaction is actually deleted.
  final VoidCallback? onRestore;

  /// **Edit, Delete and Restore are absent unless a callback is supplied**,
  /// and that rule is inherited from P3a rather than relaxed by P3b-2.
  ///
  /// P3a's note read: *"rendering buttons now, wired to nothing, would be
  /// worse than their absence — a delete affordance that silently does
  /// nothing in a banking app is a trust failure, not a stub."* That is still
  /// true, so the actions are nullable and each one renders only when it has
  /// somewhere to go. KHA-26 supplies all three from the ledger providers; a
  /// context that legitimately has no write path (a future read-only preview,
  /// say) still gets a screen with no dead buttons on it.
  ///
  /// The deleted-state banner is unconditional, because a transaction deleted
  /// by any path must never look live.
  const TransactionDetailScreen({
    required this.transaction,
    this.bankDisplayName,
    this.originalMessageText,
    this.internalTransferState,
    this.onEdit,
    this.onDelete,
    this.onRestore,
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
    final String? transferState =
        widget.internalTransferState ?? txn.internalTransferState;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(l10n.transactionDetailTitle)),
      body: ListView(
        padding: const EdgeInsetsDirectional.all(16),
        children: <Widget>[
          if (txn.isDeleted) const _DeletedBanner(),
          _Header(transaction: txn, internalTransferState: transferState),
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
          const SizedBox(height: 20),
          _Actions(
            isDeleted: txn.isDeleted,
            onEdit: widget.onEdit,
            onRestore: widget.onRestore,
            onDelete: widget.onDelete == null
                ? null
                : () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  /// **AC-B6.2 — "after an explicit confirmation".**
  ///
  /// A modal the user has to answer, not a toast they can miss. Three details
  /// are deliberate:
  ///
  ///  - The body says the transaction goes to Recently deleted and can be
  ///    restored (AC-B8.1). Letting the user believe deletion is permanent
  ///    would make them hesitate over correcting a wrong row, and a ledger
  ///    people are afraid to correct drifts away from reality.
  ///  - **Cancel is "Keep it"**, positively worded and first, so the safe
  ///    choice is the easy one and the default focus is not destructive.
  ///  - The dialog returning false or being dismissed writes **nothing**
  ///    (AC-B6.2's cancel clause). `showDialog` returns null on a barrier
  ///    dismiss, which `!= true` handles without a separate branch.
  Future<void> _confirmDelete(BuildContext context) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.txnDeleteConfirmTitle),
        content: Text(l10n.txnDeleteConfirmBody),
        actions: <Widget>[
          TextButton(
            key: const Key('txnDetail.deleteCancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.txnDeleteConfirmCancel),
          ),
          FilledButton(
            key: const Key('txnDetail.deleteConfirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.txnDeleteConfirmAccept),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onDelete?.call();
    }
  }
}

/// S-11's action row: Edit and Delete on a live transaction, Restore on a
/// deleted one.
///
/// Delete and Restore are never both offered. A deleted transaction has
/// nothing to delete, and showing a disabled Delete beside Restore would ask
/// the user to work out which state they are in from a greyed-out button
/// instead of from the banner that already says so.
class _Actions extends StatelessWidget {
  final bool isDeleted;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onRestore;

  const _Actions({
    required this.isDeleted,
    this.onEdit,
    this.onDelete,
    this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    if (isDeleted) {
      if (onRestore == null) {
        return const SizedBox.shrink();
      }
      return FilledButton.icon(
        key: const Key('txnDetail.restore'),
        onPressed: onRestore,
        icon: const Icon(Icons.restore_from_trash_outlined),
        label: Text(l10n.txnRestoreAction),
      );
    }

    if (onEdit == null && onDelete == null) {
      return const SizedBox.shrink();
    }

    return Row(
      children: <Widget>[
        if (onEdit != null)
          Expanded(
            child: FilledButton.icon(
              key: const Key('txnDetail.edit'),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: Text(l10n.txnEditTitle),
            ),
          ),
        if (onEdit != null && onDelete != null) const SizedBox(width: 8),
        if (onDelete != null)
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('txnDetail.delete'),
              onPressed: onDelete,
              // NFR-U4: an icon AND a word. The destructive action is never
              // signalled by colour alone.
              icon: const Icon(Icons.delete_outline),
              label: Text(l10n.txnDeleteAction),
            ),
          ),
      ],
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
  final String? internalTransferState;

  const _Header({required this.transaction, this.internalTransferState});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final bool isInternal =
        internalTransferState == InternalTransferState.internal;
    final bool isCandidate =
        internalTransferState == InternalTransferState.candidate;

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
          // design.md §3.3: a confirmed internal transfer carries **no +/−
          // prefix at all**, because it is neither spend nor income. Showing
          // "−1,500.00 SAR" next to an "excluded from spend" badge would put
          // two contradictory statements on one card.
          if (isInternal)
            Text(
              '${formatAmountDigits(transaction.amount)} '
              '${transaction.amount.currencyCode}',
              style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.ink700,
              ),
              textDirection: TextDirection.ltr,
            )
          else
            SignedAmountText(
              amount: transaction.amount,
              isCredit: transaction.isCredit,
              style: text.headlineSmall,
            ),
          if (isInternal || isCandidate) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              isInternal
                  ? l10n.txnInternalTransferExcludedNote
                  : l10n.txnInternalTransferCandidateNote,
              style: text.bodySmall?.copyWith(color: AppColors.ink500),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (isInternal || isCandidate)
                InternalTransferBadge(isConfirmed: isInternal),
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
          // The FX block — AC-B9.1 and AC-B9.3, and the whole of KHA-70.
          ..._fxRows(context, l10n, txn),
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

  /// **The FX block — AC-B9.1, AC-B9.3, and the fix for KHA-70.**
  ///
  /// Three rules hold here, and the second is the defect that was raised:
  ///
  /// 1. **Nothing is rendered on a plain base-currency purchase.** Three
  ///    "not stated in message" rows on a 152.75 SAR coffee tell the user
  ///    nothing and train them to skip the block.
  /// 2. **A rate is never shown alone.** Whenever [LedgerTransaction.fxRate]
  ///    is displayed, a rate-date row is displayed beside it — carrying either
  ///    the real date or the literal words *"date unknown"*. Rendering an
  ///    undated rate makes it look authoritative, which is exactly what
  ///    defect D-QA-2 / KHA-70 was raised for. There is a widget test that
  ///    fails if a rate ever appears without one of the two.
  /// 3. **A foreign purchase with no conversion says so.** ADR-009's case 4
  ///    excludes it from the period total, and that exclusion is stated here
  ///    rather than being something the user discovers by adding the list up
  ///    themselves.
  List<Widget> _fxRows(
    BuildContext context,
    AppLocalizations l10n,
    LedgerTransaction txn,
  ) {
    final bool hasAnyFx =
        txn.convertedAmount != null ||
        txn.feeAmount != null ||
        txn.fxRate != null ||
        txn.conversionPending;
    if (!hasAnyFx) {
      return const <Widget>[];
    }

    return <Widget>[
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
      if (txn.fxRate != null) ...<Widget>[
        DetailFieldRow(label: l10n.txnFieldExchangeRate, value: txn.fxRate),
        // Rule 2. `value` is deliberately never null on this row: a null
        // would render "Not stated in message", which reads as a *field* we
        // did not capture rather than as a statement about the rate's
        // trustworthiness. The words "Date unknown" say the latter.
        DetailFieldRow(
          label: l10n.txnFieldFxRateDate,
          value: txn.fxRateDate == null
              ? l10n.txnFxRateDateUnknown
              : formatShortDateTime(txn.fxRateDate!),
        ),
        DetailFieldRow(
          label: l10n.txnFieldFxRateSource,
          value: _fxSourceLabel(l10n, txn.fxRateSource),
        ),
      ],
      if (txn.conversionPending)
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(vertical: 8),
          child: Text(
            l10n.txnFxNotConverted(BaseCurrency.defaultCode),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.warningText),
          ),
        ),
    ];
  }

  /// Null (an unrecognised or absent source) falls through to
  /// `DetailFieldRow`'s explicit-unknown rendering rather than to a guess —
  /// §5.2's forward-compatibility rule applied to a stored vocabulary.
  String? _fxSourceLabel(AppLocalizations l10n, String? stored) =>
      switch (stored) {
        FxRateSource.smsImplied => l10n.txnFxSourceSmsImplied,
        FxRateSource.smsStated => l10n.txnFxSourceSmsStated,
        FxRateSource.user => l10n.txnFxSourceUser,
        FxRateSource.carriedForward => l10n.txnFxSourceCarriedForward,
        _ => null,
      };

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

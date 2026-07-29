import 'package:flutter/material.dart';

import '../../core/money/sign_convention.dart';
// `TransactionField` (the audit/edit field vocabulary) and `Edited<T>` are
// re-exported by the DAO so a screen expressing an edit needs one import
// rather than three — see `transaction_dao.dart`'s export block.
import '../../data/dao/transaction_dao.dart';
import '../../features/ledger/bank_tree.dart';
import '../../features/ledger/ledger_transaction.dart';
import '../../features/ledger/manual_entry.dart';
import '../../features/ledger/transaction_edit.dart';
import '../../features/ledger/transaction_types.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/ledger_widgets.dart';

/// **S-20 — Manual Transaction Entry / Edit.** KHA-26, US-B4, US-B5,
/// AC-B4.1/2/3, AC-B5.1/2/3.
///
/// ## One screen, two jobs — because design.md says they are one form
///
/// design.md S-20 is explicit that entry and edit share their field set
/// ("amount+currency, date/time, merchant, category, instrument/cash, type"),
/// so this widget takes an optional [existing] transaction and switches mode.
/// Building two screens would guarantee they drift: a validation rule added to
/// one and forgotten on the other is exactly how a negative amount reaches
/// storage through the path nobody tested (defect O-QA-2's shape).
///
/// ## The three rules this form enforces, and where they come from
///
/// 1. **Validation names the field** (AC-B4.2). Every failure sets an
///    `errorText` on the specific input, never a general banner. The service
///    validates again independently — the form protects the person, the
///    service protects the data.
/// 2. **The sign lives in the direction control, never in the amount.** A
///    negative number is rejected with `amountMustBePositive`; it is not
///    absolute-valued and the minus sign is never read as "make this a
///    refund". `lib/core/money/sign_convention.dart` is the contract, and this
///    is the form it was written for.
/// 3. **Cash is a normal choice, not an absence.** The "Paid with" picker
///    opens on *Cash* rather than on a blank, because OQ-19 makes cash
///    first-class and a tracker people avoid entering cash into produces a
///    total that is quietly too low.
///
/// ## AC-B5.2, in edit mode
///
/// When the user has previously edited a field, the caption under it shows
/// what the parser originally detected ([TransactionEditHistory]) alongside
/// the current value, plus a note that a re-scan will not overwrite it
/// (AC-B5.3). Both are read from the audit trail rather than a duplicate
/// column, so the screen cannot disagree with the change history.
class ManualEntryScreen extends StatefulWidget {
  /// Null for US-B4 (adding), non-null for US-B5 (editing an existing row).
  final LedgerTransaction? existing;

  /// AC-B5.2's "originally detected" values, keyed by [TransactionField].
  /// Empty for a new transaction and for a row nobody has edited.
  final TransactionEditHistory editHistory;

  final List<InstrumentSummary> instruments;
  final String defaultCurrencyCode;

  /// Called with the user's input in add mode.
  final void Function(ManualTransactionDraft draft)? onAdd;

  /// Called with the user's input in edit mode.
  final void Function(TransactionEditDraft draft)? onEdit;

  /// Field names ([ManualEntryField] / [TransactionField] constants) a service
  /// rejected, so a rejection that happened after Save still lands on the
  /// right input rather than in a generic snackbar.
  final List<String> rejectedFields;

  /// Set when the rejection was specifically a negative amount, so the field
  /// shows the sign-convention explanation rather than "enter an amount".
  final bool amountWasNegative;

  const ManualEntryScreen({
    this.existing,
    this.editHistory = TransactionEditHistory.none,
    this.instruments = const <InstrumentSummary>[],
    this.defaultCurrencyCode = 'SAR',
    this.onAdd,
    this.onEdit,
    this.rejectedFields = const <String>[],
    this.amountWasNegative = false,
    super.key,
  });

  bool get isEditing => existing != null;

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  late final TextEditingController _amount = TextEditingController(
    // In edit mode the field starts from the stored canonical string, so the
    // user sees exactly what is recorded rather than a re-formatted
    // approximation of it (ADR-002 — the text IS the authoritative value).
    text: widget.existing?.amount.toCanonicalString() ?? '',
  );
  late final TextEditingController _currency = TextEditingController(
    text: widget.existing?.amount.currencyCode ?? widget.defaultCurrencyCode,
  );
  late final TextEditingController _merchant = TextEditingController(
    text: widget.existing?.merchantRawText ?? '',
  );

  late DateTime _occurredAt =
      widget.existing?.occurredAt ?? DateTime.now().toUtc();
  late String? _transactionType = widget.existing?.transactionType;
  late String _direction =
      widget.existing?.direction ?? MovementDirection.debit;
  late int? _instrumentId = widget.existing?.instrument?.id;

  late List<String> _invalid = widget.rejectedFields;
  late bool _negativeAmount = widget.amountWasNegative;

  /// The vocabulary the rule pack uses, so a hand-entered transaction is
  /// indistinguishable in kind from a parsed one and every later report treats
  /// them identically.
  static const List<String> _types = <String>[
    TransactionType.posPurchase,
    TransactionType.onlinePurchase,
    TransactionType.billPayment,
    TransactionType.transferOut,
    TransactionType.transferIn,
    TransactionType.salaryIncome,
    TransactionType.cardRepayment,
    TransactionType.fee,
    TransactionType.installment,
    TransactionType.accountDebit,
    TransactionType.refund,
    TransactionType.withdrawal,
  ];

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _merchant.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          widget.isEditing ? l10n.txnEditTitle : l10n.manualEntryTitle,
        ),
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.all(16),
        children: <Widget>[
          if (!widget.isEditing)
            Text(
              l10n.manualEntryIntro,
              style: text.bodySmall?.copyWith(color: AppColors.ink500),
            ),
          const SizedBox(height: 16),

          TextField(
            controller: _amount,
            key: const Key('manualEntry.amount'),
            // A decimal keyboard. Not `TextInputType.number`, which on Android
            // hides the separator the user needs — and deliberately NOT
            // `signed: true`: the minus key has no meaning here, and offering
            // it would invite exactly the input the sign convention rejects.
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.manualEntryAmountLabel,
              errorText: _amountError(l10n),
            ),
          ),
          _originalValueCaption(l10n, TransactionField.amount),
          const SizedBox(height: 12),

          TextField(
            controller: _currency,
            key: const Key('manualEntry.currency'),
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: l10n.manualEntryCurrencyLabel,
              errorText: _invalid.contains(ManualEntryField.currency)
                  ? l10n.manualEntryCurrencyMissing
                  : null,
            ),
          ),
          const SizedBox(height: 12),

          // NFR-U4: the direction is a labelled control with words, not a
          // colour or a sign. It is the ONLY place the sign of a movement
          // lives (`sign_convention.dart`).
          SegmentedButton<String>(
            key: const Key('manualEntry.direction'),
            segments: <ButtonSegment<String>>[
              ButtonSegment<String>(
                value: MovementDirection.debit,
                label: Text(l10n.completeDirectionDebit),
                icon: const Icon(Icons.arrow_upward),
              ),
              ButtonSegment<String>(
                value: MovementDirection.credit,
                label: Text(l10n.completeDirectionCredit),
                icon: const Icon(Icons.arrow_downward),
              ),
            ],
            selected: <String>{_direction},
            onSelectionChanged: (Set<String> selection) =>
                setState(() => _direction = selection.first),
          ),
          _originalValueCaption(l10n, TransactionField.direction),
          const SizedBox(height: 16),

          TextField(
            controller: _merchant,
            key: const Key('manualEntry.merchant'),
            decoration: InputDecoration(
              labelText: l10n.manualEntryMerchantLabel,
            ),
          ),
          _originalValueCaption(l10n, TransactionField.merchantRawText),
          const SizedBox(height: 16),

          _DateTimeField(
            value: _occurredAt,
            label: l10n.manualEntryDateLabel,
            errorText: _invalid.contains(ManualEntryField.occurredAt)
                ? l10n.manualEntryDateMissing
                : null,
            onChanged: (DateTime picked) =>
                setState(() => _occurredAt = picked),
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            key: const Key('manualEntry.type'),
            initialValue: _transactionType,
            decoration: InputDecoration(
              labelText: l10n.manualEntryTypeLabel,
              errorText: _invalid.contains(ManualEntryField.transactionType)
                  ? l10n.manualEntryTypeMissing
                  : null,
            ),
            items: <DropdownMenuItem<String>>[
              for (final String type in _types)
                DropdownMenuItem<String>(
                  value: type,
                  child: Text(transactionTypeLabel(l10n, type)),
                ),
            ],
            onChanged: (String? value) => setState(() {
              _transactionType = value;
              // A refund, an incoming transfer or a salary is money coming
              // back or in (US-B7, AC-B10.1). Setting the direction with the
              // type saves the user a decision they would otherwise get wrong
              // silently — and direction is the only place the sign lives.
              _direction = TransactionType.creditTypes.contains(value)
                  ? MovementDirection.credit
                  : MovementDirection.debit;
            }),
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<int?>(
            key: const Key('manualEntry.instrument'),
            initialValue: _instrumentId,
            decoration: InputDecoration(labelText: l10n.manualEntrySourceLabel),
            items: <DropdownMenuItem<int?>>[
              // OQ-19: "Cash" leads and is the default. It is a payment
              // method, not the absence of one, and presenting it as
              // "Not stated" would frame the product's own first-class case
              // as a gap in the data.
              DropdownMenuItem<int?>(child: Text(l10n.manualEntrySourceCash)),
              for (final InstrumentSummary summary in widget.instruments)
                DropdownMenuItem<int?>(
                  value: summary.instrument.id,
                  child: Text(
                    '${instrumentKindLabel(l10n, summary.instrument.kind)} · '
                    '${summary.label}',
                  ),
                ),
            ],
            onChanged: (int? value) => setState(() => _instrumentId = value),
          ),
          const SizedBox(height: 8),
          if (_instrumentId == null)
            Text(
              l10n.manualEntryCashNote,
              style: text.bodySmall?.copyWith(color: AppColors.ink500),
            ),
          const SizedBox(height: 20),

          FilledButton(
            key: const Key('manualEntry.save'),
            onPressed: _save,
            child: Text(
              widget.isEditing ? l10n.txnEditSave : l10n.manualEntrySave,
            ),
          ),
        ],
      ),
    );
  }

  /// AC-B4.2's amount messages, kept in one place so "missing" and "negative"
  /// cannot be confused with each other.
  String? _amountError(AppLocalizations l10n) {
    if (_negativeAmount) {
      // The sign convention's own user-facing string: it explains the
      // direction control rather than just saying "no".
      return l10n.amountMustBePositive;
    }
    if (!_invalid.contains(ManualEntryField.amount)) {
      return null;
    }
    return _amount.text.trim().isEmpty
        ? l10n.manualEntryAmountMissing
        : l10n.manualEntryAmountUnparsable;
  }

  /// **AC-B5.2** — under an edited field, what the parser originally detected.
  ///
  /// Renders nothing at all when the field has never been edited, because
  /// there is then only one value and showing "originally: X" next to an
  /// identical X is noise.
  Widget _originalValueCaption(AppLocalizations l10n, String field) {
    if (!widget.isEditing || widget.editHistory.isEmpty) {
      return const SizedBox.shrink();
    }
    if (!widget.editHistory.originalValues.containsKey(field)) {
      return const SizedBox.shrink();
    }
    final String? original = widget.editHistory.originalFor(field);
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 6, start: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            // AC-B1.3 again: "the parser found nothing" and "the parser found
            // an empty string" are different facts and read differently.
            original == null || original.isEmpty
                ? l10n.txnEditOriginalValueEmpty
                : l10n.txnEditOriginalValue(original),
            style: text.bodySmall?.copyWith(color: AppColors.ink500),
          ),
          Text(
            l10n.txnEditProtectedFromRescan,
            style: text.bodySmall?.copyWith(color: AppColors.ink500),
          ),
        ],
      ),
    );
  }

  void _save() {
    final String amountText = _amount.text.trim();
    final bool negative = amountText.startsWith('-');
    final List<String> invalid = <String>[
      if (amountText.isEmpty || negative) ManualEntryField.amount,
      if (_currency.text.trim().length != 3) ManualEntryField.currency,
      if (_transactionType == null) ManualEntryField.transactionType,
    ];

    if (invalid.isNotEmpty) {
      // Every problem at once, each against its own field — one round trip
      // rather than one error per attempt (AC-B4.2, brand voice principle 4).
      setState(() {
        _invalid = invalid;
        _negativeAmount = negative;
      });
      return;
    }

    setState(() {
      _invalid = const <String>[];
      _negativeAmount = false;
    });

    if (widget.isEditing) {
      widget.onEdit?.call(
        TransactionEditDraft(
          amountText: Edited<String>(amountText),
          currencyCode: _currency.text.trim().toUpperCase(),
          merchantRawText: Edited<String?>(
            _merchant.text.trim().isEmpty ? null : _merchant.text.trim(),
          ),
          occurredAt: Edited<DateTime?>(_occurredAt),
          direction: Edited<String>(_direction),
          transactionType: Edited<String>(_transactionType!),
          instrumentId: Edited<int?>(_instrumentId),
        ),
      );
      return;
    }

    widget.onAdd?.call(
      ManualTransactionDraft(
        amountText: amountText,
        currencyCode: _currency.text.trim().toUpperCase(),
        occurredAt: _occurredAt,
        transactionType: _transactionType,
        direction: _direction,
        merchantRawText: _merchant.text,
        instrumentId: _instrumentId,
      ),
    );
  }
}

/// A date+time field. Deliberately small and dependency-free — full localised
/// date formatting arrives with P5's reporting work, and pulling a formatting
/// dependency in for one caption now would be scope this phase does not own.
class _DateTimeField extends StatelessWidget {
  final DateTime value;
  final String label;
  final String? errorText;
  final void Function(DateTime) onChanged;

  const _DateTimeField({
    required this.value,
    required this.label,
    required this.onChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('manualEntry.date'),
      onTap: () => _pick(context),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, errorText: errorText),
        child: Text(formatShortDateTime(value)),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final DateTime local = value.toLocal();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: local,
      firstDate: DateTime(2000),
      // A transaction dated in the future is a typo, not a fact.
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !context.mounted) {
      return;
    }
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(local),
    );
    if (time == null) {
      return;
    }
    onChanged(
      DateTime(date.year, date.month, date.day, time.hour, time.minute).toUtc(),
    );
  }
}

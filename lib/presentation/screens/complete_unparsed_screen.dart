import 'package:flutter/material.dart';

import '../../features/ingestion/review_queue.dart';
import '../../features/ledger/bank_tree.dart';
import '../../features/ledger/unparsed_completion.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/ledger_widgets.dart';

/// **S-19 — Complete Unparsed SMS.** Mockup: `docs/mockups/needs-review.html`.
/// KHA-64 (first half), US-A4, **AC-A4.2**, AC-B4.2.
///
/// ## What this screen closes
///
/// P2 shipped the review queue with "Fill in details" wired to a callback
/// that had no implementation behind it, and said so in PR #2. AC-A4.2 —
/// *"the user fills in the missing fields manually, a normal transaction is
/// created and the item leaves the review list"* — was therefore not
/// shipped, even though the issue that claimed it was closed. This form, plus
/// `UnparsedCompletionService`, is that implementation.
///
/// ## Three design rules this form follows
///
/// 1. **The original message is on the same screen, not behind a tap.** The
///    user is transcribing from it. Making them remember it while typing is
///    how a wrong amount gets entered. The text is safe to show: it was
///    redacted at the ingestion boundary (ADR-013).
/// 2. **Validation names the field** (AC-B4.2). "Enter an amount to save this
///    transaction", not "invalid input" — brand.md's voice principle 4, and
///    the only kind of error message a user can act on.
/// 3. **Nothing is pre-filled with a guess.** The date defaults to the
///    message's delivery time — a fact, not an invention — and everything
///    else starts empty. A pre-filled amount the user might not notice is
///    exactly the wrong kind of convenience in a spending tracker.
///
/// ## What this form deliberately does not do
///
/// It **cannot create an instrument.** The picker offers only accounts and
/// cards that already exist, plus "Not stated". An instrument invented from a
/// message the parser could not read would be keyed on nothing reliable, and
/// the next genuine message from that card would not match it — producing the
/// duplicate-instrument failure AC-B3.2 exists to prevent. Auto-creation
/// belongs to the parser, where the identifier came from the bank itself.
///
/// It also has **no category picker**, which the mockup shows. Categories are
/// P4 (KHA-30); a picker with nothing behind it would be a lie, so the form
/// says plainly that the transaction saves as uncategorised.
class CompleteUnparsedScreen extends StatefulWidget {
  final ReviewQueueItem item;

  /// The user's existing accounts and cards, for the optional instrument
  /// picker. Empty is a normal state — a first-run user completing their
  /// first message has none.
  final List<InstrumentSummary> instruments;

  /// The app's base currency, used as the initial value of the currency
  /// field. It is a **default, not an assumption**: the field is editable and
  /// its value is stored explicitly, because NFR-A5 allows no amount without
  /// a currency of its own.
  final String defaultCurrencyCode;

  /// Called with a validated-shaped draft. The service validates again — the
  /// form's checks are for the user's benefit, the service's are for the
  /// data's, and the two are deliberately not the same code.
  final void Function(UnparsedCompletionDraft draft) onSave;

  /// Field names ([CompletionField] constants) the service rejected, so a
  /// server-side-style rejection can still be shown against the right field.
  final List<String> rejectedFields;

  const CompleteUnparsedScreen({
    required this.item,
    required this.onSave,
    this.instruments = const <InstrumentSummary>[],
    this.defaultCurrencyCode = 'SAR',
    this.rejectedFields = const <String>[],
    super.key,
  });

  @override
  State<CompleteUnparsedScreen> createState() => _CompleteUnparsedScreenState();
}

class _CompleteUnparsedScreenState extends State<CompleteUnparsedScreen> {
  late final TextEditingController _amount = TextEditingController();
  late final TextEditingController _currency = TextEditingController(
    text: widget.defaultCurrencyCode,
  );
  late final TextEditingController _merchant = TextEditingController();

  /// Defaults to when the message arrived. That is a fact about the message,
  /// not a guess about the transaction — and it is what the parser itself
  /// falls back to (`received_at_fallback`). The user can change it.
  late DateTime _occurredAt = widget.item.receivedAt;

  String? _transactionType;
  String _direction = 'debit';
  int? _instrumentId;

  /// Populated on a failed save attempt so each field can show its own
  /// message (AC-B4.2). Starts from whatever the caller passed in, so a
  /// rejection from the service round-trips onto the right fields.
  late List<String> _missing = widget.rejectedFields;

  /// The transaction types the form offers.
  ///
  /// The same vocabulary the rule pack uses, so a completed transaction is
  /// indistinguishable in kind from a parsed one and every later report
  /// treats them identically.
  static const List<String> _types = <String>[
    'pos_purchase',
    'online_purchase',
    'transfer_out',
    'transfer_in',
    'salary_income',
    'bill_payment',
    'card_repayment',
    'fee',
    'installment',
    'account_debit',
    'refund',
    'withdrawal',
  ];

  /// Which types do **not** count toward spend (US-B10/B11).
  ///
  /// The form derives this from the chosen type rather than asking the user,
  /// because it is a property of the type, not a judgement.
  ///
  /// **P3b-1 correction: `transfer_out` is no longer in this set.** It was,
  /// on the reasoning that a transfer moves the user's own money — but that
  /// is only true of an *internal* transfer, and whether a transfer is
  /// internal is a property of the **pair**, which a form filling in one leg
  /// cannot know (AC-B11.2, risk R-7). Keeping it here meant every
  /// hand-completed outgoing transfer, including a genuine payment to a third
  /// party, was silently dropped from spend. `internal_transfer.dart` decides
  /// this now, from evidence, and flags what it cannot prove.
  static const Set<String> _nonSpendTypes = <String>{
    'card_repayment',
    'transfer_in',
    'salary_income',
    // AC-B10.2 — cash out is not spend until the user records what it bought.
    'withdrawal',
  };

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
      appBar: AppBar(title: Text(l10n.completeTitle)),
      body: ListView(
        padding: const EdgeInsetsDirectional.all(16),
        children: <Widget>[
          Text(
            l10n.completeIntro,
            style: text.bodySmall?.copyWith(color: AppColors.ink500),
          ),
          const SizedBox(height: 12),
          _OriginalMessage(item: widget.item),
          const SizedBox(height: 16),

          TextField(
            controller: _amount,
            // A number keyboard with a decimal point. Not `TextInputType
            // .number`, which on Android hides the separator the user needs.
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.completeAmountLabel,
              errorText: _missing.contains(CompletionField.amount)
                  ? l10n.completeAmountMissing
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _currency,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: l10n.completeCurrencyLabel,
              errorText: _missing.contains(CompletionField.currency)
                  ? l10n.completeCurrencyMissing
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _merchant,
            decoration: InputDecoration(labelText: l10n.completeMerchantLabel),
          ),
          const SizedBox(height: 16),

          _DateField(
            value: _occurredAt,
            label: l10n.completeDateLabel,
            errorText: _missing.contains(CompletionField.occurredAt)
                ? l10n.completeDateMissing
                : null,
            onChanged: (DateTime picked) =>
                setState(() => _occurredAt = picked),
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            initialValue: _transactionType,
            decoration: InputDecoration(
              labelText: l10n.completeTypeLabel,
              errorText: _missing.contains(CompletionField.transactionType)
                  ? l10n.completeTypeMissing
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
              // silently — and the direction is the ONLY place the sign
              // lives, so getting it wrong is getting the total wrong
              // (`lib/core/money/sign_convention.dart`).
              _direction =
                  const <String>{
                    'refund',
                    'transfer_in',
                    'salary_income',
                  }.contains(value)
                  ? 'credit'
                  : 'debit';
            }),
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<int?>(
            initialValue: _instrumentId,
            decoration: InputDecoration(
              labelText: l10n.completeInstrumentLabel,
            ),
            items: <DropdownMenuItem<int?>>[
              // "Not stated" is first and is the default — AC-B1.3's
              // explicit unknown, chosen deliberately over pre-selecting an
              // instrument the message may never have mentioned.
              DropdownMenuItem<int?>(
                child: Text(l10n.completeInstrumentNotStated),
              ),
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
          const SizedBox(height: 16),

          Text(
            l10n.completeCategoryDeferred,
            style: text.bodySmall?.copyWith(color: AppColors.ink500),
          ),
          const SizedBox(height: 20),

          FilledButton(onPressed: _save, child: Text(l10n.completeSave)),
        ],
      ),
    );
  }

  void _save() {
    // The form's own check exists so the user sees every problem at once
    // rather than one per attempt. `UnparsedCompletionService` re-validates
    // independently — the form protects the person, the service protects the
    // data, and neither trusts the other.
    final List<String> missing = <String>[
      if (_amount.text.trim().isEmpty) CompletionField.amount,
      if (_currency.text.trim().length != 3) CompletionField.currency,
      if (_transactionType == null) CompletionField.transactionType,
    ];
    if (missing.isNotEmpty) {
      setState(() => _missing = missing);
      return;
    }

    setState(() => _missing = const <String>[]);
    widget.onSave(
      UnparsedCompletionDraft(
        rawMessageId: widget.item.rawMessageId,
        amountText: _amount.text.trim(),
        currencyCode: _currency.text.trim().toUpperCase(),
        occurredAt: _occurredAt,
        transactionType: _transactionType,
        direction: _direction,
        affectsSpend: !_nonSpendTypes.contains(_transactionType),
        merchantRawText: _merchant.text,
        instrumentId: _instrumentId,
      ),
    );
  }
}

/// AC-A4.1's raw text, kept on screen while the user transcribes from it.
class _OriginalMessage extends StatelessWidget {
  final ReviewQueueItem item;

  const _OriginalMessage({required this.item});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: AppColors.ink100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.completeOriginalMessage,
            style: text.bodySmall?.copyWith(color: AppColors.ink500),
          ),
          const SizedBox(height: 6),
          Text(item.sanitizedBody, style: text.bodyMedium),
          const SizedBox(height: 6),
          Text(
            l10n.needsReviewReceivedFrom(
              formatShortDateTime(item.receivedAt),
              item.sender,
            ),
            style: text.bodySmall?.copyWith(color: AppColors.ink500),
          ),
        ],
      ),
    );
  }
}

/// A date+time field. Kept small and dependency-free — full localised date
/// formatting arrives with P5's reporting work.
class _DateField extends StatelessWidget {
  final DateTime value;
  final String label;
  final String? errorText;
  final void Function(DateTime) onChanged;

  const _DateField({
    required this.value,
    required this.label,
    required this.onChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
      // A transaction cannot have happened before this app's data could
      // exist, and one dated in the future is a typo rather than a fact.
      firstDate: DateTime(2000),
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

import 'package:flutter/material.dart';

import '../../core/money/sign_convention.dart';
import '../../core/text/masking.dart';
import '../../features/ingestion/review_queue.dart';
import '../../features/ledger/bank_tree.dart';
import '../../features/ledger/transaction_types.dart';
import '../../features/ledger/unparsed_completion.dart';
import '../../features/parsing/partial_extraction.dart';
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
/// 3. **Nothing is pre-filled with a guess** — but everything the parser
///    genuinely *read* is pre-filled (KHA-146). The distinction is the whole
///    of rule 3 and is worth stating precisely, because the rule used to be
///    "everything starts empty" and that turned out to be the product's
///    biggest complaint.
///
/// ## KHA-146 — pre-fill is transcription, not inference
///
/// This is a **restoration of the approved design, not a new feature.**
/// `docs/design.md` S-19 has always read: *"Pre-filled with whatever the
/// parser extracted; remaining fields required"*. P3b-2 shipped this form with
/// the opposite rule written into this very comment ("everything else starts
/// empty"), so the screen contradicted the design it cites, and nobody noticed
/// until a real device made it obvious.
///
/// A message reaches this screen for one of two quite different reasons, and
/// the form treats them differently:
///
///  - **No rule recognised the message at all.** Nothing was extracted, so
///    there is nothing honest to pre-fill and every field starts empty. This
///    is the original behaviour and it is correct.
///  - **A rule matched, extracted several fields, and then failed on one
///    required field.** Until KHA-146 everything it read was thrown away
///    between the parser and this screen, and the user retyped an amount, a
///    merchant and a card the app had already read correctly — on a screen
///    that was *displaying the message those values came from, two inches
///    above the empty boxes*. Now `ReviewQueueItem.partialExtraction` carries
///    them and this form starts from them.
///
/// Nothing here is inferred: every pre-filled value is a substring of the
/// message shown on the same screen, transformed only by the matched rule's
/// declared transforms. And **none of it is a transaction until the user
/// presses Save** — the pre-filled form is still validated, still explicitly
/// confirmed, and the notice at the top says out loud that the app filled
/// these in, so a wrong reading is visible rather than assumed.
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
  /// What the parser read before it gave up, or `null` when it read nothing
  /// (no rule matched). Resolved once here so every initialiser below reads
  /// from one place rather than each re-deriving "is there partial data?".
  PartialExtraction? get _partial => widget.item.partialExtraction;

  late final TextEditingController _amount = TextEditingController(
    // KHA-146. The exact decimal string the message printed, never a
    // re-formatted `double` (ADR-002) — what the user sees in the box is
    // character-for-character what the bank wrote.
    text: _partial?.amountText ?? '',
  );

  /// The message's own currency where it stated one, otherwise the app's base
  /// currency as a **default**. `PartialExtraction` never carries an amount
  /// without a currency (NFR-A5), so this cannot pair a foreign amount with
  /// the base code.
  late final TextEditingController _currency = TextEditingController(
    text: _partial?.currencyCode ?? widget.defaultCurrencyCode,
  );
  late final TextEditingController _merchant = TextEditingController(
    text: _partial?.merchantRawText ?? '',
  );

  /// The instant the message stated, where the parser read one; otherwise when
  /// the message arrived. Both are facts about the message rather than guesses
  /// about the transaction — and the fallback is what the parser itself uses
  /// (`received_at_fallback`). The user can change it.
  late DateTime _occurredAt = _partial?.occurredAtUtc ?? widget.item.receivedAt;

  /// The matched rule's `messageType`, but **only if this build knows it**.
  ///
  /// A rule pack may declare a type this app has never heard of (rule_pack.md
  /// §5.2's forward-compatibility rule), and `DropdownButtonFormField` asserts
  /// that its initial value is one of its items — so an imported pack could
  /// otherwise crash this screen. Unknown type reads as "not stated", which is
  /// the same honest answer the rest of the app gives (AC-B1.3).
  late String? _transactionType = _knownTypeOrNull(_partial?.transactionType);

  /// Derived from the type by exactly the same rule the dropdown's `onChanged`
  /// applies, deliberately: if pre-filling used a different rule, a
  /// pre-selected type and a hand-picked one could produce different signs for
  /// the same transaction — and direction is the ONLY place the sign lives
  /// (`lib/core/money/sign_convention.dart`).
  late String _direction = _directionFor(_transactionType);

  /// The existing account/card the message's identifier resolves to, when it
  /// resolves to exactly one. See [_matchInstrument] for why "exactly one".
  late int? _instrumentId = _matchInstrument();

  /// Whether the user has made their own choice in the instrument picker.
  ///
  /// This exists because [CompleteUnparsedScreen.instruments] arrives from a
  /// **stream** (`bankTreeProvider`), so on a real device the first build of
  /// this screen almost always has an empty list and the list arrives a frame
  /// or two later — a one-shot match at construction would therefore run
  /// against nothing and never pre-select anything, on exactly the path the
  /// user is complaining about. [didUpdateWidget] re-matches when the list
  /// changes; this flag is what stops that re-match from overwriting a
  /// deliberate human choice (including a deliberate "Not stated").
  bool _instrumentChosenByUser = false;

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
  /// **P3b-2: this list now lives in `TransactionType.nonSpendTypes`** rather
  /// than being duplicated here and in the manual-entry form (S-20). design.md
  /// treats the two as one form, and a spend rule that existed in two copies
  /// would eventually be corrected in one of them only — which is precisely
  /// how `transfer_out` came to be wrongly listed here in P3a. See that
  /// constant's doc comment for why it is absent.
  static Set<String> get _nonSpendTypes => TransactionType.nonSpendTypes;

  // --- KHA-146 pre-fill helpers --------------------------------------------

  /// [type] when the dropdown actually offers it, otherwise `null`.
  ///
  /// Guards two real cases, not a hypothetical one: an **imported** rule pack
  /// declaring a type this build predates, and the engine's own `unknown`
  /// placeholder for a rule that declared no type. Both must read as "not
  /// stated" rather than crash the screen or silently select a neighbouring
  /// item.
  static String? _knownTypeOrNull(String? type) =>
      type != null && _types.contains(type) ? type : null;

  /// The sign that goes with a transaction type — one rule, used both for the
  /// pre-filled type and for a type the user picks.
  static String _directionFor(String? type) =>
      TransactionType.creditTypes.contains(type)
      ? MovementDirection.credit
      : MovementDirection.debit;

  /// Digits only, last four — the same reduction `buildInstrumentRefKey` uses,
  /// so `****4821`, `xxxx4821` and `4821` all compare equal. Bank templates
  /// disagree about mask characters; the digits are the stable part.
  static String? _last4(String? maskedIdentifier) {
    if (maskedIdentifier == null) {
      return null;
    }
    final String digits = maskedIdentifier.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return null;
    }
    return digits.length <= 4 ? digits : digits.substring(digits.length - 4);
  }

  /// The id of the one existing instrument the message's identifier names, or
  /// `null`.
  ///
  /// **"Exactly one match, or nothing" is the deliberate rule.** Four digits
  /// are not globally unique (see `instrument_identity.dart`'s honest note on
  /// the residual collision), and this form has none of the extra context the
  /// parser's own resolver has — no bank scoping, because the picker is a flat
  /// list of every instrument the user owns. Pre-selecting one of two
  /// candidates would attach a transaction to the wrong card, quietly, on a
  /// screen the user is skimming. Ambiguity therefore falls back to "Not
  /// stated" plus the [_InstrumentFromMessageHint] below, which shows what the
  /// message said and lets the person choose.
  int? _matchInstrument() {
    final PartialExtraction? partial = _partial;
    final String? kind = partial?.instrumentKind;
    final String? digits = _last4(partial?.instrumentMaskedRef);
    if (kind == null || digits == null) {
      return null;
    }

    final List<InstrumentSummary> matches = <InstrumentSummary>[
      for (final InstrumentSummary summary in widget.instruments)
        if (summary.instrument.kind == kind &&
            _last4(summary.instrument.maskedIdentifier) == digits)
          summary,
    ];
    return matches.length == 1 ? matches.single.instrument.id : null;
  }

  /// True when at least one box on this form was filled in by the app rather
  /// than by the user — which is exactly when the notice at the top must
  /// appear. Derived rather than stored so it cannot fall out of step with
  /// what the fields actually show.
  bool get _hasPrefill =>
      (_partial?.hasAnyValue ?? false) &&
      (_amount.text.isNotEmpty ||
          _merchant.text.isNotEmpty ||
          _transactionType != null ||
          _instrumentId != null ||
          _partial?.occurredAtUtc != null);

  /// Re-runs the instrument match when the account/card list finally arrives.
  ///
  /// Riverpod hands this screen a fresh `List` on every emission, so comparing
  /// by identity would re-match on every rebuild — harmless (the match is pure
  /// and cheap) but noisy. Comparing the resolved match instead means we only
  /// touch state when the answer actually changes.
  @override
  void didUpdateWidget(CompleteUnparsedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_instrumentChosenByUser) {
      return;
    }
    final int? matched = _matchInstrument();
    if (matched != _instrumentId) {
      setState(() => _instrumentId = matched);
    }
  }

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

          // KHA-146. Only rendered when the app actually filled something in.
          // Saying "we read some of this" over a blank form would be worse
          // than saying nothing: it would teach the user to distrust a notice
          // that is usually wrong, and then to ignore it when it is right.
          if (_hasPrefill) ...<Widget>[
            const SizedBox(height: 12),
            const _PrefilledNotice(),
          ],
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
              //
              // KHA-146: `_directionFor` is the same function the pre-fill
              // uses, so a type that arrived from the parser and the same type
              // chosen by hand can never disagree about the sign.
              _direction = _directionFor(value);
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
            onChanged: (int? value) => setState(() {
              _instrumentId = value;
              // From here on the person owns this field — a later emission of
              // the instrument list must not quietly re-pick for them.
              _instrumentChosenByUser = true;
            }),
          ),

          // KHA-146. The message named a card or account, and it resolved to
          // no existing instrument (or to more than one). The form still
          // cannot create an instrument — see the class doc — so the honest
          // thing is to show what the message said instead of dropping it, and
          // let the person map it.
          if (_last4(_partial?.instrumentMaskedRef) case final String last4
              when _instrumentId == null)
            _InstrumentFromMessageHint(last4: last4),
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

/// **KHA-146** — says out loud that the app filled some boxes in.
///
/// This is a money-safety affordance rather than decoration. A form that
/// silently arrives pre-filled invites the user to press Save without reading
/// it, which is how a misread amount becomes a transaction. Naming the
/// pre-fill, and stating that nothing is recorded until Save, keeps the
/// confirmation genuinely explicit — the same reason `_OriginalMessage` sits
/// directly above the fields.
class _PrefilledNotice extends StatelessWidget {
  const _PrefilledNotice();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        // brand.md §7's information tone, not the warning tone: nothing has
        // gone wrong here, the app is reporting what it did.
        color: AppColors.infoTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        l10n.completePrefilledNotice,
        style: text.bodySmall?.copyWith(color: AppColors.ink700),
      ),
    );
  }
}

/// **KHA-146** — the card/account the message named, when it maps to no
/// instrument the user has (or to more than one, ambiguously).
///
/// Shows only the last four digits, formatted by the same helper the rest of
/// the app uses (`•••• 4821`), so this screen cannot become the one place that
/// renders an identifier differently. There is nothing sensitive to leak: the
/// value has been masked to last-4 since ingestion (NFR-S2), and the full
/// message is already on screen above it.
class _InstrumentFromMessageHint extends StatelessWidget {
  final String last4;

  const _InstrumentFromMessageHint({required this.last4});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 6, start: 12, end: 12),
      child: Text(
        l10n.completeInstrumentUnmatched(formatMaskedCardOrAccount(last4)),
        style: text.bodySmall?.copyWith(color: AppColors.ink500),
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

/// Shared presentation pieces for the P3a ledger screens.
///
/// These map 1:1 onto `docs/design.md` §5's component library, keeping the
/// Flutter and (hypothetical) React vocabularies aligned:
///
/// | design.md component | here |
/// |---|---|
/// | `MaskedIdentifier` | [MaskedIdentifierText] |
/// | field row in S-11 | [DetailFieldRow] |
/// | signed amount in `TransactionListItem` | [SignedAmountText] |
/// | period figure on bank/instrument pages | [PeriodTotalsText] |
///
/// ## Two rules every widget in this file obeys
///
/// **NFR-U4 — never colour alone.** A debit is a `−` prefix *and* a semantic
/// label; a credit is `+` *and* a label. Colour reinforces; it never carries
/// the meaning. Everything here stays legible in greyscale, which is what the
/// accessibility audit converts the mockups to.
///
/// **AC-B1.3 — absent is stated, never blank.** [DetailFieldRow] renders the
/// literal words *"Not stated in message"* for a null value. There is no code
/// path in which a missing field produces an empty row the user has to
/// interpret.
library;

import 'package:flutter/material.dart';

import '../../core/money/currency_exponents.dart';
import '../../core/money/money.dart';
import '../../core/text/masking.dart';
import '../../features/ledger/instrument_identity.dart';
import '../../features/ledger/period_totals.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';

/// `•••• 4821` — design.md's `MaskedIdentifier`.
///
/// The value handed in is already masked at the source (NFR-S2); this widget
/// only styles it. It cannot reveal anything, because there is nothing fuller
/// anywhere in the app to reveal (design.md §3.2: *"permanent, not a reveal
/// toggle"*).
class MaskedIdentifierText extends StatelessWidget {
  final String maskedIdentifier;
  final TextStyle? style;

  const MaskedIdentifierText({
    required this.maskedIdentifier,
    this.style,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      formatMaskedCardOrAccount(_digitsOf(maskedIdentifier)),
      style: style,
      // The identifier is digits and bullets: it reads left-to-right even
      // inside an Arabic sentence (design.md §3.1, "mixed-direction content
      // is isolated, not flipped"). Without this, `•••• 4821` renders with
      // the digits on the wrong side under RTL.
      textDirection: TextDirection.ltr,
    );
  }

  /// The stored form is `****4821`; the display form is `•••• 4821`.
  /// `formatMaskedCardOrAccount` expects just the digits, and never receives
  /// anything fuller than four of them.
  static String _digitsOf(String masked) =>
      masked.replaceAll(RegExp(r'[^0-9]'), '');
}

/// One `label / value` row in S-11, with AC-B1.3's explicit-unknown handling.
class DetailFieldRow extends StatelessWidget {
  final String label;

  /// `null` means the source message did not state this. It is rendered as
  /// the literal "Not stated in message" — **never** as an empty string, a
  /// dash, or a zero.
  final String? value;

  /// An optional widget to render instead of [value] when the value is
  /// present (used for the masked identifier, which needs its own direction).
  final Widget? valueWidget;

  const DetailFieldRow({
    required this.label,
    this.value,
    this.valueWidget,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final bool isUnknown = valueWidget == null && value == null;

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // `Expanded` on both sides rather than a fixed label width: at the
          // largest OS font size (NFR-U3) a fixed column truncates Arabic
          // labels, and truncating a field label is how a user ends up
          // guessing what a number means.
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: text.bodySmall?.copyWith(color: AppColors.ink500),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child:
                valueWidget ??
                Text(
                  isUnknown ? l10n.fieldNotStatedInMessage : value!,
                  style: text.bodyMedium?.copyWith(
                    color: isUnknown ? AppColors.ink500 : AppColors.ink900,
                    // Italic is reinforcement only — the words themselves say
                    // it is unknown, so the meaning survives a screen reader
                    // and a greyscale print.
                    fontStyle: isUnknown ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

/// A signed money figure with its non-colour indicators (NFR-U4, design.md
/// §3.3).
///
/// The sign prefix is part of the *text*, and the semantic label ("Debit" /
/// "Credit") is attached for screen readers, so neither meaning depends on
/// the colour.
class SignedAmountText extends StatelessWidget {
  final Money amount;

  /// True for a credit — a refund, income, or an incoming transfer. Credits
  /// **reduce** period spend (US-B7).
  final bool isCredit;

  final TextStyle? style;

  const SignedAmountText({
    required this.amount,
    required this.isCredit,
    this.style,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextStyle base =
        style ?? Theme.of(context).textTheme.titleMedium ?? const TextStyle();

    return Semantics(
      // The label a screen reader announces before the figure, so "45.00 SAR"
      // is never ambiguous about direction.
      label: isCredit ? l10n.txnCreditLabel : l10n.txnDebitLabel,
      child: Text(
        formatSignedAmount(amount, isCredit: isCredit),
        style: base.copyWith(
          // Deliberately NOT red for a debit — brand.md §2.3: colouring the
          // majority case red is a false alarm.
          color: isCredit ? AppColors.success : AppColors.ink900,
          fontWeight: FontWeight.w700,
        ),
        textDirection: TextDirection.ltr,
      ),
    );
  }
}

/// `−45.00 SAR` / `+45.00 SAR`.
///
/// AC-B1.4 — *"the amount matches the amount in the source SMS exactly,
/// including decimal precision, with no rounding"* — is satisfied by there
/// being no arithmetic, no formatting library and no float anywhere between
/// the database and this string. The only transformation applied is the one
/// [formatAmountDigits] documents below.
String formatSignedAmount(Money amount, {required bool isCredit}) {
  final String sign = isCredit ? '+' : '−';
  return '$sign${formatAmountDigits(amount)} ${amount.currencyCode}';
}

/// The digits of [amount], padded to its currency's minor-unit width.
///
/// ## Why padding is needed, and why it is not rounding
///
/// [Money] is backed by an arbitrary-precision `Decimal`, for which `1500.00`
/// and `1500` are *the same value* — so a message printing `SAR 1,500.00`
/// stores, and canonicalises back to, `1500`. That is correct arithmetic and
/// it is what the parser corpus pins. It is the wrong thing to **show**: a
/// bank SMS says `1,500.00`, and rendering `1500` invites the user to wonder
/// whether something was lost.
///
/// So this pads the fraction out to the currency's own exponent (SAR/USD 2,
/// KWD 3, JPY 0). It never truncates: an amount carrying *more* precision
/// than its currency's minor unit — a rate-derived figure, or a bank printing
/// three decimals on a two-decimal currency — is shown in full. Padding adds
/// zeros; it can never change a value, which is exactly the property AC-B1.4
/// needs.
String formatAmountDigits(Money amount) {
  final String canonical = amount.toCanonicalString();
  final int exponent = minorUnitExponentFor(amount.currencyCode);
  if (exponent == 0) {
    return canonical;
  }

  final int separator = canonical.indexOf('.');
  if (separator < 0) {
    return '$canonical.${'0' * exponent}';
  }

  final int fractionLength = canonical.length - separator - 1;
  if (fractionLength >= exponent) {
    return canonical;
  }
  return canonical + '0' * (exponent - fractionLength);
}

/// A period figure, one line per currency.
///
/// Multiple lines rather than one converted number, because ADR-009 forbids
/// inventing a rate and KHA-27 owns conversion. "1,240.00 SAR and 45.00 USD"
/// is honest; a single blended figure would not be.
class PeriodTotalsText extends StatelessWidget {
  final PeriodTotals totals;
  final TextStyle? style;

  const PeriodTotalsText({required this.totals, this.style, super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    if (totals.isEmpty) {
      // Not "0.00". Zero would claim the user spent nothing; this says we
      // have nothing to show for the period, which is a different fact.
      return Text(
        l10n.totalsNoneForPeriod,
        style: text.bodySmall?.copyWith(color: AppColors.ink500),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final CurrencyTotal total in totals.byCurrency)
          Text(
            formatSignedAmount(total.net.abs, isCredit: total.net.isNegative),
            style:
                style ??
                text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            textDirection: TextDirection.ltr,
          ),
      ],
    );
  }
}

/// Localised label for a rule pack `messageType`.
///
/// An unrecognised type falls through to "Not specified" rather than being
/// hidden: §5.2's compatibility rules allow a newer imported pack to
/// introduce a type this build has never heard of, and showing the user
/// *something* beats showing them a blank row.
String transactionTypeLabel(AppLocalizations l10n, String type) =>
    switch (type) {
      'pos_purchase' => l10n.txnTypePosPurchase,
      'online_purchase' => l10n.txnTypeOnlinePurchase,
      'transfer_out' => l10n.txnTypeTransferOut,
      'transfer_in' => l10n.txnTypeTransferIn,
      'bill_payment' => l10n.txnTypeBillPayment,
      'card_repayment' => l10n.txnTypeCardRepayment,
      'fee' => l10n.txnTypeFee,
      'installment' => l10n.txnTypeInstallment,
      'account_debit' => l10n.txnTypeAccountDebit,
      'refund' => l10n.txnTypeRefund,
      'withdrawal' => l10n.txnTypeWithdrawal,
      _ => l10n.txnTypeUnknown,
    };

/// Localised label for an instrument kind (AC-B13.1/2).
String instrumentKindLabel(AppLocalizations l10n, String kind) =>
    switch (kind) {
      InstrumentKind.card => l10n.instrumentKindCard,
      _ => l10n.instrumentKindAccount,
    };

/// A short, locale-independent date/time rendering.
///
/// Full localised formatting arrives with the reporting work in P5; pulling a
/// formatting dependency in here for one line would be scope this PR has no
/// business taking. `null` renders as AC-B1.3's explicit unknown at the call
/// site, not here.
String formatShortDateTime(DateTime value) =>
    value.toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ');

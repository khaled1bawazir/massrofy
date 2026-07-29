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
import '../../core/money/exchange_rate.dart';
import '../../core/money/money.dart';
import '../../core/text/masking.dart';
import '../../core/time/clock.dart';
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

/// A period figure: the base-currency headline, and — when something could
/// not be converted — an explicit line saying so.
///
/// ## Why the incompleteness line is not optional
///
/// KHA-27 gives this widget a single base-currency number to show, which is
/// what AC-B9.2 asks for. ADR-009 attaches a condition to that number: a
/// transaction whose message stated no rate is **excluded** from it, and the
/// user must be told, because *"reconciliation is visibly incomplete rather
/// than silently wrong"*. A total that quietly omits a purchase is worse than
/// one that admits it is incomplete — so the omission is rendered from
/// [PeriodTotals.unconverted] rather than left to a caller to remember.
///
/// The unconverted currencies are also shown as exact figures in their own
/// currency. The user's money did not stop existing because the app has no
/// rate for it.
class PeriodTotalsText extends StatelessWidget {
  final PeriodTotals totals;
  final TextStyle? style;

  /// What the figure *means*, which decides its sign prefix.
  ///
  /// This is not decoration. The same `PeriodTotals` shape carries spend,
  /// income, cash withdrawn and internal transfers ([PeriodReport]), and all
  /// four hold a **positive** net. Rendering them all with the spend
  /// convention would print a salary of 14,500 SAR as *"−14,500.00 SAR"* —
  /// a figure that says the exact opposite of the truth. So the caller states
  /// which it is, and there is no default that silently works for one kind
  /// and lies about the others.
  final TotalsSign sign;

  const PeriodTotalsText({
    required this.totals,
    this.style,
    this.sign = TotalsSign.spend,
    super.key,
  });

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

    final TextStyle? headlineStyle =
        style ?? text.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    final Money? base = totals.base;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (base != null)
          Text(
            _format(base),
            style: headlineStyle,
            textDirection: TextDirection.ltr,
          ),
        // Everything the base figure leaves out, in its own currency.
        for (final UnconvertedGroup group in totals.unconverted)
          Text(
            _format(group.net),
            style: base == null
                ? headlineStyle
                : text.bodySmall?.copyWith(color: AppColors.ink700),
            textDirection: TextDirection.ltr,
          ),
        if (totals.isIncomplete)
          Text(
            l10n.totalsNotConverted(totals.unconvertedCount),
            style: text.bodySmall?.copyWith(color: AppColors.ink500),
          ),
      ],
    );
  }

  /// `.abs` with the sign supplied separately keeps the `+`/`−` prefix rule
  /// in one function (NFR-U4) instead of letting a minus sign leak out of
  /// `Money`'s own formatting and bypass the icon/label pairing.
  ///
  /// A *net* that has gone negative flips the prefix — a month of more
  /// refunds than purchases genuinely was money in, and printing it as "−"
  /// would be wrong in the other direction.
  String _format(Money value) => switch (sign) {
    TotalsSign.none => '${formatAmountDigits(value.abs)} ${value.currencyCode}',
    TotalsSign.spend => formatSignedAmount(
      value.abs,
      isCredit: value.isNegative,
    ),
    TotalsSign.credit => formatSignedAmount(
      value.abs,
      isCredit: !value.isNegative,
    ),
  };
}

/// How a [PeriodTotalsText] figure should be signed.
enum TotalsSign {
  /// Money out. A positive net renders as `−`.
  spend,

  /// Money in — income. A positive net renders as `+`.
  credit,

  /// Neither: an internal transfer or a cash withdrawal. **No prefix at
  /// all**, exactly as design.md §3.3 specifies for the internal-transfer
  /// row, because a sign would claim it belongs on one side of the ledger.
  none,
}

/// design.md §3.3's non-colour indicator for a movement that is **neither
/// spend nor income** — an internal transfer (AC-B11.1) or an unproven
/// candidate for one (AC-B11.2).
///
/// The design spec is specific about this row: *"a bidirectional-arrow icon +
/// label 'Internal transfer' / 'تحويل داخلي'; no +/− prefix at all"*. The
/// icon and the words carry the meaning; colour only reinforces, so the
/// distinction survives greyscale and a screen reader (NFR-U4).
class InternalTransferBadge extends StatelessWidget {
  /// True for a proven internal transfer, false for a candidate.
  final bool isConfirmed;

  const InternalTransferBadge({required this.isConfirmed, super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String label = isConfirmed
        ? l10n.txnBadgeInternalTransfer
        : l10n.txnBadgeInternalTransferCandidate;
    final Color foreground = isConfirmed
        ? AppColors.ink700
        : AppColors.warningText;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: isConfirmed ? AppColors.ink100 : AppColors.secondaryTint10,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            isConfirmed ? Icons.swap_horiz : Icons.help_outline,
            size: 14,
            color: foreground,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: foreground),
          ),
        ],
      ),
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
      'salary_income' => l10n.txnTypeSalaryIncome,
      _ => l10n.txnTypeUnknown,
    };

/// The words for an [ExchangeRateSource] — AC-B9.3's *"the user can inspect
/// where this rate came from"*.
String fxRateSourceLabel(AppLocalizations l10n, ExchangeRateSource source) =>
    switch (source) {
      ExchangeRateSource.smsImplied => l10n.txnFxSourceSmsImplied,
      ExchangeRateSource.smsStated => l10n.txnFxSourceSmsStated,
      ExchangeRateSource.user => l10n.txnFxSourceUser,
      ExchangeRateSource.carriedForward => l10n.txnFxSourceCarriedForward,
    };

/// Localised label for an instrument kind (AC-B13.1/2).
String instrumentKindLabel(AppLocalizations l10n, String kind) =>
    switch (kind) {
      InstrumentKind.card => l10n.instrumentKindCard,
      _ => l10n.instrumentKindAccount,
    };

/// A short, locale-independent date/time rendering.
///
/// Kept for the dense field lists (S-11's detail rows, the audit trail), where
/// an unambiguous machine-shaped timestamp is what a person cross-checking a
/// figure against their bank's SMS actually wants. Lists use
/// [formatLocalizedDateTime] instead. `null` renders as AC-B1.3's explicit
/// unknown at the call site, not here.
String formatShortDateTime(DateTime value) =>
    value.toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ');

/// A **localised** date and time, for list rows (P5a).
///
/// ## Where this comes from, and why it needs no new dependency
///
/// P3a's note here said full localised formatting would arrive "with the
/// reporting work in P5", assuming a `package:intl` dependency. It does not
/// need one: `GlobalMaterialLocalizations` — already installed, because the app
/// declares it in `localizationsDelegates` for Arabic and English — carries
/// `formatMediumDate` and `formatTimeOfDay`, both fully localised, including
/// Arabic month names and the Arabic date order.
///
/// `alwaysUse24HourFormat` is read from `MediaQuery` rather than hard-coded, so
/// the row follows the user's own OS clock setting. Someone whose phone shows
/// 14:20 should not read 2:20 PM in their spending list.
String formatLocalizedDateTime(BuildContext context, DateTime value) {
  final MaterialLocalizations materialL10n = MaterialLocalizations.of(context);
  final DateTime local = value.toLocal();
  final String date = materialL10n.formatMediumDate(local);
  final String time = materialL10n.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  return '$date · $time';
}

/// A localised "July 2026" for the period selector (AC-E1.4).
///
/// Takes the period's **start instant** and shifts it into Riyadh wall-clock
/// time before naming it. That step is not cosmetic: a Riyadh calendar month
/// starts at 21:00 UTC on the last day of the *previous* month (see
/// `RiyadhCalendar.monthWindowUtc`), so labelling the raw UTC instant would
/// title July's figures "June".
String formatPeriodMonthLabel(BuildContext context, DateTime periodStartUtc) =>
    MaterialLocalizations.of(
      context,
    ).formatMonthYear(RiyadhCalendar.toRiyadhWallClock(periodStartUtc));

import 'package:flutter/material.dart';

import '../../features/ledger/bank_tree.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/ledger_widgets.dart';

/// **S-21 — Banks List.** Mockup: `docs/mockups/banks.html`.
/// KHA-23, US-B2, US-B12, AC-B2.1, AC-B12.1.
///
/// Each bank with its own combined figure for the period; tapping one drills
/// into [BankDetailScreen], which shows **only that bank's** instruments —
/// the second half of AC-B2.1. The tree is built by `BankTreeBuilder`, so the
/// "only its own" part is a property of the data structure rather than of a
/// query this screen has to get right.
///
/// ## The empty state says what the product promises
///
/// Before any SMS has been seen there are no banks, and the copy says a bank
/// appears *automatically* the first time a message arrives (US-B15,
/// AC-B15.1). That is the one thing a user needs to know here: there is
/// nothing for them to set up, and an empty list is not a broken app.
class BanksScreen extends StatelessWidget {
  final List<BankTreeNode> banks;
  final void Function(BankTreeNode bank) onOpenBank;

  const BanksScreen({required this.banks, required this.onOpenBank, super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(l10n.banksTitle)),
      body: banks.isEmpty
          ? const _BanksEmptyState()
          : ListView.builder(
              padding: const EdgeInsetsDirectional.all(16),
              itemCount: banks.length,
              itemBuilder: (BuildContext context, int index) =>
                  _BankListItem(node: banks[index], onTap: onOpenBank),
            ),
    );
  }
}

class _BanksEmptyState extends StatelessWidget {
  const _BanksEmptyState();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.account_balance_outlined,
              size: 44,
              color: AppColors.ink300,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.banksEmptyTitle,
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.banksEmptyBody,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: AppColors.ink500),
            ),
          ],
        ),
      ),
    );
  }
}

class _BankListItem extends StatelessWidget {
  final BankTreeNode node;
  final void Function(BankTreeNode) onTap;

  const _BankListItem({required this.node, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    // The locale drives which of the two stored display names is shown —
    // design.md §3.1's Arabic-first rule applies to bank names too, and a
    // bank labelled in the wrong script is a bank the user has to translate
    // in their head every time.
    final String languageCode = Localizations.localeOf(context).languageCode;

    // `Material` rather than a `Container` with a background colour: a
    // `ListTile` paints its ink splash on the nearest `Material` ancestor, so
    // a decorated box in between would swallow the touch feedback (Flutter
    // asserts on exactly this). The card's border comes from the tile's own
    // `shape` for the same reason.
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 12),
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          onTap: () => onTap(node),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.ink100),
          ),
          contentPadding: const EdgeInsetsDirectional.symmetric(
            horizontal: 14,
            vertical: 6,
          ),
          title: Text(
            node.bank.displayName(languageCode),
            style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            // Two ICU plurals joined by a translatable separator, so neither
            // language ever renders "1 accounts" and Arabic gets its own
            // dual/few/many forms.
            l10n.bankInstrumentsSummary(
              l10n.bankAccountsCount(node.accounts.length),
              l10n.bankCardsCount(node.cards.length),
            ),
            style: text.bodySmall?.copyWith(color: AppColors.ink500),
          ),
          trailing: PeriodTotalsText(
            totals: node.totals,
            style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

/// **S-22 — Bank Detail.** Mockup: `docs/mockups/banks.html`.
/// AC-B2.1, AC-B2.2, AC-B12.2, AC-B13.3.
///
/// ## Why accounts and cards get a segmented control, not one list
///
/// AC-B13.3 requires account activity and card activity to be
/// *distinguishable, not merged into one undifferentiated list*, and US-B13
/// explains why it matters: "money sitting in my account" and "credit card
/// spend" are different things, and a single list of both invites the user to
/// add them together. The data already arrives as two collections
/// ([BankTreeNode.accounts] and [BankTreeNode.cards]), so this screen cannot
/// merge them even by accident.
class BankDetailScreen extends StatefulWidget {
  final BankTreeNode node;
  final void Function(InstrumentSummary instrument) onOpenInstrument;

  const BankDetailScreen({
    required this.node,
    required this.onOpenInstrument,
    super.key,
  });

  @override
  State<BankDetailScreen> createState() => _BankDetailScreenState();
}

class _BankDetailScreenState extends State<BankDetailScreen> {
  /// 0 = accounts, 1 = cards. Accounts lead because the account is what funds
  /// the cards (US-B14), so it is the top of the hierarchy the user is
  /// looking at.
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final String languageCode = Localizations.localeOf(context).languageCode;
    final BankTreeNode node = widget.node;

    final List<InstrumentSummary> visible = _segment == 0
        ? node.accounts
        : node.cards;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(node.bank.displayName(languageCode))),
      body: ListView(
        padding: const EdgeInsetsDirectional.all(16),
        children: <Widget>[
          // AC-B12.2's "combined total for that bank" — computed from exactly
          // the transactions of exactly this bank's instruments, so it always
          // equals the sum of the per-instrument figures below (NFR-A6).
          Text(
            l10n.bankTotalThisPeriod,
            style: text.bodySmall?.copyWith(color: AppColors.ink500),
          ),
          const SizedBox(height: 4),
          PeriodTotalsText(totals: node.totals, style: text.headlineSmall),
          const SizedBox(height: 16),
          SegmentedButton<int>(
            segments: <ButtonSegment<int>>[
              ButtonSegment<int>(
                value: 0,
                label: Text(l10n.bankAccountsSection(node.accounts.length)),
              ),
              ButtonSegment<int>(
                value: 1,
                label: Text(l10n.bankCardsSection(node.cards.length)),
              ),
            ],
            selected: <int>{_segment},
            onSelectionChanged: (Set<int> selection) =>
                setState(() => _segment = selection.first),
          ),
          const SizedBox(height: 12),
          if (node.hasNoInstruments)
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 24),
              child: Text(
                l10n.bankNoInstruments,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: AppColors.ink500),
              ),
            )
          else
            for (final InstrumentSummary summary in visible)
              InstrumentTile(
                summary: summary,
                onTap: () => widget.onOpenInstrument(summary),
              ),
        ],
      ),
    );
  }
}

/// One account or card row — design.md's `AccountTile` / `CardTile`.
///
/// **AC-B15.2** is the interesting part: an auto-created instrument the user
/// has not renamed is labelled by its masked identifier and captioned "Not
/// named yet", so it stays identifiable without pretending to have a name.
class InstrumentTile extends StatelessWidget {
  final InstrumentSummary summary;
  final VoidCallback onTap;

  const InstrumentTile({required this.summary, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    // See `_BankListItem` for why this is a `Material` and not a decorated
    // `Container`.
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 10),
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          onTap: onTap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.ink100),
          ),
          contentPadding: const EdgeInsetsDirectional.symmetric(
            horizontal: 14,
            vertical: 4,
          ),
          title: summary.isUnnamed
              ? MaskedIdentifierText(
                  maskedIdentifier: summary.instrument.maskedIdentifier,
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                )
              : Text(
                  summary.label,
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
          subtitle: Text(
            summary.isUnnamed
                // The caption, not the label: the masked identifier above is
                // already doing the identifying.
                ? l10n.instrumentUnnamed
                : '${instrumentKindLabel(l10n, summary.instrument.kind)} · '
                      '${summary.instrument.maskedIdentifier}',
            style: text.bodySmall?.copyWith(color: AppColors.ink500),
          ),
          trailing: PeriodTotalsText(
            totals: summary.totals,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

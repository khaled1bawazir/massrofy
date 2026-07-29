/// **The categorization component library** — design.md §5's `CategoryChip`,
/// plus the confidence and needs-review indicators KHA-32 requires.
///
/// Everything here is a `StatelessWidget` over plain values with **no
/// provider, no database and no async**, exactly like `ledger_widgets.dart`.
/// That is what lets the widget tests render each state directly, and it is
/// what keeps these components usable from four different screens without any
/// of them owning the data.
///
/// ## The rule every indicator in this file follows: icon AND word (NFR-U4)
///
/// design.md §3.3 is a table of state → *"non-colour indicator"*, and the entry
/// for a flagged row reads: *"a flag icon **and the literal words** 'Needs
/// review', never a bare coloured dot"*. Every widget below carries its meaning
/// in an icon plus text, so the screen survives greyscale, colour-vision
/// differences and a screen reader. Colour is added on top; it never carries
/// the message on its own.
///
/// ## A note for readers new to Flutter
///
/// A `StatelessWidget` is a description of a piece of UI: Flutter calls
/// `build` whenever the inputs change and rebuilds from scratch. There is no
/// mutable state to keep in sync — the widget *is* a function of its fields,
/// which is why these can be constructed freely, `const`-ed, and dropped into
/// any screen. `EdgeInsetsDirectional` (rather than `EdgeInsets`) is used
/// throughout so padding mirrors automatically under Arabic RTL (design.md
/// §3.1) without any screen writing a direction check.
library;

import 'package:flutter/material.dart';

import '../../features/categorization/categories.dart';
import '../../features/categorization/learned_rules.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';

/// Maps design.md §4's Material Symbols token to the icon Flutter bundles.
///
/// design.md §4 names each category's icon as a semantic Material Symbols
/// identifier (`shopping_cart`, `restaurant`, …) so the HTML mockups and the
/// Flutter app can agree on one vocabulary. Flutter ships those glyphs as
/// vector icon data in `Icons`, so this is a lookup rather than a font load.
///
/// **Unknown tokens fall back to a neutral label icon rather than throwing.**
/// A category the user created carries whatever token the picker offered, and
/// a future token added to design.md must not be able to crash every screen
/// that renders a chip. The same forward-compatibility posture
/// `CategoryGroup.fromKey` takes for an unknown group.
IconData categoryIconFor(String? iconToken) => switch (iconToken) {
  'shopping_cart' => Icons.shopping_cart_outlined,
  'restaurant' => Icons.restaurant_outlined,
  'directions_car' => Icons.directions_car_outlined,
  'bolt' => Icons.bolt_outlined,
  'shopping_bag' => Icons.shopping_bag_outlined,
  'movie' => Icons.movie_outlined,
  'medical_services' => Icons.medical_services_outlined,
  'account_balance' => Icons.account_balance_outlined,
  'receipt_long' => Icons.receipt_long_outlined,
  'help_outline' => Icons.help_outline,
  'payments' => Icons.payments_outlined,
  'local_atm' => Icons.local_atm_outlined,
  'sync_alt' => Icons.sync_alt_outlined,
  'label' => Icons.label_outline,
  _ => Icons.label_outline,
};

/// The icon tokens offered by the inline "+ New category" form (§6.5).
///
/// A short list on purpose: the form is an *inline row inside a bottom sheet*,
/// not a screen, and a full icon browser would defeat the design's whole
/// point. These are the design §4 tokens that read as generic rather than as
/// one specific category's identity.
const List<String> newCategoryIconTokens = <String>[
  'label',
  'shopping_cart',
  'restaurant',
  'directions_car',
  'bolt',
  'shopping_bag',
  'movie',
  'medical_services',
  'account_balance',
  'receipt_long',
  'payments',
];

/// A category's name in the reader's language.
///
/// Chosen from the ambient locale rather than from a stored "current language"
/// setting, so a category renders in Arabic on an Arabic device and English on
/// an English one with no per-screen branching. Custom categories carry the
/// same string in both fields (the user typed one name), so this is a no-op
/// for them.
String categoryName(BuildContext context, Category category) =>
    Localizations.localeOf(context).languageCode == 'ar'
    ? category.nameAr
    : category.nameEn;

/// **design.md §5's `CategoryChip`** — a tappable pill showing a transaction's
/// category, and the entry point to the correction flow (§6.1).
///
/// Tapping it is *tap 1* of the two-tap correction: it opens the
/// `CategoryPickerSheet` over the current screen. When [onTap] is null the chip
/// is a read-only label — used where there is no write path (a locked session,
/// a deleted transaction), and never rendered as a dead button.
class CategoryChip extends StatelessWidget {
  final Category category;

  /// How the category got there. Drives the *"Auto"* caption (design.md §3.3's
  /// *"Auto: {rule}"* row) and the low-confidence treatment.
  final ConfidenceBand band;

  final VoidCallback? onTap;

  /// Renders the chip at list-row scale rather than detail-header scale.
  final bool compact;

  const CategoryChip({
    required this.category,
    this.band = ConfidenceBand.userChosen,
    this.onTap,
    this.compact = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool uncertain = band == ConfidenceBand.low;

    final Widget content = Container(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 3 : 6,
      ),
      decoration: BoxDecoration(
        color: uncertain ? AppColors.secondaryTint10 : AppColors.ink100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: uncertain ? AppColors.warningFill : AppColors.ink300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            categoryIconFor(category.iconToken),
            size: compact ? 13 : 16,
            color: uncertain ? AppColors.warningText : AppColors.ink700,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              categoryName(context, category),
              overflow: TextOverflow.ellipsis,
              style: (compact ? text.bodySmall : text.bodyMedium)?.copyWith(
                color: uncertain ? AppColors.warningText : AppColors.ink900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // design.md §3.3, "Auto-categorized by rule": a sparkle/auto icon
          // plus a caption. The icon alone would be decoration; paired with
          // the band it is the difference between "you chose this" and "we
          // guessed this", which is the whole point of showing it.
          if (band == ConfidenceBand.confident) ...<Widget>[
            const SizedBox(width: 4),
            Icon(
              Icons.auto_awesome_outlined,
              size: compact ? 11 : 13,
              color: AppColors.ink500,
              // Announced rather than left as decoration, so the "this was
              // automatic" fact reaches a screen-reader user too.
              semanticLabel: AppLocalizations.of(context).categoryAutoApplied,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }
    // No key on the `InkWell`: the *caller* keys the chip (see
    // `needs_review_screen.dart`, which keys it per transaction id), and a
    // constant key here would be duplicated the moment two chips sat under one
    // parent.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: content,
    );
  }
}

/// **KHA-32's confidence display** — how sure the app was, in words.
///
/// Deliberately shows the band **and** the raw figure. The band is the part a
/// person can act on; the number is what makes the app auditable to someone who
/// wants to check it, and hiding it would sit oddly beside an audit trail this
/// product otherwise exposes in full.
///
/// Nothing at all is rendered for [ConfidenceBand.userChosen]: printing
/// "100%" beside a category the user typed themselves would be the app
/// congratulating itself on a fact it did not establish.
class ConfidenceIndicator extends StatelessWidget {
  final ConfidenceBand band;
  final double? confidence;

  const ConfidenceIndicator({required this.band, this.confidence, super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    if (band == ConfidenceBand.userChosen) {
      return const SizedBox.shrink();
    }

    final (IconData icon, String label, Color colour) = switch (band) {
      ConfidenceBand.confident => (
        Icons.verified_outlined,
        l10n.categoryConfidenceHigh,
        AppColors.success,
      ),
      ConfidenceBand.low => (
        Icons.help_outline,
        l10n.categoryConfidenceLow,
        AppColors.warningText,
      ),
      // `none` and `userChosen` (returned above) share this arm because Dart
      // requires the switch to be exhaustive; only `none` can reach it.
      _ => (Icons.help_outline, l10n.categoryConfidenceNone, AppColors.ink500),
    };

    return Row(
      key: const Key('confidenceIndicator'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: colour),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            // The percentage is appended only when there is one. A row with no
            // candidate at any tier has no meaningful figure, and printing
            // "0%" would read as "we are certain it is nothing".
            confidence == null || confidence == 0
                ? label
                : l10n.categoryConfidenceWithValue(
                    label,
                    (confidence! * 100).round(),
                  ),
            style: text.bodySmall?.copyWith(color: colour),
          ),
        ),
      ],
    );
  }
}

/// **design.md §3.3's "Needs review" row** — a flag icon plus the literal
/// words, never a bare coloured dot.
///
/// The [reviewReason] is turned into the *question the app is actually asking*
/// rather than a status. `CategoryReviewReason` distinguishes three of them on
/// purpose (see `category_fields.dart`), and collapsing them here would make
/// the inbox say the wrong sentence about half its rows.
class NeedsReviewBadge extends StatelessWidget {
  final String? reviewReason;

  const NeedsReviewBadge({this.reviewReason, super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('needsReviewBadge'),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: AppColors.secondaryTint10,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.flag_outlined,
            size: 13,
            color: AppColors.warningText,
          ),
          const SizedBox(width: 4),
          Text(
            l10n.txnBadgeNeedsReview,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.warningText),
          ),
        ],
      ),
    );
  }
}

/// The plain-language question behind a categorizer review flag.
///
/// Kept as a free function rather than a widget so the review inbox can put it
/// in a card heading, a subtitle or a semantics label without three widgets
/// disagreeing about the wording.
String categoryReviewQuestion(
  AppLocalizations l10n,
  String? reason,
) => switch (reason) {
  CategoryReviewReason.unknownMerchant => l10n.reviewReasonUnknownMerchant,
  CategoryReviewReason.noRuleForMerchant => l10n.reviewReasonNoRuleForMerchant,
  CategoryReviewReason.lowConfidenceCategory => l10n.reviewReasonLowConfidence,
  _ => l10n.reviewReasonGeneric,
};

/// design.md §5's `EmptyState`, in the reassuring tone S-18 asks for.
///
/// Shared by the review inbox, the learned-rules screen and the category list
/// so *"nothing here"* looks the same everywhere — three copies of an
/// `if (isEmpty)` is three chances for one of them to render a blank screen.
class CategoryEmptyState extends StatelessWidget {
  final IconData icon;
  final String headline;
  final String body;
  final Color iconColor;

  const CategoryEmptyState({
    required this.icon,
    required this.headline,
    required this.body,
    this.iconColor = AppColors.ink300,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44, color: iconColor),
            const SizedBox(height: 12),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: AppColors.ink500),
            ),
          ],
        ),
      ),
    );
  }
}

/// The **loading** and **error** halves of design.md §3.4's baseline states,
/// as one widget so no screen has to write them twice.
///
/// `AsyncValue.when` is the Riverpod idiom, and every screen in this build
/// renders all three arms. The error arm never falls back to an empty list:
/// *"a failed read must never render as '0.00' — a zero the user believes is
/// worse than an error they can act on"* (the note P3b-1 left on the home
/// screen, applied to lists as well as to figures).
class CategorySectionError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const CategorySectionError({required this.message, this.onRetry, super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.report_gmailerrorred_outlined,
              size: 40,
              color: AppColors.error,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.error),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('categorySection.retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.commonRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// design.md §3.4's **Locked** state, for any categorization screen reached
/// while the session is not unlocked.
///
/// It should never appear in practice — `app.dart`'s gateway renders the lock
/// gate instead of any screen — but a screen that could render *nothing* while
/// locked would be indistinguishable from a screen with no data, and ADR-005's
/// guarantee deserves to be visible rather than inferred.
class CategoryLockedState extends StatelessWidget {
  const CategoryLockedState({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return CategoryEmptyState(
      key: const Key('categoryLockedState'),
      icon: Icons.lock_outline,
      headline: l10n.lockGateUnlockToView,
      body: l10n.categoryLockedBody,
    );
  }
}

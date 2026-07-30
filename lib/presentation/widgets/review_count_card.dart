/// **design.md §5's `ReviewCountCard`, and AC-C4.2** — *"the count of items
/// needing review is visible from the main screen."*
///
/// Built in P4b on `HomePlaceholderScreen`; moved here unchanged in P5a when
/// that placeholder was replaced by the real S-08 dashboard. It lives in
/// `widgets/` rather than inside `home_screen.dart` for the reason the move
/// exposed: the last screen it was embedded in was deleted, and an AC that can
/// only be met by one screen's private class disappears with that screen.
///
/// ## Two visual states, and the difference is the point
///
/// At zero it says *"All caught up"* and **recedes**; above zero it carries the
/// flag icon, the count and a tap target. A queue that shouted at you about
/// being empty would train you to ignore it, which is exactly what you must not
/// do to a review queue in a money app.
///
/// Renders all four of design.md §3.4's states: loading (a spinner, not a "0"
/// the user would believe), error (an honest message, again not a zero),
/// locked/empty (the reassuring state — while locked every source
/// `reviewCountsProvider` composes yields nothing, which is the truthful value:
/// with no key there is no database to count).
///
/// ## KHA-144 — the state this widget was *wrongly* rendering
///
/// Nothing changed in this file's structure for KHA-144; the defect was in the
/// number handed to it. It is recorded here anyway because this widget is where
/// the damage showed: with 833 real messages waiting in the Needs Review queue,
/// `counts.total` was 0, so the card took its `clear` branch — the reassuring
/// tone, the success icon, *"All caught up"*, and `onTap: null`. The one screen
/// meant to answer "what is going on?" said "nothing", and could not even be
/// tapped to prove otherwise. See `categorization_providers.dart` for the fix.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../providers/categorization_providers.dart';
import '../screens/categorization_routes.dart';
import '../theme/app_colors.dart';

class ReviewCountCard extends ConsumerWidget {
  const ReviewCountCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ReviewCounts> countsAsync = ref.watch(
      reviewCountsProvider,
    );

    return countsAsync.when(
      loading: () => const Padding(
        key: Key('home.reviewCount.loading'),
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      // A failed read must never render as "0 need review" — a reassuring zero
      // the user believes is worse than an error they can act on. Same rule the
      // month total follows for a figure.
      error: (Object error, StackTrace stackTrace) => Text(
        key: const Key('home.reviewCount.error'),
        l10n.reviewCountUnavailable,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.error),
      ),
      data: (ReviewCounts counts) {
        final bool clear = counts.total == 0;
        return InkWell(
          key: const Key('home.reviewCount'),
          onTap: clear ? null : () => openNeedsReview(context),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsetsDirectional.all(14),
            decoration: BoxDecoration(
              color: clear ? AppColors.surface : AppColors.secondaryTint10,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: clear ? AppColors.ink100 : AppColors.warningFill,
              ),
            ),
            child: Row(
              children: <Widget>[
                // NFR-U4: icon AND words, never a bare coloured dot.
                Icon(
                  clear ? Icons.task_alt : Icons.flag_outlined,
                  color: clear ? AppColors.success : AppColors.warningText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        key: const Key('home.reviewCount.headline'),
                        clear
                            ? l10n.reviewCountAllClear
                            : l10n.reviewCountNeedsReview(counts.total),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: clear
                              ? AppColors.ink700
                              : AppColors.warningText,
                        ),
                      ),
                      if (!clear) ...<Widget>[
                        const SizedBox(height: 2),
                        // The breakdown, because "9 items" with no explanation
                        // is a number the user cannot act on.
                        //
                        // **KHA-144.** The two figures are an exact partition
                        // of the headline — `unparsed + needingAttention ==
                        // total`, with no overlap — so a user can add them up
                        // and get the number above. The previous breakdown
                        // showed two *overlapping* figures that never summed to
                        // the headline, and omitted the unparsed queue entirely
                        // (which on the reporting device was all 833 of them).
                        Text(
                          key: const Key('home.reviewCount.breakdown'),
                          l10n.reviewCountBreakdown(
                            counts.unparsed,
                            counts.needingAttention,
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.ink700),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!clear) const Icon(Icons.chevron_right),
              ],
            ),
          ),
        );
      },
    );
  }
}

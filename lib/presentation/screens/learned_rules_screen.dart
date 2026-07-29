/// **S-16 — Learned (Merchant) Rules** and **S-17 — Edit a rule**. Mockup:
/// `docs/mockups/categories-rules.html`. KHA-34, covering AC-D4.1 through
/// AC-D4.4.
///
/// ## Why this screen exists at all, in the issue's own words
///
/// > *"Without this screen, a bad rule can only be undone by correcting
/// > transaction after transaction — exactly the tedium the product exists to
/// > eliminate."*
///
/// So the screen is the *inverse* of the learning loop: everything the app
/// inferred from the user's corrections, listed, editable and deletable in one
/// place. A learning system the user cannot inspect is a system they cannot
/// trust with a ledger.
///
/// ## AC-D4.4 is a question, and the answer changes history
///
/// Editing a rule's category always changes what **future** transactions get
/// (AC-D4.2). Whether it also rewrites **past** ones is the user's call, and
/// S-17 asks it explicitly: *"Also re-apply to this merchant's existing
/// transactions? \[Yes, N\] \[No, going forward only\]"*.
///
/// The prompt is not decorative. Re-applying rewrites categorization on records
/// that are already in last month's figures, so:
///
///  - the **N is computed before the dialog opens**, so the button cannot
///    promise a number the write does not deliver;
///  - the write path (`CategoryCorrectionService.reapplyRuleToHistory`) writes
///    **one audit entry per affected transaction** naming the rule — KHA-34
///    calls a bulk re-apply that writes no history a defect, not a gap;
///  - rows a **person** categorized are never touched, and the result says how
///    many were left alone, so the reported number always adds up.
///
/// ## Deleting a rule (AC-D4.3)
///
/// Stops future auto-categorization; leaves already-categorized transactions
/// exactly as they are. The confirmation says both halves, because a user who
/// believes deleting a rule will un-categorize a year of history will never
/// delete a bad rule.
library;

import 'package:flutter/material.dart';

import '../../features/categorization/categories.dart';
import '../../features/categorization/learned_rules.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/category_widgets.dart';

/// What S-17 asks for and gets back.
final class RuleEditRequest {
  final int ruleId;
  final String categoryId;

  /// AC-D4.4's answer. False = *"going forward only"*.
  final bool reapplyToHistory;

  const RuleEditRequest({
    required this.ruleId,
    required this.categoryId,
    required this.reapplyToHistory,
  });
}

class LearnedRulesScreen extends StatelessWidget {
  final List<LearnedRule> rules;

  /// Resolves a rule's `categoryId` for display. Never returns null — that is
  /// `CategoryResolver`'s whole contract (AC-C1.1's "never a blank").
  final CategoryResolver resolver;

  /// Every category, for S-17's re-picker.
  final List<Category> categories;

  /// Applies an edit. Returns the number of historical transactions rewritten,
  /// or null when the write was refused (a category that no longer exists —
  /// KHA-104's guard, which this screen deliberately routes through rather
  /// than around).
  final Future<int?> Function(RuleEditRequest request)? onEditRule;

  /// AC-D4.3.
  final Future<void> Function(LearnedRule rule)? onDeleteRule;

  /// The **N** in *"Yes, re-apply to N transactions"*, computed before the
  /// dialog can promise it.
  final Future<int> Function(LearnedRule rule, String categoryId)?
  onCountAffected;

  final bool isLoading;
  final String? errorMessage;
  final bool isLocked;

  const LearnedRulesScreen({
    required this.rules,
    required this.resolver,
    this.categories = const <Category>[],
    this.onEditRule,
    this.onDeleteRule,
    this.onCountAffected,
    this.isLoading = false,
    this.errorMessage,
    this.isLocked = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(l10n.learnedRulesTitle)),
      body: _body(context, l10n),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    if (isLocked) {
      return const CategoryLockedState();
    }
    if (errorMessage != null) {
      return CategorySectionError(message: errorMessage!);
    }
    if (isLoading) {
      return const Center(
        key: Key('rules.loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (rules.isEmpty) {
      // The mockup's empty state, and its copy is doing real work: it tells the
      // user how rules come into existence, so an empty screen reads as "you
      // have not corrected anything yet" rather than "this feature is broken".
      return CategoryEmptyState(
        key: const Key('rules.empty'),
        icon: Icons.rule,
        headline: l10n.learnedRulesEmptyTitle,
        body: l10n.learnedRulesEmptyBody,
      );
    }

    // The mockup's "recently changed" section on top. Sorting by `updatedAt`
    // rather than by name because the reason a person opens this screen is
    // almost always *"the app just did something odd"* — and the rule that did
    // it is the one that changed most recently.
    final List<LearnedRule> sorted = <LearnedRule>[...rules]
      ..sort(
        (LearnedRule a, LearnedRule b) => b.updatedAt.compareTo(a.updatedAt),
      );

    return ListView.builder(
      padding: const EdgeInsetsDirectional.all(16),
      itemCount: sorted.length,
      itemBuilder: (BuildContext context, int index) => _RuleRow(
        rule: sorted[index],
        category: resolver.resolve(sorted[index].categoryId),
        onEdit: onEditRule == null ? null : () => _edit(context, sorted[index]),
        onDelete: onDeleteRule == null
            ? null
            : () => _delete(context, sorted[index]),
      ),
    );
  }

  /// **S-17.** Two questions in one dialog, in the order the design shows them:
  /// which category, then whether to re-apply.
  Future<void> _edit(BuildContext context, LearnedRule rule) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final RuleEditRequest? request = await showDialog<RuleEditRequest>(
      context: context,
      builder: (BuildContext dialogContext) => _EditRuleDialog(
        rule: rule,
        categories: categories,
        resolver: resolver,
        onCountAffected: onCountAffected,
      ),
    );
    if (request == null || !context.mounted) {
      return;
    }
    final int? updated = await onEditRule!(request);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          // Three genuinely different outcomes, three different sentences. A
          // single "Saved" would hide the one that matters: a refused write.
          updated == null
              ? l10n.ruleEditRefused
              : (request.reapplyToHistory
                    ? l10n.ruleReappliedCount(updated)
                    : l10n.ruleUpdatedGoingForward),
        ),
      ),
    );
  }

  /// **AC-D4.3**, with a confirmation that states both halves of what happens.
  Future<void> _delete(BuildContext context, LearnedRule rule) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.ruleDeleteTitle(rule.merchantName)),
        content: Text(l10n.ruleDeleteBody),
        actions: <Widget>[
          TextButton(
            key: Key('rules.deleteCancel.${rule.ruleId}'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: Key('rules.deleteConfirm.${rule.ruleId}'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await onDeleteRule!(rule);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.ruleDeleted)));
  }
}

/// **AC-D4.1** — one rule, with its merchant and its category.
class _RuleRow extends StatelessWidget {
  final LearnedRule rule;
  final Category category;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _RuleRow({
    required this.rule,
    required this.category,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      key: Key('rules.row.${rule.ruleId}'),
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ink100),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.ink100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              categoryIconFor(category.iconToken),
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // "{Merchant} → {Category}". The arrow is a literal character
                // rather than an icon so it mirrors correctly under RTL along
                // with the rest of the line.
                Text(
                  '${rule.merchantName} ← ${categoryName(context, category)}',
                  style: text.bodyLarge,
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        l10n.ruleAppliedCount(rule.appliedCount),
                        style: text.bodySmall?.copyWith(
                          color: AppColors.ink500,
                        ),
                      ),
                    ),
                    // AC-D3.1 makes a user rule outrank a seed rule, so the
                    // provenance of the rule itself is worth showing: "you
                    // taught me this" and "I shipped with this" behave
                    // differently and should not look identical.
                    if (!rule.isUserTaught) ...<Widget>[
                      const SizedBox(width: 6),
                      Text(
                        l10n.ruleSourceSeed,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.ink500,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              key: Key('rules.edit.${rule.ruleId}'),
              onPressed: onEdit,
              tooltip: l10n.commonEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (onDelete != null)
            IconButton(
              key: Key('rules.delete.${rule.ruleId}'),
              onPressed: onDelete,
              tooltip: l10n.commonDelete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
    );
  }
}

/// **S-17 — the edit dialog with AC-D4.4's required prompt.**
class _EditRuleDialog extends StatefulWidget {
  final LearnedRule rule;
  final List<Category> categories;
  final CategoryResolver resolver;
  final Future<int> Function(LearnedRule rule, String categoryId)?
  onCountAffected;

  const _EditRuleDialog({
    required this.rule,
    required this.categories,
    required this.resolver,
    this.onCountAffected,
  });

  @override
  State<_EditRuleDialog> createState() => _EditRuleDialogState();
}

class _EditRuleDialogState extends State<_EditRuleDialog> {
  late String _categoryId = widget.rule.categoryId;

  /// Null while the count is in flight. The re-apply button stays disabled
  /// until it arrives, because AC-D4.4's prompt names a number and a button
  /// that said "Yes, ? transactions" would be asking the user to consent to
  /// something unspecified.
  int? _affected;

  @override
  void initState() {
    super.initState();
    _refreshCount();
  }

  Future<void> _refreshCount() async {
    final Future<int> Function(LearnedRule, String)? counter =
        widget.onCountAffected;
    if (counter == null) {
      return;
    }
    setState(() => _affected = null);
    final int count = await counter(widget.rule, _categoryId);
    if (mounted) {
      setState(() => _affected = count);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool changed = _categoryId != widget.rule.categoryId;

    return AlertDialog(
      title: Text(l10n.ruleEditTitle(widget.rule.merchantName)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.ruleEditCurrentCategory(
              categoryName(
                context,
                widget.resolver.resolve(widget.rule.categoryId),
              ),
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('rules.editPicker'),
            initialValue: _categoryId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.ruleEditNewCategory,
              isDense: true,
            ),
            items: <DropdownMenuItem<String>>[
              for (final Category category in widget.categories)
                // *Uncategorized* is deliberately not offered as a rule
                // target: "always file this merchant under 'I do not know'" is
                // not a lesson, and storing it as one would auto-file every
                // future transaction from that merchant and call it a
                // decision. `CategorizationService` makes the same refusal at
                // the write boundary; this stops the user reaching it.
                if (!category.isUncategorized && !category.isArchived)
                  DropdownMenuItem<String>(
                    value: category.id,
                    child: Text(categoryName(context, category)),
                  ),
            ],
            onChanged: (String? value) {
              if (value == null) {
                return;
              }
              setState(() => _categoryId = value);
              _refreshCount();
            },
          ),
          const SizedBox(height: 16),
          // **AC-D4.4's prompt.** Rendered only when the category actually
          // changed: asking "shall I re-apply this to history?" about a change
          // that is not a change would be a question with no meaning, and a
          // user who answered Yes would get a no-op they cannot explain.
          if (changed)
            Text(
              _affected == null
                  ? l10n.ruleReapplyPromptCounting
                  : l10n.ruleReapplyPrompt(_affected!),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('rules.editCancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        // "No, going forward only" — AC-D4.2 without AC-D4.4's rewrite.
        TextButton(
          key: const Key('rules.editForwardOnly'),
          onPressed: changed
              ? () => Navigator.of(context).pop(
                  RuleEditRequest(
                    ruleId: widget.rule.ruleId,
                    categoryId: _categoryId,
                    reapplyToHistory: false,
                  ),
                )
              : null,
          child: Text(l10n.ruleReapplyNo),
        ),
        // "Yes, N transactions".
        FilledButton(
          key: const Key('rules.editReapply'),
          onPressed: changed && _affected != null
              ? () => Navigator.of(context).pop(
                  RuleEditRequest(
                    ruleId: widget.rule.ruleId,
                    categoryId: _categoryId,
                    reapplyToHistory: true,
                  ),
                )
              : null,
          child: Text(l10n.ruleReapplyYes(_affected ?? 0)),
        ),
      ],
    );
  }
}

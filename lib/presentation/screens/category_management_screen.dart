/// **S-14 — Category Management** and **S-15 — the reassignment dialog**.
/// Mockup: `docs/mockups/categories-rules.html`. KHA-97, covering the UI half
/// of AC-C3.1, AC-C3.2 and AC-C3.3.
///
/// ## The one thing this screen must not get wrong
///
/// AC-C3.3: deleting a category that has transactions **blocks until the user
/// decides what happens to them**. The data layer already refuses to guess —
/// `CategoryDao.deleteCategory` requires a sealed `CategoryDeleteDecision`, so
/// there is no way to call it without an answer. This screen is where that
/// answer is produced, and the dialog is *modal and unskippable*: dismissing it
/// deletes nothing.
///
/// That is the opposite posture from the category-correction sheet, which
/// deliberately auto-confirms. The difference is stated in design.md §6.6 and
/// is worth repeating because both patterns live in this feature: a category
/// correction is low-stakes and reversible, so it uses undo; a delete moves
/// every transaction in a category and is not, so it uses a blocking dialog.
///
/// ## *Uncategorized* offers no affordance at all
///
/// Not a disabled button, and not a button that throws. `CategoryDao` raises
/// `ProtectedCategoryError` for rename and delete, and KHA-97 asks for the
/// stronger property: *"the screen must not offer the action in the first
/// place"*. So the row renders with a "system category" caption and no icons.
/// A greyed-out delete icon would still be a delete icon, and the user would
/// spend a tap finding out.
///
/// ## Why this widget takes values and callbacks rather than a database
///
/// Same discipline as `NeedsReviewScreen` and `TransactionDetailScreen`: a
/// `StatelessWidget` over plain values means the widget test is a pure render
/// test, and the screen physically cannot read something the app lock has not
/// unlocked (ADR-005). The provider that supplies the values is in
/// `categorization_providers.dart`.
library;

import 'package:flutter/material.dart';

import '../../data/dao/category_dao.dart'
    show CategoryDeleteDecision, ReassignTo, SetToUncategorized;
import '../../features/categorization/categories.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/category_widgets.dart';

/// One row of S-14: a category and how much depends on it.
final class CategoryListItem {
  final Category category;

  /// `CategoryDao.countTransactionsUsing` — the *"18 transactions"* caption,
  /// and the number the S-15 dialog quotes back when the user tries to delete.
  final int transactionCount;

  const CategoryListItem({
    required this.category,
    required this.transactionCount,
  });
}

class CategoryManagementScreen extends StatelessWidget {
  final List<CategoryListItem> items;

  /// AC-C3.4 — renaming keeps the id, so nothing re-categorises. Null renders
  /// no rename affordance anywhere (a read-only context).
  final Future<bool> Function(Category category, String newName)? onRename;

  /// AC-C3.3 — called only after this screen has obtained a decision.
  final Future<void> Function(Category category, CategoryDeleteDecision)?
  onDelete;

  /// AC-C3.1/C3.2 — the "+ New category" FAB. Returns null for a duplicate
  /// name, exactly like `CategoryDao.createCustom`.
  final Future<Category?> Function({
    required String name,
    required String iconToken,
    required CategoryGroup group,
  })?
  onCreate;

  /// design.md §3.4's Loading state. True while the first read is in flight.
  final bool isLoading;

  /// design.md §3.4's Error state — a failed read never renders as an empty
  /// list, because an empty list is a claim ("you have no categories") that a
  /// failed read has not established.
  final String? errorMessage;

  /// design.md §3.4's Locked state (ADR-005).
  final bool isLocked;

  const CategoryManagementScreen({
    required this.items,
    this.onRename,
    this.onDelete,
    this.onCreate,
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
      appBar: AppBar(title: Text(l10n.categoriesTitle)),
      floatingActionButton: onCreate == null || isLocked
          ? null
          : FloatingActionButton(
              key: const Key('categories.add'),
              onPressed: () => _openCreateSheet(context),
              tooltip: l10n.categoryPickerNewCategory,
              child: const Icon(Icons.add),
            ),
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
        key: Key('categories.loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (items.isEmpty) {
      // Only reachable before the seed has been written — a real state on a
      // very fresh install, and it must not look like a broken screen.
      return CategoryEmptyState(
        key: const Key('categories.empty'),
        icon: Icons.label_outline,
        headline: l10n.categoriesEmptyTitle,
        body: l10n.categoriesEmptyBody,
      );
    }

    final List<CategoryListItem> spending = <CategoryListItem>[
      for (final CategoryListItem item in items)
        if (item.category.group == CategoryGroup.spending) item,
    ];
    final List<CategoryListItem> movement = <CategoryListItem>[
      for (final CategoryListItem item in items)
        if (item.category.group == CategoryGroup.moneyMovement) item,
    ];

    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: <Widget>[
        if (spending.isNotEmpty) ...<Widget>[
          _SectionLabel(text: l10n.categoryGroupSpending),
          for (final CategoryListItem item in spending)
            _CategoryRow(
              item: item,
              onRename: onRename == null ? null : () => _rename(context, item),
              onDelete: onDelete == null ? null : () => _delete(context, item),
            ),
        ],
        if (movement.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          _SectionLabel(text: l10n.categoryGroupMoneyMovement),
          for (final CategoryListItem item in movement)
            _CategoryRow(
              item: item,
              onRename: onRename == null ? null : () => _rename(context, item),
              onDelete: onDelete == null ? null : () => _delete(context, item),
            ),
        ],
      ],
    );
  }

  /// AC-C3.4 — rename in place. The id never changes, so no transaction is
  /// re-categorised and no rule is disturbed; only the label moves.
  ///
  /// A false result means the new name collides with another category (folded,
  /// so case and Arabic orthography collide too), which is reported with the
  /// same AC-C3.2 message the create form uses — the same problem deserves the
  /// same sentence.
  Future<void> _rename(BuildContext context, CategoryListItem item) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _RenameDialog(category: item.category),
    );
    if (name == null || !context.mounted) {
      return;
    }
    final bool ok = await onRename!(item.category, name);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? l10n.categoryRenamed(name) : l10n.categoryNewDuplicateName,
        ),
      ),
    );
  }

  /// **AC-C3.3 — the delete cannot complete without a decision.**
  ///
  /// Two shapes, and the split is deliberate:
  ///
  ///  - **No transactions use it** → an ordinary destructive confirmation.
  ///    Asking "where should these zero transactions go?" would be theatre.
  ///  - **N transactions use it** → S-15, which *requires* a target before its
  ///    Delete button is enabled. Dismissing it returns null and deletes
  ///    nothing.
  Future<void> _delete(BuildContext context, CategoryListItem item) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final CategoryDeleteDecision?
    decision = await showDialog<CategoryDeleteDecision>(
      context: context,
      builder: (BuildContext dialogContext) => _ReassignDialog(
        item: item,
        // *Uncategorized* is always a target and is never itself deletable, so
        // it is present in every reassignment list. The category being deleted
        // is excluded — reassigning to itself is not a decision.
        targets: <Category>[
          for (final CategoryListItem candidate in items)
            if (candidate.category.id != item.category.id) candidate.category,
        ],
      ),
    );
    if (decision == null || !context.mounted) {
      return;
    }
    await onDelete!(item.category, decision);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.categoryDeleted(categoryName(context, item.category)),
        ),
      ),
    );
  }

  /// AC-C3.1/C3.2 — the same inline form the picker sheet uses (§6.5), reached
  /// from the FAB. One implementation, so the duplicate-name message and the
  /// icon list cannot drift between the two entry points.
  Future<void> _openCreateSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      builder: (BuildContext sheetContext) =>
          _CreateCategorySheet(onCreate: onCreate!),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(top: 8, bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.ink500,
      ),
    ),
  );
}

/// One category row. The affordances are **absent**, not disabled, when the
/// category is protected — see this library's note.
class _CategoryRow extends StatelessWidget {
  final CategoryListItem item;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  const _CategoryRow({required this.item, this.onRename, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final bool protected = item.category.isProtected;

    return Container(
      key: Key('categories.row.${item.category.id}'),
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
              categoryIconFor(item.category.iconToken),
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  categoryName(context, item.category),
                  style: text.bodyLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  protected
                      ? l10n.categoryRowSystemCaption(item.transactionCount)
                      : l10n.categoryRowTransactionCount(item.transactionCount),
                  style: text.bodySmall?.copyWith(color: AppColors.ink500),
                ),
              ],
            ),
          ),
          // KHA-97: *"Uncategorized renders with its delete/rename affordances
          // disabled — the screen must not offer the action in the first
          // place."* Absent, not disabled.
          if (!protected) ...<Widget>[
            if (onRename != null)
              IconButton(
                key: Key('categories.rename.${item.category.id}'),
                onPressed: onRename,
                tooltip: l10n.commonRename,
                icon: const Icon(Icons.edit_outlined),
              ),
            if (onDelete != null)
              IconButton(
                key: Key('categories.delete.${item.category.id}'),
                onPressed: onDelete,
                tooltip: l10n.commonDelete,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ],
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  final Category category;
  const _RenameDialog({required this.category});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: categoryName(context, widget.category),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.categoryRenameTitle),
      content: TextField(
        key: const Key('categories.renameField'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.categoryNewNameLabel),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('categories.renameCancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('categories.renameSave'),
          onPressed: () {
            final String value = _controller.text.trim();
            if (value.isNotEmpty) {
              Navigator.of(context).pop(value);
            }
          },
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}

/// **S-15 — the reassignment dialog (AC-C3.3).**
///
/// *"This category has 12 transactions. Reassign to: \[picker\] or set to
/// Uncategorized"* — and **Delete stays disabled until one is chosen**. That
/// disabled state is the acceptance criterion made mechanical: there is no tap
/// sequence that deletes a category in use without an answer, and dismissing
/// the dialog returns null so nothing is written.
class _ReassignDialog extends StatefulWidget {
  final CategoryListItem item;
  final List<Category> targets;

  const _ReassignDialog({required this.item, required this.targets});

  @override
  State<_ReassignDialog> createState() => _ReassignDialogState();
}

class _ReassignDialogState extends State<_ReassignDialog> {
  /// Null means "not decided yet", which is a distinct state from either
  /// choice — and it is the state that keeps Delete disabled.
  CategoryDeleteDecision? _decision;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String name = categoryName(context, widget.item.category);
    final bool inUse = widget.item.transactionCount > 0;

    return AlertDialog(
      title: Text(l10n.categoryDeleteTitle(name)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            inUse
                ? l10n.categoryDeleteInUseBody(widget.item.transactionCount)
                : l10n.categoryDeleteEmptyBody,
          ),
          if (inUse) ...<Widget>[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('categories.reassignPicker'),
              initialValue: switch (_decision) {
                ReassignTo(:final String categoryId) => categoryId,
                SetToUncategorized() => CategoryIds.uncategorized,
                null => null,
              },
              decoration: InputDecoration(
                labelText: l10n.categoryDeleteReassignLabel,
                isDense: true,
              ),
              items: <DropdownMenuItem<String>>[
                for (final Category target in widget.targets)
                  DropdownMenuItem<String>(
                    value: target.id,
                    child: Text(categoryName(context, target)),
                  ),
              ],
              onChanged: (String? value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  // Choosing *Uncategorized* from the list is expressed as the
                  // sealed `SetToUncategorized` rather than as
                  // `ReassignTo('uncategorized')`, because the DAO stores that
                  // state as NULL. Two encodings of one fact is the ambiguity
                  // `normalizeStoredCategoryId` exists to prevent, and the UI
                  // must not reintroduce it one layer up.
                  _decision = value == CategoryIds.uncategorized
                      ? const SetToUncategorized()
                      : ReassignTo(value);
                });
              },
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('categories.deleteCancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('categories.deleteConfirm'),
          // AC-C3.3, mechanically: a category in use cannot be deleted until a
          // decision exists. An empty category needs no decision, so it gets
          // the trivially-true one.
          onPressed: inUse && _decision == null
              ? null
              : () => Navigator.of(
                  context,
                ).pop(_decision ?? const SetToUncategorized()),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: Text(l10n.commonDelete),
        ),
      ],
    );
  }
}

/// The "+ New category" sheet reached from S-14's FAB — the same fields as the
/// picker's inline form (§6.5), without the "and use it on this transaction"
/// half, because there is no transaction in this context.
class _CreateCategorySheet extends StatefulWidget {
  final Future<Category?> Function({
    required String name,
    required String iconToken,
    required CategoryGroup group,
  })
  onCreate;

  const _CreateCategorySheet({required this.onCreate});

  @override
  State<_CreateCategorySheet> createState() => _CreateCategorySheetState();
}

class _CreateCategorySheetState extends State<_CreateCategorySheet> {
  final TextEditingController _name = TextEditingController();
  String _iconToken = newCategoryIconTokens.first;
  CategoryGroup _group = CategoryGroup.spending;
  bool _duplicate = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String name = _name.text.trim();
    if (name.isEmpty || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _duplicate = false;
    });
    final Category? created = await widget.onCreate(
      name: name,
      iconToken: _iconToken,
      group: _group,
    );
    if (!mounted) {
      return;
    }
    if (created == null) {
      setState(() {
        _busy = false;
        _duplicate = true;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.categoryPickerNewCategory,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('categories.newName'),
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.categoryNewNameLabel,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: _duplicate ? l10n.categoryNewDuplicateName : null,
                ),
                onChanged: (_) {
                  if (_duplicate) {
                    setState(() => _duplicate = false);
                  }
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String token in newCategoryIconTokens)
                    ChoiceChip(
                      key: Key('categories.newIcon.$token'),
                      selected: token == _iconToken,
                      onSelected: (_) => setState(() => _iconToken = token),
                      avatar: Icon(categoryIconFor(token), size: 16),
                      label: const SizedBox.shrink(),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<CategoryGroup>(
                key: const Key('categories.newGroup'),
                segments: <ButtonSegment<CategoryGroup>>[
                  ButtonSegment<CategoryGroup>(
                    value: CategoryGroup.spending,
                    label: Text(l10n.categoryGroupSpending),
                  ),
                  ButtonSegment<CategoryGroup>(
                    value: CategoryGroup.moneyMovement,
                    label: Text(l10n.categoryGroupMoneyMovement),
                  ),
                ],
                selected: <CategoryGroup>{_group},
                onSelectionChanged: (Set<CategoryGroup> selection) =>
                    setState(() => _group = selection.first),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('categories.newCreate'),
                  onPressed: _busy ? null : _submit,
                  child: Text(l10n.commonCreate),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

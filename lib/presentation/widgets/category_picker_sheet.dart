/// **S-12/S-13 — the category picker and the scope strip.** Mockup:
/// `docs/mockups/category-correction.html`. KHA-33 (US-C2, US-D5) and the
/// inline "+ New category" half of KHA-97 (AC-C3.2).
///
/// ## This is the highest-frequency interaction in the product (NFR-U7)
///
/// design.md §6 sets the bar numerically and this file is measured against it:
///
/// > *"the category itself is corrected in exactly **two taps** from any
/// > transaction context, with **zero screen navigation**"* (AC-C2.2).
///
/// So it is a **bottom sheet**, not a pushed route. A sheet layers over the
/// screen the user was already on, which is what makes "no more than two
/// screens" true by construction rather than by counting: the transaction is
/// still on screen behind it, and dismissing the sheet returns to it with no
/// navigation at all.
///
///  - **Tap 1** opens this sheet (from a `CategoryChip` — see §6.1's four entry
///    points, all of which land here).
///  - **Tap 2** taps a category cell, which **applies it immediately**. There
///    is deliberately no Confirm button: at this point the correction is
///    complete and AC-C2.2 is satisfied on its own.
///  - Everything after tap 2 — the scope strip — is an *extension in place*
///    that never blocks. It auto-confirms its default, so the passive flow is
///    still exactly two taps.
///
/// ## Why the scope strip auto-confirms instead of asking
///
/// design.md §6.4: the default is *"this + future"*, pre-selected, because that
/// trains the learning loop and is very likely the intent. A 3-second timer
/// applies it if the user does nothing. The one-off case (US-D5's "this was a
/// gift") costs exactly one extra, clearly-labelled tap.
///
/// The safety net is **undo, not a blocking dialog** (§6.6): a category
/// correction is low-stakes and reversible, unlike delete or erase-all, which
/// do use blocking confirmation. Making the reversible thing cheap is what
/// stops the learning loop going untrained.
///
/// ## Skipping the scope question entirely (AC-C4.3)
///
/// If the chosen category already matches the merchant's learned rule, the user
/// is confirming a flagged guess rather than teaching anything. §6.4 says the
/// strip is skipped in that case, and it is: asking "shall I also learn this?"
/// about a rule that already says exactly that is a question with no answer.
///
/// ## A note for readers new to Flutter
///
/// `showModalBottomSheet` pushes a *route* whose content is this widget and
/// completes its `Future` with whatever `Navigator.pop` is given — so
/// [showCategoryPickerSheet] returns `null` when the user dismisses by tapping
/// outside or swiping down, and that null is a real answer meaning "changed my
/// mind". `isScrollControlled: true` lets the sheet grow past the default
/// half-screen cap, which the category grid needs.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/categorization/categories.dart';
import '../../features/categorization/category_correction.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import 'category_widgets.dart';

/// What the sheet returns: the category the user picked and the scope they
/// chose (or let the timer choose).
final class CategoryPickResult {
  final String categoryId;
  final CorrectionScope scope;

  const CategoryPickResult({required this.categoryId, required this.scope});

  @override
  String toString() => 'CategoryPickResult($categoryId, ${scope.name})';
}

/// Creates a category from the inline form (§6.5).
///
/// Returns the new category, or **null when the name is a duplicate** —
/// `CategoryDao.createCustom`'s own contract, carried up unchanged so the sheet
/// can render AC-C3.2's message. A thrown exception would be the wrong shape:
/// a duplicate name is an ordinary thing for a person to type, not an error
/// condition.
typedef CreateCategory =
    Future<Category?> Function({
      required String name,
      required String iconToken,
      required CategoryGroup group,
    });

/// Opens S-12 over the current screen and returns the user's choice.
///
/// [affectedCountFor] is consulted *after* a category is tapped, so the scope
/// strip can state how many existing transactions "this + future" would fill in
/// (design.md §6.4's `affectedCount`, AC-D5.3's number). It is a callback
/// rather than a value because the count depends on the category chosen, and
/// computing it up front for thirteen categories would be thirteen queries for
/// a number the user will probably never see.
Future<CategoryPickResult?> showCategoryPickerSheet({
  required BuildContext context,
  required List<Category> categories,
  String? currentCategoryId,
  String? merchantName,

  /// The category the merchant's rule already teaches, when there is one.
  /// Choosing exactly this skips the scope strip (AC-C4.3).
  String? existingRuleCategoryId,

  /// design.md §6.2's "Recent" row — the last three categories used. Empty on
  /// a fresh install, in which case the row is not rendered at all rather than
  /// rendered empty.
  List<String> recentCategoryIds = const <String>[],
  Future<int> Function(String categoryId)? affectedCountFor,
  CreateCategory? onCreateCategory,

  /// Set to zero in tests so the scope strip resolves deterministically instead
  /// of racing a real timer.
  Duration autoConfirmDelay = const Duration(seconds: 3),
}) {
  return showModalBottomSheet<CategoryPickResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (BuildContext sheetContext) => CategoryPickerSheet(
      categories: categories,
      currentCategoryId: currentCategoryId,
      merchantName: merchantName,
      existingRuleCategoryId: existingRuleCategoryId,
      recentCategoryIds: recentCategoryIds,
      affectedCountFor: affectedCountFor,
      onCreateCategory: onCreateCategory,
      autoConfirmDelay: autoConfirmDelay,
    ),
  );
}

/// The sheet body. Public so widget tests can pump it directly without a
/// modal route.
class CategoryPickerSheet extends StatefulWidget {
  final List<Category> categories;
  final String? currentCategoryId;
  final String? merchantName;
  final String? existingRuleCategoryId;
  final List<String> recentCategoryIds;
  final Future<int> Function(String categoryId)? affectedCountFor;
  final CreateCategory? onCreateCategory;
  final Duration autoConfirmDelay;

  const CategoryPickerSheet({
    required this.categories,
    this.currentCategoryId,
    this.merchantName,
    this.existingRuleCategoryId,
    this.recentCategoryIds = const <String>[],
    this.affectedCountFor,
    this.onCreateCategory,
    this.autoConfirmDelay = const Duration(seconds: 3),
    super.key,
  });

  @override
  State<CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<CategoryPickerSheet> {
  /// The sheet has exactly three faces, and which one is showing is the whole
  /// of its state. An enum rather than two booleans, so "picking AND creating"
  /// is not representable.
  _SheetStage _stage = _SheetStage.picking;

  String _query = '';
  String? _chosenCategoryId;
  CorrectionScope _scope = CorrectionScope.thisAndFuture;
  int? _affectedCount;
  Timer? _autoConfirm;

  // Inline "+ New category" form state (§6.5).
  final TextEditingController _newNameController = TextEditingController();
  String _newIconToken = newCategoryIconTokens.first;
  CategoryGroup _newGroup = CategoryGroup.spending;
  bool _duplicateName = false;
  bool _creating = false;

  @override
  void dispose() {
    // A pending timer that fired after the sheet closed would call
    // `Navigator.pop` on a dead route. Cancelling in `dispose` is the whole
    // defence, and it is why the timer lives in State rather than in a
    // callback closure.
    _autoConfirm?.cancel();
    _newNameController.dispose();
    super.dispose();
  }

  /// Design §6.3 — **tap 2 applies immediately**.
  ///
  /// The pop that carries the result is deferred to the scope stage, but the
  /// *decision* is made here, and the scope strip's default is pre-selected, so
  /// a user who walks away has still corrected the category.
  Future<void> _pick(Category category) async {
    // AC-C4.3 — confirming a flagged guess that already matches the rule
    // teaches nothing new, so the scope question is not asked (design §6.4's
    // last bullet). Returning straight away keeps the passive path at two taps
    // *and* zero waiting.
    if (category.id == widget.existingRuleCategoryId) {
      Navigator.of(context).pop(
        CategoryPickResult(
          categoryId: category.id,
          // Not "this only": the rule already exists and is unchanged, so the
          // honest scope is the one that leaves it alone AND leaves it
          // applying. `thisAndFuture` re-upserts the identical rule, which
          // `upsertRule` handles as a no-op change.
          scope: CorrectionScope.thisAndFuture,
        ),
      );
      return;
    }

    // The explicit *Uncategorized* choice never becomes a rule ("I do not know
    // what this is" is not a lesson — `CategorizationService.applyUserCategory`
    // makes the same point at the write boundary), so there is no scope
    // question to ask.
    if (category.isUncategorized) {
      Navigator.of(context).pop(
        CategoryPickResult(
          categoryId: category.id,
          scope: CorrectionScope.thisTransactionOnly,
        ),
      );
      return;
    }

    setState(() {
      _chosenCategoryId = category.id;
      _stage = _SheetStage.scope;
      _scope = CorrectionScope.thisAndFuture;
      _affectedCount = null;
    });

    // AC-D5.3's number, fetched while the strip is already on screen so the
    // query never delays the feedback the tap gives.
    final Future<int> Function(String)? counter = widget.affectedCountFor;
    if (counter != null) {
      final int count = await counter(category.id);
      if (mounted) {
        setState(() => _affectedCount = count);
      }
    }

    if (!mounted) {
      return;
    }
    _startAutoConfirm();
  }

  /// design §6.4's 3-second auto-confirm. Zero in tests.
  void _startAutoConfirm() {
    _autoConfirm?.cancel();
    _autoConfirm = Timer(widget.autoConfirmDelay, () {
      if (mounted) {
        _confirmScope();
      }
    });
  }

  void _confirmScope() {
    _autoConfirm?.cancel();
    final String? chosen = _chosenCategoryId;
    if (chosen == null) {
      return;
    }
    Navigator.of(
      context,
    ).pop(CategoryPickResult(categoryId: chosen, scope: _scope));
  }

  /// Overriding the default before the timer fires (§6.4's optional 3rd tap).
  ///
  /// Choosing a scope explicitly **cancels** the countdown rather than
  /// restarting it: the user has answered, and a screen that kept counting
  /// down after an answer would imply the answer might still change.
  void _chooseScope(CorrectionScope scope) {
    setState(() => _scope = scope);
    _autoConfirm?.cancel();
  }

  /// §6.5 + AC-C3.2 — create a category inline and use it immediately.
  Future<void> _createCategory() async {
    final CreateCategory? create = widget.onCreateCategory;
    final String name = _newNameController.text.trim();
    if (create == null || name.isEmpty || _creating) {
      return;
    }
    setState(() {
      _creating = true;
      _duplicateName = false;
    });

    final Category? created = await create(
      name: name,
      iconToken: _newIconToken,
      group: _newGroup,
    );
    if (!mounted) {
      return;
    }
    if (created == null) {
      // AC-C3.2. `createCustom` returns null for a duplicate name — folded, so
      // case, spacing and Arabic orthography all collide — and the message
      // names the problem rather than saying "invalid input" (brand.md voice
      // principle 4).
      setState(() {
        _creating = false;
        _duplicateName = true;
      });
      return;
    }
    setState(() {
      _creating = false;
      _stage = _SheetStage.picking;
    });
    // "Create and use": the new category is applied to the transaction the
    // user was correcting, which is why they were in this form at all.
    await _pick(created);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Padding(
      // Lifts the sheet above the on-screen keyboard when the inline form's
      // text field has focus, so the Create button is never behind it.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _SheetHandle(),
              const SizedBox(height: 10),
              Text(
                widget.merchantName == null
                    ? l10n.categoryPickerTitle
                    : l10n.categoryPickerTitleFor(widget.merchantName!),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              switch (_stage) {
                _SheetStage.picking => Flexible(child: _buildPicker(l10n)),
                _SheetStage.creating => _buildNewCategoryForm(l10n),
                _SheetStage.scope => _buildScopeStrip(l10n),
              },
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------
  // Stage 1 — the picker (§6.2)
  // -----------------------------------------------------------------

  Widget _buildPicker(AppLocalizations l10n) {
    final List<Category> matching = <Category>[
      for (final Category category in widget.categories)
        if (!category.isArchived && _matches(context, category)) category,
    ];
    final List<Category> spending = <Category>[
      for (final Category c in matching)
        if (c.group == CategoryGroup.spending) c,
    ];
    final List<Category> movement = <Category>[
      for (final Category c in matching)
        if (c.group == CategoryGroup.moneyMovement) c,
    ];
    final List<Category> recent = <Category>[
      for (final String id in widget.recentCategoryIds)
        ...matching.where((Category c) => c.id == id),
    ];

    return ListView(
      shrinkWrap: true,
      children: <Widget>[
        TextField(
          key: const Key('categoryPicker.search'),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: l10n.categoryPickerSearchHint,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (String value) => setState(() => _query = value),
        ),
        const SizedBox(height: 14),
        // A search that matches nothing is a distinct state from "there are no
        // categories" — design.md §3.4's `Filtered-empty`, which it requires
        // to read differently from a true empty.
        if (matching.isEmpty)
          Padding(
            key: const Key('categoryPicker.noResults'),
            padding: const EdgeInsetsDirectional.symmetric(vertical: 24),
            child: Text(
              l10n.categoryPickerNoResults(_query),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.ink500),
            ),
          ),
        if (recent.isNotEmpty) ...<Widget>[
          _GroupLabel(text: l10n.categoryPickerRecent),
          _CategoryGrid(
            categories: recent,
            currentCategoryId: widget.currentCategoryId,
            onPick: _pick,
            keyPrefix: 'recent',
          ),
          const SizedBox(height: 12),
        ],
        if (spending.isNotEmpty) ...<Widget>[
          _GroupLabel(text: l10n.categoryGroupSpending),
          _CategoryGrid(
            categories: spending,
            currentCategoryId: widget.currentCategoryId,
            onPick: _pick,
            keyPrefix: 'spending',
          ),
          const SizedBox(height: 12),
        ],
        if (movement.isNotEmpty) ...<Widget>[
          _GroupLabel(text: l10n.categoryGroupMoneyMovement),
          _CategoryGrid(
            categories: movement,
            currentCategoryId: widget.currentCategoryId,
            onPick: _pick,
            keyPrefix: 'movement',
          ),
        ],
        if (widget.onCreateCategory != null) ...<Widget>[
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('categoryPicker.newCategory'),
            onPressed: () => setState(() {
              _stage = _SheetStage.creating;
              _duplicateName = false;
            }),
            icon: const Icon(Icons.add_circle_outline),
            label: Text(l10n.categoryPickerNewCategory),
          ),
        ],
      ],
    );
  }

  bool _matches(BuildContext context, Category category) {
    if (_query.trim().isEmpty) {
      return true;
    }
    final String needle = _query.trim().toLowerCase();
    // Both names are searched regardless of locale: a bilingual user types
    // whichever comes to mind first, and matching only the displayed name
    // would make the search feel broken to exactly the audience this product
    // is built for.
    return category.nameAr.toLowerCase().contains(needle) ||
        category.nameEn.toLowerCase().contains(needle);
  }

  // -----------------------------------------------------------------
  // Stage 2 — the scope strip (§6.4, US-D5)
  // -----------------------------------------------------------------

  Widget _buildScopeStrip(AppLocalizations l10n) {
    final TextTheme text = Theme.of(context).textTheme;
    final Category chosen = widget.categories.firstWhere(
      (Category c) => c.id == _chosenCategoryId,
      orElse: () => DefaultCategories.uncategorized,
    );

    return Column(
      key: const Key('categoryPicker.scopeStrip'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // The confirmation comes first, and it is unconditional: the category
        // is already applied by the time this renders, so the strip must not
        // read as if the correction were still pending.
        Row(
          children: <Widget>[
            const Icon(
              Icons.check_circle_outline,
              size: 18,
              color: AppColors.success,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.categoryAppliedAs(categoryName(context, chosen)),
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          widget.merchantName == null
              ? l10n.categoryScopeQuestionGeneric
              : l10n.categoryScopeQuestion(widget.merchantName!),
          style: text.bodyMedium,
        ),
        const SizedBox(height: 10),
        _ScopeOption(
          key: const Key('categoryPicker.scopeFuture'),
          selected: _scope == CorrectionScope.thisAndFuture,
          title: l10n.categoryScopeFuture,
          // The count is only shown once it has arrived, and the subtitle
          // changes rather than a number appearing in place — a "0" that later
          // becomes "12" would be a figure the user saw and cannot trust.
          subtitle: _affectedCount == null
              ? l10n.categoryScopeFutureHint
              : l10n.categoryScopeFutureCount(_affectedCount!),
          onTap: () => _chooseScope(CorrectionScope.thisAndFuture),
        ),
        const SizedBox(height: 8),
        _ScopeOption(
          key: const Key('categoryPicker.scopeOnly'),
          selected: _scope == CorrectionScope.thisTransactionOnly,
          title: l10n.categoryScopeThisOnly,
          // AC-D5.2's guarantee, stated where the choice is made: a one-off
          // does not disturb a rule already learned for this merchant.
          subtitle: l10n.categoryScopeThisOnlyHint,
          onTap: () => _chooseScope(CorrectionScope.thisTransactionOnly),
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                l10n.categoryScopeAutoConfirm,
                style: text.bodySmall?.copyWith(color: AppColors.ink500),
              ),
            ),
            FilledButton(
              key: const Key('categoryPicker.scopeConfirm'),
              onPressed: _confirmScope,
              child: Text(l10n.commonConfirm),
            ),
          ],
        ),
      ],
    );
  }

  // -----------------------------------------------------------------
  // Stage 3 — inline "+ New category" (§6.5, AC-C3.2)
  // -----------------------------------------------------------------

  Widget _buildNewCategoryForm(AppLocalizations l10n) {
    final AppLocalizations loc = l10n;
    return Column(
      key: const Key('categoryPicker.newCategoryForm'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          key: const Key('categoryPicker.newCategoryName'),
          controller: _newNameController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: loc.categoryNewNameLabel,
            isDense: true,
            border: const OutlineInputBorder(),
            // AC-C3.2's message, inline on the field that caused it. Naming
            // the problem ("a category with this name already exists") rather
            // than a generic rejection is brand.md voice principle 4.
            errorText: _duplicateName ? loc.categoryNewDuplicateName : null,
          ),
          onChanged: (_) {
            if (_duplicateName) {
              setState(() => _duplicateName = false);
            }
          },
        ),
        const SizedBox(height: 12),
        Text(
          loc.categoryNewIconLabel,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String token in newCategoryIconTokens)
              _IconChoice(
                key: Key('categoryPicker.icon.$token'),
                token: token,
                selected: token == _newIconToken,
                onTap: () => setState(() => _newIconToken = token),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // design §4's two buckets are a behavioural distinction, not a
        // heading: a money-movement category is excluded from spend totals and
        // cannot carry a budget. So the choice is made at creation, where the
        // consequence can be explained, rather than inferred later.
        SegmentedButton<CategoryGroup>(
          key: const Key('categoryPicker.newCategoryGroup'),
          segments: <ButtonSegment<CategoryGroup>>[
            ButtonSegment<CategoryGroup>(
              value: CategoryGroup.spending,
              label: Text(loc.categoryGroupSpending),
            ),
            ButtonSegment<CategoryGroup>(
              value: CategoryGroup.moneyMovement,
              label: Text(loc.categoryGroupMoneyMovement),
            ),
          ],
          selected: <CategoryGroup>{_newGroup},
          onSelectionChanged: (Set<CategoryGroup> selection) =>
              setState(() => _newGroup = selection.first),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                key: const Key('categoryPicker.newCategoryCancel'),
                onPressed: () => setState(() {
                  _stage = _SheetStage.picking;
                  _duplicateName = false;
                }),
                child: Text(loc.commonCancel),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: const Key('categoryPicker.newCategoryCreate'),
                // Disabled until there is a name, so the failure the user is
                // most likely to hit is prevented rather than reported.
                onPressed: _creating ? null : _createCategory,
                child: Text(loc.categoryNewCreateAndUse),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _SheetStage { picking, scope, creating }

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.ink300,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.ink500,
      ),
    ),
  );
}

/// The grid of tappable category cells. `Wrap` rather than `GridView` so a long
/// Arabic name gets the width it needs instead of being clipped to a column.
class _CategoryGrid extends StatelessWidget {
  final List<Category> categories;
  final String? currentCategoryId;
  final void Function(Category) onPick;
  final String keyPrefix;

  const _CategoryGrid({
    required this.categories,
    required this.onPick,
    required this.keyPrefix,
    this.currentCategoryId,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      for (final Category category in categories)
        _CategoryCell(
          key: Key('categoryPicker.$keyPrefix.${category.id}'),
          category: category,
          selected: category.id == currentCategoryId,
          onTap: () => onPick(category),
        ),
    ],
  );
}

class _CategoryCell extends StatelessWidget {
  final Category category;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryCell({
    required this.category,
    required this.selected,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryTint10 : AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.ink300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              categoryIconFor(category.iconToken),
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              categoryName(context, category),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// One radio-shaped scope choice. Not a `RadioListTile`, because the strip has
/// to sit inside a sheet with its own padding and a `ListTile` would paint its
/// ink splash onto the wrong `Material` ancestor — the same trap
/// `needs_review_screen.dart` documents on its flagged card.
class _ScopeOption extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ScopeOption({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsetsDirectional.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryTint10 : AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.ink300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // NFR-U4: selection is a filled/outlined ICON as well as a border
            // colour, so it survives greyscale.
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? AppColors.primary : AppColors.ink500,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: text.bodySmall?.copyWith(color: AppColors.ink500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  final String token;
  final bool selected;
  final VoidCallback onTap;

  const _IconChoice({
    required this.token,
    required this.selected,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: selected ? AppColors.primaryTint10 : AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.ink300,
          width: selected ? 2 : 1,
        ),
      ),
      child: Icon(categoryIconFor(token), size: 20, color: AppColors.primary),
    ),
  );
}

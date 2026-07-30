/// **S-26 / S-27 — search and filter** (KHA-38, US-E5).
///
/// | design.md §5 component | here |
/// |---|---|
/// | `SearchBar` | [TransactionSearchField] |
/// | `FilterSheet` | [TransactionFilterSheet] |
/// | S-27's "applied filters surface as removable chips" | [ActiveFilterChips] |
///
/// ---
///
/// ## NFR-S4 governs this file more than any other in the presentation layer
///
/// > *"Search queries and results must not be logged — a search history is a
/// > record of what the user was looking for in their financial life."*
///
/// So: **nothing here imports a logger**, nothing calls `print`, and no widget
/// below puts the query into a `Key`, a `Semantics` identifier or an exception
/// message. The query lives in exactly two places — a `TextEditingController` and
/// the `TransactionFilter` value the sheet hands back — and both are in memory for
/// as long as the screen is. Nothing persists it, which is why there is no
/// "recent searches" row here even though a search field invites one: a stored
/// search history is a durable record of the user's suspicions about their own
/// spending, and the product's privacy posture (US-F4) promises the opposite.
///
/// `TransactionFilter.toString` follows the same rule at the domain layer — it
/// reports which facets are set, never their values.
///
/// ## Why the sheet edits a *draft* and returns it, rather than mutating live
///
/// A filter sheet that applied each tap immediately would re-filter and re-total
/// the list under the user's finger four or five times while they set up one
/// query, and AC-E5.2's total would visibly jump between meanings. So
/// [TransactionFilterSheet] holds a private draft, and "Apply" is the single
/// moment the screen's filter changes. "Clear filters" is offered *inside* the
/// sheet as well as on the screen, because AC-E5.3 requires a way out from the
/// no-results state and a user who over-constrained is most likely to notice it
/// while still in the sheet.
library;

import 'package:flutter/material.dart';

import '../../core/money/money.dart';
import '../../core/time/clock.dart';
import '../../features/categorization/categories.dart';
import '../../features/ledger/bank_tree.dart';
import '../../features/ledger/instrument_identity.dart';
import '../../features/ledger/transaction_filter.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import 'category_widgets.dart';

/// One choice in the sheet's card/account facet.
///
/// ## Why a purpose-built type rather than reusing a domain object
///
/// The obvious candidates were `InstrumentSummary` (which carries a
/// `PeriodTotals` this sheet has no use for) and `InstrumentSlice` (which lives in
/// `instrument_breakdown.dart` — a **reports** type). An earlier draft used the
/// latter, and it made the transaction list depend on `instrumentBreakdownProvider`
/// purely to label three chips: a second Drift subscription, and a conceptual
/// dependency from S-10 onto S-30 that nothing about the feature justifies.
///
/// Three fields is the whole contract, so it is written down. The host builds these
/// from `bankTreeProvider`, which S-10 is already entitled to read and which is
/// where a renamed instrument's label lives (AC-B3.1).
final class FilterInstrumentOption {
  final int instrumentId;

  /// The friendly name, or the masked identifier when the user has not renamed it
  /// (AC-B15.2). Never the raw `****4821` form — the label is produced by
  /// `InstrumentSummary.label`, which the rest of the app also uses.
  final String label;

  /// Drives the chip's icon only. AC-B13.1/2's distinction, kept because two
  /// instruments can share a label suffix and the icon is the cheapest
  /// disambiguation in a chip that has no room for a subtitle.
  final bool isCard;

  const FilterInstrumentOption({
    required this.instrumentId,
    required this.label,
    required this.isCard,
  });

  /// Builds the options for a whole bank tree, accounts before cards within each
  /// bank — the same order S-22's segmented control uses.
  static List<FilterInstrumentOption> fromBankTree(List<BankTreeNode> banks) =>
      <FilterInstrumentOption>[
        for (final BankTreeNode node in banks)
          for (final InstrumentSummary summary in <InstrumentSummary>[
            ...node.accounts,
            ...node.cards,
          ])
            FilterInstrumentOption(
              instrumentId: summary.instrument.id,
              label: summary.label,
              isCard: summary.instrument.kind == InstrumentKind.card,
            ),
      ];
}

/// **design.md §5's `SearchBar`** — AC-E5.1's merchant-name field.
///
/// A `StatefulWidget` only because it owns a `TextEditingController`; it holds no
/// filter state of its own and reports every keystroke upward, so results are
/// live (design.md §7 S-26: *"live results as `TransactionListItem`s"*).
class TransactionSearchField extends StatefulWidget {
  /// The current query, so the field survives a rebuild with the right text in
  /// it (an `IndexedStack` tab switch, a locale change, a new ledger emission).
  final String query;

  final ValueChanged<String> onChanged;

  const TransactionSearchField({
    required this.query,
    required this.onChanged,
    super.key,
  });

  @override
  State<TransactionSearchField> createState() => _TransactionSearchFieldState();
}

class _TransactionSearchFieldState extends State<TransactionSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );

  @override
  void didUpdateWidget(TransactionSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only when the *owner* changed the query behind our back — clearing the
    // filter from the empty state, or arriving with a category pre-filtered.
    // Assigning unconditionally would fight the user's cursor on every keystroke.
    if (widget.query != _controller.text) {
      _controller.text = widget.query;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return TextField(
      key: const Key('txnList.search'),
      controller: _controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        // "Search a merchant name", not "Search": that is the only field
        // searched, and promising more would make an empty result read as a bug.
        hintText: l10n.searchTransactionsHint,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                key: const Key('txnList.search.clear'),
                // NFR-U2 — an X glyph announces as nothing useful.
                tooltip: l10n.searchClear,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                },
              ),
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: AppColors.ink300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: const BorderSide(color: AppColors.ink300),
        ),
      ),
    );
  }
}

/// **S-27's removable chips** — *"applied filters surface as removable chips"*.
///
/// Each chip states the facet it represents and removes only that facet, so a
/// user who over-constrained can back out one step instead of clearing
/// everything and starting again. The "Clear filters" action is separate and
/// clears all of them (AC-E5.3).
class ActiveFilterChips extends StatelessWidget {
  final TransactionFilter filter;

  /// Resolves a stored id to a name for the category chips. Without it the chip
  /// would have to render an id, which is app vocabulary rather than the user's.
  final CategoryResolver resolver;

  /// Labels for the instrument chips, keyed by instrument id.
  final Map<int, String> instrumentLabels;

  final ValueChanged<TransactionFilter> onChanged;
  final VoidCallback onClearAll;

  const ActiveFilterChips({
    required this.filter,
    required this.resolver,
    required this.instrumentLabels,
    required this.onChanged,
    required this.onClearAll,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (!filter.isActive) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          if (filter.fromUtc != null || filter.toUtcExclusive != null)
            _Chip(
              chipKey: const Key('filter.chip.dates'),
              label: _dateRangeLabel(context, l10n),
              onRemove: () => onChanged(filter.copyWith(clearDateRange: true)),
            ),
          for (final String categoryId in filter.categoryIds)
            _Chip(
              // Keyed on the category id, which is app vocabulary rather than
              // user data. A key built from the *query* would put a search term
              // into the widget tree's identity — see this file's NFR-S4 note.
              chipKey: Key('filter.chip.category.$categoryId'),
              label: categoryName(context, resolver.resolve(categoryId)),
              onRemove: () => onChanged(
                filter.copyWith(
                  categoryIds: <String>{...filter.categoryIds}
                    ..remove(categoryId),
                ),
              ),
            ),
          for (final int instrumentId in filter.instrumentIds)
            _Chip(
              chipKey: Key('filter.chip.instrument.$instrumentId'),
              label: instrumentLabels[instrumentId] ?? '$instrumentId',
              onRemove: () => onChanged(
                filter.copyWith(
                  instrumentIds: <int>{...filter.instrumentIds}
                    ..remove(instrumentId),
                ),
              ),
            ),
          if (filter.minAmount != null || filter.maxAmount != null)
            _Chip(
              chipKey: const Key('filter.chip.amount'),
              label: _amountRangeLabel(l10n),
              onRemove: () =>
                  onChanged(filter.copyWith(clearAmountRange: true)),
            ),
          TextButton.icon(
            key: const Key('filter.clearAll'),
            onPressed: onClearAll,
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: Text(l10n.filterClearAll),
          ),
        ],
      ),
    );
  }

  /// Dates are rendered through `MaterialLocalizations`, so they read correctly in
  /// Arabic (month names and order) without a new dependency — the same route
  /// `formatLocalizedDateTime` takes.
  String _dateRangeLabel(BuildContext context, AppLocalizations l10n) {
    final MaterialLocalizations material = MaterialLocalizations.of(context);
    final String from = filter.fromUtc == null
        ? l10n.filterDateAny
        : material.formatMediumDate(
            RiyadhCalendar.toRiyadhWallClock(filter.fromUtc!),
          );
    final String to = filter.toUtcExclusive == null
        ? l10n.filterDateAny
        // Displayed **inclusively** although stored as a half-open bound: the
        // user picked "to 31 July" and must see 31 July, while the predicate uses
        // `< 1 August` so nothing can fall into two ranges.
        //
        // Read back through the Riyadh wall clock, matching how `_pickDate` wrote
        // it — otherwise the label would drift by a day for the three hours after
        // Riyadh midnight, which is the same boundary trap
        // `formatPeriodMonthLabel` documents for month labels.
        : material.formatMediumDate(
            RiyadhCalendar.toRiyadhWallClock(
              filter.toUtcExclusive!.subtract(const Duration(days: 1)),
            ),
          );
    return '$from — $to';
  }

  String _amountRangeLabel(AppLocalizations l10n) {
    final String min = filter.minAmount == null
        ? l10n.filterAmountMin
        : filter.minAmount!.toCanonicalString();
    final String max = filter.maxAmount == null
        ? l10n.filterAmountMax
        : filter.maxAmount!.toCanonicalString();
    return '$min — $max';
  }
}

class _Chip extends StatelessWidget {
  final Key chipKey;
  final String label;
  final VoidCallback onRemove;

  const _Chip({
    required this.chipKey,
    required this.label,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => InputChip(
    key: chipKey,
    label: Text(label),
    onDeleted: onRemove,
    // NFR-U2: the delete affordance needs a spoken name, not just an X.
    deleteButtonTooltipMessage: AppLocalizations.of(context).filterClearAll,
    backgroundColor: AppColors.primaryTint10,
    side: const BorderSide(color: AppColors.ink300),
  );
}

/// **S-27 — the filter sheet.** AC-E5.2's four facets.
///
/// Shown with `showModalBottomSheet`, matching design.md §11's Flutter mapping for
/// every sheet in this app. Returns the new [TransactionFilter] via `Navigator.pop`
/// so the caller owns the state — see [showTransactionFilterSheet].
class TransactionFilterSheet extends StatefulWidget {
  final TransactionFilter initial;

  /// Every category, for the category facet — including *Uncategorized*, which is
  /// a first-class choice here rather than an implementation detail.
  final List<Category> categories;

  /// Every instrument, for the card/account facet. See [FilterInstrumentOption]
  /// for why this is not a domain type.
  final List<FilterInstrumentOption> instruments;

  /// The currency the amount bounds are interpreted in — stated on screen
  /// (NFR-A5) rather than assumed.
  final String baseCurrencyCode;

  /// The period currently on screen, used as the default date range so the sheet
  /// opens describing what the user is already looking at.
  final DateTime periodStartUtc;
  final DateTime periodEndUtcExclusive;

  const TransactionFilterSheet({
    required this.initial,
    required this.categories,
    required this.instruments,
    required this.baseCurrencyCode,
    required this.periodStartUtc,
    required this.periodEndUtcExclusive,
    super.key,
  });

  @override
  State<TransactionFilterSheet> createState() => _TransactionFilterSheetState();
}

class _TransactionFilterSheetState extends State<TransactionFilterSheet> {
  late TransactionFilter _draft = widget.initial;

  late final TextEditingController _min = TextEditingController(
    text: widget.initial.minAmount?.toCanonicalString() ?? '',
  );
  late final TextEditingController _max = TextEditingController(
    text: widget.initial.maxAmount?.toCanonicalString() ?? '',
  );

  /// Set when a bound is typed but unparseable, or when the range is inverted.
  /// Blocks Apply, because applying an unparseable bound would silently ignore it
  /// and show a result the user would read as an answer.
  String? _amountError;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l10n.filterTitle,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const Key('filterSheet.clear'),
                    onPressed: () => setState(() {
                      _draft = TransactionFilter.none;
                      _min.clear();
                      _max.clear();
                      _amountError = null;
                    }),
                    child: Text(l10n.filterClearAll),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              _SectionLabel(label: l10n.filterSectionDates),
              _dateRow(context, l10n),
              const SizedBox(height: 16),

              _SectionLabel(label: l10n.filterSectionCategories),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final Category category in widget.categories)
                    FilterChip(
                      key: Key('filterSheet.category.${category.id}'),
                      label: Text(categoryName(context, category)),
                      avatar: Icon(
                        categoryIconFor(category.iconToken),
                        size: 16,
                      ),
                      selected: _draft.categoryIds.contains(category.id),
                      onSelected: (bool selected) => setState(() {
                        final Set<String> next = <String>{
                          ..._draft.categoryIds,
                        };
                        if (selected) {
                          next.add(category.id);
                        } else {
                          next.remove(category.id);
                        }
                        _draft = _draft.copyWith(categoryIds: next);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              _SectionLabel(label: l10n.filterSectionInstruments),
              if (widget.instruments.isEmpty)
                Text(
                  // Honest absence: a facet with nothing to choose from is
                  // stated rather than rendered as an empty gap.
                  l10n.banksEmptyTitle,
                  style: text.bodySmall?.copyWith(color: AppColors.ink500),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final FilterInstrumentOption option
                        in widget.instruments)
                      FilterChip(
                        key: Key(
                          'filterSheet.instrument.${option.instrumentId}',
                        ),
                        label: Text(option.label),
                        avatar: Icon(
                          option.isCard
                              ? Icons.credit_card_outlined
                              : Icons.account_balance_outlined,
                          size: 16,
                        ),
                        selected: _draft.instrumentIds.contains(
                          option.instrumentId,
                        ),
                        onSelected: (bool selected) => setState(() {
                          final Set<int> next = <int>{..._draft.instrumentIds};
                          if (selected) {
                            next.add(option.instrumentId);
                          } else {
                            next.remove(option.instrumentId);
                          }
                          _draft = _draft.copyWith(instrumentIds: next);
                        }),
                      ),
                  ],
                ),
              const SizedBox(height: 16),

              _SectionLabel(label: l10n.filterSectionAmount),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      key: const Key('filterSheet.amountMin'),
                      controller: _min,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.filterAmountMin,
                        isDense: true,
                      ),
                      onChanged: (String _) => _revalidateAmounts(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const Key('filterSheet.amountMax'),
                      controller: _max,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.filterAmountMax,
                        isDense: true,
                      ),
                      onChanged: (String _) => _revalidateAmounts(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                // NFR-A5 — an amount range is in one currency and the ledger may
                // hold several, so the sheet says which and where the rate came
                // from rather than comparing 20.00 against 20.00 USD.
                l10n.filterAmountCurrencyNote(widget.baseCurrencyCode),
                style: text.bodySmall?.copyWith(color: AppColors.ink500),
              ),
              if (_amountError != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 6),
                  child: Text(
                    key: const Key('filterSheet.amountError'),
                    _amountError!,
                    style: text.bodySmall?.copyWith(color: AppColors.error),
                  ),
                ),

              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.commonCancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const Key('filterSheet.apply'),
                      // Disabled rather than silently dropping a bad bound: a
                      // filter that ignored what the user typed would show a
                      // result they would read as an answer.
                      onPressed: _amountError != null
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop<TransactionFilter>(_applied()),
                      child: Text(l10n.commonApply),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateRow(BuildContext context, AppLocalizations l10n) {
    final MaterialLocalizations material = MaterialLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton(
            key: const Key('filterSheet.dateFrom'),
            onPressed: () => _pickDate(context, isStart: true),
            child: Text(
              _draft.fromUtc == null
                  ? l10n.filterDateFrom
                  // Riyadh wall clock, matching how `_pickDate` wrote it —
                  // `toLocal()` would read the bound in the device's timezone and
                  // could name the day before for the three hours after Riyadh
                  // midnight.
                  : material.formatMediumDate(
                      RiyadhCalendar.toRiyadhWallClock(_draft.fromUtc!),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            key: const Key('filterSheet.dateTo'),
            onPressed: () => _pickDate(context, isStart: false),
            child: Text(
              _draft.toUtcExclusive == null
                  ? l10n.filterDateTo
                  // Inclusive to the user, half-open in the predicate — see
                  // `_pickDate`.
                  : material.formatMediumDate(
                      RiyadhCalendar.toRiyadhWallClock(
                        _draft.toUtcExclusive!.subtract(
                          const Duration(days: 1),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate(BuildContext context, {required bool isStart}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          (isStart ? _draft.fromUtc : _draft.toUtcExclusive) ??
          widget.periodStartUtc,
      // A generous window rather than the visible period: the date facet's whole
      // point is looking outside the month currently on screen.
      firstDate: DateTime.utc(2015),
      lastDate: DateTime.utc(2100),
    );
    if (picked == null) {
      return;
    }

    // **The picked day is a RIYADH day, converted to a UTC instant.**
    //
    // `DateTime.utc(y, m, d)` would be wrong by three hours in the direction that
    // silently loses transactions: midnight UTC on the 3rd is already 03:00 on the
    // 3rd in Riyadh, so a purchase at 01:00 Riyadh time on the 3rd would fall
    // *before* a "from the 3rd" bound and vanish from the user's own results with
    // no explanation. `RiyadhCalendar.monthWindowUtc` applies exactly this
    // correction for the period selector and the import lookback (AC-A3.1,
    // AC-E1.4, OQ-12); a filter that used a different day boundary from the rest
    // of the app would be a second definition of "a day".
    final DateTime dayStartUtc = RiyadhCalendar.riyadhLocalToUtc(
      DateTime(picked.year, picked.month, picked.day),
    );

    setState(() {
      _draft = isStart
          ? _draft.copyWith(fromUtc: dayStartUtc)
          // Stored as the **exclusive** end of the chosen day, so a transaction
          // at 23:59 Riyadh time on the last day is included while nothing can
          // fall into two ranges (the same half-open rule `PeriodRange` uses).
          : _draft.copyWith(
              toUtcExclusive: dayStartUtc.add(const Duration(days: 1)),
            );
    });
  }

  /// Parses both bounds and sets [_amountError].
  ///
  /// `Money.tryParse` rather than `parse`: a half-typed amount is the *normal*
  /// state of a text field, and an exception per keystroke would be absurd. It
  /// also normalises Arabic-Indic digits and the Arabic decimal separator on the
  /// way in, so a user typing on an Arabic keyboard is not silently rejected.
  void _revalidateAmounts() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Money? min = _parseBound(_min.text);
    final Money? max = _parseBound(_max.text);
    final bool minBad = _min.text.trim().isNotEmpty && min == null;
    final bool maxBad = _max.text.trim().isNotEmpty && max == null;

    setState(() {
      if (minBad || maxBad) {
        _amountError = l10n.filterAmountInvalid;
        return;
      }
      if (min != null && max != null && min.abs > max.abs) {
        // Caught here rather than silently returning nothing, which would look
        // identical to "you have no transactions in that range".
        _amountError = l10n.filterAmountRangeInverted;
        return;
      }
      _amountError = null;
    });
  }

  Money? _parseBound(String raw) => raw.trim().isEmpty
      ? null
      : Money.tryParse(raw.trim(), currency: widget.baseCurrencyCode);

  TransactionFilter _applied() => TransactionFilter(
    // The query is owned by the search field on the screen, not by this sheet,
    // so it is carried through untouched.
    query: _draft.query,
    fromUtc: _draft.fromUtc,
    toUtcExclusive: _draft.toUtcExclusive,
    categoryIds: _draft.categoryIds,
    instrumentIds: _draft.instrumentIds,
    minAmount: _parseBound(_min.text),
    maxAmount: _parseBound(_max.text),
  );
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: 8),
    child: Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: AppColors.ink500,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Opens [TransactionFilterSheet] and resolves with the new filter, or null when
/// the user dismissed it.
///
/// A free function rather than a static, matching `category_picker_sheet.dart`'s
/// shape, so a screen calls one thing and never constructs the sheet itself.
Future<TransactionFilter?> showTransactionFilterSheet({
  required BuildContext context,
  required TransactionFilter initial,
  required List<Category> categories,
  required List<FilterInstrumentOption> instruments,
  required String baseCurrencyCode,
  required DateTime periodStartUtc,
  required DateTime periodEndUtcExclusive,
}) => showModalBottomSheet<TransactionFilter>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (BuildContext sheetContext) => TransactionFilterSheet(
    initial: initial,
    categories: categories,
    instruments: instruments,
    baseCurrencyCode: baseCurrencyCode,
    periodStartUtc: periodStartUtc,
    periodEndUtcExclusive: periodEndUtcExclusive,
  ),
);

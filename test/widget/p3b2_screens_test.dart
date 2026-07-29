/// Widget tests for P3b-2's mutation surface on screen — KHA-26, KHA-64,
/// KHA-74, KHA-78, KHA-80.
///
/// | Surface | Acceptance criteria |
/// |---|---|
/// | S-20 Manual entry / edit | AC-B4.1, **AC-B4.2** (validation names the field), AC-B5.2 |
/// | S-44 Recently deleted | AC-B8.1, AC-B8.2 |
/// | S-18 transfers tab | AC-B11.2 (KHA-78 pairs, KHA-80 unpairables) |
/// | S-18 duplicate merge | AC-A5.2, AC-A5.3 (KHA-64) |
/// | S-18 data-problem banner | KHA-74 |
///
/// Following the existing suites' rules: both locales, and every dense screen
/// at a 2.0 text scale (NFR-U3, NFR-U8).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/features/ingestion/duplicate_policy.dart';
import 'package:massrofy/features/ingestion/review_queue.dart';
import 'package:massrofy/features/ledger/internal_transfer.dart';
import 'package:massrofy/features/ledger/ledger_mapping.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/manual_entry.dart';
import 'package:massrofy/features/ledger/transaction_edit.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';
import 'package:massrofy/presentation/screens/manual_entry_screen.dart';
import 'package:massrofy/presentation/screens/needs_review_screen.dart';
import 'package:massrofy/presentation/screens/recently_deleted_screen.dart';
import 'package:massrofy/presentation/screens/transaction_detail_screen.dart';

import 'p3_screens_test.dart' show useTallSurface, wrap;

LedgerTransaction deletedPurchase({
  int id = 1,
  String amount = '152.75',
  String? merchant = 'EXTRA MART',
}) => LedgerTransaction(
  id: id,
  amount: Money.parse(amount, currency: 'SAR'),
  direction: 'debit',
  transactionType: TransactionType.posPurchase,
  affectsSpend: true,
  occurredAt: DateTime.utc(2026, 7, 15, 10),
  merchantRawText: merchant,
  isDeleted: true,
  deletedAt: DateTime.utc(2026, 7, 20, 8, 30),
);

void main() {
  // =========================================================================
  group('S-20 — Manual entry (US-B4)', () {
    testWidgets('AC-B4.2 — saving with no amount names the AMOUNT field and '
        'emits no draft', (WidgetTester tester) async {
      useTallSurface(tester);
      final List<ManualTransactionDraft> emitted = <ManualTransactionDraft>[];
      await tester.pumpWidget(wrap(ManualEntryScreen(onAdd: emitted.add)));

      await tester.tap(find.byKey(const Key('manualEntry.save')));
      await tester.pumpAndSettle();

      // Not "invalid input" — the message names the field, which is the whole
      // substance of AC-B4.2 (brand voice principle 4).
      expect(
        find.text('Enter an amount to save this transaction'),
        findsOneWidget,
      );
      expect(emitted, isEmpty);
    });

    testWidgets('AC-B4.2 — the type field is named too, and both messages '
        'appear at once rather than one per attempt', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(wrap(ManualEntryScreen(onAdd: (_) {})));

      await tester.tap(find.byKey(const Key('manualEntry.save')));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter an amount to save this transaction'),
        findsOneWidget,
      );
      expect(
        find.text('Choose what kind of transaction this was'),
        findsOneWidget,
      );
    });

    testWidgets('O-QA-2 — a typed minus sign is rejected with the '
        'sign-convention explanation, not silently absolute-valued', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final List<ManualTransactionDraft> emitted = <ManualTransactionDraft>[];
      await tester.pumpWidget(wrap(ManualEntryScreen(onAdd: emitted.add)));

      await tester.enterText(
        find.byKey(const Key('manualEntry.amount')),
        '-50.00',
      );
      await tester.tap(find.byKey(const Key('manualEntry.save')));
      await tester.pumpAndSettle();

      // The message explains the direction control rather than just saying no.
      expect(
        find.text(
          'Enter an amount greater than zero, then choose Money in or '
          'Money out',
        ),
        findsOneWidget,
      );
      expect(emitted, isEmpty);
    });

    testWidgets('a complete form emits a draft with the EXACT typed amount, '
        'unrounded and unreformatted', (WidgetTester tester) async {
      useTallSurface(tester);
      final List<ManualTransactionDraft> emitted = <ManualTransactionDraft>[];
      await tester.pumpWidget(wrap(ManualEntryScreen(onAdd: emitted.add)));

      await tester.enterText(
        find.byKey(const Key('manualEntry.amount')),
        '85.50',
      );
      await tester.enterText(
        find.byKey(const Key('manualEntry.merchant')),
        'CORNER SHOP',
      );
      await tester.tap(find.byKey(const Key('manualEntry.type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Card purchase').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('manualEntry.save')));
      await tester.pumpAndSettle();

      expect(emitted, hasLength(1));
      // The text goes to the service untouched; `Money.tryParse` is the one
      // place that decides what a valid amount is (ADR-002).
      expect(emitted.single.amountText, '85.50');
      expect(emitted.single.currencyCode, 'SAR');
      expect(emitted.single.merchantRawText, 'CORNER SHOP');
    });

    testWidgets('OQ-19 — "Cash" is the default payment method and is named as '
        'one, not shown as an absence', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(wrap(ManualEntryScreen(onAdd: (_) {})));

      expect(find.text('Cash'), findsOneWidget);
      expect(
        find.text(
          'Cash transactions count toward your totals exactly like card ones.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('choosing salary sets the direction to Money in — the sign '
        'lives in the direction control, never in the amount', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final List<ManualTransactionDraft> emitted = <ManualTransactionDraft>[];
      await tester.pumpWidget(wrap(ManualEntryScreen(onAdd: emitted.add)));

      await tester.enterText(
        find.byKey(const Key('manualEntry.amount')),
        '9000.00',
      );
      await tester.tap(find.byKey(const Key('manualEntry.type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salary / income').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('manualEntry.save')));
      await tester.pumpAndSettle();

      expect(emitted.single.direction, 'credit');
    });

    testWidgets('renders in Arabic RTL at a 2.0 text scale without '
        'overflowing (NFR-U3, NFR-U8)', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(ManualEntryScreen(onAdd: (_) {}), locale: 'ar', textScale: 2.0),
      );
      await tester.pumpAndSettle();

      expect(find.text('إضافة معاملة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  group('S-20 in edit mode (US-B5)', () {
    final LedgerTransaction existing = LedgerTransaction(
      id: 9,
      amount: Money.parse('152.75', currency: 'SAR'),
      direction: 'debit',
      transactionType: TransactionType.posPurchase,
      affectsSpend: true,
      occurredAt: DateTime.utc(2026, 7, 15, 10),
      merchantRawText: 'EXTRA MART',
    );

    testWidgets('the form opens pre-filled with the stored canonical amount, '
        'not a re-formatted approximation', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(ManualEntryScreen(existing: existing, onEdit: (_) {})),
      );

      expect(find.text('Edit transaction'), findsOneWidget);
      expect(find.text('152.75'), findsOneWidget);
      expect(find.text('EXTRA MART'), findsOneWidget);
    });

    testWidgets('AC-B5.2 — an edited field shows the ORIGINAL auto-detected '
        'value alongside the current one', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          ManualEntryScreen(
            existing: existing,
            editHistory: const TransactionEditHistory(<String, String?>{
              'merchantRawText': 'EXTR4 M4RT 0042',
            }),
            onEdit: (_) {},
          ),
        ),
      );

      expect(find.text('Originally detected: EXTR4 M4RT 0042'), findsOneWidget);
      // AC-B5.3 made visible: the user is told their edit outranks the parser.
      expect(
        find.text(
          'Your edit is kept — re-reading the message will not overwrite it',
        ),
        findsOneWidget,
      );
    });

    testWidgets('AC-B5.2 — a field the parser produced NOTHING for says so, '
        'rather than showing an empty quotation (AC-B1.3)', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          ManualEntryScreen(
            existing: existing,
            editHistory: const TransactionEditHistory(<String, String?>{
              'merchantRawText': null,
            }),
            onEdit: (_) {},
          ),
        ),
      );
      expect(find.text('Originally detected: nothing'), findsOneWidget);
    });

    testWidgets('an unedited field shows no "originally detected" caption at '
        'all', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(ManualEntryScreen(existing: existing, onEdit: (_) {})),
      );
      expect(find.textContaining('Originally detected'), findsNothing);
    });

    testWidgets('saving emits an edit draft, not an add draft', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final List<TransactionEditDraft> edits = <TransactionEditDraft>[];
      final List<ManualTransactionDraft> adds = <ManualTransactionDraft>[];
      await tester.pumpWidget(
        wrap(
          ManualEntryScreen(
            existing: existing,
            onEdit: edits.add,
            onAdd: adds.add,
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('manualEntry.merchant')),
        'IKEA',
      );
      await tester.tap(find.byKey(const Key('manualEntry.save')));
      await tester.pumpAndSettle();

      expect(adds, isEmpty);
      expect(edits, hasLength(1));
      expect(edits.single.merchantRawText?.value, 'IKEA');
    });
  });

  // =========================================================================
  group('S-11 — Edit / Delete / Restore (US-B5, US-B6, US-B8)', () {
    LedgerTransaction live({bool isDeleted = false}) => LedgerTransaction(
      id: 9,
      amount: Money.parse('152.75', currency: 'SAR'),
      direction: 'debit',
      transactionType: TransactionType.posPurchase,
      affectsSpend: true,
      occurredAt: DateTime.utc(2026, 7, 15, 10),
      merchantRawText: 'EXTRA MART',
      isDeleted: isDeleted,
      deletedAt: isDeleted ? DateTime.utc(2026, 7, 20, 8, 30) : null,
    );

    testWidgets('AC-B6.2 — Delete asks for an explicit confirmation and does '
        'NOTHING until it is given', (WidgetTester tester) async {
      useTallSurface(tester);
      int deletes = 0;
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: live(),
            onDelete: () => deletes++,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('txnDetail.delete')));
      await tester.pumpAndSettle();

      expect(find.text('Delete this transaction?'), findsOneWidget);
      // Nothing has happened yet — the dialog is the gate, not a notification.
      expect(deletes, 0);
    });

    testWidgets('AC-B6.2 — cancelling destroys nothing', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      int deletes = 0;
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: live(),
            onDelete: () => deletes++,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('txnDetail.delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('txnDetail.deleteCancel')));
      await tester.pumpAndSettle();

      expect(deletes, 0);
    });

    testWidgets('confirming performs the delete exactly once', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      int deletes = 0;
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: live(),
            onDelete: () => deletes++,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('txnDetail.delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('txnDetail.deleteConfirm')));
      await tester.pumpAndSettle();

      expect(deletes, 1);
    });

    testWidgets('AC-B8.1 — the confirmation says the transaction is '
        'recoverable, so the user is not deciding under a false impression of '
        'permanence', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(TransactionDetailScreen(transaction: live(), onDelete: () {})),
      );
      await tester.tap(find.byKey(const Key('txnDetail.delete')));
      await tester.pumpAndSettle();

      expect(find.textContaining('moved to Recently deleted'), findsOneWidget);
      // The safe choice is positively worded.
      expect(find.text('Keep it'), findsOneWidget);
    });

    testWidgets('a DELETED transaction offers Restore and not Delete', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: live(isDeleted: true),
            onEdit: () {},
            onDelete: () {},
            onRestore: () {},
          ),
        ),
      );

      expect(find.byKey(const Key('txnDetail.restore')), findsOneWidget);
      expect(find.byKey(const Key('txnDetail.delete')), findsNothing);
      expect(find.byKey(const Key('txnDetail.edit')), findsNothing);
    });

    testWidgets('no callbacks means no buttons — a dead affordance in a '
        'banking app is worse than an absent one (P3a\'s rule, kept)', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(TransactionDetailScreen(transaction: live())),
      );

      expect(find.byKey(const Key('txnDetail.edit')), findsNothing);
      expect(find.byKey(const Key('txnDetail.delete')), findsNothing);
      expect(find.byKey(const Key('txnDetail.restore')), findsNothing);
    });

    testWidgets('the delete confirmation renders in Arabic RTL', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(transaction: live(), onDelete: () {}),
          locale: 'ar',
        ),
      );
      await tester.tap(find.byKey(const Key('txnDetail.delete')));
      await tester.pumpAndSettle();

      expect(find.text('حذف هذه المعاملة؟'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  group('S-44 — Recently deleted (US-B8)', () {
    testWidgets('AC-B8.1 — the screen states that deleted items are kept and '
        'are not in any total', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          RecentlyDeletedScreen(
            deleted: <LedgerTransaction>[deletedPurchase()],
            onRestore: (_) {},
          ),
        ),
      );

      expect(
        find.text(
          'Deleted transactions are kept here and are not counted in any '
          'total. Only Erase everything removes them permanently.',
        ),
        findsOneWidget,
      );
      expect(find.text('EXTRA MART'), findsOneWidget);
    });

    testWidgets('AC-B6.4 — each row shows WHEN it was deleted', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          RecentlyDeletedScreen(
            deleted: <LedgerTransaction>[deletedPurchase()],
            onRestore: (_) {},
          ),
        ),
      );
      // Matched on the year rather than on the word "Deleted", which also
      // appears in the screen's intro paragraph.
      expect(find.textContaining('Deleted 2026-07-'), findsOneWidget);
    });

    testWidgets('AC-B8.2 — Restore is offered per row and returns that '
        'transaction', (WidgetTester tester) async {
      useTallSurface(tester);
      final List<LedgerTransaction> restored = <LedgerTransaction>[];
      await tester.pumpWidget(
        wrap(
          RecentlyDeletedScreen(
            deleted: <LedgerTransaction>[deletedPurchase(id: 7)],
            onRestore: restored.add,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('recentlyDeleted.restore.7')));
      await tester.pumpAndSettle();

      expect(restored.single.id, 7);
    });

    testWidgets('a row removed by a MERGE says so, rather than looking like '
        'something the user deleted', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          RecentlyDeletedScreen(
            deleted: <LedgerTransaction>[deletedPurchase(id: 7)],
            mergedInto: const <int, int>{7: 41},
            onRestore: (_) {},
          ),
        ),
      );
      // In the one screen built to reassure the user nothing is lost, a merge
      // must not read as data loss.
      expect(find.text('Merged into transaction #41'), findsOneWidget);
    });

    testWidgets('the empty state is reassuring, not an error', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          RecentlyDeletedScreen(
            deleted: const <LedgerTransaction>[],
            onRestore: (_) {},
          ),
        ),
      );
      expect(find.text('Nothing has been deleted'), findsOneWidget);
    });

    testWidgets('renders in Arabic RTL at a 2.0 text scale', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          RecentlyDeletedScreen(
            deleted: <LedgerTransaction>[deletedPurchase()],
            onRestore: (_) {},
          ),
          locale: 'ar',
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('المحذوفات مؤخراً'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  group('S-18 — the transfers tab (AC-B11.2)', () {
    const TransferReviewItem candidate = TransferReviewItem(
      transactionId: 1,
      counterpartTransactionId: 2,
      groupId: 'itl:1:2',
      amount: '2000.00',
      currencyCode: 'SAR',
    );

    Widget inbox({
      List<TransferReviewItem> transfers = const <TransferReviewItem>[],
      List<UnreadableTransaction> unreadable = const <UnreadableTransaction>[],
      void Function(TransferReviewItem, bool)? onVerdict,
    }) => NeedsReviewScreen(
      unparsed: const <ReviewQueueItem>[],
      flagged: const <FlaggedTransactionItem>[],
      transfers: transfers,
      unreadable: unreadable,
      onFillInDetails: (_) {},
      onNotATransaction: (_) {},
      onOpenFlagged: (_) {},
      onTransferVerdict: onVerdict,
    );

    testWidgets('KHA-78 — a derived candidate now REACHES the inbox, which is '
        'the gap this issue was about', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(inbox(transfers: const <TransferReviewItem>[candidate])),
      );

      expect(find.text('Transfers (1)'), findsOneWidget);
      await tester.tap(find.text('Transfers (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Possible internal transfer'), findsOneWidget);
      expect(
        find.text('Was this a transfer to your own account?'),
        findsOneWidget,
      );
      // The AC-B11.2 copy already in the .arb files, as KHA-78 asked.
      expect(
        find.text(
          'Still counted as spend until you confirm this went to your own '
          'account',
        ),
        findsOneWidget,
      );
    });

    testWidgets('confirm and reject are BOTH offered for a pair, and report '
        'the verdict', (WidgetTester tester) async {
      useTallSurface(tester);
      final List<bool> verdicts = <bool>[];
      await tester.pumpWidget(
        wrap(
          inbox(
            transfers: const <TransferReviewItem>[candidate],
            onVerdict: (_, bool isOwn) => verdicts.add(isOwn),
          ),
        ),
      );
      await tester.tap(find.text('Transfers (1)'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('needsReview.transferConfirm.1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('needsReview.transferReject.1')));
      await tester.pumpAndSettle();

      expect(verdicts, <bool>[true, false]);
    });

    testWidgets('KHA-80 — an UNPAIRABLE cross-currency transfer offers only '
        'the dismiss action, with its own explanation', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          inbox(
            transfers: const <TransferReviewItem>[
              TransferReviewItem(
                transactionId: 5,
                amount: '2000.00',
                currencyCode: 'SAR',
                unpairableReasonKey: TransferReviewReasonKey.crossCurrency,
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Transfers (1)'));
      await tester.pumpAndSettle();

      // A different sentence from the paired-candidate one, as KHA-80 asked.
      expect(
        find.textContaining('A transfer in another currency happened'),
        findsOneWidget,
      );
      // Confirming one leg alone would exclude an amount whose partner keeps
      // counting, so it is not offered at all.
      expect(
        find.byKey(const Key('needsReview.transferConfirm.5')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('needsReview.transferDismiss.5')),
        findsOneWidget,
      );
    });

    testWidgets('KHA-80 — an unresolved-instrument near-match gets its own '
        'sentence, not the cross-currency one', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          inbox(
            transfers: const <TransferReviewItem>[
              TransferReviewItem(
                transactionId: 6,
                amount: '2000.00',
                currencyCode: 'SAR',
                unpairableReasonKey:
                    TransferReviewReasonKey.unresolvedInstrument,
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Transfers (1)'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('we could not tell which account it reached'),
        findsOneWidget,
      );
    });

    testWidgets('an empty transfers tab shows the reassuring empty state, not '
        'an amber warning about nothing', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(wrap(inbox()));
      await tester.tap(find.text('Transfers (0)'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing needs review right now'), findsOneWidget);
    });

    testWidgets('renders in Arabic RTL at a 2.0 text scale', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          inbox(transfers: const <TransferReviewItem>[candidate]),
          locale: 'ar',
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  group('S-18 — the duplicate merge action (KHA-64, AC-A5.2/A5.3)', () {
    const FlaggedTransactionItem flagged = FlaggedTransactionItem(
      transactionId: 9,
      amount: '152.75',
      currencyCode: 'SAR',
      merchantRawText: 'EXTRA MART',
      reviewReason: ReviewReason.possibleDuplicate,
      possibleDuplicateOfId: 8,
    );

    Widget inbox({
      void Function(FlaggedTransactionItem)? onMerge,
      void Function(FlaggedTransactionItem)? onKeepBoth,
      FlaggedTransactionItem item = flagged,
    }) => NeedsReviewScreen(
      unparsed: const <ReviewQueueItem>[],
      flagged: <FlaggedTransactionItem>[item],
      onFillInDetails: (_) {},
      onNotATransaction: (_) {},
      onOpenFlagged: (_) {},
      onMergeDuplicate: onMerge,
      onKeepBothDuplicates: onKeepBoth,
    );

    testWidgets('the merge copy tells the user what a merge DOES before they '
        'commit to it (risk R-8)', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(wrap(inbox(onMerge: (_) {}, onKeepBoth: (_) {})));
      await tester.tap(find.text('Low confidence (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Are these the same transaction?'), findsOneWidget);
      expect(find.textContaining('nothing is destroyed'), findsOneWidget);
    });

    testWidgets('merging requires an explicit tap, and "keep both" is exactly '
        'as easy (AC-A5.3)', (WidgetTester tester) async {
      useTallSurface(tester);
      final List<String> actions = <String>[];
      await tester.pumpWidget(
        wrap(
          inbox(
            onMerge: (_) => actions.add('merge'),
            onKeepBoth: (_) => actions.add('keep'),
          ),
        ),
      );
      await tester.tap(find.text('Low confidence (1)'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('needsReview.keepBoth.9')));
      await tester.pumpAndSettle();
      // O-QA-8: merging now goes through a confirmation, so the tap opens the
      // dialog and the second tap is the commitment.
      await tester.tap(find.byKey(const Key('needsReview.merge.9')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('needsReview.mergeConfirm.9')));
      await tester.pumpAndSettle();

      // The app has no idea which is right, so the UI must not imply it.
      expect(actions, <String>['keep', 'merge']);
    });

    testWidgets('O-QA-8 — a single tap on Merge does NOT merge: it asks '
        'first, like delete does (risk R-8)', (WidgetTester tester) async {
      // `build-plan.md` calls the merge "the single highest-risk operation in
      // P3", and until KHA-90 it was one tap away while the strictly less
      // dangerous soft delete took two. This test is the guard on that.
      useTallSurface(tester);
      final List<String> actions = <String>[];
      await tester.pumpWidget(
        wrap(inbox(onMerge: (_) => actions.add('merge'), onKeepBoth: (_) {})),
      );
      await tester.tap(find.text('Low confidence (1)'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('needsReview.merge.9')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Merge these two into one?'), findsOneWidget);
      // The dialog states the effect on totals AND the reversibility, so the
      // user is not deciding under a false impression of permanence. Scoped to
      // the dialog because the card behind it says something similar — which
      // is the point: the two say the same thing, one before and one during.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('nothing is destroyed'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('can be restored at any time'),
        ),
        findsOneWidget,
      );
      expect(
        actions,
        isEmpty,
        reason: 'opening the dialog must not have merged anything yet',
      );
    });

    testWidgets('O-QA-8 — cancelling the confirmation merges nothing', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final List<String> actions = <String>[];
      await tester.pumpWidget(
        wrap(inbox(onMerge: (_) => actions.add('merge'), onKeepBoth: (_) {})),
      );
      await tester.tap(find.text('Low confidence (1)'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('needsReview.merge.9')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('needsReview.mergeCancel.9')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(actions, isEmpty);
      // The card is still there with its decision unmade — the pair stays
      // flagged rather than quietly resolving itself.
      expect(find.byKey(const Key('needsReview.merge.9')), findsOneWidget);
    });

    testWidgets('O-QA-8 — dismissing the dialog by tapping outside it merges '
        'nothing either (showDialog returns null)', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final List<String> actions = <String>[];
      await tester.pumpWidget(
        wrap(inbox(onMerge: (_) => actions.add('merge'), onKeepBoth: (_) {})),
      );
      await tester.tap(find.text('Low confidence (1)'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('needsReview.merge.9')));
      await tester.pumpAndSettle();
      // Tap the barrier, well away from the dialog itself.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(actions, isEmpty);
    });

    testWidgets('no merge button is offered when there is no counterpart to '
        'merge with — the action is never shown without a target', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          inbox(
            onMerge: (_) {},
            item: const FlaggedTransactionItem(
              transactionId: 9,
              amount: '152.75',
              currencyCode: 'SAR',
              merchantRawText: 'EXTRA MART',
              reviewReason: ReviewReason.possibleDuplicate,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Low confidence (1)'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('needsReview.merge.9')), findsNothing);
    });
  });

  // =========================================================================
  group('S-18 — the data-problem banner (KHA-74)', () {
    Widget inbox(List<UnreadableTransaction> unreadable) => NeedsReviewScreen(
      unparsed: const <ReviewQueueItem>[],
      flagged: const <FlaggedTransactionItem>[],
      unreadable: unreadable,
      onFillInDetails: (_) {},
      onNotATransaction: (_) {},
      onOpenFlagged: (_) {},
    );

    testWidgets('an unreadable transaction is announced ABOVE the tabs, where '
        'it cannot be missed', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          inbox(const <UnreadableTransaction>[
            UnreadableTransaction(
              transactionId: 41,
              reason: UnreadableReason.unparsableAmount,
            ),
          ]),
        ),
      );

      expect(find.text('A transaction could not be read'), findsOneWidget);
      expect(
        find.text('1 transaction is missing from your totals'),
        findsOneWidget,
      );
      // The row id is named so the problem is actionable; the unreadable
      // value itself is never rendered (NFR-S4).
      expect(find.textContaining('Transaction #41'), findsOneWidget);
    });

    testWidgets('a healthy ledger shows no banner at all', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(wrap(inbox(const <UnreadableTransaction>[])));
      expect(find.text('A transaction could not be read'), findsNothing);
    });

    testWidgets('renders in Arabic RTL at a 2.0 text scale', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          inbox(const <UnreadableTransaction>[
            UnreadableTransaction(
              transactionId: 41,
              reason: UnreadableReason.unparsableAmount,
            ),
          ]),
          locale: 'ar',
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('تعذّرت قراءة إحدى المعاملات'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

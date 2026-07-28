/// Widget tests for every screen P3a adds:
///
/// | Screen | Mockup | Acceptance criteria |
/// |---|---|---|
/// | S-11 Transaction Detail | `transaction-detail.html` | AC-B1.1, AC-B1.2, AC-B1.3, AC-B1.4 |
/// | S-21 Banks List | `banks.html` | AC-B2.1, AC-B12.1 |
/// | S-22 Bank Detail | `banks.html` | AC-B2.2, AC-B12.2, AC-B13.3 |
/// | S-23/24 Instrument Detail | `banks.html` | AC-B2.3, AC-B14.2, AC-B14.3, AC-B15.2 |
/// | S-25 Rename sheet | `banks.html` | AC-B3.1 |
/// | S-19 Complete Unparsed SMS | `needs-review.html` | AC-A4.2, AC-B4.2 |
///
/// Following the P2 suite's rules: every screen is exercised in **both**
/// locales (Arabic RTL is the primary direction — design.md §3.1), and the
/// ones with dense field lists are also rendered at a 2.0 text scale, because
/// NFR-U3 requires no truncation at the largest OS font size.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/features/ingestion/review_queue.dart';
import 'package:massrofy/features/ledger/bank_tree.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/unparsed_completion.dart';
import 'package:massrofy/presentation/l10n/generated/app_localizations.dart';
import 'package:massrofy/presentation/screens/banks_screen.dart';
import 'package:massrofy/presentation/screens/complete_unparsed_screen.dart';
import 'package:massrofy/presentation/screens/instrument_detail_screen.dart';
import 'package:massrofy/presentation/screens/transaction_detail_screen.dart';

/// Gives the test a phone-shaped but **tall** surface.
///
/// These screens are scrolling forms and lists, and a `ListView` builds
/// lazily: on the default 800×600 test window the Save button of a long form
/// is never constructed, so a finder for it fails for a reason that has
/// nothing to do with the behaviour under test. A taller viewport keeps the
/// tests about the screens rather than about scroll mechanics.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget wrap(Widget child, {String locale = 'en', double textScale = 1.0}) {
  return MaterialApp(
    locale: Locale(locale),
    localizationsDelegates: const <LocalizationsDelegate<Object?>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
    builder: (BuildContext context, Widget? navigator) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: navigator!,
    ),
    home: child,
  );
}

const LedgerInstrument blueVisa = LedgerInstrument(
  id: 11,
  bankId: 1,
  kind: InstrumentKind.card,
  maskedIdentifier: '****4821',
  friendlyName: 'Blue Visa',
  network: 'mada',
  settlementAccountId: 10,
);

const LedgerInstrument unnamedCard = LedgerInstrument(
  id: 12,
  bankId: 1,
  kind: InstrumentKind.card,
  maskedIdentifier: '****7765',
);

final LedgerTransaction posPurchase = LedgerTransaction(
  id: 1,
  amount: Money.parse('152.75', currency: 'SAR'),
  direction: 'debit',
  transactionType: 'pos_purchase',
  affectsSpend: true,
  occurredAt: DateTime.utc(2026, 7, 28, 11, 32),
  merchantRawText: 'EXTRA MART 0042',
  instrument: blueVisa,
  instrumentMaskedRefFromMessage: '****4821',
  sourceMessageId: 5,
  rulePackId: 'sa-core',
  ruleId: 'baj-pos-purchase-ar',
);

void main() {
  group('S-11 — Transaction Detail (AC-B1.1..B1.4)', () {
    testWidgets('AC-B1.1 — amount, merchant, date-time, instrument and type '
        'are all displayed', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: posPurchase,
            bankDisplayName: 'Bank Aljazira',
            originalMessageText: 'شراء بطاقة:مدى-****4821 مبلغ:152.75 SAR',
          ),
        ),
      );

      // Twice: once as the headline, once in the "Merchant / payee" field
      // row. AC-B1.1 asks for the merchant to be displayed; the header is the
      // glanceable copy and the field row is the labelled one.
      expect(find.text('EXTRA MART 0042'), findsNWidgets(2));
      expect(find.text('−152.75 SAR'), findsOneWidget);
      expect(find.text('Card purchase'), findsOneWidget);
      expect(find.text('Blue Visa'), findsOneWidget);
      expect(find.text('•••• 4821'), findsWidgets);
      expect(find.text('SMS · Bank Aljazira'), findsOneWidget);
    });

    testWidgets('AC-B1.4 — the amount is the exact stored decimal, with no '
        'rounding and no re-formatting', (WidgetTester tester) async {
      useTallSurface(tester);
      // A value that a float round-trip would corrupt, and one with more
      // precision than SAR's two minor digits.
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: LedgerTransaction(
              id: 2,
              amount: Money.parse('1234567.891', currency: 'SAR'),
              direction: 'debit',
              transactionType: 'pos_purchase',
              affectsSpend: true,
              occurredAt: DateTime.utc(2026, 7, 1),
            ),
          ),
        ),
      );

      expect(find.text('−1234567.891 SAR'), findsOneWidget);
    });

    testWidgets('AC-B1.3 — a field the message did not state reads as '
        '"Not stated in message", never blank', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: LedgerTransaction(
              id: 3,
              amount: Money.parse('15.00', currency: 'SAR'),
              direction: 'debit',
              transactionType: 'fee',
              affectsSpend: true,
              occurredAt: DateTime.utc(2026, 7, 25, 5),
              // No merchant, no instrument, no reference.
            ),
            bankDisplayName: 'D360 Bank',
          ),
        ),
      );

      // Merchant, instrument and reference number are all unknown here, so
      // the literal text appears three times — and nowhere is there an empty
      // row the user would have to interpret.
      expect(find.text('Not stated in message'), findsNWidgets(3));
    });

    testWidgets('AC-B1.2 — the original message is available, collapsed by '
        'default and expandable', (WidgetTester tester) async {
      useTallSurface(tester);
      const String original = 'شراء بطاقة:مدى-****4821 مبلغ:152.75 SAR';
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: posPurchase,
            bankDisplayName: 'Bank Aljazira',
            originalMessageText: original,
          ),
        ),
      );

      // Collapsed: the raw text is not on screen over someone's shoulder.
      expect(find.text(original), findsNothing);

      await tester.tap(find.text('Show original message'));
      await tester.pumpAndSettle();

      expect(find.text(original), findsOneWidget);
      expect(find.text('Hide original message'), findsOneWidget);
    });

    testWidgets('a manual entry says there is no original message rather than '
        'offering an expander onto nothing', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: LedgerTransaction(
              id: 4,
              amount: Money.parse('32.00', currency: 'SAR'),
              direction: 'debit',
              transactionType: 'pos_purchase',
              affectsSpend: true,
              occurredAt: DateTime.utc(2026, 7, 22, 18),
              merchantRawText: 'Taxi — cash',
              provenance: TransactionProvenance.manual,
            ),
          ),
        ),
      );

      expect(find.text('Show original message'), findsNothing);
      expect(
        find.text('No original message — this transaction was added manually'),
        findsOneWidget,
      );
      // AC-B4.3 — visually distinguishable from an SMS-derived transaction.
      expect(find.text('Manual'), findsOneWidget);
      expect(find.text('Manual entry'), findsOneWidget);
    });

    testWidgets('KHA-64 — a completed message reads as SMS provenance '
        'completed by the user, not as a plain manual entry', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: LedgerTransaction(
              id: 5,
              amount: Money.parse('75.50', currency: 'SAR'),
              direction: 'debit',
              transactionType: 'account_debit',
              affectsSpend: true,
              occurredAt: DateTime.utc(2026, 7, 20, 6),
              provenance: TransactionProvenance.sms,
              provenanceDetail: ProvenanceDetail.manualCompletion,
              sourceMessageId: 9,
            ),
            bankDisplayName: 'Bank Aljazira',
            originalMessageText: 'خصم من حسابك',
          ),
        ),
      );

      expect(
        find.text('SMS · Bank Aljazira · completed by you'),
        findsOneWidget,
      );
      expect(find.text('Manual'), findsOneWidget);
    });

    testWidgets('a credit is signed and labelled as one (US-B7, NFR-U4)', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: LedgerTransaction(
              id: 6,
              amount: Money.parse('50.00', currency: 'SAR'),
              direction: 'credit',
              transactionType: 'refund',
              affectsSpend: true,
              occurredAt: DateTime.utc(2026, 7, 12),
              merchantRawText: 'EXTRA MART 0042',
            ),
          ),
        ),
      );

      expect(find.text('+50.00 SAR'), findsOneWidget);
      expect(find.text('Refund'), findsOneWidget);
      // The sign is not the only indicator: a semantic label rides with it.
      expect(
        tester
            .widget<Semantics>(
              find
                  .ancestor(
                    of: find.text('+50.00 SAR'),
                    matching: find.byType(Semantics),
                  )
                  .first,
            )
            .properties
            .label,
        'Credit',
      );
    });

    testWidgets('the FX block appears only when the message carried one', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: LedgerTransaction(
              id: 7,
              amount: Money.parse('49.99', currency: 'USD'),
              convertedAmount: Money.parse('187.46', currency: 'SAR'),
              feeAmount: Money.parse('4.69', currency: 'SAR'),
              direction: 'debit',
              transactionType: 'online_purchase',
              affectsSpend: true,
              occurredAt: DateTime.utc(2026, 7, 26, 6, 14),
              merchantRawText: 'GLOBAL CLOUD SERVICES',
            ),
          ),
        ),
      );

      // The fee is its own row — PRD §3.4's requirement that it never be
      // folded into the spend amount, made visible.
      expect(find.text('187.46 SAR'), findsOneWidget);
      expect(find.text('4.69 SAR'), findsOneWidget);
      expect(find.text('−49.99 USD'), findsOneWidget);
      // The rate was not stated by this message.
      expect(find.text('Not stated in message'), findsWidgets);
    });

    testWidgets('a deleted transaction is unmistakably out of every total', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: LedgerTransaction(
              id: 8,
              amount: Money.parse('10.00', currency: 'SAR'),
              direction: 'debit',
              transactionType: 'fee',
              affectsSpend: true,
              occurredAt: DateTime.utc(2026, 7, 2),
              isDeleted: true,
              deletedAt: DateTime.utc(2026, 7, 3),
            ),
          ),
        ),
      );

      expect(
        find.text('This transaction is deleted and is in no total'),
        findsOneWidget,
      );
    });

    testWidgets('renders in Arabic RTL', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: posPurchase,
            bankDisplayName: 'بنك الجزيرة',
            originalMessageText: 'شراء',
          ),
          locale: 'ar',
        ),
      );

      expect(find.text('المعاملة'), findsOneWidget);
      expect(find.text('التاريخ والوقت'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('المعاملة'))),
        TextDirection.rtl,
      );
    });

    testWidgets('NFR-U3 — no overflow at 2.0 text scale', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          TransactionDetailScreen(
            transaction: posPurchase,
            bankDisplayName: 'Bank Aljazira',
            originalMessageText: 'شراء',
          ),
          locale: 'ar',
          textScale: 2.0,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('S-21 — Banks List (AC-B2.1, AC-B12.1)', () {
    testWidgets('the empty state explains that banks appear by themselves', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(BanksScreen(banks: const <BankTreeNode>[], onOpenBank: (_) {})),
      );

      expect(find.text('No banks yet'), findsOneWidget);
      expect(
        find.textContaining('automatically the first time a message arrives'),
        findsOneWidget,
      );
    });

    testWidgets('each bank shows its own figure and opens on tap', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      BankTreeNode? opened;
      await tester.pumpWidget(
        wrap(
          BanksScreen(
            banks: <BankTreeNode>[_aljaziraNode(), _d360Node()],
            onOpenBank: (BankTreeNode node) => opened = node,
          ),
        ),
      );

      expect(find.text('Bank Aljazira'), findsOneWidget);
      expect(find.text('−2140.00 SAR'), findsOneWidget);
      expect(find.text('D360 Bank'), findsOneWidget);
      // ICU plurals, not "1 accounts". The Arabic build gets its own
      // dual/few/many forms from the same call site.
      expect(find.text('1 account · 2 cards'), findsOneWidget);
      expect(find.text('1 account · no cards'), findsOneWidget);

      await tester.tap(find.text('Bank Aljazira'));
      expect(opened?.bank.canonicalKey, 'bank-aljazira');
    });

    testWidgets('renders in Arabic RTL with the Arabic bank name', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          BanksScreen(
            banks: <BankTreeNode>[_aljaziraNode()],
            onOpenBank: (_) {},
          ),
          locale: 'ar',
        ),
      );

      expect(find.text('البنوك'), findsOneWidget);
      expect(find.text('بنك الجزيرة'), findsOneWidget);
    });
  });

  group('S-22 — Bank Detail (AC-B12.2, AC-B13.3)', () {
    testWidgets('accounts and cards are separate segments, never one merged '
        'list', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(BankDetailScreen(node: _aljaziraNode(), onOpenInstrument: (_) {})),
      );

      expect(find.text('Accounts (1)'), findsOneWidget);
      expect(find.text('Cards (2)'), findsOneWidget);

      // The accounts segment is showing: the salary account is visible and
      // the cards are not.
      expect(find.text('Salary Account'), findsOneWidget);
      expect(find.text('Blue Visa'), findsNothing);

      await tester.tap(find.text('Cards (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Blue Visa'), findsOneWidget);
      expect(find.text('Salary Account'), findsNothing);
    });

    testWidgets('AC-B15.2 — an auto-created card is labelled by its masked '
        'identifier and captioned as unnamed', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(BankDetailScreen(node: _aljaziraNode(), onOpenInstrument: (_) {})),
      );
      await tester.tap(find.text('Cards (2)'));
      await tester.pumpAndSettle();

      expect(find.text('•••• 7765'), findsOneWidget);
      expect(find.text('Not named yet'), findsOneWidget);
    });

    testWidgets('AC-B12.2 — the bank total is shown above the segments', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(BankDetailScreen(node: _aljaziraNode(), onOpenInstrument: (_) {})),
      );

      expect(find.text('Total this period'), findsOneWidget);
      expect(find.text('−2140.00 SAR'), findsOneWidget);
    });

    testWidgets('a bank with no instruments says so instead of showing an '
        'empty segment', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          BankDetailScreen(
            node: const BankTreeNode(
              bank: LedgerBank(
                id: 3,
                canonicalKey: 'bank-new',
                displayNameAr: 'بنك',
                displayNameEn: 'New Bank',
              ),
              accounts: <InstrumentSummary>[],
              cards: <InstrumentSummary>[],
              totals: PeriodTotals.empty,
            ),
            onOpenInstrument: (_) {},
          ),
        ),
      );

      expect(
        find.text('No accounts or cards mentioned for this bank yet'),
        findsOneWidget,
      );
      expect(find.text('No transactions in this period'), findsOneWidget);
    });
  });

  group('S-23/S-24 — Instrument Detail (AC-B2.3, AC-B14.2, AC-B14.3)', () {
    testWidgets('AC-B14.2 — a linked card shows its settlement account', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          InstrumentDetailScreen(
            summary: _blueVisaSummary(),
            transactions: <LedgerTransaction>[posPurchase],
            onRename: (_) {},
          ),
        ),
      );

      expect(find.text('Settles from Salary Account'), findsOneWidget);
    });

    testWidgets('AC-B14.3 — an unlinked card says so neutrally, and offers no '
        'guess', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          InstrumentDetailScreen(
            summary: _unnamedCardSummary(),
            transactions: const <LedgerTransaction>[],
            onRename: (_) {},
          ),
        ),
      );

      expect(
        find.text('Not linked to a settlement account yet'),
        findsOneWidget,
      );
      expect(find.text('No transactions on this one yet'), findsOneWidget);
    });

    testWidgets('AC-B2.3 — only this instrument\'s transactions are listed, '
        'with its own total above them', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          InstrumentDetailScreen(
            summary: _blueVisaSummary(),
            transactions: <LedgerTransaction>[posPurchase],
            onRename: (_) {},
          ),
        ),
      );

      expect(find.text('Recent transactions'), findsOneWidget);
      expect(find.text('EXTRA MART 0042'), findsOneWidget);
      expect(find.text('−152.75 SAR'), findsWidgets);
    });

    testWidgets('S-25 — the rename sheet returns the new name (AC-B3.1)', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      String? renamedTo;
      await tester.pumpWidget(
        wrap(
          InstrumentDetailScreen(
            summary: _unnamedCardSummary(),
            transactions: const <LedgerTransaction>[],
            onRename: (String? name) => renamedTo = name,
          ),
        ),
      );

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(find.text('Friendly name'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Everyday mada');
      await tester.tap(find.text('Save name'));
      await tester.pumpAndSettle();

      expect(renamedTo, 'Everyday mada');
    });

    testWidgets('renders in Arabic RTL at 2.0 text scale without overflow', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          InstrumentDetailScreen(
            summary: _blueVisaSummary(),
            transactions: <LedgerTransaction>[posPurchase],
            onRename: (_) {},
          ),
          locale: 'ar',
          textScale: 2.0,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('أحدث المعاملات'), findsOneWidget);
    });
  });

  group('S-19 — Complete Unparsed SMS (AC-A4.2, AC-B4.2)', () {
    final ReviewQueueItem item = ReviewQueueItem(
      rawMessageId: 77,
      sanitizedBody: 'خصم من حسابك. الرصيد المتبقي 500',
      sender: 'BAJ',
      receivedAt: DateTime.utc(2026, 7, 20, 9),
      bankId: 'bank-aljazira',
      unparsedReason: 'required_field_missing',
    );

    testWidgets('the original message is on screen while the user types', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(CompleteUnparsedScreen(item: item, onSave: (_) {})),
      );

      expect(find.text('Original message'), findsOneWidget);
      expect(find.text('خصم من حسابك. الرصيد المتبقي 500'), findsOneWidget);
    });

    testWidgets('AC-B4.2 — saving with no amount names the missing field and '
        'emits no draft', (WidgetTester tester) async {
      useTallSurface(tester);
      UnparsedCompletionDraft? saved;
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(
            item: item,
            onSave: (UnparsedCompletionDraft draft) => saved = draft,
          ),
        ),
      );

      await tester.tap(find.text('Save as transaction'));
      await tester.pumpAndSettle();

      expect(saved, isNull);
      expect(
        find.text('Enter an amount to save this transaction'),
        findsOneWidget,
      );
      expect(
        find.text('Choose what kind of transaction this is'),
        findsOneWidget,
      );
    });

    testWidgets('a completed form emits a draft carrying the message id and '
        'the exact typed amount', (WidgetTester tester) async {
      useTallSurface(tester);
      UnparsedCompletionDraft? saved;
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(
            item: item,
            onSave: (UnparsedCompletionDraft draft) => saved = draft,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).first, '75.50');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Account debit').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save as transaction'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.rawMessageId, 77);
      expect(saved!.amountText, '75.50');
      expect(saved!.currencyCode, 'SAR');
      expect(saved!.transactionType, 'account_debit');
      expect(saved!.direction, 'debit');
      expect(saved!.affectsSpend, isTrue);
      expect(
        saved!.instrumentId,
        isNull,
        reason:
            'the instrument picker defaults to "Not stated" — AC-B1.3, not a '
            'pre-selected guess',
      );
    });

    testWidgets('choosing a refund flips the direction to credit (US-B7)', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      UnparsedCompletionDraft? saved;
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(
            item: item,
            onSave: (UnparsedCompletionDraft draft) => saved = draft,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).first, '20.00');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refund').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as transaction'));
      await tester.pumpAndSettle();

      expect(saved!.direction, 'credit');
    });

    testWidgets('choosing a card repayment marks it as not affecting spend '
        '(US-B10/B11)', (WidgetTester tester) async {
      useTallSurface(tester);
      UnparsedCompletionDraft? saved;
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(
            item: item,
            onSave: (UnparsedCompletionDraft draft) => saved = draft,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).first, '1500.00');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Credit-card repayment').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as transaction'));
      await tester.pumpAndSettle();

      expect(
        saved!.affectsSpend,
        isFalse,
        reason:
            'counting a repayment as spend double-counts the purchases it '
            'settles',
      );
    });

    testWidgets('the form offers existing instruments but cannot create one', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(
            item: item,
            instruments: <InstrumentSummary>[_blueVisaSummary()],
            onSave: (_) {},
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();

      expect(find.text('Not stated'), findsWidgets);
      expect(find.text('Card · Blue Visa'), findsWidgets);
    });

    testWidgets('renders in Arabic RTL', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(item: item, onSave: (_) {}),
          locale: 'ar',
        ),
      );

      expect(find.text('إكمال التفاصيل'), findsOneWidget);
      expect(find.text('حفظ كمعاملة'), findsOneWidget);
    });
  });
}

// --- fixtures ---------------------------------------------------------------

/// A base-currency-only period figure — the ordinary case for these screens.
///
/// P3b-1 gave [PeriodTotals] a base-currency headline alongside the native
/// per-currency breakdown (KHA-27), so a total now has to state both. These
/// fixtures keep both in agreement, which is what a SAR-only ledger produces:
/// nothing needed converting, so the base figure and the SAR figure are the
/// same number and `unconverted` is empty.
PeriodTotals _sarTotal(String amount, {required int count}) {
  final Money money = Money.parse(amount, currency: 'SAR');
  return PeriodTotals(
    base: money,
    baseCurrencyCode: 'SAR',
    convertedCount: count,
    byCurrency: <CurrencyTotal>[
      CurrencyTotal(currencyCode: 'SAR', net: money, transactionCount: count),
    ],
    unconverted: const <UnconvertedGroup>[],
  );
}

InstrumentSummary _blueVisaSummary() => InstrumentSummary(
  instrument: blueVisa,
  totals: _sarTotal('1500.00', count: 2),
  settlementAccountLabel: 'Salary Account',
);

InstrumentSummary _unnamedCardSummary() => const InstrumentSummary(
  instrument: unnamedCard,
  totals: PeriodTotals.empty,
);

InstrumentSummary _salaryAccountSummary() => InstrumentSummary(
  instrument: const LedgerInstrument(
    id: 10,
    bankId: 1,
    kind: InstrumentKind.account,
    maskedIdentifier: '****3388',
    friendlyName: 'Salary Account',
  ),
  totals: _sarTotal('640.00', count: 1),
);

BankTreeNode _aljaziraNode() => BankTreeNode(
  bank: const LedgerBank(
    id: 1,
    canonicalKey: 'bank-aljazira',
    displayNameAr: 'بنك الجزيرة',
    displayNameEn: 'Bank Aljazira',
  ),
  accounts: <InstrumentSummary>[_salaryAccountSummary()],
  cards: <InstrumentSummary>[_blueVisaSummary(), _unnamedCardSummary()],
  totals: _sarTotal('2140.00', count: 3),
);

BankTreeNode _d360Node() => BankTreeNode(
  bank: const LedgerBank(
    id: 2,
    canonicalKey: 'd360',
    displayNameAr: 'دي ٣٦٠',
    displayNameEn: 'D360 Bank',
  ),
  accounts: <InstrumentSummary>[
    InstrumentSummary(
      instrument: const LedgerInstrument(
        id: 20,
        bankId: 2,
        kind: InstrumentKind.account,
        maskedIdentifier: '****9911',
      ),
      totals: _sarTotal('1074.50', count: 2),
    ),
  ],
  cards: const <InstrumentSummary>[],
  totals: _sarTotal('1074.50', count: 2),
);

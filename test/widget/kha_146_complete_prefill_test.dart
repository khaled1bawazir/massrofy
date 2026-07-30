/// **KHA-146 — S-19 "Complete the details" pre-fills what the parser read.**
///
/// The live evidence this file turns into assertions: a purchase notification
/// containing a type word, a card, a merchant, an amount and a date reached
/// the completion form with **only the date** filled in, and the user was
/// asked to retype the rest by hand from a message displayed two inches above
/// the empty boxes.
///
/// The two cases, kept apart here as everywhere else in this fix:
///
///  - a message whose rule extracted several fields and failed ONE required
///    one arrives with every other field pre-filled;
///  - a message no rule recognised arrives blank, exactly as before.
///
/// ## And the money-safety half
///
/// Pre-filling must not become auto-saving. The form still validates, the
/// draft is still only emitted when the user presses **Save as transaction**,
/// and a notice says out loud that the app filled these boxes in — so a
/// misreading is visible rather than assumed. All three are asserted.
///
/// ## NFR-M3
///
/// The message text is fabricated (`test/support/kha146_synthetic_pack.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/features/ingestion/review_queue.dart';
import 'package:massrofy/features/ledger/bank_tree.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/unparsed_completion.dart';
import 'package:massrofy/features/parsing/partial_extraction.dart';
import 'package:massrofy/presentation/screens/complete_unparsed_screen.dart';

import '../support/kha146_synthetic_pack.dart';
import 'p3_screens_test.dart' show useTallSurface, wrap;

/// What the parser reads out of [syntheticMissingOneRequiredField]: everything
/// except the required remaining balance.
final PartialExtraction _partial = PartialExtraction(
  amountText: '152.75',
  currencyCode: 'SAR',
  merchantRawText: 'SAMPLE MARKET 7',
  instrumentKind: InstrumentKind.card,
  instrumentMaskedRef: '****4821',
  occurredAtUtc: DateTime.utc(2026, 7, 30, 6, 14),
  transactionType: 'pos_purchase',
  missingFields: const <String>['remainingBalance'],
);

/// Case (b) — a rule matched, extracted, and failed one required field.
ReviewQueueItem _partiallyParsedItem({PartialExtraction? partial}) =>
    ReviewQueueItem(
      rawMessageId: 77,
      sanitizedBody: syntheticMissingOneRequiredField,
      sender: syntheticSender,
      receivedAt: DateTime.utc(2026, 7, 30, 9),
      bankId: syntheticBankId,
      unparsedReason: 'required_field_missing',
      partialExtraction: partial ?? _partial,
    );

/// Case (a) — no rule recognised the message, so nothing was extracted.
ReviewQueueItem _unrecognisedItem() => ReviewQueueItem(
  rawMessageId: 78,
  sanitizedBody: syntheticNoRuleMatches,
  sender: syntheticSender,
  receivedAt: DateTime.utc(2026, 7, 30, 9),
  bankId: syntheticBankId,
  unparsedReason: 'no_rule_matched',
);

/// An existing card whose last four digits are the ones the message named.
InstrumentSummary _matchingCard() => InstrumentSummary(
  instrument: const LedgerInstrument(
    id: 11,
    bankId: 1,
    kind: InstrumentKind.card,
    maskedIdentifier: '****4821',
    friendlyName: 'Blue Visa',
  ),
  totals: _emptyTotals,
);

/// A card that is emphatically NOT the one the message named.
InstrumentSummary _otherCard() => InstrumentSummary(
  instrument: const LedgerInstrument(
    id: 12,
    bankId: 1,
    kind: InstrumentKind.card,
    maskedIdentifier: '****9999',
    friendlyName: 'Other Card',
  ),
  totals: _emptyTotals,
);

/// The instrument picker shows a label, never a figure, so the totals on these
/// fixtures are irrelevant to what is under test — [PeriodTotals.empty] keeps
/// them from suggesting otherwise.
const PeriodTotals _emptyTotals = PeriodTotals.empty;

String? _textIn(WidgetTester tester, int fieldIndex) => tester
    .widget<TextField>(find.byType(TextField).at(fieldIndex))
    .controller
    ?.text;

void main() {
  group('case (b) — the parser read most of it', () {
    testWidgets('every successfully-extracted field arrives pre-filled — this '
        'is KHA-146\'s done-check', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(
            item: _partiallyParsedItem(),
            instruments: <InstrumentSummary>[_matchingCard(), _otherCard()],
            onSave: (_) {},
          ),
        ),
      );

      // Amount, currency and merchant are the three TextFields, in order.
      expect(_textIn(tester, 0), '152.75');
      expect(_textIn(tester, 1), 'SAR');
      expect(_textIn(tester, 2), 'SAMPLE MARKET 7');

      // The type the rule declared, already selected rather than left for the
      // user to re-pick from a twelve-item dropdown.
      expect(find.text('Card purchase'), findsOneWidget);

      // The card the message named, resolved to the user's existing one.
      expect(find.text('Card · Blue Visa'), findsOneWidget);

      // And the date the message stated, not merely when it arrived.
      final DropdownButtonFormField<int?> picker = tester
          .widget<DropdownButtonFormField<int?>>(
            find.byType(DropdownButtonFormField<int?>),
          );
      expect(picker.initialValue, 11);
    });

    testWidgets('the form says out loud that the app filled these in — a '
        'silently pre-filled form invites Save without reading', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(item: _partiallyParsedItem(), onSave: (_) {}),
        ),
      );

      expect(
        find.text(
          'We read some of this from the message. Check it before saving — '
          'nothing is recorded until you do.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('pre-filling is NOT auto-saving: no draft exists until the '
        'user presses Save', (WidgetTester tester) async {
      useTallSurface(tester);
      UnparsedCompletionDraft? saved;
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(
            item: _partiallyParsedItem(),
            instruments: <InstrumentSummary>[_matchingCard()],
            onSave: (UnparsedCompletionDraft draft) => saved = draft,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        saved,
        isNull,
        reason:
            'a fully pre-filled form must still be confirmed. Nothing the '
            'parser suggested may reach the ledger on its own.',
      );

      await tester.tap(find.text('Save as transaction'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.rawMessageId, 77);
      expect(
        saved!.amountText,
        '152.75',
        reason: 'the exact decimal the bank printed, unrounded (ADR-002)',
      );
      expect(saved!.currencyCode, 'SAR');
      expect(saved!.merchantRawText, 'SAMPLE MARKET 7');
      expect(saved!.transactionType, 'pos_purchase');
      expect(saved!.direction, 'debit');
      expect(saved!.affectsSpend, isTrue);
      expect(saved!.instrumentId, 11);
      expect(
        saved!.occurredAt,
        DateTime.utc(2026, 7, 30, 6, 14),
        reason:
            'the instant the MESSAGE stated, not when it was delivered. Before '
            'KHA-146 the delivery time was the only thing that survived.',
      );
    });

    testWidgets('the user can still overwrite a pre-filled value', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      UnparsedCompletionDraft? saved;
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(
            item: _partiallyParsedItem(),
            onSave: (UnparsedCompletionDraft draft) => saved = draft,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).first, '999.00');
      await tester.tap(find.text('Save as transaction'));
      await tester.pumpAndSettle();

      expect(saved!.amountText, '999.00');
    });

    testWidgets('the card is matched even though the instrument list arrives '
        'a frame LATE — it comes from a stream, and the first build has '
        'nothing in it', (WidgetTester tester) async {
      useTallSurface(tester);

      // Exactly what happens on a device: `bankTreeProvider` is async, so S-19
      // first builds with an empty picker and the accounts/cards land a moment
      // later. A one-shot match at construction would run against nothing and
      // silently never pre-select — on the very path the issue reports.
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(item: _partiallyParsedItem(), onSave: (_) {}),
        ),
      );
      expect(
        tester
            .widget<DropdownButtonFormField<int?>>(
              find.byType(DropdownButtonFormField<int?>),
            )
            .initialValue,
        isNull,
      );

      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(
            item: _partiallyParsedItem(),
            instruments: <InstrumentSummary>[_matchingCard()],
            onSave: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<DropdownButtonFormField<int?>>(
              find.byType(DropdownButtonFormField<int?>),
            )
            .initialValue,
        11,
      );
    });

    testWidgets('a later emission does not overwrite a choice the user made', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(
            item: _partiallyParsedItem(),
            instruments: <InstrumentSummary>[_matchingCard(), _otherCard()],
            onSave: (_) {},
          ),
        ),
      );

      // The user overrides the pre-selection with "Not stated".
      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not stated').last);
      await tester.pumpAndSettle();

      // A fresh emission of the same list arrives (Riverpod rebuilds often).
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(
            item: _partiallyParsedItem(),
            instruments: <InstrumentSummary>[_matchingCard(), _otherCard()],
            onSave: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<DropdownButtonFormField<int?>>(
              find.byType(DropdownButtonFormField<int?>),
            )
            .initialValue,
        isNull,
        reason:
            'a suggestion the person has already answered must not be made '
            'again behind their back',
      );
    });

    testWidgets('a card the user does not have yet is reported, not silently '
        'dropped', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(
            item: _partiallyParsedItem(),
            instruments: <InstrumentSummary>[_otherCard()],
            onSave: (_) {},
          ),
        ),
      );

      expect(
        find.textContaining('•••• 4821'),
        findsOneWidget,
        reason:
            'the form cannot create an instrument (see its class doc), so the '
            'honest thing is to show what the message said and let the person '
            'map it — never to pre-select a different card',
      );
      final DropdownButtonFormField<int?> picker = tester
          .widget<DropdownButtonFormField<int?>>(
            find.byType(DropdownButtonFormField<int?>),
          );
      expect(picker.initialValue, isNull);
    });

    testWidgets('two cards ending in the same four digits select neither — '
        'ambiguity falls back to Not stated', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(
            item: _partiallyParsedItem(),
            instruments: <InstrumentSummary>[
              _matchingCard(),
              InstrumentSummary(
                instrument: const LedgerInstrument(
                  id: 13,
                  bankId: 2,
                  kind: InstrumentKind.card,
                  maskedIdentifier: '****4821',
                  friendlyName: 'Another Bank Card',
                ),
                totals: _emptyTotals,
              ),
            ],
            onSave: (_) {},
          ),
        ),
      );

      final DropdownButtonFormField<int?> picker = tester
          .widget<DropdownButtonFormField<int?>>(
            find.byType(DropdownButtonFormField<int?>),
          );
      expect(
        picker.initialValue,
        isNull,
        reason:
            'four digits are not globally unique (instrument_identity.dart). '
            'Guessing between two candidates would attach a transaction to the '
            'wrong card, quietly, on a screen the user is skimming.',
      );
    });

    testWidgets('a transaction type this build does not know reads as not '
        'stated instead of crashing the dropdown', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(
            item: _partiallyParsedItem(
              partial: const PartialExtraction(
                amountText: '10.00',
                currencyCode: 'SAR',
                // A type an imported pack could declare that this build
                // predates (rule-pack §5.2 forward compatibility).
                transactionType: 'crypto_settlement',
              ),
            ),
            onSave: (_) {},
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final DropdownButtonFormField<String> picker = tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          );
      expect(picker.initialValue, isNull);
      expect(_textIn(tester, 0), '10.00');
    });

    testWidgets('renders in Arabic RTL', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(item: _partiallyParsedItem(), onSave: (_) {}),
          locale: 'ar',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('إكمال التفاصيل'), findsOneWidget);
      expect(_textIn(tester, 0), '152.75');
    });
  });

  group('case (a) — no rule recognised the message (no regression)', () {
    testWidgets('the form is correctly blank and says nothing about a '
        'pre-fill', (WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(
            item: _unrecognisedItem(),
            instruments: <InstrumentSummary>[_matchingCard()],
            onSave: (_) {},
          ),
        ),
      );

      expect(_textIn(tester, 0), '');
      expect(_textIn(tester, 2), '');
      expect(
        _textIn(tester, 1),
        'SAR',
        reason:
            'the base currency is a default, and was one before this change '
            'too — not a value read from a message nobody parsed',
      );
      expect(
        find.textContaining('We read some of this'),
        findsNothing,
        reason:
            'announcing a pre-fill over a blank form teaches the user to '
            'ignore the notice for the times it is right',
      );

      final DropdownButtonFormField<String> type = tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          );
      expect(type.initialValue, isNull);
      final DropdownButtonFormField<int?> instrument = tester
          .widget<DropdownButtonFormField<int?>>(
            find.byType(DropdownButtonFormField<int?>),
          );
      expect(instrument.initialValue, isNull);
    });

    testWidgets('AC-B4.2 still blocks a save that names no amount', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      UnparsedCompletionDraft? saved;
      await tester.pumpWidget(
        wrap(
          CompleteUnparsedScreen(
            item: _unrecognisedItem(),
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
    });
  });
}

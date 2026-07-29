/// **NFR-U4 in greyscale** — KHA-36's done-check:
///
/// > *"Greyscale screenshot test proves credit/debit and needs-review remain
/// > distinguishable."*
///
/// ---
///
/// ## What this test does, and why it is not a golden image
///
/// The obvious reading of "greyscale screenshot test" is a golden file
/// compared pixel by pixel. That would be the *weaker* test, for three
/// reasons worth writing down:
///
///  1. **A golden proves two renders are identical, not that two rows are
///     distinguishable.** It would pass just as happily if a credit and a debit
///     rendered identically, as long as they went on doing so.
///  2. Goldens are font-dependent, and this app bundles Tajawal and Manrope as
///     assets that `flutter test` does not load — every glyph would be a
///     box, and the file would be re-blessed rather than read.
///  3. A failure reads as "23 pixels differ", which tells the next person
///     nothing about which requirement broke.
///
/// So this asserts the **property** the requirement is actually about:
/// *strip every colour out of the tree, and a credit row still differs from a
/// debit row, and a flagged row still differs from an unflagged one, in text
/// and in iconography.*
///
/// The stripping is real, not notional: [greyscaleTheme] collapses the entire
/// palette to one grey and paints the subtree through a saturation-zero
/// `ColorFilter`, so any signal that survives is provably not carried by
/// colour. [signalsOf] then reads back what a colour-blind user — or anyone
/// glancing at a phone in bright sun — actually has left: the strings and the
/// icons.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/transaction_types.dart';
import 'package:massrofy/presentation/widgets/transaction_list_item.dart';

import 'p3_screens_test.dart' show wrap;

/// A matrix that maps every colour to its luminance — the standard greyscale
/// conversion. Applied over the subtree, so nothing rendered inside it can
/// convey meaning through hue.
const ColorFilter kGreyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// Everything a user can still perceive with colour removed: the text on the
/// row, and the icons on it.
///
/// Deliberately does **not** include any `Color`. If two rows produce
/// different sets here, they are distinguishable without colour — that is the
/// whole claim.
Set<String> signalsOf(WidgetTester tester, Finder scope) {
  final Set<String> signals = <String>{};
  for (final Text text in tester.widgetList<Text>(
    find.descendant(of: scope, matching: find.byType(Text)),
  )) {
    final String? value = text.data;
    if (value != null && value.trim().isNotEmpty) {
      signals.add('text:$value');
    }
  }
  for (final Icon icon in tester.widgetList<Icon>(
    find.descendant(of: scope, matching: find.byType(Icon)),
  )) {
    signals.add('icon:${icon.icon?.codePoint}');
  }
  return signals;
}

LedgerTransaction txn({
  required int id,
  String amount = '45.00',
  String direction = 'debit',
  String type = TransactionType.posPurchase,
  bool needsReview = false,
}) => LedgerTransaction(
  id: id,
  amount: Money.parse(amount, currency: 'SAR'),
  direction: direction,
  transactionType: type,
  affectsSpend: true,
  occurredAt: DateTime.utc(2026, 7, 15, 11, 20),
  merchantRawText: 'QANDA FOODS',
  needsReview: needsReview,
);

/// Renders [rows] with the whole palette flattened to one grey **and** the
/// result painted through [kGreyscale].
///
/// Belt and braces on purpose: the theme override removes colour from anything
/// that asks the theme for it, and the filter removes colour from anything that
/// hard-codes a value (which `AppColors` constants do).
Widget colourless(List<Widget> rows) => Theme(
  data: ThemeData(
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF808080),
      secondary: Color(0xFF808080),
      surface: Color(0xFF808080),
      error: Color(0xFF808080),
    ),
  ),
  child: ColorFiltered(
    colorFilter: kGreyscale,
    child: Material(child: Column(children: rows)),
  ),
);

void main() {
  testWidgets('**AC-B7.3 / NFR-U4** — with every colour removed, a credit row '
      'and a debit row still carry different signals', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: colourless(<Widget>[
            Container(
              key: const Key('grey.debit'),
              child: TransactionListItem(transaction: txn(id: 1)),
            ),
            Container(
              key: const Key('grey.credit'),
              child: TransactionListItem(
                transaction: txn(
                  id: 2,
                  amount: '45.00',
                  direction: 'credit',
                  type: TransactionType.refund,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
    await tester.pump();

    final Set<String> debit = signalsOf(
      tester,
      find.byKey(const Key('grey.debit')),
    );
    final Set<String> credit = signalsOf(
      tester,
      find.byKey(const Key('grey.credit')),
    );

    // The amounts are the same magnitude on purpose: if the rows were only
    // distinguishable because one said 45.00 and the other 9000.00, the test
    // would be proving nothing about the *direction*.
    expect(debit, isNot(equals(credit)));
    expect(debit, contains('text:−45.00 SAR'));
    expect(credit, contains('text:+45.00 SAR'));
    // The `−`/`+` prefixes are U+2212 and U+002B — glyphs, not hues.
    expect(
      debit.difference(credit),
      isNotEmpty,
      reason:
          'a debit must carry at least one signal a credit does not, with '
          'colour removed',
    );
  });

  testWidgets('**AC-C4.1 / NFR-U4** — with every colour removed, a flagged row '
      'still announces that it needs review, in words and an icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: colourless(<Widget>[
            Container(
              key: const Key('grey.clean'),
              child: TransactionListItem(transaction: txn(id: 1)),
            ),
            Container(
              key: const Key('grey.flagged'),
              child: TransactionListItem(
                transaction: txn(id: 2, needsReview: true),
              ),
            ),
          ]),
        ),
      ),
    );
    await tester.pump();

    final Set<String> clean = signalsOf(
      tester,
      find.byKey(const Key('grey.clean')),
    );
    final Set<String> flagged = signalsOf(
      tester,
      find.byKey(const Key('grey.flagged')),
    );

    final Set<String> extra = flagged.difference(clean);
    // Both halves. The words alone would fail a user skimming; the icon alone
    // would fail a screen reader and anyone who has not learned what a flag
    // means in this app.
    expect(
      extra.any((String s) => s.startsWith('text:')),
      isTrue,
      reason: 'the flagged row must carry WORDS the unflagged one does not',
    );
    expect(
      extra.contains('icon:${Icons.flag_outlined.codePoint}'),
      isTrue,
      reason: 'and an icon, per design.md §3.3',
    );
  });

  testWidgets('**AC-B4.3 / NFR-U4** — a manual entry stays distinguishable '
      'from an SMS-derived one in greyscale', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: colourless(<Widget>[
            Container(
              key: const Key('grey.sms'),
              child: TransactionListItem(transaction: txn(id: 1)),
            ),
            Container(
              key: const Key('grey.manual'),
              child: TransactionListItem(
                transaction: LedgerTransaction(
                  id: 2,
                  amount: Money.parse('45.00', currency: 'SAR'),
                  direction: 'debit',
                  transactionType: TransactionType.posPurchase,
                  affectsSpend: true,
                  occurredAt: DateTime.utc(2026, 7, 15, 11, 20),
                  merchantRawText: 'QANDA FOODS',
                  provenance: TransactionProvenance.manual,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
    await tester.pump();

    final Set<String> extra = signalsOf(
      tester,
      find.byKey(const Key('grey.manual')),
    ).difference(signalsOf(tester, find.byKey(const Key('grey.sms'))));

    expect(extra, contains('text:Manual'));
    expect(extra, contains('icon:${Icons.edit_outlined.codePoint}'));
  });

  testWidgets('the greyscale harness itself is honest — two rows that DO '
      'differ only by colour are indistinguishable to it', (
    WidgetTester tester,
  ) async {
    // A negative control. Without this, every assertion above could be passing
    // because `signalsOf` reads something it should not, and nobody would know.
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: colourless(<Widget>[
            Container(
              key: const Key('grey.red'),
              child: const Text(
                '45.00 SAR',
                style: TextStyle(color: Colors.red),
              ),
            ),
            Container(
              key: const Key('grey.green'),
              child: const Text(
                '45.00 SAR',
                style: TextStyle(color: Colors.green),
              ),
            ),
          ]),
        ),
      ),
    );
    await tester.pump();

    expect(
      signalsOf(tester, find.byKey(const Key('grey.red'))),
      equals(signalsOf(tester, find.byKey(const Key('grey.green')))),
      reason:
          'if this ever passes with a difference, the harness is reading a '
          'colour and the three assertions above prove nothing',
    );
  });
}

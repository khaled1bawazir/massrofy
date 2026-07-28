/// Widget tests for every screen P2 adds:
///
/// | Screen | Mockup | Acceptance criteria |
/// |---|---|---|
/// | S-02 SMS permission rationale | `onboarding.html` | AC-A1.2, design flag D-9 |
/// | S-04 Limited mode / denied | `onboarding.html` | AC-A1.2, AC-A1.3 |
/// | S-05 Historical import progress | `onboarding.html` | AC-A3.2 |
/// | S-18 Needs Review inbox | `needs-review.html` | US-A4, AC-A4.1/A4.2/A4.4 |
///
/// Every screen is exercised in **both locales**, because Arabic RTL is the
/// app's primary, first-designed direction (design.md §3.1) and English is
/// the secondary one — the reverse of the usual assumption. A screen that
/// only renders correctly in English is, for this product, a broken screen.
///
/// Several tests also render at a **2.0 text scale factor**. NFR-U3 requires
/// no truncation at the largest OS font size, and a `Column` containing a
/// `Spacer` is the single most common thing to overflow when someone turns
/// their font up — a real accessibility need, not an edge case.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/features/ingestion/duplicate_policy.dart';
import 'package:massrofy/features/ingestion/review_queue.dart';
import 'package:massrofy/features/ingestion/sms_permission_service.dart';
import 'package:massrofy/features/parsing/parse_outcome.dart';
import 'package:massrofy/presentation/l10n/generated/app_localizations.dart';
import 'package:massrofy/presentation/screens/import_progress_screen.dart';
import 'package:massrofy/presentation/screens/needs_review_screen.dart';
import 'package:massrofy/presentation/screens/sms_limited_mode_screen.dart';
import 'package:massrofy/presentation/screens/sms_permission_rationale_screen.dart';

/// Wraps a screen with the localisation delegates and a chosen locale.
///
/// `textScale` drives `MediaQuery.textScaler`, which is how Flutter models
/// the OS font-size setting. Passing 2.0 is the closest a widget test gets to
/// "the user turned their font all the way up".
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

void main() {
  group('S-02 — SMS permission rationale (AC-A1.2, design flag D-9)', () {
    testWidgets('shows all four guarantees before any OS dialog', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SmsPermissionRationaleScreen(
            onGrantPressed: () {},
            onNotNowPressed: () {},
          ),
        ),
      );

      // Each bullet is a promise the architecture actually keeps — see the
      // table in the screen's doc comment. Asserting all four here means a
      // future edit cannot quietly drop one and leave the user with less
      // information than the approved mockup gives them.
      expect(find.text('Why Massrofy needs SMS access'), findsOneWidget);
      expect(
        find.text('Everything is processed on your phone'),
        findsOneWidget,
      );
      expect(
        find.text('No data is sent to us or to anyone else'),
        findsOneWidget,
      );
      expect(find.text('You can revoke access at any time'), findsOneWidget);
      expect(
        find.text('Non-financial messages are ignored and never stored'),
        findsOneWidget,
      );
    });

    testWidgets('offers both a grant path and a decline path', (
      WidgetTester tester,
    ) async {
      bool granted = false;
      bool declined = false;

      await tester.pumpWidget(
        wrap(
          SmsPermissionRationaleScreen(
            onGrantPressed: () => granted = true,
            onNotNowPressed: () => declined = true,
          ),
        ),
      );

      await tester.tap(find.text('Grant SMS access'));
      await tester.tap(find.text('Not now'));
      await tester.pump();

      expect(granted, isTrue);
      // "Not now" must exist and do something. A rationale screen with only
      // one exit is a coercion pattern, and — more practically — a user who
      // feels trapped denies at the OS dialog instead, which is the one
      // outcome that is hard to recover from.
      expect(declined, isTrue);
    });

    testWidgets('renders in Arabic RTL', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          SmsPermissionRationaleScreen(
            onGrantPressed: () {},
            onNotNowPressed: () {},
          ),
          locale: 'ar',
        ),
      );

      expect(find.text('لماذا يحتاج مصروفي إلى إذن الرسائل'), findsOneWidget);
      expect(find.text('منح إذن الرسائل'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('منح إذن الرسائل'))),
        TextDirection.rtl,
      );
    });

    testWidgets('does not overflow at 2.0 text scale (NFR-U3)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SmsPermissionRationaleScreen(
            onGrantPressed: () {},
            onNotNowPressed: () {},
          ),
          locale: 'ar',
          textScale: 2.0,
        ),
      );
      // `pumpWidget` fails the test on a RenderFlex overflow, so reaching
      // this line is the assertion. The screen scrolls rather than clipping
      // precisely so this passes.
      expect(tester.takeException(), isNull);
    });
  });

  group('S-04 — limited mode (AC-A1.2, AC-A1.3)', () {
    testWidgets(
      'always states that existing data is intact — the half of AC-A1.3 that '
      'stops a user reinstalling and destroying it',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          wrap(
            SmsLimitedModeScreen(
              status: SmsPermissionStatus.denied,
              onRequestPermission: () {},
              onOpenSettings: () {},
              onAddManually: () {},
            ),
          ),
        );

        expect(find.text('Limited mode is on'), findsOneWidget);
        expect(
          find.textContaining('Any data you already have is still intact'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'denied → the primary action retries the OS dialog (which will appear)',
      (WidgetTester tester) async {
        bool requested = false;
        await tester.pumpWidget(
          wrap(
            SmsLimitedModeScreen(
              status: SmsPermissionStatus.denied,
              onRequestPermission: () => requested = true,
              onOpenSettings: () => fail('must not deep-link when it can ask'),
              onAddManually: () {},
            ),
          ),
        );

        await tester.tap(find.text('Grant SMS access'));
        expect(requested, isTrue);
        expect(find.text('Open system settings'), findsNothing);
      },
    );

    testWidgets(
      'permanentlyDenied → the primary action deep-links to Settings, '
      'because a re-request would silently do nothing',
      (WidgetTester tester) async {
        bool openedSettings = false;
        await tester.pumpWidget(
          wrap(
            SmsLimitedModeScreen(
              status: SmsPermissionStatus.permanentlyDenied,
              onRequestPermission: () =>
                  fail('Android would no-op this; offering it is a dead end'),
              onOpenSettings: () => openedSettings = true,
              onAddManually: () {},
            ),
          ),
        );

        await tester.tap(find.text('Open system settings'));
        expect(openedSettings, isTrue);
      },
    );

    testWidgets('always offers manual entry — the app is never a dead end', (
      WidgetTester tester,
    ) async {
      for (final SmsPermissionStatus status in <SmsPermissionStatus>[
        SmsPermissionStatus.denied,
        SmsPermissionStatus.permanentlyDenied,
      ]) {
        bool addedManually = false;
        await tester.pumpWidget(
          wrap(
            SmsLimitedModeScreen(
              status: status,
              onRequestPermission: () {},
              onOpenSettings: () {},
              onAddManually: () => addedManually = true,
            ),
          ),
        );
        await tester.tap(find.text('Add a transaction manually'));
        expect(addedManually, isTrue, reason: 'for status $status');
      }
    });

    testWidgets('the revoked banner carries BOTH halves of AC-A1.3', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(Scaffold(body: SmsAccessRevokedBanner(onFix: () {}))),
      );

      // The warning…
      expect(find.text('SMS access was turned off'), findsOneWidget);
      // …and the reassurance. Shipping only the first half is the bug this
      // test exists to prevent.
      expect(find.textContaining('still intact'), findsOneWidget);
    });

    testWidgets('renders in Arabic RTL', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          SmsLimitedModeScreen(
            status: SmsPermissionStatus.permanentlyDenied,
            onRequestPermission: () {},
            onOpenSettings: () {},
            onAddManually: () {},
          ),
          locale: 'ar',
        ),
      );

      expect(find.text('الوضع المحدود مفعّل'), findsOneWidget);
      expect(find.text('فتح إعدادات النظام'), findsOneWidget);
    });
  });

  group('S-05 — import progress (AC-A3.2)', () {
    testWidgets('shows a determinate bar and the live transaction count', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ImportProgressScreen(
            processed: 32,
            total: 50,
            transactionsFound: 41,
            onContinueInBackground: () {},
          ),
        ),
      );

      final LinearProgressIndicator bar = tester.widget(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.64, 0.001));
      expect(find.text('41 transactions found so far…'), findsOneWidget);
    });

    testWidgets(
      'sweeps (indeterminate) while the total is still unknown, rather than '
      'showing a fabricated percentage',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          wrap(
            ImportProgressScreen(
              processed: 0,
              total: null,
              transactionsFound: 0,
              onContinueInBackground: () {},
            ),
          ),
        );

        final LinearProgressIndicator bar = tester.widget(
          find.byType(LinearProgressIndicator),
        );
        expect(bar.value, isNull);
      },
    );

    testWidgets('a zero total does not produce a NaN bar', (
      WidgetTester tester,
    ) async {
      // `0 / 0` is NaN, which renders in an undefined state rather than
      // throwing — so it would slip past review unnoticed.
      await tester.pumpWidget(
        wrap(
          ImportProgressScreen(
            processed: 0,
            total: 0,
            transactionsFound: 0,
            onContinueInBackground: () {},
          ),
        ),
      );
      final LinearProgressIndicator bar = tester.widget(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, isNull);
    });

    testWidgets('the user can leave — the import is non-blocking (NFR-R2)', (
      WidgetTester tester,
    ) async {
      bool dismissed = false;
      await tester.pumpWidget(
        wrap(
          ImportProgressScreen(
            processed: 5,
            total: 10,
            transactionsFound: 2,
            onContinueInBackground: () => dismissed = true,
          ),
        ),
      );

      await tester.tap(find.text('Continue in the background'));
      expect(dismissed, isTrue);
    });

    testWidgets(
      'states the import scope, so a small result is not mistaken for a bug '
      '(AC-A3.1 / OQ-11)',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          wrap(
            ImportProgressScreen(
              processed: 1,
              total: 1,
              transactionsFound: 1,
              onContinueInBackground: () {},
            ),
          ),
        );
        expect(
          find.textContaining('from the start of this month'),
          findsOneWidget,
        );
      },
    );

    testWidgets('renders in Arabic RTL', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          ImportProgressScreen(
            processed: 32,
            total: 50,
            transactionsFound: 41,
            onContinueInBackground: () {},
          ),
          locale: 'ar',
        ),
      );

      expect(find.text('جارٍ استيراد رسائلك'), findsOneWidget);
      expect(find.text('المتابعة في الخلفية'), findsOneWidget);
    });
  });

  group('S-18 — Needs Review inbox (US-A4, AC-A4.1/A4.2/A4.4)', () {
    final ReviewQueueItem unparsedItem = ReviewQueueItem(
      rawMessageId: 1,
      // Synthetic, like every message in this repository (NFR-M3).
      sanitizedBody:
          'تنبيه: تم رصد عملية غير معتادة على حسابك. يرجى زيارة الفرع.',
      sender: 'BAJ',
      receivedAt: DateTime.utc(2026, 7, 28, 9, 12),
      bankId: 'bank-aljazira',
      unparsedReason: UnparsedReason.noRuleMatched,
    );

    const FlaggedTransactionItem flaggedItem = FlaggedTransactionItem(
      transactionId: 9,
      amount: '212.00',
      currencyCode: 'SAR',
      merchantRawText: 'JARIR BOOKSTORE',
      reviewReason: ReviewReason.possibleDuplicate,
      possibleDuplicateOfId: 8,
    );

    Widget screen({
      List<ReviewQueueItem>? unparsed,
      List<FlaggedTransactionItem>? flagged,
      void Function(ReviewQueueItem)? onFill,
      void Function(ReviewQueueItem)? onDismiss,
      String locale = 'en',
    }) => wrap(
      NeedsReviewScreen(
        unparsed: unparsed ?? <ReviewQueueItem>[unparsedItem],
        flagged: flagged ?? const <FlaggedTransactionItem>[],
        onFillInDetails: onFill ?? (ReviewQueueItem _) {},
        onNotATransaction: onDismiss ?? (ReviewQueueItem _) {},
        onOpenFlagged: (FlaggedTransactionItem _) {},
      ),
      locale: locale,
    );

    testWidgets(
      'AC-A4.1 — shows the original (sanitised) message text, so the user can '
      'see exactly what the parser saw',
      (WidgetTester tester) async {
        await tester.pumpWidget(screen());
        expect(find.text(unparsedItem.sanitizedBody), findsOneWidget);
        expect(find.textContaining('BAJ'), findsOneWidget);
      },
    );

    testWidgets('explains WHY it could not be understood', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(screen());
      // "did not match any known format" (the bank changed a template, risk
      // R-4) reads very differently to a user than "some details were
      // missing", and only one of them is worth reporting to a maintainer.
      expect(
        find.text('This message did not match any known format'),
        findsOneWidget,
      );
    });

    testWidgets('offers both AC-A4.2 actions and wires them up', (
      WidgetTester tester,
    ) async {
      ReviewQueueItem? filled;
      ReviewQueueItem? dismissed;

      await tester.pumpWidget(
        screen(
          onFill: (ReviewQueueItem i) => filled = i,
          onDismiss: (ReviewQueueItem i) => dismissed = i,
        ),
      );

      await tester.tap(find.text('Fill in details'));
      await tester.tap(find.text('Not a transaction'));
      await tester.pump();

      expect(filled?.rawMessageId, 1);
      expect(dismissed?.rawMessageId, 1);
    });

    testWidgets('the two tabs are counted separately and never conflated', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        screen(
          unparsed: <ReviewQueueItem>[unparsedItem],
          flagged: const <FlaggedTransactionItem>[flaggedItem],
        ),
      );

      expect(find.text('Not understood (1)'), findsOneWidget);
      expect(find.text('Low confidence (1)'), findsOneWidget);
    });

    testWidgets(
      'a flagged transaction shows the possible-duplicate marker as an icon '
      'AND a word, never colour alone (NFR-U4)',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          screen(
            unparsed: const <ReviewQueueItem>[],
            flagged: const <FlaggedTransactionItem>[flaggedItem],
          ),
        );

        // Switch to the second tab.
        await tester.tap(find.text('Low confidence (1)'));
        await tester.pumpAndSettle();

        expect(find.text('JARIR BOOKSTORE'), findsOneWidget);
        expect(find.text('Possible duplicate'), findsOneWidget);
        expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
        // The amount is rendered from the exact decimal string (ADR-002),
        // never re-parsed through a float on the way to the screen.
        expect(find.text('212.00 SAR'), findsOneWidget);
      },
    );

    testWidgets('the empty state is reassuring, not a warning', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        screen(
          unparsed: const <ReviewQueueItem>[],
          flagged: const <FlaggedTransactionItem>[],
        ),
      );

      expect(find.text('Nothing needs review right now'), findsWidgets);
      expect(find.byIcon(Icons.task_alt), findsWidgets);
    });

    testWidgets('renders in Arabic RTL', (WidgetTester tester) async {
      await tester.pumpWidget(screen(locale: 'ar'));

      expect(find.text('بحاجة إلى مراجعة'), findsOneWidget);
      expect(find.text('غير مفهومة (1)'), findsOneWidget);
      expect(find.text('أكمل التفاصيل'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('أكمل التفاصيل'))),
        TextDirection.rtl,
      );
    });
  });
}

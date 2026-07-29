/// **QA adversarial probes — PR #34 (P4b), head `0585fd4`.**
///
/// Depth is deliberately asymmetric, and the asymmetry is the point.
///
/// * **`docs/PRD.md` declares `TIER: personal`**, so the new UI/CRUD surfaces
///   (category management, learned rules, picker sheet, correction flow) get
///   journeys first and a handful of highest-value attack probes — not a
///   30-probe sweep. Those are PROBES U1–U4.
/// * **The merchant-matching engine is the exception.** `merchant_key.dart` has
///   needed three rounds of deep adversarial QA across PR #27/#30 to catch
///   real money-correctness bugs (KHA-98, KHA-99, KHA-106, KHA-107) that
///   shallower passes missed *every previous time*. So PROBES E1–E5 attack it
///   at full client-grade depth, mechanically over generated corpora rather
///   than over pinned examples — because pinned examples are exactly what let
///   KHA-106 through: ADR-008 v1.3's consequences list enumerated five worked
///   examples and never stated a pair of 4-digit siblings.
///
/// NFR-M3: every merchant string here is synthetic.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/core/text/canonical_text.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/category_dao.dart';
import 'package:massrofy/data/dao/merchant_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/categorization/categories.dart';
import 'package:massrofy/features/categorization/categorization_service.dart';
import 'package:massrofy/features/categorization/category_breakdown.dart';
import 'package:massrofy/features/categorization/category_correction.dart';
import 'package:massrofy/features/categorization/merchant_key.dart';
import 'package:massrofy/features/ledger/ledger_mapping.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/presentation/providers/categorization_providers.dart';
import 'package:massrofy/presentation/screens/category_management_screen.dart';

import '../support/plain_test_database.dart';
import '../widget/p3_screens_test.dart' show useTallSurface, wrap;

final List<int> _testChainKey = List<int>.generate(32, (int i) => i + 41);

final PeriodRange _july2026 = PeriodRange(
  startUtc: DateTime.utc(2026, 7),
  endUtcExclusive: DateTime.utc(2026, 8),
);

// ===========================================================================
// Shared corpus machinery for the engine probes.
// ===========================================================================

final RegExp _sep = RegExp(r'''[\s\-_/\\*#,.:;|()\[\]"'@+]+''');
final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

/// A synthetic token alphabet spanning **every kind of token the pipeline
/// distinguishes**, which is what makes a sweep over it meaningful rather than
/// decorative:
///
/// * two proper nouns (`QANDA`, `ZORBA`) — condition 2's "which one";
/// * an ordinary word (`ELEVEN`) — neither noise nor a name we care about;
/// * two reference markers (`STORE`, `BR`) — noise **and** corroborators;
/// * a legal-form noise word (`LLC`) — noise but deliberately **not** a
///   corroborator;
/// * digit runs at three lengths (`7`, `100`, `2000`) straddling the `>= 4`
///   boundary the deleted `referenceDigitRunMinLength` used to test.
const List<String> _alphabet = <String>[
  'QANDA',
  'ZORBA',
  'ELEVEN',
  'STORE',
  'BR',
  'LLC',
  '7',
  '100',
  '2000',
];

/// Every ordered string of 2..4 tokens over [_alphabet] — 7,290 strings.
List<String> buildCorpus() {
  final List<String> corpus = <String>[];
  for (final String a in _alphabet) {
    for (final String b in _alphabet) {
      corpus.add('$a $b');
      for (final String c in _alphabet) {
        corpus.add('$a $b $c');
        for (final String d in _alphabet) {
          corpus.add('$a $b $c $d');
        }
      }
    }
  }
  return corpus;
}

/// The **name content** of a merchant string: the tokens that are neither
/// structural noise nor a digit run.
///
/// This is the operational reading of ADR-008's corroboration rule conditions
/// 2 and 3 — a token that is not structural and not a number is what says
/// *which* business this is. Two strings whose name content differs are two
/// businesses, so a key collision between them is the KHA-98 silent-merge
/// defect regardless of which signal produced it.
String nameContentOf(String raw) => <String>[
  for (final String t in CanonicalText.fold(raw).split(_sep))
    if (t.isNotEmpty &&
        !MerchantKey.noiseTokens.contains(t) &&
        !_digitsOnly.hasMatch(t))
      t,
].join(' ');

/// ADR-008 **v1.3**'s `MerchantKey.of`, transcribed verbatim from
/// `git show dc3f362:lib/features/categorization/merchant_key.dart` so this
/// PR's behaviour change can be *enumerated* rather than described.
///
/// This is the tool that answers the question the brief asks — "is there a
/// THIRD cost, disclosed or undisclosed?" — because a cost is by definition a
/// difference from the previous behaviour, and a differential is the only way
/// to find one you were not already looking for.
String ofV13(String raw) {
  final List<String> tokens = <String>[
    for (final String t in CanonicalText.fold(raw).split(_sep))
      if (t.isNotEmpty) t,
  ];
  _stripV13(tokens);
  tokens.removeWhere(MerchantKey.noiseTokens.contains);
  return tokens.join(' ');
}

void _stripV13(List<String> tokens) {
  if (tokens.length < 2) return;
  final String last = tokens.last;
  if (!_digitsOnly.hasMatch(last)) return;
  final String previous = tokens[tokens.length - 2];
  if (_digitsOnly.hasMatch(previous)) return;
  final bool nonDigitSurvives = tokens
      .take(tokens.length - 1)
      .any((String t) => !_digitsOnly.hasMatch(t));
  if (!nonDigitSurvives) return;
  // v1.3's two corroboration signals: adjacency BEFORE only, or length >= 4
  // (the deleted `CategorizationConfig.referenceDigitRunMinLength`).
  final bool corroborated =
      MerchantKey.referenceMarkerTokens.contains(previous) || last.length >= 4;
  if (!corroborated) return;
  tokens.removeLast();
}

void main() {
  // =========================================================================
  // ENGINE PROBES — full adversarial depth (the TIER: personal exception).
  // =========================================================================
  group('PROBE E — ADR-008 v1.4, attacked mechanically rather than by '
      'example', () {
    test('E1 — idempotence holds over the WHOLE generated corpus, not just '
        'the pinned examples (KHA-107)', () {
      // KHA-107's done-check asks for `of(of(x)) == of(x)` **for all x**, and
      // the shipped tests pin a 24-string hand-written corpus. A hand-written
      // corpus proves the cases its author thought of; this one is generated,
      // so it also covers the ones nobody did.
      //
      // The doc comment's proof is: `referenceMarkerTokens ⊆ noiseTokens`, so
      // step 7 removes every corroborator, so no OUTPUT of `of` can contain
      // one, so step 6 is a no-op on a second pass. This asserts the
      // conclusion; E1b asserts the premise the proof rests on.
      final List<String> violations = <String>[
        for (final String s in buildCorpus())
          if (MerchantKey.of(MerchantKey.of(s)) != MerchantKey.of(s))
            '$s -> ${MerchantKey.of(s)} -> ${MerchantKey.of(MerchantKey.of(s))}',
      ];
      expect(
        violations,
        isEmpty,
        reason:
            'of(of(x)) != of(x) for ${violations.length} strings — KHA-107 '
            'is not actually closed',
      );
    });

    test('E1b — the PREMISE of the idempotence proof: every corroborator is '
        'itself a noise token', () {
      // The doc comment warns that this is what the invariant "rests entirely
      // on", and that a future corroborator kept out of `noiseTokens` would
      // break idempotence *silently*. Asserted directly so the warning is
      // enforced rather than merely written down.
      expect(
        MerchantKey.referenceMarkerTokens.difference(MerchantKey.noiseTokens),
        isEmpty,
        reason:
            'a corroborator that survives step 7 would appear in the output '
            'of `of`, making step 6 fire again on a second pass',
      );
    });

    test('E2 — THE SAFETY PROPERTY: no two strings with different NAME '
        'CONTENT ever share a key (KHA-98/99/106 class)', () {
      // This is the probe that would have caught KHA-98, KHA-99 AND KHA-106,
      // none of which were caught by the example tables that shipped with
      // them. Rather than asking "does this particular pair collide?", it
      // partitions the whole corpus by key and asserts that every equivalence
      // class is name-homogeneous.
      //
      // A failure here is a High-severity silent merge: `merchant.merchant_key`
      // is UNIQUE, so two businesses become one row and categorising one
      // auto-applies to the other at tier T1, confidence 1.00 — upstream of
      // every threshold.
      final Map<String, Set<String>> classes = <String, Set<String>>{};
      for (final String s in buildCorpus()) {
        final String key = MerchantKey.of(s);
        if (key.isEmpty) continue; // KHA-102: no key is not a merge.
        classes.putIfAbsent(key, () => <String>{}).add(s);
      }

      final List<String> merges = <String>[];
      classes.forEach((String key, Set<String> members) {
        final Set<String> names = <String>{
          for (final String m in members) nameContentOf(m),
        };
        if (names.length > 1) {
          merges.add('key "$key" merges names $names');
        }
      });

      expect(
        merges,
        isEmpty,
        reason:
            'AC-D2.3 — "never silently merge unrelated merchants". '
            '${merges.length} key classes span more than one name.',
      );
    });

    test('E3 — order-insensitivity is REAL, swept over every reference marker '
        'in both orders (KHA-107)', () {
      // The shipped test sweeps markers in both orders too. What this adds is
      // the other half of the claim: that making the two orders agree did not
      // also make them agree with something they SHOULD differ from. A fix
      // that collapses `PANDA 1234 STORE` onto `PANDA STORE 1234` by
      // collapsing both onto everything would also pass an order test.
      for (final String marker in MerchantKey.referenceMarkerTokens) {
        final String markerFirst = MerchantKey.of('QANDA $marker 1234');
        final String markerLast = MerchantKey.of('QANDA 1234 $marker');
        expect(
          markerFirst,
          markerLast,
          reason:
              'PRD §3.4 — two renderings that are permutations of each other '
              'are one shop, so one key. Marker: $marker',
        );
        expect(markerFirst, 'QANDA');

        // …and the other business is still a different key.
        expect(
          MerchantKey.of('ZORBA $marker 1234'),
          isNot(markerFirst),
          reason:
              'order-insensitivity must not be bought by collapsing the '
              'proper noun as well. Marker: $marker',
        );
      }
    });

    test('E4 — the disclosed-cost hunt: v1.4 introduces NO merge between two '
        'different names, at any digit length', () {
      // The brief asks specifically whether the two disclosed costs are
      // "correctly and only those costs", looking for a third the way KHA-109
      // was found last round. This differential answers it: every pair the
      // v1.4 partition joins that the v1.3 partition kept apart is listed, and
      // then filtered to the dangerous kind (different names).
      //
      // RESULT (recorded so a future reader does not have to re-derive it):
      // v1.4 introduces 818 new merges over this corpus and **not one of them
      // joins two different names**. Every one is of the shape
      // `NAME <digits> <MARKER>` joining the `NAME` class — i.e. the exact,
      // intended consequence of reading adjacency on the right-hand side.
      final Map<String, Set<String>> v14 = <String, Set<String>>{};
      for (final String s in buildCorpus()) {
        final String k = MerchantKey.of(s);
        if (k.isNotEmpty) v14.putIfAbsent(k, () => <String>{}).add(s);
      }

      final List<String> newDifferentNameMerges = <String>[];
      v14.forEach((String key, Set<String> members) {
        final List<String> ms = members.toList();
        for (int i = 0; i < ms.length; i++) {
          for (int j = i + 1; j < ms.length; j++) {
            final bool newMerge = ofV13(ms[i]) != ofV13(ms[j]);
            final bool differentNames =
                nameContentOf(ms[i]) != nameContentOf(ms[j]);
            if (newMerge && differentNames) {
              newDifferentNameMerges.add('"${ms[i]}" + "${ms[j]}" -> "$key"');
            }
          }
        }
      });

      expect(
        newDifferentNameMerges,
        isEmpty,
        reason:
            'a THIRD undisclosed cost of the KHA-106 kind: v1.4 merges two '
            'different businesses that v1.3 kept apart',
      );
    });

    test('E4b — DEFECT D-QA-34-1: the disclosed cost is WIDER than the '
        'example that documents it (documentation-accuracy, Low)', () {
      // The PR pins ONE example of disclosed cost #2 — `QAMART 1000 STORE` ==
      // `QAMART 2000 STORE`, a four-digit pair — and ADR-008 v1.4's
      // consequences list names the same shape.
      //
      // The actual class is **any digit run adjacent to a marker, at any
      // length**, and the sub-4-digit half of it is genuinely NEW in v1.4
      // (v1.3 read adjacency on the left only, so a right-hand marker did not
      // corroborate and the run survived). Asserted here because it is exactly
      // the pattern KHA-106 was filed for: a consequence that is correct by
      // design but was never *stated*, so nobody decided it.
      //
      // It is Low, not High: it merges numbered siblings of ONE name, never
      // two names (E2/E4 prove that), and it is the necessary consequence of
      // order-insensitivity — `QAMART STORE 100` and `QAMART STORE 200`
      // already merged under v1.3, so the permutation must merge too or
      // KHA-107 is not fixed. The defect is the disclosure, not the behaviour.
      expect(ofV13('QANDA 100 STORE'), 'QANDA 100');
      expect(ofV13('QANDA 200 STORE'), 'QANDA 200');
      expect(
        ofV13('QANDA 100 STORE'),
        isNot(ofV13('QANDA 200 STORE')),
        reason: 'under v1.3 this three-digit pair was TWO identities',
      );

      expect(MerchantKey.of('QANDA 100 STORE'), 'QANDA');
      expect(MerchantKey.of('QANDA 200 STORE'), 'QANDA');
      expect(
        MerchantKey.of('QANDA 100 STORE'),
        MerchantKey.of('QANDA 200 STORE'),
        reason:
            'under v1.4 it is ONE — a new sibling merge below the four-digit '
            'length the disclosure names',
      );
    });

    test(
      'E5 — the KHA-109 all-digit-key residual is NOT worsened by this PR',
      () {
        // KHA-109 (still open, not this PR's problem) is the residual class of
        // keys made only of digits. The brief asks to check nothing similar was
        // introduced. It was not — the net movement is strongly in the safe
        // direction, and this pins that so a future change cannot quietly
        // reverse it.
        int v13AllDigit = 0;
        int v14AllDigit = 0;
        final RegExp allDigitKey = RegExp(r'^[0-9 ]+$');
        for (final String s in buildCorpus()) {
          final String a = ofV13(s);
          final String b = MerchantKey.of(s);
          if (a.isNotEmpty && allDigitKey.hasMatch(a)) v13AllDigit++;
          if (b.isNotEmpty && allDigitKey.hasMatch(b)) v14AllDigit++;
        }
        expect(
          v14AllDigit,
          lessThanOrEqualTo(v13AllDigit),
          reason:
              'v1.4 must not grow the KHA-109 class. v1.3=$v13AllDigit, '
              'v1.4=$v14AllDigit',
        );

        // The specific shape that MOVED: a bare number beside a marker used to
        // key as that number; now it correctly has no identity at all (KHA-102's
        // reasoning — a string of nothing but structural tokens and a number
        // cannot distinguish two businesses).
        expect(ofV13('100 STORE'), '100');
        expect(
          MerchantKey.ofOrNull('100 STORE'),
          isNull,
          reason: 'an improvement, and an undisclosed one — worth stating',
        );
      },
    );
  });

  // =========================================================================
  // UI PROBES — TIER: personal depth. Highest-value only.
  // =========================================================================
  group('PROBE U — the P4b surfaces', () {
    late AppDatabase db;
    late CategoryDao categoryDao;
    late TransactionDao transactionDao;
    late MerchantDao merchantDao;
    late CategorizationService service;
    late CategoryCorrectionService corrections;
    late AuditLogDao auditLogDao;

    setUp(() async {
      db = openPlainTestDatabase();
      auditLogDao = AuditLogDao(db, auditChainKey: _testChainKey);
      categoryDao = CategoryDao(db, auditLogDao);
      transactionDao = TransactionDao(db, auditLogDao);
      merchantDao = MerchantDao(db, auditLogDao);
      service = CategorizationService(
        categoryDao: categoryDao,
        merchantDao: merchantDao,
        transactionDao: transactionDao,
      );
      corrections = CategoryCorrectionService(
        categorization: service,
        transactionDao: transactionDao,
        merchantDao: merchantDao,
      );
      await service.ensureDefaultsSeeded();
    });

    tearDown(() async => db.close());

    Future<int> spend(
      String amount, {
      String? categoryId,
      int day = 15,
      String currency = 'SAR',
      String direction = 'debit',
      String transactionType = 'pos_purchase',
    }) async {
      final int id = await transactionDao.insertFromParsedSms(
        occurredAt: DateTime.utc(2026, 7, day, 12),
        amount: Money.parse(amount, currency: currency),
        direction: direction,
        transactionType: transactionType,
        affectsSpend: true,
        merchantRawText: 'QANDA MART',
        sourceMessageId: day,
        rulePackId: 'qa-pack',
        rulePackVersion: '1.0.0',
        ruleId: 'qa-rule',
      );
      if (categoryId != null) {
        await transactionDao.setUserCategory(id: id, categoryId: categoryId);
      }
      return id;
    }

    Future<CategoryBreakdown> breakdown() async => CategoryBreakdown.of(
      toLedgerTransactions(await transactionDao.all()),
      period: _july2026,
      resolver: await service.resolver(),
    );

    /// AC-C1.3, plus the independent recomputation that makes it a business
    /// oracle rather than a self-consistency check: the slices must sum to the
    /// figure `LedgerTotals` produces by a *different* code path.
    Future<void> expectSumInvariant(String after) async {
      final CategoryBreakdown result = await breakdown();
      expect(result.reconciles, isTrue, reason: 'AC-C1.3 broken after $after');
      final PeriodTotals independent = LedgerTotals.spend(
        toLedgerTransactions(await transactionDao.all()),
        period: _july2026,
      );
      expect(
        result.total.base,
        independent.base,
        reason:
            'the breakdown total drifted from the period total after $after',
      );
    }

    testWidgets('U1 — AC-C1.3 survives a category delete driven through the '
        'S-15 WIDGET, for both decisions (KHA-97 done-check)', (
      WidgetTester tester,
    ) async {
      // KHA-97's done-check says, verbatim: *"both decisions leave the
      // AC-C1.3 category-sum invariant intact (already covered by
      // category_sum_invariant_test.dart at the data layer — **this adds the
      // widget-level path**)"*.
      //
      // No P4b test asserts the invariant on the widget path — grep for
      // `reconciles` in `test/widget/p4b_screens_test.dart` returns nothing.
      // This probe is that missing half: it wires the REAL DAO behind the real
      // screen's `onDelete` callback and drives the dialog with taps, so what
      // is verified is the production write the button actually performs.
      useTallSurface(tester);

      final CategoryRow custom = (await categoryDao.createCustom(
        name: 'QA Coffee',
        iconToken: 'label',
        groupKey: 'spending',
      ))!;

      await spend('100.00', categoryId: 'groceries');
      await spend('40.00', categoryId: custom.id, day: 16);
      await spend('25.00', categoryId: custom.id, day: 17);
      await spend('10.00', day: 18); // uncategorized
      await expectSumInvariant('seeding');

      // The ledger sums to 175.00 by hand: 100 + 40 + 25 + 10. Asserting the
      // literal figure is what makes this an oracle rather than a tautology —
      // "the parts sum to the whole" passes even if both are wrong.
      final CategoryBreakdown before = await breakdown();
      expect(before.total.base, Money.parse('175.00', currency: 'SAR'));

      // The whole category list, so the S-15 dialog has real reassignment
      // targets — `_ReassignDialog.targets` is derived from `items`.
      final List<Category> all = await service.categories();
      await tester.pumpWidget(
        wrap(
          CategoryManagementScreen(
            items: <CategoryListItem>[
              for (final Category c in all)
                CategoryListItem(
                  category: c,
                  transactionCount: await categoryDao.countTransactionsUsing(
                    c.id,
                  ),
                ),
            ],
            onDelete: (Category c, CategoryDeleteDecision d) async {
              await categoryDao.deleteCategory(
                id: c.id,
                decision: d,
                actor: 'user',
              );
            },
          ),
        ),
      );

      await tester.scrollUntilVisible(
        find.byKey(Key('categories.delete.${custom.id}')),
        200,
      );
      await tester.tap(find.byKey(Key('categories.delete.${custom.id}')));
      await tester.pumpAndSettle();

      // AC-C3.3 — the confirm button is disabled until a decision exists. This
      // is the criterion KHA-97 calls "a property of the widget tree", so it is
      // read off the widget rather than inferred from behaviour.
      final Finder confirm = find.byKey(const Key('categories.deleteConfirm'));
      expect(confirm, findsOneWidget);
      expect(
        tester.widget<ButtonStyleButton>(confirm).onPressed,
        isNull,
        reason: 'AC-C3.3 — the delete must block until the user chooses',
      );

      // Choose *Uncategorized* from the picker. The screen turns this into the
      // sealed `SetToUncategorized`, never `ReassignTo('uncategorized')`.
      await tester.tap(find.byKey(const Key('categories.reassignPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uncategorized').last);
      await tester.pumpAndSettle();

      expect(
        tester.widget<ButtonStyleButton>(confirm).onPressed,
        isNotNull,
        reason: 'a decision now exists, so the delete may proceed',
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      // THE POINT: the money did not move. The two rows that were 'QA Coffee'
      // are now Uncategorized, and 40 + 25 is still inside the 175.00 total.
      await expectSumInvariant('a widget-driven delete-with-uncategorize');
      final CategoryBreakdown after = await breakdown();
      expect(
        after.total.base,
        Money.parse('175.00', currency: 'SAR'),
        reason:
            'deleting a CATEGORY must never delete or hide the TRANSACTIONS '
            'in it — the category-sum invariant is a money guarantee',
      );
      expect(after.uncategorizedCount, 3, reason: '1 original + the 2 moved');
      expect(
        await categoryDao.byId(custom.id),
        isNull,
        reason: 'the category itself is gone',
      );
    });

    testWidgets('U2 — a category delete that REASSIGNS also preserves the sum, '
        'and moves exactly the right rows', (WidgetTester tester) async {
      useTallSurface(tester);
      final CategoryRow custom = (await categoryDao.createCustom(
        name: 'QA Coffee',
        iconToken: 'label',
        groupKey: 'spending',
      ))!;
      await spend('100.00', categoryId: 'groceries');
      await spend('40.00', categoryId: custom.id, day: 16);
      await spend('25.00', categoryId: custom.id, day: 17);

      await tester.pumpWidget(
        wrap(
          CategoryManagementScreen(
            items: <CategoryListItem>[
              CategoryListItem(
                // Read back through the service rather than hand-built, so the
                // widget is driven by the same `Category` the real
                // `categoryListProvider` would hand it.
                category: (await service.categories()).firstWhere(
                  (Category c) => c.id == custom.id,
                ),
                transactionCount: 2,
              ),
            ],
            onDelete: (Category c, CategoryDeleteDecision d) async {
              await categoryDao.deleteCategory(
                id: c.id,
                decision: d,
                actor: 'user',
              );
            },
          ),
        ),
      );

      await tester.tap(find.byKey(Key('categories.delete.${custom.id}')));
      await tester.pumpAndSettle();
      // Drive the reassignment path rather than the uncategorize one.
      await categoryDao.deleteCategory(
        id: custom.id,
        decision: const ReassignTo('groceries'),
        actor: 'user',
      );

      await expectSumInvariant('a delete-with-reassign');
      final CategoryBreakdown after = await breakdown();
      // The oracle: groceries must now hold 100 + 40 + 25 = 165.00 exactly.
      final CategoryTotal groceries = after.categories.firstWhere(
        (CategoryTotal s) => s.category.id == 'groceries',
      );
      expect(
        groceries.totals.base,
        Money.parse('165.00', currency: 'SAR'),
        reason:
            'reassignment must move the money into the target category, not '
            'merely detach it from the deleted one',
      );
    });

    test(
      'U3 — adversarial category names: injection, unicode and length are '
      'stored as DATA, never executed, and folding still de-duplicates',
      () async {
        // The highest-value data-integrity probe on the new CRUD surface. Drift
        // parameterises, so injection is expected to fail — the probe exists to
        // prove it on THIS path and to record the attempt as audit evidence.
        final List<String> attacks = <String>[
          "'; DROP TABLE category;--",
          "' OR '1'='1",
          // U+202E RIGHT-TO-LEFT OVERRIDE, built from its code point rather than
          // pasted as a literal so this file stays greppable as text — a
          // display-spoofing attempt (the name renders reversed in a list).
          'QA${String.fromCharCode(0x202E)}gnicnalab',
          // An embedded NUL, again built from its code point. Written this way
          // deliberately: `test/source_hygiene_test.dart` refuses a raw control
          // byte anywhere in `lib/` or `test/`, and it caught an earlier draft
          // of this very line — which is exactly the guard working.
          'QA${String.fromCharCode(0)}Null',
        ];
        for (final String attack in attacks) {
          final CategoryRow? row = await categoryDao.createCustom(
            name: attack,
            iconToken: 'label',
            groupKey: 'spending',
          );
          // Either it is stored verbatim as data, or it is refused. What must
          // NOT happen is the statement executing.
          if (row != null) {
            expect(row.nameEn, attack, reason: 'stored as data, unchanged');
          }
        }
        // The table still exists and the seed data is intact — the DROP did not
        // run.
        final List<Category> categories = await service.categories();
        expect(
          categories.any((Category c) => c.id == 'groceries'),
          isTrue,
          reason: 'injection would have taken the category table with it',
        );

        // AC-C3.2's folding: a "different" name that folds to an existing one is
        // refused rather than creating a second row the user cannot tell apart.
        expect(
          await categoryDao.createCustom(
            name: '  qa   COFFEE  ',
            iconToken: 'label',
            groupKey: 'spending',
          ),
          isNotNull,
        );
        expect(
          await categoryDao.createCustom(
            name: 'QA Coffee',
            iconToken: 'label',
            groupKey: 'spending',
          ),
          isNull,
          reason:
              'AC-C3.2 — case and spacing fold together, so this is a duplicate',
        );
      },
    );

    test('U4 — AC-C4.2 review count is a UNION, verified against a hand '
        'recount of the rows (KHA-32 done-check)', () async {
      // KHA-32's done-check: *"the review count equals the number of flagged
      // plus uncategorized items, verified against the data layer"*. The
      // implementation deliberately reads that as a UNION. This recomputes the
      // answer independently from the rows and asserts the figure — a business
      // oracle, not "a number appeared".
      await spend('10.00', categoryId: 'groceries'); // neither
      await spend('20.00', day: 16); // uncategorized only

      // Flagged AND categorized — written through the real automatic path, so
      // the flag is set the way production sets it rather than by poking the
      // column directly.
      final int flaggedOnly = await spend('30.00', day: 17);
      await transactionDao.applyAutomaticCategory(
        id: flaggedOnly,
        categoryId: 'dining',
        confidence: 0.40,
        actorDetail: 'qa-probe',
        flagForReview: true,
        reviewReason: CategoryReviewReason.lowConfidenceCategory,
      );

      // Flagged AND uncategorized — the row that makes union != sum.
      final int both = await spend('40.00', day: 18);
      await transactionDao.applyAutomaticCategory(
        id: both,
        categoryId: null,
        confidence: 0.10,
        actorDetail: 'qa-probe',
        flagForReview: true,
        reviewReason: CategoryReviewReason.unknownMerchant,
      );

      final List<TransactionRow> rows = await transactionDao.all();
      final ReviewCounts counts = ReviewCounts.fromRows(rows);

      // Recounted by hand from the four rows above, by a different path.
      final int handUncategorized = rows
          .where((TransactionRow r) => r.categoryId == null)
          .length;
      final int handFlagged = rows
          .where((TransactionRow r) => r.needsReview)
          .length;
      final int handUnion = rows
          .where((TransactionRow r) => r.categoryId == null || r.needsReview)
          .length;

      expect(counts.uncategorized, handUncategorized);
      expect(counts.flagged, handFlagged);
      expect(counts.needingAttention, handUnion);

      // The literal answer, so a change in both the code and the recount
      // cannot pass unnoticed: 2 uncategorized, 2 flagged, 3 distinct rows.
      expect(counts.uncategorized, 2);
      expect(counts.flagged, 2);
      expect(
        counts.needingAttention,
        3,
        reason:
            'the row that is BOTH is one thing needing review — a sum would '
            'say 4 and tell the user there are more problems than there are',
      );
    });

    test('U5 — AC-C5.2 undo restores each row\'s OWN prior category when the '
        'priors genuinely DIFFER', () async {
      // The shipped test for this criterion (`category_correction_test.dart`,
      // *"rows that had DIFFERENT prior categories each get their own back,
      // not a default"*) states the risk exactly right in its own comment —
      // *"this is the case a 'reset to Uncategorized' undo destroys"* — and
      // then does not construct it: all three of its rows have a `null` prior,
      // and all three are asserted back to `null`. A buggy undo that reset
      // every row to Uncategorized would pass it unchanged.
      //
      // The mixed case IS reachable, because the bulk fill only touches
      // *uncategorized* rows (AC-C5.1) while the TARGET row may already carry
      // a category — the user correcting a wrong one is the product's
      // highest-frequency interaction (NFR-U7). So: one row starting at
      // `dining`, two starting blank, corrected merchant-wide to `groceries`,
      // then undone. A correct undo returns three DIFFERENT answers.
      final int target = await spend('75.00', day: 3);
      final int blankA = await spend('20.00', day: 4);
      final int blankB = await spend('30.00', day: 5);
      for (final int id in <int>[target, blankA, blankB]) {
        await service.categorizeTransaction(transactionId: id);
      }

      // The target's genuine prior: an existing user category.
      await transactionDao.setUserCategory(id: target, categoryId: 'dining');
      expect((await transactionDao.byId(target)).categoryId, 'dining');
      expect((await transactionDao.byId(blankA)).categoryId, isNull);

      final CategoryCorrection correction = await corrections.correct(
        transactionId: target,
        categoryId: 'groceries',
        scope: CorrectionScope.thisAndFuture,
      );
      // All three now read `groceries` — the state the undo must unpick.
      for (final int id in <int>[target, blankA, blankB]) {
        expect((await transactionDao.byId(id)).categoryId, 'groceries');
      }

      await corrections.undo(correction.undo);

      // THE ORACLE: three rows, two different answers, neither of them a
      // default. This is the assertion that distinguishes "restored each row's
      // own prior" from "reset everything".
      expect(
        (await transactionDao.byId(target)).categoryId,
        'dining',
        reason:
            'AC-C5.2 — the corrected row goes back to the category it '
            'actually had, not to Uncategorized',
      );
      expect((await transactionDao.byId(blankA)).categoryId, isNull);
      expect((await transactionDao.byId(blankB)).categoryId, isNull);

      // NFR-A3 — the undo APPENDS history rather than erasing it, and the
      // hash chain still verifies after all of the above.
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });
  });
}

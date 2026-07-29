import 'package:drift/drift.dart';

/// **`Merchant`** — `docs/architecture.md` §4.2, ADR-008, risk R-5.
///
/// One row per *place the user's money went*, as opposed to per *string a bank
/// printed*. The distinction is the entire point of the table: PRD §3.4
/// observes that the same shop appears as `PANDA STORE 1234`, `Panda`, and —
/// in a fully Arabic message — a Latin transliteration, and the product's core
/// promise (KHA-31: *"correct it once per merchant and it stays right"*)
/// cannot be kept if each spelling is its own merchant.
///
/// ## [merchantKey] is the identity; [canonicalName] is the label
///
/// [merchantKey] is produced by `MerchantKey.of` — ADR-008's normalisation
/// pipeline — and is `UNIQUE`, so two ingestion paths racing on the same
/// merchant cannot create two rows. [canonicalName] is the first raw string we
/// saw, kept for display, because the key has been upper-cased and
/// orthographically folded and showing it to the user would show them a
/// misspelling of their own merchant.
///
/// ## NFR-S4 / NFR-M3
///
/// A merchant name is personal data: it says where someone shops. It is never
/// logged (ADR-015 makes that structurally hard), and no real merchant string
/// from a user's SMS appears in a test fixture or a PR body — the corpus in
/// `test/features/categorization/` is synthetic.
@DataClassName('MerchantRow')
class Merchants extends Table {
  @override
  String get tableName => 'merchant';

  IntColumn get id => integer().autoIncrement()();

  /// The first raw merchant string observed for this merchant, for display.
  TextColumn get canonicalName => text()();

  /// ADR-008's normalised key. `UNIQUE` — see the class comment.
  TextColumn get merchantKey => text().unique()();

  /// `raw_message.id` of the message that first mentioned this merchant
  /// (NFR-A1), or null when the user created it by hand.
  IntColumn get firstSeenMessageId => integer().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// **`MerchantAlias`** — ADR-008's answer to *the hard half of R-5*.
///
/// > Arabic and Latin renderings of the same merchant cannot be reliably
/// > transliterated. **We do not try.** Instead: a `MerchantAlias` table. From
/// > the review UI the user can link an alias to a canonical merchant in one
/// > action; rules key on `merchantId`, not on the raw string, so one link
/// > fixes both scripts forever.
///
/// ## Nothing in P4a writes a row here automatically, and that is deliberate
///
/// [source] has two values, `user` and `observed`, and P4a only ever writes
/// `user`. An automatic writer is *tempting* — a token-set match could record
/// what it matched so the next one is an exact hit — and it is exactly the
/// wrong thing, because it would silently promote a fuzzy guess into a
/// permanent identity claim. The next message would then match at confidence
/// 1.00 on the strength of a 0.85 guess nobody confirmed, and AC-D2.3's
/// *"never silently merge unrelated merchants"* would be broken by a mechanism
/// designed to help. `observed` exists in the vocabulary for a future,
/// user-confirmed path (P4b's "did you mean…"), not as a gap.
@DataClassName('MerchantAliasRow')
class MerchantAliases extends Table {
  @override
  String get tableName => 'merchant_alias';

  IntColumn get id => integer().autoIncrement()();

  /// The canonical merchant this alias resolves to.
  ///
  /// `customConstraint` rather than `.references(Merchants, #id)` for the same
  /// drift 2.31 reason documented on `instrument_table.dart`'s `bankId`: the
  /// Dart-side resolver silently emits *no* foreign key under this project's
  /// pinned analyzer, and a constraint you believe you have and do not is
  /// worse than none.
  IntColumn get merchantId =>
      integer().customConstraint('NOT NULL REFERENCES merchant(id)')();

  /// The normalised key of the *alternative* spelling, produced by the same
  /// `MerchantKey.of` pipeline. `UNIQUE`, so one spelling can never point at
  /// two different merchants — which is the database refusing to represent an
  /// ambiguity the matcher would otherwise have to resolve by guessing.
  TextColumn get aliasKey => text().unique()();

  /// `arabic` | `latin` | `mixed` — recorded so a future review screen can
  /// explain *why* two spellings were linked.
  TextColumn get script => text()();

  /// `user` | `observed`. P4a writes only `user` — see the class comment.
  TextColumn get source => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// **`MerchantRule`** — Epic D's learned rule store, architecture §4.2.
///
/// One row is one sentence: *"money going to this merchant belongs in this
/// category"*. AC-D1.1 requires that sentence to appear in a learned-rules
/// list the user can see and edit, which is why it is a row and not an
/// inference over past transactions.
///
/// ## Two invariants that are not negotiable
///
/// 1. **Rules are created and updated only by explicit user action**
///    (ADR-008, AC-D3.2). An automatic match reads this table and never writes
///    it — with one exception that is not a mutation of meaning: [appliedCount]
///    and [lastAppliedAt], which count firings and are not part of what the
///    rule *says*. `MerchantRuleDao` enforces this by exposing no
///    category-changing method that does not take a user actor.
///
/// 2. **`source = user` outranks `source = seed`** (AC-D3.1). Represented as a
///    confidence difference (1.00 vs 0.90 in `CategorizationConfig`) *and* as
///    an ordering in the matcher, so a seed rule can never win against a user
///    rule for the same merchant even if the numbers were tuned to collide.
///
/// ## Why `UNIQUE(merchant_id)` and not a history of rules
///
/// AC-D1.2: re-categorising another transaction from merchant M to a different
/// category **updates** the rule rather than adding a second one. A merchant
/// with two live rules would be a matcher that has to pick, which is a coin
/// toss with the user's money-tracking. The rule's change history lives in the
/// audit trail (ADR-010), which is where history belongs — the store holds
/// what is true *now*.
@DataClassName('MerchantRuleRow')
class MerchantRules extends Table {
  @override
  String get tableName => 'merchant_rule';

  IntColumn get id => integer().autoIncrement()();

  /// One live rule per merchant — see the class comment.
  ///
  /// `UNIQUE` is written inside the custom constraint rather than as a
  /// separate `.unique()` call: a column-level `customConstraint` **replaces**
  /// everything drift would have generated for the column, so a `.unique()`
  /// alongside it would silently produce no constraint at all (the same trap
  /// `instrument_table.dart` documents for `NOT NULL`).
  IntColumn get merchantId =>
      integer().customConstraint('NOT NULL UNIQUE REFERENCES merchant(id)')();

  /// The category this merchant's transactions belong in.
  ///
  /// Not declared as a SQL foreign key, and the reason is the same one that
  /// makes `AppDatabase`'s category-delete trigger the right mechanism: the
  /// guarantee AC-C3.3 asks for is *"no transaction points at a missing
  /// category"*, and it is enforced at the single operation that could break
  /// it (the delete) for every referencing table at once. `CategoryDao.deleteCategory`
  /// repoints or removes the rules that name the doomed category inside the
  /// same database transaction as the delete.
  TextColumn get categoryId => text()();

  /// `exact_key` | `token_set` | `manual_alias` — how the rule is intended to
  /// be matched. Recorded per architecture §4.2; the matcher currently applies
  /// every rule through the full tier ladder regardless, so this is
  /// descriptive of the rule's origin rather than a switch.
  TextColumn get matchType => text().withDefault(const Constant('exact_key'))();

  /// `user` | `seed`. See invariant 2 in the class comment.
  TextColumn get source => text()();

  /// False hides the rule from matching without destroying what the user
  /// taught (US-D4's rule management, P4b).
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();

  /// How many times this rule has auto-categorised a transaction. The
  /// learned-rules list shows it so a user can see which lessons are earning
  /// their keep (AC-D1.1's "visible").
  IntColumn get appliedCount => integer().withDefault(const Constant(0))();

  DateTimeColumn get lastAppliedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

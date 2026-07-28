import 'package:drift/drift.dart';

/// **Scope note — P1 created this, P2 extended it, P3a completes the spine.**
///
/// `docs/architecture.md` §4.2 defines the full `Transaction` entity. P1
/// created a deliberately minimal version, purely to give the append-only
/// audit trail (ADR-010) a real mutation path to prove itself against.
///
/// **P2 (this phase) added exactly the columns SMS ingestion cannot work
/// without**, and no more:
///
///  - **Provenance** (`provenance`, `sourceMessageId`, `rulePackId`,
///    `rulePackVersion`, `ruleId`) — NFR-A1 requires every transaction to
///    know where it came from, and provenance cannot be reconstructed after
///    the fact. It has to be written at the moment of the write.
///  - **`occurredAt` + `referenceNumber` + `direction` + `affectsSpend`** —
///    ADR-017's duplicate-detection tiers are *defined* in terms of these.
///    Without them, dedup is untestable rather than merely unimplemented.
///  - **The dedup outcome fields** (`needsReview`, `reviewReason`,
///    `possibleDuplicateOfId`) — because ADR-017's central rule is
///    "**flag, never auto-remove**", and a flag needs somewhere to live.
///  - **FX triple** (`convertedAmount*`, `feeAmount*`) — PRD §3.4's fee
///    component must be its own field from the first write, not folded in
///    and separated later.
///
/// **P3a (this phase — KHA-25) adds the rest of the record's spine:**
///
///  - **`instrumentId`** — the real foreign key to `instrument`, which now
///    exists. `instrumentKind`/`instrumentMaskedRef` are **kept** rather than
///    dropped: they are what the message itself said, and they remain
///    meaningful when the identifier could not be masked into a usable
///    `refKey` (fewer than four digits) and therefore matched no instrument.
///    A null `instrumentId` is AC-B1.3's explicit unknown, not a data error.
///  - **`counterpartyName` / `counterpartyBankName` / `remainingBalance*`** —
///    architecture §4.2 fields the parser already extracted and P2 had
///    nowhere to put. AC-B1.1 asks the detail view to show the payee; for a
///    transfer, the counterparty *is* the payee.
///  - **`provenanceDetail`** — see the doc comment on that column.
///  - **`deletedAt`** — soft delete previously recorded *that* a row was
///    deleted but not *when*, which AC-B6.4 needs.
///
/// **P3b-1 (KHA-27, KHA-28, KHA-29, KHA-70) adds the columns a period total
/// needs to *mean* something:** the rest of the FX block (`fxRateDate`,
/// `fxRateSource`, `conversionPending`) and the internal-transfer link
/// (`internalTransferGroupId`, `internalTransferState`). KHA-28 needed no new
/// column at all — see the note on `direction` below and the full statement of
/// the sign convention in `lib/core/money/sign_convention.dart`.
///
/// **Still not here, deliberately:** foreign keys to `Category` and
/// `Merchant` (P4 owns those tables), `isExcluded` and the restore UX
/// (KHA-26, P3b-2), the fee's `parentTransactionId` child-row form (ADR-009's
/// stronger variant of PRD §3.4's "own field" — the field form ships now
/// because the parser produces one row per message, and the child-row form is
/// a P4 reporting decision) and categorisation confidence (P4). Each arrives
/// with the behaviour that gives it meaning, rather than as an unused column.
///
/// The SQL table is named `transactions` (plural) rather than the singular
/// domain word, specifically to avoid any ambiguity with SQLite's own
/// `TRANSACTION` keyword (used in `BEGIN TRANSACTION`) — a defensive choice,
/// not a hint that the underlying concept is anything other than "one
/// transaction record" (`docs/architecture.md`'s `Transaction` entity).
@DataClassName('TransactionRow')
class Transactions extends Table {
  @override
  String get tableName => 'transactions';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get merchantRawText => text().nullable()();

  // --- ADR-002 money triple: every stored amount is TEXT (authoritative,
  // exact decimal string) + TEXT (currency) + INTEGER (non-authoritative,
  // indexing-only minor units). No monetary total is ever produced by
  // summing `amountMinor` in SQL — see `.github/scripts/check_money_type_ban.sh`
  // and ADR-002's non-negotiable rule.
  TextColumn get amountAmount => text()();
  TextColumn get amountCurrency => text()();
  IntColumn get amountMinor => integer()();

  /// Nullable, no FK target yet (the `Category` table is P4 work) —
  /// intentionally loose in this P1-minimal table.
  TextColumn get categoryId => text().nullable()();

  // --- P2: multi-currency, with the fee kept separate ----------------------
  //
  // PRD §3.4 and Linear KHA-19 are explicit: the FX/international fee is its
  // own component and must NOT be folded into the spend amount. Folding it
  // in overstates what the merchant charged and makes the fee invisible to
  // the "where does my money go" question the product exists to answer.

  /// The bank's own inline conversion into the base currency, where the
  /// message supplied one. ADR-009 prefers the bank's figure over anything
  /// we could derive: it is what actually hit the account.
  TextColumn get convertedAmountAmount => text().nullable()();
  TextColumn get convertedAmountCurrency => text().nullable()();
  IntColumn get convertedAmountMinor => integer().nullable()();

  TextColumn get feeAmountAmount => text().nullable()();
  TextColumn get feeAmountCurrency => text().nullable()();
  IntColumn get feeAmountMinor => integer().nullable()();

  /// Exact decimal **string**, never a float (ADR-002). A rate is not an
  /// amount of money, so it is not a `Money` triple either.
  TextColumn get fxRate => text().nullable()();

  // --- P3b-1: the rest of architecture §4.2's FX block (KHA-27, KHA-70) -----
  //
  // Schema v3 shipped `fxRate` alone, so the detail screen rendered a rate the
  // user could not date — defect D-QA-2 / KHA-70. AC-B9.3 asks for the rate
  // **and its date**, and ADR-009 asks for the source and for an explicit
  // "not converted" state. All three land together, because a rate without a
  // date and a provenance is exactly the authoritative-looking-but-unverifiable
  // figure this app exists to avoid.

  /// The date [fxRate] applies to.
  ///
  /// **NULL is a real, expected value** and must never be defaulted: it means
  /// the message stated no date, which the UI renders as the words *"date
  /// unknown"*. Storing `now()` here instead would fabricate a fact.
  DateTimeColumn get fxRateDate => dateTime().nullable()();

  /// `sms_implied` | `sms_stated` | `user` | `carried_forward` — ADR-009's
  /// table, mirrored by `FxRateSource` in `features/ledger/base_currency.dart`.
  TextColumn get fxRateSource => text().nullable()();

  /// **ADR-009 case 4.** True for a foreign-currency transaction whose message
  /// supplied neither a converted amount nor a rate.
  ///
  /// Such a row is excluded from base-currency totals and counted on an
  /// explicit "N transactions not converted" line, so reconciliation is
  /// *visibly* incomplete rather than silently wrong. Defaults to false, which
  /// is correct for every existing row: a base-currency transaction is never
  /// pending, and a foreign one that already stored a converted amount is not
  /// either.
  BoolColumn get conversionPending =>
      boolean().withDefault(const Constant(false))();

  // --- P3b-1: internal transfers (KHA-29, US-B11) ---------------------------

  /// The pair this transaction belongs to (architecture §4.2
  /// `InternalTransferLink.groupId`), when a link has been **persisted**.
  ///
  /// Read-time detection (`features/ledger/internal_transfer.dart`) derives
  /// pairs without writing anything, because the two legs routinely arrive in
  /// separate messages hours apart and a decision taken at ingestion would
  /// have to be revisited when the second one lands. This column exists for
  /// the user's own confirmation, which P3b-2 wires up.
  TextColumn get internalTransferGroupId => text().nullable()();

  /// `internal` | `candidate` | `external`, or NULL for "nobody has ruled on
  /// this".
  ///
  /// A stored value **outranks** anything derived: it records a decision a
  /// person made (AC-B11.2), and a screen re-deriving over the top of it would
  /// silently overrule the user.
  TextColumn get internalTransferState => text().nullable()();

  // --- P2: when, and which way ---------------------------------------------

  /// When the movement happened, per the message, in UTC.
  ///
  /// Distinct from `createdAt` (when *we* recorded it) on purpose: a
  /// historical import writes rows today for purchases made three weeks ago,
  /// and a period total keyed on `createdAt` would put every one of them in
  /// the wrong month.
  DateTimeColumn get occurredAt => dateTime().nullable()();

  /// `sms_explicit` | `sms_local_assumed` | `received_at_fallback`
  /// (architecture §7.4). Recorded so an odd-looking timestamp is
  /// explainable rather than mysterious.
  TextColumn get timeSource => text().nullable()();

  /// `debit` | `credit`. **This column is where the sign of a movement
  /// lives, and it is the only place it lives** — `amount_amount` is always a
  /// non-negative magnitude.
  ///
  /// A refund is a credit and **reduces** period spend (US-B7); it is never
  /// stored as a negative debit. `lib/core/money/sign_convention.dart`
  /// is the full statement of this decision, including why a signed amount
  /// was rejected and what it obliges the manual-entry form to validate
  /// (defect O-QA-2). Read it before adding any write path that touches
  /// money.
  TextColumn get direction => text().withDefault(const Constant('debit'))();

  /// The matched rule's `messageType`, e.g. `pos_purchase`, `installment`.
  TextColumn get transactionType =>
      text().withDefault(const Constant('unknown'))();

  /// Whether this counts toward "money spent" (US-B10/B11). `false` for
  /// internal transfers, salary income, and card repayment.
  BoolColumn get affectsSpend => boolean().withDefault(const Constant(true))();

  /// Present on transfers and some bill payments (PRD §3.4). The reliable
  /// duplicate key when it exists (ADR-017 D2).
  TextColumn get referenceNumber => text().nullable()();

  // --- P2: what the message said about the instrument ----------------------

  /// `card` | `account`, from the matched rule's declaration — never guessed
  /// from digit length (AC-B13.1/2).
  TextColumn get instrumentKind => text().nullable()();

  /// Already masked, e.g. `****4821`. There is deliberately no column in this
  /// schema capable of holding a full PAN (NFR-S2, architecture §4.2).
  TextColumn get instrumentMaskedRef => text().nullable()();

  // --- P3a: the resolved instrument (KHA-23, KHA-25) ------------------------

  /// The `instrument` row this transaction hit.
  ///
  /// **Nullable on purpose** (architecture §4.2 says so explicitly): a
  /// message that named no instrument, or named one with too few digits to
  /// mask meaningfully, produces a transaction whose instrument is
  /// *explicitly unknown* (AC-B1.3). Defaulting to some "unassigned"
  /// instrument row would put real money under a fictional card.
  /// (Written as an explicit SQL constraint rather than `.references(...)` —
  /// see the same note on `instrument_table.dart`'s `bankId`. `ALTER TABLE
  /// ADD COLUMN` accepts a `REFERENCES` clause as long as the column defaults
  /// to NULL, which it does, so an upgraded database gets exactly the same
  /// constraint a fresh install does.)
  IntColumn get instrumentId =>
      integer().nullable().customConstraint('REFERENCES instrument(id)')();

  // --- P3a: fields the parser already produced and P2 could not store -------

  /// Who the money went to or came from on a transfer (PRD §3.4). For a
  /// transfer this is the payee AC-B1.1 asks the detail view to show; for a
  /// purchase it is null and `merchantRawText` plays that role.
  TextColumn get counterpartyName => text().nullable()();

  /// The counterparty's bank, where the message named it.
  TextColumn get counterpartyBankName => text().nullable()();

  /// The balance a message reported *after* the movement — PRD §3.4 notes the
  /// installment template does this.
  ///
  /// **Informational only. It is never treated as spend and never summed**;
  /// it is stored as a `Money` triple like every other amount purely so it
  /// cannot accidentally be handled as a float on its way to the screen.
  TextColumn get remainingBalanceAmount => text().nullable()();
  TextColumn get remainingBalanceCurrency => text().nullable()();
  IntColumn get remainingBalanceMinor => integer().nullable()();

  // --- P2: provenance (NFR-A1) ---------------------------------------------

  /// `sms` | `manual` | `statement`. P7 must not create a fourth, untracked
  /// path (build-plan §5).
  TextColumn get provenance => text().withDefault(const Constant('sms'))();

  /// A refinement of [provenance], not a fourth value of it.
  ///
  /// KHA-64/AC-A4.2 creates a genuinely hybrid record: an unparsed SMS the
  /// **user** completed by hand. Recording it as `manual` would throw away
  /// the source-message reference NFR-A1 requires; recording it as plain
  /// `sms` would claim the parser produced numbers a human actually typed.
  /// So [provenance] stays `sms` (the message reference is real and is kept)
  /// and this column carries `manual_completion`. Architecture §4.2's
  /// three-value provenance vocabulary is left intact.
  ///
  /// Null for an ordinary parsed transaction.
  TextColumn get provenanceDetail => text().nullable()();

  /// FK to `raw_message.id`, so the user can open a transaction and read the
  /// message it came from to verify the parse (AC-B1.2).
  IntColumn get sourceMessageId => integer().nullable()();

  /// Which pack, version and rule produced this row. A rule change never
  /// rewrites history (ADR-007 "Provenance"); these three columns are what
  /// make it possible to tell later which parse produced which number.
  TextColumn get rulePackId => text().nullable()();
  TextColumn get rulePackVersion => text().nullable()();
  TextColumn get ruleId => text().nullable()();

  // --- P2: the dedup outcome (ADR-017) -------------------------------------

  /// Set by ADR-017's D3 heuristic tier and by any other "we are not sure"
  /// signal. Surfaced in the Needs Review inbox (design.md S-18).
  BoolColumn get needsReview => boolean().withDefault(const Constant(false))();

  /// A machine-readable reason, e.g. `possible_duplicate`. Never free text.
  TextColumn get reviewReason => text().nullable()();

  /// The transaction this one *might* duplicate.
  ///
  /// **Both rows stay in the list and in the totals until the user decides**
  /// (ADR-017 D3). The bias is deliberate and asymmetric: an inflated total
  /// is visible and correctable; a silently deleted real transaction is
  /// invisible and uncorrectable. Banking default — prefer the auditable,
  /// recoverable error.
  IntColumn get possibleDuplicateOfId => integer().nullable()();

  /// Soft delete (US-B8) — hidden from normal lists/totals but retained and
  /// restorable. Only "erase everything" (ADR-011, P8) is a true hard
  /// delete.
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  /// When the soft delete happened. AC-B6.4 requires the change history to
  /// show a deletion "with timestamp and prior values" — the audit entry
  /// carries both, and this column makes the same fact readable from the row
  /// itself (e.g. for the Recently Deleted list's ordering, US-B8).
  DateTimeColumn get deletedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

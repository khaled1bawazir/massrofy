import 'package:drift/drift.dart';

import 'tables/app_settings_table.dart';
import 'tables/audit_entry_table.dart';
import 'tables/bank_table.dart';
import 'tables/category_table.dart';
import 'tables/ingest_watermark_table.dart';
import 'tables/instrument_table.dart';
import 'tables/merchant_table.dart';
import 'tables/raw_message_table.dart';
import 'tables/transaction_table.dart';

part 'app_database.g.dart';

/// Massrofy's single, whole-database-encrypted (ADR-003) local datastore.
///
/// For readers new to Drift: this class is mostly generated. The
/// `@DriftDatabase` annotation below, plus `part 'app_database.g.dart';`,
/// tells `build_runner` (via `drift_dev`) to generate a base class
/// `_$AppDatabase` containing typed table accessors (`auditEntries`,
/// `rawMessages`, ...), `Companion` classes for inserts/updates, and query
/// building helpers. You never edit the generated file by hand — run
/// `dart run build_runner build` after changing a table or this class.
///
/// **Note on DAOs (`lib/data/dao/`):** they are deliberately **not** listed
/// in a `daos: [...]` parameter here. Drift's `daos:` codegen assumes every
/// DAO's constructor takes only the database instance — but
/// `AuditLogDao` needs an `auditChainKey` and `TransactionDao` needs an
/// `AuditLogDao` collaborator (see those files), so this app constructs
/// its DAOs explicitly wherever they're needed (`app_providers.dart` in
/// production, directly in tests) instead of relying on a generated
/// getter that couldn't supply those extra arguments anyway.
@DriftDatabase(
  tables: [
    AuditEntries,
    RawMessages,
    Banks,
    Instruments,
    Transactions,
    AppSettingsTable,
    IngestWatermarks,
    Categories,
    Merchants,
    MerchantAliases,
    MerchantRules,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// [executor] is opened by `lib/data/db/db_connection.dart` in production
  /// (SQLCipher-keyed, pointing at the app's private storage) or directly
  /// by tests (an in-memory or temp-file SQLCipher-keyed connection) — this
  /// class itself has no opinion about *where* its bytes live, only about
  /// the schema and migrations within them.
  AppDatabase(super.executor);

  /// Bump this and add a branch in [migration] whenever a table changes.
  /// ADR-003 requires a forward-migration test from an empty install for
  /// every version — see `test/data/db/app_database_encryption_test.dart`.
  ///
  /// | Version | Phase | Change |
  /// |---|---|---|
  /// | 1 | P1 | audit, raw_message, minimal transactions, settings |
  /// | 2 | P2 | ingest watermark; SMS provenance, FX and dedup columns on transactions; unparsed diagnostics on raw_message |
  /// | 3 | P3a | `bank` + `instrument` tables (KHA-23); instrument FK, counterparty, remaining balance, provenance detail and `deleted_at` on transactions (KHA-25) |
  /// | 4 | P3b-1 | FX rate date/source/pending (KHA-27, KHA-70) and internal-transfer link + state (KHA-29) on transactions |
  /// | 5 | P3b-2 | the mutation surface: `user_edited_fields` (KHA-26) and the merge pair `merged_into_id` / `merged_from_transaction_id` (KHA-64) |
  /// | 6 | — | **deliberately unused.** `docs/build-plan.md` reserved v6 for P3b-3 *if it needed a schema change*; it did not. The number is burned rather than reused so that no two builds can ever disagree about what "v6" contained — a gap in the sequence is free, a collision is not |
  /// | 7 | P4a | the categorization spine (KHA-30, KHA-31): `category`, `merchant`, `merchant_alias`, `merchant_rule` tables; `category_source` / `category_confidence` / `category_rule_id` / `merchant_id` on transactions; the category-delete guard trigger |
  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _installAuditTriggers();
      await _installCategoryGuardTrigger();
      await _seedIngestWatermark();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // Stepwise, never a single "if from < to" catch-all. A user who skips
      // several app versions (entirely normal on a side-loaded build with no
      // update channel — risk R-11) must walk every step in order.
      if (from < 2) {
        await m.createTable(ingestWatermarks);
        await _seedIngestWatermark();

        for (final GeneratedColumn<Object> column in <GeneratedColumn<Object>>[
          transactions.convertedAmountAmount,
          transactions.convertedAmountCurrency,
          transactions.convertedAmountMinor,
          transactions.feeAmountAmount,
          transactions.feeAmountCurrency,
          transactions.feeAmountMinor,
          transactions.fxRate,
          transactions.occurredAt,
          transactions.timeSource,
          transactions.direction,
          transactions.transactionType,
          transactions.affectsSpend,
          transactions.referenceNumber,
          transactions.instrumentKind,
          transactions.instrumentMaskedRef,
          transactions.provenance,
          transactions.sourceMessageId,
          transactions.rulePackId,
          transactions.rulePackVersion,
          transactions.ruleId,
          transactions.needsReview,
          transactions.reviewReason,
          transactions.possibleDuplicateOfId,
        ]) {
          await m.addColumn(transactions, column);
        }

        await m.addColumn(rawMessages, rawMessages.unparsedReason);
        await m.addColumn(rawMessages, rawMessages.unparsedRuleId);
      }

      if (from < 3) {
        // P3a — the domain spine (KHA-23, KHA-25).
        //
        // Order matters and SQLite is unforgiving about it: `instrument`
        // references `bank`, and `transactions.instrument_id` references
        // `instrument`, so the parents must exist before the child that
        // points at them.
        await m.createTable(banks);
        await m.createTable(instruments);

        for (final GeneratedColumn<Object> column in <GeneratedColumn<Object>>[
          transactions.instrumentId,
          transactions.counterpartyName,
          transactions.counterpartyBankName,
          transactions.remainingBalanceAmount,
          transactions.remainingBalanceCurrency,
          transactions.remainingBalanceMinor,
          transactions.provenanceDetail,
          transactions.deletedAt,
        ]) {
          await m.addColumn(transactions, column);
        }
      }

      if (from < 4) {
        // P3b-1 — what a period total *means* (KHA-27, KHA-28, KHA-29,
        // KHA-70).
        //
        // Five columns, no data backfill, and the absence of a backfill is
        // the interesting part:
        //
        //  - `fx_rate_date` / `fx_rate_source` stay NULL on every existing
        //    row. That is the honest value: those rows were written by a
        //    build that never recorded a rate date, so we do not know one.
        //    Deriving `occurredAt` into them retroactively would invent
        //    provenance for figures nobody recorded provenance for — the
        //    opposite of what KHA-70 asked for.
        //  - `conversion_pending` defaults to false, which is right for every
        //    existing row: schema v3's only foreign-currency path came from
        //    the two online-purchase rules, both of which capture the bank's
        //    inline converted amount, so nothing already stored is pending.
        //    A v3 row that somehow lacked both is still handled correctly at
        //    read time, because `BaseCurrencyConverter` decides from the data
        //    it finds rather than from this flag.
        //  - `internal_transfer_*` stay NULL, meaning "nobody has ruled on
        //    this", which lets the read-time detector classify historic
        //    transfers on the same evidence as new ones. Backfilling a state
        //    here would freeze today's detector output into the database and
        //    make a later improvement unable to correct it.
        for (final GeneratedColumn<Object> column in <GeneratedColumn<Object>>[
          transactions.fxRateDate,
          transactions.fxRateSource,
          transactions.conversionPending,
          transactions.internalTransferGroupId,
          transactions.internalTransferState,
        ]) {
          await m.addColumn(transactions, column);
        }
      }

      if (from < 5) {
        // P3b-2 — the mutation surface (KHA-26, KHA-64).
        //
        // Three nullable columns, no backfill, and NULL is the correct and
        // meaningful value for every pre-existing row: nobody had edited them
        // (`user_edited_fields`), and nothing had been merged
        // (`merged_*_id`). There is no honest non-null value to invent here.
        for (final GeneratedColumn<Object> column in <GeneratedColumn<Object>>[
          transactions.userEditedFields,
          transactions.mergedIntoId,
          transactions.mergedFromTransactionId,
        ]) {
          await m.addColumn(transactions, column);
        }

        // ------------------------------------------------------------------
        // KHA-69 — the audit chain's forward-only fix. DECIDED: option (a).
        // Recorded 2026-07-29; full reasoning in `docs/architecture.md` next
        // to ADR-010, under "KHA-69 decision".
        // ------------------------------------------------------------------
        //
        // P3a fixed `AuditLogDao.append` to hash the *truncated* timestamp it
        // actually stores. That fix is **forward-only**: `verifyChainIntegrity`
        // and `_canonicalize` were not touched, so an entry written by a
        // pre-P3a build would still recompute to a different hash and would
        // still report tampering — permanently, and (because the chain is
        // sequential) poisoning every entry after it.
        //
        // We are deliberately **not** writing a re-chaining migration here,
        // because there is nothing to re-chain. The evidence, which is
        // stronger than "plausible":
        //
        //  - The DB Master Key is provisioned *behind* the app-lock gate
        //    (ADR-005). No unlock means no database, which means no
        //    `audit_entry` table and therefore no audit rows.
        //  - KHA-75 established that the app lock had **never** succeeded on
        //    real hardware — a correct fingerprint and a correct device PIN
        //    both reported "auth failed" because of a Keystore channel
        //    byte-encoding defect.
        //  - The first successful real-device unlock in this app's history
        //    happened on build `56e9cbaa` (confirmed 2026-07-28/29), and that
        //    build **already contains P3a's timestamp fix**.
        //
        // So every audit row that has ever existed on a real device was
        // written by fixed code. A re-chaining migration (option (b)) would
        // rewrite an append-only history to repair rows that do not exist,
        // which is precisely the operation the trail exists to make
        // impossible — a worse trade than the problem it solves.
        //
        // **The standing condition this decision carries:** the P10 staging
        // APK must go onto a *clean install*. If a device is ever found
        // carrying audit rows written before `56e9cbaa`, this decision is void
        // and option (c) — a genesis marker, so verification reports "verified
        // from <date>" rather than "tampered" — becomes the remedy. See
        // `test/data/db/schema_v5_migration_test.dart`, which pins the
        // consequence: a v4 database upgraded to v5 verifies intact.
      }

      if (from < 7) {
        // ------------------------------------------------------------------
        // P4a — the categorization spine (KHA-30, KHA-31).
        // ------------------------------------------------------------------
        //
        // **On the missing v6:** `docs/build-plan.md` reserved schema v6 for
        // P3b-3 in case its merge/undo fixes needed one. They did not, so v6
        // was never written and this branch is `from < 7` rather than
        // `from == 6`. An install can therefore arrive here from v5 (every
        // real install) or from a hypothetical v6 (none exist); both walk the
        // same steps, and skipping the number costs nothing while reusing it
        // would leave two builds disagreeing about what v6 contained.

        // Order matters: `merchant_rule` and `merchant_alias` reference
        // `merchant`, and `transactions.merchant_id` references it too, so the
        // parent must exist before anything that points at it.
        await m.createTable(categories);
        await m.createTable(merchants);
        await m.createTable(merchantAliases);
        await m.createTable(merchantRules);

        for (final GeneratedColumn<Object> column in <GeneratedColumn<Object>>[
          transactions.categorySource,
          transactions.categoryConfidence,
          transactions.categoryRuleId,
          transactions.merchantId,
        ]) {
          await m.addColumn(transactions, column);
        }

        await _installCategoryGuardTrigger();

        // **No backfill, and each absence is the honest value:**
        //
        //  - `category_source` stays NULL on every existing row, meaning "no
        //    categorization decision has ever been recorded here". Writing
        //    `'none'` would be a claim that the app looked at the row and
        //    declined to categorise it, which it never did.
        //  - `merchant_id` stays NULL rather than being derived from
        //    `merchant_raw_text`. Deriving it would run ADR-008's matcher over
        //    historical rows during a migration — an unattended, unauditable
        //    bulk categorization, which is exactly the operation AC-D4.4 says
        //    must write one audit entry per affected transaction and be the
        //    user's choice (P4b's "re-apply to history"). A migration is not
        //    the place to decide where someone's money went.
        //  - The 13 starter categories are **not** seeded here either. Seeding
        //    goes through `CategoryDao.ensureDefaultsSeeded`, which is
        //    idempotent and is called from the composition root once the
        //    database is unlocked — so the seed list has exactly one
        //    implementation shared by fresh installs, upgrades and tests,
        //    instead of one here and one there that can drift apart.
      }
    },
    beforeOpen: (OpeningDetails details) async {
      // ADR-003: enforce referential integrity on every connection, not
      // just at creation time (SQLite defaults foreign_keys OFF per
      // connection unless told otherwise).
      await customStatement('PRAGMA foreign_keys = ON;');
    },
  );

  /// Guarantees the singleton watermark row exists.
  ///
  /// Written as an INSERT OR IGNORE rather than a read-then-write so it is
  /// safe to call from both `onCreate` and `onUpgrade`, and so two concurrent
  /// openings (the UI isolate and the background ingestion isolate can both
  /// open the database — ADR-006) cannot race into two rows. The table's own
  /// CHECK constraint is the second line of defence.
  Future<void> _seedIngestWatermark() async {
    await customStatement(
      'INSERT OR IGNORE INTO ingest_watermark (id) VALUES '
      '($ingestWatermarkSingletonId);',
    );
  }

  /// **AC-C3.3 — "no transaction may be left pointing at a category that no
  /// longer exists"** — enforced at the database, against every code path.
  ///
  /// ## Why a trigger and not the `FK RESTRICT` architecture §4.2 names
  ///
  /// §4.2 says *"deleting a category in use is blocked by `FK RESTRICT`"*.
  /// That would require `transactions.category_id` to carry a `REFERENCES`
  /// clause — and that column has existed since schema v1 without one. SQLite
  /// cannot add a foreign key to an existing column; the only way is to
  /// rebuild the entire `transactions` table (create-copy-drop-rename). This
  /// build declines to do that, and the reason is specific rather than
  /// squeamish: `transactions` is the money table, it carries 50-odd columns,
  /// P3b-2 and P3b-3 have just finished repairing two money-losing defects in
  /// the code that writes it, and a column silently dropped during a rebuild
  /// would be undetectable from the outside until a total came out wrong. The
  /// risk of the mechanism would exceed the risk it removes.
  ///
  /// **This is not a weakening, and the difference is worth being precise
  /// about.** `FK RESTRICT` aborts a `DELETE FROM category` while any row
  /// references it. So does this trigger — for `transactions` *and* for
  /// `merchant_rule`, in one place, with a message that says which. What the
  /// trigger does not do is police *writes* to `transactions.category_id`
  /// (a real FK would reject an insert naming a nonexistent category). That
  /// direction is covered differently and deliberately:
  ///
  ///  - the write paths go through `CategoryDao`/`CategorizationService`,
  ///    which resolve a category before writing it;
  ///  - and a dangling id, if one ever occurred, is **not** a data-loss
  ///    condition — `CategoryResolver` renders any unresolvable id as
  ///    *Uncategorized*, so the transaction stays visible, stays in its
  ///    period total, and stays in the category breakdown (AC-C1.3). The
  ///    figure is never wrong; only the label is.
  ///
  /// The asymmetry is the right way round for a ledger: refuse the operation
  /// that could orphan money, and degrade gracefully on a label.
  ///
  /// Deleting is still possible — `CategoryDao.deleteCategory` reassigns or clears
  /// every referencing row *inside the same transaction*, before the delete
  /// statement runs. The trigger is what makes "the caller must decide first"
  /// a fact rather than a convention (AC-C3.3's "REQUIRES a decision").
  Future<void> _installCategoryGuardTrigger() async {
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS category_no_delete_while_in_use
        BEFORE DELETE ON category
        BEGIN
          SELECT RAISE(ABORT, 'category is still used by transactions')
          WHERE EXISTS (
            SELECT 1 FROM transactions WHERE category_id = OLD.id
          );
          SELECT RAISE(ABORT, 'category is still used by merchant rules')
          WHERE EXISTS (
            SELECT 1 FROM merchant_rule WHERE category_id = OLD.id
          );
          SELECT RAISE(ABORT, 'this category cannot be deleted')
          WHERE OLD.is_protected = 1;
        END;
    ''');
  }

  /// ADR-010 layer 2: SQL triggers that make `audit_entry` append-only
  /// against *any* code path — present or future, including a bug in
  /// `AuditLogDao` itself — not just against the DAO's public API shape.
  Future<void> _installAuditTriggers() async {
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS audit_no_update BEFORE UPDATE ON audit_entry
        BEGIN SELECT RAISE(ABORT, 'audit_entry is append-only'); END;
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS audit_no_delete BEFORE DELETE ON audit_entry
        BEGIN SELECT RAISE(ABORT, 'audit_entry is append-only'); END;
    ''');
  }
}

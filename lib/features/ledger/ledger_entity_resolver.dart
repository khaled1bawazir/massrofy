/// Turns what a message *said* into rows in the bank/instrument tree —
/// KHA-23, US-B12/B13/B14/B15, AC-B12.1, AC-B13.1/2, AC-B14.1, AC-B15.1/2.
///
/// ## What "auto-creation on first mention" actually means here
///
/// US-B15 promises the user never registers an account or card by hand. So
/// this resolver is called on **every** parsed message, and it is idempotent
/// by construction: both DAO entry points are `ensure`-shaped (resolve, then
/// create only if absent), keyed on values that do not change when the user
/// renames things.
///
/// The whole chain for one message is:
///
/// ```
/// rule.bankId ──► BankDao.ensure(canonicalKey)          ─► bank row id
///                                │
/// fields.instrument (kind+mask) ─┴► refKey ─► InstrumentDao.ensure ─► id
///                                                   │
/// fields.settlementInstrument ──────────────────────┴► link (AC-B14.1)
/// ```
///
/// ## Every step can legitimately produce "nothing", and that is not failure
///
/// A message may name no instrument at all (PRD §3.4 records a bare "debited
/// from account" template with almost no detail). The transaction is still
/// recorded, with its instrument explicitly unknown — AC-B1.3. The one thing
/// that must never happen is inventing an instrument to hang it on.
///
/// ## When a bank is created, stated precisely
///
/// This resolver is called from the **transaction** write path only, so a
/// bank appears the first time one of its messages produces a transaction —
/// not when one of its OTPs or marketing messages is recognised and
/// discarded. AC-B12.1's own wording assumes that reading: *"a new bank
/// entity is created … **and the account or card mentioned is placed under
/// it**"*.
///
/// The alternative — creating a bank from any recognised sender — would put
/// a bank in the user's tree because a marketing SMS arrived, with nothing
/// under it and no money at it. An unparsed message from a new bank is not
/// lost either way: it is in the review queue with its sender visible
/// (US-A4), and completing it (KHA-64) produces a transaction like any other.
library;

import '../../data/dao/bank_dao.dart';
import '../../data/dao/instrument_dao.dart';
import '../parsing/parsed_fields.dart';
import 'bank_directory.dart';
import 'instrument_identity.dart';

/// What one message resolved to in the tree. Any field may be null.
final class ResolvedLedgerEntities {
  /// `bank.id`, or null when the bank could not be identified at all.
  final int? bankId;

  /// `instrument.id` for the instrument the movement hit, or null when the
  /// message named none (AC-B1.3).
  final int? instrumentId;

  /// `instrument.id` of the settlement account named by a card-repayment
  /// message (AC-B14.1), or null.
  final int? settlementInstrumentId;

  const ResolvedLedgerEntities({
    this.bankId,
    this.instrumentId,
    this.settlementInstrumentId,
  });

  /// Ids only — safe to log (ADR-015, NFR-S4). There is nothing here that
  /// identifies a card or a person.
  @override
  String toString() =>
      'ResolvedLedgerEntities(bank: $bankId, instrument: $instrumentId, '
      'settlement: $settlementInstrumentId)';
}

final class LedgerEntityResolver {
  final BankDao bankDao;
  final InstrumentDao instrumentDao;

  /// The active packs' view of which banks exist and what they are called.
  /// Supplied rather than read, so this class stays free of any dependency on
  /// the parsing feature's internals (architecture §3).
  final BankDirectory directory;

  const LedgerEntityResolver({
    required this.bankDao,
    required this.instrumentDao,
    required this.directory,
  });

  /// Resolves (creating where needed) the bank and instruments one parsed
  /// message refers to.
  ///
  /// [bankCanonicalKey] is the rule pack's `bankId` for the matched rule —
  /// the sender-derived half of AC-B12.3. [firstSeenMessageId] is the
  /// `raw_message.id` recorded on anything created here (NFR-A1).
  ///
  /// **Must be called from inside the caller's database transaction.** The
  /// ingestion pipeline wraps one message's raw-message row, its ledger rows,
  /// its audit entries and the watermark advance in a single Drift
  /// transaction; entities created here have to be part of that unit or a
  /// crash could leave an instrument with no transaction and no message.
  Future<ResolvedLedgerEntities> resolveForMessage({
    required String bankCanonicalKey,
    required ParsedFields fields,
    int? firstSeenMessageId,
    DateTime? observedAt,
    DateTime? now,
  }) async {
    final int? bankId = await ensureBank(
      canonicalKey: bankCanonicalKey,
      firstSeenMessageId: firstSeenMessageId,
      now: now,
    );
    if (bankId == null) {
      return const ResolvedLedgerEntities();
    }

    final int? instrumentId = await ensureInstrument(
      bankRowId: bankId,
      bankCanonicalKey: bankCanonicalKey,
      reference: fields.instrument,
      currencyCode: fields.amount?.currencyCode,
      firstSeenMessageId: firstSeenMessageId,
      now: now,
    );

    final int? settlementId = await ensureInstrument(
      bankRowId: bankId,
      bankCanonicalKey: bankCanonicalKey,
      reference: fields.settlementInstrument,
      // The settlement account's own currency is not stated by a repayment
      // message; the amount's currency belongs to the repayment, not to the
      // account. Leaving it unknown is the honest reading.
      currencyCode: null,
      firstSeenMessageId: firstSeenMessageId,
      now: now,
    );

    // AC-B14.1: a card-repayment message is the only automatic source of the
    // card → settlement-account link. Both sides must have resolved, and the
    // primary side must actually be a card — a message naming two accounts
    // says nothing about card settlement.
    if (instrumentId != null &&
        settlementId != null &&
        fields.instrument?.kind == InstrumentKind.card &&
        fields.settlementInstrument?.kind == InstrumentKind.account) {
      await instrumentDao.linkSettlementAccount(
        cardId: instrumentId,
        accountId: settlementId,
        linkSource: InstrumentLinkSource.smsRepayment,
        observedAt: observedAt,
        now: now,
      );
    }

    return ResolvedLedgerEntities(
      bankId: bankId,
      instrumentId: instrumentId,
      settlementInstrumentId: settlementId,
    );
  }

  /// Resolve-or-create one bank (AC-B12.1, AC-B15.1).
  ///
  /// Display names come from the active pack where it still declares this
  /// bank; where it does not (an imported pack replaced it), the canonical
  /// key itself is used as a placeholder name rather than refusing to create
  /// the bank — losing a transaction because a pack was swapped would be a
  /// far worse outcome than an ugly label (NFR-A7).
  Future<int?> ensureBank({
    required String canonicalKey,
    int? firstSeenMessageId,
    DateTime? now,
  }) async {
    if (canonicalKey.isEmpty) {
      return null;
    }
    final BankProfile? profile = directory.byCanonicalKey(canonicalKey);
    return bankDao.ensure(
      canonicalKey: canonicalKey,
      displayNameAr: profile?.displayNameAr ?? canonicalKey,
      displayNameEn: profile?.displayNameEn ?? canonicalKey,
      aliases: profile?.aliases ?? const <String>[],
      firstSeenMessageId: firstSeenMessageId,
      now: now,
    );
  }

  /// Resolve-or-create one instrument from what the message stated.
  ///
  /// Returns null — meaning "explicitly unknown", AC-B1.3 — when there is no
  /// reference, when the rule declared a kind this app does not know, or when
  /// the masked identifier carries no digits to key on.
  Future<int?> ensureInstrument({
    required int bankRowId,
    required String bankCanonicalKey,
    required InstrumentReference? reference,
    String? currencyCode,
    int? firstSeenMessageId,
    DateTime? now,
  }) async {
    if (reference == null) {
      return null;
    }
    final String? refKey = buildInstrumentRefKey(
      bankCanonicalKey: bankCanonicalKey,
      kind: reference.kind,
      maskedIdentifier: reference.maskedIdentifier,
    );
    if (refKey == null) {
      return null;
    }

    return instrumentDao.ensure(
      bankId: bankRowId,
      // AC-B13.1/2: straight from the rule's declared kind. There is no
      // inference from digit count anywhere in this file, and adding one
      // would break the case PRD §3.4 documents — the same bank printing
      // both forms depending on transaction type.
      kind: reference.kind,
      maskedIdentifier: reference.maskedIdentifier,
      refKey: refKey,
      network: reference.network,
      cardType: reference.cardType,
      currencyCode: currencyCode,
      firstSeenMessageId: firstSeenMessageId,
      now: now,
    );
  }
}

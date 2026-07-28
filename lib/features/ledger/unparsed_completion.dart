/// **S-19 — completing an unparsed SMS into a real transaction.**
/// KHA-64 (first half), US-A4, AC-A4.2, AC-B4.2, NFR-A1, NFR-A2.
///
/// ## What was actually missing before this file
///
/// P2 shipped the review queue and, honestly, said so in PR #2: *"S-19 …
/// and the duplicate-merge action are **callbacks, not implementations**.
/// Both write a full `Transaction`, which needs the P3 domain model."* The
/// queue genuinely worked — nothing was silently dropped — but AC-A4.2's
/// *"the user fills in the missing fields … a normal transaction is created
/// and the item leaves the review list"* had nothing behind it. This is that
/// implementation.
///
/// ## The three properties this service exists to guarantee
///
/// 1. **Provenance survives** (NFR-A1). The result is `provenance: sms` with
///    its `sourceMessageId` intact, refined by `provenanceDetail:
///    manual_completion`. Recording it as a plain manual entry would discard
///    the link to a message that genuinely exists, and AC-B1.2 would then
///    have no original text to show.
/// 2. **One unit of work.** The transaction row, its audit entry and the
///    raw message's reclassification commit together. A half-applied
///    completion would either leave a transaction whose message is still in
///    the queue (the user sees it twice) or empty the queue with nothing to
///    show for it (the user loses the message) — the second being the
///    NFR-A7 failure the queue exists to prevent.
/// 3. **Validation names the field** (AC-B4.2: *"saving is blocked with a
///    specific message naming the missing field"*). The result type carries
///    the missing field names, so the form can point at them instead of
///    saying "invalid input".
///
/// ## Scope note — the other half of KHA-64 is not here
///
/// KHA-64 also covers **ADR-017 D2's enrichment merge** (merging two partial
/// transactions into one). That is deliberately **not** in this PR: it is a
/// mutation over the multi-currency, refund and soft-delete behaviour that
/// KHA-26/27/28 introduce in P3b, and it is the single highest-risk operation
/// in P3 (build-plan §P3 — *"the only place in the entire product where two
/// records become one"*). P3b implements it on top of the model this PR
/// lands. Until then P2's behaviour stands unchanged: the pair is **flagged**,
/// both rows remain, and `DuplicateAction` still has no `delete` case — the
/// safe direction to be incomplete in (risk R-8).
library;

import '../../core/money/money.dart';
import '../../data/dao/raw_message_dao.dart';
import '../../data/dao/transaction_dao.dart';
import '../../data/db/app_database.dart';

/// The field names the S-19 form can report as missing. Constants rather than
/// free text, because the UI maps them to localised labels — an English
/// string baked in here would be untranslatable in an Arabic-first app.
abstract final class CompletionField {
  static const String amount = 'amount';
  static const String currency = 'currency';
  static const String occurredAt = 'occurredAt';
  static const String transactionType = 'transactionType';
}

/// What the user typed into S-19. Every field is what a person stated; none
/// of it is inferred.
final class UnparsedCompletionDraft {
  /// The review-queue item being completed (`raw_message.id`).
  final int rawMessageId;

  /// Exact decimal text, as typed. Deliberately **not** parsed by the widget:
  /// parsing happens once, here, through [Money.tryParse], so there is one
  /// place that decides what a valid amount is (and it accepts Arabic-Indic
  /// digits, which a hand-rolled check in a form would not).
  final String amountText;

  /// ISO 4217 code. Defaulted by the form to the app's base currency, but
  /// still explicit in the data — NFR-A5 allows no amount without one.
  final String currencyCode;

  final DateTime? occurredAt;

  /// One of the ledger's transaction types, e.g. `pos_purchase`.
  final String? transactionType;

  /// `debit` | `credit`. A refund the parser missed is still a refund
  /// (US-B7), so the form offers both and does not assume debit.
  final String direction;

  /// Whether this counts toward spend. Derived by the form from the chosen
  /// type (a transfer between the user's own accounts does not — US-B11) and
  /// carried explicitly so the rule is visible rather than re-derived here.
  final bool affectsSpend;

  final String? merchantRawText;

  /// The instrument the user picked from their existing accounts/cards, or
  /// null for "not stated". **The form never creates an instrument**: an
  /// instrument invented from a message the parser could not read would be
  /// keyed on nothing reliable, and the next real message from that card
  /// would not match it. Auto-creation stays with the parser, where the
  /// identifier came from the bank.
  final int? instrumentId;

  final String? referenceNumber;

  const UnparsedCompletionDraft({
    required this.rawMessageId,
    required this.amountText,
    required this.currencyCode,
    this.occurredAt,
    this.transactionType,
    this.direction = 'debit',
    this.affectsSpend = true,
    this.merchantRawText,
    this.instrumentId,
    this.referenceNumber,
  });

  /// No amount, no merchant (NFR-S4).
  @override
  String toString() => 'UnparsedCompletionDraft(message #$rawMessageId)';
}

/// The outcome of a completion attempt.
sealed class CompletionResult {
  const CompletionResult();
}

/// A transaction was created and the message left the queue.
final class CompletionAccepted extends CompletionResult {
  final int transactionId;
  const CompletionAccepted(this.transactionId);
}

/// Nothing was written. [missingFields] holds [CompletionField] constants, so
/// the form can highlight each one by name (AC-B4.2).
final class CompletionRejected extends CompletionResult {
  final List<String> missingFields;
  const CompletionRejected(this.missingFields);
}

/// The message id did not resolve to a queued, undismissed message.
///
/// Its own case rather than an exception: it is reachable without any bug —
/// two windows open on the same queue, or a background sweep reclassifying
/// the message between the form opening and the user pressing Save. The UI
/// says "this item is no longer in the queue" instead of crashing.
final class CompletionMessageUnavailable extends CompletionResult {
  const CompletionMessageUnavailable();
}

final class UnparsedCompletionService {
  final AppDatabase database;
  final TransactionDao transactionDao;
  final RawMessageDao rawMessageDao;

  const UnparsedCompletionService({
    required this.database,
    required this.transactionDao,
    required this.rawMessageDao,
  });

  /// Validates [draft], and on success writes the transaction and removes the
  /// message from the queue — atomically.
  Future<CompletionResult> complete(
    UnparsedCompletionDraft draft, {
    DateTime? now,
  }) async {
    final Money? amount = Money.tryParse(
      draft.amountText,
      currency: draft.currencyCode,
    );

    final List<String> missing = <String>[
      // A zero amount is *valid* here and is not treated as missing: KHA-25
      // is explicit that zero and unknown are different facts, and a bank can
      // genuinely post a zero-value authorisation.
      if (amount == null)
        draft.amountText.trim().isEmpty
            ? CompletionField.amount
            : CompletionField.currency,
      if (draft.occurredAt == null) CompletionField.occurredAt,
      if ((draft.transactionType ?? '').trim().isEmpty)
        CompletionField.transactionType,
    ];
    if (missing.isNotEmpty) {
      return CompletionRejected(missing);
    }

    return database.transaction<CompletionResult>(() async {
      final RawMessageRow? message = await rawMessageDao.byId(
        draft.rawMessageId,
      );
      if (message == null ||
          message.classification != 'financial_unparsed' ||
          message.dismissedAsNotTransaction) {
        return const CompletionMessageUnavailable();
      }

      final int transactionId = await transactionDao.insertManualCompletion(
        amount: amount!,
        merchantRawText: _blankToNull(draft.merchantRawText),
        occurredAt: draft.occurredAt!,
        direction: draft.direction,
        transactionType: draft.transactionType!,
        affectsSpend: draft.affectsSpend,
        instrumentId: draft.instrumentId,
        referenceNumber: _blankToNull(draft.referenceNumber),
        sourceMessageId: draft.rawMessageId,
        now: now,
      );

      await rawMessageDao.markCompletedIntoTransaction(draft.rawMessageId);

      return CompletionAccepted(transactionId);
    });
  }

  /// An empty text field means "the user did not state this", which is
  /// AC-B1.3's unknown — not an empty-string value that would render as a
  /// blank row indistinguishable from a merchant literally called "".
  static String? _blankToNull(String? value) {
    final String trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

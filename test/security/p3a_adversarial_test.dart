/// **QA adversarial pass over the P3a domain spine (PR #11 — KHA-23, KHA-25,
/// KHA-64 first half).**
///
/// These tests do not re-state what the implementation's own tests assert.
/// They *attack* the feature, on the banking-domain rule that a successful
/// attack is a high-severity defect and an unsuccessful one is audit evidence
/// that the attack was attempted:
///
///  - **Injection** through every string a message or a user controls
///    (instrument friendly name, bank display name, merchant text, currency
///    code, masked identifier).
///  - **Identity forging** — can a crafted masked identifier make one bank's
///    card resolve to another bank's instrument (`refKey` is a `:`-joined
///    string, so this is the obvious attack on it).
///  - **Double-spend analogues** — concurrent completion of the same queued
///    message, i.e. the money-duplication race the sequential test in
///    `unparsed_completion_test.dart` cannot reach.
///  - **Mass assignment / referential integrity** — a completion draft naming
///    an instrument id that does not exist, or one belonging to another bank.
///  - **Money math** — 3-decimal currencies, negative input, cross-currency
///    blending, and the exactness AC-B1.4 requires.
///  - **Audit-trail tampering** — specifically on `changedAt`, the column the
///    P1 hash-chain defect this PR fixes was mis-hashing.
///
/// Threat model, stated honestly: Massrofy is a single-user, offline,
/// no-network Android app (ADR-001), so there is no cross-tenant authorization
/// boundary to bypass and no remote attacker. The realistic adversary is
/// (a) a malicious or malformed **SMS** — attacker-controlled text that
/// reaches storage, and (b) the device owner or another process editing the
/// database directly on a rooted device, which ADR-010 answers with
/// tamper-*evidence*. Both are exercised below.
library;

import 'package:drift/drift.dart' show QueryRow;
import 'package:flutter_test/flutter_test.dart';
import 'package:massrofy/core/money/money.dart';
import 'package:massrofy/core/text/sms_sanitizer.dart';
import 'package:massrofy/data/dao/audit_log_dao.dart';
import 'package:massrofy/data/dao/bank_dao.dart';
import 'package:massrofy/data/dao/instrument_dao.dart';
import 'package:massrofy/data/dao/raw_message_dao.dart';
import 'package:massrofy/data/dao/transaction_dao.dart';
import 'package:massrofy/data/db/app_database.dart';
import 'package:massrofy/features/ledger/instrument_identity.dart';
import 'package:massrofy/features/ledger/ledger_mapping.dart';
import 'package:massrofy/features/ledger/ledger_transaction.dart';
import 'package:massrofy/features/ledger/period_totals.dart';
import 'package:massrofy/features/ledger/unparsed_completion.dart';

import '../support/plain_test_database.dart';

final List<int> _qaChainKey = List<int>.generate(32, (int i) => i + 11);

/// Payloads that would end a statement, drop a table, or smuggle a second
/// statement if any of these values were ever concatenated into SQL.
const List<String> _injectionPayloads = <String>[
  "'; DROP TABLE instrument;--",
  "' OR '1'='1",
  '" OR 1=1 --',
  "Robert'); DROP TABLE transactions;--",
  "'||(SELECT amount_amount FROM transactions)||'",
  "x'; DELETE FROM bank; --",
  // A raw NUL, written as an escape: a value that truncates a C string is the
  // classic way past a naive length/format check. `source_hygiene_test.dart`
  // forbids the literal byte in source, which is why this is the escape form.
  'end\x00; DROP TABLE bank;--',
];

void main() {
  late AppDatabase db;
  late AuditLogDao auditLogDao;
  late BankDao bankDao;
  late InstrumentDao instrumentDao;
  late RawMessageDao rawMessageDao;
  late TransactionDao transactionDao;
  late UnparsedCompletionService completionService;

  setUp(() {
    db = openPlainTestDatabase();
    auditLogDao = AuditLogDao(db, auditChainKey: _qaChainKey);
    bankDao = BankDao(db, auditLogDao);
    instrumentDao = InstrumentDao(db, auditLogDao);
    rawMessageDao = RawMessageDao(db);
    transactionDao = TransactionDao(db, auditLogDao);
    completionService = UnparsedCompletionService(
      database: db,
      transactionDao: transactionDao,
      rawMessageDao: rawMessageDao,
    );
  });

  tearDown(() async => db.close());

  Future<int> ensureBank() => bankDao.ensure(
    canonicalKey: 'bank-aljazira',
    displayNameAr: 'بنك الجزيرة',
    displayNameEn: 'Bank Aljazira',
  );

  Future<int> ensureCard(int bankId) => instrumentDao.ensure(
    bankId: bankId,
    kind: InstrumentKind.card,
    maskedIdentifier: '****4821',
    refKey: 'bank-aljazira:card:4821',
  );

  Future<int> queueUnparsed({String hmac = 'hmac-qa-1'}) =>
      rawMessageDao.insert(
        // Unique per message: `raw_message.sms_provider_id` is UNIQUE (ADR-017
        // D1), which is itself part of what stops a re-delivered SMS becoming
        // a second transaction.
        smsProviderId: 'provider-$hmac',
        sender: 'BAJ',
        receivedAt: DateTime.utc(2026, 7, 20, 9),
        sanitizedText: SmsSanitizer.sanitize('خصم من حسابك'),
        contentHmac: hmac,
        bankId: 'bank-aljazira',
        classification: 'financial_unparsed',
        unparsedReason: 'required_field_missing',
      );

  Future<List<String>> tableNames() async {
    final List<QueryRow> rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    return rows.map((QueryRow r) => r.data['name'] as String).toList();
  }

  // ---------------------------------------------------------------------
  // ATTACK 1 — SQL injection through every attacker-reachable string
  // ---------------------------------------------------------------------
  group('ATTACK — SQL injection through user- and SMS-controlled strings', () {
    test('an injection payload as an instrument friendly name is stored as '
        'literal text; no table is dropped and no extra row appears', () async {
      final int bankId = await ensureBank();
      final int cardId = await ensureCard(bankId);

      for (final String payload in _injectionPayloads) {
        await instrumentDao.rename(id: cardId, newName: payload);

        // Stored verbatim — proof it was bound as a parameter, not spliced
        // into SQL (where it would either have executed or been mangled).
        expect((await instrumentDao.byId(cardId)).friendlyName, payload);
        // And the schema survived every one of them.
        expect(await tableNames(), containsAll(<String>['instrument', 'bank']));
        expect((await instrumentDao.all()).length, 1);
      }

      // The audit chain is intact after all of it — an injection that had
      // partially executed would almost certainly have disturbed it.
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });

    test('an injection payload as a bank display name creates exactly one '
        'bank and leaves the schema intact', () async {
      for (int i = 0; i < _injectionPayloads.length; i++) {
        await bankDao.ensure(
          canonicalKey: 'bank-$i',
          displayNameAr: _injectionPayloads[i],
          displayNameEn: _injectionPayloads[i],
        );
      }

      expect((await bankDao.all()).length, _injectionPayloads.length);
      expect(
        (await bankDao.byCanonicalKey('bank-0'))!.displayNameEn,
        _injectionPayloads[0],
      );
      expect(await tableNames(), containsAll(<String>['instrument', 'bank']));
    });

    test('an injection payload typed as the merchant on S-19 is stored as '
        'text and the ledger survives', () async {
      final int messageId = await queueUnparsed();
      final CompletionResult result = await completionService.complete(
        UnparsedCompletionDraft(
          rawMessageId: messageId,
          amountText: '75.50',
          currencyCode: 'SAR',
          occurredAt: DateTime.utc(2026, 7, 20, 9),
          transactionType: 'account_debit',
          merchantRawText: "Panda'); DROP TABLE transactions;--",
        ),
      );

      expect(result, isA<CompletionAccepted>());
      expect(
        (await transactionDao.all()).single.merchantRawText,
        "Panda'); DROP TABLE transactions;--",
      );
      expect(await tableNames(), contains('transactions'));
    });

    test('a hostile currency code is rejected as a value, not executed as '
        'SQL', () async {
      final int messageId = await queueUnparsed();
      final CompletionResult result = await completionService.complete(
        UnparsedCompletionDraft(
          rawMessageId: messageId,
          amountText: '75.50',
          currencyCode: "SAR'; DROP TABLE transactions;--",
          occurredAt: DateTime.utc(2026, 7, 20, 9),
          transactionType: 'account_debit',
        ),
      );

      // Money.tryParse refuses the currency, so the service rejects the draft
      // — nothing reaches storage at all.
      expect(result, isA<CompletionRejected>());
      expect(await transactionDao.all(), isEmpty);
      expect(await tableNames(), contains('transactions'));
    });
  });

  // ---------------------------------------------------------------------
  // ATTACK 2 — forging instrument identity through the masked identifier
  // ---------------------------------------------------------------------
  group('ATTACK — forging a refKey through the masked identifier', () {
    test('a masked identifier containing the key separator cannot make one '
        "bank's message resolve to another bank's instrument", () {
      // `refKey` is `<bank>:<kind>:<digits>`. If the masked identifier were
      // pasted in unfiltered, a hostile SMS printing
      // "0000:account:1111" could aim at a key it does not own.
      final String? forged = buildInstrumentRefKey(
        bankCanonicalKey: 'bank-attacker',
        kind: InstrumentKind.card,
        maskedIdentifier: 'bank-victim:card:4821',
      );

      expect(forged, 'bank-attacker:card:4821');
      expect(
        forged,
        isNot(contains('bank-victim')),
        reason: 'non-digits are stripped, so no separator can be smuggled in',
      );
    });

    test('an unknown instrument kind produces no key at all rather than a '
        'mystery instrument', () {
      expect(
        buildInstrumentRefKey(
          bankCanonicalKey: 'bank-aljazira',
          kind: 'crypto_wallet',
          maskedIdentifier: '****4821',
        ),
        isNull,
      );
    });

    test('the same four digits at two banks stay two instruments', () async {
      final int a = await bankDao.ensure(
        canonicalKey: 'bank-a',
        displayNameAr: 'أ',
        displayNameEn: 'A',
      );
      final int b = await bankDao.ensure(
        canonicalKey: 'bank-b',
        displayNameAr: 'ب',
        displayNameEn: 'B',
      );

      final int cardA = await instrumentDao.ensure(
        bankId: a,
        kind: InstrumentKind.card,
        maskedIdentifier: '****4821',
        refKey: 'bank-a:card:4821',
      );
      final int cardB = await instrumentDao.ensure(
        bankId: b,
        kind: InstrumentKind.card,
        maskedIdentifier: '****4821',
        refKey: 'bank-b:card:4821',
      );

      expect(cardA, isNot(cardB));
      expect((await instrumentDao.forBank(a)).length, 1);
      expect((await instrumentDao.forBank(b)).length, 1);
    });
  });

  // ---------------------------------------------------------------------
  // ATTACK 3 — double-spend analogue: racing two completions
  // ---------------------------------------------------------------------
  group('ATTACK — concurrent completion of one queued message', () {
    test('two simultaneous completions of the same message produce exactly '
        'one transaction', () async {
      final int messageId = await queueUnparsed();
      UnparsedCompletionDraft draft() => UnparsedCompletionDraft(
        rawMessageId: messageId,
        amountText: '500.00',
        currencyCode: 'SAR',
        occurredAt: DateTime.utc(2026, 7, 20, 9),
        transactionType: 'account_debit',
      );

      // Both futures are started before either is awaited — the check
      // ("is this message still queued?") and the write are in separate
      // statements, so if they were not inside one serialised database
      // transaction, both could pass the check and both could write.
      final List<CompletionResult> results = await Future.wait(
        <Future<CompletionResult>>[
          completionService.complete(draft()),
          completionService.complete(draft()),
        ],
      );

      expect(
        (await transactionDao.all()).length,
        1,
        reason:
            'a race that double-counts the user\'s money is a HIGH '
            'severity defect in a banking app',
      );
      expect(results.whereType<CompletionAccepted>().length, 1);
      expect(results.whereType<CompletionMessageUnavailable>().length, 1);
      expect(await rawMessageDao.watchReviewQueue().first, isEmpty);
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });
  });

  // ---------------------------------------------------------------------
  // ATTACK 4 — mass assignment / referential integrity on the S-19 draft
  // ---------------------------------------------------------------------
  group('ATTACK — a completion draft naming an instrument it should not', () {
    test('an instrument id that does not exist cannot create an orphaned '
        'transaction, and nothing is half-written', () async {
      final int messageId = await queueUnparsed();

      Object? thrown;
      try {
        await completionService.complete(
          const UnparsedCompletionDraft(
            rawMessageId: 0, // replaced below
            amountText: '1.00',
            currencyCode: 'SAR',
          ).copyWithForTest(
            rawMessageId: messageId,
            occurredAt: DateTime.utc(2026, 7, 20, 9),
            transactionType: 'account_debit',
            instrumentId: 9999,
          ),
        );
      } catch (error) {
        thrown = error;
      }

      // Either outcome is acceptable *provided* no orphan row exists: SQLite's
      // foreign key rejects the insert (PRAGMA foreign_keys = ON), and the
      // service's single transaction rolls the whole unit back.
      expect(
        await transactionDao.all(),
        isEmpty,
        reason:
            'a transaction pointing at a non-existent instrument would '
            'break the bank tree AC-B2.1 rests on',
      );
      expect(
        await rawMessageDao.watchReviewQueue().first,
        hasLength(1),
        reason:
            'atomicity — a failed write must leave the message in the '
            'queue rather than losing it (NFR-A7)',
      );
      expect(thrown, isNotNull);
    });
  });

  // ---------------------------------------------------------------------
  // ATTACK 5 — money math
  // ---------------------------------------------------------------------
  group('ATTACK — money math edge cases', () {
    Future<int> completeWith({
      required String amount,
      required String currency,
      String direction = 'debit',
      String hmac = 'hmac-money',
    }) async {
      final int messageId = await queueUnparsed(hmac: hmac);
      final CompletionResult result = await completionService.complete(
        UnparsedCompletionDraft(
          rawMessageId: messageId,
          amountText: amount,
          currencyCode: currency,
          occurredAt: DateTime.utc(2026, 7, 20, 9),
          transactionType: 'account_debit',
          direction: direction,
        ),
      );
      return (result as CompletionAccepted).transactionId;
    }

    test('a 3-decimal currency keeps all three decimals through storage '
        '(AC-B1.4)', () async {
      await completeWith(amount: '12.345', currency: 'KWD');
      final TransactionRow row = (await transactionDao.all()).single;

      expect(row.amountAmount, '12.345');
      expect(row.amountCurrency, 'KWD');
      // The non-authoritative _minor column must reflect KWD's exponent of 3,
      // not a hard-coded 2 — a 2 here would be a 10x error.
      expect(row.amountMinor, 12345);
    });

    test('a total is never blended across currencies (ADR-009)', () async {
      await completeWith(amount: '100.00', currency: 'SAR', hmac: 'h1');
      await completeWith(amount: '50.00', currency: 'USD', hmac: 'h2');

      final PeriodTotals totals = LedgerTotals.spend(
        toLedgerTransactions(await transactionDao.all()),
        period: PeriodRange.unbounded(),
      );

      expect(totals.byCurrency.length, 2);
      expect(totals.forCurrency('SAR')!.toCanonicalString(), '100');
      expect(totals.forCurrency('USD')!.toCanonicalString(), '50');
      // There is no single blended figure to read, by construction.
      expect(totals.forCurrency('EUR'), isNull);
    });

    test('summing a bucket that somehow contained a foreign currency throws '
        'rather than silently producing a wrong number', () {
      expect(
        () => Money.sum(<Money>[
          Money.parse('10.00', currency: 'SAR'),
          Money.parse('10.00', currency: 'USD'),
        ], currency: 'SAR'),
        throwsA(anything),
      );
    });

    test('a refund subtracts from spend and can drive a period negative, '
        'which must not be clamped', () async {
      await completeWith(amount: '40.00', currency: 'SAR', hmac: 'h3');
      await completeWith(
        amount: '100.00',
        currency: 'SAR',
        direction: 'credit',
        hmac: 'h4',
      );

      final PeriodTotals totals = LedgerTotals.spend(
        toLedgerTransactions(await transactionDao.all()),
        period: PeriodRange.unbounded(),
      );
      expect(totals.forCurrency('SAR')!.toCanonicalString(), '-60');
    });

    test('repeated small amounts sum exactly — no binary-float drift', () {
      final List<Money> tenths = List<Money>.generate(
        10,
        (_) => Money.parse('0.1', currency: 'SAR'),
      );
      expect(
        Money.sum(tenths, currency: 'SAR').toCanonicalString(),
        '1',
        reason:
            '0.1 summed ten times is exactly 1 in decimal arithmetic; a '
            'double would give 0.9999999999999999. (The canonical form drops '
            'the trailing zero; display padding to the currency exponent is '
            'a separate, presentation-only step — formatAmountDigits.)',
      );
    });

    test(
      'a NEGATIVE amount typed on S-19 is accepted and inverts the sign '
      'of the movement — recorded as an observation, not an exploit',
      () async {
        // The direction control already expresses debit vs credit, so a typed
        // "-50" is a second, redundant way to say "credit". It is only
        // self-inflicted (single-user, offline app) but it means two different
        // inputs produce the same ledger effect.
        final int id = await completeWith(amount: '-50.00', currency: 'SAR');
        final TransactionRow row = await transactionDao.byId(id);

        expect(row.amountAmount, '-50');
        expect(row.direction, 'debit');

        final PeriodTotals totals = LedgerTotals.spend(
          toLedgerTransactions(await transactionDao.all()),
          period: PeriodRange.unbounded(),
        );
        expect(
          totals.forCurrency('SAR')!.toCanonicalString(),
          '-50',
          reason:
              'a debit of a negative amount reduces spend — see the QA note '
              'in docs/test-plan.md §Epic B observations',
        );
      },
    );
  });

  // ---------------------------------------------------------------------
  // ATTACK 6 — the audit trail
  // ---------------------------------------------------------------------
  group('ATTACK — tampering with the audit trail', () {
    test('editing a stored changedAt outside the app is detected (the exact '
        'column the P1 hash-chain defect mis-hashed)', () async {
      final int bankId = await ensureBank();
      await ensureCard(bankId);
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);

      // A raw edit, as a database editor on a rooted device would make. The
      // BEFORE UPDATE trigger guards `audit_entry`, so this is done with the
      // trigger dropped — i.e. the strongest attacker ADR-010 contemplates,
      // and the case where only the hash chain can still tell the truth.
      await db.customStatement('DROP TRIGGER IF EXISTS audit_no_update;');
      await db.customStatement(
        'UPDATE audit_entry SET changed_at = changed_at + 60 WHERE id = 1;',
      );

      expect(
        await auditLogDao.verifyChainIntegrity(),
        isFalse,
        reason:
            'a back-dated audit entry must be detectable, which is the '
            'whole point of hashing changedAt',
      );
    });

    test('every P3a mutation leaves an audit entry — a scripted sequence '
        'produces exactly the expected count and the chain verifies', () async {
      final int bankId = await ensureBank(); // 1 create
      final int cardId = await ensureCard(bankId); // 2 create
      final int accountId = await instrumentDao.ensure(
        // 3 create
        bankId: bankId,
        kind: InstrumentKind.account,
        maskedIdentifier: '****3388',
        refKey: 'bank-aljazira:account:3388',
      );
      await instrumentDao.ensure(
        // 4 enrich (network newly stated)
        bankId: bankId,
        kind: InstrumentKind.card,
        maskedIdentifier: '****4821',
        refKey: 'bank-aljazira:card:4821',
        network: 'mada',
      );
      await instrumentDao.rename(id: cardId, newName: 'Blue'); // 5
      await instrumentDao.linkSettlementAccount(
        // 6
        cardId: cardId,
        accountId: accountId,
        linkSource: InstrumentLinkSource.smsRepayment,
      );

      final List<QueryRow> rows = await db
          .customSelect('SELECT COUNT(*) AS n FROM audit_entry')
          .get();
      expect(rows.single.data['n'], 6);
      expect(await auditLogDao.verifyChainIntegrity(), isTrue);
    });
  });

  // ---------------------------------------------------------------------
  // ATTACK 7 — can a corrupted row make money vanish from a total silently?
  // ---------------------------------------------------------------------
  group('ATTACK — a corrupted amount column', () {
    test('a row whose amount cannot be parsed is dropped from the ledger '
        'view with no signal — recorded as a QA observation', () async {
      final int messageId = await queueUnparsed();
      await completionService.complete(
        UnparsedCompletionDraft(
          rawMessageId: messageId,
          amountText: '100.00',
          currencyCode: 'SAR',
          occurredAt: DateTime.utc(2026, 7, 20, 9),
          transactionType: 'account_debit',
        ),
      );

      await db.customStatement(
        "UPDATE transactions SET amount_amount = 'not-a-number';",
      );

      final List<LedgerTransaction> mapped = toLedgerTransactions(
        await transactionDao.all(),
      );

      // Documented behaviour of `toLedgerTransactionOrNull`. The row is still
      // in the database (nothing is destroyed), but it is invisible in every
      // list and every total, and nothing tells the user. Only reachable by
      // editing the database outside the app, since the write path only ever
      // stores `Money.toCanonicalString()`.
      expect(mapped, isEmpty);
      expect((await transactionDao.all()).length, 1);
    });
  });
}

/// A tiny test-only helper so the mass-assignment case can build a draft with
/// one field replaced without repeating every argument.
extension on UnparsedCompletionDraft {
  UnparsedCompletionDraft copyWithForTest({
    int? rawMessageId,
    DateTime? occurredAt,
    String? transactionType,
    int? instrumentId,
  }) => UnparsedCompletionDraft(
    rawMessageId: rawMessageId ?? this.rawMessageId,
    amountText: amountText,
    currencyCode: currencyCode,
    occurredAt: occurredAt ?? this.occurredAt,
    transactionType: transactionType ?? this.transactionType,
    direction: direction,
    affectsSpend: affectsSpend,
    merchantRawText: merchantRawText,
    instrumentId: instrumentId ?? this.instrumentId,
    referenceNumber: referenceNumber,
  );
}

/// The synthetic SMS regression corpus (NFR-M2, NFR-M3).
///
/// ## Read this before adding anything here
///
/// > **The user's genuine bank SMS must never be committed to a repository,
/// > pasted into any tool, or quoted in an issue, PR or defect report**
/// > (NFR-M3, build-plan §P2, Linear KHA-19).
///
/// Every message below is **fabricated**. The structural shapes — which
/// fields appear for which transaction type, which language each bank writes
/// in, where a converted amount and an FX fee sit, which types carry a
/// reference number — come from the prose descriptions in `docs/PRD.md` §3.4,
/// which itself deliberately reproduces no real text. Every amount, merchant,
/// counterparty, account suffix, reference number and date here was invented
/// for this file.
///
/// The two bank *names* are real, because they are public companies named in
/// the PRD. Nothing else is.
///
/// ## What this corpus is for
///
/// Two jobs, and the second is the one that matters most:
///
/// 1. **Regression.** A rule change that breaks a previously-passing message
///    fails the build (NFR-M2). This is the guard-rail on risk R-4, the
///    highest-variance item on the critical path.
/// 2. **Proving nothing vanishes.** NFR-A7 and AC-A4.4 require that every
///    financial message either parses or lands in the review queue. The
///    corpus test asserts that for **every** fixture, including the ones
///    designed to fail — see `rule_pack_corpus_test.dart`. A fixture that
///    silently disappeared would pass a naive "did the good ones parse?"
///    test and fail this one.
library;

/// What the engine is expected to do with one fixture.
enum ExpectedOutcome {
  /// A transaction, with the fields named in the fixture.
  parsed,

  /// Recognised noise from a known bank: body destroyed, counter row only.
  ignored,

  /// Known bank, could not be turned into a transaction → review queue.
  /// **Not a failure of the corpus — a required behaviour** (US-A4).
  unparsed,

  /// Sender matched no bank: nothing retained at all (NFR-P4).
  notFinancial,
}

/// One corpus entry: an input, and precisely what must come out.
///
/// Expectations are **pinned literals**, never `isNotNull` or
/// `contains(...)`. The P1 review of the SMS sanitiser turned on exactly this
/// distinction: a loose matcher is how a wrong-but-plausible value passes
/// green. If the rule pack starts reporting 1520.00 where 152.00 is correct,
/// this file is what must fail.
final class SmsFixture {
  /// Short stable id used in the test name, so a CI failure names the case.
  final String id;
  final String sender;
  final String body;
  final ExpectedOutcome expect;

  /// Expected `messageType` from the matched rule, for [ExpectedOutcome.parsed]
  /// and [ExpectedOutcome.ignored].
  final String? messageType;

  /// Expected `ruleId`, so a fixture that starts matching a *different* rule
  /// (the classic priority-ordering regression) fails loudly rather than
  /// quietly producing similar-looking output.
  final String? ruleId;

  /// The expected amount as `Money.toCanonicalString()` renders it — i.e.
  /// the **exact decimal value**, with no trailing-zero padding. A message
  /// printing `SAR 1,500.00` is expected here as `1500`, and `412.30` as
  /// `412.3`.
  ///
  /// That is not sloppiness: `Money` is backed by an arbitrary-precision
  /// `Decimal` (ADR-002), for which `1500.00` and `1500` are the same value,
  /// and the canonical form is what gets persisted. Padding to a currency's
  /// minor-unit width is a **presentation** concern (P5), and pinning a
  /// display format in a parser corpus would make the corpus fail the day
  /// the display format changed — for no correctness gain.
  final String? amount;
  final String? currency;

  final String? convertedAmount;
  final String? convertedCurrency;
  final String? feeAmount;
  final String? feeCurrency;
  final String? exchangeRate;
  final String? remainingBalance;

  final String? merchant;

  /// Already in stored form, e.g. `****4821`.
  final String? instrumentMasked;
  final String? instrumentKind;
  final String? instrumentNetwork;
  final String? instrumentCardType;
  final String? settlementMasked;

  /// UTC ISO-8601, e.g. `2026-07-28T11:32:00.000Z`. The fixtures print Riyadh
  /// wall-clock times, so every expectation here is three hours earlier —
  /// which is itself the assertion that the `Asia/Riyadh` interpretation in
  /// `core/time/clock.dart` is actually being applied.
  final String? occurredAtUtc;

  final String? referenceNumber;
  final String? counterpartyName;
  final String? counterpartyBankName;
  final String? billerCode;
  final String? invoiceNumber;

  final String? direction;
  final bool? affectsSpend;

  /// For [ExpectedOutcome.ignored]: the `RawMessage.classification` to store.
  final String? classification;

  const SmsFixture({
    required this.id,
    required this.sender,
    required this.body,
    required this.expect,
    this.messageType,
    this.ruleId,
    this.amount,
    this.currency,
    this.convertedAmount,
    this.convertedCurrency,
    this.feeAmount,
    this.feeCurrency,
    this.exchangeRate,
    this.remainingBalance,
    this.merchant,
    this.instrumentMasked,
    this.instrumentKind,
    this.instrumentNetwork,
    this.instrumentCardType,
    this.settlementMasked,
    this.occurredAtUtc,
    this.referenceNumber,
    this.counterpartyName,
    this.counterpartyBankName,
    this.billerCode,
    this.invoiceNumber,
    this.direction,
    this.affectsSpend,
    this.classification,
  });
}

/// Bank Aljazira — **Arabic** templates with Arabic field labels, per PRD
/// §3.4 ("one bank's messages are fully Arabic with Arabic field labels").
/// Merchant names appear in Latin transliteration even inside the Arabic
/// message, which the PRD calls out explicitly and which the categorisation
/// work in P4 depends on.
///
/// The templates below are written multi-line, as bank SMS genuinely are.
/// The pipeline's normaliser collapses every whitespace run to a single
/// space before any rule sees the text, which is exactly why the rules can
/// be written as one flat pattern — that is normalisation earning its keep.
const List<SmsFixture> aljaziraFixtures = <SmsFixture>[
  // --- 1/9 POS purchase ----------------------------------------------------
  SmsFixture(
    id: 'baj-01-pos-purchase',
    sender: 'BAJ',
    body:
        'شراء\n'
        'بطاقة:مدى-****4821\n'
        'مبلغ:152.75 SAR\n'
        'لدى:EXTRA MART 0042\n'
        'في:28-07-26 14:32',
    expect: ExpectedOutcome.parsed,
    messageType: 'pos_purchase',
    ruleId: 'baj-pos-purchase-ar',
    amount: '152.75',
    currency: 'SAR',
    merchant: 'EXTRA MART 0042',
    instrumentMasked: '****4821',
    instrumentKind: 'card',
    instrumentNetwork: 'مدى',
    occurredAtUtc: '2026-07-28T11:32:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 2/9 Online purchase, foreign currency + inline conversion + FX fee ---
  //
  // PRD §3.4: "some state a foreign currency with an inline SAR-converted
  // amount and an FX/international fee". KHA-19 is explicit that the fee is
  // its OWN field and must not be folded into the spend amount — this
  // fixture is what holds that line.
  SmsFixture(
    id: 'baj-02-online-purchase-fx',
    sender: 'Aljazira',
    body:
        'شراء عبر الإنترنت\n'
        'بطاقة:فيزا-****9013\n'
        'مبلغ:49.99 USD (187.46 SAR)\n'
        'رسوم دولية:4.69 SAR\n'
        'لدى:GLOBAL CLOUD SERVICES\n'
        'في:26-07-26 09:14',
    expect: ExpectedOutcome.parsed,
    messageType: 'online_purchase',
    ruleId: 'baj-online-purchase-ar',
    amount: '49.99',
    currency: 'USD',
    convertedAmount: '187.46',
    convertedCurrency: 'SAR',
    feeAmount: '4.69',
    feeCurrency: 'SAR',
    merchant: 'GLOBAL CLOUD SERVICES',
    instrumentMasked: '****9013',
    instrumentKind: 'card',
    instrumentNetwork: 'فيزا',
    occurredAtUtc: '2026-07-26T06:14:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 3/9 Outgoing transfer (carries a reference number) ------------------
  SmsFixture(
    id: 'baj-03-transfer-out',
    sender: 'BAJ',
    body:
        'حوالة صادرة\n'
        'من حساب:****3388\n'
        'مبلغ:1500.00 SAR\n'
        'إلى:AHMED N ALMUTAIRI\n'
        'بنك:مصرف الراجحي\n'
        'رقم العملية:TRX8842190\n'
        'في:25-07-26 11:05',
    expect: ExpectedOutcome.parsed,
    messageType: 'transfer_out',
    ruleId: 'baj-transfer-out-ar',
    amount: '1500',
    currency: 'SAR',
    instrumentMasked: '****3388',
    instrumentKind: 'account',
    counterpartyName: 'AHMED N ALMUTAIRI',
    counterpartyBankName: 'مصرف الراجحي',
    referenceNumber: 'TRX8842190',
    occurredAtUtc: '2026-07-25T08:05:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 4/9 Incoming transfer (salary) --------------------------------------
  //
  // `affectsSpend: false` and `direction: credit`. US-B10: income is captured
  // so the user can see "spent vs kept", but it is emphatically not spending.
  SmsFixture(
    id: 'baj-04-transfer-in-salary',
    sender: 'BAJ',
    body:
        'حوالة واردة\n'
        'إلى حساب:****3388\n'
        'مبلغ:14500.00 SAR\n'
        'من:ALFA TRADING COMPANY\n'
        'بنك:البنك الأهلي\n'
        'رقم العملية:TRX8850677\n'
        'في:25-07-26 08:00',
    expect: ExpectedOutcome.parsed,
    messageType: 'transfer_in',
    ruleId: 'baj-transfer-in-ar',
    amount: '14500',
    currency: 'SAR',
    instrumentMasked: '****3388',
    instrumentKind: 'account',
    counterpartyName: 'ALFA TRADING COMPANY',
    counterpartyBankName: 'البنك الأهلي',
    referenceNumber: 'TRX8850677',
    occurredAtUtc: '2026-07-25T05:00:00.000Z',
    direction: 'credit',
    affectsSpend: false,
  ),

  // --- 5/9 Bill payment (biller code + invoice number) ---------------------
  SmsFixture(
    id: 'baj-05-bill-payment',
    sender: 'BAJ',
    body:
        'سداد فاتورة\n'
        'من حساب:****3388\n'
        'مبلغ:412.30 SAR\n'
        'المفوتر:SEC-KAHRABA\n'
        'رقم الفاتورة:INV77120934\n'
        'في:24-07-26 19:41',
    expect: ExpectedOutcome.parsed,
    messageType: 'bill_payment',
    ruleId: 'baj-bill-payment-ar',
    amount: '412.3',
    currency: 'SAR',
    merchant: 'SEC-KAHRABA',
    billerCode: 'SEC-KAHRABA',
    invoiceNumber: 'INV77120934',
    instrumentMasked: '****3388',
    instrumentKind: 'account',
    occurredAtUtc: '2026-07-24T16:41:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 6/9 Credit-card repayment (names BOTH card and settling account) ----
  //
  // PRD §3.4 and US-B14: this template is the only automatic source of the
  // card→settlement-account link (AC-B14.1). `affectsSpend: false` — the
  // spend was already counted when the card was used; counting the repayment
  // too is the single easiest way to make every total in the app wrong
  // (architecture §4.2).
  SmsFixture(
    id: 'baj-06-card-repayment',
    sender: 'BAJ',
    body:
        'سداد بطاقة ائتمانية\n'
        'بطاقة:****9013\n'
        'من حساب:****3388\n'
        'مبلغ:1200.00 SAR\n'
        'في:23-07-26 12:00',
    expect: ExpectedOutcome.parsed,
    messageType: 'card_repayment',
    ruleId: 'baj-card-repayment-ar',
    amount: '1200',
    currency: 'SAR',
    instrumentMasked: '****9013',
    instrumentKind: 'card',
    settlementMasked: '****3388',
    occurredAtUtc: '2026-07-23T09:00:00.000Z',
    direction: 'debit',
    affectsSpend: false,
  ),

  // --- 7/9 Standalone fee / VAT debit --------------------------------------
  SmsFixture(
    id: 'baj-07-fee-vat',
    sender: 'BAJ',
    body:
        'رسوم وضريبة قيمة مضافة\n'
        'من حساب:****3388\n'
        'مبلغ:17.25 SAR\n'
        'في:22-07-26 03:15',
    expect: ExpectedOutcome.parsed,
    messageType: 'fee',
    ruleId: 'baj-fee-ar',
    amount: '17.25',
    currency: 'SAR',
    instrumentMasked: '****3388',
    instrumentKind: 'account',
    occurredAtUtc: '2026-07-22T00:15:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 8/9 Bare "debited from account", almost no other detail -------------
  //
  // PRD §3.4 lists this explicitly. It has no merchant at all, which is why
  // `merchant` is not a required field anywhere: requiring it would send
  // every one of these to the review queue for no benefit. The merchant
  // reads as explicitly unknown (AC-B1.3) instead.
  SmsFixture(
    id: 'baj-08-bare-account-debit',
    sender: 'BAJ',
    body:
        'خصم من حساب:****3388\n'
        'مبلغ:75.00 SAR\n'
        'في:21-07-26 16:20',
    expect: ExpectedOutcome.parsed,
    messageType: 'account_debit',
    ruleId: 'baj-account-debit-ar',
    amount: '75',
    currency: 'SAR',
    instrumentMasked: '****3388',
    instrumentKind: 'account',
    occurredAtUtc: '2026-07-21T13:20:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 9/9 Loan / finance installment, reporting a remaining balance -------
  SmsFixture(
    id: 'baj-09-installment',
    sender: 'BAJ',
    body:
        'قسط تمويل\n'
        'من حساب:****3388\n'
        'مبلغ:2350.00 SAR\n'
        'المتبقي:47000.00 SAR\n'
        'في:20-07-26 06:00',
    expect: ExpectedOutcome.parsed,
    messageType: 'installment',
    ruleId: 'baj-installment-ar',
    amount: '2350',
    currency: 'SAR',
    remainingBalance: '47000',
    instrumentMasked: '****3388',
    instrumentKind: 'account',
    occurredAtUtc: '2026-07-20T03:00:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- Noise from the same (known) sender ----------------------------------
  //
  // AC-A2.1. Note the OTP body contains the word "الشراء" (purchase) on
  // purpose: if the ignore rule did not outrank the purchase rule, the app
  // would invent a transaction out of a security code. This fixture is the
  // priority-ordering regression test.
  SmsFixture(
    id: 'baj-10-otp',
    sender: 'BAJ',
    body: 'رمز التحقق 483920 لعملية الشراء. لا تشاركه مع أحد.',
    expect: ExpectedOutcome.ignored,
    messageType: 'otp',
    ruleId: 'baj-otp',
    classification: 'ignored_otp',
  ),
  // AC-A2.2
  SmsFixture(
    id: 'baj-11-marketing',
    sender: 'BAJ',
    body: 'عرض خاص! تمويل شخصي بأرباح تنافسية. للتفاصيل اتصل بنا.',
    expect: ExpectedOutcome.ignored,
    messageType: 'marketing',
    ruleId: 'baj-marketing',
    classification: 'ignored_marketing',
  ),
  // AC-A2.5 — states a balance, reports no purchase.
  SmsFixture(
    id: 'baj-12-balance-info',
    sender: 'BAJ',
    body: 'رصيد حسابك:****3388 هو 8420.15 SAR بتاريخ 28-07-26',
    expect: ExpectedOutcome.ignored,
    messageType: 'balance_info',
    ruleId: 'baj-balance-info',
    classification: 'ignored_info',
  ),

  // --- The safety net (US-A4, AC-A4.4, NFR-A7) -----------------------------
  //
  // A known bank, a genuinely financial-sounding message, and no rule that
  // understands it — a bank changing a template (risk R-4). It MUST reach the
  // review queue. If this fixture ever starts being discarded, the product's
  // central promise ("nothing is missing") is broken.
  SmsFixture(
    id: 'baj-13-unknown-template',
    sender: 'BAJ',
    body: 'تنبيه: تم رصد عملية غير معتادة على حسابك. يرجى زيارة الفرع.',
    expect: ExpectedOutcome.unparsed,
  ),
  // A rule matches (it is clearly a POS purchase) but the amount is absent,
  // so a required field is missing. AC-A4.2: the user fills it in, we do not
  // invent a zero.
  SmsFixture(
    id: 'baj-14-purchase-missing-amount',
    sender: 'BAJ',
    body:
        'شراء\n'
        'بطاقة:مدى-****4821\n'
        'لدى:EXTRA MART 0042\n'
        'في:28-07-26 14:32',
    expect: ExpectedOutcome.unparsed,
  ),
];

/// D360 — **English** templates, per PRD §3.4 ("the other bank's are fully
/// English"). Structurally different from Aljazira for every single type,
/// which is the whole reason a generic template cannot work and the rule
/// engine has to exist.
const List<SmsFixture> d360Fixtures = <SmsFixture>[
  // --- 1/9 POS purchase ----------------------------------------------------
  SmsFixture(
    id: 'd360-01-pos-purchase',
    sender: 'D360',
    body:
        'D360: Purchase of SAR 89.00 with Mada Debit Card ending 4472 '
        'at BALAD COFFEE ROASTERS on 28/07/2026 15:10',
    expect: ExpectedOutcome.parsed,
    messageType: 'pos_purchase',
    ruleId: 'd360-pos-purchase-en',
    amount: '89',
    currency: 'SAR',
    merchant: 'BALAD COFFEE ROASTERS',
    instrumentMasked: '****4472',
    instrumentKind: 'card',
    instrumentNetwork: 'mada',
    instrumentCardType: 'debit',
    occurredAtUtc: '2026-07-28T12:10:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 2/9 Online purchase — the "converted amount in parentheses" form ----
  //
  // PRD §3.4 records that one format shows the converted amount in
  // parentheses after the foreign amount. Note the thousands separator is
  // absent here but present in the transfer fixtures below, deliberately:
  // both forms must survive `normalizeNumerals`.
  SmsFixture(
    id: 'd360-02-online-purchase-fx',
    sender: 'D360',
    body:
        'D360: Online purchase of USD 120.00 (SAR 450.12) with Visa Credit '
        'Card ending 8821 at NORTHWIND SOFTWARE. FX fee SAR 11.25. '
        'Rate 3.7510. On 27/07/2026 22:47',
    expect: ExpectedOutcome.parsed,
    messageType: 'online_purchase',
    ruleId: 'd360-online-purchase-en',
    amount: '120',
    currency: 'USD',
    convertedAmount: '450.12',
    convertedCurrency: 'SAR',
    feeAmount: '11.25',
    feeCurrency: 'SAR',
    exchangeRate: '3.7510',
    merchant: 'NORTHWIND SOFTWARE',
    instrumentMasked: '****8821',
    instrumentKind: 'card',
    instrumentNetwork: 'visa',
    instrumentCardType: 'credit',
    occurredAtUtc: '2026-07-27T19:47:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 3/9 Outgoing transfer -----------------------------------------------
  SmsFixture(
    id: 'd360-03-transfer-out',
    sender: 'D360',
    body:
        'D360: Outgoing transfer of SAR 2,000.00 from account ending 1157 '
        'to SARA K ALHARBI at Alinma Bank. Ref D360-TRF-556231. '
        'On 26/07/2026 10:02',
    expect: ExpectedOutcome.parsed,
    messageType: 'transfer_out',
    ruleId: 'd360-transfer-out-en',
    amount: '2000',
    currency: 'SAR',
    instrumentMasked: '****1157',
    instrumentKind: 'account',
    counterpartyName: 'SARA K ALHARBI',
    counterpartyBankName: 'Alinma Bank',
    referenceNumber: 'D360-TRF-556231',
    occurredAtUtc: '2026-07-26T07:02:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 4/9 Incoming transfer -----------------------------------------------
  SmsFixture(
    id: 'd360-04-transfer-in',
    sender: 'D360',
    body:
        'D360: Incoming transfer of SAR 9,750.00 to account ending 1157 '
        'from MERIDIAN LOGISTICS LLC at Riyad Bank. Ref D360-TRF-556904. '
        'On 25/07/2026 07:30',
    expect: ExpectedOutcome.parsed,
    messageType: 'transfer_in',
    ruleId: 'd360-transfer-in-en',
    amount: '9750',
    currency: 'SAR',
    instrumentMasked: '****1157',
    instrumentKind: 'account',
    counterpartyName: 'MERIDIAN LOGISTICS LLC',
    counterpartyBankName: 'Riyad Bank',
    referenceNumber: 'D360-TRF-556904',
    occurredAtUtc: '2026-07-25T04:30:00.000Z',
    direction: 'credit',
    affectsSpend: false,
  ),

  // --- 5/9 Bill payment ----------------------------------------------------
  SmsFixture(
    id: 'd360-05-bill-payment',
    sender: 'D360',
    body:
        'D360: Bill payment of SAR 320.55 from account ending 1157. '
        'Biller MOBILY-POSTPAID. Invoice 4471902288. On 24/07/2026 20:15',
    expect: ExpectedOutcome.parsed,
    messageType: 'bill_payment',
    ruleId: 'd360-bill-payment-en',
    amount: '320.55',
    currency: 'SAR',
    merchant: 'MOBILY-POSTPAID',
    billerCode: 'MOBILY-POSTPAID',
    invoiceNumber: '4471902288',
    instrumentMasked: '****1157',
    instrumentKind: 'account',
    occurredAtUtc: '2026-07-24T17:15:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 6/9 Credit-card repayment (card + settlement account) ---------------
  SmsFixture(
    id: 'd360-06-card-repayment',
    sender: 'D360',
    body:
        'D360: Credit card payment of SAR 1,500.00 to card ending 8821 '
        'from account ending 1157. On 23/07/2026 13:44',
    expect: ExpectedOutcome.parsed,
    messageType: 'card_repayment',
    ruleId: 'd360-card-repayment-en',
    amount: '1500',
    currency: 'SAR',
    instrumentMasked: '****8821',
    instrumentKind: 'card',
    settlementMasked: '****1157',
    occurredAtUtc: '2026-07-23T10:44:00.000Z',
    direction: 'debit',
    affectsSpend: false,
  ),

  // --- 7/9 Standalone fee / VAT -------------------------------------------
  SmsFixture(
    id: 'd360-07-fee-vat',
    sender: 'D360',
    body:
        'D360: Service fee and VAT of SAR 28.75 debited from account '
        'ending 1157. On 22/07/2026 04:00',
    expect: ExpectedOutcome.parsed,
    messageType: 'fee',
    ruleId: 'd360-fee-en',
    amount: '28.75',
    currency: 'SAR',
    instrumentMasked: '****1157',
    instrumentKind: 'account',
    occurredAtUtc: '2026-07-22T01:00:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 8/9 Bare debit ------------------------------------------------------
  //
  // This one is the priority trap for D360: its text is a strict SUBSTRING
  // shape of the fee (7/9) and installment (9/9) templates. If the catch-all
  // rule were not the lowest priority, it would swallow both of them and the
  // app would lose the fee/installment distinction entirely.
  SmsFixture(
    id: 'd360-08-bare-account-debit',
    sender: 'D360',
    body:
        'D360: SAR 60.00 debited from account ending 1157. '
        'On 21/07/2026 17:55',
    expect: ExpectedOutcome.parsed,
    messageType: 'account_debit',
    ruleId: 'd360-account-debit-en',
    amount: '60',
    currency: 'SAR',
    instrumentMasked: '****1157',
    instrumentKind: 'account',
    occurredAtUtc: '2026-07-21T14:55:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 9/9 Finance installment with remaining balance ----------------------
  SmsFixture(
    id: 'd360-09-installment',
    sender: 'D360',
    body:
        'D360: Finance installment of SAR 3,100.00 debited from account '
        'ending 1157. Remaining balance SAR 62,000.00. On 20/07/2026 05:00',
    expect: ExpectedOutcome.parsed,
    messageType: 'installment',
    ruleId: 'd360-installment-en',
    amount: '3100',
    currency: 'SAR',
    remainingBalance: '62000',
    instrumentMasked: '****1157',
    instrumentKind: 'account',
    occurredAtUtc: '2026-07-20T02:00:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- Noise ---------------------------------------------------------------
  SmsFixture(
    id: 'd360-10-otp',
    sender: 'D360',
    body:
        'D360: 774193 is your verification code. Do not share it with anyone.',
    expect: ExpectedOutcome.ignored,
    messageType: 'otp',
    ruleId: 'd360-otp',
    classification: 'ignored_otp',
  ),
  SmsFixture(
    id: 'd360-11-marketing',
    sender: 'D360',
    body: 'D360: Enjoy up to 30% cashback this month on dining. Terms apply.',
    expect: ExpectedOutcome.ignored,
    messageType: 'marketing',
    ruleId: 'd360-marketing',
    classification: 'ignored_marketing',
  ),
  SmsFixture(
    id: 'd360-12-balance-info',
    sender: 'D360',
    body:
        'D360: Balance for account ending 1157 is SAR 12,308.40 '
        'as of 28/07/2026',
    expect: ExpectedOutcome.ignored,
    messageType: 'balance_info',
    ruleId: 'd360-balance-info',
    classification: 'ignored_info',
  ),

  // --- Safety net ----------------------------------------------------------
  SmsFixture(
    id: 'd360-13-unknown-template',
    sender: 'D360',
    body: 'D360: Your card was used for a contactless payment. Details in app.',
    expect: ExpectedOutcome.unparsed,
  ),
];

/// Senders that match no bank in any pack.
///
/// AC-A2.3, and NFR-P4's strictest clause: these leave **no row at all**.
/// Note the first one deliberately looks financial — a personal message
/// about money. Resolving the bank from the *sender* rather than from the
/// body is what makes it impossible for this to become a transaction.
const List<SmsFixture> nonFinancialFixtures = <SmsFixture>[
  SmsFixture(
    id: 'noise-01-personal',
    sender: '+966500000000',
    body: 'I paid the 250 SAR for dinner, you can transfer it whenever.',
    expect: ExpectedOutcome.notFinancial,
  ),
  SmsFixture(
    id: 'noise-02-delivery',
    sender: 'ARAMEX',
    body: 'Your shipment 4471902288 is out for delivery today.',
    expect: ExpectedOutcome.notFinancial,
  ),
  SmsFixture(
    id: 'noise-03-lookalike-sender',
    sender: 'D360Rewards',
    body: 'D360: Purchase of SAR 89.00 with Mada Debit Card ending 4472',
    expect: ExpectedOutcome.notFinancial,
  ),
];

/// Everything, in one list, so the "nothing is silently discarded" assertion
/// can iterate the whole corpus without a test author having to remember to
/// add each group.
const List<SmsFixture> allFixtures = <SmsFixture>[
  ...aljaziraFixtures,
  ...d360Fixtures,
  ...nonFinancialFixtures,
];

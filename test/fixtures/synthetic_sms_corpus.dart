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
/// reference number — come from two prose sources, neither of which
/// reproduces any real text:
///
///  1. `docs/PRD.md` §3.4, for the two banks sampled before the build began;
///  2. Linear **KHA-136** / **KHA-145** (2026-07-30), where the human read the
///     shapes of their own messages off their own device and described them
///     structurally — field names, field order, language, delimiter style,
///     and crucially which fields are only *sometimes* present.
///
/// Every amount, merchant, counterparty, account suffix, reference number and
/// date here was invented for this file.
///
/// The bank *names* are real, because they are public companies. Nothing else
/// is.
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

  // --- P3b-1 additions: the types a period total needs in order to mean
  // something (KHA-27, KHA-28, KHA-29) -------------------------------------
  //
  // These four templates are **extrapolated, not observed.** PRD §3.4's sample
  // set covered nine message types and none of them was a refund, an ATM
  // withdrawal, or a foreign purchase without an inline conversion — yet
  // AC-B7.1, AC-B10.1 and AC-B10.2 are all written as "given an SMS
  // describing…". So the shapes below follow the *field-label style* the same
  // bank uses for its observed templates (Arabic labels, `key:value`, the same
  // date format) rather than being invented from nothing. That is stated
  // plainly here so a reviewer knows which fixtures rest on real structural
  // evidence and which rest on a consistent extension of it — and so that,
  // when real samples of these types arrive (OQ-2 is explicitly still open for
  // "declines, partial refunds"), whoever updates them knows these are the
  // ones to check first.

  // --- 10/13 Refund to a card (KHA-28, AC-B7.1) ----------------------------
  //
  // `direction: credit`, and note `affectsSpend: true` — a refund very much
  // affects the spend total; it *reduces* it. `false` would exclude it
  // entirely and leave the original purchase standing at full price.
  SmsFixture(
    id: 'baj-15-refund',
    sender: 'BAJ',
    body:
        'استرجاع مبلغ\n'
        'بطاقة:فيزا-****9013\n'
        'مبلغ:187.46 SAR\n'
        'من:GLOBAL CLOUD SERVICES\n'
        'في:29-07-26 10:15',
    expect: ExpectedOutcome.parsed,
    messageType: 'refund',
    ruleId: 'baj-refund-ar',
    amount: '187.46',
    currency: 'SAR',
    merchant: 'GLOBAL CLOUD SERVICES',
    instrumentMasked: '****9013',
    instrumentKind: 'card',
    instrumentNetwork: 'فيزا',
    occurredAtUtc: '2026-07-29T07:15:00.000Z',
    direction: 'credit',
    affectsSpend: true,
  ),

  // --- 11/13 ATM cash withdrawal (KHA-29, AC-B10.2) ------------------------
  SmsFixture(
    id: 'baj-16-atm-withdrawal',
    sender: 'BAJ',
    body:
        'سحب نقدي\n'
        'من حساب:****3388\n'
        'مبلغ:500.00 SAR\n'
        'الصراف:ATM-RIYADH-0042\n'
        'في:27-07-26 18:22',
    expect: ExpectedOutcome.parsed,
    messageType: 'withdrawal',
    ruleId: 'baj-atm-withdrawal-ar',
    amount: '500',
    currency: 'SAR',
    merchant: 'ATM-RIYADH-0042',
    instrumentMasked: '****3388',
    instrumentKind: 'account',
    occurredAtUtc: '2026-07-27T15:22:00.000Z',
    direction: 'debit',
    affectsSpend: false,
  ),

  // --- 12/13 Salary credit (KHA-29, AC-B10.1) ------------------------------
  //
  // Distinct from `baj-04-transfer-in-salary`, deliberately: that fixture is
  // the *generic* incoming transfer that happens to be a salary, and it must
  // keep classifying as `transfer_in`. This one names the salary explicitly
  // and must outrank it. Together they pin the priority ordering.
  SmsFixture(
    id: 'baj-17-salary',
    sender: 'BAJ',
    body:
        'راتب\n'
        'إلى حساب:****3388\n'
        'مبلغ:14500.00 SAR\n'
        'من:ALFA TRADING COMPANY\n'
        'رقم العملية:TRX8850999\n'
        'في:25-07-26 07:30',
    expect: ExpectedOutcome.parsed,
    messageType: 'salary_income',
    ruleId: 'baj-salary-ar',
    amount: '14500',
    currency: 'SAR',
    instrumentMasked: '****3388',
    instrumentKind: 'account',
    counterpartyName: 'ALFA TRADING COMPANY',
    referenceNumber: 'TRX8850999',
    occurredAtUtc: '2026-07-25T04:30:00.000Z',
    direction: 'credit',
    affectsSpend: false,
  ),

  // --- 13/13 Foreign purchase with NO conversion (KHA-27, ADR-009 case 4) --
  //
  // The message states EUR and nothing else — no converted amount, no rate.
  // ADR-009 forbids inventing one, so this transaction is recorded in full,
  // is **excluded from the base-currency total**, and is counted on the
  // "N transactions not converted" line. It is the fixture that proves the
  // app would rather show an incomplete total than a fabricated one.
  SmsFixture(
    id: 'baj-18-pos-purchase-foreign-unconverted',
    sender: 'BAJ',
    body:
        'شراء\n'
        'بطاقة:فيزا-****9013\n'
        'مبلغ:35.00 EUR\n'
        'لدى:PARIS BOOKSHOP\n'
        'في:26-07-26 12:00',
    expect: ExpectedOutcome.parsed,
    messageType: 'pos_purchase',
    ruleId: 'baj-pos-purchase-ar',
    amount: '35',
    currency: 'EUR',
    merchant: 'PARIS BOOKSHOP',
    instrumentMasked: '****9013',
    instrumentKind: 'card',
    instrumentNetwork: 'فيزا',
    occurredAtUtc: '2026-07-26T09:00:00.000Z',
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

  // --- KHA-145 additions: the second POS channel, and a notification -------
  //
  // Structure from the live KHA-136 sampling round; every value invented.
  // Sender is the human-confirmed `Jazira Bank` (KHA-128), which is what a
  // real device shows.

  // --- 19 POS purchase through the second (wallet/channel) template --------
  //
  // The KHA-145 defect, reproduced and fixed. Real messages of this shape sat
  // in Needs Review saying "Some details were missing from this message":
  // they satisfy `baj-pos-purchase-ar`'s gate (شراء / بطاقة / لدى) and then
  // fail its extraction, because this channel writes `التاريخ:` with a
  // four-digit year instead of `في:` with a two-digit one, prefixes its
  // labels with the definite article, and adds an available-balance and a
  // total-amount-due line.
  //
  // The channel name in the header is deliberately generic here: the rule
  // does not key on a payment brand at all (its regex starts at the card
  // label), because a brand is exactly the part a bank rebrands next quarter.
  //
  // `remainingBalance` carries the available balance. The total amount due is
  // matched and NOT extracted — it is a statement figure, not a movement, and
  // putting two different numbers in one field would be worse than dropping
  // one of them.
  SmsFixture(
    id: 'baj-19-pos-purchase-wallet',
    sender: 'Jazira Bank',
    body:
        'شراء عبر محفظة الجوال\n'
        'البطاقة: ****4821\n'
        'المبلغ: 88.00 SAR\n'
        'لدى: SAMPLE COFFEE HOUSE\n'
        'التاريخ: 30/07/2026 08:05\n'
        'الرصيد المتاح: 1234.56 SAR\n'
        'إجمالي المستحق: 210.00 SAR',
    expect: ExpectedOutcome.parsed,
    messageType: 'pos_purchase',
    ruleId: 'baj-pos-purchase-wallet-ar',
    amount: '88',
    currency: 'SAR',
    merchant: 'SAMPLE COFFEE HOUSE',
    instrumentMasked: '****4821',
    instrumentKind: 'card',
    remainingBalance: '1234.56',
    occurredAtUtc: '2026-07-30T05:05:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 20 Beneficiary registration / pending activation (ignore) -----------
  //
  // Moves no money, names a payee, and used to sit in Needs Review forever.
  // `ignore` does not mean "dropped": a counter row with no body is still
  // written (NFR-P4), so the parser-health panel can report how many of these
  // arrived without retaining one character of them.
  SmsFixture(
    id: 'baj-20-beneficiary-notification',
    sender: 'Jazira Bank',
    body:
        'تم تسجيل المستفيد الجديد SAMPLE PAYEE NAME بانتظار التفعيل '
        'خلال 24 ساعة.',
    expect: ExpectedOutcome.ignored,
    messageType: 'beneficiary_notification',
    ruleId: 'baj-beneficiary-notification-ar',
    classification: 'ignored_info',
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

  // --- P3b-1 additions (see the note in the Aljazira list above for why
  // these three are extrapolated rather than observed) ----------------------

  // --- 10/12 Refund to a card (KHA-28, AC-B7.1) ----------------------------
  SmsFixture(
    id: 'd360-14-refund',
    sender: 'D360',
    body:
        'D360: Refund of SAR 187.46 to Visa Credit Card ending 8821 '
        'from NORTHWIND SOFTWARE. On 29/07/2026 10:15',
    expect: ExpectedOutcome.parsed,
    messageType: 'refund',
    ruleId: 'd360-refund-en',
    amount: '187.46',
    currency: 'SAR',
    merchant: 'NORTHWIND SOFTWARE',
    instrumentMasked: '****8821',
    instrumentKind: 'card',
    instrumentNetwork: 'visa',
    instrumentCardType: 'credit',
    occurredAtUtc: '2026-07-29T07:15:00.000Z',
    direction: 'credit',
    affectsSpend: true,
  ),

  // --- 11/12 ATM cash withdrawal (KHA-29, AC-B10.2) ------------------------
  SmsFixture(
    id: 'd360-15-atm-withdrawal',
    sender: 'D360',
    body:
        'D360: Cash withdrawal of SAR 500.00 from account ending 1157 '
        'at ATM RIYADH 0042. On 27/07/2026 18:22',
    expect: ExpectedOutcome.parsed,
    messageType: 'withdrawal',
    ruleId: 'd360-atm-withdrawal-en',
    amount: '500',
    currency: 'SAR',
    merchant: 'ATM RIYADH 0042',
    instrumentMasked: '****1157',
    instrumentKind: 'account',
    occurredAtUtc: '2026-07-27T15:22:00.000Z',
    direction: 'debit',
    affectsSpend: false,
  ),

  // --- 12/12 Salary credit (KHA-29, AC-B10.1) ------------------------------
  SmsFixture(
    id: 'd360-16-salary',
    sender: 'D360',
    body:
        'D360: Salary credit of SAR 14,500.00 to account ending 1157 '
        'from ALFA TRADING COMPANY. Ref D360-SAL-990112. On 25/07/2026 07:30',
    expect: ExpectedOutcome.parsed,
    messageType: 'salary_income',
    ruleId: 'd360-salary-en',
    amount: '14500',
    currency: 'SAR',
    instrumentMasked: '****1157',
    instrumentKind: 'account',
    counterpartyName: 'ALFA TRADING COMPANY',
    referenceNumber: 'D360-SAL-990112',
    occurredAtUtc: '2026-07-25T04:30:00.000Z',
    direction: 'credit',
    affectsSpend: false,
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

  // --- KHA-145 additions: message TYPES this "configured" bank was missing --
  //
  // Structure from the live KHA-136 sampling round; every value invented.
  // Note the sender is the human-confirmed `D360 Bank` (KHA-128) rather than
  // the older guessed `D360`, so these fixtures also exercise the sender
  // string a real device actually delivers.

  // --- 17 Ecommerce purchase (a THIRD purchase shape) ----------------------
  //
  // Distinct from both existing purchase templates: a label:value layout with
  // an explicit `Ecommerce` channel tag and no conversion/fee block at all.
  // It classifies as `online_purchase` — the type vocabulary is closed
  // (`transaction_types.dart`), and inventing `ecommerce_purchase` would make
  // this transaction unknown-typed and therefore excluded from spend totals.
  SmsFixture(
    id: 'd360-17-ecommerce-purchase',
    sender: 'D360 Bank',
    body:
        'D360 Bank\n'
        'Purchase - Ecommerce\n'
        'Card: Mada Debit ****4472\n'
        'Amount: SAR 320.00\n'
        'Merchant: SAMPLE ONLINE STORE\n'
        'Date: 28/07/2026 21:15',
    expect: ExpectedOutcome.parsed,
    messageType: 'online_purchase',
    ruleId: 'd360-ecommerce-purchase-en',
    amount: '320',
    currency: 'SAR',
    merchant: 'SAMPLE ONLINE STORE',
    instrumentMasked: '****4472',
    instrumentKind: 'card',
    instrumentNetwork: 'mada',
    instrumentCardType: 'debit',
    occurredAtUtc: '2026-07-28T18:15:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 18 Incoming-transfer NOTIFICATION -----------------------------------
  //
  // `direction: credit` and `affectsSpend: false`. Money arriving is not
  // spending; if the counterparty turns out to be the user themselves, P3's
  // internal-transfer pairing nets it against the outbound leg (US-B10/B11).
  // The opposite flag on a salary-sized credit is the largest error the app
  // could make in the one number it exists to show.
  //
  // The sender's IBAN is deliberately NOT extracted: it identifies the
  // counterparty, and `instrumentRef` means "the user's own account". Hence
  // `instrumentMasked: null` even though the message clearly names an
  // identifier — recording it would invent a stranger's account inside the
  // user's own bank tree.
  SmsFixture(
    id: 'd360-18-transfer-in-notification',
    sender: 'D360 Bank',
    body:
        'D360 Bank\n'
        'Incoming Transfer\n'
        'From Bank: Sample Bank Three\n'
        'Amount: SAR 1850.00\n'
        'Sender: OMAR K ALZAHRANI\n'
        'IBAN: SA**7654\n'
        'Date: 29/07/2026 13:05',
    expect: ExpectedOutcome.parsed,
    messageType: 'transfer_in',
    ruleId: 'd360-transfer-in-notification-en',
    amount: '1850',
    currency: 'SAR',
    counterpartyName: 'OMAR K ALZAHRANI',
    counterpartyBankName: 'Sample Bank Three',
    occurredAtUtc: '2026-07-29T10:05:00.000Z',
    direction: 'credit',
    affectsSpend: false,
  ),

  // --- 19 Arabic OTP from an English-language bank -------------------------
  //
  // The AC-A2.1 hazard in its purest form, and the reason `d360-otp-ar`
  // exists: D360 writes transactions in English but sends the verification
  // code for an online purchase in Arabic, quoting the merchant and the
  // amount. Any rule reading this as a purchase would double that day's
  // spend. The ignore rule at priority 900 is what makes it a counter-only
  // row with no body retained (NFR-P4) instead.
  SmsFixture(
    id: 'd360-19-otp-ar',
    sender: 'D360 Bank',
    body:
        'D360 Bank: رمز التحقق 883021 لعملية شراء عبر الإنترنت بمبلغ '
        '320.00 SAR لدى SAMPLE ONLINE STORE. لا تشاركه مع أحد.',
    expect: ExpectedOutcome.ignored,
    messageType: 'otp',
    ruleId: 'd360-otp-ar',
    classification: 'ignored_otp',
  ),
];

// ---------------------------------------------------------------------------
// KHA-136 — the banks that gained their FIRST templates
// ---------------------------------------------------------------------------
//
// Everything below was authored from the structural descriptions the human
// read off their own device on 2026-07-30 and wrote down on Linear KHA-136:
// which fields appear, in what order, in which language, joined by which
// delimiter, and — the part that matters most for `requiredFields` — which
// fields are only *sometimes* present. No real message text, amount, name,
// merchant or account number was recorded anywhere, including in that issue
// (NFR-M3). Every value here is invented for this file.
//
// Each bank gets rules for the types that were actually observed and for no
// others. That is why `nera` has one type and `al-rajhi` has no transaction
// rule at all: a guessed extraction regex silently produces a WRONG amount,
// while a missing rule produces a visible review item the user can complete.
//
// Every bank below also carries a **safety-net fixture**, and each one reuses
// the exact body that `test/features/ingestion/sender_only_bank_review_test`
// and `test/qa/kha_128_sender_gate_qa_probes_test` feed through the pipeline
// for that sender. Those two suites assert those bodies reach Needs Review
// with `no_rule_matched`, which is only true while these gates stay narrow —
// so pinning the same strings here means a gate widened by accident fails in
// this fast unit suite first, naming the rule, instead of surfacing three
// files away as an unexplained pipeline count.

/// nera — **English**, `label: value`, with the card's sub-fields joined by
/// semicolons and a running balance that is not always present.
const List<SmsFixture> neraFixtures = <SmsFixture>[
  // --- 1/2 Card purchase, with the optional balance line present ----------
  SmsFixture(
    id: 'nera-01-pos-purchase',
    sender: 'nera',
    body:
        'nera\n'
        'Purchase\n'
        'Card: mada;****6034\n'
        'Amount: SAR 137.50\n'
        'Merchant: SAMPLE MART RIYADH\n'
        'Balance: SAR 2410.75\n'
        'Date: 30/07/2026 14:32:10',
    expect: ExpectedOutcome.parsed,
    messageType: 'pos_purchase',
    ruleId: 'nera-pos-purchase-en',
    amount: '137.5',
    currency: 'SAR',
    merchant: 'SAMPLE MART RIYADH',
    instrumentMasked: '****6034',
    instrumentKind: 'card',
    instrumentNetwork: 'mada',
    remainingBalance: '2410.75',
    // 14:32:10 Riyadh. The seconds are pinned too: this template prints them
    // and a rule that silently dropped them would still look right in a list.
    occurredAtUtc: '2026-07-30T11:32:10.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 2/2 Same type, NO balance line, and a three-part card field --------
  //
  // Two things at once, both deliberate. First, "optional" that is only ever
  // tested present is not optional: if `Balance:` were required, every
  // message of this shape would land in Needs Review — the KHA-145 failure
  // mode on another bank. `remainingBalance` is therefore expected to be
  // null, not zero (AC-B1.3).
  //
  // Second, the card field here carries a wallet tag *and* a network before
  // the masked number, so the rule must read a two-part or a three-part
  // semicolon list without knowing which it will get.
  SmsFixture(
    id: 'nera-02-pos-purchase-no-balance',
    sender: 'nera',
    body:
        'nera\n'
        'Purchase\n'
        'Card: apple pay;mada;****6034\n'
        'Amount: SAR 42.00\n'
        'Merchant: SAMPLE PHARMACY 7\n'
        'Date: 29/07/2026 19:05:44',
    expect: ExpectedOutcome.parsed,
    messageType: 'pos_purchase',
    ruleId: 'nera-pos-purchase-en',
    amount: '42',
    currency: 'SAR',
    merchant: 'SAMPLE PHARMACY 7',
    instrumentMasked: '****6034',
    instrumentKind: 'card',
    // Reported verbatim, wallet tag and all. Canonicalising this onto
    // visa|mada|mastercard is P3 entity-resolution work; the parser's job is
    // to say what the message said. It is safe for the two fixtures to
    // disagree here because the network is an *attribute* of an instrument,
    // never part of its identity (`instrument_identity.dart`) — so both
    // fixtures still resolve to the one card ****6034.
    instrumentNetwork: 'apple pay;mada',
    occurredAtUtc: '2026-07-29T16:05:44.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- Safety net ---------------------------------------------------------
  //
  // nera has exactly one template, so anything else it sends must reach the
  // review queue rather than vanish (AC-A4.4). This is also the fixture that
  // proves the purchase rule's gate is narrow: it says "payment" and names an
  // amount, and it still must not become a transaction.
  SmsFixture(
    id: 'nera-03-unknown-template',
    sender: 'nera',
    body: 'nera: Card payment 61.25 SAR at SAMPLE STORE 12. Ref TS00119.',
    expect: ExpectedOutcome.unparsed,
  ),
];

/// AlRajhi — an **OTP only**. No transaction sample was obtained, so there is
/// deliberately no transaction fixture here and no transaction rule in the
/// pack. See the bank's `_note` in `assets/rule_packs/sa-core.json`.
const List<SmsFixture> alRajhiFixtures = <SmsFixture>[
  SmsFixture(
    id: 'rajhi-01-otp',
    sender: 'AlRajhi Bank',
    body:
        'AlRajhi Bank\n'
        'OTP Code: 483920\n'
        'Reason: Login',
    expect: ExpectedOutcome.ignored,
    messageType: 'otp',
    ruleId: 'rajhi-otp-en',
    classification: 'ignored_otp',
  ),

  // The half of this bank that is still missing, asserted as missing rather
  // than left unstated: a transaction-shaped message must reach the review
  // queue, where US-A4/S-19 completes it by hand (AC-A6.5). The day a real
  // sample arrives, this fixture is the one that turns into a parsed one.
  SmsFixture(
    id: 'rajhi-02-transaction-not-yet-templated',
    sender: 'AlRajhi Bank',
    body: 'AlRajhi Bank: 240.00 SAR spent, acct ending 7788, 30-07-26 09:14.',
    expect: ExpectedOutcome.unparsed,
  ),
];

/// STC Bank — **English**, one label per line and **no colons**, so the
/// labels themselves are the delimiters.
const List<SmsFixture> stcBankFixtures = <SmsFixture>[
  // --- 1/3 SARIE inward transfer (interbank) ------------------------------
  //
  // `direction: credit`, `affectsSpend: false` — money arriving is not
  // spending, and an internal one is netted at the pair level in P3
  // (US-B10/B11), never guessed at from one message.
  SmsFixture(
    id: 'stc-01-transfer-in-sarie',
    sender: 'STC Bank',
    body:
        'STC Bank\n'
        'Incoming Transfer (SARIE)\n'
        'Amount\n'
        'SAR 3250.00\n'
        'From\n'
        'FAISAL A ALSHEHRI\n'
        'From Bank\n'
        'Sample Bank Two\n'
        'To Account\n'
        '****5566\n'
        'Date\n'
        '30/07/2026 09:15\n'
        'Reference\n'
        'STCB4471902',
    expect: ExpectedOutcome.parsed,
    messageType: 'transfer_in',
    ruleId: 'stc-transfer-in-sarie-en',
    amount: '3250',
    currency: 'SAR',
    instrumentMasked: '****5566',
    instrumentKind: 'account',
    counterpartyName: 'FAISAL A ALSHEHRI',
    counterpartyBankName: 'Sample Bank Two',
    referenceNumber: 'STCB4471902',
    occurredAtUtc: '2026-07-30T06:15:00.000Z',
    direction: 'credit',
    affectsSpend: false,
  ),

  // --- 2/3 Instant transfer out to a named recipient ----------------------
  //
  // `affectsSpend: true`, matching every other `transfer_out` in this pack.
  // Money leaving toward a named counterparty is spend unless that
  // counterparty is the user, which is a property of the *pair* and cannot be
  // known from one message (AC-B11.2). Guessing `false` would silently hide
  // real payments from the total.
  //
  // This template names no account at all, so `instrumentMasked` is null —
  // explicitly unknown, never a blank instrument.
  SmsFixture(
    id: 'stc-02-transfer-out',
    sender: 'STC Bank',
    body:
        'STC Bank\n'
        'Transfer Out\n'
        'Amount\n'
        'SAR 150.00\n'
        'To\n'
        'NOURAH S ALQAHTANI\n'
        'Date\n'
        '30/07/2026 10:05',
    expect: ExpectedOutcome.parsed,
    messageType: 'transfer_out',
    ruleId: 'stc-transfer-out-en',
    amount: '150',
    currency: 'SAR',
    counterpartyName: 'NOURAH S ALQAHTANI',
    occurredAtUtc: '2026-07-30T07:05:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 3/3 The P2P "Pay X" payment — first half of a PAIR -----------------
  //
  // One logical transaction arrives as TWO SMS: this one, and its own OTP
  // (next fixture). Only this half may become a transaction. See
  // `stc-payment-otp` in the pack, and the combination test in
  // `rule_pack_corpus_test.dart` that feeds both and asserts exactly one
  // transaction comes out.
  SmsFixture(
    id: 'stc-03-p2p-payment',
    sender: 'STC Bank',
    body:
        'STC Bank\n'
        'Pay SALEH M ALDOSSARI\n'
        'Amount\n'
        'SAR 75.00\n'
        'Date\n'
        '30/07/2026 12:40\n'
        'Reference\n'
        'STCBP2P8830142',
    expect: ExpectedOutcome.parsed,
    messageType: 'transfer_out',
    ruleId: 'stc-p2p-payment-en',
    amount: '75',
    currency: 'SAR',
    counterpartyName: 'SALEH M ALDOSSARI',
    referenceNumber: 'STCBP2P8830142',
    occurredAtUtc: '2026-07-30T09:40:00.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- The OTP half of that same pair -------------------------------------
  //
  // It quotes the payee, the amount and the same reference as the payment
  // above. Without an ignore rule that outranks the payment rule, this second
  // SMS would produce a second 75.00 transaction and double the user's spend
  // for that payment. It is recognised and discarded — a counter row with no
  // body (NFR-P4) — not silently dropped.
  SmsFixture(
    id: 'stc-04-p2p-payment-otp',
    sender: 'STC Bank',
    body:
        'STC Bank\n'
        'Pay SALEH M ALDOSSARI\n'
        'Amount\n'
        'SAR 75.00\n'
        'Reference\n'
        'STCBP2P8830142\n'
        'OTP 774193\n'
        'Do not share this code with anyone.',
    expect: ExpectedOutcome.ignored,
    messageType: 'otp',
    ruleId: 'stc-payment-otp',
    classification: 'ignored_otp',
  ),

  // --- A standalone security code (the other OTP shape) -------------------
  SmsFixture(
    id: 'stc-05-otp',
    sender: 'STC Bank',
    body: 'STC Bank: Your verification code is 118240. Do not share it.',
    expect: ExpectedOutcome.ignored,
    messageType: 'otp',
    ruleId: 'stc-otp',
    classification: 'ignored_otp',
  ),

  // --- Safety net ---------------------------------------------------------
  SmsFixture(
    id: 'stc-06-unknown-template',
    sender: 'STC Bank',
    body: 'STC Bank: Wallet debit 18.90 SAR - EXAMPLE VENDOR ONE.',
    expect: ExpectedOutcome.unparsed,
  ),
];

/// SAB — the **bilingual** bank: the same purchase type arrives in English
/// *and* in Arabic from this one sender, with different punctuation
/// conventions in each. Both variants are templated; assuming one language
/// per bank would leave half of them in Needs Review.
const List<SmsFixture> sabFixtures = <SmsFixture>[
  // --- 1/4 English POS purchase, balance present, wallet tag present ------
  SmsFixture(
    id: 'sab-01-pos-purchase-en',
    sender: 'SAB',
    body:
        'SAB\n'
        'Purchase\n'
        'Card: ****7788;Visa;Mobile Wallet\n'
        'Amount: SAR 249.90\n'
        'Merchant: SAMPLE ELECTRONICS CO\n'
        'Balance: SAR 5120.45\n'
        'Date: 30/07/2026 16:48:02',
    expect: ExpectedOutcome.parsed,
    messageType: 'pos_purchase',
    ruleId: 'sab-pos-purchase-en',
    amount: '249.9',
    currency: 'SAR',
    merchant: 'SAMPLE ELECTRONICS CO',
    instrumentMasked: '****7788',
    instrumentKind: 'card',
    instrumentNetwork: 'visa',
    remainingBalance: '5120.45',
    occurredAtUtc: '2026-07-30T13:48:02.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 2/4 Same type, NO balance and no wallet tag ------------------------
  //
  // The structural spec is explicit that a running balance is not on every
  // SAB purchase. This fixture is what stops anyone adding `remainingBalance`
  // to `requiredFields` — doing so would route every message of this shape to
  // Needs Review while looking like a tightening improvement.
  SmsFixture(
    id: 'sab-02-pos-purchase-en-no-balance',
    sender: 'SAB',
    body:
        'SAB\n'
        'Purchase\n'
        'Card: ****7788;Mada\n'
        'Amount: SAR 63.00\n'
        'Merchant: SAMPLE BAKERY\n'
        'Date: 28/07/2026 07:12:33',
    expect: ExpectedOutcome.parsed,
    messageType: 'pos_purchase',
    ruleId: 'sab-pos-purchase-en',
    amount: '63',
    currency: 'SAR',
    merchant: 'SAMPLE BAKERY',
    instrumentMasked: '****7788',
    instrumentKind: 'card',
    instrumentNetwork: 'mada',
    occurredAtUtc: '2026-07-28T04:12:33.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 3/4 The SAME purchase type, in Arabic ------------------------------
  //
  // Same fields, Arabic labels carrying the definite article, and the network
  // in parentheses rather than semicolon-joined — a different pattern, not a
  // widened English one. Note it resolves to the same card ****7788 as the
  // English fixtures: identity is bank + kind + digits, so a bank switching
  // language mid-month must not split one card into two.
  SmsFixture(
    id: 'sab-03-pos-purchase-ar',
    sender: 'SAB',
    body:
        'SAB\n'
        'شراء\n'
        'البطاقة: ****7788 (فيزا)\n'
        'المبلغ: 318.25 SAR\n'
        'لدى: SAMPLE FURNITURE HOUSE\n'
        'الرصيد: 4801.10 SAR\n'
        'التاريخ: 27/07/2026 20:03:11',
    expect: ExpectedOutcome.parsed,
    messageType: 'pos_purchase',
    ruleId: 'sab-pos-purchase-ar',
    amount: '318.25',
    currency: 'SAR',
    merchant: 'SAMPLE FURNITURE HOUSE',
    instrumentMasked: '****7788',
    instrumentKind: 'card',
    instrumentNetwork: 'فيزا',
    remainingBalance: '4801.1',
    occurredAtUtc: '2026-07-27T17:03:11.000Z',
    direction: 'debit',
    affectsSpend: true,
  ),

  // --- 4/4 Arabic incoming-transfer deposit -------------------------------
  //
  // The masked account named here is the user's own receiving account, so it
  // IS the instrument. The sender's IBAN is matched and deliberately not
  // extracted — there is no field for a counterparty identifier, and putting
  // it in `instrumentRef` would attribute the user's money to a stranger's
  // account inside their own bank tree.
  SmsFixture(
    id: 'sab-04-transfer-in-ar',
    sender: 'SAB',
    body:
        'SAB\n'
        'إيداع حوالة واردة\n'
        'إلى حساب: ****1122\n'
        'من: SAMPLE SENDER NAME\n'
        'الايبان: SA**7654\n'
        'البنك: Sample Bank Two\n'
        'المبلغ: 3200.00 SAR\n'
        'التاريخ: 29/07/2026 11:20:35\n'
        'المرجع: SABX20260729A0099',
    expect: ExpectedOutcome.parsed,
    messageType: 'transfer_in',
    ruleId: 'sab-transfer-in-ar',
    amount: '3200',
    currency: 'SAR',
    instrumentMasked: '****1122',
    instrumentKind: 'account',
    counterpartyName: 'SAMPLE SENDER NAME',
    counterpartyBankName: 'Sample Bank Two',
    referenceNumber: 'SABX20260729A0099',
    occurredAtUtc: '2026-07-29T08:20:35.000Z',
    direction: 'credit',
    affectsSpend: false,
  ),

  // --- Biometric / login notification (ignore) ----------------------------
  //
  // Security-shaped text from a financial sender. Recognised at priority 900
  // so that the next loosely-written rule anyone adds to this bank cannot
  // read one as a movement.
  SmsFixture(
    id: 'sab-05-login-notification',
    sender: 'SAB',
    body: 'SAB: تم تسجيل الدخول إلى التطبيق باستخدام البصمة على جهاز جديد.',
    expect: ExpectedOutcome.ignored,
    messageType: 'security_notification',
    ruleId: 'sab-login-notification-ar',
    classification: 'ignored_info',
  ),

  // --- Safety net ---------------------------------------------------------
  SmsFixture(
    id: 'sab-06-unknown-template',
    sender: 'SAB',
    body: 'SAB: SAR 75.40 debited. Merchant SAMPLE GROCER 3. Ref ZZ0088.',
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

/// SAIB — a recognised sender with **no templates at all**, which is a
/// complete state and not a stub (AC-A6.5). No message of any kind was
/// observed for this bank in the KHA-136 round, so nothing is guessed.
///
/// The fixture exists so the corpus covers all seven configured banks and so
/// the sender-only path is exercised by the same sweep as everything else:
/// past gate 1, no rule, review queue, nothing lost.
const List<SmsFixture> saibFixtures = <SmsFixture>[
  SmsFixture(
    id: 'saib-01-no-template-yet',
    sender: 'SAIB',
    body: 'SAIB: Payment of SAR 512.00 completed. Reference QQ4410.',
    expect: ExpectedOutcome.unparsed,
  ),
];

/// Everything, in one list, so the "nothing is silently discarded" assertion
/// can iterate the whole corpus without a test author having to remember to
/// add each group.
///
/// **Add every new group here.** A fixture list that exists but is not in
/// this list is invisible to the NFR-A7 sweep in `rule_pack_corpus_test.dart`
/// — which is the one assertion in the suite designed to catch a message
/// disappearing rather than a message parsing wrongly.
const List<SmsFixture> allFixtures = <SmsFixture>[
  ...aljaziraFixtures,
  ...d360Fixtures,
  ...neraFixtures,
  ...alRajhiFixtures,
  ...stcBankFixtures,
  ...saibFixtures,
  ...sabFixtures,
  ...nonFinancialFixtures,
];

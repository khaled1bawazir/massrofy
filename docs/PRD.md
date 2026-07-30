STATUS: Approved
TIER: personal
# Massrofy — Personal Spending Tracker from Bank SMS

**Version:** 0.5 (Addendum B — user-taught message formats; see the addendum status lines below)
**Date:** 2026-07-27 (v0.3), 2026-07-30 (Addendum A), 2026-07-30 (Addendum B)
**Author:** product-owner agent (v0.1), revised directly per human decisions (v0.2)
**Phase:** 1 — Requirements

> **ADDENDUM A STATUS: APPROVED (2026-07-30).**
> On 2026-07-30, after a real-device finding (Linear **KHA-128**: the bundled rule pack
> configures 2 of the user's 7 banks, and both patterns were guessed wrong — the phone shows
> `Jazira Bank`, which matches none of them), one capability (**C17**), two stories
> (**US-A6**, **US-B16**), two out-of-scope rows (**X18**, **X19**) and one privacy
> requirement (**NFR-P4a**) were added. Every addendum item is tagged
> **`[Addendum A — APPROVED]`**.
> Everything else in this document stays `Approved` and `/build` may continue against it.
> **The tagged items are now authorised for build**, sequenced per the human's decision on
> OQ-23: **KHA-128 (verified sender patterns for the 7 known banks) ships first, US-A6 second.**
> Both are needed; neither substitutes for the other.
> **Process note:** US-A6 needs one screen `docs/design.md` does not contain (an unrecognized-
> sender review screen), so building it also triggers a `/revise-design` round — the same
> shape as architecture.md's H-15. It does **not** reopen gate 1 for the rest of the PRD.
> **Human decisions on OQ-21/22, 2026-07-30:** the sender-recognition check stays **on-demand
> only** (not added to first-run onboarding) — see OQ-21 resolution below. A linked bank whose
> messages can't be auto-parsed **is stated explicitly per bank**, not left to the Needs Review
> queue alone — see OQ-22 resolution below, which also adds a manual **AC-A6.10** (re-check a
> linked bank on demand, not just once at link time).

> **ADDENDUM B STATUS: APPROVED (2026-07-30).**
> Everything else in this document — including Addendum A — stays as it is. Addendum B adds
> **Epic J**, two capabilities (**C18**, **C19**), six stories (**US-J1**–**US-J6**, of which
> **three are v1 and three are explicitly deferred**), three out-of-scope rows (**X18a**, **X20**,
> **X21**), two non-functional requirements (**NFR-M3a**, **NFR-A1a**) and five open questions
> (**OQ-24**–**OQ-28**), of which **OQ-24, OQ-25, and OQ-27 are now resolved** (see below); OQ-26
> (the confirmation count for the deferred learning phase) and OQ-28 (the usage trigger for
> re-opening X20) remain open, since neither blocks v1 work.
> **Human decisions, 2026-07-30:**
> - **OQ-24 — v1 scope confirmed as written.** No app rebuild required, but a new format still
>   goes through a rule author for review before shipping — the "faster iteration, on-device
>   derivation now" alternative was explicitly declined given the money-correctness risk.
> - **OQ-25 — samples stay private to this team.** A shared/community pack repository is
>   explicitly deferred; do not design US-J2 around it.
> - **OQ-27 — the sender must be linked as a known bank (US-A6) before its message type can be
>   declared (US-J1).** No "declare type first, link bank later" path in v1.
> It does **not** reopen gate 1 for the rest of the document, and it must
> **not** interrupt the in-flight rule-writing for the human's seven real banks (KHA-128 and its
> follow-ups), which remains the higher priority.
>
> **Why this exists.** Getting seven banks working on 2026-07-30 required an engineer to read the
> human's real message previews off their phone, describe the structure by hand, write regex, and
> ship a new APK. The human's request: *"we will have to give the user the cap to do this too…
> adding SMSs structure and banks names too… if it is something require a new build each time then
> we should allow the user to do it himself."* Addendum A solved this one layer up (*which senders
> are banks*). Addendum B is the next layer down: *what does this message say, and where.*
>
> **The tension, and how it is resolved.** **X18 (approved) forbids exposing pattern/regex
> authoring to the user, and X18 stands unamended.** Its reasoning is correct and Addendum B does
> not override it: a wrong extraction pattern silently corrupts a real amount, and user-supplied
> expressions are the executable-input surface ADR-007 deliberately has none of. What Addendum B
> establishes is that **the human's complaint and X18 are not actually in conflict**, because the
> complaint has two halves and only one of them needs pattern authoring:
>
> 1. *"A new build every time"* — **this half is already false, and v1 makes it visibly false.**
>    ADR-007 already supports **imported rule packs** installed by the user through the file
>    picker, with a reviewed diff and no APK reinstall. Today that capability exists and the user
>    has never been shown it. Closing that loop (US-J3) plus a one-tap way to hand a redacted
>    sample to whoever writes the rule (US-J2) removes the app release from the cycle entirely.
>    What remains is a round trip to a rule author — slower per format, but every regex that ever
>    touches a real amount stays reviewed and fixture-tested.
> 2. *"The app can't even tell what type of message this is"* — **this half needs no patterns at
>    all**, and it is the part the user is genuinely authoritative on. The user knows a refund is a
>    refund. US-J1 lets them say so, which fixes the sign/affects-spend correctness of every
>    hand-completed transaction. (Separate from, and complementary to, **KHA-146**, which is a bug:
>    fields the parser *did* extract are being thrown away before the completion form. Fix that bug
>    and add US-J1 and the completion flow becomes a short confirmation rather than full retyping.)
>
> **On deriving a rule from labeled examples (the deferred half, US-J4–J6).** Option (a) —
> auto-derive a rule from one labeled example and trust it — is **rejected outright**. Option (b)
> — export the example so an engineer writes a reviewed rule from it — is **v1**. Option (c) — a
> candidate rule that must be confirmed on repeated messages before it is trusted — is the
> **recommended eventual mechanism, deferred**, because it is real work carrying real risk and the
> human's immediate need is served without it. The reasoning that must survive into that later
> phase, stated now so it is not re-litigated from optimism:
>
> - **A whole-message positional regex derived from one example is not safely derivable.** Anything
>   the user did not label stays literal, so a varying field they did not think to label (a running
>   balance, a reference number) makes the rule match exactly one message forever. That failure is
>   *safe* (no match → review queue) but useless. The dangerous failure is the opposite: an
>   over-general anchor. "The first number in the message" extracts the card suffix as the amount
>   on the very next message, and says nothing.
> - **A narrow structural anchor is more derivable than a regex, but only with two hard rules.**
>   "The amount is the number adjacent to `SAR`/`ريال`" survives different merchant lengths, amounts
>   and dates, which a positional regex does not. It is only safe if **(i)** an anchor occurring
>   more than once in the source example is refused rather than guessed at, and **(ii)** a rule
>   producing more than one candidate value for a field on a later message extracts **nothing** and
>   sends that message to review. Ambiguity must fail closed. Both are ACs below.
> - **The genuinely underivable part is semantics, not position.** Whether a message is a purchase
>   or a refund decides whether an amount is *added to* or *subtracted from* a total — an error of
>   twice the amount. Bank formats for the two differ by a single word, and `sa-core.json`'s own
>   rule-ordering notes show an engineer had to reason explicitly about it. **No amount of field
>   highlighting expresses that.** So sign and affects-spend are never derived: they come from the
>   user's declared type (US-J1), which is why US-J1 is the foundation of the deferred phase as
>   well as being valuable on its own.
> - **A self-taught rule is held to a stricter bar than merchant categorization (ADR-008).** A
>   wrong category is annoying; a wrong amount is a wrong number in a real total. So a learned
>   format never auto-applies until confirmed on repeated messages, an extraction correction
>   demotes it, a second correction disables it, a bundled/imported pack rule always outranks it,
>   and every transaction it produces names it in provenance (**NFR-A1a**) — which is also the
>   answer to the objection that killed the on-device-classifier option in ADR-007: *weights have
>   no `ruleId`.* A learned format does.

---

## 1. Problem Statement

### The pain
The user (a single individual) spends across multiple credit cards and bank accounts. Each institution notifies them of a transaction by SMS, but those SMS messages are the only record they see day to day. The result:

- Transactions live scattered in a phone's SMS inbox, mixed in with OTPs, marketing, and non-financial messages.
- There is no running total of spending — per card, per month, or per category.
- Working out "how much did I spend on groceries this month" requires manually scrolling through raw SMS text.
- Bank apps show one institution each; nothing aggregates across cards.
- Manually categorizing every transaction in a spreadsheet or a generic budgeting app is tedious enough that the user stops doing it, so the data goes stale and becomes useless.

### The business/personal goal
Give the user a single, automatic, always-current view of their spending, built from the SMS notifications they already receive — with categorization that requires correction *once* per merchant and then keeps itself right. Success means the user opens the app and trusts the numbers without having done manual data entry.

### Definition of success
This is a personal tool, so success is measured against the user's own behaviour, not market metrics:

- The user can answer "what did I spend this month, and on what?" in under 10 seconds, without opening a bank app.
- After an initial learning period, the large majority of new transactions arrive already correctly categorized (exact target is an Open Question — see OQ-14).
- The user does not abandon the app because upkeep is too manual.

### Non-goals of this product
It is not a budgeting coach, not a bank replacement, not a payments app, and not something anyone other than the user will run.

---

## 2. Target Users / Personas

### Persona 1 — "The Owner" (primary and only persona)
The founder/sole user of the app.

| Attribute | Detail |
|---|---|
| Role | Individual consumer; owner, operator, and only user of the app |
| Technical level | Comfortable with software; not necessarily wanting to do data entry |
| Devices | A smartphone that receives bank/card SMS (OS is an Open Question — OQ-1) |
| Financial setup | Multiple credit cards and/or bank accounts, each sending SMS alerts |
| Motivation | Awareness and control over spending; avoid surprises at statement time |
| Frustration | Categorizing the same merchant over and over again |
| Success looks like | Opens app, sees this month's spend broken down by category and by card, and it is right |

### Secondary "personas" that are explicitly NOT targeted
- Family members / shared household accounts — out of scope (see §6).
- Accountants, advisors, or any third-party viewer — out of scope.
- Multi-tenant SaaS customers — out of scope. There is no signup, no tenancy model, no other user's data in the system.

> **Note for later phases:** even though there is one user, the banking-domain requirements in §7 still apply in full. Single-user does not mean low-sensitivity — this app holds a complete, timestamped record of one person's financial life.

---

## 3. Scope

### 3.1 In scope (v1)

| # | Capability |
|---|---|
| C1 | Ingest incoming SMS messages on the device and identify which ones are financial transaction notifications |
| C2 | Parse a transaction SMS into structured fields (amount, currency, merchant/payee, card/account identifier, date-time, transaction type) |
| C3 | Store transactions locally and present them as a reviewable list |
| C4 | Track balances/spend per card or account, so the user sees spending broken down by instrument |
| C5 | Assign a spending category to every transaction |
| C6 | Let the user correct a category manually |
| C7 | Learn from corrections so the same merchant/payee is auto-categorized correctly on subsequent transactions, without re-tagging |
| C8 | Show spending summaries — by month, by category, by card |
| C9 | Flag transactions the app could not parse or could not confidently categorize, so nothing is silently lost |
| C10 | Let the user add a transaction manually (for cash or non-SMS spending) |
| C11 | Let the user edit or delete a transaction, with an audit trail of the change |
| C12 | Support multiple currencies: record each transaction's native currency and convert to a base currency for combined totals |
| C13 | Let the user set a monthly budget per category (and optionally overall) and receive an alert when it is reached/exceeded |
| C14 | Import a bank statement (PDF/CSV) and reconcile it against SMS-derived transactions, adding any that were missed and feeding the learning loop |
| C15 | Capture non-spending money movement from SMS too — income/salary credits, ATM withdrawals, and transfers between the user's own accounts — so the app shows total spent vs. total kept, not just card spend. Transfers between the user's own accounts must never be counted as spending. |
| C16 | Cloud backup/sync of the (small) local dataset, so data survives a lost/replaced device |
| C17 | **`[Addendum A — APPROVED]`** Let the user declare that SMS from a sender the app does not recognize are from one of their banks (naming that bank if it is new), so a bank the app was never configured for — or one that changed its sender ID — starts being tracked without waiting for a new app version |
| C18 | **`[Addendum B — APPROVED]`** Let the user state what *kind* of transaction an unreadable message describes (purchase, refund, transfer between own accounts, deposit, withdrawal, fee, bill payment), so a hand-completed transaction lands with the right sign and the right effect on totals without the user having to reason about which way it goes |
| C19 | **`[Addendum B — APPROVED]`** Let the user hand a redacted sample of a message the app cannot read to whoever writes parsing rules, in one reviewed tap, and install the resulting rule pack themselves — so a new bank or a changed message format reaches them **without a new app release** |

### 3.2 Out of scope (v1) — explicitly

These are deliberately excluded. Some may return in a later version; none should be built now.

| # | Excluded | Rationale |
|---|---|---|
| X1 | Multi-user / multi-tenant support, accounts, login-with-email, sharing | Personal app for one person |
| X2 | Direct bank API / open-banking / aggregator integration (Plaid-style) | The idea is explicitly SMS-driven; direct integration is a different product |
| X3 | Screen-scraping bank apps or websites, or email-parsing of bank statements | Not part of the stated idea (email is a candidate for v2 — see OQ-9) |
| X4 | Initiating any payment, transfer, or card action | Read-only observability tool. Never touches money. |
| X6 | Bill reminders / due-date tracking / autopay management | Follow-on feature |
| X7 | Investment, net-worth, loan-amortization, or savings-goal tracking | Different problem |
| X8 | Tax reporting or export to tax software | Follow-on feature |
| X9 | Receipt photo capture and OCR | Follow-on feature |
| X12 | Predictive/forecast features ("you'll spend X by month end") | Follow-on feature |
| X13 | Any monetization, ads, analytics SDK, or third-party telemetry | Personal app; and hostile to the privacy posture in §7 |
| X14 | Support for SMS formats from banks the user does not personally use | Scope is bounded by the user's own institutions (see OQ-2) |
| X15 | Email or push-notification-based transaction capture | Confirmed out — SMS is the only ingestion channel (was OQ-9) |
| X16 | Publishing to an app store | Personal side-load (APK install) only for now (was OQ-4) |
| X17 | Hard, non-recoverable delete of a single transaction from the UI | Deletes are soft/hidden by default so a mistaken delete is recoverable; only "erase everything" (US-F3) is a true hard delete (was OQ-8) |
| X18 **`[Addendum A — APPROVED]`** | A rule-authoring UI — letting the user write or edit sender/message patterns, message templates, or field-extraction mappings | C17 deliberately stops at *sender recognition*. Once a sender is recognized, the already-built unparsed queue (US-A4) plus manual completion (AC-A4.2) turn its messages into transactions with no pattern-writing at all. Authoring parsing rules is a specialist task, it is where a wrong guess silently corrupts amounts, and user-supplied patterns would be an executable-input surface the rule-pack design deliberately has none of. Keeping **rule content** an engineering data task (KHA-128) is the right split |
| X19 **`[Addendum A — APPROVED]`** | A persisted "not my bank / ignore this sender" list | The unrecognized-sender list is shown only on demand, so there is nothing nagging the user that needs suppressing — and persisting it would mean storing metadata about senders the user has just confirmed are *not* financial, which is exactly what NFR-P4 exists to prevent. Revisit only if the list proves noisy in real use |
| X18a **`[Addendum B — APPROVED]`** | Any UI that shows the user a regular expression, pattern, template, expression language, or field-extraction mapping **to write, paste, or edit** — in v1 or in any deferred phase | *Boundary clarification, not a relaxation — **X18 stands unamended.*** What X18 does **not** forbid, and what Addendum B relies on, is the user (a) **stating a fact about their own message** ("this is a refund" — C18/US-J1), (b) **handing a redacted copy of their own message to a rule author** (C19/US-J2), and (c) in a deferred phase, **pointing at where a value sits inside their own message** (US-J4). In all three the user supplies *data about a message*, never an expression; the app or a reviewed rule author converts it. If any design ever puts a pattern in front of the user for editing, it has left this addendum's scope and needs its own approval |
| X20 **`[Addendum B — APPROVED]`** | On-device derivation of extraction rules from user-labeled examples — **US-J4, US-J5, US-J6**. **DEFERRED, not permanently excluded** | Specified below (stories and ACs) so the safety constraints are settled while the reasoning is fresh, and so a later `/design` round has something concrete to architect against. Deferred because: the immediate scaling pain is discharged by C19 (no app release needed), the immediate correctness pain is discharged by C18 plus the KHA-146 bug fix, and five of the seven configured banks currently have **no message samples at all** — so the binding constraint today is *samples*, not *tooling*. Building the harder, riskier half first would be the wrong order. Re-open trigger: **OQ-28** |
| X21 **`[Addendum B — APPROVED]`** | Any shared, crowd-sourced, community, or public repository of rule packs or message samples | NFR-C5 forbids exposing bank SMS content to third parties, and CON-1 means there is no account system to attribute or moderate contributions. A one-to-one hand-off to a known rule author (US-J2) is a different act from publishing to a repository, and only the former is in scope. Revisit only as a deliberate, separately approved decision — see **OQ-25** |

> **Moved from out-of-scope to in-scope (v1)** following human review: budgets/alerts (was X5, now C13), cloud backup/sync (was X10, now C16), statement PDF/CSV reconciliation (was X11, now C14).

### 3.3 Assumptions this PRD makes
These are stated so they can be challenged, not treated as decided facts:

- A1 — The user's banks/card issuers do send transaction SMS, and those SMS contain at minimum an amount and some merchant/payee identifier. **Needs confirmation with real (redacted) samples from Saudi Arabian banks/card issuers — user has committed to providing 20–50 — see OQ-2.**
- A2 — The user is willing to grant the app access to their SMS inbox on the device. **Confirmed feasible in principle: platform is Android, built in Flutter, installed as a side-loaded APK (not published to a store) — see OQ-1/OQ-3/OQ-4 resolution in §8. Actual runtime SMS-permission behaviour on the target Android version still needs to be verified during build.**
- A3 — The app runs on the same device that receives the SMS.
- A4 — SMS are in Arabic and/or English (Saudi Arabia); the UI must support right-to-left layout.

Nothing else about the target market, bank list, formats, or platform is assumed. Where a decision is missing, it appears in §8 rather than being invented here.

### 3.4 Observed SMS format patterns (from user-provided samples, redacted here)

The user shared real sample SMS from two Saudi banks (Bank Aljazira, D360) to unblock OQ-2. The raw text is intentionally **not reproduced in this document** (NFR-M3 — genuine bank SMS must not be committed to a repository); it should be turned into synthetic, realistic-but-fake fixtures during phase 4/7 build. The structural patterns observed, which the app must handle, are:

| Pattern observed | Implication |
|---|---|
| Same two banks produce **structurally different messages per transaction type** — POS purchase, online purchase, outgoing transfer, incoming transfer (including salary), bill payment, credit-card repayment, a standalone fee/VAT debit, and a loan/finance installment deduction all have distinct field sets and keywords. | Parsing cannot be one generic template; it needs a per-bank, per-message-type rule set (NFR-M1) — a build-phase design concern, not decided here. |
| One bank's messages are fully Arabic with Arabic field labels; the other bank's are fully English; merchant names appear in Latin transliteration even inside Arabic messages. | Confirms A4 (Arabic + English + RTL) and that merchant text itself may already be Latin-script even in an Arabic SMS — categorization matching must not assume one script. |
| Some messages state only **SAR**, some state a **foreign currency with an inline SAR-converted amount and an FX/international fee**, and one format shows the converted amount in parentheses after the foreign amount. | Confirms C12/US-B9 (multi-currency) is real, not hypothetical, and that a "fee" component can ride alongside the transaction amount — needs its own field, not folded into the spend amount. |
| Transaction types beyond simple purchases appear: outgoing/incoming transfers (with counterparty name, counterparty bank, and a transaction reference number), bill payments (with a biller code and invoice number), credit-card repayment from a linked account, a bare VAT fee debit, a bare "debited from account" message with almost no other detail, and a loan/finance installment deduction that also reports a remaining balance. | Validates C15 (non-spending capture), US-B14 (card-to-account linkage — repayment messages name both the card and the source account), and suggests "loan/finance installment" may need its own category distinct from general spending (feeds OQ-18's default category list in phase 3). |
| Instrument identifiers appear in different forms: a masked card number with an explicit network/type (e.g. a credit card, or a debit card tagged with a scheme), and a bare account number with no network — appearing in the *same* bank's messages depending on transaction type. | Directly confirms the bank/account/card hierarchy requested (US-B12/B13): the same underlying relationship (account funds card) is visible in real messages, e.g. a card repayment message names both the card and the debiting account. |
| A transaction reference/ID number is present in some message types (notably transfers) but not others. | Where present, it should be captured for duplicate-suppression (US-A5) and traceability (NFR-A1); where absent, dedup must fall back to the existing amount/time/sender heuristic. |

---

## 4. User Stories

Stories are grouped by capability area, kept small, and each is independently testable. IDs are stable and should be referenced by the manager, designer, engineers, and QA in later phases.

### Epic A — SMS ingestion and transaction detection
- **US-A1** — As the Owner, I want the app to read incoming SMS messages on my phone so that I don't have to enter transactions by hand.
- **US-A2** — As the Owner, I want the app to tell financial transaction SMS apart from OTPs, marketing, and personal messages so that my spending list isn't polluted with noise.
- **US-A3** — As the Owner, I want the app to import my existing SMS history on first run so that I have spending data from day one instead of starting empty.
- **US-A4** — As the Owner, I want SMS the app couldn't understand to be shown in an "unparsed" area rather than silently dropped so that I know nothing is missing.
- **US-A5** — As the Owner, I want the app to ignore duplicate SMS for the same transaction so that my totals aren't inflated.
- **US-A6** **`[Addendum A — APPROVED]`** — As the Owner, I want to tell the app that messages from a sender it doesn't recognize are from one of my banks, so that a bank the app was never configured for (or one that changed its sender ID) starts being tracked without waiting for a new version of the app.
  > *Why this exists, in one paragraph, because it is the justification for the whole story:* the app decides "is this SMS from a bank?" by matching the sender string against patterns shipped inside the app. Whoever writes those patterns is guessing at a string they cannot see; the person holding the phone can read the exact string with zero guesswork. On 2026-07-30 that guess was wrong for both configured banks and absent for five more (KHA-128), and because an unmatched sender is discarded with nothing retained, the user saw `0.00 SAR` with nothing in the review queue either and no way to tell the app it was wrong. This is the same philosophy as the merchant-learning loop (US-D1–D5) — *the user corrects what the app got wrong and it sticks* — applied one layer up, at the bank/sender layer instead of the merchant/category layer. It does **not** replace shipping correct patterns (KHA-128); it means the *next* wrong or changed sender ID costs the user thirty seconds instead of costing them an app release.

### Epic B — Banks, accounts, cards, and the transaction record
- **US-B1** — As the Owner, I want each detected transaction to show amount, currency, merchant/payee, date-time, and which account/card it hit so that I can identify it at a glance.
- **US-B2** — As the Owner, I want my accounts and cards grouped under the bank that issued them so that I can see spending per bank, not just per instrument.
- **US-B3** — As the Owner, I want to give an account or card a friendly name (e.g. "Blue Visa", "Salary Account") so that I don't have to recognize it by trailing digits.
- **US-B12** — As the Owner, I want each bank I use recognized as its own entity with its own page so that I can see everything at that bank — its debit/current accounts and its cards — in one place.
- **US-B13** — As the Owner, I want debit/current accounts tracked as their own instrument type, separate from cards, under each bank, so that "money sitting in my account" and "credit card spend" don't get conflated.
- **US-B14** — As the Owner, I want a card recognized as belonging to the account that funds/settles it (where the SMS indicates that link, e.g. a credit card repayment debited from an account) so that the app understands the real money flow between my account and my card, not just two unrelated instruments.
- **US-B15** — As the Owner, I want a new bank, account, or card to be created automatically the first time an SMS mentions it (bank identified from the SMS sender/content), so that I don't have to pre-register my accounts and cards by hand.
- **US-B16** **`[Addendum A — APPROVED]`** — As the Owner, I want to give a bank the name I actually call it, so that my bank list reads the way I think about my money rather than however the app or the SMS spelled it. *(This is the "edit bank names" half of the human's 2026-07-30 request; US-A6 is the "add" half. It is the bank-level equivalent of US-B3, which only covers accounts and cards.)*
  > **ID note for whoever raises `docs/design.md` §10 D-13's recommended story** (a formal story for the S-48/S-49 manual add-account/add-card screens): `US-B16` is now taken — use **US-B17**.
- **US-B4** — As the Owner, I want to add a transaction manually so that cash spending and non-SMS purchases are included in my totals.
- **US-B5** — As the Owner, I want to edit a transaction's details when the parser got something wrong so that my records are accurate.
- **US-B6** — As the Owner, I want to delete or exclude a transaction (e.g. a reversed charge) so that my totals reflect reality.
- **US-B7** — As the Owner, I want refunds/reversals/credits to reduce my spending rather than add to it so that my totals are correct.
- **US-B8** — As the Owner, I want a deleted transaction to move to a hidden/recently-deleted view instead of being destroyed, and be able to restore it, so that a mistaken delete isn't permanent.
- **US-B9** — As the Owner, I want each transaction to carry its native currency, and totals to convert to a base currency, so that spending in a different currency doesn't distort or get excluded from my summaries.
- **US-B10** — As the Owner, I want non-spending money movements — salary/income credits, ATM withdrawals, and transfers between my own accounts — captured from SMS too, so that I can see total spent vs. total kept, not just card charges.
- **US-B11** — As the Owner, I want transfers between my own accounts to never be counted as spending so that moving money to myself doesn't inflate my spend totals.

### Epic C — Categorization
- **US-C1** — As the Owner, I want every transaction to carry a spending category so that I can see where my money goes.
- **US-C2** — As the Owner, I want to change a transaction's category in one or two taps so that correcting the app is not a chore.
- **US-C3** — As the Owner, I want to create my own categories so that the breakdown matches how I actually think about my spending.
- **US-C4** — As the Owner, I want transactions the app is unsure about to be visibly flagged for review so that I know which ones to check.
- **US-C5** — As the Owner, I want to bulk-categorize a group of similar uncategorized transactions so that catching up after a while isn't painful.

### Epic D — Learning loop
- **US-D1** — As the Owner, I want the app to remember that a given merchant belongs to a given category after I set it once so that I never tag the same electric utility twice.
- **US-D2** — As the Owner, I want that memory applied automatically to future transactions from the same merchant so that new charges arrive already categorized.
- **US-D3** — As the Owner, I want a correction to override any earlier guess for that merchant so that the app follows my latest decision, not its own.
- **US-D4** — As the Owner, I want to see and edit the merchant-to-category rules the app has learned so that I can fix a bad rule directly instead of correcting transaction after transaction.
- **US-D5** — As the Owner, I want to choose whether a correction applies only to this transaction or to all past and future ones from that merchant so that a one-off (e.g. a supermarket purchase that was actually a gift) doesn't corrupt the rule.

### Epic E — Insight and reporting
- **US-E1** — As the Owner, I want a current-month total spend so that I know where I stand right now.
- **US-E2** — As the Owner, I want spending broken down by category for a chosen period so that I can see what's driving the total.
- **US-E3** — As the Owner, I want spending broken down by card for a chosen period so that I can see which card I'm leaning on.
- **US-E4** — As the Owner, I want to compare this month against previous months so that I can tell if I'm trending up.
- **US-E5** — As the Owner, I want to search and filter my transactions (by merchant, amount range, date, category, card) so that I can find a specific charge.

### Epic F — Data control, privacy, and trust
- **US-F1** — As the Owner, I want my financial data protected behind device authentication so that anyone picking up my unlocked phone can't browse my spending.
- **US-F2** — As the Owner, I want to export all my data so that I'm not locked in and can back it up.
- **US-F3** — As the Owner, I want to delete all my data permanently so that I can wipe the app if I stop using it or lose the device.
- **US-F4** — As the Owner, I want to know exactly what data leaves my device (if anything) so that I can trust the app with my bank SMS.
- **US-F5** — As the Owner, I want a history of changes to a transaction (what was auto-detected vs what I edited) so that I can trace why a number is what it is.

### Epic G — Budgets and alerts
- **US-G1** — As the Owner, I want to set a monthly budget for a category so that I have a target to track against.
- **US-G2** — As the Owner, I want to set an overall monthly spending budget so that I can track total spend against a single limit.
- **US-G3** — As the Owner, I want to be alerted when a category or overall budget is reached or exceeded so that I find out during the month, not after.
- **US-G4** — As the Owner, I want to see how close I am to each budget at a glance so that I can adjust behaviour before I go over.

### Epic H — Statement reconciliation
- **US-H1** — As the Owner, I want to import a bank statement (PDF or CSV) so that transactions my SMS never captured are added.
- **US-H2** — As the Owner, I want the app to show me which statement entries didn't match an existing SMS-derived transaction so that I know exactly what was added or is still missing.
- **US-H3** — As the Owner, I want a transaction added via statement reconciliation to go through the same categorization/learning flow as an SMS-derived one so that it's treated consistently.

### Epic I — Backup and sync
- **US-I1** — As the Owner, I want my data backed up to the cloud so that I don't lose it if I lose or replace my device.
- **US-I2** — As the Owner, I want backed-up data encrypted so that a cloud account compromise doesn't expose my financial history in the clear.
- **US-I3** — As the Owner, I want to restore my data on a new device from the backup so that switching devices doesn't mean starting over.

### Epic J — Teaching the app a message format `[Addendum B — APPROVED]`

*Scope guard for the whole epic, and it is the point of the design: the user states facts about
their own messages and points at their own text. **The user never writes, pastes, or edits a
pattern, regex, template, or field mapping** (X18, X18a) — in v1 or in any deferred phase.*

**In v1 (three stories):**

- **US-J1** — As the Owner, I want to tell the app what kind of transaction a message describes when it completes one by hand, so that a refund reduces my spending instead of increasing it and a transfer to myself isn't counted as spending at all — without me having to work out which way the sign goes.
- **US-J2** — As the Owner, I want to hand a redacted copy of a message my app can't read to whoever writes the parsing rules, in one tap and after seeing exactly what I'm sending, so that getting my bank supported doesn't depend on someone scrolling through my phone with me.
- **US-J3** — As the Owner, I want to install an updated parsing rule pack myself and immediately see what it can now read, so that a new bank or a changed message format reaches me **without waiting for a new version of the app**.
  > *This is the story that actually answers the human's "does this require a new build each time?"* — and the answer is **no, and it already didn't**. ADR-007 has supported user-imported rule packs (file picker, human-readable diff, explicit confirmation, no APK reinstall) since v1.0 of the architecture. What has never existed is a user-facing loop that makes it usable: no way to see what the new pack changed for *your* data, and no prompt to re-check your banks afterwards. US-J3 is mostly wiring an existing capability to the AC-A6.10 "check again" mechanism, which is why it is cheap and why it belongs in v1.

**Deferred to a later phase (three stories) — specified now, not authorised now (X20):**

- **US-J4** — As the Owner, I want to point at the parts of one of my own unreadable messages and say "this is the amount, this is the merchant, this is the date", so that the app can learn the shape of that message without me writing anything technical.
- **US-J5** — As the Owner, I want a format I've just taught the app to ask me to confirm it on the next few messages before it starts filling things in on its own, so that a format I taught it wrong is caught on the second message rather than silently corrupting three months of totals.
- **US-J6** — As the Owner, I want to see every format I've taught the app in plain language, and turn one off or delete it, so that a format that turns out to be wrong is one tap to stop rather than something I have to keep correcting transaction by transaction.

---

## 5. Acceptance Criteria

Written as Given/When/Then so QA can automate them directly. Each criterion is scoped to one story. Where a value is undecided, the criterion references an Open Question rather than inventing a number — QA should not automate those until the OQ is resolved.

### Epic A — SMS ingestion

**US-A1 — Read incoming SMS**
- AC-A1.1 — **Given** the app has been granted SMS access and is open, unlocked, and in the foreground, **when** a new SMS arrives from a configured financial sender, **then** the app processes it and a corresponding transaction appears in the transaction list within single-digit seconds and without any user action — **including when the app simply stays open and is never backgrounded and resumed.** *(Clarification added 2026-07-30 after a device-found gap — KHA-122. This is not a scope change: NFR-R1's human-approved "single-digit seconds while unlocked" already required it. The app-not-in-foreground and locked cases remain AC-A1.4 / NFR-R1.)*
- AC-A1.2 — **Given** the app has NOT been granted SMS access, **when** the user opens the app, **then** the app shows a clear explanation of why access is needed and a way to grant it, and does not show an empty state with no explanation.
- AC-A1.3 — **Given** SMS access was granted and then revoked in device settings, **when** the user opens the app, **then** the app warns that ingestion has stopped and previously captured data is still intact.
- AC-A1.4 — **Given** a new SMS arrives while the app is not in the foreground, **when** the user next opens the app, **then** that transaction is already present. *(Background-processing feasibility depends on OQ-3.)*

**US-A2 — Distinguish financial SMS from noise**
- AC-A2.1 — **Given** an SMS containing a one-time passcode from a bank sender, **when** it is processed, **then** no transaction is created.
- AC-A2.2 — **Given** a marketing/promotional SMS from a bank sender (e.g. a loan offer), **when** it is processed, **then** no transaction is created.
- AC-A2.3 — **Given** an SMS from a non-financial sender (a person, a delivery service), **when** it is processed, **then** no transaction is created.
- AC-A2.4 — **Given** a genuine purchase-notification SMS from a configured financial sender, **when** it is processed, **then** exactly one transaction is created.
- AC-A2.5 — **Given** a balance-enquiry or informational SMS that states a balance but reports no purchase, **when** it is processed, **then** no spending transaction is created.

**US-A3 — Historical import**
- AC-A3.1 — **Given** the user completes first-run setup with SMS access granted, **when** the app performs its initial import, **then** transaction SMS already in the inbox from the start of the current calendar month onward are parsed into transactions (confirmed lookback — was OQ-11).
- AC-A3.2 — **Given** an initial import is running over a large inbox, **when** the user views the app, **then** progress is shown and the app remains responsive.
- AC-A3.3 — **Given** an initial import is interrupted (app closed, device restart), **when** the app next runs, **then** the import resumes or restarts without creating duplicate transactions.

**US-A4 — Unparsed SMS are surfaced, not dropped**
- AC-A4.1 — **Given** an SMS is judged financial but cannot be parsed into a complete transaction, **when** processing finishes, **then** it appears in a "Needs review / unparsed" list with its original text visible.
- AC-A4.2 — **Given** an unparsed SMS in the review list, **when** the user fills in the missing fields manually, **then** a normal transaction is created and the item leaves the review list.
- AC-A4.3 — **Given** an unparsed SMS in the review list, **when** the user dismisses it as not-a-transaction, **then** it is removed from the list and does not reappear on re-scan.
- AC-A4.4 — **Given** any SMS is processed, **when** it is neither converted to a transaction nor placed in the review list, **then** this is a defect — no financial SMS may be discarded without a trace.

**US-A5 — Duplicate suppression**
- AC-A5.1 — **Given** the identical SMS is delivered twice (carrier retry), **when** both are processed, **then** exactly one transaction exists.
- AC-A5.2 — **Given** two SMS from two different senders describe the same underlying transaction (e.g. an authorization alert and a posting alert for the same charge), **when** both are processed, **then** the app flags them as a possible duplicate for user confirmation rather than silently merging or silently double-counting.
- AC-A5.3 — **Given** two genuinely separate purchases at the same merchant, for the same amount, on the same day, **when** both are processed, **then** both transactions are retained (they may be flagged as possible duplicates, but must not be auto-removed).

**US-A6 — Recognize a sender the app was never configured for `[Addendum A — APPROVED]`**

*Scope guard for the whole block: the user names banks and identifies senders. The user never writes, pastes, or edits a pattern, template, or field mapping (X18).*

- AC-A6.1 — **Given** the app has SMS access, **when** the user opens the "Banks & senders" screen (reachable from Settings, and linked from Home's zero/empty state and from an empty Needs Review queue), **then** it lists, in two clearly separated groups, (a) the senders in the current lookback window that the app **does** recognize and (b) the senders it does **not**, each shown as the exact sender string as it appears on the phone, with a count of messages from it in that window — so that "the app is finding nothing" and "the app is not recognizing my bank" are distinguishable by the user without help.
- AC-A6.2 — **Given** an unrecognized sender whose string alone does not identify it (e.g. a short code), **when** the user taps that one sender, **then** the app shows a redaction-applied preview of at most its single most recent message so the user can decide; the preview is not persisted, and no other sender's content is shown.
- AC-A6.3 — **Given** an unrecognized sender the user identifies as one of their banks, **when** they link it either to a bank the app already knows or to a new bank they name themselves, **then** messages from that sender are treated as financial from that point on, and the link is recorded in the audit trail (NFR-A2) as a user action.
- AC-A6.4 — **Given** the user has just linked a sender, **when** the link is saved, **then** the app re-scans that sender's existing messages over the same lookback window as the initial import (AC-A3.1), and every one of them ends as either a parsed transaction or an item in the Needs Review queue — never discarded (NFR-A7, AC-A4.4).
- AC-A6.5 — **Given** a linked sender whose message format no rule in any active rule pack can parse, **when** its messages are processed, **then** they appear in the Needs Review / unparsed list with their sanitized text and can be completed into real transactions through the existing flow (AC-A4.1, AC-A4.2). **The user gets value from a linked sender without any parsing rule ever being written for it.**
- AC-A6.6 — **Given** the user supplies or confirms a sender string, **when** it is stored and matched against incoming messages, **then** it is matched **literally** — whole-string, case-insensitive, surrounding whitespace trimmed — and is never interpreted as a regular expression or any other executable expression.
- AC-A6.7 — **Given** the user linked sender S to bank B, **when** a later rule-pack update adds its own pattern matching S for that same bank, **then** messages from S still resolve to the single bank B — no second bank entity, no split totals, no duplicated accounts or cards — and the pack's parsing rules now take effect for those messages.
- AC-A6.8 — **Given** a linked sender, **when** the user removes the link, **then** future messages from that sender stop being ingested, and transactions already created from it are retained unchanged with their provenance intact (they are real records of real money, not artefacts of the link).
- AC-A6.9 — **Given** unrecognized senders the user chooses **not** to link, **when** they leave the screen, **then** nothing about those senders or their messages has been persisted anywhere — the list is derived on demand and NFR-P4's discard behaviour is unchanged (NFR-P4a).
- AC-A6.10 — **Given** a linked bank whose messages currently can't be auto-parsed (AC-A6.5), **when** the user views that bank's entry (e.g. after the app has been updated with new parsing rules), **then** they can trigger "check again" on demand, which re-scans that sender's messages the same way AC-A6.4 does at link time, without needing to unlink and re-link. The bank's entry also states plainly when nothing from it could be auto-parsed yet (per OQ-22's resolution below), rather than relying on the user to infer this from an empty-looking Needs Review queue.
- AC-A6.11 — **Given** a well-established install (Home is not in an empty state, the review queue is not empty), **when** a sender the app previously recognized stops matching (e.g. the bank silently changes its sender ID) or a genuinely new bank starts messaging the user, **then** the app does not rely on an empty-state link alone (AC-A6.1) to surface it — the count of currently-unrecognized senders is also shown as a standing row in the Settings → Diagnostics parser-health panel (ADR-015), so the "month-eight silent drift" case is discoverable the same way the "day-one everything is empty" case is. *(Gap identified by solution-architect's 2026-07-30 assessment: Addendum A as originally scoped only surfaced this via empty states, which are true only near first run.)*

### Epic B — Transaction record and cards

**US-B1 — Transaction fields**
- AC-B1.1 — **Given** a successfully parsed purchase SMS, **when** the user opens the transaction, **then** amount, currency, merchant/payee, date-time, card/account identifier, and transaction type are all displayed.
- AC-B1.2 — **Given** a parsed transaction, **when** the user opens its detail view, **then** the original SMS text is viewable so the user can verify the parse.
- AC-B1.3 — **Given** a parsed transaction where one optional field was absent from the SMS, **when** it is displayed, **then** the missing field is shown as explicitly unknown rather than blank, zero, or guessed.
- AC-B1.4 — **Given** any parsed transaction, **when** it is displayed, **then** the amount matches the amount in the source SMS exactly, including decimal precision, with no rounding.

**US-B2 — Bank-grouped instruments**
- AC-B2.1 — **Given** transactions from accounts/cards at two different banks, **when** the user views the banks screen, **then** each bank is listed with its own totals, and drilling into a bank shows only its own accounts/cards.
- AC-B2.2 — **Given** transactions from two different cards at the same bank, **when** the user views that bank's page, **then** both cards are listed separately with their respective totals for the selected period.
- AC-B2.3 — **Given** the user selects one instrument (account or card), **when** they view its detail, **then** only that instrument's transactions are listed and the total equals the sum of those transactions for the period.

**US-B3 — Friendly names**
- AC-B3.1 — **Given** an auto-created account or card shown by its raw identifier, **when** the user renames it, **then** the new name appears everywhere that instrument is referenced.
- AC-B3.2 — **Given** a renamed account or card, **when** a new SMS arrives with that instrument's raw identifier, **then** the transaction is attached to the renamed instrument, not to a new one.

**US-B12 — Bank as an entity**
- AC-B12.1 — **Given** SMS from a bank the app has not seen before arrive, **when** they are processed, **then** a new bank entity is created (identified from sender/message content) and the account or card mentioned is placed under it.
- AC-B12.2 — **Given** the user opens a bank's page, **when** it renders, **then** it lists that bank's accounts and cards as two distinguishable groups, plus a combined total for that bank.
- AC-B12.3 — **Given** two SMS reference the same bank using different naming (e.g. Arabic name in one message, an abbreviation in another), **when** both are processed, **then** they resolve to the same bank entity, not two.

**US-B13 — Accounts vs. cards**
- AC-B13.1 — **Given** an SMS whose fields describe a debit/current account (e.g. an account number with no card network), **when** it is processed, **then** the instrument is created/matched as an "account" type, not a "card" type.
- AC-B13.2 — **Given** an SMS whose fields describe a card (card number plus a network such as Visa/mada/credit), **when** it is processed, **then** the instrument is created/matched as a "card" type.
- AC-B13.3 — **Given** the bank page, **when** the user views totals, **then** account activity (transfers, bills, fees, incoming funds) and card activity (POS/online purchases) are distinguishable, not merged into one undifferentiated list.

**US-B14 — Card-to-account linkage**
- AC-B14.1 — **Given** an SMS that explicitly states a card repayment/settlement was debited from a specific account (e.g. a "credit card payment" message naming both the card and the source account), **when** it is processed, **then** the app records the link between that card and that account.
- AC-B14.2 — **Given** a card with a known linked settlement account, **when** the user views the card, **then** the linked account is shown for context.
- AC-B14.3 — **Given** no SMS has ever indicated a card's settlement account, **when** the user views the card, **then** it is shown as unlinked rather than guessed.

**US-B15 — Auto-creation on first mention**
- AC-B15.1 — **Given** an SMS references a bank, account, or card the app has never seen, **when** it is processed, **then** the corresponding entities are created automatically with no setup step required from the user.
- AC-B15.2 — **Given** an auto-created instrument, **when** the user views it before renaming it, **then** it is labelled using its raw identifier (e.g. masked card/account number) so it's still identifiable.

**US-B16 — Rename a bank `[Addendum A — APPROVED]`**
- AC-B16.1 — **Given** any bank in the app (created from a rule pack or created by the user via US-A6), **when** the user renames it, **then** the new name appears everywhere that bank is referenced, and the bank's underlying identity is unchanged — its accounts, cards, totals and history all stay attached to it (the same guarantee AC-B3.1/B3.2 give for instruments).
- AC-B16.2 — **Given** a bank the user has renamed, **when** a later SMS or rule-pack update supplies a different display name for that same bank, **then** the user's name wins and is not silently overwritten (the US-D3/AC-D3.2 principle — a user's explicit choice outranks the app's — applied to bank names).

**US-B4 — Manual entry**
- AC-B4.1 — **Given** the user is on the transaction list, **when** they add a transaction with amount, date, merchant, category, and card/cash source, **then** it is saved and included in all totals and breakdowns.
- AC-B4.2 — **Given** the user submits a manual transaction with a missing required field, **when** they attempt to save, **then** saving is blocked with a specific message naming the missing field.
- AC-B4.3 — **Given** a manually added transaction, **when** it is displayed in any list, **then** it is visually distinguishable from an SMS-derived one.

**US-B5 — Edit a transaction**
- AC-B5.1 — **Given** an SMS-derived transaction with a mis-parsed merchant name, **when** the user edits the merchant and saves, **then** the corrected merchant is shown and used in all breakdowns.
- AC-B5.2 — **Given** an edited transaction, **when** the user opens its detail, **then** both the original auto-detected value and the user-edited value are visible.
- AC-B5.3 — **Given** an edited transaction, **when** a later re-scan of SMS occurs, **then** the user's edit is preserved and not overwritten by re-parsing.

**US-B6 — Delete / exclude**
- AC-B6.1 — **Given** a transaction the user wants removed, **when** they delete it, **then** it disappears from lists and all totals recalculate without it.
- AC-B6.2 — **Given** a delete action, **when** it is performed, **then** the user is asked to confirm before the data is removed.
- AC-B6.3 — **Given** a deleted transaction, **when** the source SMS is re-scanned, **then** the transaction is not resurrected.
- AC-B6.4 — **Given** a transaction is deleted, **when** an auditor (the user) inspects the change history, **then** the deletion is recorded with timestamp and prior values. *(Retention/hard-delete behaviour depends on OQ-8.)*

**US-B7 — Refunds and reversals**
- AC-B7.1 — **Given** an SMS describing a refund or credit to a card, **when** it is processed, **then** it is recorded as a credit and **decreases** the period's total spend rather than increasing it.
- AC-B7.2 — **Given** a refund and its original charge both exist, **when** the user views the category breakdown, **then** the net effect on that category is zero (or the difference, for partial refunds).
- AC-B7.3 — **Given** a credit transaction, **when** it is displayed in a list, **then** it is visually distinct from a debit (e.g. sign and/or colour).

### Epic C — Categorization

**US-C1 — Every transaction has a category**
- AC-C1.1 — **Given** any transaction in the system, **when** it is displayed, **then** it shows either a specific category or an explicit "Uncategorized" state — never a blank.
- AC-C1.2 — **Given** a transaction the app cannot confidently categorize, **when** it is created, **then** it is assigned "Uncategorized" and counted in the review queue.
- AC-C1.3 — **Given** a set of transactions, **when** category totals are summed, **then** the sum of all category totals (including Uncategorized) equals the overall period total.

**US-C2 — Fast manual correction**
- AC-C2.1 — **Given** a transaction with the wrong category, **when** the user changes it, **then** the new category is saved and reflected in the breakdowns immediately.
- AC-C2.2 — **Given** the user is changing a category, **when** the category picker opens, **then** the change can be completed without leaving the transaction context or navigating through more than two screens.
- AC-C2.3 — **Given** the user changes a category, **when** the change is saved, **then** the app offers to apply the same category to other transactions from the same merchant (see US-D5).

**US-C3 — Custom categories**
- AC-C3.1 — **Given** the user is in category settings, **when** they create a category with a unique name, **then** it becomes available in every category picker.
- AC-C3.2 — **Given** the user attempts to create a category whose name already exists, **when** they save, **then** it is rejected with a message.
- AC-C3.3 — **Given** a custom category in use by transactions, **when** the user deletes it, **then** the app requires a decision on what happens to those transactions (reassign or set to Uncategorized) and no transaction is left pointing at a non-existent category.
- AC-C3.4 — **Given** the user renames a category, **when** they save, **then** all historical transactions in that category reflect the new name and their history is preserved.

**US-C4 — Low-confidence flagging**
- AC-C4.1 — **Given** a transaction categorized below the confidence threshold (threshold value — see OQ-14), **when** it is displayed, **then** it carries a visible "needs review" indicator.
- AC-C4.2 — **Given** flagged transactions exist, **when** the user opens the app, **then** the count of items needing review is visible from the main screen.
- AC-C4.3 — **Given** a flagged transaction, **when** the user confirms or corrects the category, **then** the flag is cleared.

**US-C5 — Bulk categorization**
- AC-C5.1 — **Given** several uncategorized transactions from the same merchant, **when** the user categorizes them as a group, **then** all selected transactions receive that category in one action.
- AC-C5.2 — **Given** a bulk categorization was applied, **when** the user undoes it, **then** all affected transactions revert to their prior categories.

### Epic D — Learning loop

**US-D1 — Remember merchant→category**
- AC-D1.1 — **Given** the user categorizes a transaction from merchant "M" as category "C", **when** the change is saved, **then** a merchant rule M→C exists and is visible in the learned-rules list.
- AC-D1.2 — **Given** a rule M→C exists, **when** the user re-categorizes another transaction from M to a different category "C2", **then** the rule updates to M→C2 (subject to the scope choice in US-D5).

**US-D2 — Apply learning to future transactions (the electric-bill case)**
- AC-D2.1 — **Given** the user has categorized a payment to the electric utility as "Utilities", **when** a new SMS arrives for a charge from that same utility, **then** the new transaction is created already categorized as "Utilities" with no user action.
- AC-D2.2 — **Given** an auto-categorized-by-rule transaction, **when** the user views it, **then** the app indicates it was categorized automatically (and, ideally, why).
- AC-D2.3 — **Given** a merchant string that differs cosmetically from a known merchant (extra store number, differing spacing/case, trailing reference codes), **when** a transaction from it is processed, **then** the app still matches the learned rule OR flags it as low-confidence — it must not silently create an unrelated new merchant with no link. *(Matching strictness is an implementation decision for later phases; the observable requirement is "match or flag", never "silently miscategorize".)*
- AC-D2.4 — **Given** a merchant never seen before, **when** a transaction from it is processed, **then** it is Uncategorized or low-confidence-flagged, and is **not** assigned a confident category by coincidence.

**US-D3 — User correction wins**
- AC-D3.1 — **Given** the app auto-assigned category C1 and the user changes it to C2, **when** the next transaction from that merchant arrives, **then** it is categorized C2.
- AC-D3.2 — **Given** a user-set rule, **when** any automatic re-learning runs, **then** the user's explicit choice is never silently overridden.

**US-D4 — Inspect and edit learned rules**
- AC-D4.1 — **Given** the app has learned rules, **when** the user opens the rules screen, **then** every rule is listed with its merchant and category.
- AC-D4.2 — **Given** a rule in the list, **when** the user edits its category, **then** future transactions use the new category.
- AC-D4.3 — **Given** a rule in the list, **when** the user deletes it, **then** future transactions from that merchant are Uncategorized rather than following the deleted rule.
- AC-D4.4 — **Given** the user edits a rule, **when** they save, **then** the app asks whether to also re-apply the change to existing historical transactions, and honours the answer.

**US-D5 — Scope of a correction**
- AC-D5.1 — **Given** the user changes a transaction's category, **when** the change is saved, **then** the app offers at least: "this transaction only", and "this and future transactions from this merchant".
- AC-D5.2 — **Given** the user picks "this transaction only", **when** a later transaction from that merchant arrives, **then** the previously learned rule (if any) still applies and the one-off does not become the rule.
- AC-D5.3 — **Given** the user picks the merchant-wide option, **when** they confirm, **then** the rule is created/updated and the app states how many existing transactions were affected.

### Epic E — Insight and reporting

**US-E1 — Current month total**
- AC-E1.1 — **Given** transactions exist in the current calendar month, **when** the user opens the app, **then** the current-month total spend is visible on the first screen without further navigation.
- AC-E1.2 — **Given** a new transaction is added or corrected, **when** the user returns to the main screen, **then** the total reflects the change.
- AC-E1.3 — **Given** no transactions exist for the current month, **when** the user opens the app, **then** a zero/empty state is shown rather than a blank or error.
- AC-E1.4 — **Given** the month boundary passes, **when** the user opens the app on the 1st, **then** the "current month" total resets to the new month and the prior month remains viewable. Periods are calendar months, not card statement cycles (confirmed — was OQ-12).

**US-E2 — Category breakdown**
- AC-E2.1 — **Given** a selected period, **when** the user views the category breakdown, **then** each category is listed with its total and its share of the period total.
- AC-E2.2 — **Given** a category in the breakdown, **when** the user selects it, **then** the underlying transactions for that category and period are listed.
- AC-E2.3 — **Given** an "Uncategorized" bucket with a non-zero total, **when** the breakdown is shown, **then** Uncategorized is displayed as its own line and not hidden or folded into "Other".

**US-E3 — Per-card breakdown**
- AC-E3.1 — **Given** a selected period, **when** the user views the card breakdown, **then** each card is listed with its total for that period.
- AC-E3.2 — **Given** the card breakdown, **when** the totals are summed, **then** they equal the period total shown elsewhere in the app.

**US-E4 — Month-over-month comparison**
- AC-E4.1 — **Given** at least two months of data, **when** the user views the comparison, **then** the current period total is shown alongside the prior period total and the difference.
- AC-E4.2 — **Given** fewer than two months of data, **when** the user views the comparison, **then** the app states that there isn't enough history yet rather than showing a misleading comparison.

**US-E5 — Search and filter**
- AC-E5.1 — **Given** transactions exist, **when** the user searches a merchant name fragment, **then** all matching transactions are listed.
- AC-E5.2 — **Given** the user applies a filter (date range, category, card, amount range), **when** the filter is applied, **then** only matching transactions are shown and the displayed total reflects the filtered subset.
- AC-E5.3 — **Given** a filter produces no results, **when** it is applied, **then** an explicit empty state is shown with a way to clear the filter.

### Epic F — Data control, privacy, trust

**US-F1 — Access protection**
- AC-F1.1 — **Given** app-level authentication is enabled, **when** the app is opened or resumed after being backgrounded, **then** the user must authenticate before any financial data is visible.
- AC-F1.2 — **Given** authentication fails or is cancelled, **when** the user is returned to the app, **then** no transaction data, totals, or card identifiers are visible.
- AC-F1.3 — **Given** the app is backgrounded, **when** it appears in the OS app switcher, **then** financial figures are obscured in the preview/snapshot.

**US-F2 — Export**
- AC-F2.1 — **Given** transactions exist, **when** the user exports their data, **then** a complete, machine-readable file containing all transactions, categories, cards, and learned rules is produced.
- AC-F2.2 — **Given** an export was produced, **when** the row/record count is compared to the in-app transaction count, **then** they match.
- AC-F2.3 — **Given** the user initiates an export, **when** the export is created, **then** the user is warned that the file contains sensitive financial data and is unprotected unless they secure it. A plain (unencrypted) file is acceptable for v1 (confirmed — was OQ-13).

**US-F3 — Delete everything**
- AC-F3.1 — **Given** the user chooses to erase all data, **when** they confirm through an explicit confirmation step, **then** all transactions, cards, categories, learned rules, and cached SMS content are removed.
- AC-F3.2 — **Given** all data has been erased, **when** the app is reopened, **then** it presents the first-run state with no residual financial data recoverable in the UI.
- AC-F3.3 — **Given** the user starts the erase flow, **when** they cancel, **then** no data is removed.

**US-F4 — Transparency about data movement**
- AC-F4.1 — **Given** the user opens the privacy/about screen, **when** they read it, **then** it states plainly what data is stored, where it is stored, and what (if anything) leaves the device.
- AC-F4.2 — **Given** the app's stated posture is local-only (pending OQ-7), **when** the app runs under network monitoring during normal use, **then** no financial data (SMS content, amounts, merchants, card identifiers) is transmitted off-device.

**US-F5 — Change history / audit trail**
- AC-F5.1 — **Given** a transaction has been edited, re-categorized, or deleted, **when** the user views its history, **then** each change is listed with what changed, from what value, to what value, and when.
- AC-F5.2 — **Given** an auto-categorized transaction, **when** the user views its history, **then** the entry indicates the change was made by the app (and which rule applied), not by the user.
- AC-F5.3 — **Given** any history entry, **when** the user attempts to alter it, **then** it cannot be edited — history is append-only.

**US-B8 — Soft delete and restore**
- AC-B8.1 — **Given** the user deletes a transaction, **when** the deletion completes, **then** the transaction leaves normal lists/totals but is retained in a "Recently deleted" view, not destroyed.
- AC-B8.2 — **Given** a transaction in "Recently deleted", **when** the user restores it, **then** it reappears in normal lists/totals with its full prior history intact.
- AC-B8.3 — **Given** a transaction was removed via "erase everything" (US-F3) rather than a single delete, **when** the erase completes, **then** it is truly and permanently gone, not recoverable from "Recently deleted."

**US-B9 — Multi-currency**
- AC-B9.1 — **Given** a transaction in a currency other than the base currency, **when** it is displayed, **then** both its native amount/currency and its converted base-currency amount are shown.
- AC-B9.2 — **Given** transactions in more than one currency, **when** a period total is computed, **then** it is computed in the base currency using each transaction's recorded conversion, never by summing raw numbers across currencies.
- AC-B9.3 — **Given** a converted amount, **when** the user inspects it, **then** the conversion rate and rate date used are visible (traceability; exact rate source is a later-phase decision).

**US-B10 — Non-spending movement capture**
- AC-B10.1 — **Given** an SMS reporting a salary/income credit, **when** it is processed, **then** it is recorded as income, not spend, and is visible in a distinct income view.
- AC-B10.2 — **Given** an SMS reporting an ATM withdrawal, **when** it is processed, **then** it is recorded as a withdrawal and is available for the user to later reclassify as cash spending via manual entry if desired.
- AC-B10.3 — **Given** the user opens a "spent vs. kept" summary, **when** it renders, **then** it nets spend against income for the period rather than showing spend alone.

**US-B11 — Own-account transfers excluded from spend**
- AC-B11.1 — **Given** an SMS describing a transfer between two of the user's own accounts/cards, **when** it is processed, **then** it is tagged as an internal transfer and excluded from all "spend" totals and category breakdowns.
- AC-B11.2 — **Given** the app cannot determine whether a transfer is to the user's own account or to a third party, **when** it is processed, **then** it is flagged for review rather than silently classified either way.

**US-G1/G2 — Set budgets**
- AC-G1.1 — **Given** the user sets a monthly budget for a category, **when** they save it, **then** it applies starting the current calendar month and is visible on that category's view.
- AC-G2.1 — **Given** the user sets an overall monthly budget, **when** they save it, **then** it is tracked against total spend (excluding income/transfers per US-B10/B11) for the month.

**US-G3/G4 — Alerts and progress**
- AC-G3.1 — **Given** spend against a budget crosses 100% within the period, **when** the threshold is crossed, **then** the user receives an alert.
- AC-G3.2 — **Given** no budget is set for a category, **when** spend accrues in it, **then** no alert fires (alerts are opt-in per budget).
- AC-G4.1 — **Given** an active budget, **when** the user views it, **then** current spend, the budget amount, and percentage-used are all shown together.

**US-H1/H2/H3 — Statement reconciliation**
- AC-H1.1 — **Given** the user imports a statement file (PDF or CSV), **when** import completes, **then** every statement line is matched to an existing transaction or added as a new one.
- AC-H2.1 — **Given** a reconciliation run, **when** it finishes, **then** the user sees counts of matched, newly-added, and unmatched-but-flagged entries.
- AC-H3.1 — **Given** a transaction added via reconciliation, **when** it is categorized, **then** it uses the same learned merchant rules as SMS-derived transactions (US-D1/D2) and can itself train the learning loop.

**US-I1/I2/I3 — Backup and sync**
- AC-I1.1 — **Given** cloud backup is enabled, **when** data changes, **then** a backup is created/updated without requiring a manual export step.
- AC-I2.1 — **Given** data is backed up to the cloud, **when** it is stored, **then** it is encrypted such that the cloud provider/account holder alone cannot read financial content in the clear.
- AC-I3.1 — **Given** a new device and an existing backup, **when** the user signs in and restores, **then** all transactions, cards, categories, learned rules, and budgets are recovered.

### Epic J — Teaching the app a message format `[Addendum B — APPROVED]`

**US-J1 — Declare the transaction type of a message the app couldn't read**

- AC-J1.1 — **Given** an item in the Needs Review queue, **when** the user opens "Complete the details", **then** a Type selector is present offering the transaction types the app supports (purchase, refund/reversal, transfer to my own account, transfer to someone else, deposit/income, ATM withdrawal, fee/charge, bill payment, loan/finance installment), labelled in both Arabic and English (NFR-U8).
- AC-J1.2 — **Given** the user selects a type, **when** the transaction is saved, **then** its sign (debit/credit) and whether it affects spend follow from the selected type automatically — the user is never asked to choose a sign, tick "is this a credit", or otherwise reason about arithmetic direction.
- AC-J1.3 — **Given** the user selects "refund/reversal", **when** the transaction is saved, **then** it **reduces** the period's spend total rather than increasing it (same guarantee as AC-B7.1) and is displayed as visually distinct from a debit (AC-B7.3).
- AC-J1.4 — **Given** the user selects "transfer to my own account", **when** the transaction is saved, **then** it is tagged as an internal transfer and excluded from all spend totals and category breakdowns (same guarantee as AC-B11.1).
- AC-J1.5 — **Given** the parser had already determined a type before the message failed on some other field, **when** the completion form opens, **then** the Type selector is pre-selected with what the parser found and the user may override it. **Given** the parser matched no rule at all, **then** the selector opens unselected and saving is blocked until a type is chosen (AC-B4.2 shape). *(The pre-fill half depends on **KHA-146** being fixed; the two are complementary, not duplicates.)*
- AC-J1.6 — **Given** the user declares a type, **when** the transaction is saved, **then** the declaration is recorded in the audit trail as a **user** action, distinguishable from a parser-derived type (NFR-A2, AC-F5.2).
- AC-J1.7 — **Given** the user has declared a type on one message, **when** a later message from the same sender is processed, **then** **nothing is auto-applied from that declaration** — a v1 type declaration teaches the app nothing about future messages. *(Stated explicitly, as an AC rather than a note, because implementing it as learning is the obvious shortcut and it is out of scope until US-J4/J5 are approved. Learning from declarations without the US-J5 confirmation loop would be exactly the silent-wrong-number risk this addendum exists to avoid.)*

**US-J2 — Hand a redacted sample to a rule author**

- AC-J2.1 — **Given** a message in the Needs Review queue, **when** the user chooses "help support this format", **then** the app produces a shareable file containing, for that message only: its redaction-applied text (ADR-013 redaction already applied — no PAN, PIN, CVV, or OTP), its sender string, its linked bank if any, and the user-declared type if one was set. **Nothing else, and nothing from any other message.**
- AC-J2.2 — **Given** the file has been prepared, **when** it is presented, **then** the exact content the user is about to share is displayed in full for them to read, and they can edit or cancel before anything leaves the app.
- AC-J2.3 — **Given** the user proceeds, **when** the file is produced, **then** they are warned in plain language that it still contains real values from a real message (amount, merchant, date, sender) and that **they** choose who receives it — the same posture and honesty as AC-F2.3, not a claim of anonymity.
- AC-J2.4 — **Given** the export, **when** it is written, **then** it is written to a user-chosen location through the platform file picker and **the app performs no network transmission of any kind** (ADR-001 — the release build declares no network permission). Sharing it onward is an act the user performs in another app of their choosing.
- AC-J2.5 — **Given** the user selects several messages of the same format, **when** they export, **then** each appears as a separate, individually-reviewable entry in the file, and any message the user did not explicitly select is never included. There is no "export everything unparsed" action.
- AC-J2.6 — **Given** an exported sample reaches a rule author, **when** a parsing rule is written from it, **then** the real message text is never committed to any repository, test corpus, or tooling — only a **synthetic** fixture mimicking its structure (NFR-M3, NFR-M3a). The export flow states this boundary to the user.

**US-J3 — Install a rule pack and see what changed**

- AC-J3.1 — **Given** the user has a rule-pack file, **when** they import it, **then** the app shows a human-readable summary of what it changes (banks added/changed, message formats added/removed) and requires explicit confirmation before it takes effect (ADR-007).
- AC-J3.2 — **Given** an imported pack has just been activated, **when** the user confirms, **then** the app offers to re-check their banks immediately using the existing AC-A6.10 "check again" mechanism, and reports the outcome in concrete numbers — *"N messages re-checked, N transactions added, N still need review"* — rather than leaving the user to guess whether it helped.
- AC-J3.3 — **Given** a transaction produced by an imported pack, **when** the user inspects its provenance, **then** it records the pack id, pack version and rule id that produced it, and the pack is marked as imported/unverified (NFR-A1, ADR-007).
- AC-J3.4 — **Given** an imported pack would parse an already-recorded transaction differently, **when** it is activated, **then** existing transactions are **not** rewritten and user edits are preserved (AC-B5.3).
- AC-J3.5 — **Given** a rule-pack file that is malformed, schema-invalid, or rejected by the engine, **when** the user imports it, **then** it is refused with a plain explanation of why, and the previously active packs stay in effect unchanged.
- AC-J3.6 — **Given** any imported pack, **when** it is active, **then** a bundled pack rule and an imported pack rule are the only things that may produce a transaction automatically in v1 — no rule derived on-device from user labeling exists in v1 (X20).

**US-J4 — Point at the fields in your own message `[DEFERRED — X20]`**

*These ACs are specified now so the safety constraints are settled and a later `/design` round has
something concrete to work from. They are **not authorised for build** and QA must not automate
them until X20 is re-opened and the phase is separately approved.*

- AC-J4.1 — **Given** an unreadable message, **when** the user teaches its format, **then** they do so **only** by selecting spans of the message text already displayed to them and assigning each span a field (amount, currency, merchant, date-time, card/account reference). They never type, paste, see, or edit a pattern, expression, or regex (X18, X18a).
- AC-J4.2 — **Given** a labeled span whose surrounding anchor text occurs **more than once** in that same message, **when** the app attempts to derive a rule, **then** it does **not** guess — it either asks the user for a more distinctive selection or declines to learn that field, and says which field it could not learn.
- AC-J4.3 — **Given** a derived rule applied to any later message, **when** it produces **more than one** candidate value for a field, **then** it extracts **nothing** for that field and the message goes to Needs Review. **Ambiguity always fails closed; it is never resolved by picking the first, the largest, or the most likely.**
- AC-J4.4 — **Given** a derived rule, **when** it is evaluated, **then** it applies only to messages from the **same sender** *and* carrying the **same declared-type keyword** as the example it was learned from. A rule learned from a purchase may never fire on that bank's refund message.
- AC-J4.5 — **Given** a derived rule, **when** it produces a transaction, **then** the sign and affects-spend come from the user's declared type (US-J1) and are **never** derived from the message text. *(This is the crux: field labeling expresses where a number is, never what it means.)*
- AC-J4.6 — **Given** a message that a bundled or imported pack rule can parse, **when** it is processed, **then** the pack rule always takes precedence over any user-taught format for that message.
- AC-J4.7 — **Given** the user has labeled a message, **when** they export it via US-J2, **then** the export may substitute placeholders for the labeled spans, producing a genuinely structural description with no real values in it. *(A forward benefit: US-J4 makes US-J2's export strictly safer than it can be in v1.)*

**US-J5 — Confirm before trusting `[DEFERRED — X20]`**

- AC-J5.1 — **Given** a newly taught format, **when** any message matches it, **then** the result is a **pre-filled Needs Review item, never a transaction**, until the format has been confirmed on **K** distinct subsequent messages (value of K — see **OQ-26**).
- AC-J5.2 — **Given** a pre-filled review item from an unconfirmed format, **when** the user accepts every extracted value unchanged, **then** that counts as one confirmation. **Changing any extracted field is a rejection, not a confirmation**, and resets the count.
- AC-J5.3 — **Given** a promoted (auto-applying) format, **when** the user corrects any **extracted** field on a transaction it produced, **then** the format is demoted to unconfirmed. On a **second** such correction it is disabled and the user is told plainly which format was disabled and why. *(A category correction is not an extraction correction and does not count — that is the ADR-008 learning loop, a different mechanism.)*
- AC-J5.4 — **Given** any transaction produced by a user-taught format, **when** the user views it, **then** it is visibly marked as read by a format they taught the app, and its provenance names that format by a stable id (NFR-A1a).
- AC-J5.5 — **Given** user-taught formats exist, **when** the app runs, **then** they are treated as local configuration: never transmitted, never shared by default, and never applied to any user's data but this one's (CON-1, X21). They are included in export (US-F2) and backup (US-I1) like any other setting.

**US-J6 — Manage what the app has learned `[DEFERRED — X20]`**

- AC-J6.1 — **Given** taught formats exist, **when** the user opens the formats list, **then** each is described in **plain language** ("Bank X purchases — the amount is the number after `SAR`"), never as a regex or pattern, and each can be disabled or deleted (X18a).
- AC-J6.2 — **Given** the user deletes or disables a taught format, **when** they confirm, **then** transactions already created by it are retained unchanged with their values and provenance intact (same guarantee as AC-A6.8), and only future messages are affected.

---

## 6. Constraints

- **CON-1** — Single user. There is no account system, no tenancy, no sharing, no server-side identity. Any design that implies "users" plural is out of scope.
- **CON-2** — Read-only with respect to money. The app never initiates, authorizes, or modifies a payment. Its only inputs are SMS and the user's own manual entries.
- **CON-3** — The app cannot see anything the SMS doesn't say. If an institution's SMS omits the merchant, the app cannot supply it. Coverage is bounded by SMS content quality.
- **CON-4** — Platform capability. The ability to read SMS at all is an OS-level permission question and may be a hard blocker on some platforms (see OQ-1 / OQ-3). This constraint may materially reshape the product.
- **CON-5** — No architecture, stack, storage-engine, or ML-model decisions are made in this document; those belong to phases 2–4.

---

## 7. Non-Functional Requirements

Even as a personal app, this system holds a complete record of one individual's financial activity, sourced from bank communications. Banking-domain expectations apply.

### 7.1 Security

| ID | Requirement |
|---|---|
| NFR-S1 | All financial data at rest (transactions, card identifiers, raw SMS content, learned rules) must be encrypted on the device. |
| NFR-S2 | Card/account identifiers must be stored and displayed in masked form (e.g. last 4 digits only). The app must never store or display a full PAN, CVV, PIN, or any credential, even if an SMS were to contain one — such content must be redacted before storage. |
| NFR-S3 | The app must support device-level or app-level authentication (biometric or passcode) gating access to all financial views. |
| NFR-S4 | Sensitive values must not be written to application logs, crash reports, or diagnostic output. Logs may reference a transaction by internal ID only. |
| NFR-S5 | If any network communication exists at all, it must use current TLS with certificate validation; plaintext transport of financial data is prohibited. |
| NFR-S6 | The app must not embed third-party analytics, advertising, or telemetry SDKs that could receive financial data. |
| NFR-S7 | The app's own cloud backup (C16) must always be encrypted (NFR-P2). Manual data *exports* (US-F2) may be a plain, unencrypted file — the user has accepted that trade-off for now (was OQ-13) — but the export flow must still warn the user the file is sensitive (AC-F2.3). |
| NFR-S8 | Screen content containing financial figures must be obscured in the OS app-switcher snapshot. |

### 7.2 Privacy and PII

| ID | Requirement |
|---|---|
| NFR-P1 | Bank SMS content is PII and financial data combined. It must be processed under a data-minimization principle: store only what is needed to produce a transaction record and to support user verification of the parse. |
| NFR-P2 | Cloud backup/sync (C16) is approved for v1, since the dataset is expected to stay small. It must be encrypted (NFR-S1/S5, AC-I2.1) and the user must be able to see/control what is backed up (US-F4). Categorization and parsing logic itself still runs on-device by default. |
| NFR-P3 | If any part of *processing* (parsing, categorization) is ever proposed to run off-device — as opposed to encrypted backup storage, which is approved — it must be an explicit, opt-in, clearly-labelled choice, and must be listed here as a change. |
| NFR-P4 | The app must not read, index, or retain SMS from non-financial senders beyond the momentary classification step needed to reject them. |
| NFR-P4a **`[Addendum A — APPROVED]`** | **NFR-P4's discard behaviour is deliberately left unchanged by US-A6.** The unrecognized-sender list is derived in memory, on demand, from the SMS inbox the app already has permission to read, and is never persisted. Content from an unlinked sender may be shown only one sender at a time, only at the user's request, redaction-applied, and is never stored (AC-A6.2). Only a sender the user affirmatively links becomes persisted configuration (AC-A6.3); everything else leaves no trace (AC-A6.9). **A retained log of unmatched-sender messages was considered as the alternative "toehold" for the user to correct from, and rejected:** it would mean permanently accumulating metadata — and possibly content — about senders that are genuinely not financial (friends, delivery services, marketing), which is the exact harm NFR-P4 exists to prevent, in order to solve a problem an on-demand read of a store the app can already read solves for free. |
| NFR-P5 | The user must be able to delete all stored data completely and verifiably (US-F3). |
| NFR-P6 | The app must state, in-product, what is collected, where it is stored, and what leaves the device (US-F4). |
| NFR-P7 | Data retention: SMS-derived records are retained until the user deletes them; the app must not retain data after a user-initiated erase (see OQ-8 for whether a retention period is desired for the audit trail). |

### 7.3 Compliance and regulatory

| ID | Requirement |
|---|---|
| NFR-C1 | The app is a personal financial record-keeping tool. It does not provide financial advice, does not hold funds, and does not act as a payment initiator; product copy must not imply otherwise. |
| NFR-C2 | The app must not store cardholder authentication data. Where PCI-DSS-adjacent concepts apply (full PAN, sensitive authentication data), the design must avoid handling them entirely rather than attempt to secure them. |
| NFR-C3 | Reading a user's own SMS on their own device is subject to platform store policy (notably restrictions on SMS-permission use). Compliance with the target platform's policy must be verified before build (see OQ-3), including whether distribution is via app store or personal/side-loaded install (see OQ-4). |
| NFR-C4 | Applicable data-protection law depends on the user's jurisdiction (see OQ-5). Even for a single-user personal app, the design should not preclude data-subject rights: access (export), erasure (delete-all), and rectification (edit) are already covered by US-F2, US-F3, US-B5. |
| NFR-C5 | The app must not redistribute or expose bank SMS content to any third party. |

### 7.4 Audit trail and data integrity

| ID | Requirement |
|---|---|
| NFR-A1 | Every transaction must retain its provenance: SMS-derived (with a reference to the source message) or manually entered. |
| NFR-A2 | Every mutation of a transaction (edit, re-categorization, deletion, merge) must be recorded in an append-only history with timestamp, previous value, new value, and actor (user vs system rule). |
| NFR-A3 | History entries must not be editable or deletable from the UI. |
| NFR-A4 | Monetary amounts must be stored and computed with exact decimal arithmetic. Floating-point representation of money is prohibited. |
| NFR-A5 | Every stored monetary amount must carry an explicit currency. Amounts in different currencies must never be summed without a stated conversion (multi-currency is required — see US-B9, C12). |
| NFR-A6 | Totals shown in the UI must be reproducible from the underlying transaction records; no derived figure may exist that cannot be traced to its constituent transactions. |
| NFR-A7 | The app must never silently discard a financial SMS (AC-A4.4). |

### 7.5 Performance and reliability

| ID | Requirement |
|---|---|
| NFR-R1 | A newly arrived transaction SMS must be reflected in the app within seconds (user's stated target), not merely "by the time the app is next opened" — the app is expected to process SMS in the background. **Amended (human-approved 2026-07-28) per ADR-018:** a background isolate cannot open the cryptographically-locked database (ADR-005), so the actual, shipped promise is single-digit seconds while the app is unlocked, and "visible at next unlock" while locked — nothing is ever lost, only delayed. See `docs/architecture.md` ADR-018 for the full reasoning and rejected alternatives. |
| NFR-R2 | The main screen (current month total) must render without a perceptible wait on a typical dataset; the app must remain responsive during background processing. |
| NFR-R3 | Initial historical import must not block the UI and must be resumable after interruption (AC-A3.2, AC-A3.3). |
| NFR-R4 | The app must function fully offline. No feature required for viewing or categorizing existing transactions may depend on network availability. |
| NFR-R5 | A parse failure on one SMS must not prevent processing of others; failures are isolated and routed to the review queue. |
| NFR-R6 | Data loss is unacceptable: an app crash, force-close, or device restart mid-processing must not corrupt or lose already-recorded transactions. |
| NFR-R7 | Battery and storage footprint must remain reasonable for continuous background SMS monitoring on a personal device.

### 7.6 Accessibility and usability

| ID | Requirement |
|---|---|
| NFR-U1 | The app should conform to WCAG 2.2 level AA principles as applicable to a mobile app, and to the target platform's accessibility guidelines. |
| NFR-U2 | All interactive elements must be reachable and correctly labelled for screen readers (TalkBack/VoiceOver), including amounts, categories, and card names. |
| NFR-U3 | Text must respect the OS font-size setting and remain readable and non-truncated at large accessibility text sizes. |
| NFR-U4 | Colour must never be the only means of conveying information — notably debit vs credit, and "needs review" status must have a non-colour indicator. |
| NFR-U5 | Contrast ratios must meet at least 4.5:1 for normal text. |
| NFR-U6 | Touch targets must meet the platform's minimum size guidance. |
| NFR-U7 | The correction flow (US-C2) is the highest-frequency interaction and must be optimized for minimal taps; if correcting is tedious, the learning loop never gets trained.
| NFR-U8 | Arabic and English SMS/UI must be supported, including full right-to-left layout — this is confirmed, not optional (was OQ-17). |

### 7.7 Maintainability and testability

| ID | Requirement |
|---|---|
| NFR-M1 | SMS parsing rules must be updatable without a full application redesign, since bank message formats change without notice. |
| NFR-M2 | The parsing and categorization logic must be testable against a corpus of sample SMS with expected outputs, so QA can automate regression testing (requires real samples — see OQ-2). |
| NFR-M3 | Test data must consist of realistic-but-synthetic SMS; the user's genuine bank SMS must not be committed to any repository or shared with any tooling. |
| NFR-M3a **`[Addendum B — APPROVED]`** | **The sample-export boundary (US-J2), stated so an engineer neither refuses the task nor violates NFR-M3.** A rule author *may read* a redacted real message the user has deliberately and explicitly shared — that is the only way a rule for a new format can be written at all. What that author commits is a **synthetic** fixture that mimics the message's structure; the real text must never enter a repository, a test corpus, an issue description, a commit message, or any tooling. This is the same boundary `docs/architecture.md` ADR-007's KHA-127 subsection already states for engineer-obtained samples, made explicit here because Addendum B turns it into a routine, user-initiated flow rather than a one-off. The export flow must state this boundary to the user (AC-J2.6). |
| NFR-A1a **`[Addendum B — APPROVED]`** | **No extraction mechanism may exist in this product that cannot name what produced a number.** NFR-A1 already requires SMS-derived vs. manual provenance, and ADR-007 already requires a `ruleId` per parsed transaction. Extending it: a transaction produced by a user-taught format (US-J4/J5, deferred) must record a **stable identifier for that format**, resolvable to a plain-language description (AC-J6.1) and to the moment the user taught it. This is deliberately the same bar that ADR-007 used to reject an on-device classifier for v1 (*"weights have no `ruleId`"*) — a user-taught format is only acceptable **because** it can meet that bar, and any future mechanism that cannot must be rejected on the same ground. |

---

## 8. Decisions (resolved 2026-07-27) and Residual Open Items

All items originally raised as Open Questions were answered by the human. Resolutions are recorded here for traceability; scope/story/NFR sections above have been updated to reflect them.

| ID | Decision | Where it landed |
|---|---|---|
| OQ-1 | Android only. Built with Flutter. | A2, mobile-engineer scope |
| OQ-2 | Saudi Arabia. User provided real sample SMS from two banks (Bank Aljazira, D360) covering 9 distinct message types. Patterns extracted into §3.4; raw text was not committed to any file per NFR-M3. | A1, NFR-M2, §3.4 — **resolved enough to unblock planning; more samples (other banks/message types) still welcome before phase 4/7 parser build** |
| OQ-3 | Not yet verified on-device. For now, distribute as a directly installed APK, not through an app store — avoids store policy review for the time being. | A2, NFR-C3 |
| OQ-4 | Personal side-load only; no app store publication. | X16 |
| OQ-5 | Personal use only, no other stated regulatory constraint beyond Saudi Arabia jurisdiction (OQ-2). NFR-C4 still applies generically (data-subject-style rights already covered by export/delete/edit). | NFR-C4 |
| OQ-6 | Multi-currency is needed. | C12 (new) |
| OQ-7 | Cloud backup/sync wanted; user expects the dataset to stay small, so this is acceptable. Still must be encrypted in transit and at rest per NFR-S1/S5. | C16 (new), NFR-P2 updated below |
| OQ-8 | Deleting a transaction hides it (soft delete / recoverable), it is not destroyed, in case of a mistake. Only the explicit "erase everything" flow (US-F3) is a true hard delete. | X17 (new), US-B6/AC-B6 — needs an "undo/restore hidden transaction" story, see below |
| OQ-9 | SMS only — no email or push-notification ingestion. | X15 (new) |
| OQ-10 | Yes — statement PDF/CSV import to catch anything SMS missed, and to help train the learning loop. | C14 (new) |
| OQ-11 | Initial import starts from the current calendar month, not full history. | AC-A3.1 updated below |
| OQ-12 | Calendar months (not statement cycles). | AC-E1.4 |
| OQ-13 | A plain (unencrypted) export file is acceptable for now. | AC-F2.3, NFR-S7 |
| OQ-14 | No fixed numeric threshold specified. Approach: categorize primarily by matching on merchant/payee name; some names are unambiguous immediately, others the app learns step by step from corrections, improving over time. Confidence threshold value is still a build-phase design decision — the observable bar (AC-D2.3/D2.4) stands. | US-D2, NFR partially open — **residual, non-blocking** |
| OQ-15 | Yes — budgets and threshold alerts are in v1. | C13 (new) |
| OQ-16 | Seconds — the app runs in the background and should reflect new SMS promptly. | NFR-R1 updated: target is single-digit seconds from SMS arrival to appearing in-app, not "next time the app is opened." |
| OQ-17 | Confirmed: Arabic/English SMS and UI, right-to-left layout required. | A4 (new), NFR-U8 |
| OQ-18 | The app should propose a default starting category list for the user to edit, rather than starting empty. | US-C3, first-run flow — default list to be proposed in phase 3 (design) |
| OQ-19 | Yes — cash spending is tracked via manual entry. | Confirms US-B4/C10 as first-class, not a fallback |
| OQ-20 | Yes — capture everything: card spend, cash, transfers, and withdrawals. Goal is to see total spent vs. total kept. Per-bank/per-account breakdown tabs may be added if needed. | C15 (new) |

### Residual open items (non-blocking, but track them)
- **More sample SMS (OQ-2):** the two-bank sample set is enough to design against (see §3.4) but is not exhaustive — more real samples (other banks the user uses, and more edge cases: declines, partial refunds) will still sharpen the phase-4/7 parser.
- **Soft-delete / restore UX:** deciding to hide rather than hard-delete a transaction (OQ-8) implies a new capability — a "recently deleted / hidden" view with a restore action — that wasn't in the original story set. Added as US-B8 below.
- **Auto-categorization confidence threshold:** OQ-14's qualitative answer ("clear names work immediately, the rest improves step by step") is enough to design against, but the exact numeric/behavioural threshold for the "needs review" flag (AC-C4.1) is still a phase-3/4 design decision, not a product decision.

### Open questions raised by Addendum A (2026-07-30) — resolved by the human same-day

| ID | Question | Resolution |
|---|---|---|
| **OQ-21** | First-run onboarding step, or on-demand from Settings only? | **On-demand only**, as originally scoped in AC-A6.1. No eighth onboarding screen. |
| **OQ-22** | Explicit per-bank "couldn't be read" state, or Needs Review queue alone? | **Explicit per-bank state.** Human's reasoning: the queue alone lets a user silently assume manual entry is normal forever; a bank saying plainly "N messages, none could be read automatically" tells them this specific bank needs a parser update. Also added **AC-A6.10**: the user can trigger a manual re-check on a linked bank at any time (e.g. after an app update improves its parsing), not only once automatically at link time. |
| **OQ-23** | Ship order vs KHA-128? | **KHA-128 first, then US-A6** — confirmed, matches the product-owner recommendation. |

### Open questions raised by Addendum B (2026-07-30) — **UNRESOLVED, need a human decision**

| ID | Question | Why it can't be answered here |
|---|---|---|
| **OQ-24** ✅ | **RESOLVED 2026-07-30 — v1 scope as written, confirmed by the human.** No new app release per format, but still a round trip to a rule author for review. Field tagging (US-J4/J5) explicitly declined for now given the money-correctness risk. | — |
| **OQ-25** ✅ | **RESOLVED 2026-07-30 — private to this team only.** A shared/community pack repository is explicitly out of scope (X21) unless separately re-opened. | — |
| **OQ-26** | For the deferred phase: **K** — how many confirmations before a user-taught format is trusted to auto-apply (AC-J5.1)? And is K counted per format, or per bank? | No basis to pick a number. It trades the user's patience against the blast radius of a wrongly-taught format, and the human is the only person who knows how many messages per month a format even sees. Same shape as OQ-14 (the categorization confidence threshold), which was also deliberately left to the human/build phase rather than guessed. |
| **OQ-27** ✅ | **RESOLVED 2026-07-30 — no.** The sender must be linked as a known bank (US-A6) before its message type can be declared (US-J1). No "declare type first, link later" path in v1. | — |
| **OQ-28** | What evidence would justify re-opening X20 and building US-J4–J6? | Needs a threshold the human sets from lived use, e.g. *"if I am still hand-completing more than N messages a month once all seven banks have rules"*, or *"if a bank changes its format and the round trip takes more than N days"*. Without a stated trigger, a deferral quietly becomes a permanent no. |

---

## 9. Traceability Summary

For downstream phases: every acceptance criterion is prefixed `AC-<story-id>.<n>` and maps to exactly one user story. QA (phase 7) should produce a test case per AC.

| Epic | Stories | ACs | Status |
|---|---|---|---|
| A — SMS ingestion | US-A1..A6 | 30 | Resolved; **US-A6 is `[Addendum A — APPROVED]`** — 11 ACs (AC-A6.1–11), build order per OQ-23: after KHA-128 |
| B — Banks, accounts, cards & transactions | US-B1..B16 | 48 | Resolved; **US-B16 is `[Addendum A — APPROVED]`** — 2 ACs |
| C — Categorization | US-C1..C5 | 15 | Resolved; default category list to be proposed in phase 3 |
| D — Learning loop | US-D1..D5 | 14 | Resolved; confidence threshold is a phase-3/4 design decision |
| E — Insight & reporting | US-E1..E5 | 14 | Resolved |
| F — Data control & trust | US-F1..F5 | 14 | Resolved |
| G — Budgets & alerts | US-G1..G4 | 4 | Resolved (new) |
| H — Statement reconciliation | US-H1..H3 | 3 | Resolved (new) |
| I — Backup & sync | US-I1..I3 | 3 | Resolved (new) |
| **J — Teaching a message format** | US-J1..J6 | 33 | **`[Addendum B — APPROVED]`** — v1 authorised: US-J1 (7 ACs, KHA-147), US-J2 (6, KHA-148), US-J3 (6, KHA-149) = 19. Deferred under X20: US-J4 (7), US-J5 (5), US-J6 (2) = 14 (KHA-150, tracked not built). OQ-24/25/27 resolved; OQ-26/28 remain open but don't block v1. Build sequencing: after the in-flight rule work for the seven real banks (KHA-128 and follow-ups) settles first |

**No remaining blockers before phase 2 (planning).** Real SMS samples from two banks are in hand (§3.4); more are welcome over time but nothing is gated on them now. This PRD is unblocked pending your `APPROVED` status change.

---

*End of PRD. This document must be marked `STATUS: APPROVED` by the human before phase 2 (planning) begins.*

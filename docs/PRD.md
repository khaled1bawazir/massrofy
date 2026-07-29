STATUS: Approved
TIER: personal
# Massrofy — Personal Spending Tracker from Bank SMS

**Version:** 0.4 (Addendum A — user-declared bank senders; see the addendum status line below)
**Date:** 2026-07-27 (v0.3), 2026-07-30 (Addendum A)
**Author:** product-owner agent (v0.1), revised directly per human decisions (v0.2)
**Phase:** 1 — Requirements

> **ADDENDUM A STATUS: DRAFT - awaiting human approval.**
> On 2026-07-30, after a real-device finding (Linear **KHA-128**: the bundled rule pack
> configures 2 of the user's 7 banks, and both patterns were guessed wrong — the phone shows
> `Jazira Bank`, which matches none of them), one capability (**C17**), two stories
> (**US-A6**, **US-B16**), two out-of-scope rows (**X18**, **X19**) and one privacy
> requirement (**NFR-P4a**) were added. Every addendum item is tagged
> **`[Addendum A — DRAFT]`**.
> Everything else in this document stays `Approved` and `/build` may continue against it.
> **The tagged items are NOT authorised for build** until the human changes `DRAFT` to
> `APPROVED` in this block. The product-owner does not self-approve.
> **Process note:** US-A6 needs one screen `docs/design.md` does not contain (an unrecognized-
> sender review screen), so approving it also triggers a `/revise-design` round — the same
> shape as architecture.md's H-15. It does **not** reopen gate 1 for the rest of the PRD.

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
| C17 | **`[Addendum A — DRAFT]`** Let the user declare that SMS from a sender the app does not recognize are from one of their banks (naming that bank if it is new), so a bank the app was never configured for — or one that changed its sender ID — starts being tracked without waiting for a new app version |

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
| X18 **`[Addendum A — DRAFT]`** | A rule-authoring UI — letting the user write or edit sender/message patterns, message templates, or field-extraction mappings | C17 deliberately stops at *sender recognition*. Once a sender is recognized, the already-built unparsed queue (US-A4) plus manual completion (AC-A4.2) turn its messages into transactions with no pattern-writing at all. Authoring parsing rules is a specialist task, it is where a wrong guess silently corrupts amounts, and user-supplied patterns would be an executable-input surface the rule-pack design deliberately has none of. Keeping **rule content** an engineering data task (KHA-128) is the right split |
| X19 **`[Addendum A — DRAFT]`** | A persisted "not my bank / ignore this sender" list | The unrecognized-sender list is shown only on demand, so there is nothing nagging the user that needs suppressing — and persisting it would mean storing metadata about senders the user has just confirmed are *not* financial, which is exactly what NFR-P4 exists to prevent. Revisit only if the list proves noisy in real use |

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
- **US-A6** **`[Addendum A — DRAFT]`** — As the Owner, I want to tell the app that messages from a sender it doesn't recognize are from one of my banks, so that a bank the app was never configured for (or one that changed its sender ID) starts being tracked without waiting for a new version of the app.
  > *Why this exists, in one paragraph, because it is the justification for the whole story:* the app decides "is this SMS from a bank?" by matching the sender string against patterns shipped inside the app. Whoever writes those patterns is guessing at a string they cannot see; the person holding the phone can read the exact string with zero guesswork. On 2026-07-30 that guess was wrong for both configured banks and absent for five more (KHA-128), and because an unmatched sender is discarded with nothing retained, the user saw `0.00 SAR` with nothing in the review queue either and no way to tell the app it was wrong. This is the same philosophy as the merchant-learning loop (US-D1–D5) — *the user corrects what the app got wrong and it sticks* — applied one layer up, at the bank/sender layer instead of the merchant/category layer. It does **not** replace shipping correct patterns (KHA-128); it means the *next* wrong or changed sender ID costs the user thirty seconds instead of costing them an app release.

### Epic B — Banks, accounts, cards, and the transaction record
- **US-B1** — As the Owner, I want each detected transaction to show amount, currency, merchant/payee, date-time, and which account/card it hit so that I can identify it at a glance.
- **US-B2** — As the Owner, I want my accounts and cards grouped under the bank that issued them so that I can see spending per bank, not just per instrument.
- **US-B3** — As the Owner, I want to give an account or card a friendly name (e.g. "Blue Visa", "Salary Account") so that I don't have to recognize it by trailing digits.
- **US-B12** — As the Owner, I want each bank I use recognized as its own entity with its own page so that I can see everything at that bank — its debit/current accounts and its cards — in one place.
- **US-B13** — As the Owner, I want debit/current accounts tracked as their own instrument type, separate from cards, under each bank, so that "money sitting in my account" and "credit card spend" don't get conflated.
- **US-B14** — As the Owner, I want a card recognized as belonging to the account that funds/settles it (where the SMS indicates that link, e.g. a credit card repayment debited from an account) so that the app understands the real money flow between my account and my card, not just two unrelated instruments.
- **US-B15** — As the Owner, I want a new bank, account, or card to be created automatically the first time an SMS mentions it (bank identified from the SMS sender/content), so that I don't have to pre-register my accounts and cards by hand.
- **US-B16** **`[Addendum A — DRAFT]`** — As the Owner, I want to give a bank the name I actually call it, so that my bank list reads the way I think about my money rather than however the app or the SMS spelled it. *(This is the "edit bank names" half of the human's 2026-07-30 request; US-A6 is the "add" half. It is the bank-level equivalent of US-B3, which only covers accounts and cards.)*
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

**US-A6 — Recognize a sender the app was never configured for `[Addendum A — DRAFT]`**

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

**US-B16 — Rename a bank `[Addendum A — DRAFT]`**
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
| NFR-P4a **`[Addendum A — DRAFT]`** | **NFR-P4's discard behaviour is deliberately left unchanged by US-A6.** The unrecognized-sender list is derived in memory, on demand, from the SMS inbox the app already has permission to read, and is never persisted. Content from an unlinked sender may be shown only one sender at a time, only at the user's request, redaction-applied, and is never stored (AC-A6.2). Only a sender the user affirmatively links becomes persisted configuration (AC-A6.3); everything else leaves no trace (AC-A6.9). **A retained log of unmatched-sender messages was considered as the alternative "toehold" for the user to correct from, and rejected:** it would mean permanently accumulating metadata — and possibly content — about senders that are genuinely not financial (friends, delivery services, marketing), which is the exact harm NFR-P4 exists to prevent, in order to solve a problem an on-demand read of a store the app can already read solves for free. |
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

### Open questions raised by Addendum A (2026-07-30) — need a human decision

| ID | Question | Why it is a genuine decision, not a detail |
|---|---|---|
| **OQ-21** | Should the unrecognized-sender check also appear as a **first-run onboarding step** (right after the initial import), or only on demand from Settings as AC-A6.1 specifies? | The live failure was a silent `0.00 SAR` on a fresh install: a first-run step would have caught it inside the first minute. The cost is one more screen in a first-run flow that is already seven screens long, shown at the moment the user has least reason to trust the app with a list of everyone who texts them. I have specified the on-demand path only, and I am not confident that is the right call. |
| **OQ-22** | When a sender is linked but **nothing from it can be auto-parsed**, should the app say so explicitly per bank (e.g. "Jazira Bank: 12 messages, none could be read automatically"), or is landing them in the Needs Review queue enough? | This is the difference between the user understanding "this bank needs a parser update, expect to fill these in by hand for now" and the user silently doing manual data entry forever while assuming that is normal — which is the failure mode §1 says kills the product ("the user does not abandon the app because upkeep is too manual"). Architecture already has somewhere to put it (the Settings → Diagnostics parser-health panel, ADR-015), so the cost is low; the question is whether the app should confess this in the main flow instead. |
| **OQ-23** | Sequencing against **KHA-128**: build US-A6 first (the user can self-serve all 5 missing banks immediately), or KHA-128's verified sender patterns first (the 7 known banks work out of the box, including on a clean install), or both — and in which order? | **Product-owner recommendation: KHA-128 first, US-A6 next.** KHA-128 is hours of verified data work and it fixes the number the user is looking at right now; US-A6 is a new screen plus a `/revise-design` round. They are complements, not substitutes — KHA-128 makes today right, US-A6 makes every future sender change the user's own thirty-second fix instead of an app release. Neither cancels the other. |

---

## 9. Traceability Summary

For downstream phases: every acceptance criterion is prefixed `AC-<story-id>.<n>` and maps to exactly one user story. QA (phase 7) should produce a test case per AC.

| Epic | Stories | ACs | Status |
|---|---|---|---|
| A — SMS ingestion | US-A1..A6 | 28 | US-A1..A5 resolved; **US-A6 is `[Addendum A — DRAFT]`** — 9 ACs, not authorised for build until the addendum is approved |
| B — Banks, accounts, cards & transactions | US-B1..B16 | 48 | US-B1..B15 resolved; **US-B16 is `[Addendum A — DRAFT]`** — 2 ACs |
| C — Categorization | US-C1..C5 | 15 | Resolved; default category list to be proposed in phase 3 |
| D — Learning loop | US-D1..D5 | 14 | Resolved; confidence threshold is a phase-3/4 design decision |
| E — Insight & reporting | US-E1..E5 | 14 | Resolved |
| F — Data control & trust | US-F1..F5 | 14 | Resolved |
| G — Budgets & alerts | US-G1..G4 | 4 | Resolved (new) |
| H — Statement reconciliation | US-H1..H3 | 3 | Resolved (new) |
| I — Backup & sync | US-I1..I3 | 3 | Resolved (new) |

**No remaining blockers before phase 2 (planning).** Real SMS samples from two banks are in hand (§3.4); more are welcome over time but nothing is gated on them now. This PRD is unblocked pending your `APPROVED` status change.

---

*End of PRD. This document must be marked `STATUS: APPROVED` by the human before phase 2 (planning) begins.*

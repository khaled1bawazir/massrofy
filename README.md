# Massrofy (مصروفي)

A single-user, offline-first Android app that turns the bank SMS you already
receive into a trustworthy, always-current picture of your spending — no bank
app juggling, no manual spreadsheet, no server anywhere.

## Why

Bank and card transactions arrive as SMS, one per institution, mixed in with
OTPs and marketing. There's no running total, no per-category breakdown, and
"what did I spend on groceries this month" means scrolling through raw text
messages. Massrofy reads those SMS on-device, parses them into structured
transactions, and learns how to categorize them — correct a merchant once and
it stays right from then on.

## What it does

- **Reads bank SMS automatically** (Arabic and English, RTL-first) and tells
  financial messages apart from OTPs and marketing — nothing is silently
  dropped; anything it can't parse lands in a review queue with the original
  text visible.
- **Models banks, accounts, and cards** as a real hierarchy, auto-created the
  first time each one is mentioned.
- **Categorizes and learns**: correct a merchant once, every future
  transaction from it arrives pre-categorized.
- **Reports spending** by month, category, and card, with search and filter.
- **Multi-currency, refunds, manual entries, and an append-only edit history**
  for full transaction lifecycle support.
- **Monthly budgets** per category (and overall) with threshold alerts.
- **Statement import (CSV/PDF)** reconciled against SMS-derived data.
- **Encrypted backup and restore** onto a new device.

## What it deliberately doesn't do

No payment initiation, no bank API integration, no multi-user or sharing, no
email/push ingestion, no receipt OCR, no analytics or telemetry, no app-store
listing. The single non-negotiable constraint: **Massrofy is read-only with
respect to money.** It observes; it never moves a riyal.

## Architecture, in one paragraph

There is no backend, no server, and no `INTERNET` permission in the release
build — enforced by CI, not just claimed. Everything (SMS parsing,
categorization, storage) runs on-device in Flutter/Dart. The local database is
SQLCipher-encrypted; the app lock is cryptographic, not cosmetic (losing
biometric auth means the database physically cannot open); money is exact
decimal end to end, never floating point; every ledger mutation writes an
append-only audit entry. See `docs/architecture.md` for the full ADR — every
decision states the alternatives considered and why they lost.

## Status

Single-user Android app, installed by side-load (no Play Store). Currently
implemented: foundation (encrypted storage, money type, audit trail, app
lock) and SMS ingestion/parsing. See `docs/build-plan.md` for the full phase
plan and `docs/PRD.md` for the complete requirements.

## Building it

Flutter `>=3.35.0` / Dart SDK `^3.10.0`, Android only (no `ios/` target — see
`docs/architecture.md` for why).

```
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter build apk --debug
```

## Repository layout

- `lib/` — the app: `core/` (money, crypto, text/redaction), `data/`
  (encrypted storage, DAOs), `features/` (ingestion, parsing, security),
  `presentation/` (screens, providers, l10n).
- `android/` — the one platform target.
- `test/` — unit, widget, and fixture-corpus tests.
- `docs/` — the product record: `PRD.md`, `architecture.md`, `brand.md`,
  `design.md`, `mockups/`, `test-plan.md`, `defects.md`. This is the paper
  trail for every decision in the app.

## How this gets built

Massrofy is built by an autonomous Claude Code agent team — see `CLAUDE.md`
for how that works, if you're curious about the process rather than the
product.

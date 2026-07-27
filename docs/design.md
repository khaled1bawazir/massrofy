STATUS: APPROVED
# Massrofy — UI/UX Design Specification

**Version:** 2.1 (post-review revision — typography swap to brand.md v1.1, icons rebuilt as
inline SVG, two new manual-add screens; supersedes v2.0. See changelog below.)
**Date:** 2026-07-27
**Author:** ui-ux-designer agent (Gate 2)
**Source of truth for requirements:** `docs/PRD.md` (STATUS: Approved)
**Source of truth for visual tokens:** `docs/brand.md` (STATUS: DRAFT — v1.1, awaiting approval
alongside this document)
**Planning context:** `docs/build-plan.md` (design flags D-1..D-12 answered throughout; see §10)
**Platform:** Android / Flutter, single build, **Arabic (RTL) as the primary, first-designed
layout** + English (LTR) as a fully-supported second locale, side-loaded APK.

**Changelog:**
- **v2.1 (2026-07-27, same-day revision after human mockup review):**
  1. **Typography.** `docs/brand.md` was updated to v1.1 (Tajawal + Manrope replacing IBM Plex
     Sans / IBM Plex Sans Arabic). Every mockup's Google Fonts `<link>` and `font-family` CSS
     now loads **Tajawal** (Arabic-primary pages) / **Manrope** (the `home-en.html` LTR mirror
     and all monetary/tabular-numeral values in every page), with the §3.1 weight-mapping rule
     (Tajawal **Bold 700** standing in for Manrope **SemiBold 600**) applied to every Arabic
     heading-level string (page titles, H1/H2 screen and section titles, sheet/dialog titles).
     See §2.2 below.
  2. **Icons.** The human reviewer found that Material Symbols Outlined (loaded as a ligature
     icon font via Google Fonts) did not render reliably when opening the mockup files locally
     — a real risk of any ligature-based icon font depending on a live webfont fetch. Every icon
     across all 19 files is now an **inline SVG** referencing a per-file `<symbol>` sprite
     (injected once at the top of `<body>`, zero external request), stroke-based at a consistent
     24×24 viewBox / ~1.75px stroke / round caps &amp; joins, per brand.md §5.1. This is a pure
     rendering-mechanism fix — the icon *inventory* and meaning at each screen is unchanged.
  3. **Two new screens** — Add Account Manually and Add Card Manually — added under the Banks
     hierarchy, reachable via a new "+" entry point on `banks.html`. This is a **human-requested
     scope extension beyond the literal text of US-B15** (which only specifies auto-creation
     from parsed SMS); flagged explicitly in the decision log (§10, new row D-13) with a
     recommendation to raise a formal PRD addendum before `/build` if strict requirement
     traceability is needed for these two screens.
  - v2.0 (2026-07-27): Initial rewrite against the approved brand system (superseded above).

> **No external design tool is used for this product.** Every screen below is built as a
> self-contained HTML file in `docs/mockups/`, viewable by double-clicking it open in any
> browser — no build step, no plugin, no account. Open `docs/mockups/index.html` to click
> through every screen and every state. Any earlier note in this repository's history about
> Penpot or any other design-tool integration is stale and does not apply to this workflow;
> the mockups themselves are the source of visual truth, and this document is kept in sync
> with them.

---

## 0. How to read this document

1. §1 Information architecture — the navigation map.
2. §2 Design tokens — colour, type, spacing, icons, motion, taken verbatim from `docs/brand.md`.
3. §3 Global rules — RTL-first layout, digits, masking/reveal, non-colour indicators, baseline states.
4. §4 Default category list (OQ-18).
5. §5 Component library — reusable, platform-neutral components.
6. §6 The category-correction flow — the single most important interaction (NFR-U7).
7. §7 Screen inventory — every screen, purpose, key elements, states, and **its mockup file**.
8. §8 User flows — step-by-step journeys per epic.
9. §9 Accessibility notes.
10. §10 Design-decision log answering build-plan flags D-1..D-12.
11. §11 Component ↔ engineering mapping notes.
12. §12 Approval gate.

---

## 1. Information architecture

```
Lock Gate (on launch / resume)                              → docs/mockups/lock-gate.html
        │
        ▼
First-run? ──yes──▶ Onboarding (S-01..S-07)                  → docs/mockups/onboarding.html
        │no
        ▼
┌───────────────────────── Bottom Navigation (4 tabs) ─────────────────────────┐
│  [الرئيسية]      [المعاملات]        [التقارير]        [المزيد]                │
│  [Home]        [Transactions]        [Reports]        [More]                 │
└────────────────────────────────────────────────────────────────────────────┘
   Home (S-08)      Txn List (S-10)      Reports Hub     More menu (S-40 root)
     │                  │  ▲                (S-28)            │
     │ needs-review     │  │ tap chip          │              ├─ Banks (S-21)
     │ badge            │  │ opens picker       ├─ Category    ├─ Categories (S-14)
     ▼                  ▼  │                    │  breakdown   ├─ Learned Rules (S-16)
Needs Review        Txn Detail (S-11)           │  (S-29)      ├─ Budgets (S-33)
Inbox (S-18)         │     │                    ├─ Card        ├─ Statement Import (S-36)
                     │     ├─ Category Picker    │  breakdown   ├─ Recently Deleted (S-44)
                     │     │  sheet (S-12/13)    │  (S-30)      ├─ Search (S-26, also
                     │     ├─ Original SMS panel ├─ Month-over- │  reachable from Txn List)
                     │     ├─ Edit form (S-20)   │  month (S-31)├─ Settings (S-40)
                     │     ├─ Audit history      └─ Spent vs        ├─ Privacy (S-41)
                     │     │  (S-45)                Kept (S-32)     ├─ Export (S-42)
                     │     └─ Delete → Recently                     ├─ Erase all (S-43)
                     ▼        Deleted (S-44)                        ├─ App lock (S-07 reused)
              Manual Add (S-20, "+" FAB from Home or Txn List)      └─ Backup & Restore

Banks (S-21) ─▶ Bank Detail (S-22) ─▶ Account Detail (S-23) / Card Detail (S-24)
     │ "+"                                  │ rename (S-25)         │ rename (S-25)
     ▼                                       ▼                       ▼
Add Account / Add Card (S-48/S-49,    filtered Txn List        filtered Txn List
new in v2.1 — see §10 D-13)                                        + linked account chip

Statement Import (S-36) ─▶ Reconciliation Progress (S-37) ─▶ Results (S-38)
                                                                  ├─ Matched tab
                                                                  ├─ Added tab (→ Txn Detail)
                                                                  └─ Unmatched tab → (S-39)
```

Four-tab bottom navigation (Home / Transactions / Reports / More) keeps the two
highest-frequency destinations (Home, Transaction list — where correction happens) one tap
away at all times, satisfying NFR-U7 at the navigation level, not just inside the correction
flow itself. **The tab order and every chevron/back affordance mirror under Arabic RTL**,
which is the app's primary, first-designed direction (see §3.1) — `docs/mockups/home-en.html`
is kept as the one explicit English/LTR reference showing the mirrored counterpart of Home.

---

## 2. Design tokens

All values are taken **verbatim** from `docs/brand.md` (the approved token source) — this
document does not reinvent or approximate them. The mobile-engineer maps them directly to
Flutter `ThemeData`/`TextStyle`; token names use `color.name` / `type.name` dot-notation to
match the brand quick-reference table (`docs/brand.md` §7).

### 2.1 Colour

| Token | Hex | Usage in this design |
|---|---|---|
| `color.primary` (Massrofy Navy) | `#0B3D62` | App bar, primary buttons, active nav tab, links, focus rings |
| `color.primary.pressed` | `#0A3454` | Pressed/hover state of primary controls |
| `color.primary.tint10` | `#E7EEF4` | Selected-row backgrounds, info banners, linked-account chip |
| `color.secondary` (Sadu Gold) | `#B8842E` | Accent only — budget-progress fill (on-track), the wordmark accent dot. Icons/borders/large text only, never small body text |
| `color.secondary.text` | `#8A5F1E` | Small text/links needing the accent meaning (5.6:1 on white) |
| `color.secondary.tint10` | `#F7EEDD` | Badge/chip background washes |
| `color.ink.900` | `#101418` | Primary text, headings, monetary amounts |
| `color.ink.700` | `#3A434C` | Secondary text, subtitles, labels |
| `color.ink.500` | `#6B7580` | Tertiary/meta text (timestamps, masked IDs) — the floor for any text colour |
| `color.ink.300` | `#C7CDD4` | Borders, dividers, disabled outlines — decorative only, never text |
| `color.ink.100` | `#EEF1F4` | Subtle fills: input backgrounds, unselected chips, dividers |
| `color.surface` | `#F7F8FA` | App/screen background |
| `color.white` | `#FFFFFF` | Cards, sheets, dialogs |
| `color.success` | `#1E7A46` (tint `#E5F3EA`) | Credit/refund/income amounts, "on track" budget state |
| `color.error` | `#B3261E` (tint `#FBEAE9`) | Over-budget, failed parse, destructive actions |
| `color.warning.text` | `#8A5A00` | "Needs review" label text, near-limit budget text |
| `color.warning.fill` | `#F2A93B` | Needs-review/near-limit **fill/icon only**, never as small text on white |
| `color.info` | `#0B6E8C` (tint `#E4F1F5`) | Auto-categorized indicator, informational banners |

**Categorical / chart palette** (§2.5 of `docs/brand.md`) — used only in Reports, never reused
for a semantic meaning: `chart-navy #0B3D62`, `chart-gold #B8842E`, `chart-teal #2E7D8C`,
`chart-plum #6B4C8A`, `chart-terracotta #B25D3F`, `chart-slate #55708A`, `chart-olive #7A7A3E`,
`chart-rose #A34E63`, and `chart-uncategorized` fixed to `color.ink.500 #6B7580` so
"Uncategorized" always reads as unassigned, never as a themed category slice.

### 2.2 Typography (updated in v2.1 — brand.md v1.1 pairing)

| Token | Family | Weight | Size/line-height | Usage |
|---|---|---|---|---|
| Arabic runs | **Tajawal** | — | — | Any Arabic-script text (Arabic-primary pages set it first in the font stack) |
| Latin runs | **Manrope** | — | — | Any Latin-script text, incl. transliterated merchant names; first in the stack on `home-en.html` |
| Display | — | SemiBold (600) / **Tajawal Bold 700 for Arabic runs** | 32/40 | Onboarding hero moments only |
| H1 (screen title) | — | SemiBold (600) / **Tajawal Bold 700 for Arabic runs** | 24/32 | Screen/page titles |
| H2 (section header) | — | SemiBold (600) / **Tajawal Bold 700 for Arabic runs** | 20/28 | Section headers within a screen |
| H3 (card/list header) | — | Medium (500) | 17/24 | Card titles, list-group headers (Medium maps 1:1, no substitution needed) |
| Body Large | — | Regular (400) | 17/24 | Primary reading text — transaction detail, settings rows |
| Body | — | Regular (400) | 15/22 | Default list-row text, form labels |
| Body Small / Caption | — | Regular (400) | 13/18 | Timestamps, helper text |
| **Amount — Large** | — | SemiBold (600), Manrope tabular figures | 34/40 | The one hero number on a screen (Home total) — always Manrope, never substituted, even in Arabic UI (numerals are never Tajawal) |
| **Amount — Row** | — | Medium (500), Manrope tabular figures | 17/24 | Amount in a list row or summary line |
| Label / Button | — | Medium (500), +0.1 letter-spacing | 15/20 | Buttons, tabs, chips |
| Overline | — | SemiBold (600), uppercase (Latin only) | 12/16 | Small section tags — **never uppercase Arabic** |

**Weight-mapping rule applied throughout the mockups (brand.md §3.1):** Tajawal has no 600
(SemiBold) step — it jumps 500 Medium → 700 Bold. Every mockup CSS rule that sets a heading to
`font-weight:600` on an Arabic-primary page (page titles, `<h1>`/`<h2>`, sheet/dialog titles,
the wordmark) is set to `font-weight:700` instead, per the documented substitution. Amount/
numeral classes (`.amount-lg`, `.li-amount`, `.amt`, `.pct`, `.total`, all `.num`-bearing
elements) are **not** substituted — they always render in Manrope's native weight steps,
because amounts are Western-Arabic-numeral, Manrope-tabular-figure runs regardless of
surrounding script (brand.md §3.1, §3.2 footnote).

**Loading mechanism:** Both families are Google Fonts, bundled offline as local assets in the
Flutter build (no runtime fetch, consistent with NFR-R4/no telemetry). The HTML mockups load
them via a single Google Fonts `<link>` (`family=Manrope:wght@400;500;600;700&family=Tajawal:wght@400;500;700`)
for browser preview only — **this is an accepted, explicitly-flagged deviation** from
brand.md §3.1's instruction to self-host font files even in the preview mockups: the
`ui-ux-designer` agent has no binary-file-download tool available in this workflow to fetch
and commit static Tajawal/Manrope weight files, so the mockups fall back to the CDN link
(consistent with how v2.0 already treated fonts, and unlike the icon-font problem, a live
Google Fonts CSS `<link>` did render correctly in the human's review environment). The
production Flutter app must still bundle both families as local assets per brand.md — this
mockup-only CDN link is not a precedent for the shipped app.

**Icons — inline SVG, not a font (fixes v2.0's rendering defect):** v2.0 used "Material Symbols
Outlined" as a ligature icon font loaded from Google Fonts; the human reviewer found the icons
did not render when opening the files locally (a ligature icon font requires the webfont to
load *and* the exact ligature text to resolve — a fragile combination for an offline-reviewed
mockup). Every icon in every mockup file is now a **self-contained inline SVG**: each file
carries one hidden `<svg><symbol id="i-name">…</symbol>…</svg>` sprite block right after
`<body>`, and every icon usage is `<svg class="icon"><use href="#i-name"></use></svg>`. All
icons share one stroke style — 24×24 viewBox, ~1.75px stroke, `round` caps/joins, `fill:none`,
sized via `font-size`/`1em` so existing inline size overrides keep working — matching
brand.md §5.1's line-icon spec exactly, with **zero external font/network dependency**. The
icon inventory (which concept gets which glyph) is unchanged from v2.0; only the rendering
mechanism changed.

**Numerals (resolves D-1):** Western Arabic numerals (0–9) everywhere, in both Arabic and
English UI, per `docs/brand.md` §3.1 — this is a brand decision, not re-litigated here.
Every amount/date in the mockups is wrapped so digits and the currency code render as an
internally left-to-right run even inside an RTL sentence (Unicode bidi isolation, per
brand.md §3.3) — implemented in the mockups as `.num { direction:ltr; unicode-bidi:isolate;
font-variant-numeric:tabular-nums; font-family:'Manrope',sans-serif; }`, applied to every
monetary/date value.

**Currency placement:** amount digits first, then the currency code (`45.00 SAR`), in both
languages — never mirrored, per brand.md §3.3.

### 2.3 Spacing, shape, touch targets

4dp grid (4/8/12/16/20/24/32/40/48/64). Radii: 6dp small controls/chips, 12dp cards/list
items, 16dp sheet top corners, pill (999dp) for chips/badges. Minimum touch target 48×48dp
(NFR-U6) — enforced in the mockups even where the visible icon is smaller (invisible padding).

### 2.4 Motion

Minimal and non-decorative: ~150ms ease for sheet open/close and toasts; skeleton loaders use
a low-contrast shimmer capped at ~1.2s so it never distracts from reading numbers (matches
brand.md's "calm" personality trait — no urgency banners, no manufactured excitement).

---

## 3. Global rules

### 3.1 Arabic-first RTL (resolves D-1, D-5 layout aspects)

**Arabic RTL is the primary, first-designed layout for every screen in this product** — of
the 18 screen mockup files (16 from v2.0 plus the 2 new manual-add screens in v2.1), 17 are
authored `dir="rtl" lang="ar"` as their default state, per the task brief and PRD NFR-U8.
English/LTR is a fully-supported second locale that mirrors the same layout; the one
exception, `docs/mockups/home-en.html`, is kept as one explicit side-by-side reference showing
exactly how Home mirrors, so engineers building the LTR variant have a concrete target rather
than an abstract rule.

- The entire app mirrors under Arabic locale: navigation tab order (visually) reverses, list
  leading/trailing icons swap sides, the back chevron points toward the reading-start edge
  (implemented in the mockups as `transform:scaleX(-1)` on the back-arrow glyph), swipe-to-
  reveal actions swipe from the opposite edge, and progress bars fill toward the reading
  direction.
- **Mixed-direction content is isolated, not flipped.** A transaction row in Arabic reads
  right-to-left overall, but the merchant name (which may already be Latin script — PRD §3.4),
  the amount, and the date remain internally left-to-right within their own run. E.g. an
  Arabic row reads *"Panda Foods — 45.00 SAR — اليوم، 14:20"* with "45.00 SAR" itself
  left-to-right even though the sentence flows right-to-left.
- Currency placement is fixed, not mirrored (§2.2).
- Category glyphs, the app mark, and numerals do **not** mirror; directional chevrons and
  arrows do.
- Toggle switches and radio selections use CSS logical properties (`inset-inline-start`) in
  the mockups rather than hard-coded left/right, so the same markup is correct in both
  directions without special-casing.

### 3.2 Masking and reveal of sensitive data (NFR-S2)

Two distinct mechanisms, because two distinct things are protected:

1. **Card/account identifiers.** The app never stores or has access to a full PAN — only the
   masked form banks already send in SMS (e.g. last 4 digits). This masking is **permanent,
   not a reveal toggle** — there is nothing more to reveal, by design. Every surface (list
   rows, bank/account/card pages, transaction detail) always shows the masked form: `•••• 4821`.
   An auto-created, not-yet-renamed instrument is labelled *by* its masked identifier
   (AC-B15.2) — see the `•••• 7765` card tile in `docs/mockups/banks.html`.
2. **Amount/total privacy (shoulder-surfing).** Home and Reports include a **Privacy Mode
   toggle** (eye icon, top-right). Default: visible. Tapping it masks monetary figures as a
   length-preserving mask while merchant names/categories/dates remain visible (list stays
   browsable). Session-only state, resets to visible on next unlock. This is a
   designer-proposed control that goes beyond PAN masking, since totals are the more commonly
   glanced-at sensitive figure day to day. Shown as the eye icon in the Home app bar
   (`docs/mockups/home.html`).

### 3.3 Non-colour indicators (NFR-U4) (resolves D-4)

| Signal | Colour (reinforcement only) | Non-colour indicator (the actual signal) |
|---|---|---|
| Debit / spend | `color.ink.900` (deliberately **not** red — see brand.md §2.3: colouring the majority-case red is a false alarm) | Leading debit icon + amount always prefixed with **"−"** + label "Debit"/"مدين" for screen readers |
| Credit / income / refund | `color.success` | Leading credit icon + amount always prefixed with **"+"** + label "Credit"/"دائن" |
| Needs review | `color.warning.fill` tint, `color.warning.text` label | A flag icon + the literal words **"Needs review" / "بحاجة إلى مراجعة"**, never a bare coloured dot |
| Internal transfer (excluded from spend) | neutral `color.ink.700` | A bidirectional-arrow icon + label **"Internal transfer" / "تحويل داخلي"**; no +/− prefix at all (neither spend nor income) |
| Manually added transaction | neutral | A pencil-badge icon + label **"Manual" / "يدوي"** |
| Auto-categorized by rule | neutral | A sparkle/auto icon + caption **"Auto: {rule}" / "تلقائي: {قاعدة}"** |
| Possible duplicate | `color.warning.fill` | Icon (⚠) + label **"Possible duplicate" / "تكرار محتمل"** |
| Locked / unauthenticated | neutral, opaque scrim | A padlock icon centered with label **"Unlock to view" / "افتح القفل للعرض"** |

Every row above is "icon + label", never "icon or colour" — verified against the mockups by
converting each state to greyscale during the accessibility audit (P9/KHA-51).

### 3.4 Baseline states every screen must define

Per screen in §7, the full set considered: **Loading, Empty, Populated/Success, Error
(recoverable), Locked (app-lock gate), Unauthorized (SMS permission not granted/revoked),
Session-expired-equivalent (re-auth required after backgrounding), Offline (informational
only — the app is fully offline-capable per NFR-R4; "offline" is never a blocking state,
only relevant to Statement Import's file picker and Backup, which queue for later),
Filtered-empty (a filter/search returned nothing).** Every mockup file groups its relevant
states as clearly-labelled side-by-side sections so the human reviewer can compare them
without navigating a running app.

---

## 4. Default starting category list (resolves OQ-18 / D-2)

Presented at first-run (`docs/mockups/onboarding.html`, S-06) as an editable, pre-checked
list (all checked by default) so the user starts productive immediately, per US-C3/AC-C3.1-4.
"Uncategorized" is a system category: always present, cannot be deleted or renamed (the
fallback required by AC-C1.1/C1.2).

Categories split into two conceptual buckets, both in the picker UI (§6) and in
`docs/mockups/categories-rules.html`: **Spending** categories (compete for budget share,
appear in category-breakdown reports) and **Money movement** categories (income/transfers/
withdrawals — captured and shown per US-B10/C15, but excluded from "spend" totals and cannot
carry a budget, per US-B11/G1).

### Spending categories (default, editable)

Icon names below are the semantic Material Symbols identifier (still the base icon library for
the Flutter app per brand.md §5.1 — Flutter bundles Material Symbols as vector icon data, so it
never had the offline ligature-font rendering problem the v2.0 HTML mockups had). In the HTML
mockups, each name maps to an inline SVG symbol of the same id (e.g. `shopping_cart` → the
`#i-shopping_cart` `<symbol>`), per the icon-rendering fix in §2.2.

| # | Category (Arabic / English) | Icon (Material Symbols) | Notes |
|---|---|---|---|
| 1 | البقالة / Groceries | `shopping_cart` | Supermarkets, grocery delivery |
| 2 | مطاعم ومقاهي / Dining & Cafés | `restaurant` | Restaurants, cafés, food delivery apps |
| 3 | تنقل ووقود / Transport & Fuel | `directions_car` | Fuel stations, ride-hailing, parking, tolls |
| 4 | فواتير وخدمات / Utilities & Bills | `bolt` | Electricity/water/telecom bill-payment messages (§3.4 biller-code pattern) |
| 5 | تسوق ومتاجر / Shopping & Retail | `shopping_bag` | General retail, e-commerce, clothing |
| 6 | ترفيه واشتراكات / Entertainment & Subscriptions | `movie` | Streaming, cinema, recurring subscriptions |
| 7 | صحة وصيدليات / Health & Pharmacy | `medical_services` | Pharmacies, clinics, hospitals |
| 8 | قروض وأقساط / Loan & Installments | `account_balance` | Finance/loan installment deductions reporting a remaining balance — kept distinct per §3.4 |
| 9 | رسوم وعمولات / Fees & Charges | `receipt_long` | Standalone VAT/fee debits, card annual fees, FX/international fee line items |
| 10 | غير مصنف / Uncategorized | `help_outline` | System default; always present; cannot be deleted/renamed |

### Money-movement categories (default, editable, no budget)

| # | Category | Icon | Notes |
|---|---|---|---|
| 11 | راتب ودخل / Salary & Income | `payments` | Shown in Spent-vs-Kept, not in spend breakdowns |
| 12 | سحب نقدي / Cash & ATM Withdrawal | `local_atm` | Reclassifiable to a spend category via manual edit |
| 13 | تحويل داخلي / Internal Transfer | `sync_alt` | Always excluded from spend totals; system-assigned |
| — | (ambiguous transfer) | `help_outline` + warning | Not a category — a flag state pending the user's own/third-party decision (AC-B11.2), see `docs/mockups/needs-review.html` |

Rationale: the list is short enough to scan in one screen (13 items incl. Uncategorized) but
keeps **Loan & Installments** and **Fees & Charges** as their own categories, because §3.4
shows both message types are structurally and semantically different from ordinary purchases
and lumping them in would silently corrupt category-breakdown totals (AC-C1.3, AC-E2.1).

---

## 5. Component library

Described platform-neutrally: a name, purpose, props/variants, states. React would implement
each as a function component with these props; Flutter as a `StatelessWidget`/
`StatefulWidget` with equivalent named parameters. Every component's colours/type reference
the tokens in §2 directly.

| Component | Purpose | Props / variants | States | Seen in |
|---|---|---|---|---|
| **AppBar** | Top navigation bar | `title`, `leading` (back, mirrors in RTL), `actions[]` | default, elevated on scroll | all screens |
| **BottomNav** | 4-tab primary navigation | `items`, `activeIndex` | default (badge lives on Home's review card, not the nav bar, to avoid duplicating the count) | `home.html`, `transactions.html` |
| **MonthTotalCard** | Home's headline figure | `amount`, `currency`, `periodLabel`, `deltaVsPrevMonth?`, `privacyMasked` | loading, empty, populated, masked | `home.html` |
| **BudgetProgressBar** | Shows spend vs limit | `label`, `spent`, `limit`, `percent`, `overBudget` | under (gold fill), near-limit ≥80% (warning fill + "Near limit" text), over (error fill + "Over budget" text) | `home.html`, `budgets.html` |
| **ReviewCountCard** | "Needs review: N" | `count`, `onTap` | zero ("All caught up ✓", recedes visually), non-zero (flag + count, tappable) | `home.html` |
| **TransactionListItem** | One row in any list | `merchant`, `amount`, `sign`, `categoryChip`, `dateTime`, `isManual`, `isFlaggedReview`, `isPossibleDuplicate` | default, flagged-review (leading accent bar), deleted-pending-undo, swipe-open | `transactions.html`, `needs-review.html` |
| **CategoryChip** | Tappable pill for a transaction's category | `icon`, `label`, `variant`, `auto` | default, pressed (opens Category Picker), disabled | `transaction-detail.html`, `category-correction.html` |
| **CategoryPicker** | Bottom sheet for the correction flow | `currentCategory`, `merchantName`, `recentCategories[]`, `allCategories[]` | default grid, search-filtered, empty-search | `category-correction.html` |
| **ScopeChoiceInline** | In-sheet scope question after a category is picked | `merchantName`, `defaultScope`, `affectedCount`, `autoConfirmSeconds` | countdown-to-default, user-overridden, confirmed | `category-correction.html` |
| **MaskedIdentifier** | Renders `•••• 4821` style text | `last4`, `network?`, `friendlyName?` | named, unnamed (masked ID is the primary label) | `banks.html` |
| **PrivacyModeToggle** | Eye icon, masks amounts | `masked`, `onToggle` | visible, masked | `home.html` |
| **BankListItem / AccountTile / CardTile** | Rows in bank hierarchy screens | `name`, `type`, `maskedId`, `total`, `linkedAccountName?` | default, unlinked-card, auto-created-unnamed | `banks.html` |
| **AddInstrumentForm** (new, v2.1) | Manual-add form shared shape for both accounts and cards | `instrumentKind` (`account`\|`card`), `bankOptions[]`, `nickname`, `typeChoice`, `startingBalance?` (account only), `last4?`/`settlementAccountId?` (card only) | empty (save disabled until required fields valid), validation-error (per-field inline message), success (summary + "add another") | `add-account.html`, `add-card.html` |
| **SmsOriginalTextPanel** | Collapsible raw-SMS viewer | `originalText`, `sender`, `receivedAt` | collapsed, expanded, "no original text" (manual entries) | `transaction-detail.html` |
| **AuditHistoryEntry** | One line in change-history | `timestamp`, `actor`, `ruleName?`, `field`, `fromValue`, `toValue` | user-edit, system-auto, deletion, restoration (person vs. gear icon) | `audit-history.html` |
| **EmptyState** | Generic empty/zero-data pattern | `icon`, `headline`, `body`, `primaryAction?` | used across Home, Transactions, Budgets, Learned Rules, Recently Deleted | most screens |
| **ErrorState / banner** | Recoverable error pattern | `icon`, `message`, `retryAction?` | import interrupted, statement parse failure, permission revoked | `onboarding.html`, `statement-import.html`, `home.html` |
| **PermissionRationaleCard** | Explains SMS access before the OS prompt | `bulletPoints[]`, `primaryAction`, `secondaryAction` | pre-request, denied, revoked | `onboarding.html` |
| **ConfirmationDialog** | Modal confirm/cancel | `title`, `body`, `confirmLabel`, `destructive` | used for delete, erase-all, rule deletion, category deletion | `categories-rules.html`, `privacy-data.html` |
| **SearchBar** | Text search with clear | `query`, `placeholder` | empty, typing, no-results | `transactions.html` |
| **FilterSheet** | Multi-facet filter | `dateRange`, `categories[]`, `cards[]`, `amountRange` | default, applied (badge), no-results | `transactions.html` |
| **SegmentedControl** | Tab-like switch within a screen | `segments[]`, `activeIndex` | used for Accounts/Cards, Matched/Added/Unmatched, Unparsed/Low-confidence | `banks.html`, `statement-import.html`, `needs-review.html` |
| **Toast/Snackbar** | Transient confirmation, often with Undo | `message`, `actionLabel?` | info, success, with-undo | `category-correction.html` |
| **LockGateScreen** | Full-screen auth gate | `method`, `onSuccess`, `onFail` | idle, authenticating, failed, locked-out, session-expired-banner | `lock-gate.html` |
| **RecentlyDeletedItem** | Row in Recently Deleted | `transaction summary`, `deletedAt`, `onRestore` | default, restored | `transaction-detail.html` (restore banner variant) |

---

## 6. The category-correction flow (deep dive) — resolves D-3, NFR-U7, AC-C2.2, US-D5

**Mockup: `docs/mockups/category-correction.html`.** This is the single highest-frequency
interaction the learning loop depends on. Design goal: **the category itself is corrected in
exactly two taps from any transaction context, with zero screen navigation** — the scope
question (US-D5) is offered as a lightweight, smart-defaulted, in-place extension that never
blocks or delays the core correction.

### 6.1 Entry points (all lead to the same sheet)

- **Transaction List row** — tap the `CategoryChip` directly on the row.
- **Transaction Detail** — tap the category field.
- **Needs Review Inbox** — tap the `CategoryChip` on a flagged row; confirming or changing
  the category here also clears the review flag (AC-C4.3).
- **Statement Reconciliation "Added" rows** — same sheet, same rule store (AC-H3.1).

None of these entry points is itself one of the "two taps" — they are "being in the
transaction's context," which AC-C2.2 explicitly allows.

### 6.2 Tap 1 — open the picker

Tapping the `CategoryChip` opens **CategoryPicker**, a bottom sheet layered over the current
screen — a sheet, not a navigation push, so the user never "leaves" the transaction context
and no screen-count is spent per AC-C2.2's "no more than two screens" bar. See the first two
frames of `category-correction.html` for the exact layout: a search field, a "Recent"
row (last 3 categories used), the full Spending grid, and the Money-movement group.

### 6.3 Tap 2 — pick the category

Tapping any category cell **immediately applies it** — no separate "Confirm" button. The
picker gives instant feedback and the underlying list/detail screen behind it updates its
chip in place. **At this point the correction is complete: 2 taps, 0 screen changes** —
satisfies NFR-U7 and AC-C2.2 on its own.

### 6.4 The scope question — offered, never blocking (US-D5, AC-C2.3, AC-D5.1-3)

Immediately after tap 2, the **same sheet** morphs its lower section in place into a compact
scope strip (third frame of the mockup):

- **Default = "This + future"**, pre-selected, because that trains the learning loop
  (US-D2/D3) and is very likely the user's intent.
- A **3-second auto-confirm** timer applies the default if the user does nothing further —
  the fully passive flow is still exactly 2 taps.
- A **3rd, optional tap** on "Just this transaction" overrides the default before the timer
  fires (US-D5's one-off case, e.g. a supermarket purchase that was actually a gift).
- On confirmation, a toast states the count — *"Updated 12 transactions from Panda Foods to
  Groceries"* — with an "Undo" that reverts the rule change, not just this transaction.
- If the transaction's current category already matches the merchant's learned rule (the user
  is just confirming a flagged guess, AC-C4.3), the scope strip is skipped entirely.

### 6.5 Creating a brand-new category inline

Tapping "+ New category" expands an inline row within the same sheet (name field, icon
picker, Spending/Money-movement toggle) rather than pushing a new screen. Duplicate-name
validation happens inline (AC-C3.2) — see the last frame of the mockup.

### 6.6 Why this design meets the bar

- **Tap-count:** 2 taps (chip → category) is the complete, sufficient correction.
- **Screen-count:** 0 additional screens — one sheet, layered, dismissible.
- **The scope requirement (US-D5) adds no friction** for the common case, and exactly one
  clearly-labelled extra tap for the one-off case.
- **Reversibility as a friction-reducer:** the default auto-confirms; undo (not a blocking
  dialog) is the safety net — appropriate because a category correction is low-stakes, unlike
  delete or erase-all, which do use blocking confirmation (see `privacy-data.html`).

---

## 7. Screen inventory

Each entry: **ID — Name.** Purpose. Key elements. States shown. Related ACs. **Mockup file.**

### Onboarding — `docs/mockups/onboarding.html`

**S-01 — Welcome.** First impression before any permission ask. Wordmark, one-line value
prop, "Get started" CTA. State: static.

**S-02 — SMS Permission Rationale.** Explains *why* before the OS prompt fires (D-9,
AC-A1.2). Bullet list of guarantees (on-device, never shared, revocable, noise ignored).
States: pre-request; declined → S-04.

**S-03 — OS Permission Dialog.** Native Android dialog, not designed here.

**S-04 — Permission Denied / Limited Mode.** Covers AC-A1.2 (never a blank empty state) and
AC-A1.3 (revoked mid-life). "Open Settings" deep link + "Add manually" fallback CTA.

**S-05 — Historical Import Progress.** Determinate progress, live count, dismissible
(non-blocking per NFR-R2). States: running, complete.

**S-06 — Default Categories Proposal.** The §4 list, pre-checked, editable, rename-inline.

**S-07 — App Lock Setup.** Biometric/PIN choice, offered once during onboarding.

### Home / dashboard

**S-08 — Home.** Mockup: `docs/mockups/home.html` (+ `home-en.html` LTR mirror). Purpose:
current-month total visible without navigation (AC-E1.1). Elements: `MonthTotalCard`,
`ReviewCountCard`, mini `BudgetProgressBar` list (top 3), recent-transactions preview, FAB.
States shown: **Loading** (skeleton), **Empty** (AC-E1.3 — explicit `0.00 SAR`, never blank),
**Populated/Success**, **Permission-revoked banner** (persistent, AC-A1.3).

**S-09 — App Lock Gate.** Mockup: `docs/mockups/lock-gate.html`. Full-screen, shown on cold
launch and every foreground-resume (AC-F1.1-3). States shown: **idle** (biometric prompt),
**failed** (generic message, shake, retry), **PIN fallback**, **locked-out** (too many
attempts), **session-expired-equivalent** (resumed from background banner). Nothing
underneath ever renders pre-success — the scrim is opaque, not blurred-through.

### Transactions

**S-10 — Transaction List.** Mockup: `docs/mockups/transactions.html`. Period selector,
search/filter icons, running filtered total, FAB. States shown: **Loading**, **Populated**
(mixed debit/credit/transfer/flagged/manual rows, all with icon+label indicators per §3.3),
**true Empty** ("No transactions yet…"), **Filtered-empty** (AC-E5.3, distinct copy from
true-empty).

**S-11 — Transaction Detail.** Mockup: `docs/mockups/transaction-detail.html`. Header
(merchant, signed amount, `CategoryChip`), field list, expandable `SmsOriginalTextPanel`,
change-history link, Edit/Delete. States shown: **Success**, **Missing optional field**
(literal "Not stated in message" text, AC-B1.3), **Edited** (auto-detected vs. user-edit
shown inline, AC-B5.2), **Manually-added** (no SMS panel, `Manual` badge), **Viewing a
deleted transaction** (restore banner, US-B8).

**S-12/13 — Category Picker + Scope Choice.** See §6 in full. Mockup:
`docs/mockups/category-correction.html`.

**S-14 — Category Management.** Mockup: `docs/mockups/categories-rules.html`. List of all
categories (both groups), rename/delete affordances, "+ New category". "Uncategorized"'s
delete icon is absent with an accessible tooltip.

**S-15 — Reassignment dialog.** Same file. Opens on category delete: "This category has 12
transactions. Reassign to: [picker] or set to Uncategorized" — blocks the delete until chosen
(AC-C3.3).

**S-16 — Learned (Merchant) Rules.** Same file. Search, `{Merchant} → {Category}` rows,
"recently changed" section on top. States shown: **empty**, **populated**.

**S-17 — Edit a rule.** Same file. Category re-picker + AC-D4.4's required prompt: "Also
re-apply to this merchant's existing transactions? [Yes, N] [No, going forward only]".

**S-18 — Needs Review Inbox.** Mockup: `docs/mockups/needs-review.html`. Two tabs —
Unparsed SMS vs. Low-confidence — never conflated. States shown: **Unparsed tab** (raw text
preview, "Fill in details" / "Not a transaction"), **Low-confidence tab** (normal rows with
the review flag, tapping the chip opens the same S-12/13 flow), **empty per tab** ("Nothing
needs review right now ✓"). Also hosts **possible-duplicate** (AC-A5.2) and
**ambiguous-transfer** (AC-B11.2) review cards — never auto-resolved.

**S-19 — Complete Unparsed SMS.** Same file. Pre-filled with whatever the parser extracted;
remaining fields required; validation names the missing field explicitly (AC-B4.2).

**S-20 — Manual Transaction Entry / Edit.** (Form fields specified; a dedicated static frame
is folded into `transaction-detail.html`'s Edit action and `needs-review.html`'s S-19 form,
since the fields are identical per US-B4/B5 — amount+currency, date/time, merchant, category,
instrument/cash, type, notes.)

### Banks, accounts, cards — `docs/mockups/banks.html`

**S-21 — Banks List.** Each bank with a combined period total. States: empty (before any SMS
seen), populated.

**S-22 — Bank Detail.** Combined total, `SegmentedControl` (Accounts / Cards) so account
activity (transfers, bills, fees, income) and card activity (POS/online) are never merged
(AC-B13.3).

**S-23 — Account Detail.** Filtered transaction list scoped to one account + its own total
(AC-B2.3), rename affordance.

**S-24 — Card Detail.** States shown: **linked** (shows the linked settlement account as a
tappable chip, AC-B14.2), **unlinked** (neutral caption "Not linked to an account yet",
AC-B14.3 — not an error).

**S-25 — Rename sheet.** Text field + Save, for any auto-created instrument (AC-B3.1,
AC-B15.2).

**S-48 — Add Account Manually.** Mockup: `docs/mockups/add-account.html`. **New in v2.1 —
extends US-B15 at human request during design review; see §10 D-13.** Reached via a new "+"
entry point on `banks.html` (Banks List FAB, and an inline "add account to this bank" tile on
Bank Detail). Purpose: create an account before any SMS has mentioned it (e.g. a savings
account the user wants tracked from day one). Elements: bank picker (from the same known-bank
list used elsewhere in `banks.html`, plus an "other bank" fallback), account nickname
(required), account type (segmented: current/salary vs. savings), optional starting balance
(explicitly optional — leaving it blank is a first-class choice, framed as "start tracking from
the first SMS instead"). States shown: **Empty** (Save disabled until bank + nickname are
present), **Error/validation** (inline per-field message — no bank selected, empty nickname —
never a generic "invalid input", per brand voice principle 4), **Success** (confirmation
summary + "go to bank detail" / "add another account"). No loading/locked/session states
needed beyond the app-wide lock gate (S-09), which already gates this screen like all others.

**S-49 — Add Card Manually.** Mockup: `docs/mockups/add-card.html`. **New in v2.1 — extends
US-B15 at human request during design review; see §10 D-13.** Same entry points as S-48.
Purpose: create a card before any SMS has mentioned it. Elements: bank picker (same list),
card nickname (required), card type (credit/debit segmented control), masked-identifier entry
(last 4 digits only — the form never asks for or accepts a full PAN, enforcing NFR-S2 at entry
time, not just at display time), and an optional settlement-account link (dropdown of the
user's existing accounts, reflecting the same card↔account linkage concept as US-B14/AC-B14.1-3
— explicitly optional and re-editable later from Card Detail, not just at creation). States
shown: **Empty** (Save disabled), **Error/validation** (incomplete last-4 entry highlighted
inline — "Enter exactly the last 4 digits, as shown in your bank's SMS" — plus the same
missing-bank/nickname messages as S-48), **Success** (confirmation summary showing the linked
settlement account as a chip, mirroring `banks.html`'s Card Detail linked-account chip).

### Search & filter — folded into `docs/mockups/transactions.html`

**S-26 — Search.** Live results as `TransactionListItem`s. States: results, no-results.

**S-27 — Filter Sheet.** Date range, category (both groups), card/account, amount range.
Applied filters surface as removable chips.

### Reports — `docs/mockups/reports.html`

**S-28 — Reports Hub.** Four summary cards linking to S-29..32, each pre-showing its top
line so the hub itself is informative.

**S-29 — Category Breakdown.** Each category with total + % of period; Uncategorized always
shown as its own line even at zero (AC-E2.3).

**S-30 — Card Breakdown.** Per-card totals; footer "Total" line that equals the period total
shown elsewhere (AC-E3.2, ledger traceability made visible).

**S-31 — Month-over-Month.** States shown: **populated** (bar chart + delta), **insufficient
history** (<2 months — explicit copy replaces any chart, AC-E4.2, never a misleading single-
bar comparison).

**S-32 — Spent vs Kept.** Nets spend against income (AC-B10.3); explicitly excludes internal
transfers (US-B11).

### Budgets — `docs/mockups/budgets.html`

**S-33 — Budgets Overview.** States shown: **empty** ("No budgets set yet…"), **populated**
(over-budget items sort to the top, all with text labels alongside colour, AC-G4.1).

**S-34 — Set / Edit Budget.** Category (or "Overall"), monthly amount, alert toggle
(defaulted on, opt-in *per budget* per AC-G3.2).

**S-35 — Budget Alert.** A local notification mockup (system-level, not a custom screen) —
factual tone, no alarm styling, per brand voice principle 9.

### Statement reconciliation — `docs/mockups/statement-import.html`

**S-36 — Statement Import.** File picker + required "Which bank/account" picker. States:
default, **file-type-unsupported** (suggests CSV per R-6's at-risk PDF note).

**S-37 — Reconciliation Progress.** Non-blocking, resumable framing (same pattern as S-05).

**S-38 — Reconciliation Results.** `SegmentedControl` (Matched/Added/Unmatched, AC-H2.1
counts). Added-tab rows use the same categorization flow (AC-H3.1).

**S-39 — Unmatched resolution.** Raw statement line + "Add as transaction" / "Mark as
already accounted for" / "Ignore" — mirrors the unparsed-SMS pattern deliberately.

### Backup & restore — `docs/mockups/backup-restore.html`

**Backup settings.** Toggle, "last backup" status card explicitly stating the encryption
guarantee (AC-I2.1), size, and what is/isn't included.

**Restore on a new device.** Discovered-backup summary (counts of transactions, banks,
categories, rules, budgets) before committing, per AC-I3.1. States: discovered, **restoring**
(progress).

### Settings, privacy, data control — `docs/mockups/privacy-data.html`, `docs/mockups/audit-history.html`

**S-40 — Settings (More menu root).** Full list: Banks, Categories, Learned Rules, Budgets,
Statement Import, Recently Deleted, App Lock, Backup & Restore, Privacy & Data, Export, Erase
Everything, About.

**S-41 — Privacy & Data Transparency.** Purpose: US-F4, plain-language. Sections: what is
stored, where, what leaves the device (nothing unless backup is on, and then only the
encrypted blob), no analytics/ads.

**S-42 — Export Data.** Mandatory warning interstitial before the file is produced
(AC-F2.3) — a blocking checkbox acknowledgement, not a dismissible toast.

**S-43 — Erase Everything.** The one true hard delete (X17). Three steps shown: explanation
→ type-to-confirm ("اكتب: حذف") → final `ConfirmationDialog`. Deliberately higher friction
than any other destructive action in the app.

**S-44 — Recently Deleted.** (Row pattern specified in the component library; the restore
banner variant is shown live in `transaction-detail.html`'s "viewing a deleted transaction"
state, since the row content and the detail-view restore action are the same underlying
pattern.) States: empty, populated. Not reachable after Erase-Everything (AC-B8.3).

**S-45 — Change History (Audit Trail).** Mockup: `docs/mockups/audit-history.html`. Reached
from any Transaction Detail. Reverse-chronological, read-only (AC-F5.3) — no edit/delete
affordance exists anywhere on this screen. States shown: **populated** (multiple entry
types — user edit, system rule, deletion, restoration, each with a distinct actor icon),
**minimal** (a single "Created" entry).

---

## 8. User flows

Each flow lists the screen IDs traversed. "→" is a navigation; "▸" is an in-place sheet (no
screen-count cost, consistent with §6's treatment).

**Flow A — First run, SMS granted (US-A1-A3, F1, C3/OQ-18).**
S-01 → S-02 → (OS dialog S-03, granted) → S-05 (import, dismissible) → S-06 (review default
categories) → S-07 (app lock setup) → S-08 (Home, populated from imported history).

**Flow A′ — First run, SMS declined (AC-A1.2).**
S-01 → S-02 → (OS dialog S-03, declined) → S-04 (limited mode, offers manual entry + a
persistent "Grant access" entry point) → S-08 (Home in limited mode, banner persists).

**Flow B — Correcting a category (US-C2, D5) — the critical flow.** Fully detailed in §6.
S-10 or S-11 (context) ▸ S-12 (picker, tap 1) ▸ tap 2 selects category ▸ S-13 (scope strip,
auto-confirms or 1 optional override tap) → done, toast.

**Flow C — Handling the Needs Review inbox (US-A4, C4).**
S-08 (tap review count) → S-18 [Unparsed tab] → S-19 (fill fields) → transaction created,
item removed from queue. OR S-18 [Low-confidence tab] ▸ S-12/13 (same correction flow) →
flag clears, item removed.

**Flow D — Exploring the bank hierarchy (US-B2, B12, B13, B14).**
S-08/S-40 → S-21 (Banks) → S-22 (Bank Detail, Accounts/Cards segmented) → S-23 (Account
Detail) or S-24 (Card Detail, shows linked account) → S-25 (rename) as needed → back to S-22
with the new friendly name reflected everywhere (AC-B3.1).

**Flow E — Search and filter (US-E5).**
S-10 → search icon → S-26 (type query, live results) — or — S-10 → filter icon ▸ S-27 (set
facets, Apply) → S-10 re-renders filtered, "Clear filters" always visible when active.

**Flow F — Setting and tracking a budget (US-G1-G4).**
S-40 → S-33 (empty) → "+ Add budget" → S-34 (category, amount, alert on) → Save → S-33 shows
the new `BudgetProgressBar`. Later: a threshold crossing fires an OS notification (S-35)
which deep-links back into S-33.

**Flow G — Statement reconciliation (US-H1-H3).**
S-40 → S-36 (pick file, pick bank/account) → S-37 (progress) → S-38 (Matched/Added/Unmatched
tabs) → tap an Added row ▸ S-12/13 (same categorization flow, AC-H3.1) — or — tap an
Unmatched row → S-39 (resolve: add/mark-accounted/ignore).

**Flow H — Soft delete and restore (US-B8).**
S-11 → "Delete" → `ConfirmationDialog` (AC-B6.2) → transaction leaves S-10/S-11, a toast with
"Undo" appears immediately — if missed, S-40 → S-44 (Recently Deleted) → "Restore" → the
transaction reappears in S-10 with full prior history intact (AC-B8.2).

**Flow I — Export and erase (US-F2, F3).**
Export: S-40 → S-42 → mandatory warning acknowledgement → export runs → OS share sheet.
Erase: S-40 → S-43 step 1 (explanation) → step 2 (type-to-confirm) → step 3
(`ConfirmationDialog`) → app relaunches to S-01, or cancel at any step with zero effect.

**Flow J — App lock on every resume (US-F1).**
Any screen → app backgrounded → app resumed → S-09 (Lock Gate, opaque, no data rendered
underneath) → success → returns to exactly the screen the user left — or, if the OS-enforced
timeout has elapsed, S-09 shows the session-expired banner variant regardless of how long the
app was backgrounded (AC-F1.1 has no grace-period carve-out).

**Flow K — Bulk categorize (US-C5).**
S-18 [Low-confidence tab] or S-10 (filtered to Uncategorized) → long-press enters
multi-select → select several same-merchant rows → "Categorize selected" ▸ S-12 (same
picker, applying to N transactions at once) → toast "N transactions categorized as
{category}" with "Undo" (reverts all N, not just the last).

**Flow L — Manual transaction entry (US-B4, cash spending).**
S-08 or S-10 → FAB "+" → S-20 (empty form) → fill amount/date/merchant/category(▸S-12)/
source ("Cash" or an instrument) → Save → appears in S-10, visually tagged `Manual`
(AC-B4.3), included in all totals immediately (AC-B4.1).

**Flow M — Editing a transaction and inspecting its history (US-B5, F5).**
S-11 → "Edit" → S-20 (pre-filled) → change a field → Save → S-11 shows both auto-detected
and edited values inline (AC-B5.2) → "Change history" → S-45 (full append-only log, read-only).

**Flow N — Manual add account / add card (new in v2.1 — extends US-B15, see §10 D-13).**
S-21 (Banks List) or S-22 (Bank Detail) → tap "+" → choice of "Add account" or "Add card" →
S-48 (Add Account) or S-49 (Add Card) → pick bank → fill required fields (nickname; last-4 for
a card) → optional fields (starting balance for an account; settlement-account link for a
card) → Save → validation blocks with an inline, field-specific message if bank/nickname/last-4
are missing or malformed → on success, a confirmation summary appears with "Go to bank detail"
(returns to S-22, where the new instrument now appears in its Accounts/Cards segment,
AC-B13.3-consistent) or "Add another" (resets the form in place). A manually-added instrument
behaves identically to an auto-created one from then on: it can be renamed (S-25), and a later
SMS matching its bank + masked identifier attaches to it rather than creating a duplicate,
the same guarantee AC-B3.2 already gives auto-created instruments.

---

## 9. Accessibility notes (NFR-U1..U8)

- **Contrast:** every text/background pairing in §2.1 comes from `docs/brand.md`, which
  states each pairing's computed WCAG ratio (e.g. `color.warning.text` on white = 5.93:1;
  `color.ink.500` on white = 4.69:1, the floor). Engineers must not invent a new pairing
  without re-checking contrast against brand.md's own table.
- **Screen-reader labels (TalkBack):** every amount announces sign and value together, e.g.
  "Debit, forty-five riyals, Panda Foods, Dining category, today at two twenty PM" — the
  non-colour indicators from §3.3 double as the accessible-name source (icon
  `semanticLabel`/`contentDescription`, never left to an icon-only glyph). Masked identifiers
  announce as "card ending 4821," not read digit-by-digit. The Privacy Mode toggle, when
  masking, announces "amount hidden" rather than reading mask characters literally.
- **Focus order:** follows visual reading order per the active locale's direction (RTL focus
  order is right-to-left/top-to-bottom in Arabic — not simply the same widget order reused
  blindly). Bottom sheets trap focus while open and return focus to the originating chip on
  dismiss.
- **Touch targets:** 48×48dp minimum everywhere, including compact list-row action icons.
- **Text scaling (NFR-U3):** flexible/auto-sizing containers throughout (no fixed-height text
  containers), so Arabic merchant names and larger OS font sizes wrap rather than truncate.
  The one acceptable truncation is a list row's merchant name at *default* font size, and even
  then with an accessible full-text label and a tap-through to detail — never a truncated
  *amount*, ever, at any size.
- **Never colour-only (NFR-U4):** enforced structurally in §3.3; the accessibility audit
  (P9/KHA-51) should screenshot each state in greyscale and confirm the signal still reads.
- **Colour-blind check:** the debit/credit distinction is additionally carried by icon + sign
  specifically because red/green is the single most common confusion pair (deuteranopia/
  protanopia) — and debits are deliberately neutral ink, not red, per brand.md §2.3, so the
  ordinary case of spending is never colour-coded as an alarm.

---

## 10. Design-decision log — resolving build-plan flags D-1..D-12

| Flag | Resolution | Where |
|---|---|---|
| D-1 | Arabic RTL is the **primary, first-designed** layout (all 16 mockup screens default to `dir="rtl"`); full mirroring rules defined; Western digits chosen for all monetary/numeric UI regardless of locale, per `docs/brand.md` §3.1 (a brand decision, not re-litigated here). | §2.2, §3.1, `home-en.html` as the one explicit LTR mirror reference |
| D-2 | Default category list proposed: 10 spending + 3 money-movement categories, incl. Loan & Installments and Fees & Charges as their own categories per §3.4's hint. | §4 |
| D-3 | Category-correction flow designed to 2 taps / 0 screens, with the US-D5 scope choice offered as a smart-defaulted, auto-confirming in-sheet extension, never blocking. | §6, `category-correction.html` |
| D-4 | Non-colour indicator table for debit/credit/needs-review/internal-transfer/manual/auto/duplicate/locked, using brand.md's exact semantic tokens. | §3.3 |
| D-5 | Bank → account/card IA with account activity and card activity kept in visibly separate segmented tabs on Bank Detail (AC-B13.3). | §1, `banks.html` |
| D-6 | Masked identifiers are permanent (no full-PAN reveal exists to offer); unnamed instruments display their masked ID as the primary label until renamed. | §3.2, `banks.html` |
| D-7 | Needs Review Inbox splits Unparsed-SMS and Low-confidence into explicit tabs, with raw-text preview and a "not a transaction" permanent-dismiss action. | `needs-review.html` |
| D-8 | Unhappy states enumerated per screen in §7: permission never granted, revoked mid-life, import in progress, no data yet, filter returns nothing, insufficient history to compare. | §3.4, §7, every mockup's "states" section |
| D-9 | Dedicated priming screen before the OS permission dialog, with a clear "Not now" escape and a persistent later re-entry point. | `onboarding.html` |
| D-10 | Transparency screen drafted in plain language; explicitly flagged as needing a final wording pass once `docs/architecture.md` settles cloud-backup mechanics. | `privacy-data.html`, note below |
| D-11 | Flexible/auto-sizing text containers throughout; no fixed-height truncation of amounts at any font size; merchant-name truncation, where it occurs at default size, always has an accessible full-text label and a tap-through. | §9 |
| D-12 | Budget progress shows spend, limit, and % together with "Near limit"/"Over budget" as explicit text labels, not colour alone; alerts are local notifications, opt-in per budget. | `budgets.html`, §3.3 |
| D-13 (new, v2.1) | **Scope note, not a build-plan flag — added because the human explicitly requested it during mockup review, not because the PRD asked for it.** US-B15/AC-B15.1-2 only specify auto-creation of a bank/account/card the first time an SMS mentions it; there is no existing user story for a user-initiated manual add of an account or card. Two screens were designed anyway (S-48 Add Account, S-49 Add Card) because the human reviewer asked for this gap to be closed, reachable via a new "+" entry point on `banks.html`. **This is scope added during design, beyond the literal PRD text** — it does not contradict PRD constraints (still read-only w.r.t. money, still masked-identifier-only per NFR-S2, still resolves to the same bank/account/card hierarchy model) but has no `US-Bxx`/`AC-Bxx.x` ID of its own. **Recommendation: raise a formal PRD addendum (a small US-B16 "manually add an account/card" story with 2-3 ACs) before `/build`, if formal requirement traceability for QA test-case generation is required for these two screens.** If the team accepts the mockups as sufficient specification on their own, `/build` may proceed against `docs/design.md` §7 S-48/S-49 directly — flagging this explicitly rather than silently treating it as pre-approved scope. | `add-account.html`, `add-card.html`, §7, §8 Flow N |

**Note on D-10:** the Privacy & Data Transparency screen's copy about cloud backup is written
to the PRD's stated intent (NFR-P2: backup encrypted, processing stays on-device) but its
exact wording must be verified against whatever `docs/architecture.md` decides for the backend
posture and backup key model before engineers ship it verbatim.

---

## 11. Component ↔ engineering mapping notes

- Every component in §5 is specified without assuming a specific widget library:
  - **Flutter (primary target):** `CategoryPicker` → a `showModalBottomSheet` containing a
    `Wrap`/`GridView` of chip widgets; `BudgetProgressBar` → a custom widget over
    `LinearProgressIndicator` with an accessible label override; `MaskedIdentifier` and
    `TransactionListItem` are pure presentation widgets fed exact domain values — masking
    happens once in the domain/view-model layer (NFR-S2 enforced before display, never "trust
    the UI to remember to mask").
  - **React (not currently dispatched per the build plan §2, no web surface exists for this
    product; kept platform-neutral only in case that ever changes):** each component maps to
    a function component with the same prop names.
- Money values are passed to every component as the exact decimal type the architecture
  defines (NFR-A4) — never a pre-formatted string from a lossy `double`. Formatting (digit
  rendering, currency placement per §3.1) is a pure display-layer function applied at the
  last moment.
- The HTML mockups implement the bidi-isolation and RTL-mirroring rules directly in CSS
  (`direction:ltr; unicode-bidi:isolate` on a `.num` class; `transform:scaleX(-1)` on
  direction-sensitive icons; `inset-inline-start` for toggle/radio positions) specifically so
  engineers can inspect exactly how each rule should render, not just read a description of it.

---

## 12. Approval gate

This document, together with the 19 self-contained HTML files in `docs/mockups/` (18 screen
files — the original 16 plus the 2 new manual-add screens in v2.1 — + `index.html`), is the
complete UI/UX design for Massrofy v1. It does **not** self-approve.

- [ ] Human opens `docs/mockups/index.html` and clicks through every screen and state.
- [ ] Human reviews this document alongside the mockups.
- [ ] Human changes the status line at the very top of this file from
  `DRAFT - awaiting human approval` to `APPROVED`.

Only after **all of** `docs/architecture.md`, `docs/brand.md`, and this file are `APPROVED`
does `/build` proceed (per the build plan's Gate 2).

*End of design specification.*

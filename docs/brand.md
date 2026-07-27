STATUS: APPROVED
# Massrofy — Brand & Visual Identity

**Version:** 1.1
**Date:** 2026-07-27
**Author:** brand-designer agent (phase 2 — Gate 2, parallel with `docs/architecture.md` and `docs/design.md`)
**Source of truth:** `docs/PRD.md` (STATUS: Approved), `docs/build-plan.md`

**Changelog:**
- **v1.1 (2026-07-27):** Typography (§3) replaced end to end, along with every other place
  in this document that named the old typeface (the §4.4 wordmark spec, the app-icon
  placeholder, and the §7 engineering token table). **This supersedes the v1.0 choice of
  IBM Plex Sans / IBM Plex Sans Arabic specifically because the human reviewer rejected it
  during mockup review** — it read as generic/"engineered" rather than distinctive or
  premium for a banking product. New decided pairing: **Tajawal** (Arabic) + **Manrope**
  (Latin), both free/open-licence (SIL OFL 1.1) and self-hosted, no other section changed.
  §1, §2, §4.1–4.3, §5, and §6 are unchanged from v1.0 and remain correct as drafted.
- v1.0 (2026-07-27): Initial draft.

> This document defines the visual language before any screen is designed. `ui-ux-designer`
> builds `docs/design.md` and the HTML mockups in `docs/mockups/` directly from the tokens
> here. Engineers turn these values directly into Flutter `ThemeData` / design tokens — they
> are not placeholders to be reinterpreted. No external design tool (e.g. Penpot, Figma) is
> used for this product; visual design is expressed as self-contained HTML mockups per
> `docs/design.md`'s workflow, and this brand system is the token source for those mockups.

Context this system is built for: a **single-user**, **Android/Flutter**, **side-loaded**
personal spending tracker that reads bank SMS in **Saudi Arabia**, in **Arabic and English**
with full **right-to-left** support, and is **strictly read-only with respect to money**
(PRD CON-2 — it never initiates or moves funds). Every decision below is made against that
brief, not against banking-app conventions in general.

---

## 1. Brand personality

Five adjectives, and the feeling each one produces in the product:

| Adjective | What it means in the product |
|---|---|
| **Trustworthy** | The app handles a complete record of one person's financial life. Nothing about it should feel like a growth-hacked consumer app — no urgency banners, no manufactured excitement, no dark patterns. It behaves like something a careful person built for themselves. |
| **Calm** | Money anxiety is real; the UI must lower the temperature, not raise it. Even a red "over budget" state is delivered evenly, not with alarm colours or exclamation marks. |
| **Precise** | Every number is exact (PRD NFR-A4 — no floating-point money, no rounding, AC-B1.4). The visual system reflects that: aligned figures, tabular numerals, no decorative rounding of what should be exact. |
| **Private** | This is a personal, local-first tool (NFR-P1–P4). Visually this shows up as restraint — no imagery of the user's face, no cheerful stock photography of people spending money, nothing that treats a private financial record as a lifestyle showcase. |
| **Grounded** | A quiet nod to the Saudi market this is built for (a warm, restrained gold accent inspired by Sadu weaving tradition — see §2) without becoming decorative or "ethnic-themed." The product is modern and international first, locally grounded second. |

**The feeling on open:** *"My numbers, correctly, without me having to work for it."* Never
*"look what this app can do for you."*

---

## 2. Colour palette

One system, decided — not five options. Primary is a deep, stable navy (trust, stability,
reads seriously in both a light banking UI and as an app icon at small sizes). Secondary is
a single warm, restrained gold accent used sparingly (never as a large fill) as the one note
of warmth in an otherwise cool, precise system. All body-text pairings below are computed to
WCAG 2.1 contrast ratios (relative luminance method), not eyeballed.

### 2.1 Primary and secondary

| Token | Hex | Role |
|---|---|---|
| `primary` (Massrofy Navy) | `#0B3D62` | Brand colour. App bar, primary buttons, active nav state, links, focused states. |
| `primary-hover` / `primary-pressed` | `#0A3454` | Pressed/hover state of primary controls. |
| `primary-tint-10` | `#E7EEF4` | Light wash of primary for selected-row backgrounds, subtle highlight fills. Not for text. |
| `secondary` (Sadu Gold) | `#B8842E` | Accent only — active budget-progress fill, a single highlighted stat, the wordmark accent. Icons, borders, large text (≥18px/24px or bold ≥14.66px) only. **Do not use for small body text** (3.3:1 on white — fails AA for normal text). |
| `secondary-text` (Sadu Gold, text-safe) | `#8A5F1E` | Same hue, darkened for use as small text/links where the accent meaning is needed (5.6:1 on white — passes AA). |
| `secondary-tint-10` | `#F7EEDD` | Light wash of secondary for badge/chip backgrounds. |

### 2.2 Neutrals ("Ink" scale)

| Token | Hex | Role | Contrast on white |
|---|---|---|---|
| `ink-900` | `#101418` | Primary text, headings, monetary amounts | ~17:1 |
| `ink-700` | `#3A434C` | Secondary text, subtitles, labels | 10.1:1 |
| `ink-500` | `#6B7580` | Tertiary/meta text (timestamps, helper text) — **minimum acceptable for any text**, do not use anything lighter for text | 4.69:1 (passes AA at the floor — do not tint lighter and keep using it as text) |
| `ink-300` | `#C7CDD4` | Borders, dividers, disabled control outlines — **decorative only, never text** | fails AA — not for text |
| `ink-100` | `#EEF1F4` | Subtle fills: input backgrounds, unselected chip backgrounds, card dividers | — |
| `surface` | `#F7F8FA` | App/screen background | — |
| `white` | `#FFFFFF` | Cards, sheets, dialogs | — |

### 2.3 Semantic colours

Reserved for their meaning only — never reused as a category/chart colour (see §2.5), so
"green" always means credit/success and nothing else in this product.

| Token | Hex | Meaning | Text-on-white contrast | Usage |
|---|---|---|---|---|
| `success` | `#1E7A46` | Credit, refund, income, positive/on-track budget | 5.35:1 (AA pass) | Text/icon colour for credit amounts and "on track" budget state. Pair with a light tint background `#E5F3EA` for chips. |
| `error` | `#B3261E` | Over-budget, failed action, destructive confirmation, parse error | 6.54:1 (AA pass) | Text/icon colour only. Tint background `#FBEAE9` for chips/banners. |
| `warning` | `#8A5A00` (text) / `#F2A93B` (fill) | Approaching a budget threshold, needs-attention states that are not yet errors | Text `#8A5A00` on white = 5.93:1 (AA pass). The lighter `#F2A93B` is a **fill/icon colour only** (3.1:1 on white — large graphical objects/icons only, never small text) | Use the fill for a badge/icon background with `ink-900` or `#8A5A00` text on top, never `#F2A93B` text on white. |
| `info` | `#0B6E8C` | Auto-categorized-by-rule indicator, informational banners, "needs review" flag colour | 5.79:1 (AA pass) | Text/icon colour. Tint background `#E4F1F5` for chips. |

**NFR-U4 compliance (hard rule, not a suggestion):** colour is *never* the sole signal for:
- **Debit vs. credit** — every amount also carries an explicit sign (`−` for debit, `+` for
  credit) and a direction icon (outward-arrow glyph for debit, inward-arrow glyph for
  credit), plus a text label available to screen readers ("Debit"/"Credit" or
  "مدين"/"دائن"). Colour (ink-900 for debit, `success` green for credit) is a *supporting*
  cue layered on top of sign + icon + label, not the only one. Debits deliberately stay
  neutral `ink-900`, not red — in a spend tracker most rows are debits, and colouring the
  majority of the list red would be both false alarm and gimmicky, contradicting the "calm,
  not gimmicky" brief. `error` red is reserved for actual problems (over-budget, failed
  parse), not for the ordinary fact of spending.
- **"Needs review" status** — always a labelled badge/chip with an icon (e.g. an outline
  flag or "?" glyph) and the literal text "Needs review" / "بحاجة إلى مراجعة", using the
  `warning` tokens as a supporting fill, never a bare coloured dot or coloured row.

### 2.4 Dark mode

Out of scope for v1 unless `docs/architecture.md` / `docs/design.md` calls for it — Android
system dark mode is common enough that the token names above are structured (semantic
role → hex, not "the blue one") so a dark palette can be added later without renaming
anything. Not designing five variants now; deciding this one, light-first system.

### 2.5 Categorical / chart palette (separate from semantic colours)

For category breakdowns and month-over-month charts (Epic E). Deliberately **not** the same
hues as §2.3's semantic colours, so a "Dining" category slice is never visually confused
with a "success" or "error" state. Muted, professional tones — no neon, no primary-school
pie-chart colours. Every slice/bar still carries a text label and legend entry; colour is a
visual aid, never the only identifier (same NFR-U4 principle, applied consistently).

| Order | Token | Hex |
|---|---|---|
| 1 | `chart-navy` | `#0B3D62` |
| 2 | `chart-gold` | `#B8842E` |
| 3 | `chart-teal` | `#2E7D8C` |
| 4 | `chart-plum` | `#6B4C8A` |
| 5 | `chart-terracotta` | `#B25D3F` |
| 6 | `chart-slate` | `#55708A` |
| 7 | `chart-olive` | `#7A7A3E` |
| 8 | `chart-rose` | `#A34E63` |
| — | `chart-uncategorized` | `#6B7580` (always `ink-500`, fixed grey — never reassigned to a real category's colour, so "Uncategorized" always reads as *unassigned*, not as a themed category) |

---

## 3. Typography

> **v1.1 note:** this section replaces the v1.0 choice of IBM Plex Sans / IBM Plex Sans
> Arabic in full. That pairing was rejected by the human reviewer during mockup review —
> it read as generic and "engineered," not distinctive or premium enough for a banking
> product. Everything below is the new, decided system. See the changelog above.

### 3.1 Typefaces

Arabic and Latin must sit together cleanly in the same UI — sometimes in the same string
(e.g. an Arabic SMS with a Latin-transliterated merchant name, PRD §3.4). v1.0 solved this by
using one shared family for both scripts; that is still the right *goal* (weight, x-height,
and rhythm must agree across both scripts) but IBM Plex's shared family was rejected as too
neutral/utility-feeling. **Decision: a deliberately paired two-family system** — one Arabic
family that is genuinely Arabic-native (not a Latin font with Arabic bolted on), and one
distinctive Latin family chosen to match its proportions, weight axis, and low-contrast
geometric construction closely enough that mixed-script strings still read as one coherent
system, not two fonts collided together.

| Role | Typeface | Source | Why |
|---|---|---|---|
| Arabic (headings + body) | **Tajawal** | Google Fonts, SIL OFL 1.1 | Designed Arabic-first by Boutros™ (an Arabic type foundry), with the Latin cut added to match afterward — the reverse of IBM Plex's Latin-first approach, and the reason its Arabic reads more authentic and more crafted at the letterform level, not just "supported." Contemporary, low-contrast, geometric Arabic forms with a warm, confident, slightly rounded character — distinctive without tipping into decorative, which keeps "trustworthy, not gimmicky" intact. Ships 7 weights (ExtraLight 200 / Light 300 / Regular 400 / Medium 500 / Bold 700 / ExtraBold 800 / Black 900), well proven at small UI sizes in Gulf/MENA consumer and fintech apps. |
| Latin (headings + body) | **Manrope** | Google Fonts, SIL OFL 1.1 | A geometric, semi-condensed sans with distinctive rounded terminals and a more crafted, premium feel than a neutral grotesk — reads confidently at both display and small UI sizes. Shares Tajawal's low-contrast, geometric-sans construction and a closely overlapping weight axis (ExtraLight 200 / Light 300 / Regular 400 / Medium 500 / SemiBold 600 / Bold 700 / ExtraBold 800), so paired Arabic/Latin text sits at a matching visual weight and rhythm. Ships with an explicit **Tabular Figures** OpenType feature (`tnum`) built in — the one non-negotiable for a banking app's numeral columns. |
| Numerals / amounts (both languages) | **Manrope, tabular figures (`tnum`) enabled** | same family | Digits are always rendered as Western Arabic numerals regardless of surrounding script (see below), so amounts are always set in Manrope's tabular numeral glyphs — in an English string, an Arabic string, or a mixed one — guaranteeing every amount in a list aligns on the decimal point. If a rendering surface genuinely cannot honour the `tnum` OpenType feature, fall back to **JetBrains Mono** (Google Fonts, SIL OFL 1.1) for that amount column only — never to a proportional-figure style, and never to IBM Plex Mono. |

**Weight-mapping rule (read before building the type scale in §3.2):** Manrope has a
SemiBold (600) step; Tajawal does not (it jumps 500 Medium → 700 Bold). Wherever §3.2
specifies **SemiBold** for a Latin/UI-numeral string, render the **Arabic equivalent in
Tajawal Bold (700)** at the same size/line-height — Arabic strokes need the extra weight to
read at an equivalent visual density to Latin SemiBold at the same point size. This is a
one-time, documented substitution, not a per-screen judgement call.

**Licensing & offline embedding:** both Tajawal and Manrope are SIL Open Font License 1.1 —
free for commercial use, redistribution, and modification, with no attribution requirement
in-product. Do **not** wire the mockups or the app to a Google Fonts `<link>`/CDN URL:
download the static weight files (or the variable-font builds) once, commit them as local
assets, and load them via local `@font-face` (web mockups) / bundled `pubspec.yaml` font
assets (Flutter) so the product — and the offline HTML mockups in `docs/mockups/` — render
correctly with zero network dependency.

System-font fallback (only if the app must ship a single build without bundling the above,
e.g. a throwaway first spike): Android's default `Roboto` (Latin) has no first-class Arabic
cut, so **do not** fall back to system default for Arabic — bundle Tajawal as an asset
regardless; it is small, and correct Arabic typography is the one decision that must not be
compromised in an Arabic-first product.

**Numerals:** use **Western Arabic numerals (0–9)**, not Eastern Arabic-Indic digits (٠١٢٣),
for all monetary amounts and dates, in both the Arabic and English UI. This is the prevailing
convention in Saudi banking/fintech apps and keeps amounts visually consistent regardless of
which language the surrounding UI is in. (`ui-ux-designer`'s D-1 flag is resolved by this
decision; `docs/design.md` should carry it forward, not re-decide it.)

### 3.2 Type scale

All sizes in logical pixels (Flutter `sp`, 1:1 with `dp` at default text scale). Line-heights
are generous — Arabic ascenders/descenders and diacritics need more vertical room than Latin
alone typically gets.

| Style | Size / Line-height | Weight | Use |
|---|---|---|---|
| Display | 32 / 40 | SemiBold (600) | Onboarding / first-run hero moments only. Rare. |
| H1 (screen title) | 24 / 32 | SemiBold (600) | Screen/page titles ("This month", "Bank Aljazira"). |
| H2 (section header) | 20 / 28 | SemiBold (600) | Section headers within a screen (e.g. "Category breakdown"). |
| H3 (card/list header) | 17 / 24 | Medium (500) | Card titles, list-group headers. |
| Body Large | 17 / 24 | Regular (400) | Primary reading text — transaction detail, settings rows. |
| Body | 15 / 22 | Regular (400) | Default list-row text, form labels. |
| Body Small / Caption | 13 / 18 | Regular (400) | Timestamps, helper text, footnotes. Never used for anything the user must act on. |
| **Amount — Large** | 34 / 40 | SemiBold (600), Manrope tabular figures (`tnum`) | The one hero number on a screen (current-month total, a card's balance). |
| **Amount — Row** | 17 / 24 | Medium (500), Manrope tabular figures (`tnum`) | Amount in a transaction list row or summary line. |
| Label / Button | 15 / 20 | Medium (500), +0.1 letter-spacing | Buttons, tabs, chips. |
| Overline / Section label | 12 / 16 | SemiBold (600), uppercase (Latin only) | Small all-caps section tags in English UI. **Never uppercase Arabic** — Arabic has no letter case; the Arabic equivalent uses the same size/weight without transformation. |

Weight names above are the **Latin (Manrope)** steps. For every Arabic run of a "SemiBold"
style, use **Tajawal Bold (700)** at the same size/line-height — see the weight-mapping rule
in §3.1. All other weight names (Medium 500, Regular 400) map 1:1 between the two families.

### 3.3 Usage rules

- **Never truncate a merchant name or amount to save space** (NFR-U3, D-11). Wrap to a
  second line before truncating with an ellipsis; the transaction list row must be allowed
  to grow in height for a long Arabic merchant string.
- Respect the OS text-scale setting up to at least 200%; no fixed-height container may clip
  text at large accessibility sizes.
- **Bidi isolation:** when an amount or currency code (`SAR 1,204.50`) appears inside an
  Arabic (RTL) sentence, wrap it with Unicode directional isolates (e.g. `⁦…⁩`) so
  it doesn't reorder unpredictably next to Arabic punctuation. This is a build-phase detail
  worth stating here because it's a typography correctness issue, not a logic one.
- **RTL mirrors the whole layout**, not just text alignment: navigation chevrons, back
  arrows, progress bars, and the debit/credit direction icons (§2.3) must flip horizontally
  in RTL. Numerals and currency codes do **not** mirror (they stay left-to-right internally
  even inside a mirrored layout, per the bidi-isolation rule above).
- Colour and weight, never colour alone, distinguish emphasis — e.g. a "needs review" title
  is `ink-900` + Medium weight + the badge from §2.3, not merely tinted text.

---

## 4. Logo direction

A production logo needs a human designer or image-generation tool; this section defines the
**direction** precisely enough that a real logo can be commissioned or designed later without
drifting from the brand, and gives a **buildable placeholder** the team uses until then.

### 4.1 Concept

Massrofy takes scattered, noisy signals (bank SMS mixed with OTPs and marketing) and turns
them into one clear, always-current picture. The mark should express **convergence into
clarity** — not a wallet, not a coin, not a card, and not a generic "chart bars" cliché.

Working concept: a simple geometric form built from **two overlapping strokes that resolve
into a single clean line** — evoking scattered inputs (SMS/signals) converging into one
ledger line, and loosely suggesting the "M" of Massrofy without being a literal letterform.
A single small accent mark (a dot or short tick in Sadu Gold) sits at the point of
convergence, standing for "the one figure that matters, caught."

### 4.2 Style

- Flat, geometric, two-colour maximum (Massrofy Navy `#0B3D62` + Sadu Gold `#B8842E` accent,
  or Navy alone for single-colour contexts like an app-switcher icon).
- No gradients, no drop shadows, no bevels, no skeuomorphism.
- Must read clearly and stay legible as a 24×24dp app icon and a 512×512 store-style asset
  alike (even though this app is side-loaded, not store-published — the icon still needs to
  work at launcher size).
- Not directional/asymmetric in a way that would look "backwards" when the app itself is
  running in RTL — the mark is a symbol, not text, and does not mirror with the UI.

### 4.3 Do's and don'ts

**Do:**
- Keep it to one clean geometric idea, flat colour, generous whitespace.
- Keep the accent (gold) to a single small element — it is a note, not a fill.
- Make sure it still reads correctly rendered in pure Navy-on-white and white-on-Navy
  (for dark surfaces / splash screens).

**Don't:**
- No coin, banknote, wallet, or piggy-bank iconography — clichéd, and this is explicitly a
  **read-only observability** tool (CON-2); anything suggesting money movement or payment
  initiation (a card-swipe glyph, an arrow leaving a wallet, a "send" paper-plane) misstates
  what the product does and must be avoided in the mark itself, not just in copy.
- No lock/shield/vault clichés bolted onto the mark to "look secure" — security is earned by
  behaviour (NFR-S1–S8), not signalled by a padlock icon on the logo.
- No third colour, no gradient fill, no photographic or textured treatment.
- No stretching, skewing, rotating, or recolouring outside §2's palette.
- Never place the mark on a background that fails the contrast pairings in §2.

### 4.4 Wordmark placeholder (use until a real logo exists)

A plain, buildable text lockup — no image tool required, renders directly as a styled text
widget:

| Property | Value |
|---|---|
| English wordmark | `Massrofy` |
| Arabic wordmark | `مصروفي` |
| Typeface | Manrope SemiBold (Latin) / Tajawal Bold (Arabic — see the §3.1 weight-mapping rule) |
| Case | Sentence case (`Massrofy`, not `MASSROFY` or `massrofy`) |
| Colour — on light backgrounds | `primary` `#0B3D62` |
| Colour — on Navy/dark backgrounds (e.g. splash screen) | `#FFFFFF` |
| Letter-spacing | 0 (default) |
| Size | H1 (24/32) in-app headers; Display (32/40) on the splash/first-run screen only |
| Accent | Optional: a single Sadu Gold (`#B8842E`) dot or short tick placed after the wordmark, echoing §4.1's "convergence" concept — omit entirely if it reads as noisy at small sizes; the text alone is a fully acceptable placeholder |

**App icon placeholder:** a solid `primary` `#0B3D62` rounded-square (Android adaptive-icon
safe zone), centred single white glyph — the Latin "M" in Manrope SemiBold or the Arabic "م"
in Tajawal Bold (matching the §3.1 weight-mapping rule) — no gradient, no secondary shape.
This is deliberately simple enough to ship in P1 and swap out for a commissioned mark later
without touching layout code.

---

## 5. Iconography & imagery

### 5.1 Icon style

- **Line icons**, not filled/solid, at a consistent **24dp grid with ~1.75px stroke**,
  rounded caps and joins — calm and approachable rather than sharp or alarm-toned, matching
  the "calm" personality trait.
- **Library: Material Symbols (Outlined)**, since it ships with Flutter (no extra asset
  pipeline), has broad RTL-safe auto-mirroring support for directional glyphs, and is
  actively maintained. Use it as the base for all generic icons (back, chevron, search,
  filter, settings, calendar, export, delete, restore).
- **Custom icons** (same 24dp/1.75px-stroke style, hand-aligned to match Material Symbols'
  visual weight) are needed for banking-domain concepts the generic library doesn't cover:
  bank / account / card hierarchy glyphs, an "SMS-parsed" provenance badge, a
  "merchant-learned-rule" glyph, the debit/credit direction glyphs (§2.3), and the
  "needs review" flag glyph. These should be commissioned or drawn once `docs/design.md`
  finalizes which screens need them — this doc fixes the *style*, not the final glyph set.
- **Directional icons must mirror in RTL** (back arrows, chevrons, the debit/credit
  direction glyphs) — this is a build requirement, not optional polish, given NFR-U8.
- No emoji anywhere in the product UI — too informal for a financial record-keeping tool
  and inconsistent across Android renderers/fonts.

### 5.2 Photography / illustration direction

- **No stock photography, ever.** No photos of people, cards, cash, phones, or "lifestyle"
  spending scenes. This is a private financial tool, not a marketing surface, and the
  brief's privacy posture (NFR-P1–P4) extends naturally to not treating a personal ledger
  like a consumer lifestyle app.
- Where an illustration is warranted (empty states, onboarding, the SMS-permission priming
  screen), use **flat, minimal geometric illustration only**: abstract shapes — simple
  envelope/message motifs for the SMS-import step, simple bar/arc shapes for "no data yet"
  states — built from at most **two brand colours plus a neutral** (e.g. Navy + Gold + Ink),
  no gradients, no cartoon characters, no faces.
- Charts use the categorical palette in §2.5, always paired with a legend and value labels —
  never a bare, unlabelled colour-only chart.

---

## 6. Voice & tone

The product speaks the way a careful, competent person would talk about someone else's money
if asked to be exact and kind about it: **plain, calm, precise, never cute, never alarming.**

### 6.1 Principles

1. **State facts, not feelings.** "You're at 92% of your Dining budget" — not "Whoa, you're
   almost out of budget!" No exclamation marks in financial status copy, ever — not even for
   good news.
2. **Never round or approximate a number in copy that the UI shows exactly elsewhere**
   (AC-B1.4, NFR-A4). If the total is 1,204.50 SAR, copy says 1,204.50 SAR, not "about 1,200."
3. **Explain the system, don't hide it.** Auto-categorization copy names the mechanism:
   "Categorized automatically — matches your rule for [merchant]." (AC-D2.2). A black box
   erodes the exact trust this product depends on.
4. **Errors name the problem and the next step, never blame the user.** "This message
   couldn't be read as a transaction. Add the missing details, or mark it as not a
   transaction." — not "Invalid input" or "You made a mistake."
5. **Destructive actions are described in consequence terms, plainly, every time** — no
   variation in seriousness by mood. "Delete this transaction? It moves to Recently Deleted
   and can be restored." vs. the harder, one-time "Erase everything? This permanently
   deletes all transactions, cards, categories, and learned rules. This cannot be undone."
   The second is never softened with a joke or an emoji, because it is genuinely
   irreversible (US-F3).
6. **Empty states inform, they don't perform.** "No transactions yet. Once your bank sends a
   transaction SMS, it'll appear here automatically." — not "Nothing here... yet! 👀" (also:
   no emoji, per §5.1).
7. **Never imply the app can move, send, or advise on money** (NFR-C1, CON-2). Avoid action
   verbs like "pay," "send," or "transfer" as *button labels for things Massrofy itself does*
   — those verbs may only appear when quoting what a transaction record represents (e.g. a
   transaction *type* labelled "Transfer" is fine; a button that reads "Send" is not,
   because Massrofy sends nothing).
8. **Arabic is not a translation of the English copy — it is written natively, to the same
   standard.** Use clear Modern Standard Arabic with everyday, direct phrasing (the register
   used by mainstream Saudi banking/fintech apps) — not classical/literary Arabic, not
   Latin-script slang mixed in, and never a string that ships in English only while Arabic
   "catches up later." Both languages ship at equal quality, always.
9. **Bad news stays even in tone.** Over-budget, a failed import, a stale backup — reported
   factually, with the next available action, never with alarm styling or shaming language.

### 6.2 A few worked examples

| Situation | Do | Don't |
|---|---|---|
| Over overall budget | "You've spent 4,120 SAR of your 4,000 SAR budget this month (+120 SAR)." | "Uh oh! You're over budget! 😬" |
| Needs-review item | "Needs review — couldn't confidently match a category." | "We're not sure about this one lol" |
| SMS permission not yet granted | "Massrofy reads your bank SMS to build this view automatically. Grant SMS access to get started." | "Give us permission to keep going!" |
| Erase-all confirmation | "Erase everything? This permanently deletes all transactions, cards, categories, and learned rules. This cannot be undone." | "Time for a fresh start! Clear it all?" |
| Auto-categorized transaction | "Categorized automatically — matches your rule for Jarir Bookstore." | (no explanation shown at all) |
| Manual entry validation | "Enter an amount to save this transaction." | "Oops! Something's missing." |

---

## 7. Quick reference — token summary for engineering

| Token | Value |
|---|---|
| `color.primary` | `#0B3D62` |
| `color.primary.pressed` | `#0A3454` |
| `color.primary.tint10` | `#E7EEF4` |
| `color.secondary` | `#B8842E` |
| `color.secondary.text` | `#8A5F1E` |
| `color.secondary.tint10` | `#F7EEDD` |
| `color.ink.900` | `#101418` |
| `color.ink.700` | `#3A434C` |
| `color.ink.500` | `#6B7580` |
| `color.ink.300` | `#C7CDD4` |
| `color.ink.100` | `#EEF1F4` |
| `color.surface` | `#F7F8FA` |
| `color.white` | `#FFFFFF` |
| `color.success` | `#1E7A46` (tint `#E5F3EA`) |
| `color.error` | `#B3261E` (tint `#FBEAE9`) |
| `color.warning.text` | `#8A5A00` |
| `color.warning.fill` | `#F2A93B` |
| `color.info` | `#0B6E8C` (tint `#E4F1F5`) |
| `font.arabic` | Tajawal (Google Fonts, SIL OFL 1.1 — self-hosted, not CDN-linked) |
| `font.latin` | Manrope (Google Fonts, SIL OFL 1.1 — self-hosted, not CDN-linked) |
| `font.amount` | Manrope, tabular figures (`tnum`) — both languages, since amounts always render as Western Arabic numerals |
| `font.amount.fallback` | JetBrains Mono (Google Fonts, SIL OFL 1.1 — only if `tnum` can't be honoured) |
| `font.weight-mapping.arabic-semibold` | Tajawal **Bold (700)** stands in for Manrope SemiBold (600) — Tajawal has no 600 step; see §3.1 |
| `numerals` | Western Arabic (0–9) everywhere |

---

*End of brand system. This document must be marked `STATUS: APPROVED` by the human, alongside
`docs/architecture.md` and `docs/design.md`, before `/build` may start (per the project's Gate 2).*

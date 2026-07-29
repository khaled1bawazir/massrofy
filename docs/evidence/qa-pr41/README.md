# Runtime evidence — QA pass 9, PR #41 (P5a)

**Head under test:** `feature/p5a-shell-home-transactions` @ `d9fac9e`
**Device:** `massrofy_test` AVD, API 35, x86_64, swiftshader_indirect
**Build:** `flutter build apk --debug` (Flutter 3.44.8), installed with `adb install -r`
**Fresh-install state:** `adb shell pm clear com.massrofy.massrofy`, confirmed
`READ_SMS / RECEIVE_SMS / POST_NOTIFICATIONS: granted=false` before launch.

A device screen lock had to be set (`adb shell locksettings set-pin 1234`) —
`locksettings get-disabled` reported `true` on this AVD, so ADR-005's gate had no
credential to authenticate against and no journey was reachable at all. Stated
here rather than left implicit, since it is a deviation from a true fresh device.

---

## Journeys walked, in order

| # | File | What it shows |
|---|---|---|
| 1 | `02c-lock-gate.png` | S-01 lock gate on first launch. |
| 2 | `03-after-unlock.png` | **KHA-113's core fix.** S-02 *"Why Massrofy needs SMS access"* — the screen that had no construction site anywhere in `lib/` before this PR. |
| 3 | `04-os-permission-dialog.png` | *"Grant SMS access"* raises the real OS dialog, i.e. `SmsPermissionService.request()` genuinely has a caller now. |
| 4 | `05-after-grant.png`, `05b-15s-later.png` | After granting, the app returns to the lock gate showing **"Authentication failed. Try again."** and does not re-raise the prompt by itself. Recovery is one tap on *"Use device passcode instead"*. See **O-QA-41-5**. |
| 5 | `06-home-first-real-data.png` | Home renders. Three tabs (Home / Transactions / More), period selector, **AC-E1.3's explicit `0.00 SAR` plus "No transactions recorded yet this month"**, "All caught up", Spent vs kept, empty state with a manual-entry button. |
| 6 | `08-more-menu.png` | S-40 More menu — Banks, Add a transaction, Recently deleted, Needs review, Categories, Learned rules, Lock now. **All six screens KHA-113 listed as dead code are now reachable**, plus the honest *"Reports arrive in the next release"* line instead of a fourth dead tab. |
| 7 | `09-home-still-zero-before-resume-sweep.png` | Two rule-pack-matching SMS in the inbox, permission granted, app open — still `0.00 SAR`. **This is KHA-122**, filed as Epic A / ADR-018 and explicitly not a PR #41 blocker. |
| 8 | `10-home-after-forced-sweep.png` | After one background/foreground cycle: **`−972.40 SAR`**. Business oracle: the two seeded messages are `312.40` and `660.00`; `312.40 + 660.00 = 972.40`, exact. Dates parsed from Arabic bodies into Riyadh local time (`Wed, Jul 22 · 9:40 PM`). "2 items need review" (AC-C4.2). Needs-review flag icon + words (AC-C4.1), `−` sign prefix (AC-B7.3). |
| 9 | `11-transaction-detail.png` | **KHA-114's core fix.** S-11 now renders its action row — *Edit transaction* and *Delete* — which the issue reported as entirely absent. Also: `•••• 9002` masked (NFR-S2), collapsed *"Show original message"* (AC-B1.2), *"Why this category?"*, *"Not stated in message"* for an absent field (AC-B1.3). **And the Source row reads "SMS · Unknown bank" — KHA-123.** |
| 10 | `12-delete-confirm.png` | AC-B6.2's explicit confirmation, with *"Keep it"* worded positively and placed first, and the body naming Recently deleted (AC-B8.1). |
| 11 | `13-after-delete-banner-and-restore.png` | **KHA-114's second, undisclosed defect fix** — the `watchById` vs `watchLive` change. The row does **not** vanish on delete: the banner *"This transaction is deleted and is in no total"* and a *Restore* button are both on screen, which was unreachable before. Plus the *"Moved to Recently deleted"* snackbar. |
| 12 | `14-snackbar-dismissed.png` | Nine seconds later the snackbar is gone (KHA-115 — no bar persists). |
| 13 | `15-home-total-after-delete.png` | Second business oracle: the total drops to **`−312.40 SAR`** = `972.40 − 660.00`, exactly; the review count goes 2 → 1; the row leaves Recent transactions. **AC-E1.2 verified at runtime.** |
| 14 | `16-banks-screen.png` | **NFR-A6's chain on a real device**: Banks shows `Bank Aljazira · no accounts · 2 cards · −312.40 SAR`, equal to Home's period total. Also proves entity resolution named the bank correctly — which is why journey 9's "Unknown bank" is a display gap, not a resolution failure. |
| 15 | `17-nfr-s3-lock-collapses-stack.png` | **NFR-S3.** Backgrounded from the pushed Banks route, then relaunched: the `−312.40 SAR` figure is not on screen. (The frame is black because the biometric prompt carries `FLAG_SECURE`; `dumpsys window` confirmed `mCurrentFocus=Window{... BiometricPrompt}`. What matters is that the pushed route is absent.) |
| 16 | `18-after-relock-unlock-lands-on-home.png` | Unlocking after that re-lock lands on **Home**, the first route — not back on Banks. The stack was genuinely collapsed. |

## Not covered by this walk (stated, not implied)

- **POST_NOTIFICATIONS** was never granted; nothing in P5a's scope needs it.
- **Arabic RTL at runtime** — covered by widget tests in both locales, but the
  emulator ran in English. The Arabic *message bodies* were parsed correctly,
  which exercises the Arabic rule pack.
- **Biometric (fingerprint) authentication** — no fingerprint is enrolled on this
  AVD, so every unlock went through the device-credential path.
- **A large historical import / S-05 progress screen** — the inbox held five
  messages, so the import completed too fast for the progress screen to be
  observable. AC-A3.2 remains test-verified only.

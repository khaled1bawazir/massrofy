---
description: Check this machine for everything QA needs to actually run and verify the app. Run once per machine, and after tool updates.
---

Check the local environment for the runtime-verification toolchain. For each
item: detect it, report version or MISSING, and give the exact install
command/link. Do not install anything without asking.

1. **Core**
   - Node.js (>=20) and npm
   - Java JDK (>=17) and Maven or Gradle
   - Git
   - Docker Desktop (optional but recommended for one-command backend boot)
2. **Web runtime testing**
   - In the web project: `@playwright/test` installed and browsers downloaded
     (`npx playwright --version`; browsers via `npx playwright install`)
3. **Mobile runtime testing**
   - Flutter SDK on PATH (`flutter doctor` — run it and interpret the output)
   - Android SDK / Android Studio
   - At least one AVD created (`emulator -list-avds`)
   - Note honestly: iOS testing needs a Mac; on Windows it's build-only.
4. **Verdict**
   - Print a table: tool | status | fix.
   - State clearly which verification tiers are available RIGHT NOW:
     backend boot ✓/✗, web journeys (Playwright) ✓/✗, Flutter build+test ✓/✗,
     emulator integration tests ✓/✗.
   - If something is missing, say exactly what QA will silently skip until it's
     installed — no surprises later.

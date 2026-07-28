# Massrofy CI/CD — pipeline reference and required manual setup

This file is owned by devops-engineer. It documents what `.github/workflows/`
does, what must be configured by hand in the GitHub UI (things no API token
available to the agent team could set up), and how the P10 "deploy to staging"
step works end to end. Read this before touching `.github/`.

## 1. Why this exists

`docs/CLAUDE.md` describes the safety argument for autonomous merges:

> The code-reviewer can merge, but GitHub branch protection (set by devops)
> requires `ci` checks to pass first. Green CI + a strict opus reviewer are
> the gate.

That argument is only true if branch protection is actually turned on. **As of
this setup, it is not** — the agent team's GitHub App/token available in this
environment could not authenticate against the GitHub API (`mcp__github`
returned "Incompatible auth server: does not support dynamic client
registration"), and there is no `gh` CLI installed on this machine. Nothing in
`.github/` can enforce branch protection by itself; it is a repo *setting*,
not a workflow file. **A human must do the two steps in §2 by hand,** ideally
right after the GitHub repo is created and before the first feature PR lands.

## 2. Manual steps required (do these first)

### 2.1 Create the GitHub repository

No GitHub remote exists yet. From this machine:

```bash
# from the Massrofy project root, after reviewing what's about to be pushed
git remote add origin https://github.com/<your-org-or-user>/massrofy.git
git push -u origin main
```

Or, once you've run `/mcp` in Claude Code and authenticated GitHub (see
`README.md` "One-time tool setup"), a subsequent devops-engineer run can create
the repo and push via the `mcp__github` tools instead.

Recommended repo settings: **private** (this is a banking-domain app that will
eventually reference real bank names/SMS formats in fixtures and issues).

### 2.2 Configure branch protection on `main`

GitHub UI: **Settings -> Branches -> Add branch protection rule**, branch name
pattern `main`. Turn on:

- **Require a pull request before merging**
  - **Require approvals: 1** (this is the code-reviewer agent's review)
- **Require status checks to pass before merging**
  - Search for and require the check named **`ci`** (this is the fan-in job
    in `.github/workflows/ci.yml` — it only goes green once
    `flutter-build-test`, `dependency-scan`, `money-type-guard`, and
    `no-network-permission-guard` have all passed or legitimately skipped).
    You will not see `ci` in the search box until the workflow has run at
    least once on a branch/PR — push once, then come back and add it.
  - **Require branches to be up to date before merging** — on. Prevents
    merging a PR whose CI ran against a stale base.
- **Require conversation resolution before merging** — on.
- **Do not allow bypassing the above settings** — on, including for
  administrators. (A single-owner repo with an autonomous merge bot is exactly
  the case where "the admin can just skip the check" quietly defeats the whole
  safety argument.)
- **Restrict who can push to matching branches** — on, nobody except via PR
  (blocks direct pushes to `main`, including by the human, to keep history and
  CI status meaningful).
- Force-push and branch deletion: leave **disallowed** (default).

Also, separately: **Settings -> General -> Pull Requests**, turn on **"Allow
auto-merge"** — this is what lets the code-reviewer agent's `gh pr merge
--auto` (or MCP equivalent) actually take effect the moment the `ci` check and
the required review are both green, without the reviewer having to poll.

### 2.3 Configure the `production` deploy environment

GitHub UI: **Settings -> Environments -> New environment**, name `production`.
Turn on **Required reviewers** and add yourself (the human). Leave
`deployment branches` restricted to `main`. This is the gate
`deploy.yml`'s `promote-to-production` job runs under — it will pause and wait
for your approval in the Actions UI no matter how it was triggered.

Also create a `staging` environment (**Settings -> Environments -> New
environment**, name `staging`) with **no** required reviewers — this keeps
staging deploys automatic, matching "start with staging" in the devops-agent's
brief. You can add environment-scoped secrets to either environment instead of
repo-wide secrets if you want staging and production to use different signing
material later.

## 3. Signed staging APK — the secret contract

`deploy.yml` looks for four repository (or `staging`-environment) secrets:

| Secret name | Contents |
|---|---|
| `MASSROFY_STAGING_KEYSTORE_BASE64` | `base64 <your-keystore>.jks` output — the whole keystore file, base64-encoded, as one string |
| `MASSROFY_STAGING_KEYSTORE_PASSWORD` | the keystore password |
| `MASSROFY_STAGING_KEY_ALIAS` | the key alias inside the keystore |
| `MASSROFY_STAGING_KEY_PASSWORD` | the key's own password (often the same as the keystore password) |

Generate a keystore once, locally, and **never commit it**:

```bash
keytool -genkey -v -keystore massrofy-staging-upload-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias massrofy-staging
base64 -w0 massrofy-staging-upload-key.jks   # paste this into the GitHub secret
```

Add the four secrets under **Settings -> Secrets and variables -> Actions**
(or under the `staging` environment specifically). Keep the `.jks` file itself
somewhere safe outside the repo (a password manager attachment, not a laptop
Downloads folder) — losing it means every future staging build changes signing
identity, which breaks Android's "same signer to upgrade-install" rule on the
test device.

**If these secrets are not yet configured, `deploy.yml` still runs and still
produces an installable APK.** Gradle/Flutter fall back to debug signing for
the release build type when no `android/key.properties` is present, with a
build-time warning. The published artifact is named with a `debug-signed-fallback`
suffix instead of `signed` so nobody mistakes it for the real thing. This means
P10 ("a signed APK is installed on the user's real device") is never *blocked*
on secret provisioning, but the human should configure real signing before
relying on the staging channel long-term (Android will refuse to upgrade-install
over a differently-signed APK, so switching signing identity later means
uninstall-then-reinstall once on the test device).

**mobile-engineer's part of this contract:** `android/app/build.gradle` (part
of the P1 Android scaffold) must read `android/key.properties` if present and
configure the `release` build type's `signingConfig` from it, falling back to
the default `debug` signing config if the file is absent — this is standard
Flutter boilerplate (see the "Signing the app" section of Flutter's own Android
deployment docs) and is not devops's file to own, but the key.properties
shape above is the contract devops is producing for it to read.

## 4. What "deploy to staging" (P10) actually does, end to end

1. A PR merges to `main` (code-reviewer, on green `ci`).
2. `deploy.yml` triggers on the push to `main`.
3. It builds `flutter build apk --release`, re-checks ADR-001 against the
   *actual artifact* (not just the PR that produced it — defense in depth),
   names the APK `massrofy-staging-<date>-<sha>-<signed|debug-signed-fallback>.apk`,
   computes a sha256, and:
   - uploads it as a workflow artifact (90-day retention), and
   - publishes/updates a GitHub Release tagged `staging` with the APK and
     checksum attached, so there is one stable URL to fetch "the current
     staging build" from a phone's browser.
4. The human downloads that APK to the test Android device (Chrome ->
   Downloads, or `adb install`) and side-loads it — same as any side-loaded
   app, `Settings -> Install unknown apps` for the source used.
5. This satisfies the P10 exit check's mechanics ("a signed APK is installed
   on the user's real device"); the exit check's actual pass/fail
   (**"the human confirms the current-month total matches reality"**) is a
   human judgement call, not something CI can automate, and is expected to
   happen after every staging deploy during active development.
6. Only if the human explicitly runs the `deploy` workflow via
   **Actions -> deploy -> Run workflow** with "promote to production" checked,
   does `promote-to-production` run — and it then pauses for approval under
   the protected `production` environment (§2.3) before publishing a
   `production-<version>` release tag. Nothing ever reaches that tag without
   an explicit human click, even though staging is fully automatic.

## 5. What CI (`ci.yml`) enforces and why

| Job | Enforces | Notes |
|---|---|---|
| `flutter-build-test` | build compiles, lints clean, tests pass, debug APK builds | `dart format --set-exit-if-changed` + `flutter analyze --fatal-infos` are the lint gate |
| `dependency-scan` | no known-vulnerable dependency versions | OSV-Scanner against `pubspec.lock` |
| `money-type-guard` | ADR-002 — `double`/`num`/`.toDouble()`/`double.parse` banned under `lib/core/money/`, `lib/domain/`, and any `*money*`/`*amount*`/`*budget*`/`*report*` file; `SUM(`/`TOTAL(`/`AVG(` banned in `.drift` files | grep-based, per ADR-002's own stated enforcement mechanism — see `.github/scripts/check_money_type_ban.sh`. Mobile-engineer may *additionally* add a `custom_lint` rule for IDE-time feedback; it does not replace this CI check |
| `no-network-permission-guard` | ADR-001 — the **release** manifest never carries `INTERNET` / `ACCESS_NETWORK_STATE` | Checks the source manifest for the two `tools:node="remove"` directives, then builds a release APK and inspects the real merged manifest — see `.github/scripts/check_no_network_permission.sh`. Debug/profile manifests are expected to keep `INTERNET` (hot reload) and are never checked |
| `android-sqlcipher-integration-test` | ADR-003 — SQLCipher encryption, on a real Android emulator | See KHA-62 and KHA-67 (2026-07-28): known intermittent QEMU boot-hang flakiness on GitHub's shared runners. On a `pull_request` this job only runs when the PR touches `android/`, `lib/`, `integration_test/`, `pubspec.*`, or `ci.yml` itself (merges to `main` always run it). It retries the emulator once, after an explicit teardown and against a freshly created AVD. A healthy run finishes in ~15-20 min. See §5.1 for why its timeouts are shaped the way they are |
| `ci` | fan-in of the above | this is the one status check to require in branch protection (§2.2) |

### 5.1 How to read `timeout-minutes` in `ci.yml` (KHA-67)

`timeout-minutes` is **when GitHub starts cancelling**, not when the job or
step stops. If the runner cannot stop the running step — a wedged QEMU
emulator is the case that bites here — GitHub force-terminates **5 minutes
after cancellation begins**.

That is the whole of the KHA-67 discrepancy: the emulator job on PR #11 (run
`30379373737`, job `90343139912`) declared `timeout-minutes: 55`, its check
annotation reads *"The job has exceeded the maximum execution time of 55m0s"*
at 17:35:49Z, and it was force-killed at 17:40:49Z — **exactly 60m00s**. The
55 was honoured; the extra 5 was the grace period.

Two consequences that anyone editing this file needs to hold onto:

1. **A declared budget is not a wall clock.** The emulator job declares 62 and
   its worst-case observed wall clock is 67. Both numbers are written out at
   the declaration site. Do the same for any new budget.
2. **Prefer a deadline the step enforces on itself.** Step-level
   `timeout-minutes` has the same cancel-then-force-kill semantics, so it is a
   poor primary bound: on job `90343139912` a step declaring 15 minutes ran
   20m49s, and the next one was 22m48s past its own deadline when the job
   timeout took over — which is how a nominal "3 x 15 = 45 min" ceiling
   reached 55. The emulator step now bounds itself with the action's
   `emulator-boot-timeout` and a `timeout --kill-after=60s 960s` wrapper
   around `script`, and keeps `timeout-minutes` only as a backstop. A
   self-enforced deadline also **fails with a readable log**; a force-killed
   job does not — GitHub never finalised job `90343139912`'s log blob, so the
   one run everybody needed to read is the one run nobody can.

There is also a sizing lesson worth keeping: the 15-minute step budget was
killing **healthy** attempts. Job `90326515099`'s attempt 1 printed its
ADR-003 assertion as passed at 15:55:58Z and was cut one second later at
15:55:59Z, because a cold `assembleDebug` inside that step measured **728.6 s
(12.1 min)** on a 2-vCPU runner and grows with the codebase. If the emulator
job starts timing out again as the app grows, the honest fixes are a Gradle
build cache on that job or a larger runner — not another slack increase.

**What no timeout in this file can catch.** Twice now — jobs `90326515099`
and `90365056113` — the emulator job has ended with this pair of log lines
about half a minute apart:

```
ERROR | detected a hanging thread 'QEMU2 main loop'. No response for 16311 ms
##[error]The runner has received a shutdown signal.
```

The KHA-62 QEMU hang appears to take the **runner VM itself** down with it.
When that happens the job ends on the spot, `Post` steps are skipped, and no
`timeout-minutes`, `timeout` wrapper or in-job retry gets a chance to act —
there is no longer a runner to act on. It fails **fast (~11 min) and red**,
which is the behaviour we want, so the practical response is simply to re-run
the job. **Do not read a quick red on this job as a broken budget** — check
for those two lines first. Surviving it properly would need a retry at the
*job* level, which GitHub has no native primitive for.

All four jobs are written to no-op cleanly (not fail) on this repo *right
now*, before `pubspec.yaml`/`lib/`/`android/` exist. Each one starts doing real
enforcement automatically the moment mobile-engineer's P1 scaffold adds those
files — no further devops action needed, but re-read this file once that
lands to confirm the `ci` required-check search in §2.2 still resolves (it
should; the job name doesn't change).

## 6. Secrets hygiene

- No secret is ever printed to a log. Every secret is passed through `env:`
  and only used to decode/write local files inside the ephemeral runner
  (`android/app/*.jks`, `android/key.properties`), both of which are
  `.gitignore`d so a future contributor cannot accidentally commit them even
  from a local clone.
- `.env` (repo root) stays gitignored per the existing `.gitignore` — it is
  for local MCP/tool credentials (Linear, GitHub OAuth caches), not app
  secrets, and none of it is read by any workflow here.
- If a signing secret is ever rotated, update it in **Settings -> Secrets and
  variables -> Actions** (or the `staging` environment) — nothing else needs
  to change.

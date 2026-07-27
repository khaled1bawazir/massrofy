# Product Team — Autonomous Agent Workflow

A self-operating software team of Claude Code subagents, banking domain. You give
an idea and approve two things — the PRD and the UI design. After each approval the
team runs on its own; after the design gate it builds, reviews, merges, ships to
staging, and fixes bugs autonomously.

## The TWO human gates
1. **PRD approval.** `/kickoff <idea>` -> **product-owner** writes `docs/PRD.md`
   (status `DRAFT`) + Linear stories. You set the status to `APPROVED`.
2. **Architecture + brand + design approval.** `/design` -> **manager** plans,
   **solution-architect** writes `docs/architecture.md` (ADR), **brand-designer**
   writes `docs/brand.md`, and **ui-ux-designer** writes `docs/design.md` and
   generates viewable HTML mockups in `docs/mockups/`. All `DRAFT`; then STOPS.
   You open `docs/mockups/index.html` to review the screens, and set
   `docs/architecture.md`, `docs/brand.md`, and `docs/design.md` to `APPROVED`.
   (Backend-only features get `N/A - no UI`.)
3. `/build` -> everything from implementation to staging, autonomously.

Both the designer and product-owner refuse to self-approve, and `/build` refuses to
start unless `docs/PRD.md`, `docs/architecture.md`, `docs/brand.md`, and
`docs/design.md` are all approved. So no code is written against an unapproved
architecture, brand, or design.

## Design is generated as viewable HTML (no external design tool)
The designer writes each screen as a self-contained file in `docs/mockups/`. Open
`docs/mockups/index.html` in any browser to click through the screens. Engineers
build from these mockups + `docs/design.md` + `docs/brand.md`.

## Agents hand off through FILES + Linear + GitHub (not memory)
Each subagent has isolated context and returns only a summary. Shared state lives in
`docs/`, Linear issues, and GitHub PRs.

## The team
| Agent | Model | Tools | Role |
|-------|-------|-------|------|
| product-owner | opus | Linear | idea -> PRD + stories (gate 1) |
| manager | opus | Linear | plan, order, assign issues |
| solution-architect | opus | GitHub | system design, `docs/architecture.md` (gate 2) |
| brand-designer | sonnet | (writes files) | palette, type, logo direction, `docs/brand.md` (gate 2) |
| ui-ux-designer | sonnet | (writes files) | `docs/design.md` + viewable HTML mockups (gate 2) |
| devops-engineer | sonnet | GitHub | CI/CD pipeline + branch protection |
| backend-engineer | sonnet | GitHub, Linear | Java/Spring API + tests |
| frontend-engineer | sonnet | GitHub, Linear | React web |
| mobile-engineer | sonnet | GitHub, Linear | Flutter |
| qa-tester | sonnet | GitHub, Linear | test plan, automation, defects |
| code-reviewer | opus | GitHub, Linear | reviews + MERGES PRs on green CI |
| production-support | haiku | local | log triage, raises bugs |

## Commands / flow
- `/kickoff <idea>` -> PRD draft. **You approve the PRD.**
- `/design`         -> plan + architecture + brand + UI mockups. **You approve architecture + brand + design.**
- `/build`          -> devops CI -> engineers (parallel) -> qa -> reviewer merges on
   green CI -> deploy to staging. Autonomous.
- `/fix-bugs`       -> maintenance loop: reproduce -> fix + regression test -> qa ->
   reviewer merges. Autonomous.

### Why auto-merge is safe
The code-reviewer can merge, but GitHub **branch protection** (set by devops)
requires `ci` checks to pass first. Green CI + a strict opus reviewer are the gate.
Production deploys stay a protected, human-approved environment.

## Phase 2: maintenance loop (`/fix-bugs`)
When a bug is raised (QA, production-support, or you) as a Linear issue labelled
`bug`: reproduce -> route to the right engineer -> fix on a branch with a regression
test -> qa verifies -> reviewer merges on green.

## How the team "wakes up" (the heartbeat)
Agents don't run 24/7 by themselves — a session must start them. See `automation/`:
event-triggered GitHub Action on the `bug` label, a cron sweep, or manual runs.
Headless runs use `claude -p ... --dangerously-skip-permissions` on a controlled
machine only.

## Permissions
`.claude/settings.json` lets the team act without prompting (edits, builds, tests,
branches, PRs, merges, Linear, GitHub). Still guarded: `rm -rf`, force-push, repo
deletion. Tighten to your bank's risk tolerance before real use.

## Honest limits
- No human reads code before merge — the safety net is CI + a strict opus reviewer.
  Consider keeping a human approver on production deploys (already protected) and on
  money/auth-touching PRs.
- Autonomous fix loops can occasionally thrash; the green-CI + regression-test rule
  is what stops a bad fix from shipping.

# claude-agent-team

A self-operating Claude Code subagent team that builds banking-domain products end
to end: Product Owner, Manager, UI/UX Designer, DevOps, Backend (Java/Spring),
Frontend (React), Mobile (Flutter), QA, Code Reviewer, and Production Support.

You approve the PRD; the team plans, designs, builds, reviews, merges, ships to
staging, and fixes bugs autonomously.

## Install
Copy `.claude/`, `.mcp.json`, `CLAUDE.md`, `.env.example`, `.gitignore`, and
`automation/` into your project root, then open Claude Code there.

## One-time tool setup
2. GitHub + Linear: run `/mcp` in Claude Code and approve the browser OAuth.
3. Verify with `/mcp` that github and linear show connected.

## Daily use (two approval gates)
- `/kickoff <idea>`   -> product-owner writes docs/PRD.md, then STOPS.
- Approve gate 1: set docs/PRD.md status to `APPROVED`.
- `/design`           -> manager plans, architect writes the ADR, brand-designer sets
  the brand, designer generates HTML mockups, then STOPS.
- Approve gate 2: open docs/mockups/index.html to review screens; set
  docs/architecture.md, docs/brand.md, and docs/design.md to `APPROVED`.
- `/build`            -> team builds it to staging, autonomously.
- `/fix-bugs`         -> maintenance loop: fixes open `bug` issues autonomously.

## Autonomy
`.claude/settings.json` lets the team run hands-off (including merging PRs on green
CI). See `automation/` to give it an automatic heartbeat (GitHub Action or cron).
Read the "Honest limits" section of CLAUDE.md before using on production banking code.

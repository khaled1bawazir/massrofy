# Heartbeat — how the team "wakes up"

Claude Code agents run inside a session that something has to start. These are the
ways to give the team an automatic heartbeat so it acts without you sitting there:

- **A) Event-triggered (recommended for bugs):** `claude-fix-bugs.yml.example` runs
  the `/fix-bugs` loop whenever an issue is labelled `bug`. Nearest thing to "a bug
  is raised and the team starts fixing it."
- **B) Scheduled:** `cron-heartbeat.sh.example` sweeps for open bugs on a timer.
- **C) Manual:** just run `/build` or `/fix-bugs` yourself in Claude Code.

All three use headless mode (`claude -p`). `--dangerously-skip-permissions` is what
makes it fully unattended — only use it in CI/cron on a controlled machine, never
carelessly. Requires an `ANTHROPIC_API_KEY` secret.

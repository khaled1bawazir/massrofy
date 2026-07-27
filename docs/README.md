# docs/ — the team's shared source of truth

Agents don't share memory. They hand work off by reading and writing files here.

Expected files as a project progresses:
- `PRD.md`          product-owner        (gate 1: approve before design)
- `architecture.md` solution-architect   (gate 2: approve before build)
- `build-plan.md`  manager
- `brand.md`        brand-designer       (gate 2: approve before build)
- `design.md`       ui-ux-designer       (gate 2: approve before build)
- `mockups/`        ui-ux-designer       (viewable HTML screens — open index.html)
- `api.md`         backend-engineer (the contract web + mobile build against)
- `test-plan.md`   qa-tester        (acceptance-criteria traceability matrix)
- `defects.md`     qa-tester
- `incidents/`     production-support

Keep this folder in version control — it's the paper trail for the whole build.

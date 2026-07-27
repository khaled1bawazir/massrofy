---
description: Phase between PRD and build — plan, architecture, brand, and UI mockups. Then STOP for your approval of architecture, brand, and design.
---

Precondition: `docs/PRD.md` must exist and read `APPROVED`. If not, STOP and tell
the human to approve the PRD first.

Run these, then stop:
1. **manager** -> write `docs/build-plan.md`, create/organize Linear issues, and
   state whether this feature involves UI work.
2. **solution-architect** -> write `docs/architecture.md` (ADR), status `DRAFT`.
3. If UI is in scope:
   - **brand-designer** -> write `docs/brand.md` (palette, type, logo direction +
     wordmark placeholder, voice), status `DRAFT`.
   - **ui-ux-designer** -> write `docs/design.md` (status `DRAFT`) and generate
     `docs/mockups/*.html` (viewable screens) plus `docs/mockups/index.html`.
   If there is NO UI work: write `docs/design.md` with `STATUS: N/A - no UI in
   this feature` and skip brand + mockups.

Then STOP. Do NOT dispatch devops or any engineer.
- Summarize the key architecture, brand, and design decisions.
- Tell the human to open `docs/mockups/index.html` in a browser to review screens.
- Remind them to approve ALL of: `docs/architecture.md`, `docs/brand.md`, and
  `docs/design.md` (set each to `APPROVED`) before running `/build`.

This is the second human gate — architecture, brand, and UI reviewed together.
Nothing is built until they are approved.

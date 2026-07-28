---
description: Apply client/stakeholder feedback to the approved design without a full re-kickoff.
---

The client/stakeholder gave this feedback on the design:

$ARGUMENTS

1. **ui-ux-designer** -> apply the feedback to the affected mockups in
   `docs/mockups/` and update `docs/design.md` accordingly. Mark the changed
   sections and set the design status back to `DRAFT - awaiting human approval`.
2. If the feedback changes brand-level decisions (colours, type, tone), first
   route to **brand-designer** to amend `docs/brand.md` (also back to `DRAFT`).
3. **design-critic** -> quick pass on ONLY the changed screens.
4. STOP. Tell the human what changed, and remind them to re-approve the changed
   files (set to `APPROVED`) — and to redeploy the client preview if needed.

If code was already built against the old design, note explicitly which
components will need a follow-up task, and tell the human to run /build (the
manager will pick up the divergence).

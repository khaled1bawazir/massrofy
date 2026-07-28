# Studio design system (human-owned, Penpot)

This is your STUDIO-level design system — the reusable brand + component library
that lives ABOVE any single client project. A human curates it in Penpot; it
changes rarely. The agents do not edit it and do not depend on Penpot to run.

## How it connects to the agent pipeline
1. You maintain the design system in Penpot (brand, colour/type tokens,
   components, logo).
2. When it changes, you export the current tokens into `tokens.md` in this folder
   (colours as HEX, type scale, spacing, component notes).
3. The **brand-designer** agent reads `tokens.md`. If it exists, the agent builds
   each product's brand ON TOP of the studio system instead of inventing one.
   If it's absent, the agent creates a fresh system — which you can then port
   back into Penpot to grow the studio library.

This keeps Penpot as your professional, client-facing, reusable design asset,
while the per-project screen design stays fully automated as HTML mockups.

## tokens.md — expected shape
A simple, agent-readable snapshot of the Penpot system. Example:

```
# Studio design tokens (exported from Penpot)
Colours:
- brand/primary   #0B5FFF
- brand/ink       #101828
- semantic/success #12805C
Type:
- font: Inter
- scale: 12 / 14 / 16 / 20 / 24 / 32
Spacing: 4 / 8 / 12 / 16 / 24 / 32
Components: Button (primary/secondary/ghost), Input, Card, ...
```

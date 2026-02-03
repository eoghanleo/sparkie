---
name: product-strategy
description: Produce <product-strategy> artifacts (ROADMAP-*) by selecting bets/pitches, constraints, and sequencing from research + marketing inputs.
metadata:
  short-description: Roadmaps + strategic bets
---

## Domain

Primary domain: `<product-strategy>`

## Status

Active (bus + emit receipts). Product-strategy is now in development.

## What you produce

- Product roadmaps: `phosphene/domains/product-strategy/output/product-roadmaps/ROADMAP-*.md`

## How to work

- Start from `<research>` pitch set + competitive constraints + unknowns.
- Incorporate `<product-marketing>` constraints (ICP, messaging constraints, objections).
- Create artifacts directly under `phosphene/domains/product-strategy/output/product-roadmaps/` (templates are intentionally not used).
- Keep bets explicit, with assumptions, risks, and “we lose when…” constraints.
- Manual edits are allowed for these single-file artifacts; keep headings stable.

## In-doc script hints (`[V-SCRIPT]`)

Some templates/artifacts include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` when scanning an artifact to discover relevant control scripts for that section.

## Scripts (entrypoints and purpose)

- `create_product_roadmap.sh`: Create a new ROADMAP doc (allocates ROADMAP-###).
- `validate_product_roadmap.sh`: Validate ROADMAP headers/sections and ID conventions.
- `product-strategy_emit_done_receipt.sh`: Emit DONE receipt to the signal bus.
- `product-strategy-domain-done-score.sh`: Compute a minimal domain done score (programmatic).

## DONE signal

Emit a DONE receipt to the signal bus (append-only JSONL):

```bash
./.codex/skills/phosphene/beryl/product-strategy/modulator/scripts/product-strategy_emit_done_receipt.sh --issue-number <N> --work-id <ROADMAP-###>
```

## Validation (recommended)

- Validate all roadmaps:
  - `./.github/scripts/validate_product_roadmap.sh --all`
- Domain done score:
  - `./.github/scripts/product-strategy-domain-done-score.sh --min-score <PROMPT:done_score_min>`

Include (minimum) listing:

- inputs (pointers to RA coversheet/pitches; persona/proposition docs)
- outputs (ROADMAP doc)
- checks run (format/header compliance; any domain validators if/when added)

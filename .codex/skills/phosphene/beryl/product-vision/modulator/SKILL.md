---
name: product-vision
description: Produce <product-vision> artifacts (VISION-*) that establish the bet, non-negotiables, and falsifiers.
metadata:
  short-description: Vision stack + falsifiers
---

## Domain

Primary domain: `<product-vision>`

Lane (color): `beryl` (canonical; do not use other lanes for `<product-vision>`).

## What you produce

- Product vision docs:
  - `phosphene/domains/product-vision/output/visions/VISION-###-*.md`

## How to work

- Start from `<research>` evidence and `<product-marketing>` persona/proposition constraints.
- Treat upstream artifacts as constraints (do not invent personas/evidence here).
- Keep the vision compact: a single spine with non-negotiables and falsifiers.
- Manual edits are allowed for these single-file artifacts; keep headings stable.

## In-doc script hints (`[V-SCRIPT]`)

Some artifacts include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` when scanning an artifact to discover relevant control scripts for that section.

## Scripts (entrypoints and purpose)

- `create_product_vision.sh`: Create a new VISION doc (allocates VISION-###).
- `validate_product_vision.sh`: Validate VISION headers/sections and ID conventions.
- `product-vision_emit_done_receipt.sh`: Emit DONE receipt to the signal bus.
- `product-vision-domain-done-score.sh`: Compute a minimal domain done score (programmatic).

## DONE signal (required)

Emit a DONE receipt to the signal bus (append-only JSONL):

```bash
./.codex/skills/phosphene/beryl/product-vision/modulator/scripts/product-vision_emit_done_receipt.sh --issue-number <N> --work-id <VISION-###>
```

## Validation (recommended)

- Validate all vision docs:
  - `./.github/scripts/validate_product_vision.sh --all`
- Domain done score:
  - `./.github/scripts/product-vision-domain-done-score.sh --min-score <PROMPT:done_score_min>`

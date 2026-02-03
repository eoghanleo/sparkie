---
name: product-architecture
description: Produce <product-architecture> artifacts (ARCH-*) that define domain models, contracts, telemetry, and security scaffolding.
metadata:
  short-description: Architecture + contracts
---

## Domain

Primary domain: `<product-architecture>`

Lane (color): `cerulean` (canonical; do not use other lanes for `<product-architecture>`).

## What you produce

- Architecture docs:
  - `phosphene/domains/product-architecture/output/architectures/ARCH-###-*.md`

## How to work

- Treat upstream PRDs, roadmaps, and research as constraints (do not invent personas or evidence).
- Keep contracts explicit: list boundaries and link to machine artifacts when available.
- Manual edits are allowed for these single-file artifacts; keep headings stable.

## In-doc script hints (`[V-SCRIPT]`)

Some artifacts include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` when scanning an artifact to discover relevant control scripts for that section.

## Scripts (entrypoints and purpose)

- `create_product_architecture.sh`: Create a new ARCH doc (allocates ARCH-###).
- `validate_product_architecture.sh`: Validate ARCH headers/sections and ID conventions.
- `product-architecture_emit_done_receipt.sh`: Emit DONE receipt to the signal bus.
- `product-architecture-domain-done-score.sh`: Compute a minimal domain done score (programmatic).

## DONE signal (required)

Emit a DONE receipt to the signal bus (append-only JSONL):

```bash
./.codex/skills/phosphene/cerulean/product-architecture/modulator/scripts/product-architecture_emit_done_receipt.sh --issue-number <N> --work-id <ARCH-###>
```

## Validation (recommended)

- Validate all architecture docs:
  - `./.github/scripts/validate_product_architecture.sh --all`
- Domain done score:
  - `./.github/scripts/product-architecture-domain-done-score.sh --min-score <PROMPT:done_score_min>`

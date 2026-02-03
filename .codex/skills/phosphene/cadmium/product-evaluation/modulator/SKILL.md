---
name: product-evaluation
description: Produce <product-evaluation> artifacts (EVAL-*) that define readiness rubrics and eval harness gates.
metadata:
  short-description: Eval gates + readiness rubric
---

## Domain

Primary domain: `<product-evaluation>`

Lane (color): `cadmium` (canonical; do not use other lanes for `<product-evaluation>`).

## What you produce

- Evaluation docs:
  - `phosphene/domains/product-evaluation/output/evals/EVAL-###-*.md`

## How to work

- Treat PRDs/FRs as constraints; focus on readiness gates and eval hooks.
- Manual edits are allowed for these single-file artifacts; keep headings stable.

## In-doc script hints (`[V-SCRIPT]`)

Some artifacts include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` when scanning an artifact to discover relevant control scripts for that section.

## Scripts (entrypoints and purpose)

- `create_product_evaluation.sh`: Create a new EVAL doc (allocates EVAL-###).
- `validate_product_evaluation.sh`: Validate EVAL headers/sections and ID conventions.
- `product-evaluation_emit_done_receipt.sh`: Emit DONE receipt to the signal bus.
- `product-evaluation-domain-done-score.sh`: Compute a minimal domain done score (programmatic).

## DONE signal (required)

Emit a DONE receipt to the signal bus (append-only JSONL):

```bash
./.codex/skills/phosphene/cadmium/product-evaluation/modulator/scripts/product-evaluation_emit_done_receipt.sh --issue-number <N> --work-id <EVAL-###>
```

## Validation (recommended)

- Validate all eval docs:
  - `./.github/scripts/validate_product_evaluation.sh --all`
- Domain done score:
  - `./.github/scripts/product-evaluation-domain-done-score.sh --min-score <PROMPT:done_score_min>`

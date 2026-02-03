---
name: test-management
description: Produce <test-management> test plans (TP-*) and verification strategies aligned to specs/FRs.
metadata:
  short-description: Test plans
---

## Domain

Primary domain: `<test-management>`

## Status

Active (bus + emit receipts). Test-management is now in development.

## What you produce

- Test plans: `phosphene/domains/test-management/output/test-plans/TP-*.md`

## How to work

- Start from `<product-management>` acceptance criteria and `<feature-management>` FR constraints.
- Create artifacts directly under `phosphene/domains/test-management/output/test-plans/` (templates are intentionally not used).
- Keep test scope explicit (unit/integration/e2e) and the “definition of done” checkable.
- Manual edits are allowed for these single-file artifacts; keep headings stable.

## In-doc script hints (`[V-SCRIPT]`)

Some templates/artifacts include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` when scanning an artifact to discover relevant control scripts for that section.

## Scripts (entrypoints and purpose)

- `create_test_plan.sh`: Create a new TP doc (allocates TP-###).
- `validate_test_plan.sh`: Validate TP headers/sections and ID conventions.
- `test-management_emit_done_receipt.sh`: Emit DONE receipt to the signal bus.
- `test-management-domain-done-score.sh`: Compute a minimal domain done score (programmatic).

## DONE signal

Emit a DONE receipt to the signal bus (append-only JSONL):

```bash
./.codex/skills/phosphene/cadmium/test-management/modulator/scripts/test-management_emit_done_receipt.sh --issue-number <N> --work-id <TP-###>
```

## Validation (recommended)

- Validate all test plans:
  - `./.github/scripts/validate_test_plan.sh --all`
- Domain done score:
  - `./.github/scripts/test-management-domain-done-score.sh --min-score <PROMPT:done_score_min>`

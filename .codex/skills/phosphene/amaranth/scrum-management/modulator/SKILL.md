---
name: scrum-management
description: Produce <scrum-management> issue mirrors and lightweight operational artifacts; keep routing/status portable via labels.
metadata:
  short-description: Operational issues + mirrors
---

## Domain

Primary domain: `<scrum-management>`

## Status

Active (bus + emit receipts). Scrum-management is now in development.

## What you produce

- Optional issue mirror docs (scaffold): `phosphene/domains/scrum-management/output/issues/ISSUE-*.md`

## How to work

- Treat Issues (GitHub/Linear) as optional UX; keep the automation contract portable (labels + PR events).
- If mirroring state into repo headers, do so via PR (audit trail).
- Create artifacts directly under `phosphene/domains/scrum-management/output/issues/` (if/when you mirror issues into the repo).
- Manual edits are allowed for these single-file artifacts; keep headings stable.

## In-doc script hints (`[V-SCRIPT]`)

Some templates/artifacts include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` when scanning an artifact to discover relevant control scripts for that section.

## Scripts (entrypoints and purpose)

- `create_issue_mirror.sh`: Create an ISSUE mirror doc (allocates ISSUE-###).
- `validate_issue_mirror.sh`: Validate ISSUE headers/sections and ID conventions.
- `scrum-management_emit_done_receipt.sh`: Emit DONE receipt to the signal bus.
- `scrum-management-domain-done-score.sh`: Compute a minimal domain done score (programmatic).

## DONE signal

Emit a DONE receipt to the signal bus (append-only JSONL):

```bash
./.codex/skills/phosphene/amaranth/scrum-management/modulator/scripts/scrum-management_emit_done_receipt.sh --issue-number <N> --work-id <ISSUE-###>
```

## Validation (recommended)

- Validate all issue mirrors:
  - `./.github/scripts/validate_issue_mirror.sh --all`
- Domain done score:
  - `./.github/scripts/scrum-management-domain-done-score.sh --min-score <PROMPT:done_score_min>`

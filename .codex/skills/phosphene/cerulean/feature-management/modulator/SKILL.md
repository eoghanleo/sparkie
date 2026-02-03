---
name: feature-management
description: Produce and manage <feature-management> Feature Requests (FR dossiers) using bash-only PHOSPHENE scripts (create/validate/approve/status/deps).
metadata:
  short-description: Feature Requests (FR dossiers)
---

## Domain

Primary domain: `<feature-management>`

## Status

Active (bus + emit receipts). Feature-management is now in development.

## What you produce

- Feature Requests as bash-parseable Markdown dossiers:
  - `phosphene/domains/feature-management/output/frs/FR-###-*.md`

Auto-generated (do not edit by hand):
- `phosphene/domains/feature-management/output/backlog_tree.md`
- `phosphene/domains/feature-management/output/fr_dependencies.md`

## Script-first workflow (preferred)

- Create an FR:
  - `./.codex/skills/phosphene/cerulean/feature-management/modulator/scripts/create_feature_request.sh --title "..." --description "..." --priority "High"`
- Validate:
  - `./.github/scripts/validate_feature_request.sh`
- Approve (by ID):
  - `./.codex/skills/phosphene/cerulean/feature-management/modulator/scripts/approve_feature_request.sh --id FR-001`
- Update status:
  - `./.codex/skills/phosphene/cerulean/feature-management/modulator/scripts/update_feature_request_status.sh <path-to-fr.md> "In Progress"`
- Refresh reports:
  - `./.codex/skills/phosphene/cerulean/feature-management/modulator/scripts/update_backlog_tree.sh`
  - `./.codex/skills/phosphene/cerulean/feature-management/modulator/scripts/feature_request_dependency_tracker.sh`

## In-doc script hints (`[V-SCRIPT]`)

Some templates/artifacts include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` when scanning an artifact to discover relevant control scripts for that section.

## Scripts (entrypoints and purpose)

- `create_feature_request.sh`: Create a new FR dossier from the template (allocates folder + file).
- `validate_feature_request.sh`: Validate FR dossier structure and repo-level FR invariants.
- `approve_feature_request.sh`: Approve an FR by ID (status transition).
- `update_feature_request_status.sh`: Update the status field in an FR dossier.
- `update_backlog_tree.sh`: Regenerate `output/backlog_tree.md` (auto-generated view).
- `feature_request_dependency_tracker.sh`: Regenerate `output/fr_dependencies.md` (auto-generated dependency report).
- `feature-management_emit_done_receipt.sh`: Emit DONE receipt to the signal bus.
- `feature-management-domain-done-score.sh`: Compute a minimal domain done score (programmatic).

## DONE signal

Emit a DONE receipt to the signal bus (append-only JSONL):

```bash
./.codex/skills/phosphene/cerulean/feature-management/modulator/scripts/feature-management_emit_done_receipt.sh --issue-number <N> --work-id <FR-###>
```

## Validation (recommended)

- Validate FR dossiers:
  - `./.github/scripts/validate_feature_request.sh`
- Domain done score:
  - `./.github/scripts/feature-management-domain-done-score.sh --min-score <PROMPT:done_score_min>`

## Constraints

- Keep FR dossiers machine-parseable (strict header block; required headings).
- Prefer updating headers over moving files (single-layout stability).

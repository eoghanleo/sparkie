# Feature Management (Domain)

Primary artifacts:
- `feature-request` (FR) — bash-parseable Markdown dossier created/managed by PHOSPHENE.

Canonical locations:
- FR dossiers: `phosphene/domains/feature-management/output/frs/FR-*.md`
- Auto-generated:
  - `phosphene/domains/feature-management/output/backlog_tree.md`
  - `phosphene/domains/feature-management/output/fr_dependencies.md`

Primary commands:
- `./.codex/skills/phosphene/cerulean/feature-management/modulator/scripts/create_feature_request.sh`
- `./.github/scripts/validate_feature_request.sh`
- `./.codex/skills/phosphene/cerulean/feature-management/modulator/scripts/approve_feature_request.sh --id FR-001`
- `./.codex/skills/phosphene/cerulean/feature-management/modulator/scripts/update_feature_request_status.sh phosphene/domains/feature-management/output/frs/FR-001-... \"In Progress\"`



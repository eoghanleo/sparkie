# PRDs (Product Requirements Documents)

Canonical root:
- `phosphene/domains/product-management/output/prds/`

Bundles:
- `PRD-###-<slug>/` is a PRD bundle directory (authoritative subfiles + an assembled view).

Inside a bundle:
- `00-coversheet.md` is the source of truth for `ID: PRD-###` and top-level `Dependencies:`
- `PRD-###.md` is **auto-assembled** (read-only; do not hand-edit)

Create/assemble using the domain scripts:

```bash
./.codex/skills/phosphene/cerulean/product-management/modulator/scripts/create_prd_bundle.sh --title "..." [--id PRD-001]
./.codex/skills/phosphene/cerulean/product-management/modulator/scripts/assemble_prd_bundle.sh phosphene/domains/product-management/output/prds/PRD-001-<slug>
```


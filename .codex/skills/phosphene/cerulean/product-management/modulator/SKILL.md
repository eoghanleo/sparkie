---
name: product-management
description: Produce <product-management> artifacts (PRD-*) that translate strategy into requirements, acceptance criteria, and validation plans.
metadata:
  short-description: Product requirements (PRD bundles)
---

## Domain

Primary domain: `<product-management>`

## What you produce

- PRD bundles:
  - `phosphene/domains/product-management/output/prds/PRD-###-<slug>/`
  - `phosphene/domains/product-management/output/prds/PRD-###-<slug>/PRD-###.md` (auto-assembled view; do not hand-edit)

## How to work

- Treat upstream artifacts as **constraints**, not suggestions:
  - `<product-strategy>` defines the bet + sequencing constraints.
  - `<product-marketing>` defines persona + proposition constraints (what must be true for the pitch to land).
  - `<research>` defines evidence + unknowns (what is known vs hypothesized).
- Create artifacts directly under `phosphene/domains/product-management/output/prds/` (templates are intentionally not used).
- Keep acceptance criteria and validation experiments explicit.
- Keep the output **bash-parseable and reviewable** (stable header block; consistent IDs).

## In-doc script hints (`[V-SCRIPT]`)

Some templates/artifacts include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` when scanning an artifact to discover relevant control scripts for that section.

## Scripts (entrypoints and purpose)

Core scripts:
- `./.codex/skills/phosphene/cerulean/product-management/modulator/scripts/create_prd_bundle.sh`
- `./.codex/skills/phosphene/cerulean/product-management/modulator/scripts/assemble_prd_bundle.sh`
- `./.codex/skills/phosphene/cerulean/product-management/modulator/scripts/product-management_emit_done_receipt.sh`

Do **not** hand-edit upstream script-managed artifacts (PER/PROP/RA bundles); treat them as inputs.

## Tightening moves (from observed agent output failures)

These are the “rails” that prevent the kinds of drift we saw in `<product-marketing>` (bad traceability, header/body mismatch, and manual-edit breakage):

- **Traceability is mandatory**:
  - Every referenced upstream ID in the PRD must resolve via the global registry (`where`).
  - If you cite EvidenceIDs, they must exist in the RA evidence bank.
- **Header/body consistency**:
  - `Dependencies:` must include every top-level artifact you materially relied on (at minimum: `RA-*` plus any `PER-*`/`PROP-*`/`ROADMAP-*` you reference).
- **No new claims without support**:
  - If a requirement is justified by user need, link it to a `PER-*` JTBD ID and/or `EvidenceID` (or explicitly mark as hypothesis + confidence).

## ID hygiene (required)

Before finalizing a PRD, run:

```bash
./.codex/skills/phosphene/viridian/research/modulator/scripts/research_id_registry.sh validate
./.codex/skills/phosphene/viridian/research/modulator/scripts/research_id_registry.sh where RA-001
./.codex/skills/phosphene/viridian/research/modulator/scripts/research_id_registry.sh where PER-0003
./.codex/skills/phosphene/viridian/research/modulator/scripts/research_id_registry.sh where PROP-0002
./.codex/skills/phosphene/viridian/research/modulator/scripts/research_id_registry.sh where E-0009
```

If an ID doesn’t resolve, you must either:
- fix the reference, or
- create the authoritative upstream artifact first (in its correct domain).

## DONE signal (required for condenser-ready work)

Emit a DONE receipt to `phosphene/signals/bus.jsonl` (append-only JSONL bus):

```bash
./.codex/skills/phosphene/cerulean/product-management/modulator/scripts/product-management_emit_done_receipt.sh --issue-number <N> --work-id <PRD-###>
```

Include (minimum) listing:

- inputs (ROADMAP + persona/proposition + RA pointers)
- outputs (PRD bundle path(s))
- checks run (format/header compliance; any domain validators if/when added)

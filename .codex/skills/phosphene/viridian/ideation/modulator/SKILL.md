---
name: ideation
description: Produce <ideation> artifacts (IDEA-*) as seed concepts for downstream domains; keep inputs minimal and hypotheses explicit.
metadata:
  short-description: Ideation (IDEA artifacts)
---

## Domain

Primary domain: `<ideation>`

## Status

Active (bus + emit receipts). Ideation is now in development.

## What you produce

- Ideas as repo artifacts:
  - `phosphene/domains/ideation/output/ideas/IDEA-*.md`

## How to work

- Create artifacts directly under `phosphene/domains/ideation/output/ideas/` (templates are intentionally not used).
- Use the SPARK snapshot as the **primary input** (issue text is materialized there by hopper).
- Each ideation run includes **mandatory manifold probes** derived from:
  - `SeedSHA256` and `ManifoldProbeCount` in the SPARK header.
  - Deterministic selection from `WIP/creative_madness/manifold_probes.jsonl`.
- Your core output is a **deterministic Storm table** (probe pairs × rings):
  - 3 rings: `adjacent`, `orthogonal`, `extrapolatory`
  - `manifold_probe_count` probes ⇒ **(n choose 2) × 3 rows**
  - Columns: `STORM-ID`, `PROBE_1`, `PROBE_2`, `RING`, `DESCRIPTION`
  - Each row must include a **DESCRIPTION paragraph** with **≥ 3 sentences**.
  - There is **no convergence/stress-test** step in ideation.

### Storm interpretation (mandatory)

- Treat PROBE_1 + PROBE_2 as **conceptual anchors** (material/constraints) and RING as the divergence lens.
- The DESCRIPTION **should not repeat labels verbatim** unless it is a perfect fit.
- The goal is divergence with traceability: the same SPARK input should behave differently across probe pairs and rings.

## In-doc script hints (`[V-SCRIPT]`)

Some templates/artifacts include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` when scanning an artifact to discover relevant control scripts for that section.

## Scripts (entrypoints and purpose)

- `create_idea.sh`: Create a new IDEA artifact (allocates IDEA-####).
- `ideation_storm_table_bootstrap.sh`: Rewrite the storm table for the selected probes (SPARK-derived).
- `provide_next_storm_prompt.sh`: Print the next uncompleted storm row and the setter command.
- `ideation_storm_set_description.sh`: Set DESCRIPTION for a specific STORM-ID row.
- `validate_idea.sh`: Validate IDEA headers/sections and ID conventions.
- `ideation_emit_done_receipt.sh`: Emit DONE receipt to the signal bus.
- `ideation-domain-done-score.sh`: Compute a minimal domain done score (programmatic).

## Recommended loop

1. `create_idea.sh` to create the IDEA file.
2. `ideation_storm_table_bootstrap.sh` to generate the storm table + footer.
3. `provide_next_storm_prompt.sh` → `ideation_storm_set_description.sh` for each row.
4. Repeat until all descriptions are filled.
5. Run `validate_idea.sh`, then `ideation-domain-done-score.sh`.
6. Iterate until PASS, then emit DONE receipt.

## DONE signal

Emit a DONE receipt to the signal bus (append-only JSONL):

```bash
./.codex/skills/phosphene/viridian/ideation/modulator/scripts/ideation_emit_done_receipt.sh --issue-number <N> --work-id <IDEA-####>
```

## Validation (recommended)

- Resolve the IDEA artifact path:
  - `./phosphene/phosphene-core/bin/phosphene id where <IDEA-####>`
- Validate the IDEA artifact:
  - `bash .github/scripts/validate_idea.sh <path>`
- Domain done score:
  - `bash .github/scripts/ideation-domain-done-score.sh --file <path> --min-score <PROMPT:done_score_min>`

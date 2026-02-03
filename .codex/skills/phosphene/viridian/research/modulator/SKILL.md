---
name: research
description: Produce <research> artifacts (RA bundles) using PHOSPHENE scripts and global unique IDs (E-/RS-/PITCH-/SEG-/CPE-/PER-).
metadata:
  short-description: Research assessments (RA bundles)
---

## Domain

Primary domain: `<research>`

## Status

Active (bus + emit receipts). Research is now in development.

## What you produce

- Research Assessments as **bundle folders** under `phosphene/domains/research/output/research-assessments/RA-###-<slug>/`.

Bundle files (required):
- `00-coversheet.md`
- `10-reference-solutions.md`
- `20-competitive-landscape.md`
- `30-pitches/PITCH-*.md`
- `40-hypotheses.md`
- `50-evidence-bank.md`
- `90-methods.md`

Optional:
- `99-raw-agent-output.md` (verbatim raw dump; **non-authoritative**)

Generated (view only):
- `RA-###.md` (assembled; do not treat as authoritative definitions)

## Global ID uniqueness (hard requirement)

All object IDs must be globally unique across `phosphene/domains/**/output/**`:

- EvidenceIDs: `E-####`
- RefSolIDs: `RS-####`
- PitchIDs: `PITCH-####`
- SegmentIDs: `SEG-####`
- CandidatePersonaIDs (research → marketing candidates): `CPE-####`
- PersonaIDs (canonical; <product-marketing> only): `PER-####`

Use the registry:

- Build: `./.codex/skills/phosphene/viridian/research/modulator/scripts/research_id_registry.sh build`
- Validate: `./.codex/skills/phosphene/viridian/research/modulator/scripts/research_id_registry.sh validate`
- Allocate: `./.codex/skills/phosphene/viridian/research/modulator/scripts/research_id_registry.sh next --type ra|pitch|evidence|refsol|segment|cpe|persona`

## Script-first workflow (preferred)

- Create RA bundle:
  - `./.codex/skills/phosphene/viridian/research/modulator/scripts/create_research_assessment_bundle.sh --title "..." --priority Medium`
- Validate bundle:
  - `./.github/scripts/validate_research_assessment_bundle.sh <bundle_dir>`
- Assemble single-file view:
  - `./.codex/skills/phosphene/viridian/research/modulator/scripts/assemble_research_assessment_bundle.sh <bundle_dir>`
- Create pitches / add evidence / add reference solutions:
  - `./.codex/skills/phosphene/viridian/research/modulator/scripts/create_product_pitch.sh <bundle_dir>`
  - `./.codex/skills/phosphene/viridian/research/modulator/scripts/add_evidence_record.sh <bundle_dir>`
  - `./.codex/skills/phosphene/viridian/research/modulator/scripts/add_reference_solution.sh <bundle_dir>`
- Create candidate personas (1:1 proposals for <product-marketing> personas):
  - `./.codex/skills/phosphene/viridian/research/modulator/scripts/create_candidate_persona.sh --bundle <bundle_dir> --name "..." --segment SEG-0001`

## In-doc script hints (`[V-SCRIPT]`)

Some artifacts include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` when scanning an artifact to discover relevant control scripts for that section.

## Scripts (entrypoints and purpose)

- `create_research_assessment_bundle.sh`: Create a new RA bundle folder (canonical skeleton is hard-coded); allocates the next `RA-###` if omitted.
- `validate_research_assessment_bundle.sh`: Validate RA bundle structure, headings, cross-references, and required folders.
- `assemble_research_assessment_bundle.sh`: Generate the assembled `RA-###.md` view from bundle parts (non-authoritative).
- `research_id_registry.sh`: Build/validate/query the global `id_index.tsv`, and allocate the next IDs (`ra|pitch|evidence|refsol|segment|cpe|persona|proposition`).
- `create_product_pitch.sh`: Create a new `PITCH-####` file in an RA bundle (allocates ID).
- `add_evidence_record.sh`: Append a new EvidenceID row (`E-####`) to `50-evidence-bank.md` (allocates ID).
- `add_reference_solution.sh`: Append a new RefSol row (`RS-####`) to `10-reference-solutions.md` (allocates ID).
- `create_candidate_persona.sh`: Create a new Candidate Persona (`CPE-####`) doc inside an RA bundle (allocates ID).
- `research_emit_done_receipt.sh`: Emit DONE receipt to the signal bus.

## DONE signal

Emit a DONE receipt to the signal bus (append-only JSONL):

```bash
./.codex/skills/phosphene/viridian/research/modulator/scripts/research_emit_done_receipt.sh --issue-number <N> --work-id <RA-###>
```

## Validation (recommended)

- Validate RA bundles:
  - `./.github/scripts/validate_research_assessment_bundle.sh --all`
- Domain done score:
  - `./.github/scripts/research-domain-done-score.sh --min-score <PROMPT:done_score_min>`

## Constraints

- Web-only research (no interviews) unless explicitly authorized.
- Keep product definition light; prioritize reference solutions, competition, segment/persona hypotheses, and candidate pitches.

# Product Marketing (Domain)

WTBD parent (required):
- `value-proposition-design` — a VPD bundle (`VPD-###`) that scopes a coherent run of persona + proposition work.

Primary artifacts:
- `persona` — who we serve and what they care about.
- `proposition` — what we promise and why it’s compelling.

Canonical locations:
- Creation + updates are script-driven (no runtime templates).
- Working artifacts (scoped under a VPD bundle):
  - `phosphene/domains/product-marketing/output/value-proposition-designs/VPD-###-<slug>/00-coversheet.md`
  - `phosphene/domains/product-marketing/output/value-proposition-designs/VPD-###-<slug>/10-personas/PER-*.md`
  - `phosphene/domains/product-marketing/output/value-proposition-designs/VPD-###-<slug>/20-propositions/PROP-*.md`

Create a new VPD bundle:

```bash
./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/create_value_proposition_design_bundle.sh --title "..."
```

Validation (recommended):
- `./.github/scripts/validate_persona.sh --all`
- `./.github/scripts/validate_proposition.sh --all`

Note:
- Every `PER-*` and `PROP-*` must include a `VPD-###` in its `Dependencies:` header.

JTBD IDs convention (natural keys):
- In persona Jobs/Pains/Gains tables, use: `JTBD-<TYPE>-####-<PersonaID>`
  - `<TYPE>` is `JOB|PAIN|GAIN`
  - `<PersonaID>` is the persona `PER-####` from the file header

Helper (optional):
- `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/add_persona_jtbd_item.sh --persona phosphene/domains/product-marketing/output/value-proposition-designs/VPD-001-.../10-personas/PER-0001.md --type JOB --text "..." --importance 3`

Workflow policy (preferred):
- For repeatable performance, prefer **script-first updates** for persona artifacts (avoid hand-editing).
- See `.codex/skills/phosphene/beryl/product-marketing/modulator/SKILL.md` for the full control script list.

Handoff (default):
- **To Product Strategy** with market framing and messaging constraints.
- **To Product Management** with positioning that must be reflected in the spec.

Upstream input (common):
- `<research>` bundles may include **Candidate Personas** (`CPE-####`) under `60-candidate-personas/`.
  - Treat creating `PER-####` as a promotion step from one or more CPE candidates.



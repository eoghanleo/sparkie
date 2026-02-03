---
name: product-marketing
description: Produce <product-marketing> artifacts (PER-* personas, PROP-* propositions) from research hypotheses and evidence IDs.
metadata:
  short-description: Personas + propositions
---

## Domain

Primary domain: `<product-marketing>`

Lane (color): `beryl` (canonical; do not use other lanes for `<product-marketing>`).

## What you produce

- VPD bundles: `phosphene/domains/product-marketing/output/value-proposition-designs/VPD-###-*/00-coversheet.md`
- Personas: `phosphene/domains/product-marketing/output/value-proposition-designs/VPD-###-*/10-personas/PER-*.md`
- Propositions: `phosphene/domains/product-marketing/output/value-proposition-designs/VPD-###-*/20-propositions/PROP-*.md`

## How to work

- Start from `<research>` outputs:
  - Candidate Personas: `CPE-*` docs inside the RA bundle (`60-candidate-personas/`)
  - Segments/persona hypotheses, EvidenceIDs, and the pitch set
- You may (and should) also link and cite **any other `<research>` artifacts** you consulted (e.g. methods, evidence bank, hypothesis notes, assembled bundles) via `DocumentIDs` / `Links` to drive deeper reading and higher connectivity-to-input.
- Creation is script-driven (no runtime templates): use the `create_*` scripts below to emit canonical artifacts.
- Treat personas/segments as hypotheses unless validated; include confidence and EvidenceIDs when making claims.
- When creating a canonical Persona (PER-*), treat it as a **promotion** of one or more CPE candidates (cite source CPE IDs).
- Treat the **domain done-score** as a first-class validator:
  - The harness prompt will supply `done_score_min` (your target threshold).
  - You must run the done-score script repeatedly and iterate until it is **PASS**.

## Value proposition design stance (opinionated; central)

You are doing **value proposition design** (VPD): a **creative analytical** role that maximizes structured opportunity in the problem space.

### Personas: you may extend beyond research candidates (required creativity)

- You are **allowed to create new personas** beyond the `CPE-*` candidates **if** you can justify them as:
  - a split (one CPE decomposed into multiple distinct needs/contexts),
  - a merge (multiple CPEs synthesized into a single canonical persona),
  - a missing-but-implied role/context that is a sensible extension of the research bundle.
- “Common sense” and latent product-marketing knowledge are **allowed and expected**. Do not pretend research is exhaustive.
- **Traceability requirement** (non-negotiable): every new/extended `PER-*` must record its rationale and provenance:
  - link upstream `CPE-*` where applicable (CandidatePersonaIDs),
  - link upstream RA + pitch IDs (DocumentIDs),
  - link supporting `E-*` where applicable (EvidenceIDs),
  - if a persona is primarily inferred, say so explicitly in `## Notes` and explain what bundle facts it extends.

### Propositions: not a product spec; be exhaustive and overlapping

- A value proposition is **above features** but **below the product**.
- Propositions should be **overlapping and synergistic**. Overlap is a feature, not a bug.
- The goal is to produce **as many distinct propositions as possible**, mapped to the persona pool:
  - cover different combinations of the same persona’s top Jobs/Pains/Gains,
  - cover different mechanisms/angles for the same pain/gain set,
  - cover different persona subsets (single persona vs multi-persona propositions).
- Do **not** collapse into implementation detail. Downstream domains (strategy/roadmap/feature-management) will refine into product specifics.

### Proposition abstraction level (anti-pattern guardrail)

Your propositions must be **aggregateable** by downstream agents into product visions and PRDs:

- A `PROP-*` is **not** “an entire product idea” or “a competitor replacement”.
- A `PROP-*` should read like an **outcome + mechanism stack** that could be combined with other propositions:
  - If a proposition implicitly requires a full standalone product, split it into multiple smaller propositions that can be recombined.
  - Prefer multiple propositions that share capabilities/boosters/relievers over one monolith.

### How to “map” propositions (make them mechanically useful downstream)

- Ensure each `PROP-*` has explicit **Target Persona(s)** (PER IDs).
- Ensure boosters/relievers map to the target persona’s JTBD IDs:
  - `MappedGainIDs[]`: `JTBD-GAIN-####-PER-####`
  - `MappedPainIDs[]`: `JTBD-PAIN-####-PER-####`
- Capabilities should remain **capability-level** (`feature|function|standard|experience`), not “spec backlog items”.

## Recursive iteration mandate (non-negotiable)

This domain is only valuable when you **recursively map the value space**.

- **Do not stop** at a single-pass “promote CPE → PER” and “promote PITCH → PROP”.
- You must loop until you can reasonably claim you’ve mined the problem space:
  - expand personas (splits/merges/missing implied personas),
  - expand JTBD coverage per persona,
  - expand propositions (many overlapping),
  - expand mappings (each prop maps to multiple JTBDs for its target personas).

## Coverage targets (minimum gates; report in your DONE signal)

These are **minimum** gates intended to force multi-pass enrichment. If you cannot meet them due to limited upstream evidence, you must:
- still perform the iterations, and
- explicitly justify the shortfall in your DONE signal (what prevented it; what would be needed).

### Personas (PER-*) — minimum per persona

- **JTBD coverage**:
  - at least **5 Jobs**
  - at least **5 Pains**
  - at least **5 Gains**
- **Fragment depth (required; drives exploration)**:
  - Every individual JTBD fragment (each Job/Pain/Gain table row) must be **2–3 sentences**.
  - Each fragment should include:
    - the concrete behavior/context (what’s happening),
    - the underlying need (why it matters),
    - and (optionally) an edge case / objection / tradeoff.
- **Traceability**:
  - at least **2** items across EvidenceIDs/CandidatePersonaIDs/DocumentIDs combined (more is better)
  - if an item is inferred, record the inference in `## Notes` (and keep speculative claims out of “authoritative voice”).

### Propositions (PROP-*) — minimum per proposition

- **Targeting**:
  - at least **1** Target Persona
  - at least **1** Related Segment (if segments exist upstream; otherwise justify)
- **Mechanism tables**:
  - at least **4** Gain Boosters rows
  - at least **4** Pain Relievers rows
  - at least **4** Capabilities rows
- **Fragment depth (required; drives exploration)**:
  - Every individual fragment row must be **2–3 sentences**:
    - Booster
    - Reliever
    - Capability
  - Keep them mechanism-level and testable (avoid vague “make it better” language).
- **Mapping density**:
  - each booster should map to **2+** gains when possible
  - each reliever should map to **2+** pains when possible

### Proposition breadth — minimum per persona

- For each canonical persona you output, produce at least:
  - **3** propositions that target that persona (can be overlapping, can be shared with other personas).

## Value-space mining checklist (qualitative; must be covered)

You must be able to point to propositions/persona JTBDs that cover each axis below (where applicable):

- **Benefit stacks**: different “bundles” of gains + pains (not just the pitch’s primary framing)
- **Packaging**: lightweight vs heavyweight experience, guided vs autonomous, casual vs deep
- **Risk / objections**: trust, accuracy, time cost, learning curve, sunk cost, privacy
- **Acquisition contexts**: where/when the persona discovers the proposition (storefront, community, creator content, referrals)
- **Monetization contexts**: free vs subscription vs IAP; “what are they paying for?” (without writing a full pricing spec)
- **Segment edges**: adjacent segments and “why it does/doesn’t fit” boundaries
- **Synergies**: propositions that reinforce each other vs propositions that compete for attention

## Definition of done (domain-specific, producing mode)

You must not write your DONE signal until:

- All validators are green (and strict variants if required by the run).
- The **coverage targets** above are met (or explicitly justified).
- The domain done-score is **PASS** (threshold comes from the harness prompt via `done_score_min`).
- Your DONE signal includes:
  - counts per persona: Jobs/Pains/Gains
  - counts per proposition: boosters/relievers/capabilities
  - a checklist note stating how each qualitative axis was addressed (reference PROP IDs)
  - the done-score report (overall + subscores), the `done_score_min` you were given, and a short “next actions” note if any subscores are low.

## In-doc script hints (`[V-SCRIPT]`)

Persona artifacts include fenced code blocks that begin with `[V-SCRIPT]:` listing the relevant script entrypoints for that section.
Search for `[V-SCRIPT]` when scanning a persona artifact to discover the right control scripts quickly.

JTBD IDs convention (natural keys):
- Jobs/Pains/Gains use IDs of the form: `JTBD-<TYPE>-####-<PersonaID>`
  - `<TYPE>` is `JOB|PAIN|GAIN`
  - `<PersonaID>` is the persona `PER-####` from the file header

## Validation (recommended)

- Create a VPD bundle:
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/create_value_proposition_design_bundle.sh --title "..."`
- Validate a persona:
  - `./.github/scripts/validate_persona.sh phosphene/domains/product-marketing/output/value-proposition-designs/VPD-001-.../10-personas/PER-0001.md`
- Validate a proposition:
  - `./.github/scripts/validate_proposition.sh phosphene/domains/product-marketing/output/value-proposition-designs/VPD-001-.../20-propositions/PROP-0001.md`
- Validate all personas:
  - `./.github/scripts/validate_persona.sh --all`
- Validate all propositions:
  - `./.github/scripts/validate_proposition.sh --all`
- Domain done score (mandatory for producing; programmatic; no generation):
  - `./.github/scripts/product-marketing-domain-done-score.sh --min-score <PROMPT:done_score_min>`

## Scripts (entrypoints and purpose)

All scripts are **control scripts** (script-first; avoid hand-editing). Most scripts re-run validators after applying changes.

### Personas (PER-*)

- `create_new_persona.sh`: Create a new persona doc (canonical skeleton is hard-coded); allocates the next `PER-####`.
- `validate_persona.sh`: Validate persona headers/sections/JTBD tables and ID conventions.
- `update_persona_summary.sh`: Replace the `## Snapshot summary` section.
- `add_persona_jtbd_item.sh`: Append a new JOB/PAIN/GAIN row with the next `JTBD-<TYPE>-####-<PersonaID>`.
- `update_persona_jtbd_item.sh`: Update an existing JTBD row by JTBD ID.
- `add_persona_evidence_link.sh`: Add a supporting ID into EvidenceIDs / CandidatePersonaIDs / DocumentIDs (routes by prefix).
- `remove_persona_evidence_link.sh`: Remove a supporting ID from those buckets.
- `add_persona_related_link.sh`: Add a link under `### Links`.
- `remove_persona_related_link.sh`: Remove a link under `### Links`.
- `add_persona_note.sh`: Append a timestamped note entry under `## Notes`.
- `overwrite_persona_notes.sh`: Replace the entire `## Notes` section.

### Propositions (PROP-*)

- `create_new_proposition.sh`: Create a new proposition doc (canonical skeleton is hard-coded); allocates the next `PROP-####`.
- `validate_proposition.sh`: Validate proposition headers/sections/tables and ID conventions.
- `update_proposition_formal_pitch.sh`: Replace the `## Formal Pitch` section (keeps the `[V-SCRIPT]` block).
- `add_proposition_target_persona.sh`: Add a `PER-####` bullet under `## Target Persona(s)`.
- `remove_proposition_target_persona.sh`: Remove a `PER-####` bullet from that list.
- `add_proposition_related_segment.sh`: Add a `SEG-####` bullet under `## Related Segment(s)`.
- `remove_proposition_related_segment.sh`: Remove a `SEG-####` bullet from that list.
- `add_proposition_gain_booster.sh`: Add a `BOOST-####-PROP-####` row and mapped `JTBD-GAIN-####-PER-####` list.
- `update_proposition_gain_booster.sh`: Update a booster row by BoosterID.
- `add_proposition_pain_reliever.sh`: Add a `REL-####-PROP-####` row and mapped `JTBD-PAIN-####-PER-####` list.
- `update_proposition_pain_reliever.sh`: Update a reliever row by RelieverID.
- `add_proposition_capability.sh`: Add a `CAP-####-PROP-####` row with type `feature|function|standard|experience`.
- `update_proposition_capability.sh`: Update a capability row by CapabilityID.
- `add_proposition_note.sh`: Append a timestamped note entry under `## Notes`.
- `overwrite_proposition_notes.sh`: Replace the entire `## Notes` section.
- `product-marketing-domain-done-score.sh`: Compute a programmatic domain done score for breadth/depth/interconnection across all PER/PROP outputs; prints subscores and next actions.

## Script helpers (optional)

- Add a JOB/PAIN/GAIN JTBD row (auto-allocates the next local #### and appends `-PER-####`):
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/add_persona_jtbd_item.sh --persona phosphene/domains/product-marketing/output/value-proposition-designs/VPD-001-.../10-personas/PER-0001.md --type JOB --text "..." --importance 3`

## Control scripts (preferred; avoid hand-editing)

For repeatability, prefer using these scripts instead of manual edits:

- Create a new persona:
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/create_new_persona.sh --title "..." --vpd VPD-001 --dependencies "CPE-0001,RA-001"`
- Update snapshot summary:
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/update_persona_summary.sh --persona phosphene/domains/product-marketing/output/value-proposition-designs/VPD-001-.../10-personas/PER-0001-*.md --summary-file /path/to/summary.md`
- Add/update JTBD rows:
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/add_persona_jtbd_item.sh --persona ... --type JOB|PAIN|GAIN --text "..." --importance 3`
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/update_persona_jtbd_item.sh --persona ... --jtbd-id JTBD-PAIN-0001-PER-0001 --text "..." --importance 5`
- Add/remove supporting IDs (EvidenceIDs/CPE IDs/other DocumentIDs):
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/add_persona_evidence_link.sh --persona ... --id E-0001`
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/remove_persona_evidence_link.sh --persona ... --id E-0001`
- Add/remove related links:
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/add_persona_related_link.sh --persona ... --link "https://example.com"`
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/remove_persona_related_link.sh --persona ... --link "https://example.com"`
- Notes:
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/add_persona_note.sh --persona ... --note "..." `
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/overwrite_persona_notes.sh --persona ... --notes-file /path/to/notes.md`

### Propositions (PROP-*)

- Create a new proposition:
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/create_new_proposition.sh --title "..." --vpd VPD-001 --dependencies "PER-0001,RA-001"`
- Formal pitch:
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/update_proposition_formal_pitch.sh --proposition ... --pitch "Our <capabilities> help ..."`
- Target personas / related segments:
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/add_proposition_target_persona.sh --proposition ... --persona PER-0001`
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/remove_proposition_target_persona.sh --proposition ... --persona PER-0001`
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/add_proposition_related_segment.sh --proposition ... --segment SEG-0001`
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/remove_proposition_related_segment.sh --proposition ... --segment SEG-0001`
- Gain boosters / pain relievers:
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/add_proposition_gain_booster.sh --proposition ... --booster "..." --mapped-gains "JTBD-GAIN-0001-PER-0001"`
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/update_proposition_gain_booster.sh --proposition ... --booster-id BOOST-0001-PROP-0001 --mapped-gains "..."`
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/add_proposition_pain_reliever.sh --proposition ... --reliever "..." --mapped-pains "JTBD-PAIN-0001-PER-0001"`
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/update_proposition_pain_reliever.sh --proposition ... --reliever-id REL-0001-PROP-0001 --mapped-pains "..."`
- Capabilities:
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/add_proposition_capability.sh --proposition ... --type feature --capability "..."`
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/update_proposition_capability.sh --proposition ... --capability-id CAP-0001-PROP-0001 --type experience --capability "..."`
- Notes:
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/add_proposition_note.sh --proposition ... --note "..." `
  - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/overwrite_proposition_notes.sh --proposition ... --notes-file /path/to/notes.md`

## Receipts (required)

Write a DONE receipt line to the JSONL bus:
- `phosphene/signals/bus.jsonl`
- Use: `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/product-marketing_emit_done_receipt.sh`

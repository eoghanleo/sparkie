# AGENTS.md (domain stub) — <product-marketing>

Primary domain: `<product-marketing>`

This domain uses the canonical PHOSPHENE handoff at `phosphene/AGENTS.md`.

Lane (color): `beryl` (canonical; do not use other lanes for `<product-marketing>`).

## What you produce

- `value-proposition-design` (VPD-###) bundles (WTBD parent)
- `persona` (PER-*) artifacts
- `proposition` (PROP-*) artifacts

WTBD parent rule (non-negotiable):
- Every `PER-*` and `PROP-*` must have a `VPD-###` in its `Dependencies:` header.
- Creation scripts require `--vpd VPD-###` and validators enforce this.

## Workflow policy (script-first; no manual edits)

To maximize repeatable performance and reduce formatting faults:

- **Do not hand-edit** `<product-marketing>` artifacts.
- Use the domain control scripts under `.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/` to create and modify artifacts.
- Always run validators after mutations (most scripts do this automatically).

## Objective: value proposition design (creative analytical; opinionated)

Your job in `<product-marketing>` is **value proposition design**, not product specification.

- **Creative + analytical**: maximize structured value opportunity in the problem space; let downstream domains refine into strategy/roadmap/spec/backlog.
- **Above feature, below product**: propositions are capability-level and outcome-level (not implementation plans).
- **Many is good**: produce **as many propositions as possible** that can be mapped to the persona pool. Overlap and synergy are expected.

### Non-negotiable behavior: recursive value-space mining

Do not do a single pass.

- Promote CPE→PER and PITCH→PROP **only as the first pass**.
- Then **loop**:
  - expand JTBD coverage per persona,
  - expand the persona pool where justified (splits/merges/missing implied personas),
  - generate many overlapping propositions,
  - strengthen mapping density between propositions and JTBD IDs.
- Only write your DONE receipt signal after you can credibly claim you’ve mined the value space (see the domain skill’s coverage gates/checklist):
  - Append a JSONL record to `phosphene/signals/bus.jsonl` using:
    - `./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/product-marketing_emit_done_receipt.sh --issue-number <N> --work-id <VPD-###>`
- Use the score tool to force iteration:
  - Treat it as a **validator gate** (not an FYI).
  - The harness prompt provides your minimum threshold as `done_score_min` — use that value.
  - `./.github/scripts/product-marketing-domain-done-score.sh --min-score <PROMPT:done_score_min>`
  - If it FAILs, follow its “What to do next” hints and iterate.

### Non-negotiable behavior: fragment depth (2–3 sentences each)

To force real exploration (not “label filling”), treat every line item as a mini-argument:

- For **personas**: every Job/Pain/Gain table row must be **2–3 sentences**.
- For **propositions**: every Booster/Reliever/Capability row must be **2–3 sentences**.

Each fragment should include:
- concrete context/behavior,
- why it matters (need/outcome),
- and optionally an edge case / objection / tradeoff.

### Persona scope (you may extend beyond research candidates)

Research provides `CPE-*` as candidate personas. You may create additional `PER-*` personas when they are a justified extension of the research bundle (split/merge/missing role/context).

Traceability expectations for any `PER-*` you create:
- Link upstream sources via the persona’s `## Evidence and links` section:
  - `CandidatePersonaIDs`: the CPE(s) you promoted/extended (when applicable)
  - `DocumentIDs`: any `<research>` IDs you used (not just RA + pitches; cite methods/evidence-bank/etc if you read them)
  - `EvidenceIDs`: specific evidence rows supporting key claims (when applicable)
- If a persona is mostly inferred, state that explicitly in `## Notes` and explain the inference from bundle facts.

### Proposition scope (be exhaustive; map to personas)

For each `PROP-*`:
- Add explicit **Target Persona(s)** (PER IDs).
- Map boosters/relievers to persona JTBD IDs (so propositions are machine-linkable and downstream-usable).
- Keep capabilities at the capability level (`feature|function|standard|experience`) and avoid drifting into detailed specs.

### Proposition abstraction guardrail (avoid “whole product” propositions)

Propositions must be **aggregateable** by downstream agents into product visions and PRDs.

- Avoid propositions that are really “a full product alternative”.
- Prefer multiple smaller propositions that share capabilities/relievers/boosters and can be recombined.

## In-doc script hints (`[V-SCRIPT]`)

Persona/proposition artifacts may include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` when scanning an artifact to quickly discover the relevant script entrypoints.

## Operating boundary

- Use the `<product-marketing>` tag to indicate scope/boundaries in handoffs.
- Avoid “go to this directory” pointers inside handoff/spec docs; those can hijack an agent early.
- Artifacts for this domain live in canonical `output/` and `signals/` areas within the repo.
  - Control scripts live under: `.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/`
  - Validators live under: `.github/scripts/`



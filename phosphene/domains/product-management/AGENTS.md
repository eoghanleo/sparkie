# AGENTS.md (domain stub) — <product-management>

Primary domain: `<product-management>`

This domain uses the canonical PHOSPHENE handoff at `phosphene/AGENTS.md`.

## What you produce

- `product-requirements` artifacts (PRDs: requirements, flows, acceptance criteria, validation plan, evidence/rationale)

Canonical location:
- PRD bundles:
  - `phosphene/domains/product-management/output/prds/PRD-###-<slug>/`
  - `phosphene/domains/product-management/output/prds/PRD-###-<slug>/PRD-###.md` (auto-assembled view; do not hand-edit)

## Workflow intent (tight)

`<product-management>` turns upstream intent into **testable requirements**:

- Inputs (constraints, not suggestions):
  - `<product-strategy>`: bet + scope boundaries + sequencing constraints (ROADMAP-*)
  - `<product-marketing>`: persona + proposition constraints (PER-*, PROP-*)
  - `<research>`: evidence + unknowns (RA bundles, EvidenceIDs)
- Output:
  - A PRD bundle (`PRD-###`) that can be decomposed into FRs with clear acceptance tests.

## Hard rules (to prevent drift)

- **Do not invent** new personas, propositions, or research claims here.
  - If you need a new persona/proposition, route it back to `<product-marketing>`.
  - If you need new evidence, route it back to `<research>`.
- **Keep traceability tight**:
  - Any `RA-*`, `PER-*`, `PROP-*`, `PITCH-*`, `RS-*`, `E-*`, `CPE-*` you reference must exist in the global registry.
  - `Dependencies:` header must include the upstream artifacts you relied on (at minimum: `RA-*` plus any `PER-*`/`PROP-*`/`ROADMAP-*` referenced).
- **Prefer constraints over creativity**:
  - If the proposition says “we must not claim X”, the PRD must not encode X.
  - If research confidence is C1/C2, the SPEC must treat it as hypothesis and propose validation.

## ID hygiene (required)

Before finalizing a PRD for condenser coupling (PR-gated officialization), run:

```bash
./phosphene/phosphene-core/bin/phosphene id validate
./phosphene/phosphene-core/bin/phosphene id where RA-001
```

And run `where <ID>` for any ID you cite in the PRD.

## DONE signal (required for condenser-ready work)

Emit a DONE receipt to the signal bus:

- Append a JSONL line to: `phosphene/signals/bus.jsonl`
- Use the domain emitter (computes correct parents + tamper hash):
  - `./.codex/skills/phosphene/cerulean/product-management/modulator/scripts/product-management_emit_done_receipt.sh --issue-number <N> --work-id <PRD-###>`

Include (minimum):
- inputs (RA/ROADMAP/PER/PROP pointers; EvidenceIDs used)
- outputs (PRD bundle path(s))
- checks run (ID registry validate; domain validators)

## Operating boundary

- Use the `<product-management>` tag to indicate scope/boundaries in handoffs.
- Avoid “go to this directory” pointers inside handoff/spec docs; those can hijack an agent early.
- Artifacts for this domain live in canonical `output/` and `signals/` areas within the repo.
  - Control scripts live under: `.codex/skills/phosphene/cerulean/product-management/modulator/scripts/`
  - Validators live under: `.github/scripts/`

## In-doc script hints (`[V-SCRIPT]`)

Some artifacts include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` to quickly discover relevant control scripts for the nearby section.



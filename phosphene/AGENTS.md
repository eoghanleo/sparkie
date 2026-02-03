## PHOSPHENE — Agent entrypoint (canonical)

This file is the **first thing an agent should read** when operating inside PHOSPHENE.

PHOSPHENE is a lightweight agentic harness built on a simple premise:
- **GitHub Actions is the scheduler**
- **Agents are workers**
- **The repo is shared memory**
- **PR merge is the officialization point**

If you need the deeper model (contracts + workflows), start with:
- Domain outputs under: `phosphene/domains/<domain>/output/`
- Domain control scripts under: `.codex/skills/phosphene/<colour>/<domain>/modulator/scripts/` (script-first; creation + mutation)
- Domain skill (mandatory): `.codex/skills/phosphene/<colour>/<domain>/modulator/SKILL.md`
- Validators (shared): `.github/scripts/`


### How to work (agent checklist)

- **Know your primary domain** (exactly one): `<research>`, `<product-marketing>`, etc.
- Read the domain skill (mandatory): `.codex/skills/phosphene/<colour>/<domain>/modulator/SKILL.md`
- Use **control scripts** (don’t hand-edit script-managed artifacts).
- Run the domain validator(s).
- Write a **DONE receipt** signal as a JSONL record in `phosphene/signals/bus.jsonl` (required for “registration”).
- Work in a branch named after the issue title. **Commit + push that branch to origin** so it is visible in the remote. Do **not** open PRs manually; a human will open the PR, and condensers only approve after checks (PR merge remains the officialization point).

### Repo layout (canonical)

- Domains live under: `phosphene/domains/<domain>/output/`
- Skills live under: `.codex/skills/phosphene/<colour>/<domain>/modulator/`
- Validators live under: `.github/scripts/`
- Config (owner-adjustable): `phosphene/config/<color>.yml`
- Some domains may still include `templates/` as transitional scaffolding.
- Where control scripts exist, **scripts are the single source of truth** for canonical artifact structure (avoid relying on templates at runtime).

### Domains (nine-domain execution model)

Refer to domains using angle brackets:
- `<ideation>` → IDEA
- `<research>` → research-assessment (RA bundles)
- `<product-marketing>` → personas (PER) + propositions (PROP)
- `<product-strategy>` → roadmaps (ROADMAP)
- `<product-management>` → specs (SPEC)
- `<feature-management>` → feature requests (FR)
- `<scrum-management>` → issue mirrors (ISSUE) (optional)
- `<test-management>` → test plans (TP)
- `<retrospective>` → postmortems (PM) + playbooks (PB)

### Lanes (color mapping)

When a workflow/issue/signal includes a `lane`, it must match the canonical domain color:

- `<product-marketing>` is **`beryl`** (canonical)
- `<research>` is **`viridian`** (canonical)

### DONE signals (completion + registration)

PHOSPHENE uses a **DONE signal** as the completion handshake *and* the “register this work” event.

- **Location (required)**: `phosphene/signals/bus.jsonl` (append-only JSONL bus)
- **Naming (required)**: `<WORK_ID>` is the **parent/top-level artifact ID** you completed (examples: `RA-001`, `VPD-001`, `SPEC-012`, `FR-012`).
- **Scope**: keep it small and machine-checkable (JSON with stable fields).
- **Tamper hash (required)**: every JSONL record in `phosphene/signals/bus.jsonl` must include a valid `tamper_hash`.
  - Append signals using the official bus appender (it computes `tamper_hash` last):
    - `./phosphene/phosphene-core/bin/signal_bus.sh append --bus phosphene/signals/bus.jsonl --line '<json>'`
  - Validate the bus:
    - `./phosphene/phosphene-core/bin/signal_bus.sh validate --bus phosphene/signals/bus.jsonl`

Other signals (optional routing add-ons) are also records in the central bus:
- `phosphene/signals/bus.jsonl`

### Identity and uniqueness (central tenet)

PHOSPHENE prefers **long, stable natural keys**.

- Top-level artifacts must have stable IDs (e.g. `ID: PER-0003`, `ID: RA-001`).
- Nested objects achieve global uniqueness by concatenating with parent IDs.

Example:
- `JTBD-PAIN-0001-PER-0003`

### Global ID index (repo-wide)

PHOSPHENE maintains a repo-wide ID index at:
- `phosphene/id_index.tsv`

Build / validate / query:

```bash
./phosphene/phosphene-core/bin/phosphene id build
./phosphene/phosphene-core/bin/phosphene id validate
./phosphene/phosphene-core/bin/phosphene id where PER-0003
```

### In-doc script hints (`[V-SCRIPT]`)

Some artifacts include fenced code blocks that begin with:

```text
[V-SCRIPT]:
<script_name.sh>
```

Search for `[V-SCRIPT]` inside an artifact to discover the correct control scripts quickly.



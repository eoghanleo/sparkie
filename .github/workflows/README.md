# `.github/workflows/` (PHOSPHENE)

GitHub Actions requires workflow YAML files to live **directly** in `.github/workflows/` (no subdirectories).

## Taxonomy (filename is the contract)

### Gantry instruments (no repo writes)

- **Detectors**: `gantry.detector.<domain>.yml`
  - Deterministic ruling corridors: evaluate a ref/branch (PR branches and/or `main`) against a set of **predicates**.
  - Predicates may be:
    - **Static** (baked into the workflow; e.g. run tests, validate schema), or
    - **Runtime-supplied** (e.g. `workflow_dispatch` inputs providing additional predicates/commands).
  - A detector emits a ruling (pass/fail) and **may** trigger follow-on instruments/apparatus, e.g.:
    - Call a **Condenser** to authorize coupling when green.
    - Trigger **rework** by summoning a **Modulator** with defect context, then re-evaluate.
- **Prisms**: `gantry.prism.<domain>.yml`
  - Dispatch/fanout into apparatus runs (summons agents; does not do work itself).
- **Condensers**: `gantry.condenser.<domain>.yml`
  - Coupling approval decisions (approve after checks); no PR creation/merge and **no commits**.
- **Autoscribes**: `gantry.autoscribe.<domain>.yml`
  - Create **flimsies** (GitHub Issues) from explicit triggers (e.g. `workflow_dispatch`, `/flimsie ...`).
  - Must be locked down to **no repo writes** (e.g. `contents: read` only).
  - **Policy**: autoscribes are the **only** instruments allowed to create/update Issues (title/body/state/labels/assignees). Other instruments may comment on Issues.
  - **Canonical issue config**: autoscribes enforce a machine-readable block in the Issue body:
    - `[PHOSPHENE] ... [/PHOSPHENE]`
    - Special case: `INFORMAL` inside the block is valid and means "do not interpret / do not start"
- **Hopper**: `gantry.hopper.global.yml`
  - Interpret **Issues** (the core record) to decide whether to activate a Prism and start work.
  - The hopper is the only instrument that triggers directly on Issue updates; it is comment-only (no Issue mutation beyond comments).
  - The hopper is strict: if it cannot parse the canonical `[PHOSPHENE]` block, it requires regeneration via bus-only autoscribe flow.

### Spooling / safety

- **Spooling**: `spool.tangle.<action>.yml`
- **Safety**: `safety.<action>.yml`

### Library (reusable building blocks)

`lib.*.yml` are reusable `workflow_call` wrappers to keep implementation consistent across instruments/apparatus.

## Editing rules

- Prefer adding new behaviors by extending the **existing** `gantry.<instrument>.<domain>.yml` file for that domain/instrument.
- Only add a new gantry workflow file when introducing a **new** `<instrument>.<domain>` combination.
- Prefer shared logic in `lib.*.yml`.
- Workflow config values live under `phosphene/config/` and are read via `phosphene/phosphene-core/bin/phosphene_config.sh`.


# AGENTS.md (domain stub) — <ideation>

Primary domain: `<ideation>`

This domain uses the canonical PHOSPHENE handoff at `phosphene/AGENTS.md`.

## What you produce

- `idea` artifacts (seed concepts; minimal structure)

## Operating boundary

- Use the `<ideation>` tag to indicate scope/boundaries in handoffs.
- Avoid “go to this directory” pointers inside handoff/spec docs; those can hijack an agent early.
- Artifacts for this domain live in canonical `output/` and `signals/` areas within the repo.
  - Control scripts live under: `.codex/skills/phosphene/viridian/ideation/modulator/scripts/`
  - Validators live under: `.github/scripts/`

## Recommended loop

- Create the IDEA artifact, then run `ideation_storm_table_bootstrap.sh`.
- Use `provide_next_storm_prompt.sh` → `ideation_storm_set_description.sh` until complete.
- Validate + done-score, iterate until PASS, then emit DONE receipt.

## In-doc script hints (`[V-SCRIPT]`)

Some artifacts include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` to quickly discover relevant control scripts for the nearby section.



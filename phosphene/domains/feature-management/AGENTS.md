# AGENTS.md (domain stub) — <feature-management>

Primary domain: `<feature-management>`

This domain uses the canonical PHOSPHENE handoff at `phosphene/AGENTS.md`.

## What you produce

- `feature-request` artifacts (FR dossiers; lifecycle scripts; validation)

## Operating boundary

- Use the `<feature-management>` tag to indicate scope/boundaries in handoffs.
- Avoid “go to this directory” pointers inside handoff/spec docs; those can hijack an agent early.
- Artifacts for this domain live in canonical `output/` and `signals/` areas within the repo.
  - Control scripts live under: `.codex/skills/phosphene/cerulean/feature-management/modulator/scripts/`
  - Validators live under: `.github/scripts/`

## In-doc script hints (`[V-SCRIPT]`)

Some artifacts include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` to quickly discover relevant control scripts for the nearby section.



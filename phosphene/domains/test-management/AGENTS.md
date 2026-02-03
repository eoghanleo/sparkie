# AGENTS.md (domain stub) — <test-management>

Primary domain: `<test-management>`

This domain uses the canonical PHOSPHENE handoff at `phosphene/AGENTS.md`.

## What you produce

- `test-plan` artifacts

## Operating boundary

- Use the `<test-management>` tag to indicate scope/boundaries in handoffs.
- Avoid “go to this directory” pointers inside handoff/spec docs; those can hijack an agent early.
- Artifacts for this domain live in canonical `output/` and `signals/` areas within the repo.
  - Control scripts live under: `.codex/skills/phosphene/cadmium/test-management/modulator/scripts/`
  - Validators live under: `.github/scripts/`

## In-doc script hints (`[V-SCRIPT]`)

Some artifacts include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` to quickly discover relevant control scripts for the nearby section.



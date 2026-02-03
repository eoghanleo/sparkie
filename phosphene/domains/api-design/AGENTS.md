# AGENTS.md (domain stub) — <api-design>

Primary domain: `<api-design>`

This domain uses the canonical PHOSPHENE handoff at `phosphene/AGENTS.md`.

## What you produce

- `api-spec` artifacts (endpoints/events, payloads, errors, auth, backwards-compat notes)

## Operating boundary

- Use the `<api-design>` tag to indicate scope/boundaries in handoffs.
- Avoid “go to this directory” pointers inside handoff/spec docs; those can hijack an agent early.
- Artifacts for this domain live in canonical `output/` and `signals/` areas within the repo.
  - Control scripts live under: `.codex/skills/phosphene/amaranth/api-design/modulator/scripts/`
  - Validators live under: `.github/scripts/` (stub: not yet implemented for this domain)

## In-doc script hints (`[V-SCRIPT]`)

Some artifacts include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` to quickly discover relevant control scripts for the nearby section.


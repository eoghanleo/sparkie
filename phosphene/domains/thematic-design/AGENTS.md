# AGENTS.md (domain stub) — <thematic-design>

Primary domain: `<thematic-design>`

This domain uses the canonical PHOSPHENE handoff at `phosphene/AGENTS.md`.

## What you produce

- `theme-spec` artifacts (design tokens, typography/color rules, component theming constraints)

## Operating boundary

- Use the `<thematic-design>` tag to indicate scope/boundaries in handoffs.
- Avoid “go to this directory” pointers inside handoff/spec docs; those can hijack an agent early.
- Artifacts for this domain live in canonical `output/` and `signals/` areas within the repo.
  - Control scripts live under: `.codex/skills/phosphene/amaranth/thematic-design/modulator/scripts/`
  - Validators live under: `.github/scripts/` (stub: not yet implemented for this domain)

## In-doc script hints (`[V-SCRIPT]`)

Some artifacts include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` to quickly discover relevant control scripts for the nearby section.


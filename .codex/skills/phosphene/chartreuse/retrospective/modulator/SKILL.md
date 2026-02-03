---
name: retrospective
description: Produce <retrospective> artifacts (postmortems, playbooks) capturing lessons, root causes, and guardrails for future work.
metadata:
  short-description: Postmortems + playbooks
---

## Domain

Primary domain: `<retrospective>`

## Status

TODO (not in development). Do not run this domain in live flows.

## What you produce

- Postmortems: `phosphene/domains/retrospective/output/postmortems/PM-*.md`
- Playbooks: `phosphene/domains/retrospective/output/playbooks/PB-*.md`

## How to work

- Start from merged PRs, incident reports, and outcomes.
- Create artifacts directly under:
  - `phosphene/domains/retrospective/output/postmortems/`
  - `phosphene/domains/retrospective/output/playbooks/`
- Keep learnings actionable: what changed, what to keep, what to automate/validate next time.

## In-doc script hints (`[V-SCRIPT]`)

Some templates/artifacts include fenced code blocks that begin with `[V-SCRIPT]:`.
Search for `[V-SCRIPT]` when scanning an artifact to discover relevant control scripts for that section.

## Scripts (entrypoints and purpose)

No domain scripts yet.

## DONE signal

Not active. DONE receipt scripts are not implemented for this domain yet.

Include (minimum) listing:

- inputs (PRs/issues/notes)
- outputs (PM/PB docs)
- checks run (format/header compliance)

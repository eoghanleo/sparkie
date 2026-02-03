---
name: api-design
description: Produce <api-design> API contracts (endpoints/events/payloads/errors) as applied build work. Stub-only domain scaffold.
metadata:
  short-description: API specs (stub)
---

## Domain

Primary domain: `<api-design>`

## Status

Stub scaffold only (no instrument set yet).

## What you produce

- `api-spec` artifacts under `phosphene/domains/api-design/output/`

## How to work

- Treat APIs as contracts: request/response shapes, error taxonomy, auth, versioning/backwards-compat story.
- Include edge cases and invariants (idempotency, pagination, rate limits) if relevant.
- Until control scripts exist for this domain, **manual edits are allowed** for artifacts you add under the domain output folder.

## Validation (stub)

- Validators and done-score scripts are not yet implemented for this domain.


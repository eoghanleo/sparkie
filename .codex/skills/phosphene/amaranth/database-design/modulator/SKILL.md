---
name: database-design
description: Produce <database-design> schema and migration specs as applied build work. Stub-only domain scaffold.
metadata:
  short-description: DB specs (stub)
---

## Domain

Primary domain: `<database-design>`

## Status

Stub scaffold only (no instrument set yet).

## What you produce

- `db-spec` artifacts under `phosphene/domains/database-design/output/`

## How to work

- Keep outputs implementable: tables/fields, constraints, indexes, migration order, expected query patterns.
- Document backwards-compat considerations and roll-forward/roll-back strategy.
- Until control scripts exist for this domain, **manual edits are allowed** for artifacts you add under the domain output folder.

## Validation (stub)

- Validators and done-score scripts are not yet implemented for this domain.


---
name: infrastructure-operations
description: Produce <infrastructure-operations> deployment/runtime/runbook specs as applied build work. Stub-only domain scaffold.
metadata:
  short-description: Infra ops (stub)
---

## Domain

Primary domain: `<infrastructure-operations>`

## Status

Stub scaffold only (no instrument set yet).

## What you produce

- `infra-spec` artifacts under `phosphene/domains/infrastructure-operations/output/`

## How to work

- Prefer explicitness: environment variables/config surfaces, deployment topology, secrets boundaries, operational runbooks.
- Write to real constraints (RPO/RTO, cost, compliance) where known.
- Until control scripts exist for this domain, **manual edits are allowed** for artifacts you add under the domain output folder.

## Validation (stub)

- Validators and done-score scripts are not yet implemented for this domain.


# SPARK snapshots (ideation inputs)

SPARK files are **signal-local input snapshots** created by the ideation hopper.
They preserve the exact issue prompt that triggered `<ideation>` work and provide a
deterministic input corpus for done-score anchoring.

## Location

- `phosphene/signals/sparks/SPARK-000123.md`

## Header schema (v1)

The header is a simple key:value block; the first blank line ends the header.

- `ID: SPARK-000123`
- `IssueNumber: 123`
- `WorkID: IDEA-0001`
- `Lane: viridian`
- `UpstreamSignalID: sha256:...` (if available)
- `InputWorkIDs: RA-001,VPD-002` (optional; may be empty)
- `ManifoldProbeCount: 10` (ideation storm-table size)
- `SeedSHA256: <hex>` (seed for deterministic probe selection; optional sha256: prefix accepted)
- `CreatedUTC: 2026-02-01T00:00:00Z`

## Body schema (v1)

- `## Issue snapshot`
- literal issue body copied verbatim

## Input overrides in issues (v1)

Issues may specify additional repo inputs (work IDs) in a separate block
outside the strict `[PHOSPHENE]` block:

```text
[PHOSPHENE_INPUTS]
- RA-001
- VPD-002
[/PHOSPHENE_INPUTS]
```

The hopper parses this list and stores it as `InputWorkIDs:` in the SPARK header.

## Manifold probes in issues (v2)

For ideation storm-table runs, the issue `[PHOSPHENE]` block includes:
- `manifold_probe_count` (default 10)
- `seed_sha256` (SHA-256 of PHOSPHENE block values)

The ideation hopper persists these into the SPARK header as:
- `ManifoldProbeCount: 10`
- `SeedSHA256: sha256:...`

These values are used by:
- storm table bootstrap + deterministic probe selection
- `validate_idea.sh` and `ideation-domain-done-score.sh` (row-count gates)


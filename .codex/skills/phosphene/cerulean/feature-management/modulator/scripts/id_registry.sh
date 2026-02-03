#!/usr/bin/env bash
set -euo pipefail

# Domain-local wrapper for the global PHOSPHENE ID registry.
# Use this for discoverability, but note the registry itself is repo-wide.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

exec "$ROOT/phosphene-core/bin/phosphene" id "$@"


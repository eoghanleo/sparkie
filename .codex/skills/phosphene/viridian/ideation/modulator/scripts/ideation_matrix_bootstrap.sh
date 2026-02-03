#!/usr/bin/env bash
set -euo pipefail

# ideation_matrix_bootstrap.sh (deprecated)
# This script now delegates to ideation_storm_table_bootstrap.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"

echo "Deprecated: use ideation_storm_table_bootstrap.sh instead." >&2
"$SCRIPT_DIR/ideation_storm_table_bootstrap.sh" "$@"


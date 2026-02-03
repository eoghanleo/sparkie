#!/usr/bin/env bash
set -euo pipefail

# Back-compat wrapper.
#
# The PHOSPHENE ID registry is global and lives in:
#   ./phosphene/phosphene-core/bin/id_registry.sh
#   ./phosphene/phosphene-core/bin/phosphene id ...
#
# This wrapper exists so older docs/scripts keep working.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

ROOT="$(phosphene_find_project_root)"
exec "$ROOT/phosphene/phosphene-core/bin/phosphene" id "$@"


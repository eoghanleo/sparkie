#!/usr/bin/env bash
set -euo pipefail

# Domain-local wrapper for the product-marketing persona validator.
# The canonical implementation lives under .github/scripts/.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_repo_root() {
  local d="$SCRIPT_DIR"
  while true; do
    if [[ -x "$d/phosphene/phosphene-core/bin/phosphene" ]]; then
      echo "$d"
      return 0
    fi
    [[ "$d" == "/" ]] && return 1
    d="$(cd "$d/.." && pwd)"
  done
}

ROOT="$(find_repo_root)" || { echo "Error: could not locate PHOSPHENE repo root from: $SCRIPT_DIR" >&2; exit 2; }

exec "$ROOT/.github/scripts/validate_persona.sh" "$@"


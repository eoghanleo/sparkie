#!/usr/bin/env bash
#
# Product Roadmap Validation Script (bash-only)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./.github/scripts/validate_product_roadmap.sh [--all] [FILE|DIRECTORY]
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)" || fail "Not in a PHOSPHENE project."
DEFAULT_DIR="$ROOT/phosphene/domains/product-strategy/output/product-roadmaps"

ALL=0
TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) ALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) TARGET="$1"; shift ;;
  esac
done

validate_file() {
  local file="$1"
  [[ -f "$file" ]] || return 1

  local id
  id="$(grep -E '^ID:[[:space:]]*ROADMAP-[0-9]{3}[[:space:]]*$' "$file" | head -n 1 | sed -E 's/^ID:[[:space:]]*//; s/[[:space:]]*$//')"
  [[ -n "${id:-}" ]] || fail "Missing or invalid ID header in $file"

  for h in "Title" "Status" "Updated" "Dependencies"; do
    if ! grep -q "^${h}: " "$file"; then
      fail "Missing ${h} header in $file"
    fi
  done

  local base
  base="$(basename "$file")"
  if ! [[ "$base" =~ ^${id} ]]; then
    fail "Filename does not start with ID ($id): $base"
  fi

  for h in "## Bet framing" "## Trajectory lattice (2–4 trajectories)" "## Decision triggers / gates" "## Constraints" "## Dependencies"; do
    if ! grep -Fqx "$h" "$file"; then
      fail "Missing required heading (${h}) in $file"
    fi
  done

  local traj_count
  traj_count="$(grep -cE '^### Trajectory' "$file" || true)"
  if [[ "$traj_count" -lt 2 || "$traj_count" -gt 4 ]]; then
    fail "Trajectory lattice must include 2–4 trajectories (found ${traj_count}) in $file"
  fi
}

files=()
if [[ "$ALL" -eq 1 ]]; then
  [[ -d "$DEFAULT_DIR" ]] || fail "Missing product-strategy directory: $DEFAULT_DIR"
  while IFS= read -r f; do files+=("$f"); done < <(find "$DEFAULT_DIR" -type f -name "ROADMAP-*.md" | sort)
elif [[ -n "${TARGET:-}" ]]; then
  if [[ -f "$TARGET" ]]; then
    files=("$TARGET")
  elif [[ -d "$TARGET" ]]; then
    while IFS= read -r f; do files+=("$f"); done < <(find "$TARGET" -type f -name "ROADMAP-*.md" | sort)
  else
    fail "Target not found: $TARGET"
  fi
else
  [[ -d "$DEFAULT_DIR" ]] || fail "Missing product-strategy directory: $DEFAULT_DIR"
  while IFS= read -r f; do files+=("$f"); done < <(find "$DEFAULT_DIR" -type f -name "ROADMAP-*.md" | sort)
fi

if [[ "${#files[@]}" -eq 0 ]]; then
  fail "No ROADMAP files found to validate."
fi

for f in "${files[@]}"; do
  validate_file "$f"
done

echo "OK: validated ${#files[@]} roadmap file(s)"

#!/usr/bin/env bash
#
# Test Plan Validation Script (bash-only)
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
  ./.github/scripts/validate_test_plan.sh [--all] [FILE|DIRECTORY]
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)" || fail "Not in a PHOSPHENE project."
DEFAULT_DIR="$ROOT/phosphene/domains/test-management/output/test-plans"

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
  id="$(grep -E '^ID:[[:space:]]*TP-[0-9]{3}[[:space:]]*$' "$file" | head -n 1 | sed -E 's/^ID:[[:space:]]*//; s/[[:space:]]*$//')"
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

  for h in "## Scope" "## Test matrix" "## Acceptance scenarios" "## Environment"; do
    if ! grep -qE "^${h}$" "$file"; then
      fail "Missing required heading (${h}) in $file"
    fi
  done
}

files=()
if [[ "$ALL" -eq 1 ]]; then
  [[ -d "$DEFAULT_DIR" ]] || fail "Missing test-management directory: $DEFAULT_DIR"
  while IFS= read -r f; do files+=("$f"); done < <(find "$DEFAULT_DIR" -type f -name "TP-*.md" | sort)
elif [[ -n "${TARGET:-}" ]]; then
  if [[ -f "$TARGET" ]]; then
    files=("$TARGET")
  elif [[ -d "$TARGET" ]]; then
    while IFS= read -r f; do files+=("$f"); done < <(find "$TARGET" -type f -name "TP-*.md" | sort)
  else
    fail "Target not found: $TARGET"
  fi
else
  [[ -d "$DEFAULT_DIR" ]] || fail "Missing test-management directory: $DEFAULT_DIR"
  while IFS= read -r f; do files+=("$f"); done < <(find "$DEFAULT_DIR" -type f -name "TP-*.md" | sort)
fi

if [[ "${#files[@]}" -eq 0 ]]; then
  fail "No TP files found to validate."
fi

for f in "${files[@]}"; do
  validate_file "$f"
done

echo "OK: validated ${#files[@]} test plan file(s)"

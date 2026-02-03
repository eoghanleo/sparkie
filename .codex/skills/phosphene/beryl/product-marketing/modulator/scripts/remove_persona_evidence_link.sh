#!/usr/bin/env bash
set -euo pipefail

# remove_persona_evidence_link.sh
# Removes a supporting ID from the Persona "## Evidence and links" section.
#
# Buckets follow the same rules as add_persona_evidence_link.sh.
#
# Usage:
#   ./phosphene/domains/product-marketing/scripts/remove_persona_evidence_link.sh --persona <file> --id E-0001

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/remove_persona_evidence_link.sh --persona <file> --id <stable-id>
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)"

PERSONA=""
SID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --persona) PERSONA="${2:-}"; shift 2 ;;
    --id) SID="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$PERSONA" ]] || { echo "Error: --persona is required" >&2; usage; exit 2; }
[[ -n "$SID" ]] || { echo "Error: --id is required" >&2; usage; exit 2; }

if [[ "$PERSONA" != /* ]]; then PERSONA="$ROOT/$PERSONA"; fi
[[ -f "$PERSONA" ]] || fail "Not a file: $PERSONA"

TMP_OUT="$(mktemp)"
awk -v sid="$SID" '
  BEGIN { in_ev=0; removed=0; }
  $0 == "## Evidence and links" { in_ev=1; print; next }
  in_ev && $0 ~ /^## / { in_ev=0 }
  in_ev {
    if ($0 ~ ("^-+[[:space:]]+" sid "[[:space:]]*$")) { removed++; next }
  }
  { print }
  END {
    if (removed == 0) {
      # no-op is ok
    }
  }
' "$PERSONA" > "$TMP_OUT"

mv "$TMP_OUT" "$PERSONA"

"$ROOT/.github/scripts/validate_persona.sh" "$PERSONA" >/dev/null
echo "OK: validated $PERSONA"


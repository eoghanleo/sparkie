#!/usr/bin/env bash
set -euo pipefail

# remove_persona_related_link.sh
# Removes a link under "## Evidence and links" → "### Links".
#
# Usage:
#   ./phosphene/domains/product-marketing/scripts/remove_persona_related_link.sh --persona <file> --link "<url-or-path>"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/remove_persona_related_link.sh --persona <file> --link "<url-or-path>"
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)"

PERSONA=""
LINK=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --persona) PERSONA="${2:-}"; shift 2 ;;
    --link) LINK="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$PERSONA" ]] || { echo "Error: --persona is required" >&2; usage; exit 2; }
[[ -n "$LINK" ]] || { echo "Error: --link is required" >&2; usage; exit 2; }

if [[ "$PERSONA" != /* ]]; then PERSONA="$ROOT/$PERSONA"; fi
[[ -f "$PERSONA" ]] || fail "Not a file: $PERSONA"

LINK_CLEAN="$(printf "%s" "$LINK" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
[[ -n "$LINK_CLEAN" ]] || fail "empty link"

TMP_OUT="$(mktemp)"
awk -v link="$LINK_CLEAN" '
  BEGIN { in_ev=0; }
  $0 == "## Evidence and links" { in_ev=1; print; next }
  in_ev && $0 ~ /^## / { in_ev=0 }
  in_ev && $0 ~ /^-[[:space:]]+/ {
    x=$0
    sub(/^-+[[:space:]]+/, "", x)
    gsub(/[[:space:]]+$/, "", x)
    if (x == link) next
  }
  { print }
' "$PERSONA" > "$TMP_OUT"

mv "$TMP_OUT" "$PERSONA"

"$ROOT/.github/scripts/validate_persona.sh" "$PERSONA" >/dev/null
echo "OK: validated $PERSONA"


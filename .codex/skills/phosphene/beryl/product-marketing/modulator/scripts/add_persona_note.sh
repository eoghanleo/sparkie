#!/usr/bin/env bash
set -euo pipefail

# add_persona_note.sh
# Appends a note entry under "## Notes" in a Persona (PER-*) file.
#
# Usage:
#   ./phosphene/domains/product-marketing/scripts/add_persona_note.sh --persona <file> --note "..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/add_persona_note.sh --persona <file> --note "..."
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)"

PERSONA=""
NOTE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --persona) PERSONA="${2:-}"; shift 2 ;;
    --note) NOTE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$PERSONA" ]] || { echo "Error: --persona is required" >&2; usage; exit 2; }
[[ -n "$NOTE" ]] || { echo "Error: --note is required" >&2; usage; exit 2; }

if [[ "$PERSONA" != /* ]]; then PERSONA="$ROOT/$PERSONA"; fi
[[ -f "$PERSONA" ]] || fail "Not a file: $PERSONA"

NOTE_CLEAN="$(printf "%s" "$NOTE" | sed -E 's/[[:space:]]+$//')"
[[ -n "$NOTE_CLEAN" ]] || fail "empty note"

ts="$(date -u +%FT%TZ)"
entry="- ${ts}: ${NOTE_CLEAN}"

TMP_OUT="$(mktemp)"
awk -v entry="$entry" '
  BEGIN { in_notes=0; found=0; inserted=0; last_blank=1; }
  {
    if ($0 == "## Notes") { found=1; in_notes=1; print; next }
    if (in_notes && $0 ~ /^## /) {
      if (last_blank == 0) print ""
      print entry
      inserted=1
      in_notes=0
      print
      next
    }
    if (in_notes) {
      if ($0 == "") last_blank=1; else last_blank=0
    }
    print
  }
  END {
    if (found && inserted == 0) {
      if (last_blank == 0) print ""
      print entry
    }
    if (!found) exit 1
  }
' "$PERSONA" > "$TMP_OUT" || { rm -f "$TMP_OUT" || true; fail "$(basename "$PERSONA"): missing '## Notes'"; }

mv "$TMP_OUT" "$PERSONA"

"$ROOT/.github/scripts/validate_persona.sh" "$PERSONA" >/dev/null
echo "OK: validated $PERSONA"


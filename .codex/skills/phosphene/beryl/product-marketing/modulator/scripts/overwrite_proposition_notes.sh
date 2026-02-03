#!/usr/bin/env bash
set -euo pipefail

# overwrite_proposition_notes.sh
# Replaces the entire "## Notes" section content in a Proposition (PROP-*) file.
#
# Usage:
#   ./phosphene/domains/product-marketing/scripts/overwrite_proposition_notes.sh --proposition <file> --notes-file <md_file>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/overwrite_proposition_notes.sh --proposition <file> --notes-file <md_file>
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)"

PROP=""
NOTES_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proposition) PROP="${2:-}"; shift 2 ;;
    --notes-file) NOTES_FILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$PROP" ]] || { echo "Error: --proposition is required" >&2; usage; exit 2; }
[[ -n "$NOTES_FILE" ]] || { echo "Error: --notes-file is required" >&2; usage; exit 2; }

if [[ "$PROP" != /* ]]; then PROP="$ROOT/$PROP"; fi
if [[ "$NOTES_FILE" != /* ]]; then NOTES_FILE="$ROOT/$NOTES_FILE"; fi
[[ -f "$PROP" ]] || fail "Not a file: $PROP"
[[ -f "$NOTES_FILE" ]] || fail "Not a file: $NOTES_FILE"

# Balanced fence check (bash-only).
fences="$(grep -c '^```' "$NOTES_FILE" || true)"
if [[ $((fences % 2)) -ne 0 ]]; then
  fail "Notes content contains an unbalanced code fence count"
fi

TMP_OUT="$(mktemp)"
if ! awk -v notes_file="$NOTES_FILE" '
  function print_file(path,   line) {
    while ((getline line < path) > 0) print line;
    close(path)
  }
  BEGIN { replacing=0; found=0; }
  {
    if ($0 == "## Notes") {
      found=1
      print $0
      print ""
      print "```text"
      print "[V-SCRIPT]:"
      print "add_proposition_note.sh"
      print "overwrite_proposition_notes.sh"
      print "```"
      print ""
      print_file(notes_file)
      print ""
      replacing=1
      next
    }
    if (replacing) {
      if ($0 ~ /^## /) { replacing=0 } else { next }
    }
    print
  }
  END { if (!found) exit 1; }
' "$PROP" > "$TMP_OUT"; then
  rm -f "$TMP_OUT" || true
  fail "$(basename "$PROP"): missing '## Notes'"
fi

if ! "$ROOT/.github/scripts/validate_proposition.sh" --strict "$TMP_OUT" >/dev/null; then
  val_rc=$?
  rm -f "$TMP_OUT"
  exit $val_rc
fi

mv "$TMP_OUT" "$PROP"
set -e

echo "OK: strict-validated $PROP"


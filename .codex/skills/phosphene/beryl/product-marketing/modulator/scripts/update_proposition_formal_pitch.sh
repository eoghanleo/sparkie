#!/usr/bin/env bash
set -euo pipefail

# update_proposition_formal_pitch.sh
# Replaces the "## Formal Pitch" section content in a Proposition (PROP-*) file.
#
# Usage:
#   ./phosphene/domains/product-marketing/scripts/update_proposition_formal_pitch.sh --proposition <file> --pitch-file <md_file>
#   ./phosphene/domains/product-marketing/scripts/update_proposition_formal_pitch.sh --proposition <file> --pitch "<single line>"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/update_proposition_formal_pitch.sh --proposition <file> --pitch-file <md_file>
  ./phosphene/domains/product-marketing/scripts/update_proposition_formal_pitch.sh --proposition <file> --pitch "<single line>"
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)"

PROP=""
PITCH_FILE=""
PITCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proposition) PROP="${2:-}"; shift 2 ;;
    --pitch-file) PITCH_FILE="${2:-}"; shift 2 ;;
    --pitch) PITCH="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$PROP" ]] || { echo "Error: --proposition is required" >&2; usage; exit 2; }
if [[ "$PROP" != /* ]]; then PROP="$ROOT/$PROP"; fi
[[ -f "$PROP" ]] || fail "Not a file: $PROP"

CONTENT=""
if [[ -n "$PITCH_FILE" ]]; then
  if [[ "$PITCH_FILE" != /* ]]; then PITCH_FILE="$ROOT/$PITCH_FILE"; fi
  [[ -f "$PITCH_FILE" ]] || fail "Not a file: $PITCH_FILE"
  CONTENT_FILE="$PITCH_FILE"
else
  [[ -n "$PITCH" ]] || fail "Provide --pitch-file or --pitch"
  CONTENT_FILE="$(mktemp)"
  printf "%s\n" "$PITCH" > "$CONTENT_FILE"
fi

TMP_OUT="$(mktemp)"
# Balanced fence check (bash-only).
fences="$(grep -c '^```' "$CONTENT_FILE" || true)"
if [[ $((fences % 2)) -ne 0 ]]; then
  rm -f "$TMP_OUT" || true
  [[ "${CONTENT_FILE}" == "${PITCH_FILE:-}" ]] || rm -f "$CONTENT_FILE" || true
  fail "Formal pitch content contains an unbalanced code fence count"
fi

if ! awk -v content_file="$CONTENT_FILE" '
  function print_file(path,   line) {
    while ((getline line < path) > 0) print line;
    close(path)
  }
  BEGIN { replacing=0; found=0; }
  {
    if ($0 == "## Formal Pitch") {
      found=1
      print $0
      print ""
      print "```text"
      print "[V-SCRIPT]:"
      print "update_proposition_formal_pitch.sh"
      print "```"
      print ""
      print_file(content_file)
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
  [[ "${CONTENT_FILE}" == "${PITCH_FILE:-}" ]] || rm -f "$CONTENT_FILE" || true
  fail "$(basename "$PROP"): missing '## Formal Pitch'"
fi

[[ "${CONTENT_FILE}" == "${PITCH_FILE:-}" ]] || rm -f "$CONTENT_FILE" || true

if ! "$ROOT/.github/scripts/validate_proposition.sh" --strict "$TMP_OUT" >/dev/null; then
  val_rc=$?
  rm -f "$TMP_OUT"
  exit $val_rc
fi

mv "$TMP_OUT" "$PROP"
set -e

echo "OK: strict-validated $PROP"


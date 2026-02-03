#!/usr/bin/env bash
set -euo pipefail

# update_persona_summary.sh
# Replaces the "## Snapshot summary" section content in a Persona (PER-*) file.
#
# Usage:
#   ./phosphene/domains/product-marketing/scripts/update_persona_summary.sh --persona <file> --summary-file <md_file>
#   ./phosphene/domains/product-marketing/scripts/update_persona_summary.sh --persona <file> --summary "<single line>"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/update_persona_summary.sh --persona <file> --summary-file <md_file>
  ./phosphene/domains/product-marketing/scripts/update_persona_summary.sh --persona <file> --summary "<single line>"
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)"

PERSONA=""
SUMMARY_FILE=""
SUMMARY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --persona) PERSONA="${2:-}"; shift 2 ;;
    --summary-file) SUMMARY_FILE="${2:-}"; shift 2 ;;
    --summary) SUMMARY="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$PERSONA" ]] || { echo "Error: --persona is required" >&2; usage; exit 2; }
if [[ "$PERSONA" != /* ]]; then PERSONA="$ROOT/$PERSONA"; fi
[[ -f "$PERSONA" ]] || fail "Not a file: $PERSONA"

CONTENT=""
if [[ -n "$SUMMARY_FILE" ]]; then
  if [[ "$SUMMARY_FILE" != /* ]]; then SUMMARY_FILE="$ROOT/$SUMMARY_FILE"; fi
  [[ -f "$SUMMARY_FILE" ]] || fail "Not a file: $SUMMARY_FILE"
  CONTENT_FILE="$SUMMARY_FILE"
else
  [[ -n "$SUMMARY" ]] || fail "Provide --summary-file or --summary"
  CONTENT_FILE="$(mktemp)"
  printf "%s\n" "$SUMMARY" > "$CONTENT_FILE"
fi

TMP_OUT="$(mktemp)"

# Validate balanced fences in new content (bash-only).
fences="$(grep -c '^```' "$CONTENT_FILE" || true)"
if [[ $((fences % 2)) -ne 0 ]]; then
  rm -f "$TMP_OUT" || true
  [[ "${CONTENT_FILE}" == "${SUMMARY_FILE:-}" ]] || rm -f "$CONTENT_FILE" || true
  fail "Summary content contains an unbalanced code fence count"
fi

awk -v content_file="$CONTENT_FILE" '
  function print_file(path,   line) {
    while ((getline line < path) > 0) print line;
    close(path)
  }
  BEGIN { replacing=0; found=0; }
  {
    if ($0 == "## Snapshot summary") {
      found=1
      print $0
      print ""
      print "```text"
      print "[V-SCRIPT]:"
      print "update_persona_summary.sh"
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
' "$PERSONA" > "$TMP_OUT" || {
  rm -f "$TMP_OUT" || true
  [[ "${CONTENT_FILE}" == "${SUMMARY_FILE:-}" ]] || rm -f "$CONTENT_FILE" || true
  fail "$(basename "$PERSONA"): missing '## Snapshot summary'"
}

[[ "${CONTENT_FILE}" == "${SUMMARY_FILE:-}" ]] || rm -f "$CONTENT_FILE" || true

if ! "$ROOT/.github/scripts/validate_persona.sh" --strict "$TMP_OUT" >/dev/null; then
  val_rc=$?
  rm -f "$TMP_OUT"
  exit $val_rc
fi

mv "$TMP_OUT" "$PERSONA"
set -e

echo "OK: strict-validated $PERSONA"


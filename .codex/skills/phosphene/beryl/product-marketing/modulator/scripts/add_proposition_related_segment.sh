#!/usr/bin/env bash
set -euo pipefail

# add_proposition_related_segment.sh
# Adds a SEG-#### entry under "## Related Segment(s)" in a proposition.
#
# Usage:
#   ./phosphene/domains/product-marketing/scripts/add_proposition_related_segment.sh --proposition <file> --segment SEG-0001

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/add_proposition_related_segment.sh --proposition <file> --segment SEG-0001
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)"

PROP=""
SEG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proposition) PROP="${2:-}"; shift 2 ;;
    --segment) SEG="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$PROP" ]] || { echo "Error: --proposition is required" >&2; usage; exit 2; }
[[ -n "$SEG" ]] || { echo "Error: --segment is required" >&2; usage; exit 2; }
[[ "$SEG" =~ ^SEG-[0-9]{4}$ ]] || fail "--segment must look like SEG-0001"

if [[ "$PROP" != /* ]]; then PROP="$ROOT/$PROP"; fi
[[ -f "$PROP" ]] || fail "Not a file: $PROP"

TMP_OUT="$(mktemp)"
if ! awk -v seg="$SEG" '
  BEGIN { in_sec=0; found=0; has_item=0; }
  {
    if ($0 == "## Related Segment(s)") { in_sec=1; found=1; has_item=0; print; next }
    if (in_sec && $0 ~ /^## /) {
      if (!has_item) { print "- " seg; print "" }
      in_sec=0
      print
      next
    }
    if (in_sec && $0 ~ ("^-+[[:space:]]+" seg "[[:space:]]*$")) has_item=1
    print
  }
  END {
    if (!found) exit 2
    if (in_sec && !has_item) { print "- " seg; print "" }
  }
' "$PROP" > "$TMP_OUT"; then
  rc=$?
  rm -f "$TMP_OUT" || true
  [[ $rc -eq 2 ]] && fail "$(basename "$PROP"): missing '## Related Segment(s)'"
  exit $rc
fi

if ! "$ROOT/.github/scripts/validate_proposition.sh" "$TMP_OUT" >/dev/null; then
  rc=$?
  rm -f "$TMP_OUT" || true
  exit $rc
fi

mv "$TMP_OUT" "$PROP"
echo "OK: validated $PROP"


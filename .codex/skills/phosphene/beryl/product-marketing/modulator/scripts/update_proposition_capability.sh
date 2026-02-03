#!/usr/bin/env bash
set -euo pipefail

# update_proposition_capability.sh
# Updates an existing Capability row in the "## Capabilities" table.
#
# Usage:
#   ./phosphene/domains/product-marketing/scripts/update_proposition_capability.sh --proposition <file> --capability-id CAP-0001-PROP-0001 [--type feature|function|standard|experience] [--capability "..."]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/update_proposition_capability.sh --proposition <file> --capability-id CAP-0001-PROP-0001 [--type feature|function|standard|experience] [--capability "..."]
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)"

PROP=""
CID=""
CTYPE=""
CAP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proposition) PROP="${2:-}"; shift 2 ;;
    --capability-id) CID="${2:-}"; shift 2 ;;
    --type) CTYPE="${2:-}"; shift 2 ;;
    --capability) CAP="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$PROP" ]] || { echo "Error: --proposition is required" >&2; usage; exit 2; }
[[ -n "$CID" ]] || { echo "Error: --capability-id is required" >&2; usage; exit 2; }
[[ -n "$CTYPE" || -n "$CAP" ]] || fail "Provide at least one of --type or --capability"

if [[ -n "$CTYPE" ]]; then
  case "$CTYPE" in
    feature|function|standard|experience) ;;
    *) fail "--type must be one of feature|function|standard|experience" ;;
  esac
fi
if [[ -n "$CAP" && "$CAP" == *"|"* ]]; then fail "--capability must not contain '|'"; fi

if [[ "$PROP" != /* ]]; then PROP="$ROOT/$PROP"; fi
[[ -f "$PROP" ]] || fail "Not a file: $PROP"

prop_id="$(grep -E '^ID:[[:space:]]*PROP-[0-9]{4}[[:space:]]*$' "$PROP" | head -n 1 | sed -E 's/^ID:[[:space:]]*//; s/[[:space:]]*$//')"
[[ -n "${prop_id:-}" ]] || fail "$(basename "$PROP"): missing/invalid 'ID: PROP-####'"

[[ "$CID" =~ ^CAP-[0-9]{4}-${prop_id}$ ]] || fail "capability-id must match proposition ID suffix (${prop_id}): ${CID}"

TMP_OUT="$(mktemp)"
if ! awk -v section="## Capabilities" -v cid="$CID" -v new_type="$CTYPE" -v new_cap="$CAP" '
  function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
  BEGIN { in_section=0; found_section=0; updated=0; }
  {
    if ($0 == section) { in_section=1; found_section=1; print; next }
    if (in_section && $0 ~ /^## /) { in_section=0 }

    if (in_section && $0 ~ ("^\\|[[:space:]]*" cid "[[:space:]]*\\|")) {
      n = split($0, a, "|")
      id = trim(a[2]); ctype = trim(a[3]); cap = trim(a[4])
      if (new_type != "") ctype = new_type
      if (new_cap != "") cap = new_cap
      print "| " id " | " ctype " | " cap " |"
      updated=1
      next
    }
    print
  }
  END {
    if (!found_section) exit 2
    if (!updated) exit 3
  }
' "$PROP" > "$TMP_OUT"; then
  rc=$?
  rm -f "$TMP_OUT" || true
  [[ $rc -eq 2 ]] && fail "$(basename "$PROP"): missing '## Capabilities'"
  [[ $rc -eq 3 ]] && fail "$(basename "$PROP"): CapabilityID row not found: $CID"
  exit $rc
fi

if ! "$ROOT/.github/scripts/validate_proposition.sh" "$TMP_OUT" >/dev/null; then
  rc=$?
  rm -f "$TMP_OUT" || true
  exit $rc
fi

mv "$TMP_OUT" "$PROP"

"$ROOT/.github/scripts/validate_proposition.sh" "$PROP" >/dev/null
echo "OK: validated $PROP"


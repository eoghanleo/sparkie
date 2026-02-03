#!/usr/bin/env bash
set -euo pipefail

# update_proposition_gain_booster.sh
# Updates an existing Gain Booster row in the "## Gain Boosters" table.
#
# Usage:
#   ./phosphene/domains/product-marketing/scripts/update_proposition_gain_booster.sh --proposition <file> --booster-id BOOST-0001-PROP-0001 [--booster "..."] [--mapped-gains "..."]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/update_proposition_gain_booster.sh --proposition <file> --booster-id BOOST-0001-PROP-0001 [--booster "..."] [--mapped-gains "..."]
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)"

PROP=""
BID=""
BOOSTER=""
MAPPED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proposition) PROP="${2:-}"; shift 2 ;;
    --booster-id) BID="${2:-}"; shift 2 ;;
    --booster) BOOSTER="${2:-}"; shift 2 ;;
    --mapped-gains) MAPPED="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$PROP" ]] || { echo "Error: --proposition is required" >&2; usage; exit 2; }
[[ -n "$BID" ]] || { echo "Error: --booster-id is required" >&2; usage; exit 2; }
[[ -n "$BOOSTER" || -n "$MAPPED" ]] || fail "Provide at least one of --booster or --mapped-gains"

if [[ "$PROP" != /* ]]; then PROP="$ROOT/$PROP"; fi
[[ -f "$PROP" ]] || fail "Not a file: $PROP"

if [[ -n "$BOOSTER" && "$BOOSTER" == *"|"* ]]; then fail "--booster must not contain '|'"; fi

prop_id="$(grep -E '^ID:[[:space:]]*PROP-[0-9]{4}[[:space:]]*$' "$PROP" | head -n 1 | sed -E 's/^ID:[[:space:]]*//; s/[[:space:]]*$//')"
[[ -n "${prop_id:-}" ]] || fail "$(basename "$PROP"): missing/invalid 'ID: PROP-####'"

[[ "$BID" =~ ^BOOST-[0-9]{4}-${prop_id}$ ]] || fail "booster-id must match proposition ID suffix (${prop_id}): ${BID}"

mapped_norm=""
mapped_set=0
if [[ -n "${MAPPED:-}" ]]; then
  mapped_set=1
  if [[ "${MAPPED}" == "<...>" ]]; then
    mapped_norm=""
  else
    tmp_list="$(mktemp)"
    IFS=',' read -ra PARTS <<< "$MAPPED"
    for part in "${PARTS[@]:-}"; do
      x="$(printf "%s" "$part" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      [[ -z "$x" ]] && continue
      [[ "$x" =~ ^JTBD-GAIN-[0-9]{4}-PER-[0-9]{4}$ ]] || { rm -f "$tmp_list" || true; fail "invalid mapped gain id: $x"; }
      printf "%s\n" "$x" >> "$tmp_list"
    done
    mapped_norm="$(sort -u "$tmp_list" | awk 'BEGIN{first=1}{ if(!first) printf ", "; printf $0; first=0 } END{ if(!first) print "" }')"
    rm -f "$tmp_list" || true
  fi
fi

TMP_OUT="$(mktemp)"
if ! awk -v section="## Gain Boosters" -v bid="$BID" -v new_text="$BOOSTER" -v mapped_set="$mapped_set" -v new_mapped="$mapped_norm" '
  function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
  BEGIN { in_section=0; found_section=0; updated=0; }
  {
    if ($0 == section) { in_section=1; found_section=1; print; next }
    if (in_section && $0 ~ /^## /) { in_section=0 }

    if (in_section && $0 ~ ("^\\|[[:space:]]*" bid "[[:space:]]*\\|")) {
      n = split($0, a, "|")
      id = trim(a[2]); txt = trim(a[3]); mapped = trim(a[4])
      if (new_text != "") txt = new_text
      if (mapped_set == 1) mapped = new_mapped
      print "| " id " | " txt " | " mapped " |"
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
  [[ $rc -eq 2 ]] && fail "$(basename "$PROP"): missing '## Gain Boosters'"
  [[ $rc -eq 3 ]] && fail "$(basename "$PROP"): BoosterID row not found: $BID"
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


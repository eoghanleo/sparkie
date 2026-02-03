#!/usr/bin/env bash
set -euo pipefail

# update_proposition_pain_reliever.sh
# Updates an existing Pain Reliever row in the "## Pain Relievers" table.
#
# Usage:
#   ./phosphene/domains/product-marketing/scripts/update_proposition_pain_reliever.sh --proposition <file> --reliever-id REL-0001-PROP-0001 [--reliever "..."] [--mapped-pains "..."]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/update_proposition_pain_reliever.sh --proposition <file> --reliever-id REL-0001-PROP-0001 [--reliever "..."] [--mapped-pains "..."]
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)"

PROP=""
RID=""
RELIEVER=""
MAPPED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proposition) PROP="${2:-}"; shift 2 ;;
    --reliever-id) RID="${2:-}"; shift 2 ;;
    --reliever) RELIEVER="${2:-}"; shift 2 ;;
    --mapped-pains) MAPPED="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$PROP" ]] || { echo "Error: --proposition is required" >&2; usage; exit 2; }
[[ -n "$RID" ]] || { echo "Error: --reliever-id is required" >&2; usage; exit 2; }
[[ -n "$RELIEVER" || -n "$MAPPED" ]] || fail "Provide at least one of --reliever or --mapped-pains"

if [[ "$PROP" != /* ]]; then PROP="$ROOT/$PROP"; fi
[[ -f "$PROP" ]] || fail "Not a file: $PROP"

if [[ -n "$RELIEVER" && "$RELIEVER" == *"|"* ]]; then fail "--reliever must not contain '|'"; fi

prop_id="$(grep -E '^ID:[[:space:]]*PROP-[0-9]{4}[[:space:]]*$' "$PROP" | head -n 1 | sed -E 's/^ID:[[:space:]]*//; s/[[:space:]]*$//')"
[[ -n "${prop_id:-}" ]] || fail "$(basename "$PROP"): missing/invalid 'ID: PROP-####'"

[[ "$RID" =~ ^REL-[0-9]{4}-${prop_id}$ ]] || fail "reliever-id must match proposition ID suffix (${prop_id}): ${RID}"

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
      [[ "$x" =~ ^JTBD-PAIN-[0-9]{4}-PER-[0-9]{4}$ ]] || { rm -f "$tmp_list" || true; fail "invalid mapped pain id: $x"; }
      printf "%s\n" "$x" >> "$tmp_list"
    done
    mapped_norm="$(sort -u "$tmp_list" | awk 'BEGIN{first=1}{ if(!first) printf ", "; printf $0; first=0 } END{ if(!first) print "" }')"
    rm -f "$tmp_list" || true
  fi
fi

TMP_OUT="$(mktemp)"
if ! awk -v section="## Pain Relievers" -v rid="$RID" -v new_text="$RELIEVER" -v mapped_set="$mapped_set" -v new_mapped="$mapped_norm" '
  function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
  BEGIN { in_section=0; found_section=0; updated=0; }
  {
    if ($0 == section) { in_section=1; found_section=1; print; next }
    if (in_section && $0 ~ /^## /) { in_section=0 }

    if (in_section && $0 ~ ("^\\|[[:space:]]*" rid "[[:space:]]*\\|")) {
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
  [[ $rc -eq 2 ]] && fail "$(basename "$PROP"): missing '## Pain Relievers'"
  [[ $rc -eq 3 ]] && fail "$(basename "$PROP"): RelieverID row not found: $RID"
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


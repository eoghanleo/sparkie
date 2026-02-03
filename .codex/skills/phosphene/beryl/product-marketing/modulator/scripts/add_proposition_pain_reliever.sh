#!/usr/bin/env bash
set -euo pipefail

# add_proposition_pain_reliever.sh
# Adds a Pain Reliever row to the "## Pain Relievers" table.
#
# Usage:
#   ./phosphene/domains/product-marketing/scripts/add_proposition_pain_reliever.sh --proposition <file> --reliever "..." [--mapped-pains "JTBD-PAIN-0001-PER-0001,JTBD-PAIN-0002-PER-0001"]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/add_proposition_pain_reliever.sh --proposition <file> --reliever "..." [--mapped-pains "..."]
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)"

PROP=""
RELIEVER=""
MAPPED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proposition) PROP="${2:-}"; shift 2 ;;
    --reliever) RELIEVER="${2:-}"; shift 2 ;;
    --mapped-pains) MAPPED="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$PROP" ]] || { echo "Error: --proposition is required" >&2; usage; exit 2; }
[[ -n "$RELIEVER" ]] || { echo "Error: --reliever is required" >&2; usage; exit 2; }
if [[ "$RELIEVER" == *"|"* ]]; then fail "--reliever must not contain '|'"; fi

if [[ "$PROP" != /* ]]; then PROP="$ROOT/$PROP"; fi
[[ -f "$PROP" ]] || fail "Not a file: $PROP"

prop_id="$(grep -E '^ID:[[:space:]]*PROP-[0-9]{4}[[:space:]]*$' "$PROP" | head -n 1 | sed -E 's/^ID:[[:space:]]*//; s/[[:space:]]*$//')"
[[ -n "${prop_id:-}" ]] || fail "$(basename "$PROP"): missing/invalid 'ID: PROP-####'"

# Normalize mapped pains list (optional).
mapped_norm=""
if [[ -n "${MAPPED:-}" && "${MAPPED}" != "<...>" ]]; then
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

max_num="$(
  grep -oE "REL-[0-9]{4}-${prop_id}" "$PROP" 2>/dev/null \
    | sed -E "s/^REL-//; s/-${prop_id}\$//" \
    | sort -n \
    | tail -n 1 \
    || true
)"
if [[ -z "${max_num:-}" ]]; then
  next_num=1
else
  next_num=$((10#${max_num} + 1))
fi
rid="REL-$(printf "%04d" "$next_num")-${prop_id}"

TMP_OUT="$(mktemp)"
row="| ${rid} | ${RELIEVER} | ${mapped_norm} |"

if ! awk -v section="## Pain Relievers" -v row="$row" '
  function flush_buf(   i, insert_at) {
    insert_at = -1
    for (i = n; i >= 1; i--) {
      if (buf[i] ~ /^\\|[[:space:]]*REL-[0-9]{4}-/) { insert_at = i + 1; break }
    }
    if (insert_at == -1) {
      for (i = 1; i <= n; i++) {
        if (buf[i] ~ /^\\|[[:space:]]*---/) { insert_at = i + 1; break }
      }
    }
    if (insert_at == -1) {
      print "FAIL: could not find relievers table to insert into" > "/dev/stderr"
      exit 1
    }
    for (i = 1; i <= n + 1; i++) {
      if (i == insert_at) print row
      if (i <= n) print buf[i]
    }
  }
  BEGIN { in_section=0; found=0; n=0; }
  {
    if ($0 == section) { found=1; in_section=1; n=0; print; next }
    if (in_section) {
      if ($0 ~ /^## /) { flush_buf(); in_section=0; print; next }
      n++; buf[n]=$0; next
    }
    print
  }
  END { if (!found) exit 2; if (in_section) flush_buf() }
' "$PROP" > "$TMP_OUT"; then
  rc=$?
  rm -f "$TMP_OUT" || true
  [[ $rc -eq 2 ]] && fail "$(basename "$PROP"): missing '## Pain Relievers'"
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


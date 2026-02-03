#!/usr/bin/env bash
set -euo pipefail

# add_persona_jtbd_item.sh
# Inserts a new JTBD row into a Persona (PER-*) file under the correct section/table.
#
# JTBD IDs are "long natural keys":
#   JTBD-<TYPE>-####-<PersonaID>
# where <TYPE> is JOB|PAIN|GAIN and <PersonaID> is the persona's ID (e.g., PER-0003).
#
# Usage:
#   ./phosphene/domains/product-marketing/scripts/add_persona_jtbd_item.sh \
#     --persona <path/to/PER-0003.md> \
#     --type JOB|PAIN|GAIN \
#     --text "..." \
#     --importance 1..5

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/add_persona_jtbd_item.sh --persona <file> --type JOB|PAIN|GAIN --text "..." --importance 1..5
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)"

PERSONA=""
TYPE=""
TEXT=""
IMPORTANCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --persona) PERSONA="${2:-}"; shift 2 ;;
    --type) TYPE="${2:-}"; shift 2 ;;
    --text) TEXT="${2:-}"; shift 2 ;;
    --importance) IMPORTANCE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$PERSONA" ]] || { echo "Error: --persona is required" >&2; usage; exit 2; }
[[ -n "$TYPE" ]] || { echo "Error: --type is required" >&2; usage; exit 2; }
[[ -n "$TEXT" ]] || { echo "Error: --text is required" >&2; usage; exit 2; }
[[ -n "$IMPORTANCE" ]] || { echo "Error: --importance is required" >&2; usage; exit 2; }

case "$TYPE" in
  JOB|PAIN|GAIN) ;;
  *) fail "--type must be JOB|PAIN|GAIN (got: $TYPE)" ;;
esac

if ! [[ "$IMPORTANCE" =~ ^[1-5]$ ]]; then
  fail "--importance must be an integer 1..5 (got: $IMPORTANCE)"
fi

if [[ "$TEXT" == *"|"* ]]; then
  fail "--text must not contain '|' (pipe) characters; markdown tables will break"
fi

if [[ "$PERSONA" != /* ]]; then
  PERSONA="$ROOT/$PERSONA"
fi
[[ -f "$PERSONA" ]] || fail "Not a file: $PERSONA"

persona_id="$(grep -E '^ID:[[:space:]]*PER-[0-9]{4}[[:space:]]*$' "$PERSONA" | head -n 1 | sed -E 's/^ID:[[:space:]]*//; s/[[:space:]]*$//')"
[[ -n "${persona_id:-}" ]] || fail "$(basename "$PERSONA"): missing/invalid 'ID: PER-####'"

case "$TYPE" in
  JOB) section="## Jobs" ;;
  PAIN) section="## Pains" ;;
  GAIN) section="## Gains" ;;
  *) fail "internal error: unsupported JTBD type: $TYPE" ;;
esac

max_num="$(
  grep -oE "JTBD-${TYPE}-[0-9]{4}-${persona_id}" "$PERSONA" 2>/dev/null \
    | sed -E "s/^JTBD-${TYPE}-//; s/-${persona_id}\$//" \
    | sort -n \
    | tail -n 1 \
    || true
)"
if [[ -z "${max_num:-}" ]]; then
  next_num=1
else
  next_num=$((10#${max_num} + 1))
fi
next_id="JTBD-${TYPE}-$(printf "%04d" "$next_num")-${persona_id}"

TMP_OUT="$(mktemp)"
if ! awk -v section="$section" -v row="| ${next_id} | ${TEXT} | ${IMPORTANCE} |" -v type="$TYPE" '
  function flush_buf(   i, insert_at, pref) {
    pref = "^\\|[[:space:]]*JTBD-" type "-"
    insert_at = -1
    for (i = n; i >= 1; i--) {
      if (buf[i] ~ pref) { insert_at = i + 1; break }
    }
    if (insert_at == -1) {
      for (i = 1; i <= n; i++) {
        if (buf[i] ~ /^\\|[[:space:]]*---/) { insert_at = i + 1; break }
      }
    }
    if (insert_at == -1) {
      print "FAIL: could not find a markdown table to insert into under '"'"'" section "'"'"'" > "/dev/stderr"
      exit 1
    }
    for (i = 1; i <= n + 1; i++) {
      if (i == insert_at) print row
      if (i <= n) print buf[i]
    }
  }

  BEGIN { in_section=0; found=0; n=0; }
  {
    if ($0 == section) {
      found=1
      in_section=1
      n=0
      print
      next
    }
    if (in_section) {
      if ($0 ~ /^## /) {
        flush_buf()
        in_section=0
        print
        next
      }
      n++
      buf[n]=$0
      next
    }
    print
  }
  END {
    if (!found) exit 2
    if (in_section) flush_buf()
  }
' "$PERSONA" > "$TMP_OUT"; then
  rm -f "$TMP_OUT" || true
  fail "$(basename "$PERSONA"): failed to insert JTBD row"
fi

if ! "$ROOT/.github/scripts/validate_persona.sh" "$TMP_OUT" >/dev/null; then
  rc=$?
  rm -f "$TMP_OUT" || true
  exit $rc
fi

mv "$TMP_OUT" "$PERSONA"
echo "OK: validated $PERSONA"


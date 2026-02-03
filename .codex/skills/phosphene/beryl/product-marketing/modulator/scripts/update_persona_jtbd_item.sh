#!/usr/bin/env bash
set -euo pipefail

# update_persona_jtbd_item.sh
# Updates an existing JTBD row (JOB/PAIN/GAIN) in a Persona (PER-*) file.
#
# Usage:
#   ./phosphene/domains/product-marketing/scripts/update_persona_jtbd_item.sh --persona <file> --jtbd-id JTBD-PAIN-0001-PER-0003 [--text "..."] [--importance 1..5]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/update_persona_jtbd_item.sh --persona <file> --jtbd-id JTBD-<TYPE>-####-PER-#### [--text "..."] [--importance 1..5]
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)"

PERSONA=""
JTBD_ID=""
TEXT=""
IMPORTANCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --persona) PERSONA="${2:-}"; shift 2 ;;
    --jtbd-id) JTBD_ID="${2:-}"; shift 2 ;;
    --text) TEXT="${2:-}"; shift 2 ;;
    --importance) IMPORTANCE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$PERSONA" ]] || { echo "Error: --persona is required" >&2; usage; exit 2; }
[[ -n "$JTBD_ID" ]] || { echo "Error: --jtbd-id is required" >&2; usage; exit 2; }
[[ -n "$TEXT" || -n "$IMPORTANCE" ]] || fail "Provide at least one of --text or --importance"

if [[ "$PERSONA" != /* ]]; then PERSONA="$ROOT/$PERSONA"; fi
[[ -f "$PERSONA" ]] || fail "Not a file: $PERSONA"

if [[ -n "$IMPORTANCE" && ! "$IMPORTANCE" =~ ^[1-5]$ ]]; then
  fail "--importance must be an integer 1..5 (got: $IMPORTANCE)"
fi
if [[ -n "$TEXT" && "$TEXT" == *"|"* ]]; then
  fail "--text must not contain '|' (pipe) characters; markdown tables will break"
fi

persona_id="$(grep -E '^ID:[[:space:]]*PER-[0-9]{4}[[:space:]]*$' "$PERSONA" | head -n 1 | sed -E 's/^ID:[[:space:]]*//; s/[[:space:]]*$//')"
[[ -n "${persona_id:-}" ]] || fail "$(basename "$PERSONA"): missing/invalid 'ID: PER-####'"

if ! [[ "$JTBD_ID" =~ ^JTBD-(JOB|PAIN|GAIN)-[0-9]{4}-(PER-[0-9]{4})$ ]]; then
  fail "invalid jtbd-id format: $JTBD_ID"
fi

jtbd_type="${BASH_REMATCH[1]}"
jtbd_persona="${BASH_REMATCH[2]}"
[[ "$jtbd_persona" == "$persona_id" ]] || fail "$(basename "$PERSONA"): jtbd-id suffix must match persona ID ($persona_id): $JTBD_ID"

case "$jtbd_type" in
  JOB) section="## Jobs" ;;
  PAIN) section="## Pains" ;;
  GAIN) section="## Gains" ;;
esac

TMP_OUT="$(mktemp)"
if ! awk -v section="$section" -v jtbd="$JTBD_ID" -v new_text="$TEXT" -v new_imp="$IMPORTANCE" '
  function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
  BEGIN { in_section=0; found_section=0; updated=0; }
  {
    if ($0 == section) { in_section=1; found_section=1; print; next }
    if (in_section && $0 ~ /^## /) { in_section=0 }

    if (in_section && $0 ~ ("^\\|[[:space:]]*" jtbd "[[:space:]]*\\|")) {
      n = split($0, a, "|")
      id = trim(a[2]); txt = trim(a[3]); imp = trim(a[4])
      if (new_text != "") txt = new_text
      if (new_imp != "") imp = new_imp
      print "| " id " | " txt " | " imp " |"
      updated=1
      next
    }
    print
  }
  END {
    if (!found_section) exit 2
    if (!updated) exit 3
  }
' "$PERSONA" > "$TMP_OUT"; then
  rc=$?
  rm -f "$TMP_OUT" || true
  if [[ $rc -eq 2 ]]; then fail "$(basename "$PERSONA"): missing section $section"; fi
  if [[ $rc -eq 3 ]]; then fail "$(basename "$PERSONA"): JTBD row not found: $JTBD_ID"; fi
  exit $rc
fi

if ! "$ROOT/.github/scripts/validate_persona.sh" "$TMP_OUT" >/dev/null; then
  rc=$?
  rm -f "$TMP_OUT" || true
  exit $rc
fi

mv "$TMP_OUT" "$PERSONA"
echo "OK: validated $PERSONA"


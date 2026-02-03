#!/usr/bin/env bash
set -euo pipefail

# add_proposition_capability.sh
# Adds a Capability row to the "## Capabilities" table.
#
# Usage:
#   ./phosphene/domains/product-marketing/scripts/add_proposition_capability.sh --proposition <file> --type feature|function|standard|experience --capability "..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/add_proposition_capability.sh --proposition <file> --type feature|function|standard|experience --capability "..."
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)"

PROP=""
CTYPE=""
CAP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proposition) PROP="${2:-}"; shift 2 ;;
    --type) CTYPE="${2:-}"; shift 2 ;;
    --capability) CAP="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$PROP" ]] || { echo "Error: --proposition is required" >&2; usage; exit 2; }
[[ -n "$CTYPE" ]] || { echo "Error: --type is required" >&2; usage; exit 2; }
[[ -n "$CAP" ]] || { echo "Error: --capability is required" >&2; usage; exit 2; }

case "$CTYPE" in
  feature|function|standard|experience) ;;
  *) fail "--type must be one of feature|function|standard|experience" ;;
esac
if [[ "$CAP" == *"|"* ]]; then fail "--capability must not contain '|'"; fi

if [[ "$PROP" != /* ]]; then PROP="$ROOT/$PROP"; fi
[[ -f "$PROP" ]] || fail "Not a file: $PROP"

prop_id="$(grep -E '^ID:[[:space:]]*PROP-[0-9]{4}[[:space:]]*$' "$PROP" | head -n 1 | sed -E 's/^ID:[[:space:]]*//; s/[[:space:]]*$//')"
[[ -n "${prop_id:-}" ]] || fail "$(basename "$PROP"): missing/invalid 'ID: PROP-####'"

max_num="$(
  grep -oE "CAP-[0-9]{4}-${prop_id}" "$PROP" 2>/dev/null \
    | sed -E "s/^CAP-//; s/-${prop_id}\$//" \
    | sort -n \
    | tail -n 1 \
    || true
)"
if [[ -z "${max_num:-}" ]]; then
  next_num=1
else
  next_num=$((10#${max_num} + 1))
fi
cid="CAP-$(printf "%04d" "$next_num")-${prop_id}"

TMP_OUT="$(mktemp)"
row="| ${cid} | ${CTYPE} | ${CAP} |"

if ! awk -v section="## Capabilities" -v row="$row" '
  function flush_buf(   i, insert_at) {
    insert_at = -1
    for (i = n; i >= 1; i--) {
      if (buf[i] ~ /^\\|[[:space:]]*CAP-[0-9]{4}-/) { insert_at = i + 1; break }
    }
    if (insert_at == -1) {
      for (i = 1; i <= n; i++) {
        if (buf[i] ~ /^\\|[[:space:]]*---/) { insert_at = i + 1; break }
      }
    }
    if (insert_at == -1) {
      print "FAIL: could not find capabilities table to insert into" > "/dev/stderr"
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
  [[ $rc -eq 2 ]] && fail "$(basename "$PROP"): missing '## Capabilities'"
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


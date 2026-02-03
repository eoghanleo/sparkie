#!/usr/bin/env bash
set -euo pipefail

# remove_proposition_target_persona.sh
# Removes a PER-#### entry from "## Target Persona(s)" in a proposition.
#
# Usage:
#   ./phosphene/domains/product-marketing/scripts/remove_proposition_target_persona.sh --proposition <file> --persona PER-0001

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/remove_proposition_target_persona.sh --proposition <file> --persona PER-0001
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)"

PROP=""
PER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proposition) PROP="${2:-}"; shift 2 ;;
    --persona) PER="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$PROP" ]] || { echo "Error: --proposition is required" >&2; usage; exit 2; }
[[ -n "$PER" ]] || { echo "Error: --persona is required" >&2; usage; exit 2; }
[[ "$PER" =~ ^PER-[0-9]{4}$ ]] || fail "--persona must look like PER-0001"

if [[ "$PROP" != /* ]]; then PROP="$ROOT/$PROP"; fi
[[ -f "$PROP" ]] || fail "Not a file: $PROP"

TMP_OUT="$(mktemp)"
if ! awk -v per="$PER" '
  function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
  BEGIN { in_header=1; dep_done=0; in_tp=0; tp_found=0; }
  {
    if (in_header && $0 ~ /^Dependencies:/ && dep_done==0) {
      dep_done=1
      raw=$0
      sub(/^Dependencies:[[:space:]]*/, "", raw)
      n=split(raw, a, ",")
      out=""
      first=1
      for (i=1; i<=n; i++) {
        x=trim(a[i])
        if (x=="" || x==per) continue
        if (!first) out=out", "
        out=out x
        first=0
      }
      print "Dependencies: " out
      next
    }
    if (in_header && $0 == "") { in_header=0 }

    if ($0 == "## Target Persona(s)") { in_tp=1; tp_found=1; print; next }
    if (in_tp && $0 ~ /^## /) { in_tp=0; print; next }
    if (in_tp && $0 ~ ("^-+[[:space:]]+" per "[[:space:]]*$")) next

    print
  }
  END {
    if (!dep_done) exit 2
    if (!tp_found) exit 3
  }
' "$PROP" > "$TMP_OUT"; then
  rc=$?
  rm -f "$TMP_OUT" || true
  [[ $rc -eq 2 ]] && fail "$(basename "$PROP"): missing 'Dependencies:' header"
  [[ $rc -eq 3 ]] && fail "$(basename "$PROP"): missing '## Target Persona(s)'"
  exit $rc
fi

if ! "$ROOT/.github/scripts/validate_proposition.sh" --strict "$TMP_OUT" >/dev/null; then
  val_rc=$?
  rm -f "$TMP_OUT"
  exit $val_rc
fi

mv "$TMP_OUT" "$PROP"
set -e

echo "OK: strict-validated $PROP"


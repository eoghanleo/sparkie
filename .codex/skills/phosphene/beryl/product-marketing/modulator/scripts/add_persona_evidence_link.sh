#!/usr/bin/env bash
set -euo pipefail

# add_persona_evidence_link.sh
# Adds a supporting ID into the Persona "## Evidence and links" section.
#
# This script is intentionally generous: it routes IDs into buckets:
# - EvidenceIDs: E-####
# - CandidatePersonaIDs: CPE-####
# - DocumentIDs: anything else (RA-###, PITCH-####, RS-####, FR-###, etc.)
#
# Usage:
#   ./phosphene/domains/product-marketing/scripts/add_persona_evidence_link.sh --persona <file> --id E-0001
#   ./phosphene/domains/product-marketing/scripts/add_persona_evidence_link.sh --persona <file> --id CPE-0001
#   ./phosphene/domains/product-marketing/scripts/add_persona_evidence_link.sh --persona <file> --id RA-001

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/add_persona_evidence_link.sh --persona <file> --id <stable-id>
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)"

PERSONA=""
SID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --persona) PERSONA="${2:-}"; shift 2 ;;
    --id) SID="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$PERSONA" ]] || { echo "Error: --persona is required" >&2; usage; exit 2; }
[[ -n "$SID" ]] || { echo "Error: --id is required" >&2; usage; exit 2; }

if [[ "$PERSONA" != /* ]]; then PERSONA="$ROOT/$PERSONA"; fi
[[ -f "$PERSONA" ]] || fail "Not a file: $PERSONA"

# Basic sanity: no whitespace
if [[ "$SID" =~ [[:space:]] ]]; then
  fail "--id must not contain whitespace"
fi

bucket="### DocumentIDs"
if [[ "$SID" =~ ^E-[0-9]{4}$ ]]; then bucket="### EvidenceIDs"; fi
if [[ "$SID" =~ ^CPE-[0-9]{4}$ ]]; then bucket="### CandidatePersonaIDs"; fi

TMP_ITEMS="$(mktemp)"
TMP_SORTED="$(mktemp)"
TMP_OUT="$(mktemp)"

awk -v bucket="$bucket" '
  BEGIN { in_ev=0; in_bucket=0; }
  $0 == "## Evidence and links" { in_ev=1; next }
  in_ev && $0 ~ /^## / { in_ev=0; in_bucket=0 }
  in_ev {
    if ($0 == bucket) { in_bucket=1; next }
    if (in_bucket && ($0 ~ /^### / || $0 ~ /^## /)) { in_bucket=0 }
    if (in_bucket && $0 ~ /^-[[:space:]]+/) {
      sub(/^-+[[:space:]]+/, "", $0)
      gsub(/[[:space:]]+$/, "", $0)
      if ($0 != "" && $0 != "<...>") print
    }
  }
' "$PERSONA" > "$TMP_ITEMS"

printf "%s\n" "$SID" >> "$TMP_ITEMS"
sort -u "$TMP_ITEMS" > "$TMP_SORTED"

if ! awk -v bucket="$bucket" -v items_file="$TMP_SORTED" '
  function print_items(path,   line) {
    while ((getline line < path) > 0) {
      gsub(/[[:space:]]+$/, "", line)
      if (line != "") print "- " line
    }
    close(path)
  }
  BEGIN { in_ev=0; in_bucket=0; found_bucket=0; inserted=0; }
  {
    if ($0 == "## Evidence and links") { in_ev=1; print; next }
    if (in_ev && $0 ~ /^## /) { in_ev=0; in_bucket=0 }

    if (in_ev && $0 == bucket) {
      found_bucket=1
      in_bucket=1
      inserted=0
      print
      next
    }

    if (in_bucket) {
      if ($0 ~ /^### / || $0 ~ /^## /) {
        if (!inserted) {
          print_items(items_file)
          print ""
          inserted=1
        }
        in_bucket=0
        print
        next
      }
      if ($0 ~ /^-[[:space:]]+/) next
      print
      next
    }

    print
  }
  END {
    if (!found_bucket) exit 2
    if (in_bucket && !inserted) {
      print_items(items_file)
      print ""
    }
  }
' "$PERSONA" > "$TMP_OUT"; then
  rc=$?
  rm -f "$TMP_ITEMS" "$TMP_SORTED" "$TMP_OUT" || true
  [[ $rc -eq 2 ]] && fail "$(basename "$PERSONA"): missing bucket heading $bucket under '## Evidence and links'"
  exit $rc
fi

rm -f "$TMP_ITEMS" "$TMP_SORTED" || true

if ! "$ROOT/.github/scripts/validate_persona.sh" "$TMP_OUT" >/dev/null; then
  rc=$?
  rm -f "$TMP_OUT" || true
  exit $rc
fi

mv "$TMP_OUT" "$PERSONA"

"$ROOT/.github/scripts/validate_persona.sh" "$PERSONA" >/dev/null
echo "OK: validated $PERSONA"


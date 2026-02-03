#!/usr/bin/env bash
set -euo pipefail

# add_evidence_record.sh
# Allocates the next legal EvidenceID and appends a placeholder row to 50-evidence-bank.md
#
# Usage:
#   ./phosphene/domains/research/scripts/add_evidence_record.sh --bundle <bundle_dir> [--type "Quote"] [--pointer "https://..."]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/research/scripts/add_evidence_record.sh --bundle <bundle_dir> [--type "Quote"] [--pointer "https://..."]
EOF
}

BUNDLE=""
ETYPE="Quote"
POINTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle) BUNDLE="${2:-}"; shift 2 ;;
    --type) ETYPE="${2:-}"; shift 2 ;;
    --pointer) POINTER="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$BUNDLE" ]] || { echo "Error: --bundle is required" >&2; exit 2; }

ROOT="$(phosphene_find_project_root)"
if [[ "$BUNDLE" != /* ]]; then BUNDLE="$ROOT/$BUNDLE"; fi
[[ -d "$BUNDLE" ]] || { echo "Error: not a directory: $BUNDLE" >&2; exit 1; }

"$ROOT/phosphene/phosphene-core/bin/phosphene" id validate >/dev/null
EVID="$("$ROOT/phosphene/phosphene-core/bin/phosphene" id next --type evidence)"

FILE="$BUNDLE/50-evidence-bank.md"
[[ -f "$FILE" ]] || { echo "Error: missing $FILE" >&2; exit 1; }

if grep -q "$EVID" "$FILE"; then
  echo "Error: EvidenceID already present in $FILE: $EVID" >&2
  exit 1
fi

# Ensure table exists
if ! grep -qE '^[|][[:space:]]*EvidenceID[[:space:]]*[|]' "$FILE"; then
  echo "Error: evidence bank table header not found in $FILE" >&2
  exit 1
fi

if [[ -z "$POINTER" ]]; then POINTER="<link>"; fi

echo "| ${EVID} | ${ETYPE} |  |  |  | \"<...>\" | ${POINTER} | E1 | C1 |" >> "$FILE"
echo "Added EvidenceID: $EVID"


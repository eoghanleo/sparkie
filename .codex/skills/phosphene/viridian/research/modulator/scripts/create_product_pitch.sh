#!/usr/bin/env bash
set -euo pipefail

# create_product_pitch.sh
# Creates a new pitch file in an RA bundle, allocating the next legal PITCH ID.
#
# Usage:
#   ./phosphene/domains/research/scripts/create_product_pitch.sh --bundle <bundle_dir> --title "..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/research/scripts/create_product_pitch.sh --bundle <bundle_dir> --title "..."
EOF
}

BUNDLE=""
TITLE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle) BUNDLE="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$BUNDLE" && -n "$TITLE" ]] || { echo "Error: --bundle and --title are required" >&2; exit 2; }

ROOT="$(phosphene_find_project_root)"
if [[ "$BUNDLE" != /* ]]; then BUNDLE="$ROOT/$BUNDLE"; fi
[[ -d "$BUNDLE" ]] || { echo "Error: not a directory: $BUNDLE" >&2; exit 1; }
[[ -d "$BUNDLE/30-pitches" ]] || { echo "Error: bundle missing 30-pitches/: $BUNDLE" >&2; exit 1; }

"$ROOT/phosphene/phosphene-core/bin/phosphene" id validate >/dev/null
PITCH_ID="$("$ROOT/phosphene/phosphene-core/bin/phosphene" id next --type pitch)"
RA_ID="$(grep -E '^ID:[[:space:]]*RA-[0-9]{3}[[:space:]]*$' "$BUNDLE/00-coversheet.md" | head -n 1 | sed -E 's/^ID:[[:space:]]*//; s/[[:space:]]*$//')"
[[ -n "$RA_ID" ]] || { echo "Error: could not read RA ID from 00-coversheet.md" >&2; exit 1; }

OUT="$BUNDLE/30-pitches/${PITCH_ID}.md"
if [[ -e "$OUT" ]]; then
  echo "Error: pitch already exists: $OUT" >&2
  exit 1
fi

DATE="$(date +%F)"

cat > "$OUT" <<EOF
ID: ${PITCH_ID}
RA: ${RA_ID}
Title: ${TITLE}
Status: Draft
Updated: ${DATE}
Confidence: C1
EvidenceIDs:

## One-line pitch

<one sentence>

## Target

- Target segment(s):
- Target persona(s):

## Trigger / why-now

<...>

## Core pain → promised gain

<...>

## So it works because… (mechanism, not scope)

<...>

## Differentiation vs reference solutions

<...>

## Likely objections + counters

<...>

## We lose when…

<...>

## Unknowns to validate next

<...>
EOF

echo "Created: $OUT"


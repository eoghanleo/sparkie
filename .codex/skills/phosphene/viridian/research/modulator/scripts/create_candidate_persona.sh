#!/usr/bin/env bash
set -euo pipefail

# create_candidate_persona.sh
# Creates a Candidate Persona (CPE) doc inside an RA bundle.
#
# Why:
# - CPE-* are authoritative in <research> as "1:1 proposals" for canonical personas.
# - Canonical personas (PER-*) are authoritative in <product-marketing> only.
#
# Usage:
#   ./phosphene/domains/research/scripts/create_candidate_persona.sh --bundle <bundle_dir> --name "Idle Ingrid" [--segment SEG-0001]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/research/scripts/create_candidate_persona.sh --bundle <bundle_dir> --name "..." [--segment SEG-0001]
EOF
}

slugify() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

BUNDLE=""
NAME=""
SEGMENT="SEG-XXXX"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle) BUNDLE="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --segment) SEGMENT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$BUNDLE" ]] || { echo "Error: --bundle is required" >&2; usage; exit 2; }
[[ -n "$NAME" ]] || { echo "Error: --name is required" >&2; usage; exit 2; }

ROOT="$(phosphene_find_project_root)"
if [[ "$BUNDLE" != /* ]]; then
  BUNDLE="$ROOT/$BUNDLE"
fi
[[ -d "$BUNDLE" ]] || { echo "Error: bundle dir not found: $BUNDLE" >&2; exit 1; }

RA_ID="$(grep -E '^ID:[[:space:]]*RA-[0-9]{3}[[:space:]]*$' "$BUNDLE/00-coversheet.md" | head -n 1 | sed -E 's/^ID:[[:space:]]*//; s/[[:space:]]*$//')"
[[ -n "${RA_ID:-}" ]] || { echo "Error: could not read RA ID from $BUNDLE/00-coversheet.md" >&2; exit 1; }

# Ensure global uniqueness is clean before allocating.
"$ROOT/phosphene/phosphene-core/bin/phosphene" id validate >/dev/null
CPE_ID="$("$ROOT/phosphene/phosphene-core/bin/phosphene" id next --type cpe)"

OUT_DIR="$BUNDLE/60-candidate-personas"
mkdir -p "$OUT_DIR"

OUT_FILE="$OUT_DIR/${CPE_ID}-$(slugify "$NAME").md"
if [[ -e "$OUT_FILE" ]]; then
  echo "Error: already exists: $OUT_FILE" >&2
  exit 1
fi

DATE="$(date +%F)"

# Templates are intentionally not used (bash-only; script is the single source of truth).
cat > "$OUT_FILE" <<EOF
ID: ${CPE_ID}
Title: Candidate Persona — ${NAME}
Status: Draft
Updated: ${DATE}
Dependencies: ${RA_ID}
Owner:

## Snapshot
- SegmentID: ${SEGMENT}
- Role tags: <economic buyer / champion / end user / implementer / approver / blocker>
- Role:
- Context:
- Primary goals:

## Jobs-to-be-done
- <JTBD 1>

## Pain points
- <pain 1>

## Current alternatives
- <alternative 1>

## Success looks like
- <success 1>

## Promotion notes (to <product-marketing>)
- Intended canonical persona: PER-XXXX (allocate on promotion)
- What must survive the promotion:
  - <non-negotiable 1>

## Notes / evidence
- EvidenceIDs: <E-0001, E-0002, ...>
- Confidence: <C1/C2/C3>
- Source notes (web-only):
  - <key excerpt or paraphrase + pointer>

EOF

echo "Created candidate persona: $OUT_FILE"
echo "Next:"
echo "  - add EvidenceIDs + confidence"
echo "  - reference ${CPE_ID} from hypotheses/evidence/pitches as needed"


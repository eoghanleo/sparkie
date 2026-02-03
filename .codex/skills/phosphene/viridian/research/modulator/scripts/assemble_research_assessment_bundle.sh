#!/usr/bin/env bash
set -euo pipefail

# assemble_research_assessment_bundle.sh
# Concatenates an RA bundle into a single assembled view file (<ID>.md) for convenience.
#
# Usage:
#   ./phosphene/domains/research/scripts/assemble_research_assessment_bundle.sh /abs/or/rel/path/to/RA-001-some-slug

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/research/scripts/assemble_research_assessment_bundle.sh <bundle_dir>

Writes:
  <bundle_dir>/<RA-ID>.md
EOF
}

BUNDLE_DIR="${1:-}"
if [[ -z "$BUNDLE_DIR" || "$BUNDLE_DIR" == "-h" || "$BUNDLE_DIR" == "--help" ]]; then
  usage
  exit 0
fi

ROOT="$(phosphene_find_project_root)"
if [[ "$BUNDLE_DIR" != /* ]]; then
  BUNDLE_DIR="$ROOT/$BUNDLE_DIR"
fi

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "Error: not a directory: $BUNDLE_DIR" >&2
  exit 1
fi

ID_LINE="$(grep -E '^ID:[[:space:]]*RA-[0-9]{3}[[:space:]]*$' "$BUNDLE_DIR/00-coversheet.md" || true)"
if [[ -z "$ID_LINE" ]]; then
  echo "Error: could not read RA ID from 00-coversheet.md" >&2
  exit 1
fi
RA_ID="$(echo "$ID_LINE" | sed -E 's/^ID:[[:space:]]*//; s/[[:space:]]*$//')"

OUT="$BUNDLE_DIR/${RA_ID}.md"

{
  echo "<!--"
  echo "AUTO-ASSEMBLED FILE. Do not hand-edit."
  echo "Source bundle: $(basename "$BUNDLE_DIR")"
  echo "Generated: $(date -u +%FT%TZ)"
  echo "-->"
  echo ""
  echo "# ${RA_ID} — Research Assessment (assembled)"
  echo ""
  echo "This is an assembled view of the RA bundle. Use the component files for edits."
  echo ""

  echo ""
  echo "## Coversheet"
  echo ""
  cat "$BUNDLE_DIR/00-coversheet.md"

  echo ""
  echo "## Reference solutions"
  echo ""
  cat "$BUNDLE_DIR/10-reference-solutions.md"

  echo ""
  echo "## Competitive landscape"
  echo ""
  cat "$BUNDLE_DIR/20-competitive-landscape.md"

  echo ""
  echo "## Pitches"
  echo ""
  if compgen -G "$BUNDLE_DIR/30-pitches/PITCH-*.md" >/dev/null; then
    for f in "$BUNDLE_DIR"/30-pitches/PITCH-*.md; do
      echo ""
      echo "### $(basename "$f" .md)"
      echo ""
      cat "$f"
    done
  else
    echo "_No pitch files found in 30-pitches/ yet._"
  fi

  echo ""
  echo "## Hypotheses"
  echo ""
  cat "$BUNDLE_DIR/40-hypotheses.md"

  echo ""
  echo "## Candidate personas (CPE)"
  echo ""
  if compgen -G "$BUNDLE_DIR/60-candidate-personas/CPE-*.md" >/dev/null; then
    for f in "$BUNDLE_DIR"/60-candidate-personas/CPE-*.md; do
      echo ""
      echo "### $(basename "$f" .md)"
      echo ""
      cat "$f"
    done
  else
    echo "_No candidate persona files found in 60-candidate-personas/ yet._"
  fi

  echo ""
  echo "## Evidence bank"
  echo ""
  cat "$BUNDLE_DIR/50-evidence-bank.md"

  echo ""
  echo "## Methods"
  echo ""
  cat "$BUNDLE_DIR/90-methods.md"
} > "$OUT"

echo "Assembled: $OUT"


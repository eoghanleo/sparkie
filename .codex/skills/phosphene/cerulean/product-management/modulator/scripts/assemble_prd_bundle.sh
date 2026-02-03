#!/usr/bin/env bash
set -euo pipefail

# assemble_prd_bundle.sh
# Concatenates a PRD bundle into a single assembled view file (<ID>.md) for convenience.
#
# Usage:
#   ./.codex/skills/phosphene/cerulean/product-management/modulator/scripts/assemble_prd_bundle.sh <bundle_dir>
#
# Writes:
#   <bundle_dir>/<PRD-ID>.md

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./.codex/skills/phosphene/cerulean/product-management/modulator/scripts/assemble_prd_bundle.sh <bundle_dir>

Writes:
  <bundle_dir>/<PRD-ID>.md
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

ID_LINE="$(grep -E '^ID:[[:space:]]*PRD-[0-9]{3}[[:space:]]*$' "$BUNDLE_DIR/00-coversheet.md" || true)"
if [[ -z "$ID_LINE" ]]; then
  echo "Error: could not read PRD ID from 00-coversheet.md" >&2
  exit 1
fi
PRD_ID="$(echo "$ID_LINE" | sed -E 's/^ID:[[:space:]]*//; s/[[:space:]]*$//')"

DEPS_LINE="$(grep -E '^Dependencies:' "$BUNDLE_DIR/00-coversheet.md" | head -n 1 || true)"
if [[ -n "$DEPS_LINE" ]]; then
  DEPS_RAW="$(echo "$DEPS_LINE" | sed -E 's/^Dependencies:[[:space:]]*//')"
  if [[ -z "${DEPS_RAW//[[:space:]]/}" ]]; then
    echo "WARN: Dependencies header is empty in coversheet (recommended to include VPD-###/RA-###/ROADMAP-###)" >&2
  fi
fi

OUT="$BUNDLE_DIR/${PRD_ID}.md"

assemble_cat() {
  local path="$1"
  [[ -f "$path" ]] || { echo "Error: missing file: $path" >&2; exit 1; }
  cat "$path"
}

{
  echo "<!--"
  echo "AUTO-ASSEMBLED FILE. Do not hand-edit."
  echo "Source bundle: $(basename "$BUNDLE_DIR")"
  echo "Generated: $(date -u +%FT%TZ)"
  echo "-->"
  echo ""
  echo "# ${PRD_ID} — PRD (assembled)"
  echo ""
  echo "This is an assembled view of the PRD bundle. Use the component files for edits."
  echo ""

  echo ""
  echo "## Coversheet"
  echo ""
  assemble_cat "$BUNDLE_DIR/00-coversheet.md"

  echo ""
  echo "## Executive summary"
  echo ""
  assemble_cat "$BUNDLE_DIR/10-executive-summary.md"

  echo ""
  echo "## Product context"
  echo ""
  assemble_cat "$BUNDLE_DIR/20-product-context.md"

  echo ""
  echo "## Personas, jobs, and propositions"
  echo ""
  assemble_cat "$BUNDLE_DIR/30-personas-jobs-props.md"

  echo ""
  echo "## Goals and scope"
  echo ""
  assemble_cat "$BUNDLE_DIR/40-goals-scope.md"

  echo ""
  echo "## Success metrics"
  echo ""
  assemble_cat "$BUNDLE_DIR/50-success-metrics.md"

  echo ""
  echo "## Requirements"
  echo ""
  assemble_cat "$BUNDLE_DIR/60-requirements/README.md"
  echo ""
  assemble_cat "$BUNDLE_DIR/60-requirements/functional.md"
  echo ""
  assemble_cat "$BUNDLE_DIR/60-requirements/non-functional.md"

  echo ""
  echo "## Feature catalogue"
  echo ""
  assemble_cat "$BUNDLE_DIR/70-feature-catalogue/README.md"
  echo ""
  assemble_cat "$BUNDLE_DIR/70-feature-catalogue/core-features.md"
  echo ""
  assemble_cat "$BUNDLE_DIR/70-feature-catalogue/special-features.md"

  echo ""
  echo "## Architecture"
  echo ""
  assemble_cat "$BUNDLE_DIR/80-architecture.md"

  echo ""
  echo "## Platform and technology"
  echo ""
  assemble_cat "$BUNDLE_DIR/90-platform-technology.md"

  echo ""
  echo "## Data, integrations, and APIs"
  echo ""
  assemble_cat "$BUNDLE_DIR/100-data-integrations.md"

  echo ""
  echo "## Security, privacy, and compliance"
  echo ""
  assemble_cat "$BUNDLE_DIR/110-security-compliance.md"

  echo ""
  echo "## UX, content, and accessibility"
  echo ""
  assemble_cat "$BUNDLE_DIR/120-ux-content.md"

  echo ""
  echo "## Delivery plan and roadmap"
  echo ""
  assemble_cat "$BUNDLE_DIR/130-delivery-roadmap.md"

  echo ""
  echo "## Testing and quality strategy"
  echo ""
  assemble_cat "$BUNDLE_DIR/140-testing-quality.md"

  echo ""
  echo "## Operations and support model"
  echo ""
  assemble_cat "$BUNDLE_DIR/150-operations-support.md"

  echo ""
  echo "## Risks, dependencies, and assumptions"
  echo ""
  assemble_cat "$BUNDLE_DIR/160-risks-dependencies.md"

  echo ""
  echo "## Release readiness and launch plan"
  echo ""
  assemble_cat "$BUNDLE_DIR/170-release-readiness.md"

  echo ""
  echo "## Appendix"
  echo ""
  assemble_cat "$BUNDLE_DIR/180-appendix/README.md"
  echo ""
  assemble_cat "$BUNDLE_DIR/180-appendix/glossary.md"
  echo ""
  assemble_cat "$BUNDLE_DIR/180-appendix/decision-log.md"
  echo ""
  assemble_cat "$BUNDLE_DIR/180-appendix/open-questions.md"
  echo ""
  assemble_cat "$BUNDLE_DIR/180-appendix/traceability-matrix.md"
} > "$OUT"

echo "Assembled: $OUT"


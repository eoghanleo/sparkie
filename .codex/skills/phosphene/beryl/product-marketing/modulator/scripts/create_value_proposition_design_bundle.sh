#!/usr/bin/env bash
set -euo pipefail

# create_value_proposition_design_bundle.sh
# Creates a Value Proposition Design (VPD) bundle folder populated from templates.
#
# Usage (run from repo root):
#   ./phosphene/domains/product-marketing/scripts/create_value_proposition_design_bundle.sh --title "..." [--id VPD-001] [--owner ""] [--priority Medium]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/create_value_proposition_design_bundle.sh --title "..." [--id VPD-001] [--owner "..."] [--priority Medium]

Creates:
  phosphene/domains/product-marketing/output/value-proposition-designs/VPD-001-<slug>/
    00-coversheet.md
    10-personas/ (empty; PER-*.md)
    20-propositions/ (empty; PROP-*.md)
EOF
}

slugify() {
  # Lowercase, keep alnum and dashes, collapse spaces/underscores to dash.
  # macOS bash 3.2 compatible.
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

ID=""
TITLE=""
OWNER=""
PRIORITY="Medium"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) ID="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --owner) OWNER="${2:-}"; shift 2 ;;
    --priority) PRIORITY="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "${TITLE}" ]]; then
  echo "Error: --title is required." >&2
  usage
  exit 2
fi

ROOT="$(phosphene_find_project_root)"

if [[ -z "${ID}" ]]; then
  "$ROOT/phosphene/phosphene-core/bin/phosphene" id validate >/dev/null
  ID="$("$ROOT/phosphene/phosphene-core/bin/phosphene" id next --type vpd)"
fi

if ! [[ "$ID" =~ ^VPD-[0-9]{3}$ ]]; then
  echo "Error: --id must look like VPD-001" >&2
  exit 2
fi

DOCS_DIR="$ROOT/phosphene/domains/product-marketing/output/value-proposition-designs"

mkdir -p "$DOCS_DIR"

SLUG="$(slugify "$TITLE")"
BUNDLE_DIR="$DOCS_DIR/${ID}-${SLUG}"

if [[ -e "$BUNDLE_DIR" ]]; then
  echo "Error: bundle already exists: $BUNDLE_DIR" >&2
  exit 1
fi

mkdir -p "$BUNDLE_DIR/10-personas"
mkdir -p "$BUNDLE_DIR/20-propositions"

DATE="$(date +%F)"

# Templates are intentionally not used (bash-only; script is the single source of truth).
cat > "$BUNDLE_DIR/00-coversheet.md" <<EOF
ID: ${ID}
Title: ${TITLE}
Status: Draft
Priority: ${PRIORITY}
Updated: ${DATE}
Dependencies:
Owner: ${OWNER}
EditPolicy: DO_NOT_EDIT_DIRECTLY (use scripts; see .codex/skills/phosphene/beryl/product-marketing/modulator/SKILL.md)

## Purpose (read first)

This is a **Value Proposition Design (VPD)** bundle: the WTBD parent for \`<product-marketing>\`.

It exists to make persona + proposition work:
- scoped (what are we working on right now?)
- traceable (what did this depend on?)
- composable (downstream domains can consume a VPD as a coherent unit)

## Inputs

List upstream context that seeded this VPD:
- Research IDs (RA / PITCH / E / CPE / etc)
- Prior VPDs (if this is a refinement)
- Any other relevant IDs

## Outputs (children of this VPD)

This VPD should produce:
- Personas: \`PER-####\` (must list \`Dependencies: ${ID}\` in the persona header)
- Propositions: \`PROP-####\` (must list \`Dependencies: ${ID}\` in the proposition header)

## Notes

- Use scripts. Avoid hand-editing artifacts.
- When in doubt, create more propositions than you think you need.

EOF

cat > "$BUNDLE_DIR/10-personas/README.md" <<EOF
# Personas folder

Create persona files here (PER-*.md). Recommended:

  ./phosphene/domains/product-marketing/scripts/create_new_persona.sh \\
    --title "..." \\
    --vpd "${ID}" \\
    --dependencies "RA-001" \\
    --output-dir "$BUNDLE_DIR/10-personas"

EOF

cat > "$BUNDLE_DIR/20-propositions/README.md" <<EOF
# Propositions folder

Create proposition files here (PROP-*.md). Recommended:

  ./phosphene/domains/product-marketing/scripts/create_new_proposition.sh \\
    --title "..." \\
    --vpd "${ID}" \\
    --dependencies "PER-0001,RA-001" \\
    --output-dir "$BUNDLE_DIR/20-propositions"

EOF

echo "Created VPD bundle: $BUNDLE_DIR"
echo "Next:"
echo "  - create personas: ./phosphene/domains/product-marketing/scripts/create_new_persona.sh --vpd \"${ID}\" --output-dir \"$BUNDLE_DIR/10-personas\" --dependencies \"...\" --title \"...\""
echo "  - create propositions: ./phosphene/domains/product-marketing/scripts/create_new_proposition.sh --vpd \"${ID}\" --output-dir \"$BUNDLE_DIR/20-propositions\" --dependencies \"...\" --title \"...\""


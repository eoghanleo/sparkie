#!/usr/bin/env bash
set -euo pipefail

# create_product_roadmap.sh
# Create a new product roadmap artifact (ROADMAP-###).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./.codex/skills/phosphene/beryl/product-strategy/modulator/scripts/create_product_roadmap.sh --title "..." [--id ROADMAP-001] [--status Draft] [--dependencies "RA-001,VPD-001"]
EOF
}

slugify() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

ID=""
TITLE=""
STATUS="Draft"
DEPENDENCIES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) ID="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --status) STATUS="${2:-}"; shift 2 ;;
    --dependencies) DEPENDENCIES="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "${TITLE:-}" ]]; then
  echo "Error: --title is required." >&2
  usage
  exit 2
fi

ROOT="$(cd "$ROOT" && pwd)"

if [[ -z "${ID:-}" ]]; then
  "$ROOT/phosphene/phosphene-core/bin/phosphene" id validate >/dev/null
  ID="$("$ROOT/phosphene/phosphene-core/bin/phosphene" id next --type roadmap)"
fi

if ! [[ "$ID" =~ ^ROADMAP-[0-9]{3}$ ]]; then
  echo "Error: --id must look like ROADMAP-001" >&2
  exit 2
fi

DOCS_DIR="$ROOT/phosphene/domains/product-strategy/output/product-roadmaps"
mkdir -p "$DOCS_DIR"

SLUG="$(slugify "$TITLE")"
SLUG="${SLUG:-roadmap}"
DOC_PATH="$DOCS_DIR/${ID}-${SLUG}.md"

if [[ -e "$DOC_PATH" ]]; then
  echo "Error: roadmap already exists: $DOC_PATH" >&2
  exit 1
fi

DATE="$(date -u +"%Y-%m-%d")"

cat > "$DOC_PATH" <<EOF
ID: ${ID}
Title: ${TITLE}
Status: ${STATUS}
Updated: ${DATE}
Dependencies: ${DEPENDENCIES}

\`\`\`text
[V-SCRIPT]:
create_product_roadmap.sh
\`\`\`

## Bet framing

- <What is the bet? Why now?>

## Trajectory lattice (2–4 trajectories)

### Trajectory 1

- <Trajectory hypothesis + sequencing>

### Trajectory 2

- <Trajectory hypothesis + sequencing>

## Decision triggers / gates

- <What causes us to advance/pivot/stop?>

## Constraints

- <Non-negotiables, risks, and “we lose when…”>

## Dependencies

- <Upstream constraints and open questions>

## Notes

- <Optional>
EOF

echo "Created product roadmap: $DOC_PATH"

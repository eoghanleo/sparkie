#!/usr/bin/env bash
set -euo pipefail

# create_product_architecture.sh
# Create a new product architecture artifact (ARCH-###).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./.codex/skills/phosphene/cerulean/product-architecture/modulator/scripts/create_product_architecture.sh --title "..." [--id ARCH-001] [--status Draft] [--dependencies "PRD-001,ROADMAP-001"]
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
  ID="$("$ROOT/phosphene/phosphene-core/bin/phosphene" id next --type arch)"
fi

if ! [[ "$ID" =~ ^ARCH-[0-9]{3}$ ]]; then
  echo "Error: --id must look like ARCH-001" >&2
  exit 2
fi

DOCS_DIR="$ROOT/phosphene/domains/product-architecture/output/architectures"
mkdir -p "$DOCS_DIR"

SLUG="$(slugify "$TITLE")"
SLUG="${SLUG:-architecture}"
DOC_PATH="$DOCS_DIR/${ID}-${SLUG}.md"

if [[ -e "$DOC_PATH" ]]; then
  echo "Error: architecture already exists: $DOC_PATH" >&2
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
create_product_architecture.sh
\`\`\`

## Domain model and state

- <Entities, state transitions, invariants>

## Interface contracts

- <Boundaries + contract links (OpenAPI/AsyncAPI/Schema)>

## Telemetry + security scaffolding

- <Events, privacy classification, threat controls>

## Machine artifacts (optional)

- <Links to OpenAPI/AsyncAPI/JSON Schema, if present>

## Notes

- <Optional>
EOF

echo "Created product architecture: $DOC_PATH"

#!/usr/bin/env bash
set -euo pipefail

# create_test_plan.sh
# Create a new test plan artifact (TP-###).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./.codex/skills/phosphene/cadmium/test-management/modulator/scripts/create_test_plan.sh --title "..." [--id TP-001] [--status Draft] [--dependencies "PRD-001,FR-001"]
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
  ID="$("$ROOT/phosphene/phosphene-core/bin/phosphene" id next --type tp)"
fi

if ! [[ "$ID" =~ ^TP-[0-9]{3}$ ]]; then
  echo "Error: --id must look like TP-001" >&2
  exit 2
fi

DOCS_DIR="$ROOT/phosphene/domains/test-management/output/test-plans"
mkdir -p "$DOCS_DIR"

SLUG="$(slugify "$TITLE")"
SLUG="${SLUG:-test-plan}"
DOC_PATH="$DOCS_DIR/${ID}-${SLUG}.md"

if [[ -e "$DOC_PATH" ]]; then
  echo "Error: test plan already exists: $DOC_PATH" >&2
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
create_test_plan.sh
\`\`\`

## Scope

- <What is in scope / out of scope?>

## Test matrix

| Test ID | Level (unit/integration/e2e) | Target | Expected outcome |
|---|---|---|---|

## Acceptance scenarios

- GIVEN ... WHEN ... THEN ...

## Environment

- <Environments, data, tooling>

## Notes

- <Optional>
EOF

echo "Created test plan: $DOC_PATH"

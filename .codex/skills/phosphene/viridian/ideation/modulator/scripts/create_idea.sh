#!/usr/bin/env bash
set -euo pipefail

# create_idea.sh
# Create a new ideation artifact (IDEA-####).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./.codex/skills/phosphene/viridian/ideation/modulator/scripts/create_idea.sh --title "..." [--id IDEA-0001] [--status Draft] [--dependencies "RA-001,PER-0001"]
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
  ID="$("$ROOT/phosphene/phosphene-core/bin/phosphene" id next --type idea)"
fi

if ! [[ "$ID" =~ ^IDEA-[0-9]{4}$ ]]; then
  echo "Error: --id must look like IDEA-0001" >&2
  exit 2
fi

DOCS_DIR="$ROOT/phosphene/domains/ideation/output/ideas"
mkdir -p "$DOCS_DIR"

SLUG="$(slugify "$TITLE")"
SLUG="${SLUG:-idea}"
DOC_PATH="$DOCS_DIR/${ID}-${SLUG}.md"

if [[ -e "$DOC_PATH" ]]; then
  echo "Error: idea already exists: $DOC_PATH" >&2
  exit 1
fi

DATE="$(date -u +"%Y-%m-%d")"

cat > "$DOC_PATH" <<EOF
ID: ${ID}
IssueNumber: 
Title: ${TITLE}
Status: ${STATUS}
Updated: ${DATE}
Dependencies: ${DEPENDENCIES}

\`\`\`text
[V-SCRIPT]:
create_idea.sh
ideation_storm_table_bootstrap.sh
provide_next_storm_prompt.sh
ideation_storm_set_description.sh
\`\`\`

## Problem / opportunity

- <What problem or opportunity does this idea address?>

## Target user hypotheses

- <Who is this for? What role/context?>

## Next research questions

- <What must we validate in <research>?>

## Storm table

The storm table must enumerate **every unordered probe pair** × \`adjacent\` / \`orthogonal\` / \`extrapolatory\`,
using the \`seed_sha256\` + \`manifold_probe_count\` from the SPARK header.

Use the control scripts (do not hand-edit table rows).

| STORM-ID | PROBE_1 | PROBE_2 | RING | DESCRIPTION |
| --- | --- | --- | --- | --- |

## Revision passes

- Builder: <coherence pass notes>
- Critic: <gaps/contradictions found and fixed>

## Notes

- <Optional>
EOF

echo "Created idea: $DOC_PATH"

#!/usr/bin/env bash
set -euo pipefail

# create_issue_mirror.sh
# Create a new issue mirror artifact (ISSUE-###).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./.codex/skills/phosphene/amaranth/scrum-management/modulator/scripts/create_issue_mirror.sh --title "..." [--id ISSUE-001] [--status Open] [--source-url "https://..."]
EOF
}

slugify() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

ID=""
TITLE=""
STATUS="Open"
SOURCE_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) ID="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --status) STATUS="${2:-}"; shift 2 ;;
    --source-url) SOURCE_URL="${2:-}"; shift 2 ;;
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
DOCS_DIR="$ROOT/phosphene/domains/scrum-management/output/issues"
mkdir -p "$DOCS_DIR"

if [[ -z "${ID:-}" ]]; then
  last_num="$(ls "$DOCS_DIR" 2>/dev/null | grep -oE '^ISSUE-[0-9]{3}' | sed -E 's/^ISSUE-//' | sort -V | tail -n 1 || true)"
  last_num="${last_num:-000}"
  next_num=$((10#${last_num} + 1))
  ID="ISSUE-$(printf "%03d" "$next_num")"
fi

if ! [[ "$ID" =~ ^ISSUE-[0-9]{3}$ ]]; then
  echo "Error: --id must look like ISSUE-001" >&2
  exit 2
fi

SLUG="$(slugify "$TITLE")"
SLUG="${SLUG:-issue}"
DOC_PATH="$DOCS_DIR/${ID}-${SLUG}.md"

if [[ -e "$DOC_PATH" ]]; then
  echo "Error: issue mirror already exists: $DOC_PATH" >&2
  exit 1
fi

DATE="$(date -u +"%Y-%m-%d")"

cat > "$DOC_PATH" <<EOF
ID: ${ID}
Title: ${TITLE}
Status: ${STATUS}
Updated: ${DATE}
SourceURL: ${SOURCE_URL}

\`\`\`text
[V-SCRIPT]:
create_issue_mirror.sh
\`\`\`

## Summary

- <Short summary of the work>

## Scope

- <In scope / out of scope>

## Notes

- <Optional>
EOF

echo "Created issue mirror: $DOC_PATH"

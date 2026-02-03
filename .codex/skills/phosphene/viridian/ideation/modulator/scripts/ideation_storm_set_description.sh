#!/usr/bin/env bash
set -euo pipefail

# ideation_storm_set_description.sh
# Set the DESCRIPTION cell for a specific STORM-ID row in the storm table.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./.codex/skills/phosphene/viridian/ideation/modulator/scripts/ideation_storm_set_description.sh \
    --file <path/to/IDEA-####-*.md> \
    --storm-id STORM-#### \
    --description "Three-or-more sentences..."

Notes:
- Newlines in --description are converted to spaces.
- Minimum requirement: >= 3 sentence terminators (., !, ?) in the description.
EOF
}

IDEA_FILE=""
STORM_ID=""
DESCRIPTION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) IDEA_FILE="${2:-}"; shift 2 ;;
    --storm-id) STORM_ID="${2:-}"; shift 2 ;;
    --description) DESCRIPTION="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "${IDEA_FILE:-}" ]] || { echo "Error: --file is required" >&2; usage; exit 2; }
[[ -f "$IDEA_FILE" ]] || { echo "Error: file not found: $IDEA_FILE" >&2; exit 1; }
[[ -n "${STORM_ID:-}" ]] || { echo "Error: --storm-id is required" >&2; exit 2; }
[[ "$STORM_ID" =~ ^STORM-[0-9]+$ ]] || { echo "Error: --storm-id must look like STORM-0001" >&2; exit 2; }
[[ -n "${DESCRIPTION:-}" ]] || { echo "Error: --description is required" >&2; exit 2; }

normalize_one_line() {
  printf "%s" "$1" | tr '\r\n' '  ' | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//'
}

DESCRIPTION="$(normalize_one_line "$DESCRIPTION")"
[[ -n "${DESCRIPTION:-}" ]] || { echo "Error: description is empty after normalization" >&2; exit 2; }
if [[ "$DESCRIPTION" == *"|"* ]]; then
  echo "Error: description contains '|' which breaks markdown tables. Remove/replace it." >&2
  exit 2
fi

sent_count="$(printf "%s" "$DESCRIPTION" | awk '
  function sc(s){ c=0; for(i=1;i<=length(s);i++){ ch=substr(s,i,1); if(ch=="."||ch=="!"||ch=="?") c++; } return c; }
  { print sc($0)+0; }
')"
if [[ "${sent_count:-0}" -lt 3 ]]; then
  echo "Error: description must contain >= 3 sentences (found ${sent_count})" >&2
  exit 2
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

START_HEADING="## Storm table"
out_tmp="$tmp_dir/out.md"

awk -v start="$START_HEADING" -v storm="$STORM_ID" -v desc="$DESCRIPTION" '
  function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
  BEGIN{ in_section=0; updated=0; }
  $0==start { in_section=1; print; next }
  in_section && $0 ~ /^## / { in_section=0 }
  in_section && $0 ~ /^\|/ {
    n=split($0, a, /\|/);
    sid=trim(a[2]);
    if (sid==storm) {
      if (n < 7) { print "ERROR: malformed storm table row for " storm > "/dev/stderr"; exit 2 }
      a[6] = " " desc " ";
      line="|";
      for (i=2;i<=6;i++){ line=line a[i] "|"; }
      print line;
      updated=1;
      next
    }
  }
  { print }
  END{ if (updated==0) { print "ERROR: did not find STORM-ID row to update: " storm > "/dev/stderr"; exit 3 } }
' "$IDEA_FILE" > "$out_tmp"

mv "$out_tmp" "$IDEA_FILE"
echo "OK: updated description for ${STORM_ID} in: $IDEA_FILE"

#!/usr/bin/env bash
set -euo pipefail

# provide_next_storm_prompt.sh
# Print the next uncompleted storm row with a reminder command.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./.codex/skills/phosphene/viridian/ideation/modulator/scripts/provide_next_storm_prompt.sh \
    --file <path/to/IDEA-####-*.md>
EOF
}

IDEA_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) IDEA_FILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "${IDEA_FILE:-}" ]] || { echo "Error: --file is required" >&2; usage; exit 2; }
[[ -f "$IDEA_FILE" ]] || { echo "Error: file not found: $IDEA_FILE" >&2; exit 1; }

START_HEADING="## Storm table"

row="$(
  awk -v start="$START_HEADING" '
    function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
    BEGIN{ in_section=0; found=0; }
    $0==start { in_section=1; next }
    in_section && $0 ~ /^## / { in_section=0 }
    in_section && $0 ~ /^\|/ {
      n=split($0, a, /\|/);
      if (n < 7) next;
      sid=trim(a[2]);
      p1=trim(a[3]);
      p2=trim(a[4]);
      ring=trim(a[5]);
      desc=trim(a[6]);
      if (sid ~ /^STORM-/ && (desc=="" || desc ~ /^<.*>$/)) {
        print sid "\t" p1 "\t" p2 "\t" ring;
        found=1;
        exit 0;
      }
    }
    END{ if (found==0) exit 2 }
  ' "$IDEA_FILE"
)" || {
  echo "All storm rows appear complete."
  exit 0
}

IFS=$'\t' read -r storm_id probe_one probe_two ring <<< "$row"

echo "Next storm row:"
echo "STORM-ID: ${storm_id}"
echo "PROBE_1: ${probe_one}"
echo "PROBE_2: ${probe_two}"
echo "RING: ${ring}"
echo ""
echo "Use:"
echo "${SCRIPT_DIR}/ideation_storm_set_description.sh --file \"${IDEA_FILE}\" --storm-id \"${storm_id}\" --description \"<3+ sentence paragraph influenced by PROBE_1 + PROBE_2 + RING>\""

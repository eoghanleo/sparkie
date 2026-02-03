#!/usr/bin/env bash
#
# FR Creation Script
# Automates the creation of Feature Request XML files with proper structure and metadata
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"
phosphene_load_config

if [[ -t 1 ]]; then
  PHOSPHENE_GREEN='\033[38;5;118m'
  PHOSPHENE_BRIGHT='\033[38;5;154m'
  CYAN_GLOW='\033[38;5;51m'
  YELLOW_HAZARD='\033[38;5;226m'
  MAGENTA_PULSE='\033[38;5;201m'
  RESET='\033[0m'
else
  PHOSPHENE_GREEN='' PHOSPHENE_BRIGHT='' CYAN_GLOW='' YELLOW_HAZARD='' MAGENTA_PULSE='' RESET=''
fi

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

normalize_dep_id() {
  local raw
  raw="$(echo "$1" | xargs)"
  if [[ "$raw" =~ ^FR-([0-9]{1,})$ ]]; then printf "FR-%03d" "$((10#${BASH_REMATCH[1]}))"; return 0; fi
  if [[ "$raw" =~ ^FR([0-9]{1,})$ ]]; then printf "FR-%03d" "$((10#${BASH_REMATCH[1]}))"; return 0; fi
  if [[ "$raw" =~ ^([0-9]{1,})$ ]]; then printf "FR-%03d" "$((10#${BASH_REMATCH[1]}))"; return 0; fi
  echo "$raw"
}

title=""
description=""
priority="Medium"
dependencies=""
motivation=""
success_criteria=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title) title="$2"; shift 2 ;;
    --description) description="$2"; shift 2 ;;
    --priority) priority="$2"; shift 2 ;;
    --dependencies) dependencies="$2"; shift 2 ;;
    --motivation) motivation="$2"; shift 2 ;;
    --success-criteria) success_criteria="$2"; shift 2 ;;
    *)
      echo -e "${PHOSPHENE_GREEN}[${YELLOW_HAZARD}ERROR${PHOSPHENE_GREEN}]${RESET} Unknown parameter: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$title" || -z "$description" ]]; then
  echo -e "${PHOSPHENE_GREEN}[${YELLOW_HAZARD}ERROR${PHOSPHENE_GREEN}]${RESET} Title and description are required."
  exit 1
fi

FRS_DIR="$feature_management_path/frs"

mkdir -p "$FRS_DIR"

last_num="$(ls "$FRS_DIR" 2>/dev/null | grep -oE '^FR-[0-9]{3}' | sed -E 's/^FR-//' | sort -V | tail -n 1 || true)"
last_num="${last_num:-000}"
next_num=$((10#${last_num} + 1))
fr_id="FR-$(printf "%03d" "$next_num")"
slug="$(slugify "$title")"
slug="${slug:-feature}"

fr_file="$FRS_DIR/${fr_id}-${slug}.md"

# Bash-parseable header block (blank line terminates header)
{
  echo "ID: $fr_id"
  echo "Title: $title"
  echo "Status: Pending Approval"
  echo "Priority: $priority"
  echo "Updated: $(date -u +"%Y-%m-%d")"
  if [[ -n "$dependencies" ]]; then
    # Normalize deps to FR-XYZ and preserve comma-separated list
    IFS=',' read -ra DEPS <<< "$dependencies"
    norm=()
    for dep in "${DEPS[@]}"; do norm+=("$(normalize_dep_id "$dep")"); done
    echo "Dependencies: $(IFS=', '; echo "${norm[*]}")"
  else
    # Keep bash-parseable delimiter format even when empty (validator expects ": ").
    echo "Dependencies: "
  fi
  echo ""
  echo "## Description"
  echo "$description"
  echo ""
  echo "## Motivation"
  echo "${motivation:-TBD}"
  echo ""
  echo "## Success Criteria"
  if [[ -n "${success_criteria:-}" ]]; then
    echo "- $success_criteria"
  else
    echo "- TBD"
  fi
  echo ""
  echo "## Acceptance Tests"
  echo "- GIVEN ... WHEN ... THEN ..."
  echo ""
  echo "## Requirements"
  echo "- MUST/SHALL ..."
  echo ""
  echo "## Implementation Plan"
  echo "- [ ] Task 1"
  echo ""
  echo "## Lessons Learned"
  echo "- (fill during implementation)"
  echo ""
  echo "## History"
  echo "- $(date -u +"%Y-%m-%d") Created (Pending Approval)"
} > "$fr_file"

if [[ -x "$SCRIPT_DIR/update_backlog_tree.sh" ]]; then
  "$SCRIPT_DIR/update_backlog_tree.sh" || true
fi

echo -e "${PHOSPHENE_GREEN}[${PHOSPHENE_BRIGHT}OK${PHOSPHENE_GREEN}]${RESET} Created Feature Request: ${CYAN_GLOW}$fr_id${RESET}"
echo -e "${PHOSPHENE_GREEN}[${MAGENTA_PULSE}INFO${PHOSPHENE_GREEN}]${RESET} Location: ${PHOSPHENE_BRIGHT}$fr_file${RESET}"



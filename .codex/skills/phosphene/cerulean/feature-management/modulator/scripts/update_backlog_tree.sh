#!/usr/bin/env bash
#
# Generates phosphene/domains/feature-management/output/backlog_tree.md (bash-only)
# - Single-dir only: show status-grouped listing derived from FR markdown headers
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"
phosphene_load_config

BACKLOG_DIR="$feature_management_path"
TREE_FILE="$BACKLOG_DIR/backlog_tree.md"

require_cmd() {
  local c="$1"
  if ! command -v "$c" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

header() {
  local timestamp="$1"
  cat <<EOF
# Project PHOSPHENE — Backlog Overview

**IMPORTANT: This file is automatically maintained. Do not edit manually.**

Last Updated: $timestamp

EOF
}

render_status_listing() {
  local timestamp="$1"
  local statuses=("Pending Approval" "Approved" "In Progress" "Test Coverage" "Completed" "Passed" "Failed")
  local files
  files="$(find "$BACKLOG_DIR/frs" -type f -name "FR-*.md" 2>/dev/null | sort || true)"

  {
    header "$timestamp"
    echo "## Status Listing (derived from FR headers)"
    echo ""
    for s in "${statuses[@]}"; do
      echo "### $s"
      local any="false"
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        local status
        status="$(phosphene_fr_get_header "$f" "Status" 2>/dev/null || echo "")"
        if [[ "$status" == "$s" ]]; then
          local id name
          id="$(phosphene_fr_get_header "$f" "ID" 2>/dev/null || echo "")"
          name="$(phosphene_fr_get_header "$f" "Title" 2>/dev/null || echo "")"
          # Avoid markdown backticks here; they are brittle in bash strings and can trigger command substitution.
          printf -- "- **%s**: %s (%s)\n" "$id" "$name" "$(basename "$f")"
          any="true"
        fi
      done <<< "$files"
      [[ "$any" == "false" ]] && echo "- _(none)_"
      echo ""
    done
  } > "$TREE_FILE"
}

main() {
  local timestamp
  timestamp="$(date "+%Y-%m-%d %H:%M:%S")"
  render_status_listing "$timestamp"

  echo "Successfully updated $TREE_FILE"
}

main



#!/usr/bin/env bash
#
# Approve Feature Request helper.
# Moves/updates an FR to "Approved" status.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_config.sh"
phosphene_load_config

BACKLOG_DIR="$feature_management_path"

print_usage() {
  echo "Usage:"
  echo "  $(basename "$0") --id FR-001"
  echo "  $(basename "$0") /path/to/FR-001-some-title.md"
}

find_fr_file_by_id() {
  local fr_id="$1"
  find "$BACKLOG_DIR" -type f -name "${fr_id}*.md" 2>/dev/null | sort | head -n 1
}

fr_id=""
fr_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) print_usage; exit 0 ;;
    --id) fr_id="$2"; shift 2 ;;
    *) fr_file="$1"; shift ;;
  esac
done

if [[ -z "$fr_file" && -z "$fr_id" ]]; then
  print_usage
  exit 1
fi

if [[ -z "$fr_file" && -n "$fr_id" ]]; then
  fr_file="$(find_fr_file_by_id "$fr_id")"
fi

if [[ -z "$fr_file" || ! -f "$fr_file" ]]; then
  echo "Error: FR file not found." 1>&2
  exit 1
fi

"$SCRIPT_DIR/update_feature_request_status.sh" "$fr_file" "Approved"



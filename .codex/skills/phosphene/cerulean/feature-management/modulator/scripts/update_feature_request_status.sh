#!/usr/bin/env bash
#
# FR Status Update Script (git-friendly optional mode)
# - Updates Status + Updated headers
# - Appends a History entry
# - Optionally moves the file between status directories (status_dirs layout)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"
phosphene_load_config

BACKLOG_DIR="$feature_management_path"

VALID_STATUSES=("Pending Approval" "Approved" "In Progress" "Test Coverage" "Completed" "Passed" "Failed")

print_usage() {
  echo "Usage: $(basename "$0") <fr_file> <new_status>"
}

check_required_tools() {
  for c in awk sed grep date mv; do
    if ! command -v "$c" >/dev/null 2>&1; then
      echo "Error: missing required command: $c" 1>&2
      exit 1
    fi
  done
}

get_status_directory() {
  local status="$1"
  case "$status" in
    "Pending Approval") echo "1-pending-approval" ;;
    "Approved") echo "2-approved" ;;
    "In Progress") echo "3-in-progress" ;;
    "Test Coverage") echo "4-test-coverage" ;;
    "Completed") echo "5-completed" ;;
    "Passed") echo "6-passed" ;;
    "Failed") echo "7-failed" ;;
    *) echo "unknown" ;;
  esac
}

validate_status() {
  local status="$1"
  for s in "${VALID_STATUSES[@]}"; do
    [[ "$status" == "$s" ]] && return 0
  done
  echo "Error: Invalid status '$status'." 1>&2
  exit 1
}

get_current_status() { phosphene_fr_get_header "$1" "Status" 2>/dev/null || echo ""; }
get_fr_title() { phosphene_fr_get_header "$1" "Title" 2>/dev/null || echo ""; }

append_history_entry() {
  local fr_file="$1"
  local old_status="$2"
  local new_status="$3"
  local ts
  ts="$(date -u +"%Y-%m-%d")"

  # Ensure History section exists; if not, append it.
  if ! grep -q "^## History$" "$fr_file"; then
    {
      echo ""
      echo "## History"
    } >> "$fr_file"
  fi

  printf -- "- %s Status: %s -> %s\n" "$ts" "$old_status" "$new_status" >> "$fr_file"
}

update_fr_status_fields() {
  local fr_file="$1"
  local new_status="$2"
  phosphene_fr_set_header "$fr_file" "Status" "$new_status"
  phosphene_fr_set_header "$fr_file" "Updated" "$(date -u +"%Y-%m-%d")"
}

positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done
# Bash 3.2 + `set -u`: expanding an empty array can error as "unbound variable".
# Avoid `set -- "${positional[@]}"` and instead read indices with safe defaults.
fr_file="${positional[0]-}"
new_status="${positional[1]-}"
extra_arg="${positional[2]-}"

if [[ -n "$extra_arg" ]]; then
  print_usage
  exit 1
fi
if [[ -z "$fr_file" || -z "$new_status" ]]; then
  print_usage
  exit 1
fi

check_required_tools

if [[ ! "$fr_file" = /* ]]; then
  fr_file="$PWD/$fr_file"
fi

if [[ ! -f "$fr_file" ]]; then
  echo "Error: FR file not found: $fr_file" 1>&2
  exit 1
fi

validate_status "$new_status"

current_status="$(get_current_status "$fr_file")"
if [[ "$current_status" == "$new_status" ]]; then
  echo "FR already in '$new_status' status. No changes."
  exit 0
fi

fr_title="$(get_fr_title "$fr_file")"
echo "Updating FR '$fr_title' status from '$current_status' to '$new_status'..."

update_fr_status_fields "$fr_file" "$new_status"
append_history_entry "$fr_file" "$current_status" "$new_status"

if [[ -x "$SCRIPT_DIR/update_backlog_tree.sh" ]]; then
  "$SCRIPT_DIR/update_backlog_tree.sh" || true
fi

echo "FR status update complete."



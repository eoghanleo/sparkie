#!/usr/bin/env bash
#
# FR Validation Script (bash-only)
# Validates Feature Request Markdown files adhere to the required header format.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"
phosphene_load_config

BACKLOG_DIR="$feature_management_path"

if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' RESET=''
fi

print_usage() {
  echo "Usage: $(basename "$0") [OPTIONS] [FILE|DIRECTORY]"
  echo ""
  echo "Options:"
  echo "  -h, --help    Show help"
  echo "  -v, --verbose Verbose output"
  echo "  -q, --quiet   Quiet output"
  echo "  -s, --strict  Strict content checks"
}

check_required_tools() {
  for c in awk sed grep find; do
    if ! command -v "$c" >/dev/null 2>&1; then
      echo -e "${RED}Error: missing required command: $c${RESET}"
      exit 1
    fi
  done
}

find_fr_files() {
  local dir="$1"
  find "$dir" -type f -name "FR-*.md" | sort
}

validate_required_headers() {
  local file="$1"
  local verbose="$2"
  local required=("ID" "Title" "Status" "Priority" "Updated" "Dependencies")
  local error_count=0

  for k in "${required[@]}"; do
    if ! grep -q "^${k}: " "$file"; then
      echo -e "${RED}✗ Missing header: ${k}:${RESET}"
      error_count=$((error_count + 1))
    elif [[ "$verbose" == "true" ]]; then
      echo -e "${GREEN}✓ Header present: ${k}${RESET}"
    fi
  done

  [[ "$error_count" -eq 0 ]]
}

validate_status_value() {
  local file="$1"
  local status
  status="$(phosphene_fr_get_header "$file" "Status" 2>/dev/null || echo "")"
  local valid_statuses=("Pending Approval" "Approved" "In Progress" "Test Coverage" "Completed" "Passed" "Failed")
  for s in "${valid_statuses[@]}"; do
    [[ "$status" == "$s" ]] && return 0
  done
  echo -e "${RED}✗ Invalid status value: '$status'${RESET}"
  return 1
}

validate_priority_value() {
  local file="$1"
  local p
  p="$(phosphene_fr_get_header "$file" "Priority" 2>/dev/null || echo "")"
  local valid=("High" "Medium" "Low")
  for x in "${valid[@]}"; do
    [[ "$p" == "$x" ]] && return 0
  done
  echo -e "${RED}✗ Invalid priority value: '$p'${RESET}"
  return 1
}

validate_id_matches_filename() {
  local file="$1"
  local filename
  filename="$(basename "$file")"
  local filename_id
  filename_id="$(echo "$filename" | grep -oE "FR-[0-9]{3}" | head -n 1 || true)"
  local fr_id
  fr_id="$(phosphene_fr_get_header "$file" "ID" 2>/dev/null || echo "")"
  [[ -n "$filename_id" && "$fr_id" == "$filename_id" ]]
}

validate_content_not_empty() {
  local file="$1"
  local required=("ID" "Title" "Status" "Priority" "Updated")
  local error_count=0
  for k in "${required[@]}"; do
    local v
    v="$(phosphene_fr_get_header "$file" "$k" 2>/dev/null | sed -e 's/^ *//; s/ *$//' || true)"
    if [[ -z "$v" ]]; then
      echo -e "${RED}✗ Required header empty: ${k}${RESET}"
      error_count=$((error_count + 1))
    fi
  done
  [[ "$error_count" -eq 0 ]]
}

validate_fr_file() {
  local file="$1"
  local verbose="$2"
  local strict="$3"
  local quiet="$4"

  local filename
  filename="$(basename "$file")"
  [[ "$quiet" != "true" ]] && {
    echo -e "${BLUE}===============================================${RESET}"
    echo -e "${BLUE}Validating: ${filename}${RESET}"
    echo -e "${BLUE}===============================================${RESET}"
  }

  local failed="false"
  validate_required_headers "$file" "$verbose" || failed="true"
  validate_status_value "$file" || failed="true"
  validate_priority_value "$file" || failed="true"
  validate_id_matches_filename "$file" || failed="true"
  if [[ "$strict" == "true" ]]; then
    validate_content_not_empty "$file" || failed="true"
  fi

  if [[ "$failed" == "true" ]]; then
    [[ "$quiet" != "true" ]] && echo -e "${RED}✗ Validation FAILED for ${filename}${RESET}"
    return 1
  fi
  [[ "$quiet" != "true" ]] && echo -e "${GREEN}✓ Validation PASSED for ${filename}${RESET}"
  return 0
}

main() {
  local verbose=false
  local strict=false
  local quiet=false
  local target=""

  local -a positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) print_usage; exit 0 ;;
      -v|--verbose) verbose=true; shift ;;
      -s|--strict) strict=true; shift ;;
      -q|--quiet) quiet=true; shift ;;
      -*) echo -e "${RED}Error: Unknown option: $1${RESET}"; exit 1 ;;
      *) positional+=("$1"); shift ;;
    esac
  done

  check_required_tools

  # Bash 3.2 + `set -u`: empty arrays can behave like "unbound" when expanded.
  # Avoid `set -- "${positional[@]}"` and read from indices with safe defaults.
  local target_arg="${positional[0]-}"
  local extra_arg="${positional[1]-}"
  if [[ -n "$extra_arg" ]]; then
    echo -e "${RED}Error: too many arguments (expected at most 1 target path)${RESET}"
    print_usage
    exit 1
  fi
  if [[ -n "$target_arg" ]]; then
    target="$target_arg"
  else
    target="$BACKLOG_DIR"
  fi

  local files=()
  if [[ -f "$target" ]]; then
    files=("$target")
  elif [[ -d "$target" ]]; then
    while IFS= read -r line; do files+=("$line"); done < <(find_fr_files "$target")
  else
    echo -e "${RED}Error: Target not found: $target${RESET}"
    exit 1
  fi

  if [[ "${#files[@]}" -eq 0 ]]; then
    echo -e "${YELLOW}Warning: No FR markdown files found in: $target${RESET}"
    exit 0
  fi

  local pass=0
  local fail=0
  for f in "${files[@]}"; do
    if validate_fr_file "$f" "$verbose" "$strict" "$quiet"; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
    fi
    [[ "$quiet" != "true" && "${#files[@]}" -gt 1 ]] && echo ""
  done

  echo -e "${BLUE}===============================================${RESET}"
  echo -e "${BLUE}Validation Summary${RESET}"
  echo -e "${BLUE}===============================================${RESET}"
  echo -e "Total files checked: ${#files[@]}"
  echo -e "${GREEN}Passed: ${pass}${RESET}"
  echo -e "${RED}Failed: ${fail}${RESET}"

  [[ "$fail" -eq 0 ]]
}

main "$@"



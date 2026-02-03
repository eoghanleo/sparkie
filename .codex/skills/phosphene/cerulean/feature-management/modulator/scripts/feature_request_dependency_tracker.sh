#!/usr/bin/env bash
#
# FR Dependency Tracker Script
# Analyzes and visualizes dependencies between Feature Requests.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"
phosphene_load_config

BACKLOG_DIR="$feature_management_path"
DEPENDENCY_FILE="$BACKLOG_DIR/fr_dependencies.md"
TEMP_DIR="/tmp/phosphene_fr_dependencies"

if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  MAGENTA='\033[0;35m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA='' RESET=''
fi

print_usage() {
  echo "Usage: $(basename "$0") [OPTIONS]"
  echo "  -o, --output FILE     Output file (default: fr_dependencies.md)"
  echo "  -f, --format FORMAT   tree|matrix|list (default: tree)"
  echo "  -r, --reverse         Reverse dependencies"
  echo "  -c, --check-circular  Only check for circular deps"
}

check_required_tools() {
  for c in awk sed grep find; do
    if ! command -v "$c" >/dev/null 2>&1; then
      echo -e "${RED}Error: missing required command: $c${RESET}"
      exit 1
    fi
  done
}

cleanup_temp_dir() {
  [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR" || true
}

create_temp_dir() {
  cleanup_temp_dir
  mkdir -p "$TEMP_DIR"
}

get_fr_id_from_filename() {
  local filename
  filename="$(basename "$1")"
  echo "$filename" | grep -oE "FR-[0-9]{3}" | head -n 1 || true
}

get_fr_name() {
  phosphene_fr_get_header "$1" "Title" 2>/dev/null || echo "Unknown"
}

get_fr_status() {
  phosphene_fr_get_header "$1" "Status" 2>/dev/null || echo "Unknown"
}

find_fr_dependencies() {
  local fr_file="$1"
  local fr_id
  fr_id="$(get_fr_id_from_filename "$fr_file")"
  local dep_file="$TEMP_DIR/${fr_id}_dependencies.txt"

  local deps
  deps="$(phosphene_fr_get_header "$fr_file" "Dependencies" 2>/dev/null || true)"
  if [[ -n "$deps" ]]; then
    echo "$deps" \
      | tr ',' '\n' \
      | sed -E 's/^ *//; s/ *$//' \
      | grep -E '^FR-[0-9]{3}$' \
      | grep -v '^FR-000$' \
      | sort -u > "$dep_file" || true
  else
    : > "$dep_file"
  fi

  # remove self
  [[ -n "$fr_id" ]] && grep -v "^$fr_id$" "$dep_file" > "${dep_file}.tmp" 2>/dev/null || true
  [[ -f "${dep_file}.tmp" ]] && mv "${dep_file}.tmp" "$dep_file"

  echo "$dep_file"
}

extract_all_dependencies() {
  find "$BACKLOG_DIR/frs" -type f -name "FR-*.md" | while read -r fr_file; do
    local fr_id
    fr_id="$(get_fr_id_from_filename "$fr_file")"
    [[ -z "$fr_id" ]] && continue
    local name status
    name="$(get_fr_name "$fr_file")"
    status="$(get_fr_status "$fr_file")"
    echo "$fr_id|$name|$status" > "$TEMP_DIR/${fr_id}_meta.txt"
    find_fr_dependencies "$fr_file" >/dev/null
  done
}

check_circular_dependencies() {
  local adjacency="$TEMP_DIR/adjacency.txt"
  : > "$adjacency"
  for dep_file in "$TEMP_DIR"/FR-*_dependencies.txt; do
    [[ -f "$dep_file" && -s "$dep_file" ]] || continue
    local fr_id
    fr_id="$(basename "$dep_file" | cut -d'_' -f1)"
    while read -r dep; do
      [[ -n "$dep" ]] && echo "$fr_id $dep" >> "$adjacency"
    done < "$dep_file"
  done

  # Return non-zero when there is nothing to check (no edges => no cycles).
  # This function's contract is: exit 0 => circular dependencies found.
  [[ ! -s "$adjacency" ]] && return 1

  local circular="$TEMP_DIR/circular.txt"
  : > "$circular"

  # naive cycle check: report A->B and B->A as a 2-cycle
  while read -r a b; do
    if grep -q "^$b $a$" "$adjacency"; then
      echo "$a <-> $b" >> "$circular"
    fi
  done < "$adjacency"

  sort -u "$circular" -o "$circular" 2>/dev/null || true
  [[ -s "$circular" ]]
}

generate_tree() {
  local output="$1"
  local reverse="$2"
  local timestamp
  timestamp="$(date "+%Y-%m-%d %H:%M:%S")"

  {
    echo "# Project PHOSPHENE Feature Request Dependencies"
    echo ""
    echo "**IMPORTANT: This file is automatically maintained. Do not edit manually.**"
    echo ""
    echo "Last Updated: $timestamp"
    echo ""
    echo '```'
    if [[ "$reverse" == "true" ]]; then
      # build reverse map
      local rev="$TEMP_DIR/rev.txt"
      : > "$rev"
      for dep_file in "$TEMP_DIR"/FR-*_dependencies.txt; do
        [[ -f "$dep_file" && -s "$dep_file" ]] || continue
        local fr_id
        fr_id="$(basename "$dep_file" | cut -d'_' -f1)"
        while read -r dep; do
          [[ -n "$dep" ]] && echo "$dep $fr_id" >> "$rev"
        done < "$dep_file"
      done
      sort -u "$rev" -o "$rev" 2>/dev/null || true

      find "$TEMP_DIR" -name "FR-*_meta.txt" | sort | while read -r meta; do
        local fr_id
        fr_id="$(basename "$meta" | cut -d'_' -f1)"
        local fr_data name status
        fr_data="$(cat "$meta")"
        name="$(echo "$fr_data" | cut -d'|' -f2)"
        status="$(echo "$fr_data" | cut -d'|' -f3)"
        echo "$fr_id - $name ($status)"
        if grep -q "^$fr_id " "$rev" 2>/dev/null; then
          grep "^$fr_id " "$rev" | awk '{print $2}' | while read -r dep; do
            echo "  └── $dep"
          done
        else
          echo "  └── (none)"
        fi
        echo ""
      done
    else
      find "$TEMP_DIR" -name "FR-*_meta.txt" | sort | while read -r meta; do
        local fr_id
        fr_id="$(basename "$meta" | cut -d'_' -f1)"
        local fr_data name status
        fr_data="$(cat "$meta")"
        name="$(echo "$fr_data" | cut -d'|' -f2)"
        status="$(echo "$fr_data" | cut -d'|' -f3)"
        local dep_file="$TEMP_DIR/${fr_id}_dependencies.txt"
        echo "$fr_id - $name ($status)"
        if [[ -f "$dep_file" && -s "$dep_file" ]]; then
          while read -r dep; do
            echo "  └── $dep"
          done < "$dep_file"
        else
          echo "  └── (none)"
        fi
        echo ""
      done
    fi
    echo '```'
  } > "$output"
}

main() {
  local OUTPUT_FILE="$DEPENDENCY_FILE"
  local FORMAT="tree"
  local REVERSE="false"
  local CHECK_ONLY="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) print_usage; exit 0 ;;
      -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
      -f|--format) FORMAT="$2"; shift 2 ;;
      -r|--reverse) REVERSE="true"; shift ;;
      -c|--check-circular) CHECK_ONLY="true"; shift ;;
      *) echo -e "${RED}Error: unknown option $1${RESET}"; exit 1 ;;
    esac
  done

  check_required_tools
  create_temp_dir
  extract_all_dependencies

  local circular="false"
  if check_circular_dependencies; then
    circular="true"
  fi

  if [[ "$CHECK_ONLY" == "true" ]]; then
    cleanup_temp_dir
    [[ "$circular" == "true" ]] && exit 1 || exit 0
  fi

  case "$FORMAT" in
    tree) generate_tree "$OUTPUT_FILE" "$REVERSE" ;;
    matrix|list)
      echo -e "${YELLOW}Format '$FORMAT' not implemented in drop-in version yet (tree is).${RESET}" 1>&2
      generate_tree "$OUTPUT_FILE" "$REVERSE"
      ;;
    *)
      echo -e "${RED}Error: invalid format: $FORMAT${RESET}" 1>&2
      exit 1
      ;;
  esac

  cleanup_temp_dir

  [[ "$circular" == "true" ]] && exit 1 || exit 0
}

trap cleanup_temp_dir EXIT
main "$@"



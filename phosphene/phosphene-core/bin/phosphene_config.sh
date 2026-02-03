#!/usr/bin/env bash
#
# PHOSPHENE config helper (bash-only, flat YAML)
#
# Reads config values from phosphene/config/<color>.yml using flat "key: value" pairs.
#
set -euo pipefail

CONFIG_DIR_DEFAULT="phosphene/config"

usage() {
  cat <<'EOF'
PHOSPHENE CONFIG

Usage:
  ./phosphene/phosphene-core/bin/phosphene_config.sh get --color <color> --key <key> [--default <value>]
  ./phosphene/phosphene-core/bin/phosphene_config.sh get --file <path> --key <key> [--default <value>]

Notes:
  - Files are flat YAML: "key: value" (no nesting).
  - Lines starting with "#" are ignored.
EOF
}

trim() {
  printf "%s" "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

strip_quotes() {
  local v="$1"
  v="${v%\"}"
  v="${v#\"}"
  v="${v%\'}"
  v="${v#\'}"
  printf "%s" "$v"
}

get_value() {
  local file="$1"
  local key="$2"
  local default="${3:-}"

  if [[ ! -f "$file" ]]; then
    if [[ -n "${default:-}" ]]; then
      printf "%s\n" "$default"
      return 0
    fi
    echo "PHOSPHENE: missing config file: $file" >&2
    return 2
  fi

  local line trimmed k v
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    line="${line%%$'\r'}"
    trimmed="$(trim "$line")"
    [[ -n "${trimmed:-}" ]] || continue
    [[ "$trimmed" == \#* ]] && continue
    [[ "$trimmed" == *:* ]] || continue

    k="${trimmed%%:*}"
    v="${trimmed#*:}"
    k="$(trim "$k")"
    v="$(trim "$v")"
    v="$(printf "%s" "$v" | sed -E 's/[[:space:]]+#.*$//')"
    v="$(trim "$v")"
    v="$(strip_quotes "$v")"

    if [[ "$k" == "$key" ]]; then
      printf "%s\n" "$v"
      return 0
    fi
  done < "$file"

  if [[ -n "${default:-}" ]]; then
    printf "%s\n" "$default"
    return 0
  fi

  echo "PHOSPHENE: missing key '$key' in $file" >&2
  return 3
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  get)
    color=""
    file=""
    key=""
    default=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --color) color="${2:-}"; shift 2 ;;
        --file) file="${2:-}"; shift 2 ;;
        --key) key="${2:-}"; shift 2 ;;
        --default) default="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
      esac
    done

    if [[ -z "${file:-}" ]]; then
      [[ -n "${color:-}" ]] || { echo "Missing --color (or --file)" >&2; exit 2; }
      file="${CONFIG_DIR_DEFAULT}/${color}.yml"
    fi
    [[ -n "${key:-}" ]] || { echo "Missing --key" >&2; exit 2; }

    get_value "$file" "$key" "$default"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 2
    ;;
esac


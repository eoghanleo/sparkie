#!/usr/bin/env bash
#
# PHOSPHENE signal bus utilities (JSONL, v1)
#
# Contract:
# - Signals are stored as JSONL lines in:
#     phosphene/signals/bus.jsonl
# - The bus is append-only by convention (detectors enforce in PRs).
# - Each line must include:
#     "tamper_hash": "sha256:<64hex>"
#   computed over the line bytes with the tamper_hash hex normalized to the
#   placeholder (all-zero hex), i.e. the same convention as file tamper hashing,
#   but scoped to one JSONL record.
#
# Notes:
# - Bash-only: no jq/python.
# - We treat the JSONL line as an opaque byte string (except for the tamper_hash
#   normalization); if you change whitespace/ordering you must update tamper_hash.
#
set -euo pipefail

fail() { echo "PHOSPHENE: $*" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAMPER_IMPL="$SCRIPT_DIR/signal_tamper_hash.sh"

BUS_DEFAULT="phosphene/signals/bus.jsonl"

usage() {
  cat <<'EOF'
PHOSPHENE SIGNAL BUS (JSONL)

Usage:
  ./phosphene/phosphene-core/bin/signal_bus.sh append   [--bus <path>] --line <json_line>
  ./phosphene/phosphene-core/bin/signal_bus.sh validate [--bus <path>]

Notes:
  - append will ensure tamper_hash exists and is correct, then append exactly one line.
  - validate checks tamper_hash on every non-empty line.
EOF
}

require_file() {
  local f="$1"
  [[ -n "${f:-}" ]] || fail "missing file path"
  [[ -f "$f" ]] || fail "missing file: $f"
}

require_bus_parent_dir() {
  local bus="$1"
  local dir
  dir="$(cd "$(dirname "$bus")" && pwd)" || fail "invalid bus parent dir: $bus"
  [[ -d "$dir" ]] || fail "missing bus parent dir: $dir"
}

is_single_line_json_objectish() {
  local line="$1"
  [[ "$line" != *$'\n'* ]] || return 1
  [[ "$line" != *$'\r'* ]] || return 1
  [[ "$line" == \{* ]] || return 1
  [[ "$line" == *\} ]] || return 1
  return 0
}

ensure_tamper_field_present() {
  # If tamper_hash is missing, insert a placeholder field before the final '}'.
  # We do not attempt to parse JSON; we rely on the record being a single-line object.
  local line="$1"
  if [[ "$line" =~ \"tamper_hash\"[[:space:]]*:[[:space:]]*\"sha256:[0-9A-Fa-f]{64}\" ]]; then
    printf "%s" "$line"
    return 0
  fi
  local ph="0000000000000000000000000000000000000000000000000000000000000000"
  # Insert before the final '}'.
  local prefix
  prefix="$(printf "%s" "$line" | sed -E 's/}[[:space:]]*$//')"
  printf "%s" "$prefix"
  printf "%s" ",\"tamper_hash\":\"sha256:${ph}\"}"
}

update_line_tamper_hash() {
  local line="$1"
  local with_field
  with_field="$(ensure_tamper_field_present "$line")"
  local expected
  expected="$(bash "$TAMPER_IMPL" compute-line "$with_field")"
  local expected_hex="${expected#sha256:}"
  # Replace the tamper hex with expected.
  printf "%s" "$with_field" | sed -E 's/("tamper_hash"[[:space:]]*:[[:space:]]*"sha256:)[0-9A-Fa-f]{64}(")/\1'"$expected_hex"'\2/'
}

cmd_append() {
  local bus="$BUS_DEFAULT"
  local line=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bus) bus="${2:-}"; shift 2 ;;
      --line) line="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) fail "unknown arg: $1" ;;
    esac
  done

  [[ -n "${line:-}" ]] || fail "missing --line"
  is_single_line_json_objectish "$line" || fail "line must be a single-line JSON object"
  require_bus_parent_dir "$bus"

  if [[ ! -f "$TAMPER_IMPL" ]]; then
    fail "missing tamper hash implementation: $TAMPER_IMPL"
  fi

  local updated
  updated="$(update_line_tamper_hash "$line")"

  # Append newline-delimited record.
  printf "%s\n" "$updated" >> "$bus"
}

cmd_validate() {
  local bus="$BUS_DEFAULT"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bus) bus="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) fail "unknown arg: $1" ;;
    esac
  done

  require_file "$bus"
  if [[ ! -f "$TAMPER_IMPL" ]]; then
    fail "missing tamper hash implementation: $TAMPER_IMPL"
  fi

  local fail_count=0
  local n=0
  local line
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    n=$((n + 1))
    [[ -n "${line:-}" ]] || continue
    if ! bash "$TAMPER_IMPL" validate-line "$line" >/dev/null 2>&1; then
      echo "FAIL: bus tamper hash invalid (line $n): $bus" >&2
      fail_count=$((fail_count + 1))
    fi
  done < "$bus"

  [[ "$fail_count" -eq 0 ]]
}

CMD="${1:-help}"
shift || true
case "$CMD" in
  append) cmd_append "$@" ;;
  validate) cmd_validate "$@" ;;
  help|-h|--help) usage; exit 0 ;;
  *) fail "unknown command: $CMD" ;;
esac


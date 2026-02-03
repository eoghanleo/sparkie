#!/usr/bin/env bash
#
# PHOSPHENE signal hash utilities (v1)
#
# Purpose:
# - Compute stable, collision-resistant IDs for signals in a monotonic DAG.
# - Keep dependencies minimal (bash + core utils).
#
# ID scheme:
#   parents_root = sha256("phosphene/parents/v1\n" + join(sorted(parents), "\n"))
#   signal_id    = sha256("phosphene/signal/v1\n" + parents_root + "\n" + run_marker + "\n" + output_key)
#
set -euo pipefail

hash_sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    # prints: "(stdin)= <hex>"
    openssl dgst -sha256 | awk '{print $2}'
    return 0
  fi
  echo "PHOSPHENE: no SHA-256 tool found (need sha256sum, shasum, or openssl)" 1>&2
  return 1
}

parents_root() {
  # parents are provided as args; can be empty
  local pre="phosphene/parents/v1"$'\n'
  {
    printf "%s" "$pre"
    if [[ "$#" -gt 0 ]]; then
      printf "%s\n" "$@" | LC_ALL=C sort
    fi
  } | hash_sha256_hex
}

signal_id() {
  local run_marker=""
  local output_key=""
  local parents=()

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --run-marker) run_marker="${2:-}"; shift 2 ;;
      --output-key) output_key="${2:-}"; shift 2 ;;
      --parent) parents+=("${2:-}"); shift 2 ;;
      -h|--help)
        cat <<'EOF'
Usage:
  ./phosphene/phosphene-core/bin/signal_hash.sh parents-root [PARENT_ID ...]
  ./phosphene/phosphene-core/bin/signal_hash.sh signal-id --run-marker <marker> --output-key <key> [--parent <PARENT_ID>]...

Examples:
  ./phosphene/phosphene-core/bin/signal_hash.sh parents-root
  ./phosphene/phosphene-core/bin/signal_hash.sh signal-id --run-marker RA-001 --output-key handoff:research->product-marketing
EOF
        return 0
        ;;
      *)
        echo "Unknown arg: $1" 1>&2
        return 2
        ;;
    esac
  done

  if [[ -z "${run_marker}" ]]; then
    echo "Missing --run-marker" 1>&2
    return 2
  fi
  if [[ -z "${output_key}" ]]; then
    echo "Missing --output-key" 1>&2
    return 2
  fi

  local pr
  if [[ "${#parents[@]}" -gt 0 ]]; then
    pr="$(parents_root "${parents[@]}")"
  else
    pr="$(parents_root)"
  fi
  local pre="phosphene/signal/v1"$'\n'
  local hex
  hex="$(
    {
      printf "%s" "$pre"
      printf "%s\n" "$pr"
      printf "%s\n" "$run_marker"
      printf "%s" "$output_key"
    } | hash_sha256_hex
  )"
  printf "sha256:%s\n" "$hex"
}

cmd="${1:-help}"
shift || true
case "$cmd" in
  parents-root) parents_root "$@" ;;
  signal-id) signal_id "$@" ;;
  help|-h|--help) signal_id --help ;;
  *)
    echo "Unknown command: $cmd" 1>&2
    signal_id --help
    exit 2
    ;;
esac


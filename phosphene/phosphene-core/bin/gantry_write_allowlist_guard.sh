#!/usr/bin/env bash
#
# PHOSPHENE gantry write allowlist guard (bash-only)
#
# Purpose:
# - Gantries may write to the repo, but only within a strict allowlist.
# - This helper fails fast if the working tree contains changes outside allowed paths.
#
# Typical use (in a workflow that writes commits):
#   export PHOSPHENE_GANTRY_WRITE_ALLOWLIST=$'phosphene/signals/**\nphosphene/signals/indexes/**'
#   bash phosphene/phosphene-core/bin/gantry_write_allowlist_guard.sh check
#
set -euo pipefail

fail() { echo "PHOSPHENE: $*" >&2; exit 2; }

usage() {
  cat <<'EOF'
Usage:
  gantry_write_allowlist_guard.sh check
  gantry_write_allowlist_guard.sh check --allow <glob> [--allow <glob>]...

Env:
  PHOSPHENE_GANTRY_WRITE_ALLOWLIST
    Newline-delimited list of allowed path globs (bash-style globs).
EOF
}

ALLOWLIST=()

push_allowlist_from_env() {
  local raw="${PHOSPHENE_GANTRY_WRITE_ALLOWLIST:-}"
  [[ -n "${raw:-}" ]] || return 0
  while IFS= read -r line; do
    [[ -n "${line:-}" ]] || continue
    ALLOWLIST+=("$line")
  done <<< "$raw"
}

path_allowed() {
  local p="$1"
  local g
  for g in "${ALLOWLIST[@]:-}"; do
    if [[ "$p" == $g ]]; then
      return 0
    fi
  done
  return 1
}

collect_changed_paths() {
  # Includes staged, unstaged, and untracked (but not ignored).
  git status --porcelain=v1 \
    | awk '{print $2}' \
    | sed -E 's#^\"(.*)\"$#\\1#' \
    | LC_ALL=C sort -u
}

cmd_check() {
  [[ "${#ALLOWLIST[@]}" -gt 0 ]] || fail "no allowlist configured (set PHOSPHENE_GANTRY_WRITE_ALLOWLIST or pass --allow)"

  local changed=()
  while IFS= read -r p; do
    [[ -n "${p:-}" ]] || continue
    changed+=("$p")
  done < <(collect_changed_paths)

  if [[ "${#changed[@]}" -eq 0 ]]; then
    return 0
  fi

  local bad=0
  local p
  for p in "${changed[@]}"; do
    if ! path_allowed "$p"; then
      echo "FAIL: gantry attempted to modify disallowed path: $p" >&2
      bad=1
    fi
  done

  if [[ "$bad" -ne 0 ]]; then
    echo "" >&2
    echo "Allowed globs:" >&2
    printf "  - %s\n" "${ALLOWLIST[@]}" >&2
    exit 1
  fi
}

CMD="${1:-help}"
shift || true
case "$CMD" in
  check)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --allow) ALLOWLIST+=("${2:-}"); shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) fail "unknown arg: $1" ;;
      esac
    done
    push_allowlist_from_env
    cmd_check
    ;;
  help|-h|--help) usage ;;
  *) fail "unknown command: $CMD" ;;
esac


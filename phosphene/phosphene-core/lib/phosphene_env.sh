#!/usr/bin/env bash
#
# PHOSPHENE bash-only primitives:
# - Project root discovery
# - Environment construction from canonical repo layout (hard requirement: ./phosphene at repo root)
# - Simple key/value header parsing for FR markdown files
#
set -euo pipefail

phosphene__err() { echo "PHOSPHENE: $*" 1>&2; }

phosphene_find_project_root() {
  local dir="${PWD}"
  while [[ "$dir" != "/" ]]; do
    # Hard requirement: PHOSPHENE drop-in folder must exist at repo root.
    if [[ -d "$dir/phosphene" && -f "$dir/phosphene/AGENTS.md" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

phosphene_load_config() {
  local project_root
  project_root="$(phosphene_find_project_root)" || {
    phosphene__err "Not in a PHOSPHENE project (missing ./phosphene at repo root)."
    return 1
  }

  export PHOSPHENE_PROJECT_ROOT="$project_root"
  export PHOSPHENE_ROOT="$project_root/phosphene"
  export PHOSPHENE_DOMAINS_ROOT="$PHOSPHENE_ROOT/domains"

  # Canonical domain output roots
  export feature_management_path="$PHOSPHENE_DOMAINS_ROOT/feature-management/output"
  # Back-compat alias (older scripts may still read this name)
  export fr_management_path="$feature_management_path"

  : "${feature_management_path:?missing feature_management_path (computed)}"
  : "${fr_layout:=single_dir}"
  : "${fr_format:=md}"
}

phosphene_require_cmd() {
  local c="$1"
  if ! command -v "$c" >/dev/null 2>&1; then
    phosphene__err "Missing required command: $c"
    return 1
  fi
}

# ----------------------------
# FR markdown header helpers
# ----------------------------
# Header format:
#   ID: FR-001
#   Title: ...
#   Status: Approved
#   Priority: High
#   Updated: YYYY-MM-DD
#   Dependencies: FR-002, FR-003
#

phosphene_fr_get_header() {
  local file="$1"
  local key="$2"
  awk -v k="$key" -F': ' '
    BEGIN{found=0}
    /^[A-Za-z0-9_-]+: /{
      if ($1==k) { sub(/^[^:]+: /, "", $0); print $0; found=1; exit 0 }
    }
    /^$/ { exit 0 }
    END{ if (!found) exit 1 }
  ' "$file"
}

phosphene_fr_set_header() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp="${file}.tmp.$$"

  awk -v k="$key" -v v="$value" -F': ' '
    BEGIN{done=0}
    /^[A-Za-z0-9_-]+: /{
      if ($1==k && done==0) { print k ": " v; done=1; next }
    }
    { print }
    END{
      if (done==0) {
        # Insert before first blank line if present; else append.
        # This END block cannot insert mid-stream; handled by second pass if needed.
      }
    }
  ' "$file" > "$tmp"

  # If key didn't exist, insert it before the first blank line.
  if ! grep -q "^${key}: " "$tmp"; then
    local tmp2="${file}.tmp2.$$"
    awk -v k="$key" -v v="$value" '
      BEGIN{ins=0}
      {
        if (ins==0 && $0=="") { print k ": " v; ins=1 }
        print
      }
      END{ if (ins==0) print "\n" k ": " v }
    ' "$file" > "$tmp2"
    mv "$tmp2" "$tmp"
  fi

  mv "$tmp" "$file"
}



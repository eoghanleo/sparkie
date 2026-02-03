#!/usr/bin/env bash
set -euo pipefail

# validate_proposition.sh
# Validates a <product-marketing> Proposition (PROP-*) artifact for structural compliance.
#
# Usage:
#   ./.github/scripts/validate_proposition.sh <proposition_file>
#   ./.github/scripts/validate_proposition.sh --all

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./.github/scripts/validate_proposition.sh <proposition_file>
  ./.github/scripts/validate_proposition.sh --all
  ./.github/scripts/validate_proposition.sh --strict <proposition_file>
  ./.github/scripts/validate_proposition.sh --all --strict

Checks:
  - required headers exist (ID/Title/Status/Updated/Dependencies/Owner/EditPolicy)
  - required sections exist:
      ## Formal Pitch
      ## Target Persona(s)
      ## Related Segment(s)
      ## Gain Boosters
      ## Pain Relievers
      ## Capabilities
      ## Notes
  - tables exist with expected headers
  - IDs are natural keys:
      BoosterID: BOOST-####-PROP-####
      RelieverID: REL-####-PROP-####
      CapabilityID: CAP-####-PROP-####
  - CapabilityType is one of: feature|function|standard|experience
  - mapped JTBD arrays are comma-separated lists of JTBD-(GAIN|PAIN)-####-PER-#### (whitespace ok around commas)
  - strict mode additionally enforces:
      - balanced fenced code blocks (code fence count must be even)
      - Formal Pitch contains the expected [V-SCRIPT] block for update_proposition_formal_pitch.sh
      - any PER-#### listed in Target Persona(s) must appear in Dependencies
      - all mapped JTBD IDs must exist in the referenced persona docs, and must belong to a target persona
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }

ROOT="$(phosphene_find_project_root)"
STRICT=0

code_fences_balanced() {
  local f="$1"
  local n
  n="$(grep -cE '^```' "$f" || true)"
  [[ $((n % 2)) -eq 0 ]]
}

extract_bullets_under_h2() {
  local f="$1"
  local heading="$2" # exact '## ...'
  awk -v heading="$heading" '
    BEGIN { inside=0; }
    $0 == heading { inside=1; next; }
    inside && $0 ~ /^## / { exit; }
    inside && $0 ~ /^-[[:space:]]+/ {
      sub(/^-+[[:space:]]+/, "", $0);
      gsub(/[[:space:]]+$/, "", $0);
      print $0;
    }
  ' "$f"
}

dependencies_ids() {
  local f="$1"
  local dep
  dep="$(head -n 30 "$f" | grep -E '^Dependencies:' | head -n 1 | sed -E 's/^Dependencies:[[:space:]]*//')"
  echo "$dep" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -v '^$' || true
}

persona_has_jtbd_id() {
  local per_file="$1"
  local jtbd="$2"
  grep -qE "^[|][[:space:]]*${jtbd}[[:space:]]*[|]" "$per_file"
}

validate_file() {
  local f="$1"
  [[ -f "$f" ]] || fail "Not a file: $f"

  # Helper to extract lines between a heading and next '## ' heading
  extract_block() {
    local heading="$1"
    awk -v heading="$heading" '
      BEGIN { inside=0; }
      $0 == heading { inside=1; next; }
      inside && $0 ~ /^## / { exit; }
      inside { print; }
    ' "$f"
  }

  local head
  head="$(head -n 30 "$f")"
  echo "$head" | grep -qE '^ID:[[:space:]]*PROP-[0-9]{4}[[:space:]]*$' || fail "$(basename "$f"): missing/invalid 'ID: PROP-####'"
  local prop_id
  prop_id="$(echo "$head" | grep -E '^ID:[[:space:]]*PROP-[0-9]{4}[[:space:]]*$' | head -n 1 | sed -E 's/^ID:[[:space:]]*//; s/[[:space:]]*$//')"
  [[ -n "${prop_id:-}" ]] || fail "$(basename "$f"): could not parse proposition ID"

  echo "$head" | grep -qE '^Title:[[:space:]]*.+$' || fail "$(basename "$f"): missing 'Title:'"
  echo "$head" | grep -qE '^Status:[[:space:]]*.+$' || fail "$(basename "$f"): missing 'Status:'"
  echo "$head" | grep -qE '^Updated:[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}|YYYY-MM-DD)[[:space:]]*$' || fail "$(basename "$f"): missing/invalid 'Updated:'"
  echo "$head" | grep -qE '^Dependencies:' || fail "$(basename "$f"): missing 'Dependencies:'"
  echo "$head" | grep -qE '^Owner:' || fail "$(basename "$f"): missing 'Owner:'"
  echo "$head" | grep -qE '^EditPolicy:[[:space:]]*DO_NOT_EDIT_DIRECTLY' || fail "$(basename "$f"): missing 'EditPolicy: DO_NOT_EDIT_DIRECTLY ...' (script-first policy)"

  # <product-marketing> WTBD parent requirement: every PROP belongs to a VPD.
  dependencies_ids "$f" | grep -qE '^VPD-[0-9]{3}$' || fail "$(basename "$f"): missing VPD parent in Dependencies (expected VPD-###)"

  if [[ "$STRICT" -eq 1 ]]; then
    code_fences_balanced "$f" || fail "$(basename "$f"): unbalanced fenced code blocks (code fence count must be even)"
    fp="$(extract_block "## Formal Pitch")"
    echo "$fp" | grep -qF '[V-SCRIPT]:' || fail "$(basename "$f"): Formal Pitch missing [V-SCRIPT] block (use update_proposition_formal_pitch.sh)"
    echo "$fp" | grep -qE 'update_proposition_formal_pitch\.sh' || fail "$(basename "$f"): Formal Pitch [V-SCRIPT] block missing update_proposition_formal_pitch.sh"
  fi

  for h in \
    "## Formal Pitch" \
    "## Target Persona(s)" \
    "## Related Segment(s)" \
    "## Gain Boosters" \
    "## Pain Relievers" \
    "## Capabilities" \
    "## Notes"
  do
    grep -qF "$h" "$f" || fail "$(basename "$f"): missing section '$h'"
  done

  # Target personas: must be bullet lines with PER-#### (ignore V-SCRIPT blocks and blank lines)
  tp="$(extract_block "## Target Persona(s)")"
  if ! echo "$tp" | grep -qE '^[[:space:]]*-[[:space:]]*PER-[0-9]{4}[[:space:]]*$'; then
    warn "$(basename "$f"): no PER-#### entries found under '## Target Persona(s)' (ok for draft, but recommended)"
  fi

  rs="$(extract_block "## Related Segment(s)")"
  if ! echo "$rs" | grep -qE '^[[:space:]]*-[[:space:]]*SEG-[0-9]{4}[[:space:]]*$'; then
    warn "$(basename "$f"): no SEG-#### entries found under '## Related Segment(s)' (ok for draft, but recommended)"
  fi

  # Table checks
  gb="$(extract_block "## Gain Boosters")"
  echo "$gb" | grep -qE '[|][[:space:]]*BoosterID[[:space:]]*[|]' || fail "$(basename "$f"): Gain Boosters missing 'BoosterID' table header"
  echo "$gb" | grep -qF 'MappedGainIDs[]' || fail "$(basename "$f"): Gain Boosters missing 'MappedGainIDs[]' table header"

  pr="$(extract_block "## Pain Relievers")"
  echo "$pr" | grep -qE '[|][[:space:]]*RelieverID[[:space:]]*[|]' || fail "$(basename "$f"): Pain Relievers missing 'RelieverID' table header"
  echo "$pr" | grep -qF 'MappedPainIDs[]' || fail "$(basename "$f"): Pain Relievers missing 'MappedPainIDs[]' table header"

  cap="$(extract_block "## Capabilities")"
  echo "$cap" | grep -qE '[|][[:space:]]*CapabilityID[[:space:]]*[|]' || fail "$(basename "$f"): Capabilities missing 'CapabilityID' table header"
  echo "$cap" | grep -qE '[|][[:space:]]*CapabilityType[[:space:]]*[|]' || fail "$(basename "$f"): Capabilities missing 'CapabilityType' table header"

  # Validate rows: use awk table parsing by pipe.
  # Booster table: | BOOST-0001-PROP-0001 | ... | JTBD-GAIN-.... |
  echo "$gb" | awk -v prop="$prop_id" -v file="$(basename "$f")" '
    BEGIN { FS="|"; bad=0; }
    $0 ~ /^[|][[:space:]]*BOOST-[0-9]{4}-PROP-[0-9]{4}[[:space:]]*[|]/ {
      id=$2; mapped=$4;
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", id);
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", mapped);
      if (id !~ ("^BOOST-[0-9]{4}-" prop "$")) {
        print "WARN: " file ": invalid BoosterID for proposition: " id > "/dev/stderr"; bad=1;
      }
      if (mapped != "" && mapped != "<...>") {
        n=split(mapped, a, /,/);
        for (i=1; i<=n; i++) {
          x=a[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", x);
          if (x !~ /^JTBD-GAIN-[0-9]{4}-PER-[0-9]{4}$/) {
            print "WARN: " file ": invalid MappedGainIDs[] item: " x > "/dev/stderr"; bad=1;
          }
        }
      }
      if (seen[id]++ > 0) { print "WARN: " file ": duplicate BoosterID: " id > "/dev/stderr"; bad=1; }
    }
    END { exit bad; }
  ' || fail "$(basename "$f"): Gain Boosters table has invalid rows"

  echo "$pr" | awk -v prop="$prop_id" -v file="$(basename "$f")" '
    BEGIN { FS="|"; bad=0; }
    $0 ~ /^[|][[:space:]]*REL-[0-9]{4}-PROP-[0-9]{4}[[:space:]]*[|]/ {
      id=$2; mapped=$4;
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", id);
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", mapped);
      if (id !~ ("^REL-[0-9]{4}-" prop "$")) {
        print "WARN: " file ": invalid RelieverID for proposition: " id > "/dev/stderr"; bad=1;
      }
      if (mapped != "" && mapped != "<...>") {
        n=split(mapped, a, /,/);
        for (i=1; i<=n; i++) {
          x=a[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", x);
          if (x !~ /^JTBD-PAIN-[0-9]{4}-PER-[0-9]{4}$/) {
            print "WARN: " file ": invalid MappedPainIDs[] item: " x > "/dev/stderr"; bad=1;
          }
        }
      }
      if (seen[id]++ > 0) { print "WARN: " file ": duplicate RelieverID: " id > "/dev/stderr"; bad=1; }
    }
    END { exit bad; }
  ' || fail "$(basename "$f"): Pain Relievers table has invalid rows"

  echo "$cap" | awk -v prop="$prop_id" -v file="$(basename "$f")" '
    BEGIN { FS="|"; bad=0; }
    $0 ~ /^[|][[:space:]]*CAP-[0-9]{4}-PROP-[0-9]{4}[[:space:]]*[|]/ {
      id=$2; ctype=$3;
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", id);
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", ctype);
      if (id !~ ("^CAP-[0-9]{4}-" prop "$")) {
        print "WARN: " file ": invalid CapabilityID for proposition: " id > "/dev/stderr"; bad=1;
      }
      if (ctype !~ /^(feature|function|standard|experience)$/) {
        print "WARN: " file ": invalid CapabilityType: " ctype > "/dev/stderr"; bad=1;
      }
      if (seen[id]++ > 0) { print "WARN: " file ": duplicate CapabilityID: " id > "/dev/stderr"; bad=1; }
    }
    END { exit bad; }
  ' || fail "$(basename "$f"): Capabilities table has invalid rows"

  if [[ "$STRICT" -eq 1 ]]; then
    # Internal consistency: Target personas must be listed in Dependencies.
    dep_ids="$(dependencies_ids "$f" | tr '\n' ' ')"
    # Note: grep returns 1 when no matches; allow empty target persona list in draft.
    target_pers="$(extract_bullets_under_h2 "$f" "## Target Persona(s)" | grep -E '^PER-[0-9]{4}$' || true)"
    target_pers="$(printf "%s\n" "$target_pers" | tr '\n' ' ')"
    for per in $target_pers; do
      if ! echo " $dep_ids " | grep -qF " $per "; then
        fail "$(basename "$f"): target persona $per missing from Dependencies header"
      fi
    done

    # Cross-doc JTBD integrity: mapped JTBD IDs must exist and belong to a target persona.
    # Build a map of PER-#### -> file path.
    while IFS= read -r per; do
      [[ -n "$per" ]] || continue
      per_path="$("$ROOT/phosphene/phosphene-core/bin/phosphene" id where "$per" 2>/dev/null | head -n 1 | awk -F'\t' '{print $3}')"
      [[ -n "${per_path:-}" ]] || fail "$(basename "$f"): persona not found in registry: $per"
      [[ "$per_path" = /* ]] || per_path="$ROOT/$per_path"
      [[ -f "$per_path" ]] || fail "$(basename "$f"): persona path not found: $per_path"
      export "PER_PATH_${per//-/_}=$per_path"
    done < <(printf "%s\n" $target_pers)

    # Collect mapped JTBD IDs from boosters/relievers blocks (column 3).
    # Note: grep returns 1 when no matches; allow empty mapped JTBD list in draft.
    mapped_ids="$( (echo "$gb"; echo "$pr") | grep -oE 'JTBD-(GAIN|PAIN)-[0-9]{4}-PER-[0-9]{4}' || true)"
    mapped_ids="$(printf "%s\n" "$mapped_ids" | sort -u)"
    while IFS= read -r jtbd; do
      [[ -n "$jtbd" ]] || continue
      per="${jtbd##*-PER-}"
      per="PER-$per"
      if ! echo " $target_pers " | grep -qF " $per "; then
        fail "$(basename "$f"): mapped JTBD ID belongs to non-target persona ($per): $jtbd"
      fi
      key="PER_PATH_${per//-/_}"
      per_file="${!key:-}"
      [[ -n "$per_file" ]] || fail "$(basename "$f"): internal error resolving persona path for $per"
      persona_has_jtbd_id "$per_file" "$jtbd" || fail "$(basename "$f"): mapped JTBD ID not found in $per: $jtbd"
    done <<< "$mapped_ids"
  fi

  echo "OK: $f"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || -z "${1:-}" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--strict" ]]; then
  STRICT=1
  shift
fi

if [[ "${1:-}" == "--all" ]]; then
  if [[ "${2:-}" == "--strict" ]]; then STRICT=1; fi
  dir="$ROOT/phosphene/domains/product-marketing/output"
  [[ -d "$dir" ]] || fail "Missing docs dir: $dir"
  found=0
  while IFS= read -r -d '' f; do
    found=1
    validate_file "$f"
  done < <(find "$dir" -type f -name "PROP-*.md" -print0)
  if [[ "$found" -eq 0 ]]; then
    warn "No propositions found under $dir"
  fi
  exit 0
fi

target="$1"
if [[ "$target" != /* ]]; then
  target="$ROOT/$target"
fi
validate_file "$target"


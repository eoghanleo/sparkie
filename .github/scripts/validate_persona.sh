#!/usr/bin/env bash
set -euo pipefail

# validate_persona.sh
# Validates a <product-marketing> Persona (PER-*) artifact for structural compliance.
#
# Usage:
#   ./.github/scripts/validate_persona.sh <persona_file>
#   ./.github/scripts/validate_persona.sh --all

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./.github/scripts/validate_persona.sh <persona_file>
  ./.github/scripts/validate_persona.sh --all
  ./.github/scripts/validate_persona.sh --strict <persona_file>
  ./.github/scripts/validate_persona.sh --all --strict

Checks:
  - required headers exist (ID/Title/Status/Updated/Dependencies/Owner)
  - required sections exist:
      ## Snapshot summary
      ## Jobs
      ## Pains
      ## Gains
      ## Evidence and links
      ## Notes
  - Jobs/Pains/Gains include a table with JTBD-ID + Importance
  - IDs follow: JTBD-JOB-####-PER-#### / JTBD-PAIN-####-PER-#### / JTBD-GAIN-####-PER-#### (suffix must match the persona ID)
  - Importance is integer 1..5
  - Evidence and links includes sub-sections:
      ### EvidenceIDs
      ### CandidatePersonaIDs
      ### DocumentIDs
      ### Links
  - strict mode additionally enforces:
      - balanced fenced code blocks (code fence count must be even)
      - expected [V-SCRIPT] blocks exist for key sections
      - EvidenceIDs/CPE IDs/DocumentIDs exist in the global registry
      - EvidenceIDs must either be general (no CPE in evidence row) or match at least one listed CandidatePersonaID
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
  # Even number of ``` fences means all blocks close.
  [[ $((n % 2)) -eq 0 ]]
}

require_vscript_block_contains() {
  local f="$1"
  local section="$2"
  local expected="$3" # regex inside the section block
  local block
  block="$(awk -v section="$section" '
    BEGIN { inside=0; }
    $0 == section { inside=1; next; }
    inside && $0 ~ /^## / { exit; }
    inside { print; }
  ' "$f")"
  echo "$block" | grep -qF '[V-SCRIPT]:' || fail "$(basename "$f"): $section missing [V-SCRIPT] block (script-first discoverability)"
  echo "$block" | grep -qE "$expected" || fail "$(basename "$f"): $section [V-SCRIPT] block missing expected script: $expected"
}

extract_bullets_under() {
  local f="$1"
  local heading="$2" # exact '### ...'
  awk -v heading="$heading" '
    BEGIN { inside=0; }
    $0 == heading { inside=1; next; }
    inside && $0 ~ /^### / { exit; }
    inside && $0 ~ /^## / { exit; }
    inside && $0 ~ /^-[[:space:]]+/ { 
      sub(/^-+[[:space:]]+/, "", $0);
      gsub(/[[:space:]]+$/, "", $0);
      print $0;
    }
  ' "$f"
}

id_exists_in_registry() {
  local id="$1"
  "$ROOT/phosphene/phosphene-core/bin/phosphene" id where "$id" >/dev/null 2>&1
}

evidence_row_candidate_personas() {
  local eid="$1"
  local evidence_file
  evidence_file="$("$ROOT/phosphene/phosphene-core/bin/phosphene" id where "$eid" 2>/dev/null | head -n 1 | awk -F'\t' '{print $3}')"
  [[ -n "${evidence_file:-}" ]] || return 0
  [[ "$evidence_file" = /* ]] || evidence_file="$ROOT/$evidence_file"
  [[ -f "$evidence_file" ]] || return 0
  awk -F'|' -v eid="$eid" '
    $0 ~ /^[|][[:space:]]*E-[0-9]{4}[[:space:]]*[|]/ {
      col=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", col);
      if (col==eid) {
        cpe=$4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", cpe);
        print cpe;
        exit;
      }
    }
  ' "$evidence_file"
}

validate_file() {
  local f="$1"
  [[ -f "$f" ]] || fail "Not a file: $f"

  # Header checks (only require presence somewhere in first ~20 lines)
  local head
  head="$(head -n 25 "$f")"
  echo "$head" | grep -qE '^ID:[[:space:]]*PER-[0-9]{4}[[:space:]]*$' || fail "$(basename "$f"): missing/invalid 'ID: PER-####'"
  local persona_id
  persona_id="$(echo "$head" | grep -E '^ID:[[:space:]]*PER-[0-9]{4}[[:space:]]*$' | head -n 1 | sed -E 's/^ID:[[:space:]]*//; s/[[:space:]]*$//')"
  [[ -n "${persona_id:-}" ]] || fail "$(basename "$f"): could not parse persona ID"
  echo "$head" | grep -qE '^Title:[[:space:]]*.+$' || fail "$(basename "$f"): missing 'Title:'"
  echo "$head" | grep -qE '^Status:[[:space:]]*.+$' || fail "$(basename "$f"): missing 'Status:'"
  echo "$head" | grep -qE '^Updated:[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}|YYYY-MM-DD)[[:space:]]*$' || fail "$(basename "$f"): missing/invalid 'Updated:'"
  echo "$head" | grep -qE '^Dependencies:' || fail "$(basename "$f"): missing 'Dependencies:'"
  echo "$head" | grep -qE '^Owner:' || fail "$(basename "$f"): missing 'Owner:'"
  echo "$head" | grep -qE '^EditPolicy:[[:space:]]*DO_NOT_EDIT_DIRECTLY' || fail "$(basename "$f"): missing 'EditPolicy: DO_NOT_EDIT_DIRECTLY ...' (script-first policy)"

  # <product-marketing> WTBD parent requirement: every PER belongs to a VPD.
  deps_line="$(echo "$head" | grep -E '^Dependencies:' | head -n 1 | sed -E 's/^Dependencies:[[:space:]]*//')"
  echo "$deps_line" | grep -qE '(^|[,[:space:]])VPD-[0-9]{3}($|[,[:space:]])' || fail "$(basename "$f"): missing VPD parent in Dependencies (expected VPD-###)"

  if [[ "$STRICT" -eq 1 ]]; then
    code_fences_balanced "$f" || fail "$(basename "$f"): unbalanced fenced code blocks (code fence count must be even)"
    # Script discoverability blocks (non-negotiable in strict mode)
    require_vscript_block_contains "$f" "## Snapshot summary" 'update_persona_summary\.sh'
    require_vscript_block_contains "$f" "## Jobs" 'add_persona_jtbd_item\.sh'
    require_vscript_block_contains "$f" "## Jobs" 'update_persona_jtbd_item\.sh'
    require_vscript_block_contains "$f" "## Pains" 'add_persona_jtbd_item\.sh'
    require_vscript_block_contains "$f" "## Gains" 'add_persona_jtbd_item\.sh'
    require_vscript_block_contains "$f" "## Evidence and links" 'add_persona_evidence_link\.sh'
    require_vscript_block_contains "$f" "## Notes" 'add_persona_note\.sh'
  fi

  # Section checks
  for h in \
    "## Snapshot summary" \
    "## Jobs" \
    "## Pains" \
    "## Gains" \
    "## Evidence and links" \
    "## Notes"
  do
    grep -qF "$h" "$f" || fail "$(basename "$f"): missing section '$h'"
  done

  # Evidence sub-sections (within ## Evidence and links block)
  local evidence_block
  evidence_block="$(awk '
    BEGIN { inside=0; }
    $0 == "## Evidence and links" { inside=1; next; }
    inside && $0 ~ /^## / { exit; }
    inside { print; }
  ' "$f")"
  echo "$evidence_block" | grep -qF "### EvidenceIDs" || fail "$(basename "$f"): missing '### EvidenceIDs' under '## Evidence and links'"
  echo "$evidence_block" | grep -qF "### CandidatePersonaIDs" || fail "$(basename "$f"): missing '### CandidatePersonaIDs' under '## Evidence and links'"
  echo "$evidence_block" | grep -qF "### DocumentIDs" || fail "$(basename "$f"): missing '### DocumentIDs' under '## Evidence and links'"
  echo "$evidence_block" | grep -qF "### Links" || fail "$(basename "$f"): missing '### Links' under '## Evidence and links'"

  # Extract table rows per section, then validate ID patterns + Importance.
  # We parse as:
  # - find section start line
  # - read until next '## ' heading
  # - from that chunk, pull markdown table rows where col1 matches JTBD-...
  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "${tmp:-}"' RETURN

  extract_rows() {
    local section="$1"
    awk -v section="$section" '
      BEGIN { inside=0; }
      $0 == section { inside=1; next; }
      inside && $0 ~ /^## / { exit; }
      inside { print; }
    ' "$f"
  }

  check_table() {
    local section="$1"
    local prefix="$2"   # JTBD-JOB|JTBD-PAIN|JTBD-GAIN (without -####)
    local pid="$3"      # PER-#### (must match suffix in JTBD-ID)

    extract_rows "$section" > "$tmp"

    # Must have a table header containing JTBD-ID and Importance
    grep -qE '[|][[:space:]]*JTBD-ID[[:space:]]*[|]' "$tmp" || fail "$(basename "$f"): $section missing table header 'JTBD-ID'"
    grep -qE '[|][[:space:]]*Importance[[:space:]]*[|]' "$tmp" || fail "$(basename "$f"): $section missing table header 'Importance'"

    # Validate each data row where first cell is JTBD-...
    local bad=0
    awk -v section="$section" -v prefix="$prefix" -v pid="$pid" -v file="$(basename "$f")" '
      BEGIN { FS="|"; }
      $0 ~ /^[|][[:space:]]*JTBD-[A-Z]+-[0-9]{4}-PER-[0-9]{4}[[:space:]]*[|]/ {
        id=$2; imp=$4;
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", id);
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", imp);
        if (id !~ ("^" prefix "-[0-9]{4}-" pid "$")) {
          print "WARN: " file ": " section " invalid JTBD-ID for section: " id > "/dev/stderr";
          bad=1;
        }
        if (imp !~ /^[1-5]$/) {
          print "WARN: " file ": " section " invalid Importance (1..5): " imp > "/dev/stderr";
          bad=1;
        }
        if (seen[id]++ > 0) {
          print "WARN: " file ": duplicate JTBD-ID within file: " id > "/dev/stderr";
          bad=1;
        }
      }
      END { exit bad; }
    ' "$tmp" || bad=1

    [[ "$bad" -eq 0 ]] || fail "$(basename "$f"): $section has invalid rows (see WARN lines)"
  }

  check_table "## Jobs"  "JTBD-JOB"  "$persona_id"
  check_table "## Pains" "JTBD-PAIN" "$persona_id"
  check_table "## Gains" "JTBD-GAIN" "$persona_id"

  if [[ "$STRICT" -eq 1 ]]; then
    # Verify referenced IDs exist + EvidenceIDs align to CandidatePersonaIDs when evidence row is CPE-scoped.
    local cpes eids docs
    cpes="$(extract_bullets_under "$f" "### CandidatePersonaIDs" | tr '\n' ' ')"
    eids="$(extract_bullets_under "$f" "### EvidenceIDs" | tr '\n' ' ')"
    docs="$(extract_bullets_under "$f" "### DocumentIDs" | tr '\n' ' ')"

    for cpe in $cpes; do
      [[ "$cpe" =~ ^CPE-[0-9]{4}$ ]] || fail "$(basename "$f"): CandidatePersonaIDs must be CPE-#### (got: $cpe)"
      id_exists_in_registry "$cpe" || fail "$(basename "$f"): CandidatePersonaID not found in registry: $cpe"
    done

    for eid in $eids; do
      [[ "$eid" =~ ^E-[0-9]{4}$ ]] || fail "$(basename "$f"): EvidenceIDs must be E-#### (got: $eid)"
      id_exists_in_registry "$eid" || fail "$(basename "$f"): EvidenceID not found in registry: $eid"

      # Evidence row CPE scope check:
      # If evidence row lists one or more CPEs, require intersection with persona CandidatePersonaIDs.
      # Note: grep returns exit code 1 on no matches; under set -euo pipefail that would abort strict validation.
      # Empty evidence CPE scope is valid (general evidence), so treat it as empty list.
      row_cpe="$( (evidence_row_candidate_personas "$eid" | grep -oE 'CPE-[0-9]{4}' || true) | tr '\n' ' ')"
      if [[ -n "${row_cpe:-}" && -n "${cpes:-}" ]]; then
        ok=0
        for x in $row_cpe; do
          if echo " $cpes " | grep -qF " $x "; then ok=1; break; fi
        done
        [[ "$ok" -eq 1 ]] || fail "$(basename "$f"): EvidenceID $eid is scoped to [$row_cpe] but persona CandidatePersonaIDs are [$cpes]"
      fi
    done

    for did in $docs; do
      # allow common doc IDs; ensure they exist in registry where possible
      if [[ "$did" =~ ^(RA-[0-9]{3}|PITCH-[0-9]{4}|RS-[0-9]{4}|PROP-[0-9]{4}|PER-[0-9]{4}|CPE-[0-9]{4})$ ]]; then
        id_exists_in_registry "$did" || fail "$(basename "$f"): DocumentID not found in registry: $did"
      else
        fail "$(basename "$f"): DocumentIDs contains unexpected token: $did"
      fi
    done
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
  done < <(find "$dir" -type f -name "PER-*.md" -print0)
  if [[ "$found" -eq 0 ]]; then
    warn "No personas found under $dir"
  fi
  exit 0
fi

target="$1"
if [[ "$target" != /* ]]; then
  target="$ROOT/$target"
fi
validate_file "$target"


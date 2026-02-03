#!/usr/bin/env bash
#
# IDEA Validation Script (bash-only)
# Validates ideation artifacts adhere to header and section requirements.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./.github/scripts/validate_idea.sh [--all] [FILE|DIRECTORY]
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(phosphene_find_project_root)" || fail "Not in a PHOSPHENE project."
DEFAULT_DIR="$ROOT/phosphene/domains/ideation/output/ideas"

ALL=0
TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) ALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) TARGET="$1"; shift ;;
  esac
done

validate_file() {
  local file="$1"
  [[ -f "$file" ]] || return 1

  local id
  id="$(grep -E '^ID:[[:space:]]*IDEA-[0-9]{4}[[:space:]]*$' "$file" | head -n 1 | sed -E 's/^ID:[[:space:]]*//; s/[[:space:]]*$//')"
  [[ -n "${id:-}" ]] || fail "Missing or invalid ID header in $file"

  if ! grep -q "^Title: " "$file"; then
    fail "Missing Title header in $file"
  fi
  if ! grep -q "^IssueNumber: " "$file"; then
    fail "Missing IssueNumber header in $file"
  fi
  if ! grep -qE "^IssueNumber:[[:space:]]*[0-9]+[[:space:]]*$" "$file"; then
    fail "Invalid IssueNumber header in $file (must be numeric)"
  fi
  local issue_number
  issue_number="$(grep -E '^IssueNumber:[[:space:]]*[0-9]+' "$file" | head -n 1 | sed -E 's/^IssueNumber:[[:space:]]*//; s/[[:space:]]*$//')"
  [[ -n "${issue_number:-}" ]] || fail "Cannot parse IssueNumber header in $file"
  if ! grep -q "^Status: " "$file"; then
    fail "Missing Status header in $file"
  fi
  if ! grep -q "^Updated: " "$file"; then
    fail "Missing Updated header in $file"
  fi
  if ! grep -q "^Dependencies: " "$file"; then
    fail "Missing Dependencies header in $file"
  fi

  local base
  base="$(basename "$file")"
  if ! [[ "$base" =~ ^${id} ]]; then
    fail "Filename does not start with ID ($id): $base"
  fi

  for h in "## Problem / opportunity" "## Target user hypotheses" "## Next research questions" "## Storm table" "## Revision passes"; do
    if ! awk -v h="$h" '$0==h { found=1 } END{ exit found?0:1 }' "$file"; then
      fail "Missing required heading (${h}) in $file"
    fi
  done

  local spark_id spark_path
  spark_id="$(printf "SPARK-%06d" "$issue_number")"
  spark_path="$ROOT/phosphene/signals/sparks/${spark_id}.md"
  [[ -f "$spark_path" ]] || fail "Missing SPARK snapshot for issue ${issue_number} (${spark_id}.md) for $file"

  local probe_count_raw seed_sha256
  probe_count_raw="$(awk -v key="ManifoldProbeCount" '
    BEGIN{ found=0; }
    NF==0 { exit }
    $0 ~ ("^" key ":") {
      sub("^" key ":[[:space:]]*", "", $0);
      print $0;
      found=1;
      exit
    }
    END{ if (found==0) exit 1 }
  ' "$spark_path" 2>/dev/null || true)"
  [[ -n "${probe_count_raw:-}" ]] || fail "Missing ManifoldProbeCount in SPARK header: $spark_path"

  probe_count_raw="$(printf "%s" "$probe_count_raw" | tr -d '\r' | tr -d '[:space:]')"
  if ! [[ "$probe_count_raw" =~ ^[0-9]+$ ]]; then
    fail "ManifoldProbeCount must be numeric in SPARK header: $spark_path"
  fi
  probe_count="$probe_count_raw"
  if [[ "$probe_count" -lt 2 ]]; then
    fail "ManifoldProbeCount must be >= 2 in SPARK header: $spark_path"
  fi

  seed_sha256="$(awk -v key="SeedSHA256" '
    BEGIN{ found=0; }
    NF==0 { exit }
    $0 ~ ("^" key ":") {
      sub("^" key ":[[:space:]]*", "", $0);
      print $0;
      found=1;
      exit
    }
    END{ if (found==0) exit 1 }
  ' "$spark_path" 2>/dev/null || true)"
  seed_sha256="$(printf "%s" "${seed_sha256:-}" | tr -d '\r' | tr -d '[:space:]')"
  [[ -n "${seed_sha256:-}" ]] || fail "Missing SeedSHA256 in SPARK header: $spark_path"
  if ! [[ "$seed_sha256" =~ ^(sha256:)?[0-9a-f]{64}$ ]]; then
    fail "SeedSHA256 must be <hex> (optional sha256: prefix) in SPARK header: $spark_path"
  fi

  expected_rows=$(( probe_count * (probe_count - 1) / 2 * 3 ))

  storm_count="$(awk -F'|' -v start="## Storm table" -v expected="$expected_rows" '
    function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
    function sent_count(s){
      c=0;
      for (i=1;i<=length(s);i++){
        ch=substr(s,i,1);
        if (ch=="." || ch=="!" || ch=="?") c++;
      }
      return c;
    }
    BEGIN{ inside=0; count=0; }
    $0==start { inside=1; next }
    inside && $0 ~ /^## / { exit }
    !inside { next }
    $0 !~ /^\|/ { next }
    {
      n=split($0, a, /\|/);
      if (n != 7) { print "Invalid storm row (unexpected pipe count; avoid | in cells)" > "/dev/stderr"; exit 2 }
      id=trim(a[2]); p1=trim(a[3]); p2=trim(a[4]); ring=tolower(trim(a[5])); desc=trim(a[6]);
      if (id=="" || id=="STORM-ID" || id ~ /^-+$/) next;
      if (id !~ /^STORM-[0-9]{4,}$/) { print "Invalid STORM-ID in storm table: " id > "/dev/stderr"; exit 2 }
      if (p1=="" || p1 ~ /^<.*>$/) { print "Missing PROBE_1 for " id > "/dev/stderr"; exit 2 }
      if (p2=="" || p2 ~ /^<.*>$/) { print "Missing PROBE_2 for " id > "/dev/stderr"; exit 2 }
      if (p1 !~ /^CM-[0-9]{6}:[A-Z0-9_]+$/) { print "Invalid PROBE_1 format for " id ": " p1 > "/dev/stderr"; exit 2 }
      if (p2 !~ /^CM-[0-9]{6}:[A-Z0-9_]+$/) { print "Invalid PROBE_2 format for " id ": " p2 > "/dev/stderr"; exit 2 }
      if (p1 == p2) { print "Probe pair must be unique for " id > "/dev/stderr"; exit 2 }
      if (ring !~ /^(adjacent|orthogonal|extrapolatory)$/) { print "Invalid RING in storm table: " ring " for " id > "/dev/stderr"; exit 2 }
      if (desc=="" || desc ~ /^<.*>$/) { print "Missing DESCRIPTION for " id > "/dev/stderr"; exit 2 }
      sc=sent_count(desc);
      if (sc < 3) { print "DESCRIPTION must be >= 3 sentences for " id " (found " sc ")" > "/dev/stderr"; exit 2 }
      k1=p1; k2=p2;
      if (k2 < k1) { tmp=k1; k1=k2; k2=tmp; }
      key=k1 "\t" k2 "\t" ring;
      if (seen[key]++) { print "Duplicate probe pair + ring in storm table: " key > "/dev/stderr"; exit 2 }
      count++;
    }
    END{
      if (count != expected) { print "Storm table must contain exactly " expected " rows; found " count > "/dev/stderr"; exit 2 }
      print count;
    }
  ' "$file")" || fail "Storm table invalid in $file"

  footer_meta="$(awk -v open="\\[PHOSPHENE_MANIFOLD_PROBES\\]" -v close="\\[/PHOSPHENE_MANIFOLD_PROBES\\]" '
    BEGIN{ in=0; seed=""; count=""; probes=0; found=0; }
    $0 ~ open { in=1; found=1; next }
    in && $0 ~ close { in=0; exit }
    in {
      if ($0 ~ /^seed_sha256:/) { sub(/^seed_sha256:[[:space:]]*/, "", $0); seed=$0; next }
      if ($0 ~ /^manifold_probe_count:/) { sub(/^manifold_probe_count:[[:space:]]*/, "", $0); count=$0; next }
      if ($0 ~ /^-[[:space:]]+/) { probes++; }
    }
    END{
      if (found==0) exit 2;
      print seed "\t" count "\t" probes;
    }
  ' "$file")" || fail "Missing [PHOSPHENE_MANIFOLD_PROBES] block in $file"

  footer_seed="$(printf "%s" "$footer_meta" | awk -F'\t' '{print $1}')"
  footer_count="$(printf "%s" "$footer_meta" | awk -F'\t' '{print $2}')"
  footer_probe_lines="$(printf "%s" "$footer_meta" | awk -F'\t' '{print $3}')"

  [[ -n "${footer_seed:-}" ]] || fail "Missing seed_sha256 in [PHOSPHENE_MANIFOLD_PROBES] block in $file"
  [[ -n "${footer_count:-}" ]] || fail "Missing manifold_probe_count in [PHOSPHENE_MANIFOLD_PROBES] block in $file"
  if ! [[ "$footer_seed" =~ ^(sha256:)?[0-9a-f]{64}$ ]]; then
    fail "Invalid seed_sha256 in [PHOSPHENE_MANIFOLD_PROBES] block in $file"
  fi
  if ! [[ "$footer_count" =~ ^[0-9]+$ ]]; then
    fail "Invalid manifold_probe_count in [PHOSPHENE_MANIFOLD_PROBES] block in $file"
  fi
  normalize_seed() {
    printf "%s" "$1" | sed -E 's/^sha256://I'
  }
  if [[ "$(normalize_seed "$footer_seed")" != "$(normalize_seed "$seed_sha256")" ]]; then
    fail "seed_sha256 in footer does not match SPARK header for $file"
  fi
  if [[ "$footer_count" -ne "$probe_count" ]]; then
    fail "manifold_probe_count in footer does not match SPARK header for $file"
  fi
  if [[ "$footer_probe_lines" -ne "$probe_count" ]]; then
    fail "Probe footer must list ${probe_count} probes (found ${footer_probe_lines}) in $file"
  fi

  rev_count="$(awk -v start="## Revision passes" '
    BEGIN{ inside=0; c=0; }
    $0==start { inside=1; next }
    inside && $0 ~ /^## / { exit }
    inside && $0 ~ /^-[[:space:]]+/ { c++; }
    END{ print c+0; }
  ' "$file")"
  if [[ "$rev_count" -lt 2 ]]; then
    fail "Revision passes must include at least 2 bullet items in $file"
  fi
}

files=()
if [[ "$ALL" -eq 1 ]]; then
  [[ -d "$DEFAULT_DIR" ]] || fail "Missing ideation directory: $DEFAULT_DIR"
  while IFS= read -r f; do files+=("$f"); done < <(find "$DEFAULT_DIR" -type f -name "IDEA-*.md" | sort)
elif [[ -n "${TARGET:-}" ]]; then
  if [[ -f "$TARGET" ]]; then
    files=("$TARGET")
  elif [[ -d "$TARGET" ]]; then
    while IFS= read -r f; do files+=("$f"); done < <(find "$TARGET" -type f -name "IDEA-*.md" | sort)
  else
    fail "Target not found: $TARGET"
  fi
else
  [[ -d "$DEFAULT_DIR" ]] || fail "Missing ideation directory: $DEFAULT_DIR"
  while IFS= read -r f; do files+=("$f"); done < <(find "$DEFAULT_DIR" -type f -name "IDEA-*.md" | sort)
fi

if [[ "${#files[@]}" -eq 0 ]]; then
  fail "No IDEA files found to validate."
fi

for f in "${files[@]}"; do
  validate_file "$f"
done

echo "OK: validated ${#files[@]} IDEA file(s)"

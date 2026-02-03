#!/usr/bin/env bash
set -euo pipefail

# validate_prd_bundle.sh
# Validates a PRD bundle for basic structural and cross-reference compliance.
#
# Usage:
#   ./.github/scripts/validate_prd_bundle.sh <bundle_dir> [--strict]
#
# Checks:
#  - required files and directories exist
#  - PRD ID parsed from 00-coversheet.md (ID: PRD-###)
#  - optional ID presence in other files (warn)
#  - Dependencies header includes all referenced top-level IDs (RA/VPD/ROADMAP)
#  - all referenced PHOSPHENE IDs resolve via: ./phosphene/phosphene-core/bin/phosphene id where <ID>
#    (strict mode fails on any unresolved reference)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_FOR_LIB="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$ROOT_FOR_LIB/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./.github/scripts/validate_prd_bundle.sh <bundle_dir> [--strict]

Options:
  --strict   Fail if any referenced ID cannot be resolved
EOF
}

fail() { echo "FAIL: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }

STRICT=0
BUNDLE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$BUNDLE_DIR" ]]; then
        BUNDLE_DIR="$1"
        shift
      else
        echo "Unknown arg: $1" >&2
        usage
        exit 2
      fi
      ;;
  esac
done

[[ -n "${BUNDLE_DIR:-}" ]] || { usage; exit 2; }

ROOT="$(phosphene_find_project_root)" || fail "Not in a PHOSPHENE project (cannot find ./phosphene at repo root)."
if [[ "$BUNDLE_DIR" != /* ]]; then
  BUNDLE_DIR="$ROOT/$BUNDLE_DIR"
fi
[[ -d "$BUNDLE_DIR" ]] || fail "Not a directory: $BUNDLE_DIR"

REQ_FILES=(
  "00-coversheet.md"
  "10-executive-summary.md"
  "20-product-context.md"
  "30-personas-jobs-props.md"
  "40-goals-scope.md"
  "50-success-metrics.md"
  "60-requirements/README.md"
  "60-requirements/functional.md"
  "60-requirements/non-functional.md"
  "70-feature-catalogue/README.md"
  "70-feature-catalogue/core-features.md"
  "70-feature-catalogue/special-features.md"
  "80-architecture.md"
  "90-platform-technology.md"
  "100-data-integrations.md"
  "110-security-compliance.md"
  "120-ux-content.md"
  "130-delivery-roadmap.md"
  "140-testing-quality.md"
  "150-operations-support.md"
  "160-risks-dependencies.md"
  "170-release-readiness.md"
  "180-appendix/README.md"
  "180-appendix/glossary.md"
  "180-appendix/decision-log.md"
  "180-appendix/open-questions.md"
  "180-appendix/traceability-matrix.md"
)

for f in "${REQ_FILES[@]}"; do
  [[ -f "$BUNDLE_DIR/$f" ]] || fail "Missing required file: $f"
done
[[ -d "$BUNDLE_DIR/60-requirements" ]] || fail "Missing required directory: 60-requirements/"
[[ -d "$BUNDLE_DIR/70-feature-catalogue" ]] || fail "Missing required directory: 70-feature-catalogue/"
[[ -d "$BUNDLE_DIR/180-appendix" ]] || fail "Missing required directory: 180-appendix/"

require_heading() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! grep -qE "$pattern" "$file"; then
    fail "Pane readiness missing heading (${label}) in $(basename "$file")"
  fi
}

# Pane readiness gates: presence + linkability (minimal, file/heading based).
require_heading "$BUNDLE_DIR/00-coversheet.md" '^## Links$' "Links"
require_heading "$BUNDLE_DIR/80-architecture.md" '^## 8[.]1 Architecture overview$' "Architecture overview"
require_heading "$BUNDLE_DIR/100-data-integrations.md" '^## 10[.]1 Data model overview$' "Data model overview"
require_heading "$BUNDLE_DIR/50-success-metrics.md" '^## 5[.]3 KPI definitions$' "KPI definitions"
require_heading "$BUNDLE_DIR/110-security-compliance.md" '^## 11[.]1 Data classification and handling$' "Security classification"
require_heading "$BUNDLE_DIR/140-testing-quality.md" '^## 14[.]1 Test pyramid and scope$' "Testing scope"
require_heading "$BUNDLE_DIR/130-delivery-roadmap.md" '^## 13[.]1 Program structure$' "Delivery plan"
require_heading "$BUNDLE_DIR/170-release-readiness.md" '^## 17[.]1 Launch strategy$' "Release readiness"
require_heading "$BUNDLE_DIR/150-operations-support.md" '^## 15[.]1 Operational posture$' "Operations posture"

# Pane readiness: glossary must include at least one non-placeholder term/definition.
glossary_file="$BUNDLE_DIR/180-appendix/glossary.md"
if [[ -f "$glossary_file" ]]; then
  term_line="$(awk -F'|' '
    function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
    NR<=2 { next }
    /^\|/{
      t=trim($2); d=trim($3);
      if (t=="" || d=="") next;
      if (t ~ /^\[.*\]$/ || d ~ /^\[.*\]$/) next;
      if (t ~ /^<.*>$/ || d ~ /^<.*>$/) next;
      if (tolower(t)=="tbd" || tolower(d)=="tbd") next;
      print t "|" d;
      exit;
    }
  ' "$glossary_file")"
  if [[ -z "${term_line:-}" ]]; then
    fail "Glossary must include at least one defined term (non-placeholder)"
  fi
fi

ID_LINE="$(grep -E '^ID:[[:space:]]*PRD-[0-9]{3}[[:space:]]*$' "$BUNDLE_DIR/00-coversheet.md" || true)"
[[ -n "$ID_LINE" ]] || fail "00-coversheet.md missing 'ID: PRD-###' line"
PRD_ID="$(echo "$ID_LINE" | sed -E 's/^ID:[[:space:]]*//; s/[[:space:]]*$//')"

for f in "${REQ_FILES[@]}"; do
  if ! grep -qE "^ID:[[:space:]]*${PRD_ID}[[:space:]]*$" "$BUNDLE_DIR/$f"; then
    warn "$f does not contain 'ID: $PRD_ID' (recommended for self-contained files)"
  fi
done

DEPS_LINE=""
DEPS_RAW=""
while IFS= read -r line; do
  # Header ends at first blank line.
  [[ -n "${line:-}" ]] || break
  if [[ "$line" =~ ^Dependencies: ]]; then
    DEPS_LINE="$line"
    DEPS_RAW="$(echo "$line" | sed -E 's/^Dependencies:[[:space:]]*//')"
    break
  fi
done < "$BUNDLE_DIR/00-coversheet.md"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
TMP_REF_IDS="$TMP_DIR/ref_ids.txt"
TMP_TOPLEVEL="$TMP_DIR/toplevel_ids.txt"
TMP_DEPS="$TMP_DIR/deps_ids.txt"
TMP_UNRES="$TMP_DIR/unresolved_ids.txt"
: > "$TMP_REF_IDS"
: > "$TMP_UNRES"

# Extract referenced PHOSPHENE IDs anywhere in bundle markdowns (including Dependencies line).
#
# We intentionally include FR/PRD so downstream linking can be validated.
find "$BUNDLE_DIR" -type f -name "*.md" -print0 2>/dev/null \
  | xargs -0 grep -hoE '(RA-[0-9]{3}|VPD-[0-9]{3}|ROADMAP-[0-9]{3}|PER-[0-9]{4}|PROP-[0-9]{4}|PITCH-[0-9]{4}|E-[0-9]{4}|SEG-[0-9]{4}|CPE-[0-9]{4}|FR-[0-9]{3}|PRD-[0-9]{3})' 2>/dev/null \
  | sort -u > "$TMP_REF_IDS" || true

# Drop self-reference (this PRD ID).
grep -v -x "$PRD_ID" "$TMP_REF_IDS" > "$TMP_REF_IDS.tmp" || true
mv "$TMP_REF_IDS.tmp" "$TMP_REF_IDS"

# Dependencies header parsing (top-level only).
if [[ -n "${DEPS_RAW:-}" ]]; then
  echo "$DEPS_RAW" \
    | tr ',' '\n' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' \
    | grep -E '^(RA-[0-9]{3}|VPD-[0-9]{3}|ROADMAP-[0-9]{3})$' \
    | sort -u > "$TMP_DEPS" || true
else
  : > "$TMP_DEPS"
fi

grep -E '^(RA-[0-9]{3}|VPD-[0-9]{3}|ROADMAP-[0-9]{3})$' "$TMP_REF_IDS" | sort -u > "$TMP_TOPLEVEL" || true

if [[ -s "$TMP_TOPLEVEL" ]]; then
  if [[ ! -s "$TMP_DEPS" ]]; then
    fail "Dependencies header must include top-level IDs referenced: $(tr '\n' ' ' < "$TMP_TOPLEVEL")"
  fi

  missing=0
  while IFS= read -r top_id; do
    [[ -n "${top_id:-}" ]] || continue
    if ! grep -q -x "$top_id" "$TMP_DEPS"; then
      warn "Top-level ID referenced in bundle but missing from Dependencies header: $top_id"
      missing=1
    fi
  done < "$TMP_TOPLEVEL"

  [[ "$missing" -eq 0 ]] || fail "Dependencies header missing one or more referenced top-level IDs"
fi

PHOSPHENE="$ROOT/phosphene/phosphene-core/bin/phosphene"
unresolved=0
while IFS= read -r rid; do
  [[ -n "${rid:-}" ]] || continue
  if ! "$PHOSPHENE" id where "$rid" >/dev/null 2>&1; then
    warn "Referenced ID does not resolve via 'phosphene id where': $rid"
    echo "$rid" >> "$TMP_UNRES"
    unresolved=1
  fi
done < "$TMP_REF_IDS"

if [[ "$unresolved" -eq 1 ]]; then
  if [[ "$STRICT" -eq 1 ]]; then
    fail "Unresolved referenced IDs (strict): $(tr '\n' ' ' < "$TMP_UNRES")"
  fi
  warn "Some referenced IDs are unresolved (non-strict): $(tr '\n' ' ' < "$TMP_UNRES")"
fi

echo "OK: $BUNDLE_DIR ($PRD_ID)"


#!/usr/bin/env bash
set -euo pipefail

# test-management-domain-done-score.sh
# Minimal programmatic scoring for <test-management> artifacts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_FOR_LIB="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$ROOT_FOR_LIB/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_done_score_metrics.sh"
phos_ds_env_defaults

usage() {
  cat <<'EOF'
Usage:
  ./.github/scripts/test-management-domain-done-score.sh [--docs-root <dir>] [--file <path>] [--min-score <0..100>] [--quiet]
EOF
}

fail() { echo "FAIL: $*" >&2; exit 2; }

ROOT="$(phosphene_find_project_root)"
DOCS_ROOT="$ROOT/phosphene/domains/test-management/output"
FILE=""
MIN_SCORE="10"
QUIET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --docs-root) DOCS_ROOT="${2:-}"; shift 2 ;;
    --file) FILE="${2:-}"; shift 2 ;;
    --min-score) MIN_SCORE="${2:-}"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -n "${FILE:-}" ]]; then
  if [[ "$FILE" != /* ]]; then FILE="$ROOT/$FILE"; fi
  [[ -f "$FILE" ]] || fail "Missing file: $FILE"
else
  if [[ "$DOCS_ROOT" != /* ]]; then DOCS_ROOT="$ROOT/$DOCS_ROOT"; fi
  [[ -d "$DOCS_ROOT" ]] || fail "Missing docs root dir: $DOCS_ROOT"
fi

if ! phos_ds_assert_numeric_0_100 "$MIN_SCORE"; then
  fail "--min-score must be numeric (0..100)"
fi

files=()
if [[ -n "${FILE:-}" ]]; then
  files=("$FILE")
else
  while IFS= read -r f; do
    [[ -n "${f:-}" ]] || continue
    files+=("$f")
  done < <(find "$DOCS_ROOT" -type f -name "TP-*.md" 2>/dev/null | sort)
fi

out_items="${#files[@]}"
if [[ "$out_items" -eq 0 ]]; then
  fail "No TP artifacts found under: $DOCS_ROOT"
fi

out_words="$(cat "${files[@]}" 2>/dev/null \
  | phos_ds_strip_codeblocks_and_tables \
  | phos_ds_clean_text_common \
  | wc -w | awk '{print $1}')"
score="$(phos_ds_score_minimal "$out_items" "$out_words" 12 60 100)"

result="$(awk -v s="$score" -v m="$MIN_SCORE" 'BEGIN{ if (s+0 >= m+0) print "PASS"; else print "FAIL" }')"

if [[ "$QUIET" -ne 1 ]]; then
  echo "PHOSPHENE — Done Score  <test-management>"
  echo "============================================================"
  echo "Result:    ${result}   Overall: ${score}/100   Threshold: ${MIN_SCORE}"
  echo ""
  echo "Inputs:"
  echo "  - test plan files: ${out_items}"
  echo "  - total words: ${out_words}"
fi

awk -v s="$score" -v m="$MIN_SCORE" 'BEGIN{ exit (s+0 >= m+0) ? 0 : 1 }'

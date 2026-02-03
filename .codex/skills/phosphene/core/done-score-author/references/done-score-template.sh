#!/usr/bin/env bash
set -euo pipefail

# ====================================================================
# PHOSPHENE — DONE SCORE TEMPLATE (bash-only)
# ====================================================================
#
# This file is a TEMPLATE and is not referenced by any workflows.
#
# Location (authoring reference):
#   .codex/skills/phosphene/core/done-score-author/references/done-score-template.sh
#
# To create a real scorer, copy this file to:
#   .github/scripts/<domain>-domain-done-score.sh
# and then implement the DOMAIN-SPECIFIC sections marked "TODO(domain)".
#
# --------------------------------------------------------------------
# CRITICAL contracts (keep these identical across done-score scripts)
# --------------------------------------------------------------------
# - Determinism: force LC_ALL=C, LANG=C, TZ=UTC; sort all discovery lists.
# - Shared library: MUST source `phosphene_done_score_metrics.sh` immediately
#   after `phosphene_env.sh`.
# - Metric naming: MUST use canonical metric base names from:
#     .codex/skills/phosphene/core/done-score-author/references/done-score-design.md
#   so scorer code and shared metric code speak the same variable language.
#
# --------------------------------------------------------------------
# Standard architecture (modules)
# --------------------------------------------------------------------
#   1) CLI + defaults
#   2) Discovery (repo root, targets, artifact lists)
#   3) Extraction (parse artifacts -> canonical intermediate TSV/TXT)
#   4) Cleaning (corpus hardening + anti-gaming filters)
#   5) Metrics (raw, dimension-aligned variables)
#   6) Normalization (raw -> 0..100, input-anchored wherever possible)
#   7) Scoring + levelling (scorebox -> overall 0..100)
#   8) Gates (hard fails; required artifacts/sections/validity)
#   9) Reporting (stable output; subscores + metric box + advice)
#
# --------------------------------------------------------------------
# Canonical metric variables (base names; do not rename)
# --------------------------------------------------------------------
# Volume:
#   out_items, out_words, out_lines
#   in_items,  in_words
#   out_in_ratio
#
# Coverage:
#   ref_cov, internal_cov, cat_cov, row_fill
#
# Diversity (textual):
#   out_tokens, unique_words, H, ent_norm, uniq_ratio
#   (future: hapax_ratio, simpson_div, msttr, uniq_bi_ratio, ...)
#
# Depth:
#   frag_count, frag_avg_words, two_sent_ratio
#   (future: evidence_per_item, ac_rows/req_rows, ...)
#
# Connectivity (graph):
#   edges, dens, avg_left, min_left, avg_right, min_right, multi_ratio
#
# Integrity (future):
#   dup_ids, missing_refs, bad_rows_ratio
#
# Executable / schema (future):
#   compile_ok, test_pass_rate, json_valid, yaml_valid
#

# ----------------------------
# Shared libs (MUST)
# ----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ds__find_repo_root_from_dir() {
  local dir="$1"
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

ROOT_FOR_LIB="$(ds__find_repo_root_from_dir "$SCRIPT_DIR")" || {
  echo "FAIL: Not in a PHOSPHENE project (cannot find ./phosphene at repo root from $SCRIPT_DIR)." >&2
  exit 2
}

LIB_DIR="$ROOT_FOR_LIB/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_done_score_metrics.sh"
phos_ds_env_defaults

usage() {
  cat <<'EOF'
Usage:
  # Scan a domain output tree:
  ./.github/scripts/<domain>-domain-done-score.sh [--docs-root <dir>] [--min-score <0..100>] [--quiet]

  # Score a single artifact file:
  ./.github/scripts/<domain>-domain-done-score.sh --file <path> [--min-score <0..100>] [--quiet]

  # Score a bundle directory (optional pattern; used by some domains):
  ./.github/scripts/<domain>-domain-done-score.sh <bundle_dir> [--min-score <0..100>] [--quiet]

Notes:
  - This script is evaluative only (it does not generate content).
  - Prefer input-anchored ratios (output/input) over absolute thresholds.
  - Keep extraction deterministic: sorted file discovery, stable ordering, no timestamps.

Exit codes:
  0 = PASS (score >= min-score AND all gates pass)
  1 = FAIL (score < min-score OR any gate fails)
  2 = usage/config error
EOF
}

fail() { echo "FAIL: $*" >&2; exit 2; }

# ----------------------------
# 1) CLI + defaults
# ----------------------------
ROOT="$ROOT_FOR_LIB"

# Default output root for the domain (TODO(domain): set this)
DOCS_ROOT_DEFAULT="$ROOT/phosphene/domains/<domain>/output"

# Optional upstream input root (TODO(domain): set this, or leave empty)
INPUT_ROOT_DEFAULT=""

TARGET_PATH=""              # may be a file or a bundle dir
DOCS_ROOT="$DOCS_ROOT_DEFAULT"
INPUT_ROOT="$INPUT_ROOT_DEFAULT"
FILE=""                     # explicit single-file target
MIN_SCORE="10"
QUIET=0

# Optional scaling knobs (prefer input-anchored ratios)
VOL_FULL_RATIO="1.00"       # full points at out_in_ratio >= this
OUT_IN_RATIO_CAP="5.00"     # hard cap on out_in_ratio (prevents runaway ratios)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --docs-root) DOCS_ROOT="${2:-}"; shift 2 ;;
    --input-root) INPUT_ROOT="${2:-}"; shift 2 ;;
    --file) FILE="${2:-}"; shift 2 ;;
    --min-score) MIN_SCORE="${2:-}"; shift 2 ;;
    --vol-full-ratio) VOL_FULL_RATIO="${2:-}"; shift 2 ;;
    --out-in-cap) OUT_IN_RATIO_CAP="${2:-}"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$TARGET_PATH" ]]; then
        TARGET_PATH="$1"
        shift
      else
        echo "Unknown arg: $1" >&2
        usage
        exit 2
      fi
      ;;
  esac
done

if ! phos_ds_assert_numeric_0_100 "$MIN_SCORE"; then
  fail "--min-score must be numeric (0..100)"
fi
if ! [[ "$VOL_FULL_RATIO" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  fail "--vol-full-ratio must be numeric"
fi
if ! [[ "$OUT_IN_RATIO_CAP" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  fail "--out-in-cap must be numeric"
fi

if [[ -n "${DOCS_ROOT:-}" && "$DOCS_ROOT" != /* ]]; then DOCS_ROOT="$ROOT/$DOCS_ROOT"; fi
if [[ -n "${INPUT_ROOT:-}" && "$INPUT_ROOT" != /* ]]; then INPUT_ROOT="$ROOT/$INPUT_ROOT"; fi
if [[ -n "${FILE:-}" && "$FILE" != /* ]]; then FILE="$ROOT/$FILE"; fi
if [[ -n "${TARGET_PATH:-}" && "$TARGET_PATH" != /* ]]; then TARGET_PATH="$ROOT/$TARGET_PATH"; fi

# ----------------------------
# 2) Discovery
# ----------------------------
# Decide what the "target" is:
# - FILE explicit wins (single artifact)
# - otherwise TARGET_PATH may be a bundle dir
# - otherwise scan DOCS_ROOT
if [[ -n "${FILE:-}" ]]; then
  [[ -f "$FILE" ]] || fail "Missing file: $FILE"
elif [[ -n "${TARGET_PATH:-}" ]]; then
  [[ -e "$TARGET_PATH" ]] || fail "Missing target path: $TARGET_PATH"
  if [[ -f "$TARGET_PATH" ]]; then
    FILE="$TARGET_PATH"
  fi
else
  [[ -d "$DOCS_ROOT" ]] || fail "Missing docs root dir: $DOCS_ROOT"
fi

# Collect output artifacts to score (stable ordering).
# TODO(domain): choose the canonical file pattern(s) for your domain.
OUTPUT_FILES=()
if [[ -n "${FILE:-}" ]]; then
  OUTPUT_FILES=("$FILE")
else
  scan_root="$DOCS_ROOT"
  if [[ -n "${TARGET_PATH:-}" && -d "$TARGET_PATH" ]]; then
    scan_root="$TARGET_PATH"
  fi
  while IFS= read -r f; do
    [[ -n "${f:-}" ]] || continue
    OUTPUT_FILES+=("$f")
  done < <(phos_ds_collect_files "$scan_root" "*.md")
fi

out_items="${#OUTPUT_FILES[@]}"
if [[ "$out_items" -eq 0 ]]; then
  fail "No output artifacts found under target."
fi

# ----------------------------
# 3) Extraction -> canonical intermediates
# ----------------------------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Canonical intermediate files (prefer TSV/TXT; easy to diff and test).
CORPUS_TXT="$tmp/corpus_fragments.txt"         # one fragment per line (un-cleaned)
CORPUS_CLEAN_TXT="$tmp/corpus_clean.txt"       # cleaned corpus for corpus-derived metrics

# Optional (future / domain-specific):
OUT_IDS_TXT="$tmp/out_ids.txt"                 # IDs created by this output
REF_IDS_TXT="$tmp/ref_ids.txt"                 # upstream IDs referenced
EDGES_TSV="$tmp/edges.tsv"                     # generic bipartite edges (left<TAB>right)

: > "$CORPUS_TXT"
: > "$CORPUS_CLEAN_TXT"
: > "$OUT_IDS_TXT"
: > "$REF_IDS_TXT"
: > "$EDGES_TSV"

# --- Example helper: header parsing bounded to header block ---
ds_read_header_value() {
  # Read a header value from a markdown file, bounded to the header block:
  # The first blank line ends the header block.
  local file="$1"
  local key="$2"
  local line
  while IFS= read -r line; do
    [[ -n "${line:-}" ]] || break
    if [[ "$line" =~ ^${key}: ]]; then
      echo "$line" | sed -E "s/^${key}:[[:space:]]*//"
      return 0
    fi
  done < "$file"
  return 1
}

# --- DOMAIN-SPECIFIC extraction (TODO(domain)) ---
#
# Goal: extract the *substantive* parts of the output into canonical intermediates:
# - Append one “semantic fragment” per line into $CORPUS_TXT.
# - Optionally populate IDs + edges (for coverage/connectivity/integrity).
#
# Recommended extraction strategy:
# - Treat tables as first-class: parse only “meaning-bearing” columns; ignore ID columns.
# - Treat prose sections as fragments: use `phos_ds_append_section_text` for specific H2 sections.
# - Avoid counting headings, boilerplate, and placeholders.
extract_output_corpus_fragments() {
  local f="$1"

  # Minimal baseline: treat the entire markdown (minus code blocks/tables) as prose.
  # TODO(domain): replace this with domain-aware extraction (tables + specific sections).
  cat "$f" 2>/dev/null \
    | phos_ds_strip_codeblocks_and_tables \
    | awk '
        # One fragment per non-empty line (keeps fragment_stats meaningful).
        function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
        {
          line=trim($0);
          if (line=="") next;
          if (line ~ /^#/) next;
          if (line ~ /^\[V-SCRIPT\]/) next;
          print line;
        }
      ' >> "$CORPUS_TXT"
}

# Execute extraction for each output artifact (stable ordering already ensured).
for f in "${OUTPUT_FILES[@]}"; do
  [[ -n "${f:-}" ]] || continue
  extract_output_corpus_fragments "$f"

  # TODO(domain): extract IDs, references, and edges if your domain supports them.
  # Examples:
  # - created IDs:  grep -hoE '^ID: [A-Z]+-[0-9]{3,4}$' "$f" | awk '{print $2}' >> "$OUT_IDS_TXT"
  # - referenced IDs: grep -hoE '(RA|E|PER|PROP|FR|SPEC)-[0-9]{3,4}' "$f" >> "$REF_IDS_TXT"
  # - edges: emit "<left_id>\t<right_id>" lines to "$EDGES_TSV"
done

# Stabilize optional intermediates (safe even if empty)
sort -u "$OUT_IDS_TXT" -o "$OUT_IDS_TXT" || true
sort -u "$REF_IDS_TXT" -o "$REF_IDS_TXT" || true
sort -u "$EDGES_TSV" -o "$EDGES_TSV" || true

# ----------------------------
# 4) Cleaning (anti-gaming layer)
# ----------------------------
clean_output_corpus() {
  # Remove IDs/tags/paths/URLs so they do not count toward volume/diversity metrics.
  # TODO(domain): add domain-specific ID stripping patterns.
  #
  # IMPORTANT: keep sentence punctuation so sentence-ratio metrics work.
  phos_ds_clean_text_common \
    's/(PER|PROP|CPE|SEG|PITCH|RA|E|VPD|ROADMAP|FR|SPEC|PRD)-[0-9]{3,4}/ /g' \
    < "$CORPUS_TXT" \
    | phos_ds_filter_token_dump \
    > "$CORPUS_CLEAN_TXT"
}

clean_output_corpus

# Canonical volume metrics (output)
out_words="$(wc -w < "$CORPUS_CLEAN_TXT" | awk '{print $1}')"
out_lines="$(wc -l < "$CORPUS_CLEAN_TXT" | awk '{print $1}')"

# Optional input inventory (input-anchoring)
in_items=0
in_words=0
if [[ -n "${INPUT_ROOT:-}" && -d "$INPUT_ROOT" ]]; then
  in_items="$(find "$INPUT_ROOT" -type f -name "*.md" 2>/dev/null | wc -l | awk '{print $1}')"
  in_words="$(phos_ds_clean_markdown_tree_words "$INPUT_ROOT")"
fi

# Output/input ratio (capped)
out_in_ratio="$(phos_ds_ratio_clamped "$out_words" "$in_words" "$OUT_IN_RATIO_CAP")"

# ----------------------------
# 5) Metrics (raw; dimension aligned)
# ----------------------------
# Coverage (stubs until you wire $REF_IDS_TXT to an available upstream set):
ref_cov="0.0000"
internal_cov="0.0000"
cat_cov="0.0000"
row_fill="0.0000"

# Diversity (stopword-filtered and length-filtered inside the shared lib)
div_stats="$(phos_ds_entropy_stats "$CORPUS_CLEAN_TXT")"
out_tokens="$(echo "$div_stats" | awk -F'\t' '{print $1}')"
unique_words="$(echo "$div_stats" | awk -F'\t' '{print $2}')"
H="$(echo "$div_stats" | awk -F'\t' '{print $3}')"
ent_norm="$(echo "$div_stats" | awk -F'\t' '{print $4}')"
uniq_ratio="$(echo "$div_stats" | awk -F'\t' '{print $5}')"

# Depth (fragment stats are meaningful only if you extract one fragment per line)
frag_stats="$(phos_ds_fragment_stats "$CORPUS_CLEAN_TXT")"
frag_count="$(echo "$frag_stats" | awk -F'\t' '{print $1}')"
frag_avg_words="$(echo "$frag_stats" | awk -F'\t' '{print $2}')"
two_sent_ratio="$(echo "$frag_stats" | awk -F'\t' '{print $3}')"

# Connectivity (optional; if you build a bipartite edges TSV)
edges=0
dens="0.0000"
avg_left="0.0000"
min_left=0
avg_right="0.0000"
min_right=0
multi_ratio="0.0000"

# TODO(domain): define what left/right sets represent and compute n_left/n_right.
n_left=0
n_right=0
multi_count=0
multi_total=0

if [[ -s "$EDGES_TSV" && "$n_left" -gt 0 && "$n_right" -gt 0 ]]; then
  con_stats="$(phos_ds_graph_stats_bipartite "$EDGES_TSV" "$n_left" "$n_right" "$multi_count" "$multi_total")"
  edges="$(echo "$con_stats" | awk -F'\t' '{print $1}')"
  dens="$(echo "$con_stats" | awk -F'\t' '{print $2}')"
  avg_left="$(echo "$con_stats" | awk -F'\t' '{print $3}')"
  min_left="$(echo "$con_stats" | awk -F'\t' '{print $4}')"
  avg_right="$(echo "$con_stats" | awk -F'\t' '{print $5}')"
  min_right="$(echo "$con_stats" | awk -F'\t' '{print $6}')"
  multi_ratio="$(echo "$con_stats" | awk -F'\t' '{print $7}')"
fi

# ----------------------------
# 6) Normalization (raw -> 0..100)
# ----------------------------
# NOTE: normalize ratios and corpus stats into 0..100 scores.
# Prefer input-scaled bounds where possible (e.g., out_in_ratio).

# Volume: reward output relative to input; full score at VOL_FULL_RATIO
s_vol_words="$(phos_ds_score_linear "$out_in_ratio" 0.0 "$VOL_FULL_RATIO")"

# Diversity: fixed predictable ranges (tunable per domain later)
s_div_ent_norm="$(phos_ds_score_linear "$ent_norm" 0.10 0.98)"
s_div_uniq_ratio="$(phos_ds_score_linear "$uniq_ratio" 0.10 0.25)"

# Depth: surface proxies
s_dep_frag_avg_words="$(phos_ds_score_linear "$frag_avg_words" 10 34)"
s_dep_two_sent_ratio="$(phos_ds_score_linear "$two_sent_ratio" 0.20 0.75)"

# Connectivity: only meaningful if dens/multi_ratio are wired; otherwise will remain low.
s_con_dens="$(phos_ds_score_linear "$dens" 0.10 0.50)"
s_con_multi_ratio="$(phos_ds_score_linear "$multi_ratio" 0.15 0.45)"

# ----------------------------
# 7) Scoring + levelling (scorebox)
# ----------------------------
# Default: 4-category scorebox (equal quarters).
# Each category is computed from its internal metric scores as a weighted average.

score_vol="$s_vol_words"
score_div="$(awk -v a="$s_div_ent_norm" -v b="$s_div_uniq_ratio" 'BEGIN{ printf "%.4f\n", (a+b)/2 }')"
score_dep="$(awk -v a="$s_dep_frag_avg_words" -v b="$s_dep_two_sent_ratio" 'BEGIN{ printf "%.4f\n", (a+b)/2 }')"
score_con="$(awk -v a="$s_con_dens" -v b="$s_con_multi_ratio" 'BEGIN{ printf "%.4f\n", (a+b)/2 }')"

# Levelling: overall is the clamped average of the 4 categories.
box="$(phos_ds_score_box_equal_quarters "$score_vol" "$score_div" "$score_dep" "$score_con")"
overall="$(echo "$box" | awk -F'\t' '{print $1}')"
score_vol="$(echo "$box" | awk -F'\t' '{print $2}')"
score_div="$(echo "$box" | awk -F'\t' '{print $3}')"
score_dep="$(echo "$box" | awk -F'\t' '{print $4}')"
score_con="$(echo "$box" | awk -F'\t' '{print $5}')"

# ----------------------------
# 8) Gates (hard fails; domain-defined)
# ----------------------------
gate_ok=1
gate_notes=()

# TODO(domain): add real gates (required files, required headings, schema validity, etc).
# Example patterns:
#   - required file present: [[ -f "$bundle/00-coversheet.md" ]] || { gate_ok=0; gate_notes+=("missing:coversheet"); }
#   - required section non-empty: grep -qE '^## Links$' "$file" || { gate_ok=0; gate_notes+=("missing:links"); }
#   - reject placeholders: grep -qE '^\[...\]$' "$file" && { gate_ok=0; gate_notes+=("placeholders"); }

result="$(awk -v s="$overall" -v m="$MIN_SCORE" -v g="$gate_ok" 'BEGIN{
  if (g+0 < 1) { print "FAIL"; exit }
  if (s+0 >= m+0) print "PASS"; else print "FAIL";
}')"

# ----------------------------
# 9) Reporting (stable)
# ----------------------------
if [[ "$QUIET" -ne 1 ]]; then
  echo "PHOSPHENE — Done Score  <<domain>>"
  echo "============================================================"
  echo "Result:    ${result}   Overall: ${overall}/100   Threshold: ${MIN_SCORE}"
  echo ""

  echo "Inputs:"
  if [[ -n "${INPUT_ROOT:-}" && -d "$INPUT_ROOT" ]]; then
    echo "  - input root: $INPUT_ROOT"
    echo "  - in_items:   $in_items"
    echo "  - in_words:   $in_words"
  else
    echo "  - input root: (none)"
    echo "  - in_items:   0"
    echo "  - in_words:   0"
  fi
  echo ""

  echo "Output:"
  if [[ -n "${FILE:-}" ]]; then
    echo "  - mode:       single-file"
    echo "  - file:       $FILE"
  elif [[ -n "${TARGET_PATH:-}" ]]; then
    echo "  - mode:       target-path scan"
    echo "  - target:     $TARGET_PATH"
  else
    echo "  - mode:       docs-root scan"
    echo "  - docs root:  $DOCS_ROOT"
  fi
  echo "  - out_items:  $out_items"
  echo "  - out_words:  $out_words"
  echo "  - out_lines:  $out_lines"
  echo "  - out_in_ratio(capped): $out_in_ratio   (cap=$OUT_IN_RATIO_CAP)"
  echo ""

  echo "Subscores (0–100):"
  printf "  - %-12s %6.2f\n" "volume" "$score_vol"
  printf "  - %-12s %6.2f  (ent_norm=%.4f, uniq_ratio=%.4f, unique_words=%s, H=%.4f)\n" "diversity" "$score_div" "$ent_norm" "$uniq_ratio" "$unique_words" "$H"
  printf "  - %-12s %6.2f  (frag_avg_words=%.4f, two_sent_ratio=%.4f, frag_count=%s)\n" "depth" "$score_dep" "$frag_avg_words" "$two_sent_ratio" "$frag_count"
  printf "  - %-12s %6.2f  (dens=%.4f, multi_ratio=%.4f, edges=%s)\n" "connectivity" "$score_con" "$dens" "$multi_ratio" "$edges"
  echo ""

  echo "Gates:"
  if [[ "$gate_ok" -eq 1 ]]; then
    echo "  - OK"
  else
    echo "  - FAIL: ${gate_notes[*]}"
  fi
  echo ""

  echo "Metric box (default equal-quarters levelling):"
  echo "  - volume:       out_in_ratio (full at --vol-full-ratio=$VOL_FULL_RATIO)"
  echo "  - diversity:    ent_norm + uniq_ratio"
  echo "  - depth:        frag_avg_words + two_sent_ratio"
  echo "  - connectivity: dens + multi_ratio"
  echo ""

  echo "Advice (one sentence per category if <90):"
  awk -v v="$score_vol" -v d="$score_div" -v dep="$score_dep" -v c="$score_con" '
    BEGIN{
      if (v+0 < 90)   print "  - volume: increase substantive output relative to upstream input (or add inputs and wire input-anchoring).";
      if (d+0 < 90)   print "  - diversity: reduce templated phrasing; add more distinct wording and angles grounded in inputs.";
      if (dep+0 < 90) print "  - depth: rewrite fragments into 2–3 sentence mini-arguments (context + why + tradeoff/edge-case).";
      if (c+0 < 90)   print "  - connectivity: extract and score real edges (IDs + mappings), then increase linkage density and multi-targeting.";
    }
  '
fi

awk -v s="$overall" -v m="$MIN_SCORE" -v g="$gate_ok" 'BEGIN{
  if (g+0 < 1) exit 1;
  exit (s+0 >= m+0) ? 0 : 1;
}'


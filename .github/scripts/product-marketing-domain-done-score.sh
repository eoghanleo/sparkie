#!/usr/bin/env bash
set -euo pipefail

# product-marketing-domain-done-score.sh
# Programmatic scoring (no generation) for <product-marketing> value-space mining richness.
#
# Goals:
# - Force recursive exploration by making "minimum-fill" patterns score poorly.
# - Reward breadth + depth + interconnection (overlap) across personas <-> propositions.
# - Stay bash-native (bash + awk + sed/grep/wc + gzip if available).
# - Deterministic by construction for the same tree state across environments.
#
# Determinism contract:
# - Locale + timezone are forced to stable values.
# - File discovery is sorted.
# - Scoring output must be identical across runners for the same tree state.

#
# Usage:
#   ./.github/scripts/product-marketing-domain-done-score.sh
#   ./.github/scripts/product-marketing-domain-done-score.sh --min-score 80
#   ./.github/scripts/product-marketing-domain-done-score.sh --docs-root phosphene/domains/product-marketing/output
#
# Exit codes:
#   0 = score >= min-score
#   1 = score < min-score
#   2 = usage / configuration error

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
  ./.github/scripts/product-marketing-domain-done-score.sh [--docs-root <dir>] [--input-research-root <dir>] [--min-score <0..100>] [--quiet]

Notes:
  - This script is programmatic only (it does not generate content).
  - It scores breadth + depth + interconnection across PER/PROP artifacts.
EOF
}

fail() { echo "FAIL: $*" >&2; exit 2; }

ROOT="$(phosphene_find_project_root)"
DOCS_ROOT="$ROOT/phosphene/domains/product-marketing/output"
INPUT_RESEARCH_ROOT="$ROOT/phosphene/domains/research/output"
MIN_SCORE="80"
QUIET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --docs-root) DOCS_ROOT="${2:-}"; shift 2 ;;
    --input-research-root) INPUT_RESEARCH_ROOT="${2:-}"; shift 2 ;;
    --min-score) MIN_SCORE="${2:-}"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "$DOCS_ROOT" != /* ]]; then DOCS_ROOT="$ROOT/$DOCS_ROOT"; fi
[[ -d "$DOCS_ROOT" ]] || fail "Missing docs root dir: $DOCS_ROOT"

if [[ "$INPUT_RESEARCH_ROOT" != /* ]]; then INPUT_RESEARCH_ROOT="$ROOT/$INPUT_RESEARCH_ROOT"; fi
[[ -d "$INPUT_RESEARCH_ROOT" ]] || fail "Missing input research root dir: $INPUT_RESEARCH_ROOT"

if ! phos_ds_assert_numeric_0_100 "$MIN_SCORE"; then
  fail "--min-score must be numeric (0..100)"
fi

# Collect PER/PROP artifacts anywhere under output root.
# Supports both legacy layout (output/personas + output/propositions) and VPD bundles
# (output/value-proposition-designs/**/10-personas + 20-propositions).
PERSONA_FILES=()
PROP_FILES=()

# Stable ordering, bash 3.2 friendly (no mapfile/readarray).
while IFS= read -r f; do
  [[ -n "${f:-}" ]] || continue
  PERSONA_FILES+=("$f")
done < <(phos_ds_collect_files "$DOCS_ROOT" "PER-*.md")

while IFS= read -r f; do
  [[ -n "${f:-}" ]] || continue
  PROP_FILES+=("$f")
done < <(phos_ds_collect_files "$DOCS_ROOT" "PROP-*.md")

N_PER="${#PERSONA_FILES[@]}"
N_PROP="${#PROP_FILES[@]}"

if [[ "$N_PER" -eq 0 && "$N_PROP" -eq 0 ]]; then
  fail "No PER/PROP artifacts found under: $DOCS_ROOT"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
PERSONAS_TSV="$tmp/personas.tsv"
PROPS_TSV="$tmp/props.tsv"
EDGES_TSV="$tmp/edges.tsv"   # prop_id<TAB>per_id
CORPUS_TXT="$tmp/corpus_fragments.txt"  # one fragment per line (JTBD/booster/reliever/capability text only)
CORPUS_CLEAN_TXT="$tmp/corpus_clean.txt" # cleaned corpus (no IDs/tags/paths/scripts), used for ALL corpus-derived metrics

: > "$PERSONAS_TSV"
: > "$PROPS_TSV"
: > "$EDGES_TSV"
: > "$CORPUS_TXT"
: > "$CORPUS_CLEAN_TXT"

sum_words=0
sum_chars=0

sum_boosters=0
sum_relievers=0
sum_caps=0
sum_mapped_gains_items=0
sum_mapped_gains_rows=0
sum_mapped_pains_items=0
sum_mapped_pains_rows=0

props_multi_target=0

clean_corpus() {
  # Remove IDs/tags/paths/scripts so they don't count toward ANY corpus-derived metric.
  # Keep sentence punctuation so the sentence-ratio metric still works.
  phos_ds_clean_text_common \
    's/JTBD-(JOB|PAIN|GAIN)-[0-9]{4}-PER-[0-9]{4}/ /g' \
    's/(BOOST|REL|CAP)-[0-9]{4}-PROP-[0-9]{4}/ /g' \
    's/(PER|PROP|CPE|SEG|PITCH|RA|E)-[0-9]{3,4}/ /g' \
    < "$CORPUS_TXT" > "$CORPUS_CLEAN_TXT"
}

clean_markdown_tree_words() {
  # Compute cleaned word count across an upstream markdown corpus directory.
  local dir="$1"
  phos_ds_clean_markdown_tree_words "$dir" \
    's/JTBD-(JOB|PAIN|GAIN)-[0-9]{4}-PER-[0-9]{4}/ /g' \
    's/(BOOST|REL|CAP)-[0-9]{4}-PROP-[0-9]{4}/ /g' \
    's/(PER|PROP|CPE|SEG|PITCH|RA|E)-[0-9]{3,4}/ /g'
}

# PERSONAS: counts + traceability density
# NOTE: bash 3.2 + `set -u` treats empty arrays as "unbound" on `${arr[@]}` expansion.
if [[ "$N_PER" -gt 0 ]]; then
  for f in "${PERSONA_FILES[@]}"; do
    per_id="$(awk -F': ' '/^ID: PER-[0-9]{4}$/{print $2; exit}' "$f")"
    [[ -n "${per_id:-}" ]] || continue

    words="$(wc -w < "$f" | awk '{print $1}')"
    chars="$(wc -c < "$f" | awk '{print $1}')"
    sum_words=$((sum_words + words))
    sum_chars=$((sum_chars + chars))

    jobs="$(grep -cE "^[|][[:space:]]*JTBD-JOB-[0-9]{4}-${per_id}[[:space:]]*[|]" "$f" || true)"
    pains="$(grep -cE "^[|][[:space:]]*JTBD-PAIN-[0-9]{4}-${per_id}[[:space:]]*[|]" "$f" || true)"
    gains="$(grep -cE "^[|][[:space:]]*JTBD-GAIN-[0-9]{4}-${per_id}[[:space:]]*[|]" "$f" || true)"

    # Corpus: JTBD fragment text (column 3) only
    # Table shape: | JTBD-ID | Job/Pain/Gain | Importance |
    awk -F'|' -v per="$per_id" '
      function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
      $0 ~ /^[|][[:space:]]*JTBD-(JOB|PAIN|GAIN)-[0-9]{4}-/ && $0 ~ ("-" per "[[:space:]]*[|]") {
        txt=trim($3);
        if (txt!="" && txt!="<...>") print txt;
      }
    ' "$f" >> "$CORPUS_TXT"

    # Corpus: include all agent-composed prose (snapshot summary + notes)
    phos_ds_append_section_text "$f" "## Snapshot summary" >> "$CORPUS_TXT" || true
    phos_ds_append_section_text "$f" "## Notes" >> "$CORPUS_TXT" || true

    evidence_ids="$(awk '
      $0=="### EvidenceIDs" {inside=1; next}
      inside && $0 ~ /^### / {exit}
      inside && $0 ~ /^## / {exit}
      inside && $0 ~ /^-[[:space:]]+E-[0-9]{4}[[:space:]]*$/ {c++}
      END{print c+0}
    ' "$f")"
    cpe_ids="$(awk '
      $0=="### CandidatePersonaIDs" {inside=1; next}
      inside && $0 ~ /^### / {exit}
      inside && $0 ~ /^## / {exit}
      inside && $0 ~ /^-[[:space:]]+CPE-[0-9]{4}[[:space:]]*$/ {c++}
      END{print c+0}
    ' "$f")"
    doc_ids="$(awk '
      $0=="### DocumentIDs" {inside=1; next}
      inside && $0 ~ /^### / {exit}
      inside && $0 ~ /^## / {exit}
      inside && $0 ~ /^-[[:space:]]+[^[:space:]].*$/ {c++}
      END{print c+0}
    ' "$f")"

    printf "%s\t%d\t%d\t%d\t%d\t%d\t%d\t%s\n" "$per_id" "$jobs" "$pains" "$gains" "$evidence_ids" "$cpe_ids" "$doc_ids" "$(basename "$f")" >> "$PERSONAS_TSV"
  done
fi

# PROPS: counts + mapping density + target graph
if [[ "$N_PROP" -gt 0 ]]; then
for f in "${PROP_FILES[@]}"; do
  prop_id="$(awk -F': ' '/^ID: PROP-[0-9]{4}$/{print $2; exit}' "$f")"
  [[ -n "${prop_id:-}" ]] || continue

  words="$(wc -w < "$f" | awk '{print $1}')"
  chars="$(wc -c < "$f" | awk '{print $1}')"
  sum_words=$((sum_words + words))
  sum_chars=$((sum_chars + chars))

  boosters="$(grep -cE "^[|][[:space:]]*BOOST-[0-9]{4}-${prop_id}[[:space:]]*[|]" "$f" || true)"
  relievers="$(grep -cE "^[|][[:space:]]*REL-[0-9]{4}-${prop_id}[[:space:]]*[|]" "$f" || true)"
  caps="$(grep -cE "^[|][[:space:]]*CAP-[0-9]{4}-${prop_id}[[:space:]]*[|]" "$f" || true)"
  sum_boosters=$((sum_boosters + boosters))
  sum_relievers=$((sum_relievers + relievers))
  sum_caps=$((sum_caps + caps))

  targets="$(awk '
    BEGIN {inside=0;}
    $0=="## Target Persona(s)" {inside=1; next}
    inside && $0 ~ /^## / {exit}
    inside && $0 ~ /^-[[:space:]]+PER-[0-9]{4}[[:space:]]*$/ {
      sub(/^-+[[:space:]]+/, "", $0);
      gsub(/[[:space:]]+$/, "", $0);
      print $0;
    }
  ' "$f" | sort -u)"
  tcount="$(printf "%s\n" "$targets" | grep -cE '^PER-[0-9]{4}$' || true)"
  if [[ "$tcount" -ge 2 ]]; then props_multi_target=$((props_multi_target + 1)); fi

  if [[ -n "${targets:-}" ]]; then
    while IFS= read -r per; do
      [[ -n "$per" ]] || continue
      printf "%s\t%s\n" "$prop_id" "$per" >> "$EDGES_TSV"
    done <<< "$targets"
  fi

  while IFS= read -r n; do
    sum_mapped_gains_items=$((sum_mapped_gains_items + n))
    sum_mapped_gains_rows=$((sum_mapped_gains_rows + 1))
  done < <(awk -F'|' -v pid="$prop_id" '
    $0 ~ /^[|][[:space:]]*BOOST-[0-9]{4}-/ && $0 ~ ("-" pid "[[:space:]]*[|]") {
      col=$4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", col);
      if (col=="" || col=="<...>") { print 0; next }
      n=split(col, a, /,/);
      c=0;
      for (i=1;i<=n;i++){ x=a[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); if (x!="") c++; }
      print c;
    }
  ' "$f")

  while IFS= read -r n; do
    sum_mapped_pains_items=$((sum_mapped_pains_items + n))
    sum_mapped_pains_rows=$((sum_mapped_pains_rows + 1))
  done < <(awk -F'|' -v pid="$prop_id" '
    $0 ~ /^[|][[:space:]]*REL-[0-9]{4}-/ && $0 ~ ("-" pid "[[:space:]]*[|]") {
      col=$4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", col);
      if (col=="" || col=="<...>") { print 0; next }
      n=split(col, a, /,/);
      c=0;
      for (i=1;i<=n;i++){ x=a[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); if (x!="") c++; }
      print c;
    }
  ' "$f")

  printf "%s\t%d\t%d\t%d\t%d\t%s\n" "$prop_id" "$boosters" "$relievers" "$caps" "$tcount" "$(basename "$f")" >> "$PROPS_TSV"

  # Corpus: proposition fragment text only (exclude mapped ID columns)
  awk -F'|' -v pid="$prop_id" '
    function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
    $0 ~ /^[|][[:space:]]*BOOST-[0-9]{4}-/ && $0 ~ ("-" pid "[[:space:]]*[|]") {
      txt=trim($3);
      if (txt!="" && txt!="<...>") print txt;
    }
    $0 ~ /^[|][[:space:]]*REL-[0-9]{4}-/ && $0 ~ ("-" pid "[[:space:]]*[|]") {
      txt=trim($3);
      if (txt!="" && txt!="<...>") print txt;
    }
    $0 ~ /^[|][[:space:]]*CAP-[0-9]{4}-/ && $0 ~ ("-" pid "[[:space:]]*[|]") {
      txt=trim($4);
      if (txt!="" && txt!="<...>") print txt;
    }
  ' "$f" >> "$CORPUS_TXT"

  # Corpus: include all agent-composed prose (formal pitch + notes)
  phos_ds_append_section_text "$f" "## Formal Pitch" >> "$CORPUS_TXT" || true
  phos_ds_append_section_text "$f" "## Notes" >> "$CORPUS_TXT" || true
done
fi

EDGES="$(wc -l < "$EDGES_TSV" | awk '{print $1}')"

# Upstream input inventory (research)
INPUT_RESEARCH_ARTIFACTS="$(find "$INPUT_RESEARCH_ROOT" -type f -name "*.md" 2>/dev/null | wc -l | awk '{print $1}')"
INPUT_RESEARCH_WORDS="$(clean_markdown_tree_words "$INPUT_RESEARCH_ROOT")"

# Build cleaned corpus for ALL corpus-derived metrics (volume/diversity/depth).
clean_corpus

# Diversity from cleaned corpus (stopword filtered; length filtered).
# Outputs: out_tokens \t unique_words \t H \t ent_norm \t uniq_ratio
div_stats="$(phos_ds_entropy_stats "$CORPUS_CLEAN_TXT")"
unique_words="$(echo "$div_stats" | awk -F'\t' '{print $2}')"
H="$(echo "$div_stats" | awk -F'\t' '{print $3}')"
ent_norm="$(echo "$div_stats" | awk -F'\t' '{print $4}')"
uniq_ratio="$(echo "$div_stats" | awk -F'\t' '{print $5}')"

frag_stats="$(phos_ds_fragment_stats "$CORPUS_CLEAN_TXT")"
frag_count="$(echo "$frag_stats" | awk -F'\t' '{print $1}')"
frag_avg_words="$(echo "$frag_stats" | awk -F'\t' '{print $2}')"
two_sent_ratio="$(echo "$frag_stats" | awk -F'\t' '{print $3}')"

connect_metrics="$(phos_ds_graph_stats_bipartite "$EDGES_TSV" "$N_PROP" "$N_PER" "$props_multi_target" "$N_PROP")"
dens_pp="$(echo "$connect_metrics" | awk -F'\t' '{print $2}')"
min_right="$(echo "$connect_metrics" | awk -F'\t' '{print $4}')"
multi_ratio="$(echo "$connect_metrics" | awk -F'\t' '{print $7}')"

## NOTE: saturation-style “coverage” metrics intentionally removed from scoring for now.
## The shortlist focuses on monotonic earnable metrics (no penalties). Coverage can be reintroduced later as a positive metric.

avg_boosters="$(awk -v s="$sum_boosters" -v n="$N_PROP" 'BEGIN{ if (n<=0) print 0; else printf "%.4f\n", (s/n) }')"
avg_relievers="$(awk -v s="$sum_relievers" -v n="$N_PROP" 'BEGIN{ if (n<=0) print 0; else printf "%.4f\n", (s/n) }')"
avg_caps="$(awk -v s="$sum_caps" -v n="$N_PROP" 'BEGIN{ if (n<=0) print 0; else printf "%.4f\n", (s/n) }')"
avg_mapped_gains="$(awk -v s="$sum_mapped_gains_items" -v n="$sum_mapped_gains_rows" 'BEGIN{ if (n<=0) print 0; else printf "%.4f\n", (s/n) }')"
avg_mapped_pains="$(awk -v s="$sum_mapped_pains_items" -v n="$sum_mapped_pains_rows" 'BEGIN{ if (n<=0) print 0; else printf "%.4f\n", (s/n) }')"

out_words="$(wc -w < "$CORPUS_CLEAN_TXT" | awk '{print $1}')"

# Persona upstream traceability density (non-domain artifact linkage)
avg_persona_evidence="$(awk -F'\t' '{s+=$5} END{ if (NR<=0) print 0; else printf "%.4f\n", (s/NR) }' "$PERSONAS_TSV")"
avg_persona_cpe="$(awk -F'\t' '{s+=$6} END{ if (NR<=0) print 0; else printf "%.4f\n", (s/NR) }' "$PERSONAS_TSV")"
avg_persona_docs="$(awk -F'\t' '{s+=$7} END{ if (NR<=0) print 0; else printf "%.4f\n", (s/NR) }' "$PERSONAS_TSV")"
avg_persona_upstream_refs="$(awk -v a="$avg_persona_evidence" -v b="$avg_persona_cpe" -v c="$avg_persona_docs" 'BEGIN{ printf "%.4f\n", (a+b+c) }')"

# Mapping coverage ratios (scale with persona pool size)
if [[ "$N_PER" -gt 0 ]]; then
  total_gain_ids="$(cat "${PERSONA_FILES[@]}" 2>/dev/null | { grep -hoE 'JTBD-GAIN-[0-9]{4}-PER-[0-9]{4}' || true; } | sort -u | wc -l | awk '{print $1}')"
  total_pain_ids="$(cat "${PERSONA_FILES[@]}" 2>/dev/null | { grep -hoE 'JTBD-PAIN-[0-9]{4}-PER-[0-9]{4}' || true; } | sort -u | wc -l | awk '{print $1}')"
else
  total_gain_ids=0
  total_pain_ids=0
fi

if [[ "$N_PROP" -gt 0 ]]; then
  mapped_gain_ids="$(cat "${PROP_FILES[@]}" 2>/dev/null | { grep -hoE 'JTBD-GAIN-[0-9]{4}-PER-[0-9]{4}' || true; } | sort -u | wc -l | awk '{print $1}')"
  mapped_pain_ids="$(cat "${PROP_FILES[@]}" 2>/dev/null | { grep -hoE 'JTBD-PAIN-[0-9]{4}-PER-[0-9]{4}' || true; } | sort -u | wc -l | awk '{print $1}')"
else
  mapped_gain_ids=0
  mapped_pain_ids=0
fi
internal_cov_gain="$(awk -v m="$mapped_gain_ids" -v t="$total_gain_ids" 'BEGIN{ if (t<=0) print 0; else printf "%.4f\n", (m/t) }')"
internal_cov_pain="$(awk -v m="$mapped_pain_ids" -v t="$total_pain_ids" 'BEGIN{ if (t<=0) print 0; else printf "%.4f\n", (m/t) }')"

# Input-linkage ratio: how many distinct research IDs are referenced by product-marketing artifacts,
# scaled against the number of available research artifacts.
research_refs_unique=0
refs_files=()
if [[ "$N_PER" -gt 0 ]]; then refs_files+=( "${PERSONA_FILES[@]}" ); fi
if [[ "$N_PROP" -gt 0 ]]; then refs_files+=( "${PROP_FILES[@]}" ); fi
if [[ "${#refs_files[@]}" -gt 0 ]]; then
  research_refs_unique="$(cat "${refs_files[@]}" 2>/dev/null | { grep -hoE '(RA|PITCH|E|SEG|CPE)-[0-9]{3,4}' || true; } | sort -u | wc -l | awk '{print $1}')"
fi
dens_input="$(awk -v r="$research_refs_unique" -v n="$INPUT_RESEARCH_ARTIFACTS" 'BEGIN{ if (n<=0) print 0; x=(r/n); if (x>1) x=1; printf "%.4f\n", x }')"

scores="$(awk -v out_words="$out_words" \
  -v in_words="$INPUT_RESEARCH_WORDS" \
  -v ent_norm="$ent_norm" -v uniq_ratio="$uniq_ratio" \
  -v favg="$frag_avg_words" -v two_sent="$two_sent_ratio" \
  -v gain_cov="$internal_cov_gain" -v pain_cov="$internal_cov_pain" \
  -v dens_pp="$dens_pp" -v mult="$multi_ratio" -v dens_in="$dens_input" '

function clamp(x, lo, hi){ return (x<lo)?lo:((x>hi)?hi:x); }
function score_linear(x, x0, x1){ return clamp((x - x0) / (x1 - x0), 0, 1) * 100; }

BEGIN {
  # -----------------------------
  # Ratio-based metric box (no penalties; earn-only; scales against input corpus)
  # -----------------------------
  # Max points by category (sum = 100; each category max = 25)
  MAX_VOL = 25;
  MAX_DIV = 25;
  MAX_DEP = 25;
  MAX_CON = 25;
  MAX_ALL = (MAX_VOL+MAX_DIV+MAX_DEP+MAX_CON);

  # Split points within categories (sum to 25 each)
  MAX_VOL_WORDS = 25;

  MAX_DIV_ENT   = 12.5;
  MAX_DIV_UNIQ  = 12.5;

  MAX_DEP_FAVG  = 10;
  MAX_DEP_2S    = 10;
  MAX_DEP_GAIN  = 2.5;
  MAX_DEP_PAIN  = 2.5;

  MAX_CON_DENS_PP = 10;
  MAX_CON_DENS_IN = 7.5;
  MAX_CON_MULT    = 7.5;

  # -----------------------------
  # Ratios
  # -----------------------------
  out_in_ratio = (in_words>0)?(out_words/in_words):0;                 # output vs input words
  # -----------------------------
  # Normalize to 0..100 (mostly linear; volume explicitly linear per spec)
  # -----------------------------
  s_vol = score_linear(out_in_ratio, 0.0, 0.50);

  # Diversity bounds (fixed; not user-configurable): linearly distribute reward over predictable ranges.
  s_ent = score_linear(ent_norm, 0.10, 0.98);
  s_uniq = score_linear(uniq_ratio, 0.10, 0.25);

  s_favg = score_linear(favg, 12, 30);
  s_2s   = score_linear(two_sent, 0.20, 0.75);
  s_gain = score_linear(gain_cov, 0.20, 0.80);
  s_pain = score_linear(pain_cov, 0.20, 0.80);

  s_dens_pp = score_linear(dens_pp, 0.10, 0.50);
  s_dens_in = score_linear(dens_in, 0.05, 0.35);
  s_mult    = score_linear(mult, 0.15, 0.45);

  # Points (earn-only)
  p_vol = (s_vol/100.0) * MAX_VOL_WORDS;
  p_div = (s_ent/100.0) * MAX_DIV_ENT + (s_uniq/100.0) * MAX_DIV_UNIQ;
  p_dep = (s_favg/100.0) * MAX_DEP_FAVG + (s_2s/100.0) * MAX_DEP_2S + (s_gain/100.0) * MAX_DEP_GAIN + (s_pain/100.0) * MAX_DEP_PAIN;
  p_con = (s_dens_pp/100.0) * MAX_CON_DENS_PP + (s_dens_in/100.0) * MAX_CON_DENS_IN + (s_mult/100.0) * MAX_CON_MULT;

  overall = clamp(((p_vol + p_div + p_dep + p_con) / MAX_ALL) * 100.0, 0, 100);
  vol = clamp((p_vol / MAX_VOL) * 100.0, 0, 100);
  div = clamp((p_div / MAX_DIV) * 100.0, 0, 100);
  dep = clamp((p_dep / MAX_DEP) * 100.0, 0, 100);
  con = clamp((p_con / MAX_CON) * 100.0, 0, 100);

  printf "%.2f\t%.2f\t%.2f\t%.2f\t%.2f\n", overall, vol, div, dep, con;
}
')"

overall="$(echo "$scores" | awk -F'\t' '{print $1}')"
score_vol="$(echo "$scores" | awk -F'\t' '{print $2}')"
score_div="$(echo "$scores" | awk -F'\t' '{print $3}')"
score_depth="$(echo "$scores" | awk -F'\t' '{print $4}')"
score_conn="$(echo "$scores" | awk -F'\t' '{print $5}')"

result="$(awk -v s="$overall" -v m="$MIN_SCORE" 'BEGIN{ if (s+0 >= m+0) print "PASS"; else print "FAIL" }')"

if [[ "$QUIET" -ne 1 ]]; then
  echo "PHOSPHENE — Done Score  <product-marketing>"
  echo "============================================================"
  echo "Result:    ${result}   Overall: ${overall}/100   Threshold: ${MIN_SCORE}"
  if [[ "$result" == "PASS" ]]; then
    echo ""
    echo "Next (registration): write your DONE signal when you’re truly complete:"
    echo "  - phosphene/signals/bus.jsonl"
    echo "    (append a DONE receipt line; include inputs/outputs/checks)"
  fi
  echo ""
  echo "Inputs:"
  echo "  - research: ${INPUT_RESEARCH_ARTIFACTS} markdown artifacts, ${INPUT_RESEARCH_WORDS} cleaned words"
  echo "  - output:   ${out_words} cleaned words (agent-written; IDs/scripts/tags excluded)"
  echo ""
  echo "Subscores (0–100):"
  printf "  - %-12s %6.2f\n" "volume" "$score_vol"
  printf "  - %-12s %6.2f  (H=%.4f bits/token, ent_norm=%.4f, unique_words=%d, uniq_ratio=%.4f)\n" "diversity" "$score_div" "$H" "$ent_norm" "$unique_words" "$uniq_ratio"
  printf "  - %-12s %6.2f  (frag_avg_words=%.4f, two_sent_ratio=%.4f, internal_cov_gain=%.4f, internal_cov_pain=%.4f)\n" "depth" "$score_depth" "$frag_avg_words" "$two_sent_ratio" "$internal_cov_gain" "$internal_cov_pain"
  printf "  - %-12s %6.2f  (dens_pp=%.4f, dens_input=%.4f, multi_ratio=%.4f)\n" "connectivity" "$score_conn" "$dens_pp" "$dens_input" "$multi_ratio"
  echo ""
  echo "Metric box (earn-only; max 25 points each):"
  echo "  - volume:       output_words/input_words (full points at 0.50)"
  echo "  - diversity:    ent_norm + uniq_ratio"
  echo "  - depth:        frag_avg_words + two_sent_ratio + internal_cov"
  echo "  - connectivity: dens_pp + dens_input + multi_ratio"
  echo ""
  echo "Advice (one sentence per category if <90):"
  awk -v v="$score_vol" -v d="$score_div" -v dep="$score_depth" -v c="$score_conn" '
    BEGIN{
      if (v+0 < 90)  print "  - volume: increase out_words toward ~0.50×in_words by adding more substantive fragments across JTBDs, boosters/relievers/capabilities, and notes.";
      if (d+0 < 90)  print "  - diversity: increase lexical variety by using more distinct wording and angles (avoid templated phrasing) while staying grounded in the research corpus.";
      if (dep+0 < 90) print "  - depth: rewrite fragments into 2–3 sentence mini-arguments with context + why + tradeoff/edge-case, and ensure mappings cover the persona JTBD set.";
      if (c+0 < 90)  print "  - connectivity: increase cross-linking by targeting propositions at multiple personas and referencing a broader slice of research artifacts in DocumentIDs/Links.";
    }
  '
fi

awk -v s="$overall" -v m="$MIN_SCORE" 'BEGIN{ exit (s+0 >= m+0) ? 0 : 1 }'

# Done-score template (standard script shape)

This doc is the **narrative + specification mirror** of the executable template at:

- `.codex/skills/phosphene/core/done-score-author/references/done-score-template.sh`

It defines the **standard done-score interface** and the **canonical variable contract** that must be shared by:

- domain done-score scripts (`.github/scripts/*-domain-done-score.sh`)
- the shared metrics library (`phosphene/phosphene-core/lib/phosphene_done_score_metrics.sh`)

The goal is that **if the bash template ever drifts or becomes corrupted**, you can compare it to this markdown and quickly restore the intended shape and contracts.

## What “standard” means

- **Deterministic**: `LC_ALL=C`, `LANG=C`, `TZ=UTC`; stable sorting for any file/ID list.
- **Composable**: discovery → extraction → cleaning → metrics → normalization → scorebox → gates → reporting.
- **Input-anchored by default**: prefer \(output / input\) ratios and input-derived targets.
- **Levelled**: overall score is always \(0..100\) and comparable across domains (default “equal quarters” scorebox).

## Mental model: two layers, one contract

Every domain done-score is a thin, domain-specific wrapper around shared primitives.

- **Domain script** (`.github/scripts/<domain>-domain-done-score.sh`)
  - Defines *what to score* (artifact patterns, required structure, extraction rules).
  - Defines *what the upstream input is* (if any) and how to anchor to it.
  - Wires extracted raw values into **canonical variables** (defined below).
  - Applies domain-appropriate gates (hard fails) and prints a stable report.

- **Shared metrics library** (`phosphene/phosphene-core/lib/phosphene_done_score_metrics.sh`)
  - Implements reusable, deterministic metric functions and scorers.
  - Provides stable, testable primitives for cleaning, ratios, entropy, graph stats, scoring, etc.

**The shared contract is the variable names.** Domain scripts must populate the canonical base names; shared metric functions must accept/emit those same base names.

## Script anatomy (module-by-module narrative)

The bash template is intentionally written as a “pipeline” with explicit intermediate files and explicit variables. This keeps done-scores:

- auditable (you can inspect the intermediates),
- testable (you can unit-test metric functions against fixed inputs),
- refactorable (you can migrate inline `awk` blocks into the shared library over time).

### 0) Preamble: determinism + shared libs (MUST)

**Intent**: make the run stable across environments and make helpers available.

**Invariants**:

- repo root is resolved (the template includes a local `ds__find_repo_root_from_dir` for location-independence)
- `phosphene_env.sh` is sourced first
- `phosphene_done_score_metrics.sh` is sourced immediately after
- `phos_ds_env_defaults` is called

### 1) CLI + defaults

**Intent**: define a uniform interface so workflows/tests can invoke done-scores consistently.

**Standard CLI patterns supported**:

- scan a docs root: `--docs-root <dir>`
- score a single artifact: `--file <path>`
- score a bundle directory: `<bundle_dir>` (positional target)

**Standard knobs** (domain can add more):

- `--min-score <0..100>`
- `--vol-full-ratio <float>`: full points at `out_in_ratio >= vol_full_ratio`
- `--out-in-cap <float>`: cap the ratio so tiny inputs don’t explode the score
- `--quiet`

**Contract**: CLI parsing should fail fast with exit code `2` on invalid args and should validate `--min-score` using the shared helper (`phos_ds_assert_numeric_0_100`).

### 2) Discovery (what files exist, and what are we scoring?)

**Intent**: deterministically find the target artifacts and (optionally) the upstream input corpus.

**Outputs**:

- `OUTPUT_FILES[]`: stable, sorted list of output artifacts that will be scored
- `out_items`: count of scored artifacts

**Invariants**:

- file discovery is sorted (use `phos_ds_collect_files` or `find ... | sort`)
- “no artifacts” is a config error (exit `2`) rather than a score of `0`

### 3) Extraction → canonical intermediates (the key to standardization)

**Intent**: turn messy domain markdown into **simple intermediate files** that metric functions can consume.

This is the most important standardization layer for future expansion. We want:

1) extraction to be domain-aware (tables/sections),
2) metric calculations to be generic and reusable.

**Canonical intermediate files used by the template**:

- `CORPUS_TXT`: one semantic fragment per line (un-cleaned, but already stripped of obvious boilerplate)
- `CORPUS_CLEAN_TXT`: cleaned fragments used for *all corpus-derived metrics*
- `OUT_IDS_TXT`: (optional) unique IDs created in the output
- `REF_IDS_TXT`: (optional) unique upstream IDs referenced by the output
- `EDGES_TSV`: (optional) generic bipartite edges for connectivity metrics (`left<TAB>right`)

**Extraction rules (recommended)**:

- Prefer extracting “meaning-bearing” table columns (exclude ID columns).
- Prefer extracting specific H2 sections using shared helpers like `phos_ds_append_section_text`.
- Ensure fragment granularity makes sense: fragment-based depth metrics assume “one fragment per line”.

### 4) Cleaning (anti-gaming layer; corpus hardening)

**Intent**: ensure volume/diversity metrics represent substance, not scaffolding.

**Critical rule**: *All corpus-derived metrics must run on* `CORPUS_CLEAN_TXT` (not raw markdown).

Common cleaning steps (shared library functions):

- strip inline code, URLs, script paths (`phos_ds_clean_text_common`)
- remove IDs and other “cheap tokens” (domain-specific regexes)
- suppress token dumps (high comma density) (`phos_ds_filter_token_dump`)

### 5) Metrics (raw variables; dimension-aligned)

**Intent**: compute the canonical raw variables.

The template always computes:

- `out_words`, `out_lines`
- `in_words`, `in_items` (if an input root is provided)
- `out_in_ratio` (capped ratio)
- diversity stats (`ent_norm`, `uniq_ratio`, etc)
- depth stats (`frag_avg_words`, `two_sent_ratio`, etc)

It includes stubs for:

- coverage variables (`ref_cov`, `internal_cov`, `cat_cov`, `row_fill`)
- connectivity variables (`dens`, `multi_ratio`, etc) unless you populate `EDGES_TSV` and sizes

### 6) Normalization (raw → 0..100, input-anchored)

**Intent**: transform raw variables (ratios, counts, entropies) into comparable 0–100 metric scores.

Rules:

- Prefer shared helpers like `phos_ds_score_linear`.
- Prefer input-anchored normalization (e.g., score `out_in_ratio` instead of `out_words`).
- Keep bounds explicit and readable in the “Normalization” module (avoid hiding them deep inside `awk`).

### 7) Scoring + levelling (scorebox → overall)

**Intent**: turn normalized metric scores into:

- category subscores (0..100)
- a levelled overall score (0..100)

Default levelling:

- equal quarters scorebox: volume, diversity, depth, connectivity
- `overall = avg(vol, div, dep, con)` clamped to 0..100

This default is intentionally conservative: it makes overall scores comparable and avoids “one huge metric dominates the entire score.”

### 8) Gates (hard fails)

**Intent**: enforce non-negotiables that should *override* any numeric score.

Examples:

- required files/headings missing
- schema validity/parse failure
- “undefined terms” (domain-defined strict completeness)

**Contract**:

- maintain `gate_ok` and `gate_notes[]`
- overall result is FAIL if any gate fails, regardless of score

### 9) Reporting (stable, auditable output)

**Intent**: make the score explain itself.

Report should always include:

- PASS/FAIL, overall, threshold
- input and output counters (including `out_in_ratio`)
- subscores (volume/diversity/depth/connectivity)
- key metric values used to derive subscores
- gate results
- short advice (1 sentence per category if <90)

Formatting should be stable (avoid unordered maps, avoid timestamps).

## Reference skeleton (non-executable; for diffing)

This outline is intentionally “close to code” but is **not** meant to be executed. It exists so you can diff a real template script against the intended shape.

```text
#!/usr/bin/env bash
set -euo pipefail

# Shared libs (MUST)
SCRIPT_DIR=...
ROOT_FOR_LIB="$(ds__find_repo_root_from_dir "$SCRIPT_DIR")"
LIB_DIR="$ROOT_FOR_LIB/phosphene/phosphene-core/lib"
source "$LIB_DIR/phosphene_env.sh"
source "$LIB_DIR/phosphene_done_score_metrics.sh"
phos_ds_env_defaults

usage() { ... }
fail() { ... }

# 1) CLI + defaults
ROOT="$ROOT_FOR_LIB"
DOCS_ROOT_DEFAULT="$ROOT/phosphene/domains/<domain>/output"
INPUT_ROOT_DEFAULT=""
MIN_SCORE=...
VOL_FULL_RATIO=...
OUT_IN_RATIO_CAP=...
parse_args ...
validate_args ...

# 2) Discovery
resolve DOCS_ROOT / INPUT_ROOT / FILE / TARGET_PATH (absolute)
OUTPUT_FILES=( ...sorted... )
out_items="${#OUTPUT_FILES[@]}"

# 3) Extraction -> canonical intermediates
tmp="$(mktemp -d)"; trap cleanup
CORPUS_TXT=...; CORPUS_CLEAN_TXT=...
OUT_IDS_TXT=...; REF_IDS_TXT=...; EDGES_TSV=...
: > files (touch/clear)
extract_output_corpus_fragments() { ...domain-aware... }
for f in "${OUTPUT_FILES[@]}"; do
  extract_output_corpus_fragments "$f" >> "$CORPUS_TXT"
  # optional: fill OUT_IDS_TXT / REF_IDS_TXT / EDGES_TSV
done
sort -u OUT_IDS_TXT / REF_IDS_TXT / EDGES_TSV

# 4) Cleaning
clean_output_corpus() { phos_ds_clean_text_common ... | phos_ds_filter_token_dump > CORPUS_CLEAN_TXT; }
clean_output_corpus

# Volume base metrics
out_words="$(wc -w < "$CORPUS_CLEAN_TXT")"
out_lines="$(wc -l < "$CORPUS_CLEAN_TXT")"
in_items=0; in_words=0
if [[ -d "$INPUT_ROOT" ]]; then
  in_items="$(find "$INPUT_ROOT" ... | wc -l)"
  in_words="$(phos_ds_clean_markdown_tree_words "$INPUT_ROOT")"
fi
out_in_ratio="$(phos_ds_ratio_clamped "$out_words" "$in_words" "$OUT_IN_RATIO_CAP")"

# 5) Metrics (raw; canonical names)
ref_cov=... internal_cov=... cat_cov=... row_fill=...
div_stats="$(phos_ds_entropy_stats "$CORPUS_CLEAN_TXT")"  -> out_tokens unique_words H ent_norm uniq_ratio
frag_stats="$(phos_ds_fragment_stats "$CORPUS_CLEAN_TXT")" -> frag_count frag_avg_words two_sent_ratio
if EDGES_TSV wired:
  con_stats="$(phos_ds_graph_stats_bipartite ...)" -> edges dens avg_left min_left avg_right min_right multi_ratio

# 6) Normalization (raw -> 0..100)
s_vol_words="$(phos_ds_score_linear "$out_in_ratio" 0.0 "$VOL_FULL_RATIO")"
s_div_ent_norm="$(phos_ds_score_linear "$ent_norm" ...)"
...

# 7) Scoring + levelling (scorebox)
score_vol=...
score_div=...
score_dep=...
score_con=...
box="$(phos_ds_score_box_equal_quarters "$score_vol" "$score_div" "$score_dep" "$score_con")"
overall + subscores = parse box

# 8) Gates
gate_ok=1
gate_notes=()
domain gates may set gate_ok=0 and append to gate_notes
result = PASS/FAIL based on gate_ok AND overall>=MIN_SCORE

# 9) Reporting
print stable header
print Inputs / Output / Subscores / Gates / Metric box / Advice
exit 0 on PASS, 1 on FAIL, 2 on usage/config
```

## Canonical variable contract (dimension-aligned)

These base names come from `done-score-design.md`. Keep them identical between scripts and shared metric functions.

### Volume and activity

- `out_items`: count of scored output artifacts
- `out_words`: cleaned output corpus words
- `out_lines`: cleaned output corpus lines
- `in_items`: count of upstream input artifacts (if applicable)
- `in_words`: cleaned input corpus words (if applicable)
- `out_in_ratio`: output/input ratio (capped)
- `in_items_primary`: count of primary upstream inputs (optional)
- `in_words_primary`: cleaned primary input corpus words (optional)
- `in_items_secondary`: count of secondary upstream inputs (optional)
- `in_words_secondary`: cleaned secondary input corpus words (optional)
- `out_in_primary_ratio`: output/primary ratio (capped; optional)

### Coverage

- `ref_cov`: unique referenced / available upstream refs (clamped to 1.0)
- `internal_cov`: unique internal refs / created internal ids (clamped to 1.0)
- `cat_cov`: categories_with_items / total_required_categories (clamped to 1.0)
- `row_fill`: rows_filled / target_rows (clamped to 1.0)

### Diversity and novelty (textual)

From `phos_ds_entropy_stats`:

- `out_tokens`: total counted tokens (post filters)
- `unique_words`: unique token count
- `H`: Shannon entropy (bits/token)
- `ent_norm`: entropy normalized to \(0..1\)
- `uniq_ratio`: `unique_words / out_tokens` (after the same filters)

### Depth and reasoning

From `phos_ds_fragment_stats`:

- `frag_count`: fragment lines
- `frag_avg_words`: average words per fragment line
- `two_sent_ratio`: fragments containing ≥2 sentence punctuation markers / fragments

### Connectivity and traceability

From `phos_ds_graph_stats_bipartite` (when you provide `edges.tsv`, `n_left`, `n_right`):

- `edges`: number of edges
- `dens`: bipartite density \(edges/(n_left*n_right)\)
- `avg_left`, `min_left`
- `avg_right`, `min_right`
- `multi_ratio`: items_with_2plus_targets / items (optional)

## Normalization contract

Normalize raw metrics to **0..100** using shared helpers (e.g. `phos_ds_score_linear`), then roll up:

- **category scores**: 0..100
- **overall**: 0..100

Default levelling is “equal quarters”:

- `overall = avg(volume, diversity, depth, connectivity)` with clamping.

## Gates contract

Gates are **hard fails** (override score):

- Missing required artifacts/sections/tables
- Schema/parse failures
- “Undefined terms” or other strict completeness requirements (domain-defined)

Exit codes:

- `0`: score >= threshold AND gates pass
- `1`: score < threshold OR any gate fails
- `2`: usage/config errors

## Template invariants (corruption / drift checklist)

If the template script changes, it should still satisfy **all** of these checks:

### Must-have section markers

The script should contain these module headers (exact numbering is part of the “compare to markdown” contract):

- `1) CLI + defaults`
- `2) Discovery`
- `3) Extraction -> canonical intermediates`
- `4) Cleaning`
- `5) Metrics`
- `6) Normalization`
- `7) Scoring + levelling`
- `8) Gates`
- `9) Reporting`

### Must-source order

- sources `phosphene_env.sh`
- then sources `phosphene_done_score_metrics.sh`
- then calls `phos_ds_env_defaults`

### Must-populate canonical variables (at minimum)

Even in a minimal scorer, the template must compute and report:

- `out_items`
- `out_words`
- `out_in_ratio` (even if `in_words==0`, ratio must be defined deterministically as `0`)
- `ent_norm`, `uniq_ratio`
- `frag_avg_words`, `two_sent_ratio`
- `overall`, plus the four category subscores

### Must-use shared helpers (baseline)

The template must rely on shared library helpers for the foundational primitives:

- discovery: `phos_ds_collect_files`
- cleaning: `phos_ds_strip_codeblocks_and_tables`, `phos_ds_clean_text_common`, `phos_ds_filter_token_dump`
- input corpus: `phos_ds_clean_markdown_tree_words`
- ratios: `phos_ds_ratio_clamped`
- diversity: `phos_ds_entropy_stats`
- depth: `phos_ds_fragment_stats`
- scoring: `phos_ds_score_linear`, `phos_ds_score_box_equal_quarters`



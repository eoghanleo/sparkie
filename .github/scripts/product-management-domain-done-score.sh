#!/usr/bin/env bash
set -euo pipefail

# product-management-domain-done-score.sh
# Programmatic scoring (no generation) for <product-management> PRD bundle richness.
#
# Goals:
# - Make “minimum-fill” PRDs score poorly.
# - Reward substance (volume), diversity, depth, and interconnection (connectivity).
# - Keep it deterministic + bash-only (bash + awk + sed/grep/wc).
# - Scale to the *incoming* product-marketing work (VPD / PER / PROP) via input→output ratios.
#
# Determinism contract:
# - Locale + timezone are forced to stable values.
# - File discovery is sorted.
# - Scoring output must be identical across runners for the same tree state.

#
# Usage:
#   ./.github/scripts/product-management-domain-done-score.sh <bundle_dir> [--min-score 80] [--quiet]
#   ./.github/scripts/product-management-domain-done-score.sh <bundle_dir> --min-score 0
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
  ./.github/scripts/product-management-domain-done-score.sh <bundle_dir> [--min-score <0..100>] [--vol-full-ratio <float>] [--quiet]

Notes:
  - This is programmatic only (it does not generate content).
  - Inputs are inferred from the PRD coversheet Dependencies header:
      Dependencies: VPD-001, RA-001
    (VPD-### is used to locate PER/PROP inputs.)
  - The score is "earn-only": you only gain points by adding substance + linkages.

Score box (0–100):
  - volume (25):    out_words / in_words (full points at --vol-full-ratio; default 1.00)
  - diversity (25): ent_norm + uniq_ratio (stopword-filtered)
  - depth (25):     fragment_avg_words + two_sentence_ratio + requirements_fill_ratio + AC/telemetry fill
  - connectivity (25):
      - input linkage (PER/PROP refs to upstream set)
      - requirement linkage (REQ↔PER/PROP density + multi-target requirements)
      - PRD linkage (REQ↔F density + traceability coverage + trace rows fill)
EOF
}

fail() { echo "FAIL: $*" >&2; exit 2; }

BUNDLE_DIR=""
MIN_SCORE="80"
VOL_FULL_RATIO="1.00"
QUIET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --min-score) MIN_SCORE="${2:-}"; shift 2 ;;
    --vol-full-ratio) VOL_FULL_RATIO="${2:-}"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
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
[[ -d "$BUNDLE_DIR" ]] || fail "Missing bundle dir: $BUNDLE_DIR"

if ! phos_ds_assert_numeric_0_100 "$MIN_SCORE"; then
  fail "--min-score must be numeric (0..100)"
fi
if ! [[ "$VOL_FULL_RATIO" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  fail "--vol-full-ratio must be numeric"
fi

PHOSPHENE="$ROOT/phosphene/phosphene-core/bin/phosphene"
FUNC_REQ_FILE="$BUNDLE_DIR/60-requirements/functional.md"
TRACE_MATRIX_FILE="$BUNDLE_DIR/180-appendix/traceability-matrix.md"
FEATURE_DIR="$BUNDLE_DIR/70-feature-catalogue"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

CORPUS_TXT="$tmp/corpus_fragments.txt"          # one fragment per line
CORPUS_CLEAN_TXT="$tmp/corpus_clean.txt"        # cleaned fragments corpus for all corpus-derived metrics
REQ_IDS_TXT="$tmp/req_ids.txt"
FEATURE_IDS_TXT="$tmp/feature_ids.txt"
PRD_PER_REFS_TXT="$tmp/prd_per_refs.txt"
PRD_PROP_REFS_TXT="$tmp/prd_prop_refs.txt"
REQ_PER_EDGES="$tmp/req_per_edges.tsv"          # req_id<TAB>per_id
REQ_PROP_EDGES="$tmp/req_prop_edges.tsv"        # req_id<TAB>prop_id
FEAT_REQ_EDGES="$tmp/feat_req_edges.tsv"        # feat_id<TAB>req_id

TRACE_PROP_IDS_TXT="$tmp/trace_prop_ids.txt"
TRACE_FEAT_IDS_TXT="$tmp/trace_feat_ids.txt"
TRACE_REQ_IDS_TXT="$tmp/trace_req_ids.txt"

INPUT_VPD_IDS_TXT="$tmp/input_vpd_ids.txt"
INPUT_PER_IDS_TXT="$tmp/input_per_ids.txt"
INPUT_PROP_IDS_TXT="$tmp/input_prop_ids.txt"
INPUT_PM_CORPUS_TXT="$tmp/input_pm_fragments.txt"
INPUT_PM_CLEAN_TXT="$tmp/input_pm_clean.txt"

: > "$CORPUS_TXT"
: > "$CORPUS_CLEAN_TXT"
: > "$REQ_IDS_TXT"
: > "$FEATURE_IDS_TXT"
: > "$PRD_PER_REFS_TXT"
: > "$PRD_PROP_REFS_TXT"
: > "$REQ_PER_EDGES"
: > "$REQ_PROP_EDGES"
: > "$FEAT_REQ_EDGES"
: > "$TRACE_PROP_IDS_TXT"
: > "$TRACE_FEAT_IDS_TXT"
: > "$TRACE_REQ_IDS_TXT"
: > "$INPUT_VPD_IDS_TXT"
: > "$INPUT_PER_IDS_TXT"
: > "$INPUT_PROP_IDS_TXT"
: > "$INPUT_PM_CORPUS_TXT"
: > "$INPUT_PM_CLEAN_TXT"

read_header_value() {
  # Read a header value from coversheet, bounded to the header block (first blank line ends header).
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

clean_pm_corpus() {
  # Clean product-marketing corpus fragments (PER/PROP) so IDs/tags/paths don't count.
  phos_ds_clean_text_common \
    's/JTBD-(JOB|PAIN|GAIN)-[0-9]{4}-PER-[0-9]{4}/ /g' \
    's/(BOOST|REL|CAP)-[0-9]{4}-PROP-[0-9]{4}/ /g' \
    's/(PER|PROP|CPE|SEG|PITCH|RA|E|VPD|ROADMAP)-[0-9]{3,4}/ /g' \
    < "$INPUT_PM_CORPUS_TXT" > "$INPUT_PM_CLEAN_TXT"
}

clean_prd_corpus() {
  # Clean PRD corpus fragments: remove IDs/tags/paths/scripts and common placeholder-only patterns.
  # NOTE: This cleaning step is also a *score hardening* layer:
  # - We intentionally exclude "token dumps" (huge comma-separated seed lists and similar) because
  #   they inflate volume/diversity without adding actionable requirement substance.
  # - This keeps the score aligned to natural-language arguments and structured linkages.
  phos_ds_clean_text_common \
    's/(PER|PROP|CPE|SEG|PITCH|RA|E|VPD|ROADMAP|FR|PRD)-[0-9]{3,4}/ /g' \
    's/R-[A-Z]+-[0-9]{3}/ /g' \
    's/NFR-[A-Z]+-[0-9]{3}/ /g' \
    's/F-[A-Z]+-[0-9]{2}/ /g' \
    < "$CORPUS_TXT" \
    | phos_ds_filter_token_dump > "$CORPUS_CLEAN_TXT"
}

extract_input_vpds() {
  # Primary source: Dependencies header in coversheet.
  local deps
  deps=""
  if [[ -f "$BUNDLE_DIR/00-coversheet.md" ]]; then
    deps="$(read_header_value "$BUNDLE_DIR/00-coversheet.md" "Dependencies" || true)"
  fi
  if [[ -n "${deps:-}" ]]; then
    echo "$deps" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -E '^VPD-[0-9]{3}$' | sort -u > "$INPUT_VPD_IDS_TXT" || true
    return 0
  fi

  # Fallback (non-authoritative): any VPD IDs referenced anywhere in bundle.
  find "$BUNDLE_DIR" -type f -name "*.md" -print0 2>/dev/null \
    | xargs -0 grep -hoE 'VPD-[0-9]{3}' 2>/dev/null \
    | sort -u > "$INPUT_VPD_IDS_TXT" || true
}

index_input_personas_props() {
  local vpd
  while IFS= read -r vpd; do
    [[ -n "${vpd:-}" ]] || continue
    rel_path="$("$PHOSPHENE" id where "$vpd" 2>/dev/null | head -n 1 | awk -F'\t' '{print $3}' || true)"
    [[ -n "${rel_path:-}" ]] || continue
    vpd_dir="$(cd "$(dirname "$ROOT/$rel_path")" && pwd)"
    find "$vpd_dir" -type f -name "PER-*.md" 2>/dev/null | sort | while IFS= read -r f; do
      [[ -n "${f:-}" ]] || continue
      per_id="$(awk -F': ' '/^ID: PER-[0-9]{4}$/{print $2; exit}' "$f" || true)"
      [[ -n "${per_id:-}" ]] || continue
      echo "$per_id" >> "$INPUT_PER_IDS_TXT"

      # JTBD fragment text (column 3) only
      awk -F'|' -v per="$per_id" '
        function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
        $0 ~ /^[|][[:space:]]*JTBD-(JOB|PAIN|GAIN)-[0-9]{4}-/ && $0 ~ ("-" per "[[:space:]]*[|]") {
          txt=trim($3);
          if (txt!="" && txt!="<...>") print txt;
        }
      ' "$f" >> "$INPUT_PM_CORPUS_TXT"
      phos_ds_append_section_text "$f" "## Snapshot summary" >> "$INPUT_PM_CORPUS_TXT" || true
      phos_ds_append_section_text "$f" "## Notes" >> "$INPUT_PM_CORPUS_TXT" || true
    done

    find "$vpd_dir" -type f -name "PROP-*.md" 2>/dev/null | sort | while IFS= read -r f; do
      [[ -n "${f:-}" ]] || continue
      prop_id="$(awk -F': ' '/^ID: PROP-[0-9]{4}$/{print $2; exit}' "$f" || true)"
      [[ -n "${prop_id:-}" ]] || continue
      echo "$prop_id" >> "$INPUT_PROP_IDS_TXT"

      # Proposition fragment text only (exclude mapped ID columns)
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
      ' "$f" >> "$INPUT_PM_CORPUS_TXT"
      phos_ds_append_section_text "$f" "## Formal Pitch" >> "$INPUT_PM_CORPUS_TXT" || true
      phos_ds_append_section_text "$f" "## Notes" >> "$INPUT_PM_CORPUS_TXT" || true
    done
  done < "$INPUT_VPD_IDS_TXT"

  sort -u "$INPUT_PER_IDS_TXT" -o "$INPUT_PER_IDS_TXT" || true
  sort -u "$INPUT_PROP_IDS_TXT" -o "$INPUT_PROP_IDS_TXT" || true
}

append_prd_freeform_fragments() {
  local file="$1"
  awk '
    function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
    function is_placeholder(line){
      # Drop single-line placeholder blocks like: [ ... ] but keep real markdown links: [text](url)
      if (line ~ /^\[[^]]+\]$/ && line !~ /\]\(/) return 1;
      if (line ~ /^\[\.\.\.\]$/) return 1;
      if (line ~ /^<\.\.\.>$/) return 1;
      # Drop inline placeholder tokens (common in templates): [...], <...>, TBD
      if (line ~ /\[\.\.\.\]/) return 1;
      if (line ~ /<\.\.\.>/) return 1;
      if (tolower(line) == "tbd") return 1;
      return 0;
    }
    BEGIN{ fence=0; }
    {
      if ($0 ~ /^```/) { fence = !fence; next }
      if (fence) next
      if ($0 ~ /^[|]/) next            # tables handled separately
      if ($0 ~ /^#/) next              # headings
      if ($0 ~ /^[A-Za-z0-9_-]+:[[:space:]]*/) next  # coversheet header lines
      if ($0 ~ /^\[V-SCRIPT\]/) next
      line=$0
      line=trim(line)
      sub(/^-+[[:space:]]+/, "", line)
      if (line=="") next
      if (line ~ /^[[:space:]]*[A-Za-z0-9_.-]+[.]sh[[:space:]]*$/) next
      if (is_placeholder(line)) next
      print line
    }
  ' "$file"
}

append_prd_table_fragments() {
  # Functional requirements table: extract Statement + Acceptance Criteria + Telemetry + Notes.
  if [[ -f "$FUNC_REQ_FILE" ]]; then
    awk -F'|' '
      function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
      function is_cell_placeholder(x){
        x=trim(x);
        if (x=="") return 1;
        if (x=="[...]" || x=="<...>") return 1;
        # Any single bracket/angle placeholder token like [events], [KPI], <thing>
        if (x ~ /^\[[^][]+\]$/) return 1;
        if (x ~ /^<[^<>]+>$/) return 1;
        if (tolower(x)=="tbd") return 1;
        # Template-specific placeholders that should not earn points
        if (x=="Given/When/Then") return 1;
        return 0;
      }
      function add(x){ if (is_cell_placeholder(x)) return; print trim(x); }
      BEGIN{ req=0; i_req=0; i_stmt=0; i_per=0; i_prop=0; i_ac=0; i_tel=0; i_notes=0; }
      /^\|[[:space:]]*Req ID[[:space:]]*\|/{
        for (i=2;i<=NF;i++){
          h=trim($i);
          if (h=="Req ID") i_req=i;
          else if (h=="Statement") i_stmt=i;
          else if (h ~ /^Persona/) i_per=i;
          else if (h ~ /^Proposition/) i_prop=i;
          else if (h ~ /^Acceptance/) i_ac=i;
          else if (h=="Telemetry") i_tel=i;
          else if (h=="Notes") i_notes=i;
        }
        next
      }
      /^\|/{
        if ($0 ~ /^[[:space:]]*\|[[:space:]]*[-:]+[[:space:]]*\|/) next
        if (i_req==0) next
        rid=trim($(i_req));
        if (rid=="" || rid ~ /^Req ID$/) next
        # fragments
        if (i_stmt>0) add($(i_stmt));
        if (i_ac>0) add($(i_ac));
        if (i_tel>0) add($(i_tel));
        if (i_notes>0) add($(i_notes));
      }
    ' "$FUNC_REQ_FILE" >> "$CORPUS_TXT"
  fi

  # Non-functional requirements tables: capture scenario/control/threshold text.
  local nfr="$BUNDLE_DIR/60-requirements/non-functional.md"
  if [[ -f "$nfr" ]]; then
    awk -F'|' '
      function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
      function is_cell_placeholder(x){
        x=trim(x);
        if (x=="") return 1;
        if (x=="[...]" || x=="<...>") return 1;
        if (x ~ /^\[[^][]+\]$/) return 1;
        if (x ~ /^<[^<>]+>$/) return 1;
        if (tolower(x)=="tbd") return 1;
        return 0;
      }
      function add(x){ if (is_cell_placeholder(x)) return; print trim(x); }
      /^\|/{
        if ($0 ~ /^[[:space:]]*\|[[:space:]]*[-:]+[[:space:]]*\|/) next
        if ($0 ~ /^[[:space:]]*\|[[:space:]]*NFR ID[[:space:]]*\|/) next
        # skip non-table lines
        # treat any remaining table row: add cells except the first ID-ish cell
        for (i=3;i<=NF;i++) add($i)
      }
    ' "$nfr" >> "$CORPUS_TXT"
  fi
}

compute_table_rows() {
  local file="$1"
  local header_re="$2"
  awk -F'|' -v header_re="$header_re" '
    BEGIN{count=0}
    /^\|/ {
      if ($0 ~ /^[[:space:]]*\|[[:space:]]*[-:]+[[:space:]]*\|/) next
      if ($0 ~ header_re) next
      has_data=0
      for (i=2; i<=NF; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
        if ($i != "" && $i !~ /^[-:]+$/) { has_data=1; break }
      }
      if (has_data) count++
    }
    END{print count+0}
  ' "$file"
}

extract_req_edges_and_ids() {
  [[ -f "$FUNC_REQ_FILE" ]] || return 0
  # Outputs:
  # - $REQ_IDS_TXT (unique req IDs)
  # - $REQ_PER_EDGES / $REQ_PROP_EDGES (unique)
  # - requirement counts via stdout as:
  #     total_rows<TAB>multi_rows<TAB>ac_filled_rows<TAB>tel_filled_rows<TAB>gwt_rows
  awk -F'|' '
    function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
    function is_cell_placeholder(x){
      x=trim(x);
      if (x=="") return 1;
      if (x=="[...]" || x=="<...>") return 1;
      if (x ~ /^\[[^][]+\]$/) return 1;
      if (x ~ /^<[^<>]+>$/) return 1;
      if (tolower(x)=="tbd") return 1;
      if (x=="Given/When/Then") return 1;
      return 0;
    }
    function is_stmt_placeholder(x){
      x=trim(x);
      if (is_cell_placeholder(x)) return 1;
      # Template row uses: "The system shall…" (unicode ellipsis) or "The system shall..."
      if (x ~ /^The system shall/ && (x ~ /…/ || x ~ /\.\.\.$/)) return 1;
      return 0;
    }
    function split_ids(cell, re, out,    n,i,x,c){
      gsub(/[,;]/, " ", cell);
      n=split(cell, a, /[[:space:]]+/);
      c=0;
      for (i=1;i<=n;i++){
        x=a[i];
        if (x ~ re) {
          out[x]=1;
          c++;
        }
      }
      return c;
    }
    BEGIN{ i_req=0; i_stmt=0; i_per=0; i_prop=0; i_ac=0; i_tel=0; total=0; multi=0; ac_ok=0; tel_ok=0; gwt=0; }
    /^\|[[:space:]]*Req ID[[:space:]]*\|/{
      for (i=2;i<=NF;i++){
        h=trim($i);
        if (h=="Req ID") i_req=i;
        else if (h=="Statement") i_stmt=i;
        else if (h ~ /^Persona/) i_per=i;
        else if (h ~ /^Proposition/) i_prop=i;
        else if (h ~ /^Acceptance/) i_ac=i;
        else if (h=="Telemetry") i_tel=i;
      }
      next
    }
    /^\|/{
      if ($0 ~ /^[[:space:]]*\|[[:space:]]*[-:]+[[:space:]]*\|/) next
      if (i_req==0 || i_stmt==0) next
      rid=trim($(i_req));
      if (rid=="" || rid=="Req ID") next
      stmt=trim($(i_stmt));
      if (is_stmt_placeholder(stmt)) next
      total++
      req[rid]=1
      per_count=0; prop_count=0
      delete per; delete prop
      if (i_per>0) per_count=split_ids($(i_per), /^PER-[0-9]{4}$/, per)
      if (i_prop>0) prop_count=split_ids($(i_prop), /^PROP-[0-9]{4}$/, prop)
      for (p in per) print rid "\t" p > "'"$REQ_PER_EDGES"'"
      for (q in prop) print rid "\t" q > "'"$REQ_PROP_EDGES"'"
      if (per_count>=2 || prop_count>=2) multi++

      # Fill quality (earn-only): acceptance criteria and telemetry must be non-placeholder.
      if (i_ac>0 && !is_cell_placeholder($(i_ac))) ac_ok++
      if (i_tel>0 && !is_cell_placeholder($(i_tel))) tel_ok++

      # Testability proxy: AC contains at least one Given/When/Then token (case-insensitive).
      if (i_ac>0) {
        ac=trim($(i_ac));
        if (!is_cell_placeholder(ac)) {
          low=tolower(ac);
          if (low ~ /(^|[^a-z])(given|when|then)($|[^a-z])/) gwt++
        }
      }
    }
    END{
      for (r in req) print r > "'"$REQ_IDS_TXT"'"
      print total+0 "\t" multi+0 "\t" ac_ok+0 "\t" tel_ok+0 "\t" gwt+0
    }
  ' "$FUNC_REQ_FILE"
  sort -u "$REQ_IDS_TXT" -o "$REQ_IDS_TXT" || true
  sort -u "$REQ_PER_EDGES" -o "$REQ_PER_EDGES" || true
  sort -u "$REQ_PROP_EDGES" -o "$REQ_PROP_EDGES" || true
}

extract_feature_ids() {
  if [[ -d "$FEATURE_DIR" ]]; then
    find "$FEATURE_DIR" -type f -name "*.md" -print0 2>/dev/null \
      | xargs -0 grep -hoE 'F-[A-Z]+-[0-9]{2}' 2>/dev/null \
      | sort -u > "$FEATURE_IDS_TXT" || true
  fi
}

extract_feature_req_edges() {
  # Traceability matrix is the authoritative feature↔requirement mapping.
  # We intentionally DO NOT infer edges from raw co-occurrence in feature markdowns,
  # because template/example rows (and bulk ID lists) are easy to game.
  #
  # Side effects:
  # - append unique feat_id<tab>req_id edges to $FEAT_REQ_EDGES
  # - append unique IDs to $TRACE_*_IDS_TXT
  # - print substantive trace row count to stdout
  if [[ ! -f "$TRACE_MATRIX_FILE" ]]; then
    echo "0"
    return 0
  fi

  awk -F'|' '
    function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
    function is_cell_placeholder(x){
      x=trim(x);
      if (x=="") return 1;
      if (x=="[...]" || x=="<...>") return 1;
      if (x ~ /^\[[^][]+\]$/) return 1;
      if (x ~ /^<[^<>]+>$/) return 1;
      if (tolower(x)=="tbd") return 1;
      return 0;
    }
    function emit_ids(cell, re, out_file,    n,i,x){
      gsub(/[,;]/, " ", cell);
      n=split(cell, a, /[[:space:]]+/);
      for (i=1;i<=n;i++){
        x=trim(a[i]);
        if (x ~ re) print x >> out_file;
      }
    }
    function emit_pairs(fcell, rcell,    n,i,m,j,f,r){
      gsub(/[,;]/, " ", fcell);
      gsub(/[,;]/, " ", rcell);
      n=split(fcell, fa, /[[:space:]]+/);
      m=split(rcell, ra, /[[:space:]]+/);
      for (i=1;i<=n;i++){
        f=trim(fa[i]);
        if (f ~ /^F-[A-Z]+-[0-9]{2}$/) {
          for (j=1;j<=m;j++){
            r=trim(ra[j]);
            if (r ~ /^R-[A-Z]+-[0-9]{3}$/) print f "\t" r >> "'"$FEAT_REQ_EDGES"'";
          }
        }
      }
    }
    BEGIN{ rows=0; }
    /^\|/{
      if ($0 ~ /^[[:space:]]*\|[[:space:]]*[-:]+[[:space:]]*\|/) next
      if ($0 ~ /^[[:space:]]*\|[[:space:]]*Proposition ID[[:space:]]*\|/) next
      cap=trim($3);
      if (is_cell_placeholder(cap)) next
      rows++

      prop=trim($2);
      if (prop ~ /^PROP-[0-9]{4}$/) print prop >> "'"$TRACE_PROP_IDS_TXT"'";

      fcell=trim($4); rcell=trim($5);
      if (fcell!="") emit_ids(fcell, /^F-[A-Z]+-[0-9]{2}$/, "'"$TRACE_FEAT_IDS_TXT"'");
      if (rcell!="") emit_ids(rcell, /^R-[A-Z]+-[0-9]{3}$/, "'"$TRACE_REQ_IDS_TXT"'");
      if (fcell!="" && rcell!="") emit_pairs(fcell, rcell);
    }
    END{ print rows+0; }
  ' "$TRACE_MATRIX_FILE"

  sort -u "$FEAT_REQ_EDGES" -o "$FEAT_REQ_EDGES" || true
  sort -u "$TRACE_PROP_IDS_TXT" -o "$TRACE_PROP_IDS_TXT" || true
  sort -u "$TRACE_FEAT_IDS_TXT" -o "$TRACE_FEAT_IDS_TXT" || true
  sort -u "$TRACE_REQ_IDS_TXT" -o "$TRACE_REQ_IDS_TXT" || true
}

extract_prd_refs() {
  find "$BUNDLE_DIR" -type f -name "*.md" -print0 2>/dev/null \
    | xargs -0 grep -hoE 'PER-[0-9]{4}' 2>/dev/null \
    | sort -u > "$PRD_PER_REFS_TXT" || true
  find "$BUNDLE_DIR" -type f -name "*.md" -print0 2>/dev/null \
    | xargs -0 grep -hoE 'PROP-[0-9]{4}' 2>/dev/null \
    | sort -u > "$PRD_PROP_REFS_TXT" || true
}

# ----------------------------
# Inputs: locate VPDs and build input corpus stats
# ----------------------------
extract_input_vpds
index_input_personas_props
clean_pm_corpus

in_words="$(wc -w < "$INPUT_PM_CLEAN_TXT" | awk '{print $1}')"
input_personas="$(wc -l < "$INPUT_PER_IDS_TXT" | awk '{print $1}')"
input_props="$(wc -l < "$INPUT_PROP_IDS_TXT" | awk '{print $1}')"

# ----------------------------
# Output: build PRD corpus fragments + clean
# ----------------------------
while IFS= read -r f; do
  [[ -n "${f:-}" ]] || continue
  append_prd_freeform_fragments "$f" >> "$CORPUS_TXT" || true
done < <(find "$BUNDLE_DIR" -type f -name "*.md" 2>/dev/null | sort)

append_prd_table_fragments
clean_prd_corpus

out_words="$(wc -w < "$CORPUS_CLEAN_TXT" | awk '{print $1}')"

# Diversity stats from cleaned corpus (stopword-filtered; length filtered).
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

# Given/When/Then tokens (case-insensitive) across corpus fragments (pre-clean).
gwt_count="$(cat "$CORPUS_TXT" 2>/dev/null | awk '
  BEGIN{ c=0; }
  {
    for (i=1;i<=NF;i++) {
      t=$i
      gsub(/[^A-Za-z]/, "", t)
      t=tolower(t)
      if (t=="given" || t=="when" || t=="then") c++
    }
  }
  END{ print c+0 }
')"

# ----------------------------
# Structural counts (scaled; not "one row")
# ----------------------------
multi_req_rows=0
edge_meta="$(extract_req_edges_and_ids)"
if [[ -z "${edge_meta:-}" ]]; then
  edge_meta=$'0\t0\t0\t0\t0'
fi
req_total_rows="$(echo "$edge_meta" | awk -F'\t' '{print $1}')"
multi_req_rows="$(echo "$edge_meta" | awk -F'\t' '{print $2}')"
ac_filled_rows="$(echo "$edge_meta" | awk -F'\t' '{print $3}')"
tel_filled_rows="$(echo "$edge_meta" | awk -F'\t' '{print $4}')"
gwt_rows="$(echo "$edge_meta" | awk -F'\t' '{print $5}')"

# For scoring, we count only *substantive* requirement rows (template placeholder rows do not count).
func_req_rows="$req_total_rows"

extract_feature_ids
trace_rows="$(extract_feature_req_edges)"

n_req="$(wc -l < "$REQ_IDS_TXT" | awk '{print $1}')"
n_feat="$(wc -l < "$FEATURE_IDS_TXT" | awk '{print $1}')"

row_fill_ac="$(awk -v a="$ac_filled_rows" -v t="$req_total_rows" 'BEGIN{ if (t<=0) { print 0; exit } x=a/t; if (x>1) x=1; printf "%.4f\n", x }')"
row_fill_tel="$(awk -v a="$tel_filled_rows" -v t="$req_total_rows" 'BEGIN{ if (t<=0) { print 0; exit } x=a/t; if (x>1) x=1; printf "%.4f\n", x }')"
row_fill_gwt="$(awk -v a="$gwt_rows" -v t="$req_total_rows" 'BEGIN{ if (t<=0) { print 0; exit } x=a/t; if (x>1) x=1; printf "%.4f\n", x }')"

# Targets derived from input magnitude (avoid "one row is enough").
target_req_rows="$(awk -v p="$input_props" -v per="$input_personas" 'BEGIN{
  t=8;
  if (p*2 > t) t=p*2;
  if (per*1 > t) t=per*1;
  if (t<8) t=8;
  if (t>60) t=60;
  print t+0;
}')"
target_trace_rows="$(awk -v p="$input_props" -v r="$n_req" 'BEGIN{
  t=4;
  if (p > t) t=p;
  if (r/2 > t) t=int(r/2);
  if (t<4) t=4;
  if (t>80) t=80;
  print t+0;
}')"

row_fill_req="$(awk -v n="$func_req_rows" -v t="$target_req_rows" 'BEGIN{ if (t<=0) { print 0; exit } x=n/t; if (x>1) x=1; printf "%.4f\n", x }')"
trace_fill_ratio="$(awk -v n="$trace_rows" -v t="$target_trace_rows" 'BEGIN{ if (t<=0) { print 0; exit } x=n/t; if (x>1) x=1; printf "%.4f\n", x }')"

# ----------------------------
# Connectivity metrics
# ----------------------------
# Input linkage: how many upstream PER/PROP IDs are *actually used in requirements*,
# scaled to the upstream pool.
# This avoids giving free credit for template/example rows that happen to match real IDs.
ref_input_per="$(comm -12 <(sort -u "$INPUT_PER_IDS_TXT") <(cut -f2 "$REQ_PER_EDGES" 2>/dev/null | sort -u) | wc -l | awk '{print $1}')"
ref_input_prop="$(comm -12 <(sort -u "$INPUT_PROP_IDS_TXT") <(cut -f2 "$REQ_PROP_EDGES" 2>/dev/null | sort -u) | wc -l | awk '{print $1}')"
dens_input="$(awk -v a="$ref_input_per" -v b="$ref_input_prop" -v n="$input_personas" -v m="$input_props" 'BEGIN{
  d=n+m;
  if (d<=0) { print 0; exit }
  x=(a+b)/d;
  if (x>1) x=1;
  printf "%.4f\n", x;
}')"

edges_req_per="$(wc -l < "$REQ_PER_EDGES" | awk '{print $1}')"
edges_req_prop="$(wc -l < "$REQ_PROP_EDGES" | awk '{print $1}')"
dens_req_per="$(awk -v e="$edges_req_per" -v r="$n_req" -v p="$input_personas" 'BEGIN{ if (r<=0||p<=0) print 0; else printf "%.4f\n", (e/(r*p)) }')"
dens_req_prop="$(awk -v e="$edges_req_prop" -v r="$n_req" -v p="$input_props" 'BEGIN{ if (r<=0||p<=0) print 0; else printf "%.4f\n", (e/(r*p)) }')"
dens_req_link="$(awk -v a="$dens_req_per" -v b="$dens_req_prop" 'BEGIN{ printf "%.4f\n", ((a+b)/2) }')"

edges_feat_req="$(wc -l < "$FEAT_REQ_EDGES" | awk '{print $1}')"
dens_feat_req="$(awk -v e="$edges_feat_req" -v f="$n_feat" -v r="$n_req" 'BEGIN{ if (f<=0||r<=0) print 0; else printf "%.4f\n", (e/(f*r)) }')"

multi_req_ratio="$(awk -v m="$multi_req_rows" -v t="$req_total_rows" 'BEGIN{ if (t<=0) print 0; else printf "%.4f\n", (m/t) }')"

# Traceability coverage: how much of the PRD's own IDs appear in the traceability matrix.
trace_req_cov=0
trace_feat_cov=0
trace_req_ids="$(wc -l < "$TRACE_REQ_IDS_TXT" | awk '{print $1}')"
trace_feat_ids="$(wc -l < "$TRACE_FEAT_IDS_TXT" | awk '{print $1}')"
trace_req_cov="$(awk -v a="$trace_req_ids" -v t="$n_req" 'BEGIN{ if (t<=0) { print 0; exit } x=a/t; if (x>1) x=1; printf "%.4f\n", x }')"
trace_feat_cov="$(awk -v a="$trace_feat_ids" -v t="$n_feat" 'BEGIN{ if (t<=0) { print 0; exit } x=a/t; if (x>1) x=1; printf "%.4f\n", x }')"

# Internal coverage rewards: trace matrix ID coverage + row fill (substantive rows only).
prd_internal_cov="$(awk -v a="$trace_req_cov" -v b="$trace_feat_cov" -v c="$trace_fill_ratio" 'BEGIN{ printf "%.4f\n", ((a+b+c)/3) }')"

# ----------------------------
# Scoring (earn-only; 25 pts per category)
# ----------------------------
scores="$(awk -v out_words="$out_words" -v in_words="$in_words" -v vol_full="$VOL_FULL_RATIO" \
  -v ent_norm="$ent_norm" -v uniq_ratio="$uniq_ratio" \
  -v favg="$frag_avg_words" -v two_sent="$two_sent_ratio" -v row_fill_req="$row_fill_req" -v row_fill_ac="$row_fill_ac" -v row_fill_tel="$row_fill_tel" -v row_fill_gwt="$row_fill_gwt" \
  -v dens_in="$dens_input" -v dens_req="$dens_req_link" -v dens_fr="$dens_feat_req" \
  -v cov_internal="$prd_internal_cov" -v mult_req="$multi_req_ratio" -v trace_fill="$trace_fill_ratio" '

function clamp(x, lo, hi){ return (x<lo)?lo:((x>hi)?hi:x); }
function score_linear(x, x0, x1){ return clamp((x - x0) / (x1 - x0), 0, 1) * 100; }

BEGIN {
  MAX_VOL = 25; MAX_DIV = 25; MAX_DEP = 25; MAX_CON = 25; MAX_ALL = 100;

  # Category splits
  MAX_VOL_WORDS = 25;

  MAX_DIV_ENT   = 12.5;
  MAX_DIV_UNIQ  = 12.5;

  MAX_DEP_FAVG  = 9;
  MAX_DEP_2S    = 9;
  MAX_DEP_REQF  = 3;
  MAX_DEP_ACF   = 2;
  MAX_DEP_TELF  = 1;
  MAX_DEP_GWT   = 1;

  MAX_CON_IN    = 7.5;
  MAX_CON_REQ   = 7.5;
  MAX_CON_FR    = 5.0;
  MAX_CON_INT   = 3.0;
  MAX_CON_MULT  = 2.0;

  # Ratios
  out_in_ratio = (in_words>0)?(out_words/in_words):0;
  # Normalize to 0..100
  s_vol = score_linear(out_in_ratio, 0.0, vol_full);
  s_ent = score_linear(ent_norm, 0.10, 0.98);
  s_uniq = score_linear(uniq_ratio, 0.08, 0.22);

  s_favg = score_linear(favg, 10, 34);
  s_2s   = score_linear(two_sent, 0.20, 0.75);
  s_reqf = score_linear(row_fill_req, 0.10, 1.00);
  s_acf  = score_linear(row_fill_ac, 0.20, 0.85);
  s_telf = score_linear(row_fill_tel, 0.10, 0.75);
  s_gwt  = score_linear(row_fill_gwt, 0.10, 0.60);

  s_in   = score_linear(dens_in, 0.10, 0.80);
  s_req  = score_linear(dens_req, 0.05, 0.40);
  s_fr   = score_linear(dens_fr, 0.05, 0.50);
  s_int  = score_linear(cov_internal, 0.20, 0.85);
  s_mult = score_linear(mult_req, 0.10, 0.50);

  # Points (earn-only)
  p_vol = (s_vol/100.0) * MAX_VOL_WORDS;
  p_div = (s_ent/100.0) * MAX_DIV_ENT + (s_uniq/100.0) * MAX_DIV_UNIQ;
  p_dep = (s_favg/100.0) * MAX_DEP_FAVG + (s_2s/100.0) * MAX_DEP_2S + (s_reqf/100.0) * MAX_DEP_REQF + (s_acf/100.0) * MAX_DEP_ACF + (s_telf/100.0) * MAX_DEP_TELF + (s_gwt/100.0) * MAX_DEP_GWT;
  p_con = (s_in/100.0) * MAX_CON_IN + (s_req/100.0) * MAX_CON_REQ + (s_fr/100.0) * MAX_CON_FR + (s_int/100.0) * MAX_CON_INT + (s_mult/100.0) * MAX_CON_MULT;

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

# Pane readiness gates (presence + linkability + no undefined terms).
pane_ready=1
pane_notes=()
check_pane_heading() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if [[ ! -f "$file" ]]; then
    pane_ready=0
    pane_notes+=("missing:${label}")
    return 0
  fi
  if ! grep -qE "$pattern" "$file"; then
    pane_ready=0
    pane_notes+=("missing:${label}")
  fi
}

check_pane_heading "$BUNDLE_DIR/00-coversheet.md" '^## Links$' "links"
check_pane_heading "$BUNDLE_DIR/80-architecture.md" '^## 8[.]1 Architecture overview$' "architecture"
check_pane_heading "$BUNDLE_DIR/100-data-integrations.md" '^## 10[.]1 Data model overview$' "data-model"
check_pane_heading "$BUNDLE_DIR/50-success-metrics.md" '^## 5[.]3 KPI definitions$' "telemetry"
check_pane_heading "$BUNDLE_DIR/110-security-compliance.md" '^## 11[.]1 Data classification and handling$' "security"
check_pane_heading "$BUNDLE_DIR/140-testing-quality.md" '^## 14[.]1 Test pyramid and scope$' "test-harness"
check_pane_heading "$BUNDLE_DIR/130-delivery-roadmap.md" '^## 13[.]1 Program structure$' "delivery"
check_pane_heading "$BUNDLE_DIR/170-release-readiness.md" '^## 17[.]1 Launch strategy$' "release"
check_pane_heading "$BUNDLE_DIR/150-operations-support.md" '^## 15[.]1 Operational posture$' "ops"

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
    pane_ready=0
    pane_notes+=("glossary:undefined_terms")
  fi
fi

result="$(awk -v s="$overall" -v m="$MIN_SCORE" -v p="$pane_ready" 'BEGIN{
  if (p+0 < 1) { print "FAIL"; exit }
  if (s+0 >= m+0) print "PASS"; else print "FAIL";
}')"

if [[ "$QUIET" -ne 1 ]]; then
  echo "PHOSPHENE — Done Score  <product-management>"
  echo "============================================================"
  echo "Result:    ${result}   Overall: ${overall}/100   Threshold: ${MIN_SCORE}"
  if [[ "$result" == "PASS" ]]; then
    echo ""
    echo "Next (registration): write your DONE receipt when you’re truly complete:"
    echo "  - phosphene/signals/bus.jsonl"
  fi
  echo ""
  echo "Inputs (product-marketing):"
  echo "  - VPD(s): $(tr '\n' ' ' < "$INPUT_VPD_IDS_TXT" | sed -E 's/[[:space:]]+$//')"
  echo "  - personas: ${input_personas}, propositions: ${input_props}"
  echo "  - input:   ${in_words} cleaned words (agent-written; IDs/scripts/tags excluded)"
  echo ""
  echo "Output (product-management PRD):"
  echo "  - output:  ${out_words} cleaned words (IDs/scripts/tags excluded)"
  echo ""
  echo "Subscores (0–100):"
  printf "  - %-12s %6.2f\n" "volume" "$score_vol"
  printf "  - %-12s %6.2f  (H=%.4f bits/token, ent_norm=%.4f, unique_words=%d, uniq_ratio=%.4f)\n" "diversity" "$score_div" "$H" "$ent_norm" "$unique_words" "$uniq_ratio"
  printf "  - %-12s %6.2f  (frag_avg_words=%.4f, two_sent_ratio=%.4f, row_fill_req=%.4f, row_fill_ac=%.4f, row_fill_tel=%.4f, row_fill_gwt=%.4f)\n" "depth" "$score_depth" "$frag_avg_words" "$two_sent_ratio" "$row_fill_req" "$row_fill_ac" "$row_fill_tel" "$row_fill_gwt"
  printf "  - %-12s %6.2f  (dens_input=%.4f, dens_req_link=%.4f, dens_feat_req=%.4f, internal_cov=%.4f)\n" "connectivity" "$score_conn" "$dens_input" "$dens_req_link" "$dens_feat_req" "$prd_internal_cov"
  echo ""
  echo "Pane readiness:"
  if [[ "$pane_ready" -eq 1 ]]; then
    echo "  - OK"
  else
    echo "  - FAIL: ${pane_notes[*]}"
  fi
  echo ""
  echo "Key counters (scaled targets):"
  printf "  - functional requirement rows: %d (target=%d)\n" "$func_req_rows" "$target_req_rows"
  printf "    - AC filled rows:           %d/%d (%.4f)\n" "$ac_filled_rows" "$req_total_rows" "$row_fill_ac"
  printf "    - telemetry filled rows:    %d/%d (%.4f)\n" "$tel_filled_rows" "$req_total_rows" "$row_fill_tel"
  printf "    - rows with Given/When/Then:%d/%d (%.4f)\n" "$gwt_rows" "$req_total_rows" "$row_fill_gwt"
  printf "  - traceability matrix rows:    %d (target=%d)\n" "$trace_rows" "$target_trace_rows"
  printf "  - G/W/T tokens (bundle):       %d\n" "$gwt_count"
  printf "  - multi-target requirements:   %d/%d (%.4f)\n" "$multi_req_rows" "$req_total_rows" "$multi_req_ratio"
  echo ""
  echo "Advice (one sentence per category if <90):"
  awk -v v="$score_vol" -v d="$score_div" -v dep="$score_depth" -v c="$score_conn" '
    BEGIN{
      if (v+0 < 90)  print "  - volume: increase PRD substance relative to the incoming VPD corpus (target >= 1.0× input words by default).";
      if (d+0 < 90)  print "  - diversity: reduce templated phrasing and add more distinct, specific language grounded in the upstream personas/propositions.";
      if (dep+0 < 90) print "  - depth: expand fragments into 2–3 sentence mini-arguments (context + why + tradeoff/edge-case), increase the number of substantive requirement rows, and replace placeholders with real acceptance criteria + telemetry.";
      if (c+0 < 90)  print "  - connectivity: link requirements to PER/PROP IDs, link features to requirements, and ensure the traceability matrix references the same IDs.";
    }
  '
fi

awk -v s="$overall" -v m="$MIN_SCORE" -v p="$pane_ready" 'BEGIN{
  if (p+0 < 1) exit 1;
  exit (s+0 >= m+0) ? 0 : 1;
}'

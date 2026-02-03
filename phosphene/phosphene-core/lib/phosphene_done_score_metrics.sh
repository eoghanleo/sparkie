#!/usr/bin/env bash
set -euo pipefail

phos_ds_env_defaults() {
  export LC_ALL=C
  export LANG=C
  export TZ=UTC
}

phos_ds_assert_numeric_0_100() {
  local value="$1"
  if ! [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    return 1
  fi
  awk -v v="$value" 'BEGIN{ exit (v < 0 || v > 100) ? 1 : 0 }'
}

phos_ds_resolve_repo_root() {
  phosphene_find_project_root
}

phos_ds_resolve_abs_path() {
  local root="$1"
  local path="$2"
  if [[ "$path" != /* ]]; then
    path="$root/$path"
  fi
  echo "$path"
}

phos_ds_collect_files() {
  local dir="$1"
  local pattern="$2"
  find "$dir" -type f -name "$pattern" 2>/dev/null | sort
}

phos_ds_strip_codeblocks_and_tables() {
  awk '
    BEGIN{ fence=0; }
    /^```/ { fence = !fence; next }
    fence { next }
    /^[|]/ { next }
    { print }
  '
}

phos_ds_clean_text_common() {
  local extra=()
  if [[ "$#" -gt 0 ]]; then
    extra=("$@")
  fi

  local sed_args=(
    -e 's/`[^`]*`/ /g'
    -e 's#https?://[^[:space:]]+# #g'
    -e 's#file://[^[:space:]]+# #g'
    -e 's/[[:alnum:]_.-]+[.]sh\b/ /g'
  )

  if [[ "${#extra[@]}" -gt 0 ]]; then
    for expr in "${extra[@]}"; do
      sed_args+=(-e "$expr")
    done
  fi

  sed -E "${sed_args[@]}" \
    -e 's/[[:space:]]+/ /g' \
    -e 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

phos_ds_clean_markdown_tree_words() {
  local dir="$1"
  shift
  phos_ds_collect_files "$dir" "*.md" \
    | while IFS= read -r f; do
        [[ -n "${f:-}" ]] || continue
        cat "$f" 2>/dev/null
      done \
    | phos_ds_strip_codeblocks_and_tables \
    | phos_ds_clean_text_common "$@" \
    | wc -w | awk '{print $1}'
}

phos_ds_clean_markdown_tree_text() {
  local dir="$1"
  shift
  phos_ds_collect_files "$dir" "*.md" \
    | while IFS= read -r f; do
        [[ -n "${f:-}" ]] || continue
        cat "$f" 2>/dev/null
      done \
    | phos_ds_strip_codeblocks_and_tables \
    | phos_ds_clean_text_common "$@"
}

phos_ds_entropy_stats() {
  local file="$1"
  local stats
  stats="$(cat "$file" 2>/dev/null \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs '[:alnum:]' '\n' \
    | awk '
        BEGIN{
          split("a an the and or but if then else so to of in on for with without from into over under by as at is are was were be been being i you we they he she it my your our their this that these those not no yes", sw, " ");
          for (i in sw) stop[sw[i]]=1;
        }
        NF{
          w=$0;
          if (length(w) < 3) next;
          if (w ~ /^[0-9]+$/) next;
          if (stop[w]) next;
          cnt[w]++;
        }
        END{
          for (w in cnt) print w "\t" cnt[w];
        }
      ' \
    | sort -t $'\t' -k1,1 \
    | awk -F'\t' '
        { total += $2; uniq++; cnts[uniq] = $2; }
        END{
          if (total<=0) { printf "0\t0\t0.0000\t0.0000\t0.0000\n"; exit }
          H=0;
          for (i=1;i<=uniq;i++) {
            p = cnts[i]/total;
            H += (-p * (log(p)/log(2)));
          }
          ent_norm = (uniq>1 && H>0)?(H/(log(uniq)/log(2))):0;
          uniq_ratio = (total>0)?(uniq/total):0;
          printf "%d\t%d\t%.4f\t%.4f\t%.4f\n", total+0, uniq+0, H, ent_norm, uniq_ratio;
        }
      '
  )"
  echo "$stats"
}

phos_ds_fragment_stats() {
  local file="$1"
  awk '
    function sent_count(s){ c=0; for (i=1;i<=length(s);i++){ ch=substr(s,i,1); if (ch=="." || ch=="!" || ch=="?") c++; } return c; }
    BEGIN{ n=0; ge2=0; wsum=0; }
    {
      n++;
      w=split($0, a, /[[:space:]]+/);
      wsum += (w>0?w:0);
      sc=sent_count($0);
      if (sc>=2) ge2++;
    }
    END{
      avgw=(n>0)?(wsum/n):0;
      r=(n>0)?(ge2/n):0;
      printf "%d\t%.4f\t%.4f\n", n+0, avgw, r;
    }
  ' "$file"
}

phos_ds_ratio_clamped() {
  local num="$1"
  local denom="$2"
  local cap="$3"
  awk -v n="$num" -v d="$denom" -v c="$cap" 'BEGIN{
    if (d<=0) { print 0; exit }
    r=n/d;
    if (c>0 && r>c) r=c;
    printf "%.4f\n", r;
  }'
}

phos_ds_graph_stats_bipartite() {
  local edges_file="$1"
  local n_left="$2"
  local n_right="$3"
  local multi_count="${4:-}"
  local multi_total="${5:-}"

  local metrics
  metrics="$(awk -F'\t' -v nleft="$n_left" -v nright="$n_right" '
    BEGIN{ edges=0; }
    NF>=2 { edges++; left_deg[$1]++; right_deg[$2]++; }
    END{
      if (nleft<=0 || nright<=0) { printf "0\t0\t0\t0\t0\t0\n"; exit; }
      sum_left=0; count_left=0; min_left=1e9;
      for (l in left_deg) { d=left_deg[l]; sum_left+=d; count_left++; if (d<min_left) min_left=d; }
      if (count_left < nleft) min_left=0;
      avg_left=(nleft>0)?(sum_left/nleft):0;
      sum_right=0; count_right=0; min_right=1e9;
      for (r in right_deg) { d=right_deg[r]; sum_right+=d; count_right++; if (d<min_right) min_right=d; }
      if (count_right < nright) min_right=0;
      avg_right=(nright>0)?(sum_right/nright):0;
      density = edges/(nleft*nright);
      printf "%d\t%.4f\t%.4f\t%d\t%.4f\t%d\n", edges, density, avg_left, min_left, avg_right, min_right;
    }
  ' "$edges_file")"

  if [[ -n "${multi_count:-}" && -n "${multi_total:-}" ]]; then
    local multi_ratio
    multi_ratio="$(awk -v m="$multi_count" -v n="$multi_total" 'BEGIN{ if (n<=0) print 0; else printf "%.4f\n", (m/n) }')"
    printf "%s\t%s\n" "$metrics" "$multi_ratio"
  else
    echo "$metrics"
  fi
}

phos_ds_clamp_0_1() {
  local value="$1"
  awk -v x="$value" 'BEGIN{ if (x<0) x=0; if (x>1) x=1; printf "%.4f\n", x }'
}

phos_ds_score_linear() {
  local value="$1"
  local min="$2"
  local max="$3"
  awk -v x="$value" -v a="$min" -v b="$max" '
    function clamp(v, lo, hi){ return (v<lo)?lo:((v>hi)?hi:v); }
    BEGIN{ if (b==a) { print 0; exit };
      printf "%.4f\n", clamp((x-a)/(b-a), 0, 1) * 100;
    }
  '
}

phos_ds_score_minimal() {
  local out_items="$1"
  local out_words="$2"
  local item_weight="$3"
  local word_divisor="$4"
  local cap="${5:-100}"
  awk -v n="$out_items" -v w="$out_words" -v iw="$item_weight" -v wd="$word_divisor" -v c="$cap" 'BEGIN{
    s = (n * iw) + (w / wd);
    if (s > c) s = c;
    printf "%.2f\n", s;
  }'
}

phos_ds_score_box_equal_quarters() {
  local vol="$1"
  local div="$2"
  local dep="$3"
  local con="$4"
  awk -v v="$vol" -v d="$div" -v p="$dep" -v c="$con" '
    function clamp(x, lo, hi){ return (x<lo)?lo:((x>hi)?hi:x); }
    BEGIN{
      overall = clamp((v+d+p+c)/4, 0, 100);
      printf "%.2f\t%.2f\t%.2f\t%.2f\t%.2f\n", overall, v, d, p, c;
    }
  '
}

phos_ds_append_section_text() {
  local file="$1"
  local start="$2"
  awk -v start="$start" '
    function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s; }
    function clean(line){
      line = trim(line);
      sub(/^-+[[:space:]]+/, "", line);
      if (line=="") return "";
      if (line ~ /^\[V-SCRIPT\]/) return "";
      if (line ~ /^[[:space:]]*[A-Za-z0-9_.-]+[.]sh[[:space:]]*$/) return "";
      if (line ~ /^Each item has:/) return "";
      if (line ~ /^Store supporting IDs/) return "";
      if (line ~ /^Mapped(Gain|Pain)IDs/) return "";
      if (line ~ /^CapabilityType must be/) return "";
      if (line ~ /^[|]/) return "";
      return line;
    }
    BEGIN{ inside=0; fence=0; }
    $0==start { inside=1; next }
    inside && $0 ~ /^## / { exit }
    inside {
      if ($0 ~ /^```/) { fence = !fence; next }
      if (fence) next
      line = clean($0);
      if (line!="") print line;
    }
  ' "$file"
}

phos_ds_section_words() {
  local file="$1"
  local start="$2"
  local floor="${3:-0}"
  local tmp
  tmp="$(mktemp)"
  phos_ds_append_section_text "$file" "$start" > "$tmp" || true
  local words
  words="$(phos_ds_clean_text_common < "$tmp" | wc -w | awk '{print $1}')"
  rm -f "$tmp"
  if [[ "$floor" =~ ^[0-9]+$ && "$floor" -gt 0 ]]; then
    if [[ "$words" -lt "$floor" ]]; then
      words="$floor"
    fi
  fi
  echo "$words"
}

phos_ds_index_ids_for_prefixes() {
  local index_tsv="$1"
  local prefixes_file="$2"
  awk -F'\t' 'FNR==NR{
    if ($0!="") pref[$0]=1;
    next
  }
  {
    for (p in pref) {
      if (index($3, p) == 1) { print $2; break; }
    }
  }' "$prefixes_file" "$index_tsv"
}

phos_ds_count_unique_ids_in_text() {
  local ids_file="$1"
  local text_file="$2"
  if [[ ! -s "$ids_file" ]]; then
    echo "0"
    return 0
  fi
  { grep -F -o -f "$ids_file" "$text_file" 2>/dev/null || true; } | sort -u | wc -l | awk '{print $1}'
}

phos_ds_filter_token_dump() {
  awk '
    {
      orig=$0
      line=$0
      commas=0
      dense_commas=0
      commas = gsub(/,/, "", line)
      tmp=$0
      dense_commas = gsub(/,[[:alnum:]]/, "", tmp)
      if (commas >= 12) next
      if (dense_commas >= 8) next
      print orig
    }
  '
}

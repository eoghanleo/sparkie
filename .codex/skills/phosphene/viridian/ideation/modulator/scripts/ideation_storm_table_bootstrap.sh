#!/usr/bin/env bash
set -euo pipefail

# ideation_storm_table_bootstrap.sh
# Bootstrap the Storm table for an IDEA artifact, using:
# - SeedSHA256 + ManifoldProbeCount from the SPARK header
# - WIP/creative_madness/manifold_probes.jsonl as the probe corpus
#
# This rewrites ONLY the "## Storm table" section content (table) and updates
# the [PHOSPHENE_MANIFOLD_PROBES] footer block.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./.codex/skills/phosphene/viridian/ideation/modulator/scripts/ideation_storm_table_bootstrap.sh \
    --file <path/to/IDEA-####-*.md>

Behavior:
- Reads IssueNumber from IDEA header.
- Resolves SPARK-<IssueNumber>.md under phosphene/signals/sparks/.
- Reads SeedSHA256 + ManifoldProbeCount from SPARK header.
- Selects probes deterministically from WIP/creative_madness/manifold_probes.jsonl.
- Rewrites the Storm table rows to match (n choose 2) * 3.
- Updates the [PHOSPHENE_MANIFOLD_PROBES] footer block.
EOF
}

IDEA_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) IDEA_FILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "${IDEA_FILE:-}" ]] || { echo "Error: --file is required" >&2; usage; exit 2; }
[[ -f "$IDEA_FILE" ]] || { echo "Error: file not found: $IDEA_FILE" >&2; exit 1; }

read_header_value() {
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

hash_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf "%s" "$1" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf "%s" "$1" | shasum -a 256 | awk '{print $1}'
  else
    printf "%s" "$1" | openssl dgst -sha256 | awk '{print $2}'
  fi
}

issue_number="$(read_header_value "$IDEA_FILE" "IssueNumber" || true)"
if ! [[ "${issue_number:-}" =~ ^[0-9]+$ ]]; then
  echo "Error: missing/invalid IssueNumber header in IDEA file (must be numeric)" >&2
  exit 2
fi

spark_id="$(printf "SPARK-%06d" "$issue_number")"
spark_path="$ROOT/phosphene/signals/sparks/${spark_id}.md"
[[ -f "$spark_path" ]] || { echo "Error: missing SPARK for issue ${issue_number}: $spark_path" >&2; exit 1; }

seed_sha256="$(read_header_value "$spark_path" "SeedSHA256" || true)"
seed_sha256="$(printf "%s" "${seed_sha256:-}" | tr -d '\r' | tr -d '[:space:]')"
[[ -n "${seed_sha256:-}" ]] || { echo "Error: missing SeedSHA256 in SPARK header: $spark_path" >&2; exit 1; }
seed_sha256="$(printf "%s" "$seed_sha256" | sed -E 's/^sha256://I')"

probe_count_raw="$(read_header_value "$spark_path" "ManifoldProbeCount" || true)"
probe_count_raw="$(printf "%s" "${probe_count_raw:-}" | tr -d '\r' | tr -d '[:space:]')"
[[ -n "${probe_count_raw:-}" ]] || { echo "Error: missing ManifoldProbeCount in SPARK header: $spark_path" >&2; exit 1; }

if ! [[ "$probe_count_raw" =~ ^[0-9]+$ ]]; then
  echo "Error: ManifoldProbeCount must be numeric in SPARK header: $spark_path" >&2
  exit 1
fi

probe_count="$probe_count_raw"
if [[ "$probe_count" -lt 2 ]]; then
  echo "Error: ManifoldProbeCount must be >= 2 in SPARK header: $spark_path" >&2
  exit 1
fi

probes_file="$ROOT/WIP/creative_madness/manifold_probes.jsonl"
[[ -f "$probes_file" ]] || { echo "Error: missing probe corpus: $probes_file" >&2; exit 1; }

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

ranked_tmp="$tmp_dir/ranked.tsv"
selected_tmp="$tmp_dir/selected.tsv"
table_tmp="$tmp_dir/storm_table.md"
footer_tmp="$tmp_dir/footer.md"

awk_extract() {
  local file="$1"
  awk '
    function extract(key, line, out) {
      if (match(line, "\"" key "\":\"[^\"]*\"")) {
        out = substr(line, RSTART, RLENGTH);
        sub("^\"" key "\":\"", "", out);
        sub("\"$", "", out);
        return out;
      }
      return "";
    }
    {
      id = extract("id", $0);
      label = extract("label", $0);
      category = extract("category", $0);
      if (id != "" && label != "" && category != "") {
        print id "\t" label "\t" category;
      }
    }
  ' "$file"
}

while IFS=$'\t' read -r id label category; do
  [[ -n "${id:-}" ]] || continue
  rank="$(hash_sha256 "$(printf "%s\n%s" "$seed_sha256" "$id")")"
  printf "%s\t%s\t%s\t%s\n" "$rank" "$id" "$label" "$category" >> "$ranked_tmp"
done < <(awk_extract "$probes_file")

if [[ ! -s "$ranked_tmp" ]]; then
  echo "Error: no probes parsed from corpus: $probes_file" >&2
  exit 1
fi

sort -t $'\t' -k1,1 -k2,2 "$ranked_tmp" | head -n "$probe_count" > "$selected_tmp"
selected_count="$(wc -l < "$selected_tmp" | tr -d ' ')"
if [[ "$selected_count" -ne "$probe_count" ]]; then
  echo "Error: probe selection failed (requested $probe_count, got $selected_count)" >&2
  exit 1
fi

PROBE_IDS=()
PROBE_LABELS=()
PROBE_CATEGORIES=()
while IFS=$'\t' read -r _rank id label category; do
  PROBE_IDS+=("$id")
  PROBE_LABELS+=("$label")
  PROBE_CATEGORIES+=("$category")
done < "$selected_tmp"

pair_count=$(( probe_count * (probe_count - 1) / 2 ))
storm_total=$(( pair_count * 3 ))
pad_width=${#storm_total}
if [[ "$pad_width" -lt 4 ]]; then
  pad_width=4
fi

{
  echo "| STORM-ID | PROBE_1 | PROBE_2 | RING | DESCRIPTION |"
  echo "| --- | --- | --- | --- | --- |"

  storm_index=0
  for ((i=0; i<probe_count-1; i++)); do
    for ((j=i+1; j<probe_count; j++)); do
      probe_one="${PROBE_IDS[$i]}:${PROBE_LABELS[$i]}"
      probe_two="${PROBE_IDS[$j]}:${PROBE_LABELS[$j]}"
      for ring in adjacent orthogonal extrapolatory; do
        storm_index=$((storm_index + 1))
        storm_id="$(printf "STORM-%0*d" "$pad_width" "$storm_index")"
        echo "| ${storm_id} | ${probe_one} | ${probe_two} | ${ring} | <Description> |"
      done
    done
  done
} > "$table_tmp"

START_HEADING="## Storm table"

out_tmp="$tmp_dir/out.md"
awk -v start="$START_HEADING" -v table_file="$table_tmp" '
  BEGIN{ in_section=0; wrote=0; }
  $0==start {
    print;
    print "";
    while ((getline line < table_file) > 0) print line;
    close(table_file);
    in_section=1;
    wrote=1;
    next
  }
  in_section && $0 ~ /^## / { in_section=0 }
  in_section { next }
  { print }
  END{
    if (wrote==0) {
      print "ERROR: missing required heading: " start > "/dev/stderr";
      exit 3
    }
  }
' "$IDEA_FILE" > "$out_tmp"

mv "$out_tmp" "$IDEA_FILE"

{
  echo "[PHOSPHENE_MANIFOLD_PROBES]"
  echo "seed_sha256: ${seed_sha256}"
  echo "manifold_probe_count: ${probe_count}"
  for ((k=0; k<probe_count; k++)); do
    echo "- ${PROBE_IDS[$k]} | ${PROBE_LABELS[$k]} | ${PROBE_CATEGORIES[$k]}"
  done
  echo "[/PHOSPHENE_MANIFOLD_PROBES]"
} > "$footer_tmp"

out_tmp="$tmp_dir/out_footer.md"
awk -v open="\\[PHOSPHENE_MANIFOLD_PROBES\\]" -v close="\\[/PHOSPHENE_MANIFOLD_PROBES\\]" -v footer_file="$footer_tmp" '
  BEGIN{ in_block=0; }
  $0 ~ open { in_block=1; next }
  in_block && $0 ~ close { in_block=0; next }
  in_block { next }
  { print }
  END{
    print "";
    while ((getline line < footer_file) > 0) print line;
    close(footer_file);
  }
' "$IDEA_FILE" > "$out_tmp"

mv "$out_tmp" "$IDEA_FILE"
echo "OK: bootstrapped storm table in: $IDEA_FILE"

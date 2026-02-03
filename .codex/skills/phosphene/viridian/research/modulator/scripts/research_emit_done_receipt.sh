#!/usr/bin/env bash
#
# PHOSPHENE <research> — emit DONE receipt (JSONL bus)
#
set -euo pipefail

fail() { echo "PHOSPHENE: $*" >&2; exit 2; }

usage() {
  cat <<'EOF'
Usage:
  ./.codex/skills/phosphene/viridian/research/modulator/scripts/research_emit_done_receipt.sh --issue-number <N> --work-id <RA-###> [--bus <path>]
EOF
}

ISSUE_NUMBER=""
WORK_ID=""
BUS="phosphene/signals/bus.jsonl"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue-number) ISSUE_NUMBER="${2:-}"; shift 2 ;;
    --work-id) WORK_ID="${2:-}"; shift 2 ;;
    --bus) BUS="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown arg: $1" ;;
  esac
done

[[ -n "${ISSUE_NUMBER:-}" ]] || fail "missing --issue-number"
[[ -n "${WORK_ID:-}" ]] || fail "missing --work-id"

[[ -f "$BUS" ]] || fail "missing bus file: $BUS"

HASH_IMPL="phosphene/phosphene-core/bin/signal_hash.sh"
BUS_IMPL="phosphene/phosphene-core/bin/signal_bus.sh"
[[ -f "$HASH_IMPL" ]] || fail "missing: $HASH_IMPL"
[[ -f "$BUS_IMPL" ]] || fail "missing: $BUS_IMPL"

parent_line="$(
  grep -F "\"signal_type\":\"phosphene.prism.research.branch_invoked.v1\"" "$BUS" \
    | grep -F "\"issue_number\":${ISSUE_NUMBER}" \
    | grep -F "\"work_id\":\"${WORK_ID}\"" \
    | tail -n 1 || true
)"

[[ -n "${parent_line:-}" ]] || fail "no prism branch_invoked parent found for issue_number=${ISSUE_NUMBER} work_id=${WORK_ID}"

parent_signal_id="$(
  printf "%s" "$parent_line" \
    | grep -oE '"signal_id"[[:space:]]*:[[:space:]]*"sha256:[0-9A-Fa-f]{64}"' \
    | head -n 1 \
    | sed -E 's/^"signal_id"[[:space:]]*:[[:space:]]*"//; s/"$//'
)"
[[ -n "${parent_signal_id:-}" ]] || fail "failed to extract parent signal_id"

phos_id="$(
  printf "%s" "$parent_line" \
    | grep -oE '"phos_id"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -n 1 \
    | sed -E 's/^"phos_id"[[:space:]]*:[[:space:]]*"//; s/"$//'
)"

created_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
run_marker="$WORK_ID"
output_key="done:receipt:research:issue:${ISSUE_NUMBER}"

signal_id="$(
  bash "$HASH_IMPL" signal-id \
    --run-marker "$run_marker" \
    --output-key "$output_key" \
    --parent "$parent_signal_id"
)"

if grep -qF "\"signal_id\":\"${signal_id}\"" "$BUS"; then
  echo "PHOSPHENE: done receipt already present (idempotent): $signal_id" >&2
  exit 0
fi

line="{\"signal_version\":1,\"signal_id\":\"${signal_id}\",\"signal_type\":\"phosphene.done.research.receipt.v1\",\"work_id\":\"${WORK_ID}\",\"domain\":\"research\",\"issue_number\":${ISSUE_NUMBER},\"lane\":\"viridian\",\"phos_id\":\"${phos_id}\",\"parents\":[\"${parent_signal_id}\"],\"run_marker\":\"${run_marker}\",\"output_key\":\"${output_key}\",\"ok\":true,\"created_utc\":\"${created_utc}\"}"

bash "$BUS_IMPL" append --bus "$BUS" --line "$line"
echo "OK: appended DONE receipt: $signal_id" >&2

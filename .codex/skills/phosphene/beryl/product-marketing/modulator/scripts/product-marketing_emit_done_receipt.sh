#!/usr/bin/env bash
#
# PHOSPHENE <product-marketing> — emit DONE receipt (JSONL bus)
#
# Purpose:
# - Append an idempotent DONE receipt signal line to:
#     phosphene/signals/bus.jsonl
#   in the current branch (PR branch).
#
# Contract:
# - The receipt MUST parent the prism's branch_invoked signal for this issue/work.
# - The append must be performed via the official bus appender so tamper_hash is correct.
#
set -euo pipefail

fail() { echo "PHOSPHENE: $*" >&2; exit 2; }

usage() {
  cat <<'EOF'
Usage:
  ./.codex/skills/phosphene/beryl/product-marketing/modulator/scripts/product-marketing_emit_done_receipt.sh --issue-number <N> --work-id <WORK_ID>

Notes:
  - This writes to: phosphene/signals/bus.jsonl (append-only)
  - <WORK_ID> MUST match the prism comment's `work_id` for this issue/run.
  - The emitted line will have:
      signal_type = phosphene.done.product-marketing.receipt.v1
    and parents = [<prism_branch_invoked_signal_id>]
EOF
}

ISSUE_NUMBER=""
WORK_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue-number) ISSUE_NUMBER="${2:-}"; shift 2 ;;
    --work-id) WORK_ID="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown arg: $1" ;;
  esac
done

[[ -n "${ISSUE_NUMBER:-}" ]] || fail "missing --issue-number"
[[ -n "${WORK_ID:-}" ]] || fail "missing --work-id"

BUS="phosphene/signals/bus.jsonl"
[[ -f "$BUS" ]] || fail "missing bus file: $BUS"

HASH_IMPL="phosphene/phosphene-core/bin/signal_hash.sh"
BUS_IMPL="phosphene/phosphene-core/bin/signal_bus.sh"
[[ -f "$HASH_IMPL" ]] || fail "missing: $HASH_IMPL"
[[ -f "$BUS_IMPL" ]] || fail "missing: $BUS_IMPL"

# Extract the latest prism branch_invoked line for this issue/work.
# (We keep parsing simple; signals are expected to be single-line JSON objects.)
parent_line="$(
  grep -F "\"signal_type\":\"phosphene.prism.product-marketing.branch_invoked.v1\"" "$BUS" \
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
output_key="done:receipt:product-marketing:issue:${ISSUE_NUMBER}"

signal_id="$(
  bash "$HASH_IMPL" signal-id \
    --run-marker "$run_marker" \
    --output-key "$output_key" \
    --parent "$parent_signal_id"
)"

# Idempotency: if this exact signal_id already exists in the bus, skip.
if grep -qF "\"signal_id\":\"${signal_id}\"" "$BUS"; then
  echo "PHOSPHENE: done receipt already present (idempotent): $signal_id" >&2
  exit 0
fi

# Construct a single-line JSON object (no newlines).
# Values are kept minimal to avoid complex escaping in bash.
line="{\"signal_version\":1,\"signal_id\":\"${signal_id}\",\"signal_type\":\"phosphene.done.product-marketing.receipt.v1\",\"work_id\":\"${WORK_ID}\",\"domain\":\"product-marketing\",\"issue_number\":${ISSUE_NUMBER},\"lane\":\"beryl\",\"phos_id\":\"${phos_id}\",\"parents\":[\"${parent_signal_id}\"],\"run_marker\":\"${run_marker}\",\"output_key\":\"${output_key}\",\"ok\":true,\"created_utc\":\"${created_utc}\"}"

# Append via official tool (adds/updates per-line tamper_hash).
bash "$BUS_IMPL" append --bus "$BUS" --line "$line"

echo "OK: appended DONE receipt: $signal_id" >&2


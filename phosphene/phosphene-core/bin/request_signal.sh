#!/usr/bin/env bash
#
# PHOSPHENE request signal helper (bash-only)
#
# Emits cross-domain request signals:
#   phosphene.request.<requesting_domain>.<target_domain>.<work_type>.v1
#
set -euo pipefail

fail() { echo "PHOSPHENE: $*" >&2; exit 2; }

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/phosphene-core/bin/request_signal.sh \
    --requesting-domain <domain> \
    --target-domain <domain> \
    --work-type <type> \
    --work-id <ID> \
    [--requested-work-id <ID>] \
    [--issue-number <N>] \
    [--lane <lane>] \
    [--parent <signal_id>]...

Notes:
  - Enforces requests.allow from phosphene/config/<color>.yml.
  - Appends to: phosphene/signals/bus.jsonl (tamper_hash handled).
EOF
}

REQUESTING_DOMAIN=""
TARGET_DOMAIN=""
WORK_TYPE=""
WORK_ID=""
REQUESTED_WORK_ID=""
ISSUE_NUMBER=""
LANE=""
PARENTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --requesting-domain) REQUESTING_DOMAIN="${2:-}"; shift 2 ;;
    --target-domain) TARGET_DOMAIN="${2:-}"; shift 2 ;;
    --work-type) WORK_TYPE="${2:-}"; shift 2 ;;
    --work-id) WORK_ID="${2:-}"; shift 2 ;;
    --requested-work-id) REQUESTED_WORK_ID="${2:-}"; shift 2 ;;
    --issue-number) ISSUE_NUMBER="${2:-}"; shift 2 ;;
    --lane) LANE="${2:-}"; shift 2 ;;
    --parent) PARENTS+=("${2:-}"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown arg: $1" ;;
  esac
done

[[ -n "${REQUESTING_DOMAIN:-}" ]] || fail "missing --requesting-domain"
[[ -n "${TARGET_DOMAIN:-}" ]] || fail "missing --target-domain"
[[ -n "${WORK_TYPE:-}" ]] || fail "missing --work-type"
[[ -n "${WORK_ID:-}" ]] || fail "missing --work-id"

if [[ -z "${REQUESTED_WORK_ID:-}" ]]; then
  # Back-compat default: request is "about" the requesting work_id unless
  # the caller provides a target-domain specific requested ID.
  REQUESTED_WORK_ID="$WORK_ID"
fi

if [[ -n "${ISSUE_NUMBER:-}" ]] && ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
  fail "--issue-number must be numeric"
fi

if ! [[ "$WORK_TYPE" =~ ^[a-z0-9-]+$ ]]; then
  fail "--work-type must be lowercase kebab (a-z0-9-)"
fi

lane_for_domain() {
  case "$1" in
    product-marketing|product-vision|product-strategy) echo "beryl" ;;
    ideation|research) echo "viridian" ;;
    product-management|product-architecture|feature-management) echo "cerulean" ;;
    product-evaluation|test-management) echo "cadmium" ;;
    scrum-management) echo "amaranth" ;;
    retrospective) echo "chartreuse" ;;
    *) echo "" ;;
  esac
}

if [[ -z "${LANE:-}" ]]; then
  LANE="$(lane_for_domain "$REQUESTING_DOMAIN")"
fi
[[ -n "${LANE:-}" ]] || fail "unknown lane for requesting domain: $REQUESTING_DOMAIN"

BUS="phosphene/signals/bus.jsonl"
HASH_IMPL="phosphene/phosphene-core/bin/signal_hash.sh"
BUS_IMPL="phosphene/phosphene-core/bin/signal_bus.sh"
CONFIG_IMPL="phosphene/phosphene-core/bin/phosphene_config.sh"

[[ -f "$BUS" ]] || fail "missing bus file: $BUS"
[[ -f "$HASH_IMPL" ]] || fail "missing: $HASH_IMPL"
[[ -f "$BUS_IMPL" ]] || fail "missing: $BUS_IMPL"
[[ -f "$CONFIG_IMPL" ]] || fail "missing: $CONFIG_IMPL"

allowlist="$(bash "$CONFIG_IMPL" get --color "$LANE" --key requests.allow --default "")"
allowed=0
pair="${REQUESTING_DOMAIN}->${TARGET_DOMAIN}"
if [[ -n "${allowlist:-}" ]]; then
  IFS=',' read -ra pairs <<< "$allowlist"
  for p in "${pairs[@]}"; do
    p="$(echo "$p" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [[ -n "${p:-}" ]] || continue
    if [[ "$p" == "$pair" ]]; then
      allowed=1
      break
    fi
  done
fi
if [[ "$allowed" -ne 1 ]]; then
  fail "request not allowed by config (${LANE} requests.allow): ${pair}"
fi

created_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
output_key="request:${REQUESTING_DOMAIN}->${TARGET_DOMAIN}:${WORK_TYPE}:requested:${REQUESTED_WORK_ID}:issue:${ISSUE_NUMBER:-0}"

hash_args=( "$HASH_IMPL" signal-id --run-marker "$WORK_ID" --output-key "$output_key" )
for p in "${PARENTS[@]}"; do
  [[ -n "${p:-}" ]] || continue
  hash_args+=( --parent "$p" )
done

signal_id="$(bash "${hash_args[@]}")"

if grep -qF "\"signal_id\":\"${signal_id}\"" "$BUS"; then
  echo "PHOSPHENE: request signal already present (idempotent): $signal_id" >&2
  exit 0
fi

parents_json="[]"
if [[ "${#PARENTS[@]}" -gt 0 ]]; then
  parents_json="["
  first=1
  for p in "${PARENTS[@]}"; do
    [[ -n "${p:-}" ]] || continue
    if [[ "$first" -eq 1 ]]; then
      parents_json="${parents_json}\"${p}\""
      first=0
    else
      parents_json="${parents_json},\"${p}\""
    fi
  done
  parents_json="${parents_json}]"
fi

issue_fragment=""
if [[ -n "${ISSUE_NUMBER:-}" ]]; then
  issue_fragment=",\"issue_number\":${ISSUE_NUMBER}"
fi

signal_type="phosphene.request.${REQUESTING_DOMAIN}.${TARGET_DOMAIN}.${WORK_TYPE}.v1"
line="{\"signal_version\":1,\"signal_id\":\"${signal_id}\",\"signal_type\":\"${signal_type}\",\"work_id\":\"${WORK_ID}\",\"requested_work_id\":\"${REQUESTED_WORK_ID}\",\"domain\":\"${REQUESTING_DOMAIN}\",\"target_domain\":\"${TARGET_DOMAIN}\"${issue_fragment},\"lane\":\"${LANE}\",\"parents\":${parents_json},\"run_marker\":\"${WORK_ID}\",\"output_key\":\"${output_key}\",\"created_utc\":\"${created_utc}\"}"

bash "$BUS_IMPL" append --bus "$BUS" --line "$line"
echo "OK: appended request signal: $signal_id" >&2

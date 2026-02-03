#!/usr/bin/env bash
#
# Back-compat shim:
# Historically scripts sourced phosphene_config.sh. The bash-only drop-in uses phosphene_env.sh.
#
set -euo pipefail

SCRIPT_DIR__PHOSPHENE_CONFIG_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR__PHOSPHENE_CONFIG_SH/phosphene_env.sh"



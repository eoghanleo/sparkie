#!/usr/bin/env bash
set -euo pipefail

# ideation_matrix_set_idea_paragraph.sh (deprecated)
# This script now delegates to ideation_storm_set_description.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"

echo "Deprecated: use ideation_storm_set_description.sh instead." >&2
echo "Hint: ./ideation_storm_set_description.sh --file <IDEA_PATH> --storm-id STORM-0001 --description \"...\"" >&2
exit 2


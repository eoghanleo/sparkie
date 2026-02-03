#!/usr/bin/env bash
set -euo pipefail

# create_new_persona.sh
# Creates a Persona (PER-*) doc from the canonical template, allocating IDs via the global registry.
#
# Usage:
#   ./phosphene/domains/product-marketing/scripts/create_new_persona.sh --title "Idle Ingrid" --vpd VPD-001 [--id PER-0003] [--owner "..."] [--status Draft] [--dependencies "CPE-0001,RA-001"] [--output-dir <dir>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/product-marketing/scripts/create_new_persona.sh --title "..." --vpd VPD-001 [--id PER-0001] [--owner "..."] [--status Draft] [--dependencies "..."] [--output-dir <dir>]
EOF
}

slugify() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

ROOT="$(phosphene_find_project_root)"

TITLE=""
ID=""
OWNER=""
STATUS="Draft"
DEPENDENCIES=""
VPD=""
OUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title) TITLE="${2:-}"; shift 2 ;;
    --id) ID="${2:-}"; shift 2 ;;
    --owner) OWNER="${2:-}"; shift 2 ;;
    --status) STATUS="${2:-}"; shift 2 ;;
    --vpd) VPD="${2:-}"; shift 2 ;;
    --dependencies) DEPENDENCIES="${2:-}"; shift 2 ;;
    --output-dir) OUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$TITLE" ]] || { echo "Error: --title is required" >&2; usage; exit 2; }

[[ -n "${VPD}" ]] || { echo "Error: --vpd is required (WTBD parent; expected VPD-001)" >&2; usage; exit 2; }
if ! [[ "$VPD" =~ ^VPD-[0-9]{3}$ ]]; then
  echo "Error: --vpd must look like VPD-001" >&2
  exit 2
fi

if [[ -n "${OUT_DIR}" && "$OUT_DIR" != /* ]]; then OUT_DIR="$ROOT/$OUT_DIR"; fi
if [[ -z "${OUT_DIR}" ]]; then
  vpd_cover="$("$ROOT/phosphene/phosphene-core/bin/phosphene" id where "$VPD" 2>/dev/null | head -n 1 | awk -F'\t' '{print $3}')"
  [[ -n "${vpd_cover:-}" ]] || { echo "Error: cannot locate $VPD in repo. Create a VPD bundle first." >&2; exit 1; }
  OUT_DIR="$ROOT/$(dirname "$vpd_cover")/10-personas"
fi
mkdir -p "$OUT_DIR"

# Ensure VPD is always present in Dependencies.
if ! echo ",${DEPENDENCIES}," | grep -qF ",${VPD},"; then
  if [[ -n "${DEPENDENCIES}" ]]; then
    DEPENDENCIES="${VPD},${DEPENDENCIES}"
  else
    DEPENDENCIES="${VPD}"
  fi
fi

if [[ -z "${ID}" ]]; then
  "$ROOT/phosphene/phosphene-core/bin/phosphene" id validate >/dev/null
  ID="$("$ROOT/phosphene/phosphene-core/bin/phosphene" id next --type persona)"
fi

if ! [[ "$ID" =~ ^PER-[0-9]{4}$ ]]; then
  echo "Error: --id must look like PER-0001" >&2
  exit 2
fi

DATE="$(date +%F)"
SLUG="$(slugify "$TITLE")"
OUT="$OUT_DIR/${ID}-${SLUG}.md"

if [[ -e "$OUT" ]]; then
  echo "Error: already exists: $OUT" >&2
  exit 1
fi

cat > "$OUT" <<'EOF'
ID: PER-0001
Title:
Status: Draft
Updated:
Dependencies: 
Owner: 
EditPolicy: DO_NOT_EDIT_DIRECTLY (use scripts; see .codex/skills/phosphene/beryl/product-marketing/modulator/SKILL.md)

## Snapshot summary

```text
[V-SCRIPT]:
update_persona_summary.sh
```



## Jobs

```text
[V-SCRIPT]:
add_persona_jtbd_item.sh
update_persona_jtbd_item.sh
```

Each item has:
- ID format: `JTBD-JOB-0001-PER-0001` (types: `JOB|PAIN|GAIN`)
- Importance: 1–5 (5 = most important)

| JTBD-ID | Job | Importance |
|---|---|---:|

## Pains

```text
[V-SCRIPT]:
add_persona_jtbd_item.sh
update_persona_jtbd_item.sh
```

| JTBD-ID | Pain | Importance |
|---|---|---:|

## Gains

```text
[V-SCRIPT]:
add_persona_jtbd_item.sh
update_persona_jtbd_item.sh
```

| JTBD-ID | Gain | Importance |
|---|---|---:|

## Evidence and links

```text
[V-SCRIPT]:
add_persona_evidence_link.sh
remove_persona_evidence_link.sh
add_persona_related_link.sh
remove_persona_related_link.sh
```

Store supporting IDs and pointers here (no prose argumentation—just traceability).

### EvidenceIDs

```text
[V-SCRIPT]:
add_persona_evidence_link.sh
remove_persona_evidence_link.sh
```


### CandidatePersonaIDs

```text
[V-SCRIPT]:
add_persona_evidence_link.sh
remove_persona_evidence_link.sh
```


### DocumentIDs

```text
[V-SCRIPT]:
add_persona_evidence_link.sh
remove_persona_evidence_link.sh
```


### Links

```text
[V-SCRIPT]:
add_persona_related_link.sh
remove_persona_related_link.sh
```


## Notes

```text
[V-SCRIPT]:
add_persona_note.sh
overwrite_persona_notes.sh
```



EOF

# Fill in the header block (bash-only) and update example JTBD suffixes in-body.
TMP_EDIT="$(mktemp)"
awk -v pid="$ID" -v title="$TITLE" -v status="$STATUS" -v updated="$DATE" -v deps="$DEPENDENCIES" -v owner="$OWNER" '
  BEGIN { in_header=1; }
  {
    if (in_header) {
      if ($0 ~ /^ID:[[:space:]]*/) { print "ID: " pid; next; }
      if ($0 ~ /^Title:/) { print "Title: " title; next; }
      if ($0 ~ /^Status:/) { print "Status: " status; next; }
      if ($0 ~ /^Updated:/) { print "Updated: " updated; next; }
      if ($0 ~ /^Dependencies:/) { print "Dependencies: " deps; next; }
      if ($0 ~ /^Owner:/) { print "Owner: " owner; next; }
    }
    gsub(/-PER-[0-9]{4}/, "-" pid)
    print
    if (in_header && $0 == "") { in_header=0; }
  }
' "$OUT" > "$TMP_EDIT"

# Validate (strict: scripts must not create strict-invalid artifacts)
set +e
"$ROOT/.github/scripts/validate_persona.sh" --strict "$TMP_EDIT" >/dev/null
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  rm -f "$TMP_EDIT" "$OUT" || true
  exit $rc
fi

mv "$TMP_EDIT" "$OUT"
echo "Created persona: $OUT"


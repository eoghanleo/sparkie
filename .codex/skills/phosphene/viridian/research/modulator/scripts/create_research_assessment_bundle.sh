#!/usr/bin/env bash
set -euo pipefail

# create_research_assessment_bundle.sh
# Creates a Research Assessment (RA) bundle folder populated from templates.
#
# Usage (run from repo root):
#   ./phosphene/domains/research/scripts/create_research_assessment_bundle.sh --title "..." [--id RA-001] [--owner ""] [--priority Medium]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./phosphene/domains/research/scripts/create_research_assessment_bundle.sh --title "..." [--id RA-001] [--owner "..."] [--priority Medium]

Creates:
  phosphene/domains/research/output/research-assessments/RA-001-<slug>/
    00-coversheet.md
    10-reference-solutions.md
    20-competitive-landscape.md
    30-pitches/ (empty)
    40-hypotheses.md
    50-evidence-bank.md
    60-candidate-personas/ (empty; CPE-*.md)
    90-methods.md
    RA-001.md (assembled view; re-runnable)
EOF
}

slugify() {
  # Lowercase, keep alnum and dashes, collapse spaces/underscores to dash.
  # macOS bash 3.2 compatible.
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

ID=""
TITLE=""
OWNER=""
PRIORITY="Medium"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) ID="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --owner) OWNER="${2:-}"; shift 2 ;;
    --priority) PRIORITY="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "${TITLE}" ]]; then
  echo "Error: --title is required." >&2
  usage
  exit 2
fi

ROOT="$(phosphene_find_project_root)"

if [[ -z "${ID}" ]]; then
  "$ROOT/phosphene/phosphene-core/bin/phosphene" id validate >/dev/null
  # Allocate next legal RA id from global index
  ID="$("$ROOT/phosphene/phosphene-core/bin/phosphene" id next --type ra)"
fi

if ! [[ "$ID" =~ ^RA-[0-9]{3}$ ]]; then
  echo "Error: --id must look like RA-001" >&2
  exit 2
fi

DOCS_DIR="$ROOT/phosphene/domains/research/output/research-assessments"

mkdir -p "$DOCS_DIR"

SLUG="$(slugify "$TITLE")"
BUNDLE_DIR="$DOCS_DIR/${ID}-${SLUG}"

if [[ -e "$BUNDLE_DIR" ]]; then
  echo "Error: bundle already exists: $BUNDLE_DIR" >&2
  exit 1
fi

mkdir -p "$BUNDLE_DIR/30-pitches"
mkdir -p "$BUNDLE_DIR/60-candidate-personas"

DATE="$(date +%F)"

# Templates are intentionally not used (bash-only; script is the single source of truth).
cat > "$BUNDLE_DIR/00-coversheet.md" <<EOF
ID: ${ID}
Title: ${TITLE}
Status: Draft
Priority: ${PRIORITY}
Updated: ${DATE}
Dependencies: 
Owner: ${OWNER}

## Purpose + constraints (read first)

This document is a **web-research-only research assessment**. It is a cover letter that distills key findings and hypotheses for downstream work in \`<product-marketing>\`, \`<product-strategy>\`, and \`<product-management>\`.

Hard constraints for the research agent:
- No interviews; assume only public web sources.
- Primary outputs are reference solutions, competitive landscape, and candidate product pitches grounded in public evidence.
- Outputs are candidate segments/personas/pains/gains (theories) with evidence pointers and confidence grades.
- Product definition and scope should remain light; capture only what is necessary to frame pitches and hypotheses.

## Research coversheet (target: 1–2 pages)

### 1) Mission + deliverables + sprint success criteria

Mission:
- <what decision this enables>

Deliverables (expected):
- Reference solutions scan (market + academic) with stable IDs and pointers (RS-*)
- Competitive landscape summary (categories + key players + positioning)
- 3–7 candidate product pitches (PITCH-*) with EvidenceIDs + confidence
- Candidate segments (SEG-*) ranked, with rationale + out-of-scope list
- Candidate personas (PER-*) per top segment (hypotheses)
- Candidate jobs/pains/gains (IDs) per segment with severity/frequency (hypotheses)
- Evidence bank (EvidenceID + excerpt + pointer + strength/confidence)
- 5–15 key claims with confidence grades (what seems true from web sources)

Sprint success criteria:
- <what must be true at the end>

Downstream consumers & needs:
- \`<product-marketing>\`:
  - Needs: segments/personas + pitches + evidence for claims
- \`<product-strategy>\`:
  - Needs: competitive landscape + pitch set + key constraints/risks
- \`<product-management>\`:
  - Needs: top pitch(es) + evidence + assumptions/unknowns for validation

### 2) Scope, grounding, and what we don’t know

Minimal product grounding:
- Might be: <one sentence>
- Likely isn’t: <one sentence>

Scope boundaries:
- Industries:
- Geographies:
- Buyer types:
- Explicit out-of-scope:

Unknowns (not resolvable via web research):
- <unknown 1>

Assumptions made to proceed:
- <assumption 1>

### 3) Top hypotheses snapshot (theories)

Top candidate segments (ranked):
- SEG-0001: <name>
  - Wedge hypothesis:
  - Top pains (P-0001, P-0002, P-0003):
  - Top gains (G-0001, G-0002, G-0003):
  - Buying-center map (if inferable):
  - Triggers / why-now:

### 4) Key findings (evidence-backed)

Include 5–15 claims. Each should cite EvidenceIDs.

- Claim:
  - Why it matters:
  - EvidenceIDs: E-XXXX, E-YYYY
  - Confidence (C1–C3):
  - Notes / caveats:

### 5) Candidate product pitches (stepping stones)

List the pitch set here (details live in \`30-pitches/\`):
- PITCH-XXXX: <name> — Confidence: C2 — EvidenceIDs: E-XXXX, E-YYYY
- PITCH-YYYY: <name> — Confidence: C1 — EvidenceIDs: E-XXXX, E-YYYY

### 6) Downstream handoff (do not finalize here)

What to do next (high level):
- \`<product-marketing>\` should turn pitches + hypotheses into personas/propositions and messaging tests.
- \`<product-strategy>\` should select a pitch (or reject) based on competition + constraints + risks.
- \`<product-management>\` should plan validation experiments for the chosen pitch and define a first spec slice.

EOF

cat > "$BUNDLE_DIR/10-reference-solutions.md" <<EOF
ID: ${ID}
Title: ${TITLE} — Reference Solutions
Status: Draft
Updated: ${DATE}
Dependencies: 
Owner: ${OWNER}

## A) Reference solution scan (market + academic)

Checklist:
- Scan for similar ideas in-market (products, startups, OSS)
- Scan for similar ideas academically (papers, preprints, labs)
- Capture each as a ReferenceSolution with a stable ID + pointer
- Extract what to borrow vs avoid (patterns, claims, pitfalls)

## Reference solutions table

| RefSolID | Type (Market/Academic) | Name | 1–2 line summary | What to borrow | What to avoid | Pointer |
|---|---|---|---|---|---|---|

## Notes

Optional: expand individual RS entries below the table.

EOF

cat > "$BUNDLE_DIR/20-competitive-landscape.md" <<EOF
ID: ${ID}
Title: ${TITLE} — Competitive Landscape
Status: Draft
Updated: ${DATE}
Dependencies: 
Owner: ${OWNER}

## B) Competitive landscape + relative competition

Checklist:
- Identify direct/adjacent competitors and category substitutes
- Summarize positioning and differentiation axes
- Capture win/lose patterns (“we lose when…”) as hypotheses
- Note switching costs and inertia drivers

## Competitive landscape table

| Competitor | Category | ICP/segment | Positioning claim | Key strengths | Key weaknesses | “We lose when…” | Pointer |
|---|---|---|---|---|---|---|---|

## Notes

Optional: add switching-costs narrative and competitor deep dives below.

EOF

cat > "$BUNDLE_DIR/40-hypotheses.md" <<EOF
ID: ${ID}
Title: ${TITLE} — Hypotheses (segments/personas/pains/gains)
Status: Draft
Updated: ${DATE}
Dependencies: 
Owner: ${OWNER}

## D) Segmentation prioritization logic

Checklist:
- Prioritization logic (scoring or narrative)
- Buying-center dynamics by segment
- Deprioritized segments + rationale
- Explicit out-of-scope segments

## E) Core workflows (3–7)

Checklist:
- 3–7 workflows only (keep sharp)
- Each workflow written as: trigger → steps → outcome
- Identify who performs each step (role tags)
- Identify integration/data prerequisites where relevant

## F) Ranked jobs / pains / gains per segment

Checklist:
- Per segment: ranked JTBD, pains, gains
- Severity + frequency per pain (1–5)
- Success metrics (how they measure “done”)
- Inertia sources (why they don’t change)

## G) Candidate persona dossiers (hypotheses)

Checklist:
- Candidate persona stable ID (CPE-XXXX) and segment stable ID (SEG-XXXX)
- Objections, decision criteria, terminology/lexicon
- Quotes + incident stories + workarounds
- Evidence IDs attached to each major claim

Note:
- Candidate Personas (CPE-*) are **authoritative in <research>** as 1:1 proposals for downstream personas.
- Canonical Personas (PER-*) are **authoritative in <product-marketing> only**.

## Appendix: Canonical segment table (stable IDs)

| SegmentID | Segment name | Rank | In-scope? | Buyer map notes | Top pains (IDs) | Top gains (IDs) |
|---|---|---:|---|---|---|---|

## Appendix: Candidate persona index (stable IDs)

| CandidatePersonaID | Persona name | SegmentID | Role tags | Rank pains | Rank gains | Objections (top) |
|---|---|---|---|---|---|---|

EOF

cat > "$BUNDLE_DIR/50-evidence-bank.md" <<EOF
ID: ${ID}
Title: ${TITLE} — Evidence Bank
Status: Draft
Updated: ${DATE}
Dependencies: 
Owner: ${OWNER}

## H) Evidence pack (references + rubrics)

Checklist:
- Evidence bank includes quotes + incidents tagged to jobs/pains/gains (or context)
- Each evidence item has a stable EvidenceID (E-0001…)
- Evidence pointer (URL or repo path) + context (who/when)
- Evidence strength (E0–E4) + confidence (C1–C3)

Rubrics:
- Evidence strength (E):
  - E0 = assertion only
  - E1 = single anecdote
  - E2 = multiple consistent anecdotes
  - E3 = triangulated (anecdotes + data/doc)
  - E4 = quantified impact + triangulated
- Confidence (C):
  - C1 = low (needs validation)
  - C2 = medium (plausible, incomplete)
  - C3 = high (reliable enough for downstream work)

## Evidence bank table

| EvidenceID | Type | CandidatePersonaID | SegmentID | Tag (job/pain/gain) | Excerpt | Pointer | E-strength | Confidence |
|---|---|---|---|---|---|---|---|---|

EOF

cat > "$BUNDLE_DIR/90-methods.md" <<EOF
ID: ${ID}
Title: ${TITLE} — Methods
Status: Draft
Updated: ${DATE}
Dependencies: 
Owner: ${OWNER}

## C) Research intent + method (web) + source profile + bias notes

Checklist:
- Research intent (what decision(s) this supports)
- Method(s) used (web search, competitive scan, doc triangulation, desk research)
- Source profile (types + counts): docs, blogs, analyst notes, forums, reviews, filings, OSS repos
- Date range and freshness
- Bias notes (selection bias, survivorship, availability)
- Confidence grading approach (how you assigned C1–C3)

## C.1) Research log (queries + source trail)

Checklist:
- Search queries used (and why)
- “Source trail” notes (how you followed references)
- What you deliberately ignored (and why)

| Timestamp | Query / path | What you were testing | Sources opened |
|---|---|---|---|

## I) Quantification anchors (value ranges)

Checklist:
- Unit of value (time saved, risk reduced, revenue, compliance)
- Measurable vs not measurable
- Time-to-value bands (ranges)
- Any quantified anchors (even rough ranges) + what would firm them up

## J) Alternatives, switching costs, win/lose patterns

Checklist:
- Do-nothing baseline and inertia
- Switching costs (technical, org, procurement)
- Competitor comparisons (if any)
- Explicit “we lose when…” conditions

## K) Messaging ingredients (candidate; usable by \`<product-marketing>\`)

Checklist:
- Resonant phrases (quotes preferred)
- Taboo words / red-flag claims
- Narrative frames that worked
- Claim constraints (must/must-not)

## L) Prioritized use-case catalog (mapped)

Checklist:
- Use cases mapped to personas + triggers
- Integration/data prerequisites
- Dependencies and constraints per use case

## M) Capability constraints + non-negotiables

Checklist:
- Latency / performance requirements
- Auditability / compliance requirements
- Data residency / security posture
- Support model expectations (if relevant)

## N) Assumption register + gaps + validation plan

Checklist:
- Assumptions (explicit)
- Research gaps and unknowns
- Validation plan (next experiments)
- “Do not sell here” edge cases (explicit)

## Appendix: Glossary + naming table

| Canonical term | Disallowed synonyms | Notes |
|---|---|---|

EOF

echo "# Pitches folder" > "$BUNDLE_DIR/30-pitches/README.md"
echo "" >> "$BUNDLE_DIR/30-pitches/README.md"
echo "Create pitch files here (e.g. \`PITCH-0001.md\`) and reference EvidenceIDs from \`50-evidence-bank.md\`." >> "$BUNDLE_DIR/30-pitches/README.md"

echo "# Candidate personas folder (CPE)" > "$BUNDLE_DIR/60-candidate-personas/README.md"
echo "" >> "$BUNDLE_DIR/60-candidate-personas/README.md"
echo "Create Candidate Persona (CPE-*) files here as 1:1 proposals for canonical personas in <product-marketing>." >> "$BUNDLE_DIR/60-candidate-personas/README.md"
echo "" >> "$BUNDLE_DIR/60-candidate-personas/README.md"
echo "Preferred:" >> "$BUNDLE_DIR/60-candidate-personas/README.md"
echo "  ./phosphene/domains/research/scripts/create_candidate_persona.sh --bundle \"$BUNDLE_DIR\" --name \"...\" --segment SEG-0001" >> "$BUNDLE_DIR/60-candidate-personas/README.md"

echo "Created RA bundle: $BUNDLE_DIR"
echo "Next:"
echo "  - validate: ./.github/scripts/validate_research_assessment_bundle.sh \"$BUNDLE_DIR\""
echo "  - assemble: ./phosphene/domains/research/scripts/assemble_research_assessment_bundle.sh \"$BUNDLE_DIR\""


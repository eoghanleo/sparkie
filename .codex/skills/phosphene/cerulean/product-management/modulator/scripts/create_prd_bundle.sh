#!/usr/bin/env bash
set -euo pipefail

# create_prd_bundle.sh
# Creates a Product Requirements Document (PRD) bundle folder populated from script-defined structure.
#
# Usage (run from repo root):
#   ./.codex/skills/phosphene/cerulean/product-management/modulator/scripts/create_prd_bundle.sh --title "..." [--id PRD-001] [--owner ""] [--version v0.1]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../../../.." && pwd)"
LIB_DIR="$ROOT/phosphene/phosphene-core/lib"
# shellcheck source=/dev/null
source "$LIB_DIR/phosphene_env.sh"

usage() {
  cat <<'EOF'
Usage:
  ./.codex/skills/phosphene/cerulean/product-management/modulator/scripts/create_prd_bundle.sh --title "..." [--id PRD-001] [--owner "..."] [--dependencies "VPD-001,RA-001"] [--version v0.1]

Creates:
  phosphene/domains/product-management/output/prds/PRD-001-<slug>/
    00-coversheet.md
    10-executive-summary.md
    20-product-context.md
    30-personas-jobs-props.md
    40-goals-scope.md
    50-success-metrics.md
    60-requirements/{README.md,functional.md,non-functional.md}
    70-feature-catalogue/{README.md,core-features.md,special-features.md}
    80-architecture.md
    90-platform-technology.md
    100-data-integrations.md
    110-security-compliance.md
    120-ux-content.md
    130-delivery-roadmap.md
    140-testing-quality.md
    150-operations-support.md
    160-risks-dependencies.md
    170-release-readiness.md
    180-appendix/{README.md,glossary.md,decision-log.md,open-questions.md,traceability-matrix.md}
    PRD-001.md (assembled view; created by assemble script)
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
DEPENDENCIES=""
VERSION="v0.1"
STATUS="Draft"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) ID="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --owner) OWNER="${2:-}"; shift 2 ;;
    --dependencies) DEPENDENCIES="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --status) STATUS="${2:-}"; shift 2 ;;
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
  ID="$("$ROOT/phosphene/phosphene-core/bin/phosphene" id next --type prd)"
fi

if ! [[ "$ID" =~ ^PRD-[0-9]{3}$ ]]; then
  echo "Error: --id must look like PRD-001" >&2
  exit 2
fi

if [[ -n "${DEPENDENCIES:-}" ]]; then
  # Comma-separated list of top-level upstream artifact IDs.
  # Keep format strict so validators + done-score can parse deterministically.
  echo "$DEPENDENCIES" | tr ',' '\n' | while IFS= read -r dep; do
    dep="$(echo "$dep" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [[ -n "${dep:-}" ]] || continue
    if ! [[ "$dep" =~ ^(RA-[0-9]{3}|VPD-[0-9]{3}|ROADMAP-[0-9]{3})$ ]]; then
      echo "Error: invalid dependency: '$dep' (expected RA-###, VPD-###, or ROADMAP-###)" >&2
      exit 2
    fi
  done
fi

DOCS_DIR="$ROOT/phosphene/domains/product-management/output/prds"
mkdir -p "$DOCS_DIR"

SLUG="$(slugify "$TITLE")"
BUNDLE_DIR="$DOCS_DIR/${ID}-${SLUG}"

if [[ -e "$BUNDLE_DIR" ]]; then
  echo "Error: bundle already exists: $BUNDLE_DIR" >&2
  exit 1
fi

mkdir -p "$BUNDLE_DIR/60-requirements"
mkdir -p "$BUNDLE_DIR/70-feature-catalogue"
mkdir -p "$BUNDLE_DIR/180-appendix"

DATE="$(date +%F)"

write_with_id() {
  # Write a file that is self-contained by including the PRD ID header.
  local path="$1"
  [[ -n "${path:-}" ]] || { echo "Error: write_with_id missing path" >&2; exit 2; }
  printf "ID: %s\n\n" "$ID" > "$path"
  cat >> "$path"
}

cat > "$BUNDLE_DIR/00-coversheet.md" <<EOF
ID: ${ID}
Title: ${TITLE}
DocType: PRD (Many-release Program Bible)
Version: ${VERSION}
Status: ${STATUS}
Updated: ${DATE}
Dependencies: ${DEPENDENCIES}
Owner: ${OWNER}
EditPolicy: DO_NOT_EDIT_DIRECTLY (use scripts; see .codex/skills/phosphene/cerulean/product-management/modulator/SKILL.md)

## Purpose (read first)

This is a **PRD bundle**: the \`<product-management>\` primary artifact.

It exists to make requirements work:
- scoped (what are we building now?)
- traceable (what did this depend on?)
- testable (acceptance criteria + validation plan are explicit)

## Links

- Research assessment(s) (input): [link]
- Persona pack (input): [link]
- Proposition and messaging (input): [link]
- Roadmap (input): [link]
- ADR index: [link]
- Repo: [link]

EOF

write_with_id "$BUNDLE_DIR/10-executive-summary.md" <<'EOF'
# 1) Executive Summary

[V-SCRIPT]:
./.codex/skills/phosphene/cerulean/product-management/modulator/scripts/assemble_prd_bundle.sh

## 1.1 One-paragraph summary
[What this product is, who it is for, and the primary value delivered.]

## 1.2 The problem
- **Current user pain:** [...]
- **Business pain:** [...]
- **Why now:** [...]

## 1.3 The solution (high-level)
- **Primary capability:** [...]
- **Key differentiators:** [...]
- **Constraints that shape the solution:** [...]

## 1.4 What “success” looks like
- **User success:** [...]
- **Business success:** [...]
- **Operational success:** [...]
EOF

write_with_id "$BUNDLE_DIR/20-product-context.md" <<'EOF'
# 2) Product Context and Strategy

## 2.1 Product narrative
- **Target users:** [...]
- **Usage context:** [...]
- **Primary workflows:** [...]

## 2.2 Market and competitive landscape (optional but recommended)
- **Alternatives users choose today:** [...]
- **Differentiation thesis:** [...]
- **Switching costs and adoption barriers:** [...]

## 2.3 Strategic alignment
- **Company strategy alignment:** [...]
- **Portfolio fit:** [...]
- **Ecosystem fit:** [...]

## 2.4 Guiding principles (design and engineering)
- [Principle] -> [Implication for decisions]
EOF

write_with_id "$BUNDLE_DIR/30-personas-jobs-props.md" <<'EOF'
# 3) Personas, Jobs, and Value Propositions

## 3.1 Persona index
| Persona ID | Persona Name | Segment | Primary Context | Key Constraints | Link |
|---|---|---|---|---|---|
| PER-0001 | [Name] | [Segment] | [Context] | [Constraints] | [link] |

## 3.2 Jobs-to-be-done (JTBD)
For each persona, capture functional, emotional, and social jobs, plus triggers and success criteria.

## 3.3 Key propositions and proof points
| Proposition ID | Proposition | Primary Persona(s) | Proof / Evidence | Differentiator Type | Objections | Rebuttal / Mitigation |
|---|---|---|---|---|---|---|
| PROP-0001 | [claim] | PER-0001 | E-0001 | [product/tech/ops] | [objection] | [mitigation] |

## 3.4 Value proposition to capability mapping
| Proposition ID | Required Capabilities | UX Implications | Technical Implications | Metrics |
|---|---|---|---|---|
| PROP-0001 | [capability list] | [UX needs] | [tech needs] | [metric list] |
EOF

write_with_id "$BUNDLE_DIR/40-goals-scope.md" <<'EOF'
# 4) Goals, Non-goals, and Scope

## 4.1 Goals (outcome-based)
- G1: [...]
- G2: [...]

## 4.2 Non-goals (explicit exclusions)
- NG1: [...]

## 4.3 In-scope and out-of-scope
| Area | In Scope | Out of Scope | Notes |
|---|---|---|---|
| [Area] | ✅ | ❌ | [...] |

## 4.4 Assumptions
- A1: [...]

## 4.5 Dependencies
- D1: [...]
EOF

write_with_id "$BUNDLE_DIR/50-success-metrics.md" <<'EOF'
# 5) Success Metrics and Measurement

## 5.1 Metrics framework
Define metrics across: acquisition, activation, engagement, retention, revenue, reliability, cost.

## 5.2 North Star metric
- **North Star:** [...]
- **Why it reflects value:** [...]
- **Guardrails:** [...]

## 5.3 KPI definitions
| KPI | Definition | Event Sources | Query Logic | Target | Alert Threshold | Owner |
|---|---|---|---|---:|---:|---|
| [KPI] | [definition] | [events] | [logic] | [x] | [y] | [name] |

## 5.4 Experimentation plan
- **Hypotheses to validate:** [...]
- **Experiment types:** [...]
- **Decision criteria:** [...]
EOF

write_with_id "$BUNDLE_DIR/60-requirements/README.md" <<'EOF'
# Requirements

This folder splits requirements into functional vs non-functional.
EOF

write_with_id "$BUNDLE_DIR/60-requirements/functional.md" <<'EOF'
# 6) Requirements — functional

## 6.1 Requirement conventions
- **Requirement IDs:** R-CORE-001, R-SPEC-001, etc.
- **Modality:** shall/should/may

## 6.2 Functional requirements (FRs)
| Req ID | Statement | Priority | Persona(s) | Proposition(s) | Acceptance Criteria | Telemetry | Notes |
|---|---|---:|---|---|---|---|---|
| R-CORE-001 | The system shall… | P0 | PER-0001 | PROP-0001 | Given/When/Then | [events] | |
EOF

write_with_id "$BUNDLE_DIR/60-requirements/non-functional.md" <<'EOF'
# 6) Requirements — non-functional

Define measurable thresholds and verification methods.

## Performance and latency
| NFR ID | Scenario | Threshold | Measurement Method | Environment | Notes |
|---|---|---:|---|---|---|
| NFR-PERF-001 | [API p95 latency] | [ms] | [APM metric] | [prod-like] | |

## Availability and resilience
| NFR ID | SLO | Target | Error Budget Policy | Degradation Modes | Notes |
|---|---|---:|---|---|---|
| NFR-REL-001 | [availability] | [99.9%] | [policy] | [read-only, queued] | |
EOF

write_with_id "$BUNDLE_DIR/70-feature-catalogue/README.md" <<'EOF'
# Feature catalogue

Split into core vs special features.
EOF

write_with_id "$BUNDLE_DIR/70-feature-catalogue/core-features.md" <<'EOF'
# 7) Feature Catalogue — core

### Feature: [CORE-01 Name]
- **Feature ID:** F-CORE-01
- **Summary:** [...]
- **Primary persona(s):** PER-0001
- **Linked propositions:** PROP-0001
- **Functional requirements:** R-CORE-001
EOF

write_with_id "$BUNDLE_DIR/70-feature-catalogue/special-features.md" <<'EOF'
# 7) Feature Catalogue — special

### Feature: [SPEC-01 Name]
- **Feature ID:** F-SPEC-01
- **Why it matters:** [...]
- **Dependencies:** [...]
EOF

write_with_id "$BUNDLE_DIR/80-architecture.md" <<'EOF'
# 8) Architecture and Technical Design

## 8.1 Architecture overview
- **Architecture style:** [...]
- **Primary runtime model:** [...]
- **Core boundaries:** [...]
EOF

write_with_id "$BUNDLE_DIR/90-platform-technology.md" <<'EOF'
# 9) Platform Selection and Technology Standards

## 9.1 Selection criteria
Define explicit criteria and scoring.

## 9.2 Platform choices (with rationale)
[...]
EOF

write_with_id "$BUNDLE_DIR/100-data-integrations.md" <<'EOF'
# 10) Data, Integrations, and APIs

## 10.1 Data model overview
[...]
EOF

write_with_id "$BUNDLE_DIR/110-security-compliance.md" <<'EOF'
# 11) Security, Privacy, and Compliance

## 11.1 Data classification and handling
[...]
EOF

write_with_id "$BUNDLE_DIR/120-ux-content.md" <<'EOF'
# 12) UX, Content, and Accessibility

## 12.1 UX principles and constraints
[...]
EOF

write_with_id "$BUNDLE_DIR/130-delivery-roadmap.md" <<'EOF'
# 13) Delivery Plan and Roadmap

## 13.1 Program structure
[...]
EOF

write_with_id "$BUNDLE_DIR/140-testing-quality.md" <<'EOF'
# 14) Testing and Quality Strategy

## 14.1 Test pyramid and scope
[...]
EOF

write_with_id "$BUNDLE_DIR/150-operations-support.md" <<'EOF'
# 15) Operations and Support Model

## 15.1 Operational posture
[...]
EOF

write_with_id "$BUNDLE_DIR/160-risks-dependencies.md" <<'EOF'
# 16) Risks, Dependencies, and Assumptions

## 16.1 Risk register
| Risk | Likelihood | Impact | Exposure | Mitigation | Owner | Status |
|---|---:|---:|---:|---|---|---|
| [risk] | [L/M/H] | [L/M/H] | [score] | [mitigation] | | |
EOF

write_with_id "$BUNDLE_DIR/170-release-readiness.md" <<'EOF'
# 17) Release Readiness and Launch Plan

## 17.1 Launch strategy
[...]
EOF

write_with_id "$BUNDLE_DIR/180-appendix/README.md" <<'EOF'
# Appendix

This folder holds glossary, decision log, open questions, and traceability.
EOF

write_with_id "$BUNDLE_DIR/180-appendix/glossary.md" <<'EOF'
# 18) Appendix — glossary

| Term | Definition |
|---|---|
| Example term | Example definition |
EOF

write_with_id "$BUNDLE_DIR/180-appendix/decision-log.md" <<'EOF'
# 18) Appendix — decision log

| Date | Decision | Rationale | Owner | Link |
|---|---|---|---|---|
| [date] | [decision] | [why] | | [ADR link] |
EOF

write_with_id "$BUNDLE_DIR/180-appendix/open-questions.md" <<'EOF'
# 18) Appendix — open questions

| ID | Question | Why it matters | Owner | Due Date | Status |
|---|---|---|---|---|---|
| Q1 | [question] | [impact] | | | |
EOF

write_with_id "$BUNDLE_DIR/180-appendix/traceability-matrix.md" <<'EOF'
# 18) Appendix — traceability matrix

| Proposition ID | Capability | Feature ID(s) | Requirement ID(s) | Metric(s) | Notes |
|---|---|---|---|---|---|
| PROP-0001 | [capability] | F-CORE-01 | R-CORE-001 | [KPI] | |
EOF

echo "Created PRD bundle: $BUNDLE_DIR"
echo "Next:"
echo "  - assemble: ./.codex/skills/phosphene/cerulean/product-management/modulator/scripts/assemble_prd_bundle.sh \"$BUNDLE_DIR\""


---
name: done-score-author
description: Author deterministic PHOSPHENE domain done-score scripts and evaluators (bash-only), including metric selection, normalization, weighting, gates, and reporting. Use when creating or updating `.github/scripts/*-domain-done-score.sh` or designing new deterministic evaluation rubrics.
---

# Goal
Create deterministic done-score scripts that resist gaming and reward substantive work.

## Quick start
1. Identify domain outputs and upstream inputs (IDs, bundles, artifacts).
2. Choose evaluation objectives and target behaviors.
3. Select dimension categories from `references/done-score-design.md`.
4. Pick metrics, definitions, and wiring examples from the metric catalog.
5. Pick normalization bounds and weights (prefer input-scaled denominators).
5. Implement deterministic extractor, scorer, and reporter in bash.

## Determinism contract
- Force `LC_ALL=C`, `LANG=C`, `TZ=UTC`.
- Sort all file discovery and ID lists.
- Avoid non-deterministic sources (time, randomness, unsorted globs).
- Use stable printing (fixed decimals, stable ordering).

## Shared metrics library (MUST)
- **MUST** source `phosphene/phosphene-core/lib/phosphene_done_score_metrics.sh` immediately after `phosphene_env.sh` in every done-score script.
- **MUST** use canonical metric base names from `references/done-score-design.md` for variable names and report labels (suffixes allowed for multiple instances).
- When introducing new metrics, **MUST** add them to the shared library (or document why they must remain domain-local).

## Script composition modules
- Discovery: locate docs roots and input roots; validate existence.
- Extraction: parse sections and tables; emit canonical TSVs.
- Cleaning/hardening: remove IDs, code blocks, tables, placeholders; detect token dumps.
- Metrics: compute counts, ratios, graph stats, and corpus stats.
- Normalization: map raw metrics to 0..100 via fixed or input-scaled bounds.
- Scoring: weight categories; prefer earn-only monotonic scores.
- Gates: hard-fail on missing artifacts or required sections.
- Reporting: print overall score, subscores, and advice; return exit code.

## Input-anchored metrics (default)
- Prefer output/input ratios over absolute thresholds.
- Use input-derived targets: `target = k * input_count` (e.g., `0.6 * input_words`).
- When input is zero or missing, fall back to minimal gates and clamp ratios to 0.
- Cap ratios to avoid runaway: `ratio = min(output/input, cap)`.
- If direct input anchoring is weak or missing, anchor to upstream inputs (inputs to the input).
- When using upstream anchors, update the related apparatus skill so it knows to review those upstream documents.

## Metric catalog and wiring examples
- Use the metric catalog and wiring examples in `references/done-score-design.md` to select concrete metrics and define input/output parameters.

## Anti-gaming hardening
- Exclude IDs, URLs, script names, and `[V-SCRIPT]` from corpus metrics.
- Strip placeholders (`[...]`, `<...>`, `TBD`).
- Drop likely token dumps (high comma density, no spaces, huge lists).
- Tie metrics to upstream inputs (output/input ratios, coverage).

## Weighting and tuning
- Default to equal category weights; adjust per desired behavior.
- Use hard gates for non-negotiables; otherwise earn-only scaling.
- Prefer linear ramps with saturation; avoid sharp cliffs unless gating.
- See `references/done-score-design.md` for weighting strategies.

## Outputs and exit codes
- Print PASS/FAIL, overall score, subscores, and a metric box.
- Exit `0` when score >= min and gates pass; `1` otherwise; `2` for usage/config errors.

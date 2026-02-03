# Done-score design library

This reference captures deterministic evaluation dimensions, mechanism patterns, and weighting strategies for authoring domain done-score scripts.

## Existing patterns in this repo (quick scan)
- **Minimal scorers**: file count + word count (feature-management, ideation, strategy, vision, research, evaluation, architecture, scrum, test).
- **Rich scorers**: product-marketing and product-management add corpus cleaning, lexical diversity, depth proxies, connectivity graphs, input scaling, and hard gates.

## Input-anchoring principle (default)
Anchor as many thresholds and scores as possible to upstream inputs. Prefer input-derived denominators and targets over absolute constants.

Examples:
- Output size gate: `output_words >= 0.6 * input_words`
- Row target: `target_rows = clamp(2 * input_props, 8, 60)`
- Coverage: `unique_refs / available_refs` (clamped to 1.0)
- Ratio cap: `ratio = min(output/input, cap)`

If direct inputs are too sparse or not measurable, anchor to further upstream inputs (the inputs to the input). This is acceptable, but it requires updating the related apparatus skill so it knows to review those upstream documents when producing outputs.

Fallback when input is zero or missing:
- Clamp ratios to `0` and apply minimal presence gates instead.

## Dimension catalog (deterministic)
Use any mix of these dimensions. Favor monotonic, earn-only signals unless gating is required.

### Existence and compliance
- Required files present (count or boolean).
- Required headings present (regex scan).
- Required sections non-empty (min words or rows).
- Required tables present with correct headers.
- Required field keys present in coversheet (key:value).
- Required ID patterns present (PER, PROP, RA, etc).
- Forbidden tokens absent (TBD, placeholders).
- Schema conformity (column counts, row format).
- Valid extension/location (artifact in expected path).

### Volume and activity
- Total word count, char count, line count.
- Item counts (personas, propositions, requirements, tests).
- Row counts per table.
- Output/input ratio (words, items, rows).
- Unique item count vs total (de-dup pressure).

### Breadth and coverage
- Number of distinct categories touched.
- Coverage ratio of required categories (count of categories with >=1 item).
- Coverage ratio of upstream IDs (unique referenced / available).
- Coverage ratio of internal IDs (unique referenced / created).
- Target coverage vs dynamic targets (scaled to input size).

### Diversity and novelty (textual)
- Unique word ratio (TTR, Guiraud R).
- Hapax ratio (share of one-off word types).
- Concentration / repetitiveness (Simpson concentration; higher means more repetition).
- Shannon entropy (normalized).
- Unique bigram ratio (simple n-gram diversity).
- Segmental diversity (MSTTR over fixed windows; reduces length bias).
- Template similarity (Jaccard overlap with template text).
- Stopword ratio (proxy for content density).

### Readability and difficulty (list-free)
- Mean sentence length (words/sentence).
- Average token length (characters/token).
- Long-word proportion (>=7 letters) and unique-long-word breadth.
- LIX (length-only readability proxy; no syllables needed).

### Cohesion and coherence (overlap-based)
- Adjacent sentence overlap (Jaccard similarity of word-type sets).

### Depth and reasoning
- Avg words per fragment (table rows, bullets, sections).
- Multi-sentence ratio per fragment.
- Reasoning markers count (because, therefore, tradeoff, edge, risk).
- Evidence density (evidence IDs per item).
- Requirement acceptance criteria presence.

### Connectivity and traceability
- Bipartite graph density (items to targets).
- Average degree (per item and per target).
- Minimum degree (coverage floor).
- Multi-target ratio (items linked to >=2 targets).
- Cross-artifact linkage density (REQ to PER/PROP, FEAT to REQ).
- Traceability matrix coverage (IDs used vs IDs existing).

### Consistency and integrity
- ID uniqueness (no duplicates).
- Referential integrity (all referenced IDs exist).
- Unique artifact titles (no duplicate titles).
- Link validity (URL format checks).
- Column consistency (same number of columns per row).

### Executable and schema validation
- Compile/parse success (exit code gate).
- Test pass rate (pass/total).
- JSON/YAML schema validity (jq/yq exit code).
- Required symbols present (grep or AST parse).
- Forbidden API usage absent (pattern scan).

### Attribution and sourcing
- Source coverage ratio (unique used / available).
- Required entities covered (entity hit ratio).
- Required numbers present (numeric hit ratio).
- No made-up citations (all cited IDs exist).

### Redundancy and similarity
- Duplicate content ratio (hash-based).
- Near-duplicate ideas ratio (token similarity).
- Duplicate item ratio (normalized items).
- Compressibility / compression ratio (gzip proxy for within-document redundancy).

### Format and style constraints
- Item count vs target (list/bullets/JSON length).
- Paragraph count vs target.
- Sentence length bounds (run-on rate).
- Spelling error rate (dictionary-based).
- Dialogue or descriptive density (wordlist-based).

### Poetry or strict form (optional)
- Line count exact match.
- Syllable pattern match (heuristic).
- Rhyme scheme match (suffix match).
- Theme keyword coverage.

### Balance and distribution
- Min/avg ratio across categories (avoid single bucket domination).
- Standard deviation across categories (encourage balance).
- Per-persona minimums (e.g., 3 props per persona).
- Per-prop minimums (boosters/relievers/caps).

### Specificity and clarity (simple proxies)
- Numeral density (specificity proxy).
- Sentence length bounds (avoid too short or too long).
- Ratio of concrete nouns (if using a static wordlist).
- Presence of action verbs (simple wordlist).

### Risk and edge coverage
- Mentions of risks/objections categories (wordlist scan).
- Coverage of "edge case" phrases.
- Presence of tradeoff language (cost, risk, downside).

### Anti-gaming and quality hardening
- Placeholder removal ([], <...>, TBD).
- Code block exclusion (fenced code).
- Table exclusion when counting prose.
- Token dump detection (high comma density).
- Duplicate line suppression (uniq).

## Metric catalog (specific) with definitions
Use these metrics as concrete building blocks. Variables are explicit and reusable.

### Volume metrics
- **Output words**: `out_words = wc -w on cleaned output corpus`.
- **Input words**: `in_words = wc -w on cleaned input corpus`.
- **Output/input ratio**: `out_in_ratio = (in_words>0)?(out_words/in_words):0`.
- **Output lines**: `out_lines = wc -l on cleaned output corpus`.
- **Output items**: `out_items = count of output artifacts (e.g., PER/PROP/REQ)`.
- **Primary input words**: `in_words_primary = cleaned words in primary input corpus`.
- **Secondary input words**: `in_words_secondary = cleaned words in secondary input corpora`.
- **Output/primary ratio**: `out_in_primary_ratio = (in_words_primary>0)?(out_words/in_words_primary):0`.

### Coverage metrics
- **Input reference coverage**: `ref_cov = unique_input_refs / available_input_refs`.
- **Internal coverage**: `internal_cov = unique_internal_refs / created_internal_ids`.
- **Category coverage**: `cat_cov = categories_with_items / total_required_categories`.
- **Row fill ratio**: `row_fill = rows_filled / target_rows` (clamp to 1.0).
- **Secondary trace hits**: `sec_ref_ids_hit = unique secondary IDs referenced in output`.
- **Secondary trace total**: `sec_ref_ids_total = unique secondary IDs available in the secondary corpus`.

### Diversity metrics (textual)
- **Unique word ratio (TTR)**: `uniq_ratio = unique_words / out_words`.
- **Shannon entropy**: `H = -sum(p_i * log2(p_i))` over word types.
- **Entropy normalized**: `ent_norm = H / log2(unique_words)`.
- **Unique bigram ratio**: `uniq_bi / total_bi` (optional if you compute bigrams).
- **Hapax ratio**: `hapax_ratio = hapax_types / max(1, out_words)` where `hapax_types = count(word_types with freq==1)`.
- **Simpson concentration (repetition)**: `simpson_D = (sum_i n_i*(n_i-1)) / (out_words*(out_words-1))` (define `0` when `out_words<2`).
- **Simpson diversity**: `simpson_div = 1 - simpson_D` (higher is more diverse).

### Segment-based diversity metrics (optional)
- **Mean Segmental TTR (MSTTR)**: `msttr = avg_j( V_j / m )` over `K=floor(out_words/m)` non-overlapping segments of size `m` tokens.
  - Deterministic defaults: `m=100`, ignore the final partial segment (if any).

### Readability and difficulty metrics (list-free)
All below are intended as **domain-agnostic surface proxies**. They are not “quality” by themselves; use with appropriate weights and with anti-gaming / redundancy checks.

- **Sentence count**: `Ns = sentence_count` (deterministic splitter; be consistent).
- **Mean sentence length**: `msl = out_words / max(1, Ns)`.
- **Average token length**: `awl = token_chars / max(1, out_words)` where `token_chars = sum(length(token))` for normalized tokens (exclude whitespace).
- **Long-word proportion (>=7 letters)**: `hard7 = long_words_7plus / max(1, out_words)`.
- **Unique long-word count (>=7 letters)**: `uniq_hard7 = |{ w : len(w) >= 7 }|` (use normalized tokens).
- **LIX**: `lix = (out_words / max(1, Ns)) + 100*(long_words_7plus / max(1, out_words))`.
- **Numeric token ratio**: `num_ratio = numeric_tokens / max(1, out_words)` (tokens that are purely numeric after normalization).

### Cohesion metrics (overlap-based)
- **Adjacent sentence overlap (Jaccard)**: `overlap_adj = avg_s( |W_s ∩ W_{s+1}| / |W_s ∪ W_{s+1}| )` for `s=1..Ns-1`.
  - Notes: Compute on word *types* (sets). If stopwords dominate, compute both “all tokens” and “content-only” overlap (if you already maintain a stopword list).

### Compression and information-theoretic metrics (optional)
Use these as **redundancy / structure proxies** (often correlated with entropy and duplicate-content metrics).

- **Compression ratio (gzip, deterministic)**: `cr = bytes(gzip -n -c text) / max(1, bytes(text))`.
- **Compressibility score**: `comp = clamp(1 - cr, 0, 1)` (higher means more compressible / more redundant).

### Depth metrics
- **Fragment avg words**: `frag_avg_words = total_words / fragment_count`.
- **Multi-sentence ratio**: `two_sent_ratio = fragments_with_2plus_sentences / fragment_count`.
- **Evidence density**: `evidence_per_item = evidence_ids / items`.
- **Acceptance criteria presence**: `ac_rows / req_rows` (for requirements tables).

### Connectivity metrics (graph)
- **Bipartite density**: `dens = edges / (n_left * n_right)`.
- **Avg degree (left/right)**: `avg_left = sum_deg_left / n_left`, `avg_right = sum_deg_right / n_right`.
- **Min degree**: `min_left`, `min_right` (0 if any node unlinked).
- **Multi-target ratio**: `multi_ratio = items_with_2plus_targets / items`.

### Integrity metrics
- **ID uniqueness**: `dup_ids = total_ids - unique_ids` (zero is best).
- **Referential integrity**: `missing_refs = referenced_ids_not_found`.
- **Schema conformity**: `bad_rows / total_rows` (penalty or gate).

### Executable and schema metrics
- **Compile/parse gate**: `compile_ok = I(exit_code(cmd)==0)`.
- **Test pass rate**: `test_pass_rate = tests_passed / max(1, tests_total)`.
- **JSON valid**: `json_valid = I(exit_code("jq . < file")==0)`.
- **YAML valid**: `yaml_valid = I(exit_code("yq . < file")==0)`.
- **Required symbols**: `required_symbols_found = hits / required_symbols`.
- **Forbidden API hits**: `forbidden_hits = count_regex(codebase, pattern)`.

### Attribution and sourcing metrics
- **Source coverage**: `source_cov = unique_sources / max(1, available_sources)`.
- **Entity coverage**: `entity_cov = entities_hit / required_entities`.
- **Required numbers**: `num_cov = numbers_hit / required_numbers`.
- **No fake cites**: `made_up = cited_ids_not_in_inputs` (gate if >0).

### Redundancy and similarity metrics
- **Duplicate file ratio**: `dup_file_ratio = duplicate_hashes / max(1, total_files)`.
- **Duplicate item ratio**: `dup_item_ratio = duplicate_items / max(1, items_found)`.
- **Near-duplicate ideas**: `near_dup = pairs_similar / max(1, total_pairs)`.
- **Effective idea count**: `effective_ideas = idea_count - near_duplicate_pairs`.

### Format and style metrics
- **Item count**: `items_found` (lists, JSON arrays, rows).
- **URL per item**: `url_per_item = items_with_url / max(1, items_found)`.
- **Domain diversity**: `domain_div = unique_domains / max(1, total_urls)`.
- **Paragraph count**: `paragraphs = count_blankline_blocks`.
- **Run-on rate**: `runon_rate = long_sentences / max(1, sentence_count)`.
- **Spelling error rate**: `unknown_word_rate = unknown_words / max(1, tokens)`.
- **Dialogue density**: `dialogue_density = quote_count / max(1, word_count)`.
- **Descriptive density**: `descriptive_ratio = descriptive_words / max(1, word_count)`.

### Poetry metrics (optional)
- **Line count**: `line_count = wc -l`.
- **Syllable pattern**: `haiku_ok = I(5-7-5 by heuristic lookup)`.
- **Rhyme scheme**: `rhyme_ok = I(suffix(line1)==suffix(line3) ...)`.
- **Theme hits**: `theme_ok = theme_keyword_hits >= theme_min_hits`.

## Wiring examples (input and output parameters)
These are concrete parameterizations with input/output variables.

### Example 1: Output words anchored to direct input words
Inputs: `in_words`, output: `out_words`
- Gate: `out_words >= 0.6 * in_words`
- Score: `score_linear(out_words/in_words, 0.0, 0.6)`

### Example 2: Row target anchored to input items
Inputs: `input_props`, output: `req_rows`
- Target: `target_rows = clamp(2 * input_props, 8, 60)`
- Ratio: `row_fill = min(req_rows/target_rows, 1.0)`

### Example 3: Coverage anchored to available upstream IDs
Inputs: `available_input_refs`, output: `unique_input_refs`
- Coverage: `ref_cov = min(unique_input_refs/available_input_refs, 1.0)`
- Score: `score_linear(ref_cov, 0.10, 0.80)`

### Example 4: Connectivity anchored to output scale
Inputs: `n_per`, `n_prop`, output: `edges`
- Density: `dens = edges / (n_per * n_prop)`
- Score: `score_linear(dens, 0.10, 0.50)`

### Example 5: Depth anchored to fragment count
Inputs: `fragment_count`, output: `two_sent_count`
- Ratio: `two_sent_ratio = two_sent_count / fragment_count`
- Score: `score_linear(two_sent_ratio, 0.20, 0.75)`

### Example 6: Upstream-of-input anchoring
Inputs: `input_to_input_words` (e.g., research corpus), output: `out_words`
- Ratio: `out_in2_ratio = (input_to_input_words>0)?(out_words/input_to_input_words):0`
- Gate: `out_words >= 0.5 * input_to_input_words`
- Note: Update apparatus skill so it reads the upstream documents.

### Example 7: Anti-gaming: token-dump suppression (gate)
Inputs: `comma_dense_lines`, output: `corpus_clean`
- Gate: `comma_dense_lines == 0` (or ignore those lines in corpus).

### Example 8: Schema validity gate (JSON/YAML)
Inputs: `output_json`, output: `json_valid`
- Gate: `json_valid == 1`
- Score: `score_linear(json_valid, 1, 1)`

### Example 9: Test pass rate (code outputs)
Inputs: `tests_passed`, `tests_total`
- Ratio: `test_pass_rate = tests_passed / max(1, tests_total)`
- Score: `score_linear(test_pass_rate, 0.6, 1.0)`

### Example 10: Source coverage (research outputs)
Inputs: `available_sources`, output: `unique_sources`
- Coverage: `source_cov = min(unique_sources/available_sources, 1.0)`
- Score: `score_linear(source_cov, 0.2, 0.8)`

### Example 11: Items with attribution (web collection)
Inputs: `items_found`, output: `items_with_url`
- Ratio: `url_per_item = items_with_url / max(1, items_found)`
- Gate: `url_per_item >= 1.0` (or `items_with_url == items_found`)

### Example 12: Near-duplicate suppression (ideation)
Inputs: `idea_count`, `near_duplicate_pairs`
- Effective: `effective_ideas = idea_count - near_duplicate_pairs`
- Score: `score_linear(effective_ideas/idea_count, 0.6, 1.0)`

## Mechanism modules (compose a done script)
Use these modules as building blocks in any done-score script:
- **Discovery**: find files, locate docs root and inputs, validate paths.
- **Extraction**: parse section ranges, tables, headers, and IDs into TSVs.
- **Cleaning**: remove IDs, URLs, scripts, placeholders, code blocks.
- **Metric calculators**: counts, ratios, entropies, graph stats.
- **Normalization**: map raw metrics to 0..100 with fixed bounds.
- **Scoring**: weighted sum of category scores, earn-only by default.
- **Gating**: fail fast on missing required artifacts/sections.
- **Reporting**: print subscores, metrics, advice, and exit codes.

## Normalization patterns (deterministic)
- **Linear ramp**: `(x - min) / (max - min)` clamped to 0..1.
- **Ratio cap**: `x/t` clamped to 0..1 (use input-derived `t` when possible).
- **Input-scaled bounds**: `min = a * input`, `max = b * input`.
- **Piecewise**: reward only after a minimum threshold.
- **Log or sqrt**: use when raw counts explode (cap for stability).
- **Entropy normalization**: `H / log2(unique)` for 0..1.

## Weighting strategies (deterministic)
- **Weighted sum (SAW)**: sum of normalized metrics times weights.
- **Pairwise weighting (AHP)**: derive weights from comparisons.
- **Geometric mean**: penalize low subscores more strongly.
- **Min-of-scores**: strong gating via `overall = min(subscores)`.
- **Tiered weights**: strict gates for must-haves, soft weights for rest.

## Tuning guidance
- **Exploration bias**: raise diversity and connectivity weights.
- **Compliance bias**: raise structural completeness and traceability.
- **Depth bias**: raise multi-sentence and fragment length weights.
- **Input-aligned**: weight output/input ratios more heavily and prefer input-derived gates.
- **Anti-gaming**: hard gates for placeholders and token dumps.

## Reporting patterns
- Print overall + subscores + metric box.
- Provide "next actions" hints for any subscore < 90.
- Always include input/output counts and thresholds for auditability.

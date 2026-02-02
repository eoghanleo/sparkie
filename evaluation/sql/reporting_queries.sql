------------------------------------------------------------
-- SPARKIE EVALUATION FRAMEWORK - REPORTING QUERIES
------------------------------------------------------------
-- Collection of useful queries for analyzing evaluation results
-- and monitoring RAG system performance
------------------------------------------------------------

-- ============================================================
-- OVERVIEW & SUMMARY QUERIES
-- ============================================================

-- 1. Overall system health (last 7 days)
SELECT
    COUNT(DISTINCT i.interaction_id) as total_interactions,
    COUNT(DISTINCT i.session_id) as total_sessions,
    COUNT(DISTINCT e.eval_id) as total_evaluations,

    ROUND(AVG(e.answer_relevance), 3) as avg_relevance,
    ROUND(AVG(e.hallucination_score), 3) as avg_hallucination,
    ROUND(AVG(e.citation_accuracy), 3) as avg_citation_accuracy,
    ROUND(AVG(e.answer_completeness), 3) as avg_completeness,

    ROUND(AVG(i.latency_ms), 1) as avg_latency_ms,
    ROUND(SUM(i.total_cost_usd), 4) as total_cost_usd,

    SUM(CASE WHEN i.status = 'error' THEN 1 ELSE 0 END) as error_count,
    ROUND(SUM(CASE WHEN i.status = 'error' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) as error_rate_pct
FROM RAG_INTERACTION i
LEFT JOIN EVAL_RESULTS e ON i.interaction_id = e.interaction_id
WHERE i.ts >= DATEADD(day, -7, CURRENT_TIMESTAMP());

-- 2. Daily performance trends
SELECT
    DATE_TRUNC('day', i.ts) as date,
    COUNT(*) as interactions,
    ROUND(AVG(e.answer_relevance), 3) as avg_relevance,
    ROUND(AVG(e.hallucination_score), 3) as avg_hallucination,
    ROUND(AVG(e.citation_accuracy), 3) as avg_citation_accuracy,
    ROUND(AVG(i.latency_ms), 1) as avg_latency_ms,
    SUM(CASE WHEN i.status = 'error' THEN 1 ELSE 0 END) as errors,
    SUM(CASE WHEN e.answer_relevance >= 0.7
            AND e.hallucination_score <= 0.3
            AND e.citation_accuracy >= 0.8 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as pass_rate_pct
FROM RAG_INTERACTION i
LEFT JOIN EVAL_RESULTS e ON i.interaction_id = e.interaction_id
WHERE i.ts >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY DATE_TRUNC('day', i.ts)
ORDER BY date DESC;

-- 3. Pass/Fail distribution
SELECT
    CASE
        WHEN e.answer_relevance >= 0.7
            AND e.hallucination_score <= 0.3
            AND e.citation_accuracy >= 0.8 THEN 'PASS'
        ELSE 'FAIL'
    END as status,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM EVAL_RESULTS e
WHERE e.evaluated_at >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY status;

-- ============================================================
-- QUALITY METRICS DEEP DIVE
-- ============================================================

-- 4. Hallucination analysis
SELECT
    CASE
        WHEN hallucination_score = 0 THEN '0.00 - Perfect'
        WHEN hallucination_score <= 0.2 THEN '0.01-0.20 - Excellent'
        WHEN hallucination_score <= 0.4 THEN '0.21-0.40 - Good'
        WHEN hallucination_score <= 0.6 THEN '0.41-0.60 - Concerning'
        WHEN hallucination_score <= 0.8 THEN '0.61-0.80 - Poor'
        ELSE '0.81-1.00 - Severe'
    END as hallucination_range,
    COUNT(*) as count,
    ROUND(AVG(answer_relevance), 3) as avg_relevance,
    ROUND(AVG(citation_accuracy), 3) as avg_citation_accuracy
FROM EVAL_RESULTS
WHERE evaluated_at >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY hallucination_range
ORDER BY hallucination_range;

-- 5. Top 10 worst hallucinations (for investigation)
SELECT
    i.interaction_id,
    i.user_query,
    SUBSTR(i.answer_text, 1, 200) as answer_preview,
    e.hallucination_score,
    e.unsupported_claims,
    e.judge_reasoning
FROM RAG_INTERACTION i
JOIN EVAL_RESULTS e ON i.interaction_id = e.interaction_id
WHERE e.hallucination_score > 0.5
ORDER BY e.hallucination_score DESC
LIMIT 10;

-- 6. Citation accuracy by clause
SELECT
    e.expected_clause,
    COUNT(*) as total_occurrences,
    SUM(CASE WHEN e.correct_clause_ref = TRUE THEN 1 ELSE 0 END) as correct_citations,
    ROUND(SUM(CASE WHEN e.correct_clause_ref = TRUE THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) as accuracy_pct,
    ROUND(AVG(e.citation_accuracy), 3) as avg_citation_score
FROM EVAL_RESULTS e
WHERE e.expected_clause IS NOT NULL
  AND e.evaluated_at >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY e.expected_clause
HAVING COUNT(*) >= 3
ORDER BY accuracy_pct ASC, total_occurrences DESC
LIMIT 20;

-- ============================================================
-- RETRIEVAL PERFORMANCE
-- ============================================================

-- 7. Content type distribution in retrievals
SELECT
    i.metadata:chunks_metadata[0]:content_type::STRING as primary_content_type,
    COUNT(*) as occurrences,
    ROUND(AVG(e.answer_relevance), 3) as avg_relevance,
    ROUND(AVG(e.hallucination_score), 3) as avg_hallucination,
    ROUND(AVG(i.metadata:retrieval_time::FLOAT), 3) as avg_retrieval_time_sec
FROM RAG_INTERACTION i
LEFT JOIN EVAL_RESULTS e ON i.interaction_id = e.interaction_id
WHERE i.ts >= DATEADD(day, -7, CURRENT_TIMESTAMP())
  AND i.metadata:chunks_metadata IS NOT NULL
GROUP BY primary_content_type
ORDER BY occurrences DESC;

-- 8. Similarity score analysis
SELECT
    CASE
        WHEN i.metadata:chunks_metadata[0]:similarity::FLOAT >= 0.8 THEN '0.8-1.0 - Excellent'
        WHEN i.metadata:chunks_metadata[0]:similarity::FLOAT >= 0.6 THEN '0.6-0.8 - Good'
        WHEN i.metadata:chunks_metadata[0]:similarity::FLOAT >= 0.4 THEN '0.4-0.6 - Fair'
        WHEN i.metadata:chunks_metadata[0]:similarity::FLOAT >= 0.2 THEN '0.2-0.4 - Poor'
        ELSE '0.0-0.2 - Very Poor'
    END as similarity_range,
    COUNT(*) as count,
    ROUND(AVG(e.answer_relevance), 3) as avg_relevance,
    ROUND(AVG(e.hallucination_score), 3) as avg_hallucination
FROM RAG_INTERACTION i
LEFT JOIN EVAL_RESULTS e ON i.interaction_id = e.interaction_id
WHERE i.ts >= DATEADD(day, -7, CURRENT_TIMESTAMP())
  AND i.metadata:chunks_metadata[0]:similarity IS NOT NULL
GROUP BY similarity_range
ORDER BY similarity_range DESC;

-- ============================================================
-- GOLDEN SET REGRESSION TRACKING
-- ============================================================

-- 9. Golden set performance over time
SELECT
    r.run_name,
    r.started_at,
    r.interactions_evaluated,
    r.avg_answer_relevance,
    r.avg_hallucination_score,
    r.avg_citation_accuracy,
    r.pass_rate,
    r.status
FROM EVAL_RUNS r
WHERE r.run_type = 'golden_set'
ORDER BY r.started_at DESC
LIMIT 20;

-- 10. Question type performance (golden set)
SELECT
    i.metadata:question_type::STRING as question_type,
    COUNT(*) as total_questions,
    ROUND(AVG(e.answer_relevance), 3) as avg_relevance,
    ROUND(AVG(e.hallucination_score), 3) as avg_hallucination,
    ROUND(AVG(e.citation_accuracy), 3) as avg_citation_accuracy,
    ROUND(AVG(e.technical_accuracy), 3) as avg_technical_accuracy,
    SUM(CASE WHEN e.answer_relevance >= 0.7
            AND e.hallucination_score <= 0.3
            AND e.citation_accuracy >= 0.8 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as pass_rate_pct
FROM RAG_INTERACTION i
JOIN EVAL_RESULTS e ON i.interaction_id = e.interaction_id
WHERE i.eval_run_id IS NOT NULL
  AND i.metadata:question_type IS NOT NULL
GROUP BY question_type
ORDER BY pass_rate_pct ASC;

-- ============================================================
-- COST & PERFORMANCE OPTIMIZATION
-- ============================================================

-- 11. Latency breakdown analysis
SELECT
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY i.latency_ms) as p50_latency_ms,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY i.latency_ms) as p90_latency_ms,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY i.latency_ms) as p95_latency_ms,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY i.latency_ms) as p99_latency_ms,
    MAX(i.latency_ms) as max_latency_ms,
    ROUND(AVG(i.metadata:retrieval_time::FLOAT * 1000), 1) as avg_retrieval_ms,
    ROUND(AVG(i.metadata:generation_time::FLOAT * 1000), 1) as avg_generation_ms
FROM RAG_INTERACTION i
WHERE i.ts >= DATEADD(day, -7, CURRENT_TIMESTAMP())
  AND i.status = 'success';

-- 12. Cost analysis (if token counts available)
SELECT
    DATE_TRUNC('day', i.ts) as date,
    COUNT(*) as interactions,
    SUM(i.prompt_tokens) as total_prompt_tokens,
    SUM(i.answer_tokens) as total_answer_tokens,
    SUM(i.total_cost_usd) as total_cost_usd,
    ROUND(AVG(i.prompt_tokens), 1) as avg_prompt_tokens,
    ROUND(AVG(i.answer_tokens), 1) as avg_answer_tokens
FROM RAG_INTERACTION i
WHERE i.ts >= DATEADD(day, -30, CURRENT_TIMESTAMP())
  AND i.prompt_tokens IS NOT NULL
GROUP BY DATE_TRUNC('day', i.ts)
ORDER BY date DESC;

-- ============================================================
-- FAILURE ANALYSIS
-- ============================================================

-- 13. Error patterns
SELECT
    i.status,
    i.metadata:error::STRING as error_type,
    COUNT(*) as occurrences,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM RAG_INTERACTION i
WHERE i.ts >= DATEADD(day, -7, CURRENT_TIMESTAMP())
  AND i.status != 'success'
GROUP BY i.status, error_type
ORDER BY occurrences DESC;

-- 14. Failed evaluations needing retry
SELECT
    q.queue_id,
    q.interaction_id,
    q.retry_count,
    q.error_message,
    q.queued_at,
    i.user_query
FROM EVAL_QUEUE q
JOIN RAG_INTERACTION i ON q.interaction_id = i.interaction_id
WHERE q.status = 'failed'
ORDER BY q.queued_at DESC
LIMIT 20;

-- ============================================================
-- EXPORT QUERIES (for dashboards/notebooks)
-- ============================================================

-- 15. Export full evaluation dataset (last 7 days)
SELECT
    i.interaction_id,
    i.session_id,
    i.ts as timestamp,
    i.user_query,
    i.answer_text,
    i.latency_ms,
    i.status,

    e.answer_relevance,
    e.answer_completeness,
    e.hallucination_score,
    e.citation_accuracy,
    e.correct_clause_ref,
    e.expected_clause,
    e.cited_clauses,
    e.technical_accuracy,

    i.metadata:chunks_used::INT as chunks_used,
    i.metadata:visual_content_count::INT as visual_count,
    i.metadata:retrieval_time::FLOAT as retrieval_time_sec,
    i.metadata:generation_time::FLOAT as generation_time_sec,

    e.judge_reasoning,
    e.metadata as eval_metadata
FROM RAG_INTERACTION i
LEFT JOIN EVAL_RESULTS e ON i.interaction_id = e.interaction_id
WHERE i.ts >= DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY i.ts DESC;

-- 16. Aggregate metrics for time-series visualization
SELECT
    DATE_TRUNC('hour', i.ts) as hour,
    COUNT(*) as interactions,
    ROUND(AVG(e.answer_relevance), 3) as avg_relevance,
    ROUND(AVG(e.hallucination_score), 3) as avg_hallucination,
    ROUND(AVG(e.citation_accuracy), 3) as avg_citation,
    ROUND(AVG(i.latency_ms), 1) as avg_latency_ms,
    SUM(CASE WHEN i.status = 'error' THEN 1 ELSE 0 END) as errors
FROM RAG_INTERACTION i
LEFT JOIN EVAL_RESULTS e ON i.interaction_id = e.interaction_id
WHERE i.ts >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY DATE_TRUNC('hour', i.ts)
ORDER BY hour DESC;

-- ============================================================
-- ALERTS & MONITORING
-- ============================================================

-- 17. Alert: High hallucination rate (last hour)
SELECT
    COUNT(*) as recent_interactions,
    SUM(CASE WHEN e.hallucination_score > 0.5 THEN 1 ELSE 0 END) as high_hallucination_count,
    ROUND(SUM(CASE WHEN e.hallucination_score > 0.5 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) as hallucination_rate_pct,
    CASE
        WHEN SUM(CASE WHEN e.hallucination_score > 0.5 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) > 20
        THEN 'ALERT: High hallucination rate!'
        ELSE 'OK'
    END as alert_status
FROM RAG_INTERACTION i
JOIN EVAL_RESULTS e ON i.interaction_id = e.interaction_id
WHERE i.ts >= DATEADD(hour, -1, CURRENT_TIMESTAMP());

-- 18. Alert: Degraded performance (compared to last 7 days baseline)
WITH baseline AS (
    SELECT
        AVG(answer_relevance) as baseline_relevance,
        AVG(hallucination_score) as baseline_hallucination
    FROM EVAL_RESULTS
    WHERE evaluated_at BETWEEN DATEADD(day, -7, CURRENT_TIMESTAMP())
                           AND DATEADD(hour, -1, CURRENT_TIMESTAMP())
),
recent AS (
    SELECT
        AVG(answer_relevance) as recent_relevance,
        AVG(hallucination_score) as recent_hallucination
    FROM EVAL_RESULTS
    WHERE evaluated_at >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
)
SELECT
    b.baseline_relevance,
    r.recent_relevance,
    r.recent_relevance - b.baseline_relevance as relevance_delta,

    b.baseline_hallucination,
    r.recent_hallucination,
    r.recent_hallucination - b.baseline_hallucination as hallucination_delta,

    CASE
        WHEN r.recent_relevance < b.baseline_relevance - 0.1
          OR r.recent_hallucination > b.baseline_hallucination + 0.1
        THEN 'ALERT: Performance degradation detected!'
        ELSE 'OK'
    END as alert_status
FROM baseline b
CROSS JOIN recent r;

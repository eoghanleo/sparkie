------------------------------------------------------------
-- SPARKIE EVALUATION FRAMEWORK - SNOWFLAKE SCHEMA
------------------------------------------------------------
-- This schema extends the existing RAG_SESSION and RAG_INTERACTION
-- tables with evaluation metrics and golden set testing capability
------------------------------------------------------------

------------------------------------------------------------
-- EVAL_RESULTS: Store evaluation metrics for each interaction
------------------------------------------------------------
CREATE OR REPLACE TABLE EVAL_RESULTS (
    eval_id              STRING          NOT NULL,
    interaction_id       STRING          NOT NULL,
    eval_run_id          STRING,
    evaluated_at         TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),

    -- Retrieval Quality Metrics
    retrieval_precision  FLOAT,          -- % of retrieved chunks that were relevant
    retrieval_recall     FLOAT,          -- % of relevant chunks that were retrieved
    avg_similarity       FLOAT,          -- Mean similarity score of retrieved chunks
    content_diversity    FLOAT,          -- 0-1 score: mix of text/table/visual
    chunks_used_count    INT,
    visual_count         INT,
    table_count          INT,
    text_count           INT,

    -- Generation Quality Metrics
    answer_relevance     FLOAT,          -- 0-1: Does answer address the question?
    answer_completeness  FLOAT,          -- 0-1: Are all parts answered?
    hallucination_score  FLOAT,          -- 0-1: Claims not in retrieved context (0=good)
    citation_accuracy    FLOAT,          -- 0-1: Accuracy of clause references

    -- AS3000 Domain-Specific Metrics
    correct_clause_ref   BOOLEAN,        -- Did it cite the right AS3000 clause?
    expected_clause      STRING,         -- From golden set if available
    cited_clauses        VARIANT,        -- Array of clauses mentioned in response
    technical_accuracy   FLOAT,          -- 0-1: Domain expert eval or comparison to golden answer

    -- Performance Metrics
    retrieval_time_ms    FLOAT,
    generation_time_ms   FLOAT,
    total_time_ms        FLOAT,

    -- Human Feedback (optional, for future)
    human_rating         INT,            -- 1-5 star rating
    human_feedback       STRING,         -- Free text feedback
    human_reviewed_at    TIMESTAMP_TZ,

    -- LLM-as-Judge Details
    judge_model          STRING,         -- Model used for evaluation
    judge_prompt_tokens  INT,
    judge_response_tokens INT,
    judge_reasoning      STRING,         -- Explanation of scores

    -- Metadata
    eval_method          STRING,         -- 'llm_judge', 'golden_set', 'hybrid'
    eval_version         STRING,         -- Version of eval logic
    metadata             VARIANT,        -- Additional context

    CONSTRAINT pk_eval_results PRIMARY KEY (eval_id),
    CONSTRAINT fk_eval_interaction
        FOREIGN KEY (interaction_id) REFERENCES RAG_INTERACTION(interaction_id)
);

-- Indexes for common query patterns
CREATE INDEX idx_eval_results_interaction ON EVAL_RESULTS(interaction_id);
CREATE INDEX idx_eval_results_run ON EVAL_RESULTS(eval_run_id);
CREATE INDEX idx_eval_results_evaluated_at ON EVAL_RESULTS(evaluated_at);

------------------------------------------------------------
-- EVAL_RUNS: Track evaluation campaigns
------------------------------------------------------------
CREATE OR REPLACE TABLE EVAL_RUNS (
    eval_run_id          STRING          NOT NULL,
    run_name             STRING,
    run_type             STRING,         -- 'golden_set', 'production_sample', 'regression', 'ab_test'

    -- Timing
    started_at           TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    completed_at         TIMESTAMP_TZ,

    -- Configuration
    eval_config          VARIANT,        -- {metrics: [...], thresholds: {...}, model: "..."}
    filter_criteria      VARIANT,        -- What interactions to evaluate
    sample_size          INT,

    -- Summary Results
    interactions_evaluated INT,
    avg_answer_relevance FLOAT,
    avg_hallucination_score FLOAT,
    avg_citation_accuracy FLOAT,
    avg_total_time_ms    FLOAT,
    pass_rate            FLOAT,          -- % meeting quality thresholds
    summary_metrics      VARIANT,        -- Additional aggregated metrics

    -- Status
    status               STRING,         -- 'running', 'completed', 'failed', 'cancelled'
    error_message        STRING,

    -- Metadata
    created_by           STRING,
    notes                STRING,

    CONSTRAINT pk_eval_runs PRIMARY KEY (eval_run_id)
);

CREATE INDEX idx_eval_runs_type ON EVAL_RUNS(run_type);
CREATE INDEX idx_eval_runs_started ON EVAL_RUNS(started_at);

------------------------------------------------------------
-- GOLDEN_SET: Reference Q&A pairs for regression testing
------------------------------------------------------------
CREATE OR REPLACE TABLE GOLDEN_SET (
    golden_id            STRING          NOT NULL,
    question             STRING          NOT NULL,
    question_type        STRING,         -- 'COMPLIANCE', 'CALCULATION', 'FACTUAL', 'SCENARIO'
    expected_answer      STRING,
    clause_reference     STRING,         -- Expected AS3000 clause
    chunk_id             STRING,         -- Source chunk from RAW_TEXT
    content_type         STRING,         -- 'structured_table', 'text_chunk', etc.
    source_path          STRING,

    -- Test Configuration
    answer_length        STRING,         -- 'SHORT', 'MEDIUM', 'LONG'
    difficulty           STRING,         -- 'EASY', 'MEDIUM', 'HARD'
    is_active            BOOLEAN         DEFAULT TRUE,

    -- Metadata
    created_at           TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    updated_at           TIMESTAMP_TZ,
    tags                 VARIANT,        -- Array of topic tags
    notes                STRING,

    CONSTRAINT pk_golden_set PRIMARY KEY (golden_id)
);

CREATE INDEX idx_golden_set_type ON GOLDEN_SET(question_type);
CREATE INDEX idx_golden_set_active ON GOLDEN_SET(is_active);

------------------------------------------------------------
-- EVAL_QUEUE: Async processing queue for background evals
------------------------------------------------------------
CREATE OR REPLACE TABLE EVAL_QUEUE (
    queue_id             STRING          NOT NULL,
    interaction_id       STRING          NOT NULL,
    eval_run_id          STRING,

    -- Queue Management
    queued_at            TIMESTAMP_TZ    DEFAULT CURRENT_TIMESTAMP(),
    claimed_at           TIMESTAMP_TZ,   -- When worker started processing
    completed_at         TIMESTAMP_TZ,
    worker_id            STRING,         -- Which worker is processing

    -- Status
    status               STRING          DEFAULT 'pending',  -- 'pending', 'claimed', 'completed', 'failed'
    retry_count          INT             DEFAULT 0,
    max_retries          INT             DEFAULT 3,
    error_message        STRING,

    -- Priority
    priority             INT             DEFAULT 5,          -- 1=highest, 10=lowest

    CONSTRAINT pk_eval_queue PRIMARY KEY (queue_id)
);

CREATE INDEX idx_eval_queue_status ON EVAL_QUEUE(status, priority, queued_at);
CREATE INDEX idx_eval_queue_interaction ON EVAL_QUEUE(interaction_id);

------------------------------------------------------------
-- VIEWS: Useful analytical views
------------------------------------------------------------

-- Recent eval performance summary
CREATE OR REPLACE VIEW V_EVAL_SUMMARY_DAILY AS
SELECT
    DATE_TRUNC('day', evaluated_at) as eval_date,
    COUNT(*) as total_evals,
    AVG(answer_relevance) as avg_relevance,
    AVG(hallucination_score) as avg_hallucination,
    AVG(citation_accuracy) as avg_citation_accuracy,
    AVG(total_time_ms) as avg_latency_ms,
    SUM(CASE WHEN answer_relevance >= 0.7
             AND hallucination_score <= 0.3
             AND citation_accuracy >= 0.8 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as pass_rate
FROM EVAL_RESULTS
GROUP BY DATE_TRUNC('day', evaluated_at)
ORDER BY eval_date DESC;

-- Join interactions with eval results
CREATE OR REPLACE VIEW V_INTERACTION_WITH_EVAL AS
SELECT
    i.interaction_id,
    i.session_id,
    i.ts as interaction_ts,
    i.user_query,
    i.answer_text,
    i.model_name,
    i.latency_ms as reported_latency,
    i.total_cost_usd,
    i.status as interaction_status,

    e.eval_id,
    e.evaluated_at,
    e.answer_relevance,
    e.hallucination_score,
    e.citation_accuracy,
    e.correct_clause_ref,
    e.technical_accuracy,
    e.judge_reasoning,

    e.chunks_used_count,
    e.content_diversity,
    e.avg_similarity
FROM RAG_INTERACTION i
LEFT JOIN EVAL_RESULTS e ON i.interaction_id = e.interaction_id
ORDER BY i.ts DESC;

-- Failed interactions needing attention
CREATE OR REPLACE VIEW V_FAILED_INTERACTIONS AS
SELECT
    i.interaction_id,
    i.ts,
    i.user_query,
    i.status,
    e.hallucination_score,
    e.citation_accuracy,
    e.judge_reasoning
FROM RAG_INTERACTION i
LEFT JOIN EVAL_RESULTS e ON i.interaction_id = e.interaction_id
WHERE i.status = 'error'
   OR e.hallucination_score > 0.5
   OR e.citation_accuracy < 0.5
ORDER BY i.ts DESC;

-- Golden set performance tracking
CREATE OR REPLACE VIEW V_GOLDEN_SET_PERFORMANCE AS
SELECT
    g.question_type,
    g.difficulty,
    COUNT(DISTINCT g.golden_id) as total_questions,
    COUNT(DISTINCT i.interaction_id) as tested_questions,
    AVG(e.answer_relevance) as avg_relevance,
    AVG(e.citation_accuracy) as avg_citation_accuracy,
    SUM(CASE WHEN e.correct_clause_ref = TRUE THEN 1 ELSE 0 END) * 100.0 /
        NULLIF(COUNT(e.eval_id), 0) as correct_clause_pct
FROM GOLDEN_SET g
LEFT JOIN RAG_INTERACTION i ON g.question = i.user_query
LEFT JOIN EVAL_RESULTS e ON i.interaction_id = e.interaction_id
WHERE g.is_active = TRUE
GROUP BY g.question_type, g.difficulty;

------------------------------------------------------------
-- UTILITY PROCEDURES
------------------------------------------------------------

-- Claim next item from eval queue (for workers)
CREATE OR REPLACE PROCEDURE CLAIM_EVAL_QUEUE_ITEM(worker_id STRING)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    queue_id STRING;
BEGIN
    -- Find oldest pending item
    SELECT TOP 1 queue_id INTO :queue_id
    FROM EVAL_QUEUE
    WHERE status = 'pending'
    ORDER BY priority ASC, queued_at ASC;

    -- Claim it
    IF (queue_id IS NOT NULL) THEN
        UPDATE EVAL_QUEUE
        SET status = 'claimed',
            claimed_at = CURRENT_TIMESTAMP(),
            worker_id = :worker_id
        WHERE queue_id = :queue_id;
    END IF;

    RETURN queue_id;
END;
$$;

-- Mark eval queue item complete
CREATE OR REPLACE PROCEDURE COMPLETE_EVAL_QUEUE_ITEM(
    queue_id STRING,
    success BOOLEAN,
    error_msg STRING DEFAULT NULL
)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    IF (success) THEN
        UPDATE EVAL_QUEUE
        SET status = 'completed',
            completed_at = CURRENT_TIMESTAMP()
        WHERE queue_id = :queue_id;
    ELSE
        UPDATE EVAL_QUEUE
        SET retry_count = retry_count + 1,
            status = CASE
                WHEN retry_count + 1 >= max_retries THEN 'failed'
                ELSE 'pending'
            END,
            error_message = :error_msg,
            claimed_at = NULL,
            worker_id = NULL
        WHERE queue_id = :queue_id;
    END IF;

    RETURN 'Success';
END;
$$;

------------------------------------------------------------
-- GRANTS (adjust as needed for your roles)
------------------------------------------------------------
-- GRANT SELECT, INSERT, UPDATE ON EVAL_RESULTS TO ROLE RAG_SERVICE_ROLE;
-- GRANT SELECT, INSERT, UPDATE ON EVAL_QUEUE TO ROLE RAG_SERVICE_ROLE;
-- GRANT SELECT ON GOLDEN_SET TO ROLE RAG_SERVICE_ROLE;
-- GRANT ALL ON EVAL_RUNS TO ROLE RAG_ADMIN_ROLE;

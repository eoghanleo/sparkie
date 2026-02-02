"""
Run Golden Set Evaluation with KG Metrics - Write to Snowflake

This script:
1. Loads 50 questions from GOLDEN_SET_QUESTIONS
2. Runs evaluation with current KG reranking setting
3. Writes all results to Snowflake EVAL_RESULTS and EVAL_RUNS tables
"""

import sys
import os
import logging
import uuid
from datetime import datetime
import json

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(__file__))

from app.sparkie_engine import SparkieEngine, USE_KG_RERANK
from evaluation.eval_metrics_v2 import EvalMetricsV2
import snowflake.connector
from dotenv import load_dotenv

load_dotenv()

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class GoldenSetEvaluator:
    """Run golden set evaluation with KG-aware metrics"""

    def __init__(self):
        self.connection = None
        self.engine = None
        self.evaluator = None

    def connect_snowflake(self):
        """Connect to Snowflake"""
        try:
            self.connection = snowflake.connector.connect(
                account=os.getenv('SNOWFLAKE_ACCOUNT'),
                user=os.getenv('SNOWFLAKE_USER'),
                private_key=os.getenv('SNOWFLAKE_PRIVATE_KEY'),
                warehouse=os.getenv('SNOWFLAKE_WAREHOUSE'),
                database=os.getenv('SNOWFLAKE_DATABASE'),
                schema=os.getenv('SNOWFLAKE_SCHEMA'),
                role=os.getenv('SNOWFLAKE_ROLE'),
            )
            logger.info("Connected to Snowflake")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to Snowflake: {e}")
            return False

    def load_questions(self, limit=50):
        """Load golden set questions from Snowflake"""
        if not self.connection:
            self.connect_snowflake()

        try:
            cursor = self.connection.cursor()
            query = f"""
                SELECT
                    question_id,
                    question_text,
                    ground_truth_answer,
                    clause_number,
                    has_table,
                    has_diagram
                FROM TEST_DB.CORTEX.GOLDEN_SET_QUESTIONS
                WHERE question_variant_number = 1
                ORDER BY page_number
                LIMIT {limit}
            """

            cursor.execute(query)
            rows = cursor.fetchall()
            cursor.close()

            questions = []
            for row in rows:
                questions.append({
                    'question_id': row[0],
                    'question': row[1],
                    'expected_answer': row[2],
                    'expected_clause': row[3],
                    'has_table': row[4],
                    'has_diagram': row[5]
                })

            logger.info(f"Loaded {len(questions)} golden set questions")
            return questions

        except Exception as e:
            logger.error(f"Failed to load questions: {e}")
            return []

    def run_evaluation(self, questions, run_name):
        """
        Run evaluation on questions and write to Snowflake

        Args:
            questions: List of question dicts
            run_name: Name for this eval run

        Returns:
            Dict with eval_run_id and summary
        """
        # Initialize engine and evaluator
        self.engine = SparkieEngine()
        self.evaluator = EvalMetricsV2(snowflake_conn=self.connection)

        eval_run_id = str(uuid.uuid4())
        results = []

        print(f"\n{'='*80}")
        print(f"STARTING EVALUATION: {run_name}")
        print(f"KG Reranking: {'ENABLED' if USE_KG_RERANK else 'DISABLED'}")
        print(f"Questions: {len(questions)}")
        print(f"Eval Run ID: {eval_run_id}")
        print(f"{'='*80}\n")

        # Create eval run record
        self._create_eval_run_record(eval_run_id, run_name, len(questions))

        for i, q in enumerate(questions, 1):
            print(f"\n[{i}/{len(questions)}] {q['question'][:70]}...")

            try:
                # Generate response using Sparkie engine
                response = self.engine.generate_response([], q['question'])

                # Prepare retrieved context for evaluation
                retrieved_context = response.get('chunks_metadata', []) + response.get('visual_metadata', [])

                # Run evaluation
                eval_results = self.evaluator.evaluate_interaction(
                    question=q['question'],
                    answer=response.get('response', ''),
                    retrieved_context=retrieved_context,
                    expected_answer=q.get('expected_answer'),
                    expected_clause=q.get('expected_clause'),
                    golden_has_table=q.get('has_table'),
                    golden_has_diagram=q.get('has_diagram')
                )

                # Count chunks and visuals
                # Visual items have 'thumbnail_url' or content_id starting with 'VISUAL_'
                # Text chunks have content_type='text_chunk'
                def is_visual(item):
                    return 'thumbnail_url' in item or item.get('content_id', '').startswith('VISUAL_')

                visual_count = len([c for c in retrieved_context if is_visual(c)])
                chunks_count = len([c for c in retrieved_context if not is_visual(c)])

                # Extract timing metrics from response
                retrieval_time_ms = int(response.get('retrieval_time', 0) * 1000) if response.get('retrieval_time') else None
                generation_time_ms = int(response.get('generation_time', 0) * 1000) if response.get('generation_time') else None
                total_time_ms = (retrieval_time_ms + generation_time_ms) if (retrieval_time_ms and generation_time_ms) else None

                # Store result
                # CRITICAL: Use interaction_id from response (generated by @log_rag_interaction decorator)
                # DO NOT generate new ID here - it must match RAG_INTERACTION table
                result = {
                    'question_id': q['question_id'],
                    'interaction_id': response.get('interaction_id'),  # Use ID from decorator
                    'eval_run_id': eval_run_id,
                    'question': q['question'],
                    'answer': response.get('response', ''),
                    'retrieved_context': retrieved_context,
                    'kg_config': response.get('kg_config', {}),
                    'chunks_used_count': chunks_count,
                    'visual_count': visual_count,
                    'retrieval_time_ms': retrieval_time_ms,
                    'generation_time_ms': generation_time_ms,
                    'total_time_ms': total_time_ms,
                    'judge_model': 'meta-llama/llama-4-maverick-17b-128e-instruct',
                    'eval_method': 'llm_judge',
                    'eval_version': '2.0_kg_aware',
                    **eval_results
                }
                results.append(result)

                # Save to database
                self._save_eval_result(result)

                # Log key metrics
                passed = eval_results.get('passed')
                pass_indicator = "PASS" if passed else ("FAIL" if passed is False else "N/A")
                print(f"  Result:            {pass_indicator}")
                print(f"  Hallucination:     {eval_results.get('hallucination_score', 0):.2f}")
                print(f"  Citation Acc:      {eval_results.get('citation_accuracy', 0):.2f}")
                print(f"  Technical Acc:     {eval_results.get('technical_accuracy', 'N/A')}")
                print(f"  Norm Coverage:     {eval_results.get('kg_normative_coverage', 0):.2f}")
                if not passed:
                    print(f"  Reason:            {eval_results.get('pass_fail_reason', '')}")

            except Exception as e:
                logger.error(f"  ERROR: {e}")
                import traceback
                logger.error(traceback.format_exc())
                continue

        # Compute summary
        summary = self._compute_summary(results)
        self._complete_eval_run(eval_run_id, summary)

        print(f"\n{'='*80}")
        print(f"EVALUATION COMPLETE: {run_name}")
        print(f"{'='*80}")
        print(json.dumps(summary, indent=2))

        return {
            'eval_run_id': eval_run_id,
            'run_name': run_name,
            'results': results,
            'summary': summary
        }

    def _create_eval_run_record(self, eval_run_id, run_name, sample_size):
        """Create EVAL_RUNS record in Snowflake - optimized without temp tables"""
        if not self.connection:
            return

        try:
            cursor = self.connection.cursor()

            eval_config = {
                'kg_enabled': USE_KG_RERANK,
                'evaluator_version': '2.0_kg_aware',
                'judge_model': 'meta-llama/llama-4-maverick-17b-128e-instruct'
            }
            eval_config_json = json.dumps(eval_config)

            # Direct INSERT with SELECT + PARSE_JSON (VALUES clause doesn't support PARSE_JSON)
            cursor.execute("""
                INSERT INTO TEST_DB.CORTEX.EVAL_RUNS (
                    eval_run_id, run_name, run_type, sample_size, eval_config, status
                )
                SELECT %s, %s, %s, %s, PARSE_JSON(%s), %s
            """, (eval_run_id, run_name, 'golden_set_kg_test', sample_size, eval_config_json, 'running'))

            self.connection.commit()
            cursor.close()

            logger.info(f"Created eval run record: {eval_run_id}")

        except Exception as e:
            logger.error(f"Failed to create eval run record: {e}")
            self.connection.rollback()

    def _save_eval_result(self, result):
        """Save evaluation result to EVAL_RESULTS table - optimized without temp tables"""
        if not self.connection:
            return

        try:
            cursor = self.connection.cursor()

            # Generate eval_id
            eval_id = str(uuid.uuid4())

            # Prepare metadata
            metadata = {
                'retrieved_context': result.get('retrieved_context', []),
                'kg_config': result.get('kg_config', {}),
                'kg_retrieved_counts': result.get('kg_retrieved_counts', {}),
                'kg_cited_counts': result.get('kg_cited_counts', {}),
                'passed': result.get('passed'),
                'pass_fail_reason': result.get('pass_fail_reason')
            }
            metadata_json = json.dumps(metadata)

            # Prepare cited clauses JSON
            cited_clauses = result.get('cited_clauses', [])
            cited_clauses_json = json.dumps(cited_clauses) if cited_clauses else None

            # Prepare judge reasoning (combine all details)
            judge_reasoning = result.get('hallucination_details', '') or result.get('citation_details', '')
            if judge_reasoning:
                judge_reasoning = judge_reasoning[:500]  # Truncate to 500 chars

            # Direct INSERT with SELECT + PARSE_JSON (VALUES clause doesn't support PARSE_JSON)
            cursor.execute("""
                INSERT INTO TEST_DB.CORTEX.EVAL_RESULTS (
                    eval_id, interaction_id, eval_run_id, question_id,
                    chunks_used_count, visual_count,
                    retrieval_time_ms, generation_time_ms, total_time_ms,
                    hallucination_score, citation_accuracy,
                    answer_relevance, answer_completeness, technical_accuracy,
                    correct_clause_ref, expected_clause, cited_clauses,
                    judge_model, judge_prompt_tokens, judge_response_tokens, judge_reasoning,
                    eval_method, eval_version,
                    kg_normative_coverage, kg_non_normative_reliance,
                    kg_c_reliance_pct, kg_conditional_risk, kg_multimodal_starvation,
                    metadata
                )
                SELECT
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                    CASE WHEN %s IS NOT NULL THEN PARSE_JSON(%s) ELSE NULL END,
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                    PARSE_JSON(%s)
            """, (
                eval_id,
                result.get('interaction_id'),
                result.get('eval_run_id'),
                result.get('question_id'),
                result.get('chunks_used_count'),
                result.get('visual_count'),
                result.get('retrieval_time_ms'),
                result.get('generation_time_ms'),
                result.get('total_time_ms'),
                result.get('hallucination_score'),
                result.get('citation_accuracy'),
                result.get('answer_relevance'),
                result.get('answer_completeness'),
                result.get('technical_accuracy'),
                result.get('correct_clause_ref'),
                result.get('expected_clause'),
                cited_clauses_json,  # For NULL check
                cited_clauses_json,  # For PARSE_JSON
                result.get('judge_model'),
                result.get('judge_prompt_tokens'),
                result.get('judge_response_tokens'),
                judge_reasoning,
                result.get('eval_method'),
                result.get('eval_version'),
                result.get('kg_normative_coverage'),
                result.get('kg_non_normative_reliance'),
                result.get('kg_c_reliance_pct'),
                result.get('kg_conditional_risk'),
                result.get('kg_multimodal_starvation'),
                metadata_json
            ))

            self.connection.commit()
            cursor.close()

        except Exception as e:
            logger.error(f"Failed to save eval result: {e}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")
            self.connection.rollback()

    def _compute_summary(self, results):
        """Compute summary statistics"""
        if not results:
            return {}

        def mean(values):
            valid = [v for v in values if v is not None]
            return sum(valid) / len(valid) if valid else None

        # Compute pass rate
        pass_results = [r.get('passed') for r in results if r.get('passed') is not None]
        passed_count = sum(1 for p in pass_results if p is True)
        failed_count = sum(1 for p in pass_results if p is False)
        pass_rate = (passed_count / len(pass_results) * 100) if pass_results else None

        return {
            'total_questions': len(results),
            'kg_reranking_enabled': USE_KG_RERANK,
            'passed_count': passed_count,
            'failed_count': failed_count,
            'pass_rate_pct': pass_rate,
            'avg_hallucination_score': mean([r.get('hallucination_score') for r in results]),
            'avg_citation_accuracy': mean([r.get('citation_accuracy') for r in results]),
            'avg_answer_relevance': mean([r.get('answer_relevance') for r in results]),
            'avg_answer_completeness': mean([r.get('answer_completeness') for r in results]),
            'avg_technical_accuracy': mean([r.get('technical_accuracy') for r in results]),
            'avg_kg_normative_coverage': mean([r.get('kg_normative_coverage') for r in results]),
            'avg_kg_non_normative_reliance': mean([r.get('kg_non_normative_reliance') for r in results]),
            'avg_kg_c_reliance_pct': mean([r.get('kg_c_reliance_pct') for r in results]),
            'avg_kg_conditional_risk': mean([r.get('kg_conditional_risk') for r in results]),
            'avg_kg_multimodal_starvation': mean([r.get('kg_multimodal_starvation') for r in results])
        }

    def _complete_eval_run(self, eval_run_id, summary):
        """Update EVAL_RUNS with completion status - optimized without temp tables"""
        if not self.connection:
            return

        try:
            cursor = self.connection.cursor()
            summary_json = json.dumps(summary)

            # Direct UPDATE with PARSE_JSON - no temp tables needed
            cursor.execute("""
                UPDATE TEST_DB.CORTEX.EVAL_RUNS
                SET
                    status = %s,
                    completed_at = CURRENT_TIMESTAMP(),
                    summary_metrics = PARSE_JSON(%s)
                WHERE eval_run_id = %s
            """, ('completed', summary_json, eval_run_id))

            self.connection.commit()
            cursor.close()

            logger.info(f"Completed eval run: {eval_run_id}")

        except Exception as e:
            logger.error(f"Failed to complete eval run: {e}")
            self.connection.rollback()

    def _refresh_feature_stores(self):
        """Manually refresh dynamic tables after eval completes"""
        if not self.connection:
            return

        try:
            cursor = self.connection.cursor()

            print("\n" + "="*80)
            print("REFRESHING FEATURE STORES")
            print("="*80)

            # Refresh in dependency order
            print("Refreshing FEATURE_INTERACTIONS...")
            cursor.execute("""
                ALTER DYNAMIC TABLE ELECTRICAL_STANDARDS_DB.AS_STANDARDS.FEATURE_INTERACTIONS
                REFRESH
            """)
            print("[OK] FEATURE_INTERACTIONS refreshed")

            print("Refreshing VECTOR_EPISODIC_QUERY...")
            cursor.execute("""
                ALTER DYNAMIC TABLE ELECTRICAL_STANDARDS_DB.AS_STANDARDS.VECTOR_EPISODIC_QUERY
                REFRESH
            """)
            print("[OK] VECTOR_EPISODIC_QUERY refreshed")

            print("Refreshing VECTOR_EPISODIC_ANSWER...")
            cursor.execute("""
                ALTER DYNAMIC TABLE ELECTRICAL_STANDARDS_DB.AS_STANDARDS.VECTOR_EPISODIC_ANSWER
                REFRESH
            """)
            print("[OK] VECTOR_EPISODIC_ANSWER refreshed")

            self.connection.commit()
            cursor.close()

            print("="*80)
            print("FEATURE STORE REFRESH COMPLETE")
            print("="*80 + "\n")

        except Exception as e:
            logger.error(f"Failed to refresh feature stores: {e}")
            print(f"[X] Feature store refresh failed: {e}")
            print("  (This is non-critical - eval results are still saved)")

    def close(self):
        """Close connections"""
        if self.connection:
            self.connection.close()


def main():
    """Main execution"""
    print("\n" + "="*80)
    print("GOLDEN SET EVALUATION - KG-AWARE RAG")
    print("="*80 + "\n")

    evaluator = GoldenSetEvaluator()

    # Load questions
    print("Loading golden set questions...")
    questions = evaluator.load_questions(limit=50)

    if not questions:
        print("ERROR: No questions loaded!")
        return

    print(f"Loaded {len(questions)} questions\n")

    # Run evaluation
    run_name = f"golden_set_kg_{'on' if USE_KG_RERANK else 'off'}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"

    results = evaluator.run_evaluation(
        questions=questions,
        run_name=run_name
    )

    # Refresh feature stores with latest eval data
    evaluator._refresh_feature_stores()

    # Close connections
    evaluator.close()

    print("\n" + "="*80)
    print("EVALUATION COMPLETE!")
    print("="*80 + "\n")
    print(f"Eval Run ID: {results['eval_run_id']}")
    print(f"Results written to Snowflake EVAL_RESULTS and EVAL_RUNS tables")
    print(f"\nTo query results:")
    print(f"  SELECT * FROM EVAL_RESULTS WHERE eval_run_id = '{results['eval_run_id']}'")


if __name__ == "__main__":
    main()

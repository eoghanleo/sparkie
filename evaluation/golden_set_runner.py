"""
Golden Set Regression Testing for Sparkie RAG Application

Loads test questions from CSV and runs them through the RAG system,
comparing results against expected answers and tracking performance over time.
"""

import asyncio
import logging
import csv
import uuid
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional
import json
from pathlib import Path

import snowflake.connector
from snowflake.connector import DictCursor
import aiohttp
from dotenv import load_dotenv
import os

from .eval_metrics_v2 import EvalMetricsV2 as EvalMetrics

load_dotenv()
logger = logging.getLogger(__name__)


class GoldenSetRunner:
    """
    Manages golden set / regression testing using test questions CSV
    """

    def __init__(
        self,
        api_base_url: str = "http://localhost:8000"
    ):
        self.api_base_url = api_base_url
        self.connection = None
        self.evaluator = None  # Will be initialized after connection

    def connect(self):
        """Establish Snowflake connection"""
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
            logger.info("GoldenSetRunner connected to Snowflake")
            # Initialize evaluator with Snowflake connection for presigned URLs
            self.evaluator = EvalMetrics(snowflake_conn=self.connection)
            return True
        except Exception as e:
            logger.error(f"Failed to connect to Snowflake: {e}")
            return False

    def close(self):
        """Close Snowflake connection"""
        if self.connection:
            self.connection.close()

    def load_test_questions(
        self,
        limit: Optional[int] = None,
        has_table: Optional[bool] = None,
        has_diagram: Optional[bool] = None,
        has_calculation: Optional[bool] = None
    ) -> List[Dict[str, Any]]:
        """
        Load test questions from GOLDEN_SET_QUESTIONS table

        Args:
            limit: Maximum number of questions to load
            has_table: Filter by questions with tables
            has_diagram: Filter by questions with diagrams
            has_calculation: Filter by questions with calculations

        Returns:
            List of test question dicts
        """
        if not self.connection:
            self.connect()

        questions = []

        try:
            cursor = self.connection.cursor(DictCursor)

            # Build WHERE clause for filters
            where_clauses = ["question_variant_number = 1"]  # Only use variant 1 to avoid duplicates

            if has_table is not None:
                where_clauses.append(f"has_table = {has_table}")
            if has_diagram is not None:
                where_clauses.append(f"has_diagram = {has_diagram}")
            if has_calculation is not None:
                where_clauses.append(f"has_calculation = {has_calculation}")

            where_clause = " AND ".join(where_clauses)
            limit_clause = f"LIMIT {limit}" if limit else ""

            query = f"""
                SELECT
                    question_id,
                    question_text,
                    question_group_id,
                    ground_truth_answer,
                    clause_number,
                    table_number,
                    page_number,
                    has_table,
                    has_diagram,
                    has_calculation,
                    source_document
                FROM TEST_DB.CORTEX.GOLDEN_SET_QUESTIONS
                WHERE {where_clause}
                ORDER BY page_number
                {limit_clause}
            """

            cursor.execute(query)
            rows = cursor.fetchall()

            for row in rows:
                questions.append({
                    'question_id': row['QUESTION_ID'],
                    'question': row['QUESTION_TEXT'],
                    'question_group_id': row['QUESTION_GROUP_ID'],
                    'expected_answer': row['GROUND_TRUTH_ANSWER'],
                    'clause_reference': row['CLAUSE_NUMBER'],
                    'table_number': row['TABLE_NUMBER'],
                    'page_number': row['PAGE_NUMBER'],
                    'has_table': row['HAS_TABLE'],
                    'has_diagram': row['HAS_DIAGRAM'],
                    'has_calculation': row['HAS_CALCULATION'],
                    'source_document': row['SOURCE_DOCUMENT']
                })

            cursor.close()
            logger.info(f"Loaded {len(questions)} test questions from GOLDEN_SET_QUESTIONS")
            return questions

        except Exception as e:
            logger.error(f"Failed to load test questions: {e}")
            return []

    async def run_golden_set_evaluation(
        self,
        run_name: str,
        limit: Optional[int] = 100,
        has_table: Optional[bool] = None,
        has_diagram: Optional[bool] = None,
        has_calculation: Optional[bool] = None,
        concurrency: int = 5
    ) -> Dict[str, Any]:
        """
        Run complete golden set evaluation

        Args:
            run_name: Name for this eval run
            limit: Number of questions to test
            has_table: Filter by questions with tables
            has_diagram: Filter by questions with diagrams
            has_calculation: Filter by questions with calculations
            concurrency: Number of concurrent API requests

        Returns:
            Summary of evaluation results
        """
        # Create eval run
        eval_run_id = await self._create_eval_run(run_name, limit, has_table, has_diagram, has_calculation)

        # Load test questions
        test_questions = self.load_test_questions(limit=limit, has_table=has_table, has_diagram=has_diagram, has_calculation=has_calculation)

        if not test_questions:
            logger.error("No test questions loaded")
            return {}

        logger.info(f"Starting golden set evaluation: {run_name} ({len(test_questions)} questions)")

        # Process questions with concurrency control
        semaphore = asyncio.Semaphore(concurrency)
        tasks = [
            self._evaluate_test_question(q, eval_run_id, semaphore)
            for q in test_questions
        ]

        results = await asyncio.gather(*tasks, return_exceptions=True)

        # Calculate summary metrics
        summary = self._calculate_summary(results)
        summary['eval_run_id'] = eval_run_id

        # Update eval run with results
        await self._complete_eval_run(eval_run_id, summary)

        logger.info(f"Golden set evaluation complete: {run_name}")
        logger.info(f"Summary: {json.dumps(summary, indent=2)}")

        return summary

    async def _create_eval_run(
        self,
        run_name: str,
        sample_size: int,
        has_table: Optional[bool],
        has_diagram: Optional[bool],
        has_calculation: Optional[bool]
    ) -> str:
        """Create EVAL_RUNS record"""
        if not self.connection:
            self.connect()

        eval_run_id = str(uuid.uuid4())

        try:
            cursor = self.connection.cursor()

            # Use temp table approach for PARSE_JSON
            temp_table = f"TEMP_EVAL_RUN_{uuid.uuid4().hex[:8]}"

            eval_config_json = json.dumps({
                'has_table': has_table,
                'has_diagram': has_diagram,
                'has_calculation': has_calculation,
                'evaluator_version': '1.0',
                'judge_model': self.evaluator.judge_model
            })

            # Create temp table with JSON string
            cursor.execute(f"""
                CREATE TEMP TABLE {temp_table} (
                    eval_run_id VARCHAR,
                    run_name VARCHAR,
                    sample_size NUMBER,
                    eval_config_json_str VARCHAR
                )
            """)

            cursor.execute(f"""
                INSERT INTO {temp_table}
                VALUES (%s, %s, %s, %s)
            """, (eval_run_id, run_name, sample_size, eval_config_json))

            # INSERT from temp table with PARSE_JSON
            cursor.execute(f"""
                INSERT INTO TEST_DB.CORTEX.EVAL_RUNS (
                    eval_run_id,
                    run_name,
                    run_type,
                    sample_size,
                    eval_config,
                    status
                )
                SELECT
                    eval_run_id, run_name, 'golden_set', sample_size,
                    PARSE_JSON(eval_config_json_str), 'running'
                FROM {temp_table}
            """)

            cursor.execute(f"DROP TABLE {temp_table}")
            self.connection.commit()
            cursor.close()

            logger.info(f"Created eval run: {eval_run_id}")
            return eval_run_id

        except Exception as e:
            logger.error(f"Failed to create eval run: {e}")
            self.connection.rollback()
            return str(uuid.uuid4())  # Fallback

    async def _evaluate_test_question(
        self,
        test_question: Dict[str, Any],
        eval_run_id: str,
        semaphore: asyncio.Semaphore
    ) -> Dict[str, Any]:
        """
        Send question to RAG API and evaluate response

        Returns:
            Evaluation result dict
        """
        async with semaphore:
            try:
                # Call RAG API
                response_data = await self._call_rag_api(test_question['question'])

                if not response_data:
                    return {
                        'success': False,
                        'error': 'API call failed'
                    }

                # Build retrieved context from response metadata
                retrieved_context = self._extract_retrieved_context(response_data)

                # Run evaluation
                eval_results = self.evaluator.evaluate_interaction(
                    question=test_question['question'],
                    answer=response_data['response'],
                    retrieved_context=retrieved_context,
                    expected_answer=test_question.get('expected_answer'),
                    expected_clause=test_question.get('clause_reference')
                )

                # Get interaction_id from API response (already logged by main.py)
                interaction_id = response_data.get('interaction_id') or str(uuid.uuid4())

                # Store eval results (interaction already logged by API)
                # Pass the full retrieved_context so we can log what the judge saw
                self._store_eval_results(
                    interaction_id, eval_run_id, eval_results, response_data,
                    retrieved_context, test_question['question']
                )

                return {
                    'success': True,
                    'interaction_id': interaction_id,
                    'eval_results': eval_results
                }

            except Exception as e:
                logger.error(f"Failed to evaluate question: {e}")
                return {
                    'success': False,
                    'error': str(e)
                }

    async def _call_rag_api(self, question: str) -> Optional[Dict[str, Any]]:
        """
        Call Sparkie RAG API with question

        Returns:
            Response data or None if failed
        """
        try:
            async with aiohttp.ClientSession() as session:
                # Start session
                async with session.post(
                    f"{self.api_base_url}/api/start-session"
                ) as resp:
                    session_data = await resp.json()
                    session_id = session_data['session_id']

                # Send question
                async with session.post(
                    f"{self.api_base_url}/api/chat",
                    json={
                        'session_id': session_id,
                        'message': question
                    },
                    timeout=aiohttp.ClientTimeout(total=60)
                ) as resp:
                    if resp.status == 200:
                        return await resp.json()
                    else:
                        logger.error(f"API returned status {resp.status}")
                        return None

        except asyncio.TimeoutError:
            logger.error(f"API call timed out for question: {question[:50]}...")
            return None
        except Exception as e:
            logger.error(f"API call failed: {e}")
            return None

    def _extract_retrieved_context(self, response_data: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Extract retrieved context from API response"""
        context = []

        # Add text/table chunks
        for chunk in response_data.get('chunks_metadata', []):
            context.append({
                'content_id': chunk.get('content_id'),
                'content_type': chunk.get('content_type'),
                'page_number': chunk.get('page_number'),
                'similarity': chunk.get('similarity'),
                'text_content': chunk.get('chunk_preview', chunk.get('description', ''))
            })

        # Add visual content
        for visual in response_data.get('visual_metadata', []):
            context.append({
                'content_id': visual.get('content_id'),
                'content_type': 'visual',
                'page_number': visual.get('page_number'),
                'similarity': visual.get('similarity'),
                'description': visual.get('description', ''),
                'image_url': visual.get('thumbnail_url', '')  # Add image URL for vision judge
            })

        return context

    def _log_interaction(
        self,
        interaction_id: str,
        session_id: str,
        user_query: str,
        answer_text: str,
        latency_ms: float,
        eval_run_id: str,
        metadata: Dict[str, Any]
    ):
        """Log interaction to RAG_INTERACTION table"""
        if not self.connection:
            return

        try:
            cursor = self.connection.cursor()

            # Use temp table approach for PARSE_JSON
            temp_table = f"TEMP_INTERACTION_{uuid.uuid4().hex[:8]}"

            metadata_json = json.dumps(metadata)

            # Create temp table with JSON string
            cursor.execute(f"""
                CREATE TEMP TABLE {temp_table} (
                    interaction_id VARCHAR,
                    session_id VARCHAR,
                    user_query VARCHAR,
                    answer_text VARCHAR,
                    latency_ms NUMBER,
                    eval_run_id VARCHAR,
                    metadata_json_str VARCHAR
                )
            """)

            cursor.execute(f"""
                INSERT INTO {temp_table}
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, (interaction_id, session_id, user_query, answer_text, latency_ms, eval_run_id, metadata_json))

            # INSERT from temp table with PARSE_JSON
            cursor.execute(f"""
                INSERT INTO RAG_INTERACTION (
                    interaction_id, session_id, user_query, answer_text,
                    latency_ms, eval_run_id, status, metadata
                )
                SELECT
                    interaction_id, session_id, user_query, answer_text,
                    latency_ms, eval_run_id, 'success', PARSE_JSON(metadata_json_str)
                FROM {temp_table}
            """)

            cursor.execute(f"DROP TABLE {temp_table}")
            self.connection.commit()
            cursor.close()

        except Exception as e:
            logger.error(f"Failed to log interaction: {e}")
            self.connection.rollback()

    def _store_eval_results(
        self,
        interaction_id: str,
        eval_run_id: str,
        eval_results: Dict[str, Any],
        response_data: Dict[str, Any],
        retrieved_context: List[Dict[str, Any]],
        user_query: str = None
    ):
        """Store evaluation results to EVAL_RESULTS table"""
        if not self.connection:
            return

        try:
            eval_id = str(uuid.uuid4())
            cursor = self.connection.cursor()

            # Use temp table approach for PARSE_JSON
            temp_table = f"TEMP_EVAL_RESULTS_{uuid.uuid4().hex[:8]}"

            cited_clauses_json = json.dumps(eval_results.get('cited_clauses', []))

            # IMPORTANT: Log the FULL context that the judge evaluated against
            # This includes ALL chunks (text, visual, tables) in the order the judge saw them
            metadata_json = json.dumps({
                'user_query': user_query,  # Store the question for dashboard
                'hallucination_details': eval_results.get('hallucination_details'),
                'citation_details': eval_results.get('citation_details'),
                'relevance_details': eval_results.get('relevance_details'),
                'generated_answer': response_data.get('response', ''),  # Store the answer for dashboard
                'judge_context_full': retrieved_context,  # Full context sent to judge
                'judge_context_summary': {
                    'total_chunks': len(retrieved_context),
                    'visual_chunks': len([c for c in retrieved_context if c.get('content_type') == 'visual']),
                    'text_chunks': len([c for c in retrieved_context if c.get('content_type') != 'visual']),
                    'content_ids': [c.get('content_id') for c in retrieved_context]
                }
            })

            # Create temp table with JSON strings
            cursor.execute(f"""
                CREATE TEMP TABLE {temp_table} (
                    eval_id VARCHAR,
                    interaction_id VARCHAR,
                    eval_run_id VARCHAR,
                    answer_relevance FLOAT,
                    answer_completeness FLOAT,
                    hallucination_score FLOAT,
                    citation_accuracy FLOAT,
                    correct_clause_ref BOOLEAN,
                    cited_clauses_json_str VARCHAR,
                    expected_clause VARCHAR,
                    technical_accuracy FLOAT,
                    retrieval_time_ms FLOAT,
                    generation_time_ms FLOAT,
                    total_time_ms FLOAT,
                    chunks_used_count NUMBER,
                    visual_count NUMBER,
                    judge_model VARCHAR,
                    judge_prompt_tokens NUMBER,
                    judge_response_tokens NUMBER,
                    judge_reasoning VARCHAR,
                    metadata_json_str VARCHAR
                )
            """)

            cursor.execute(f"""
                INSERT INTO {temp_table}
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                eval_id,
                interaction_id,
                eval_run_id,
                eval_results.get('answer_relevance'),
                eval_results.get('answer_completeness'),
                eval_results.get('hallucination_score'),
                eval_results.get('citation_accuracy'),
                eval_results.get('correct_clause_ref'),
                cited_clauses_json,
                eval_results.get('expected_clause'),
                eval_results.get('technical_accuracy'),
                response_data.get('retrieval_time', 0) * 1000,
                response_data.get('generation_time', 0) * 1000,
                response_data.get('total_time', 0) * 1000,
                response_data.get('chunks_used'),
                response_data.get('visual_content_count'),
                self.evaluator.judge_model,
                eval_results.get('judge_prompt_tokens'),
                eval_results.get('judge_response_tokens'),
                self._build_judge_reasoning(eval_results),
                metadata_json
            ))

            # INSERT from temp table with PARSE_JSON
            cursor.execute(f"""
                INSERT INTO TEST_DB.CORTEX.EVAL_RESULTS (
                    eval_id, interaction_id, eval_run_id,
                    answer_relevance, answer_completeness, hallucination_score,
                    citation_accuracy, correct_clause_ref, cited_clauses,
                    expected_clause, technical_accuracy,
                    retrieval_time_ms, generation_time_ms, total_time_ms,
                    chunks_used_count, visual_count,
                    judge_model, judge_prompt_tokens, judge_response_tokens,
                    judge_reasoning, eval_method, eval_version,
                    metadata
                )
                SELECT
                    eval_id, interaction_id, eval_run_id,
                    answer_relevance, answer_completeness, hallucination_score,
                    citation_accuracy, correct_clause_ref, PARSE_JSON(cited_clauses_json_str),
                    expected_clause, technical_accuracy,
                    retrieval_time_ms, generation_time_ms, total_time_ms,
                    chunks_used_count, visual_count,
                    judge_model, judge_prompt_tokens, judge_response_tokens,
                    judge_reasoning, 'golden_set', '1.0',
                    PARSE_JSON(metadata_json_str)
                FROM {temp_table}
            """)

            cursor.execute(f"DROP TABLE {temp_table}")
            self.connection.commit()
            cursor.close()

        except Exception as e:
            logger.error(f"Failed to store eval results: {e}")
            self.connection.rollback()

    def _build_judge_reasoning(self, eval_results: Dict[str, Any]) -> str:
        """Combine reasoning fields"""
        parts = []
        for key in ['hallucination_details', 'citation_details', 'relevance_details', 'completeness_details']:
            if eval_results.get(key):
                parts.append(f"{key}: {eval_results[key]}")
        return " | ".join(parts)

    def _calculate_summary(self, results: List[Any]) -> Dict[str, Any]:
        """Calculate summary metrics from evaluation results"""
        successful = [r for r in results if isinstance(r, dict) and r.get('success')]

        if not successful:
            return {
                'interactions_evaluated': 0,
                'error': 'All evaluations failed'
            }

        eval_results = [r['eval_results'] for r in successful]

        # Calculate averages
        avg_relevance = self._safe_avg([e.get('answer_relevance') for e in eval_results])
        avg_hallucination = self._safe_avg([e.get('hallucination_score') for e in eval_results])
        avg_citation = self._safe_avg([e.get('citation_accuracy') for e in eval_results])
        avg_completeness = self._safe_avg([e.get('answer_completeness') for e in eval_results])
        avg_technical = self._safe_avg([e.get('technical_accuracy') for e in eval_results])

        # Calculate pass rate (thresholds: relevance >= 0.7, hallucination <= 0.3, citation >= 0.8)
        passes = sum(
            1 for e in eval_results
            if (e.get('answer_relevance', 0) >= 0.7 and
                (e.get('hallucination_score') or 1) <= 0.3 and
                e.get('citation_accuracy', 0) >= 0.8)
        )
        pass_rate = passes / len(eval_results) if eval_results else 0

        return {
            'interactions_evaluated': len(successful),
            'avg_answer_relevance': round(avg_relevance, 3) if avg_relevance else None,
            'avg_hallucination_score': round(avg_hallucination, 3) if avg_hallucination else None,
            'avg_citation_accuracy': round(avg_citation, 3) if avg_citation else None,
            'avg_completeness': round(avg_completeness, 3) if avg_completeness else None,
            'avg_technical_accuracy': round(avg_technical, 3) if avg_technical else None,
            'pass_rate': round(pass_rate, 3)
        }

    def _safe_avg(self, values: List[Optional[float]]) -> Optional[float]:
        """Calculate average, filtering None values"""
        valid = [v for v in values if v is not None]
        return sum(valid) / len(valid) if valid else None

    async def _complete_eval_run(self, eval_run_id: str, summary: Dict[str, Any]):
        """Update EVAL_RUNS with completion status and summary"""
        if not self.connection:
            return

        try:
            cursor = self.connection.cursor()
            cursor.execute("""
                UPDATE TEST_DB.CORTEX.EVAL_RUNS
                SET completed_at = CURRENT_TIMESTAMP(),
                    status = 'completed',
                    interactions_evaluated = %s,
                    avg_answer_relevance = %s,
                    avg_hallucination_score = %s,
                    avg_citation_accuracy = %s,
                    pass_rate = %s,
                    summary_metrics = PARSE_JSON(%s)
                WHERE eval_run_id = %s
            """, (
                summary.get('interactions_evaluated'),
                summary.get('avg_answer_relevance'),
                summary.get('avg_hallucination_score'),
                summary.get('avg_citation_accuracy'),
                summary.get('pass_rate'),
                json.dumps(summary),
                eval_run_id
            ))
            self.connection.commit()
            cursor.close()

        except Exception as e:
            logger.error(f"Failed to complete eval run: {e}")
            self.connection.rollback()


async def main():
    """Main entry point for running golden set evaluation"""
    import argparse

    parser = argparse.ArgumentParser(description='Run golden set evaluation')
    parser.add_argument('--sample-size', type=int, default=50, help='Number of questions to evaluate')
    parser.add_argument('--has-table', type=bool, default=None, help='Filter questions with tables')
    parser.add_argument('--has-diagram', type=bool, default=None, help='Filter questions with diagrams')
    parser.add_argument('--has-calculation', type=bool, default=None, help='Filter questions with calculations')
    parser.add_argument('--concurrency', type=int, default=5, help='Number of concurrent evaluations')

    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

    runner = GoldenSetRunner()
    runner.connect()

    try:
        summary = await runner.run_golden_set_evaluation(
            run_name=f"Golden Set - {args.sample_size} Questions - {datetime.now().strftime('%Y-%m-%d %H:%M')}",
            limit=args.sample_size,
            has_table=args.has_table,
            has_diagram=args.has_diagram,
            has_calculation=args.has_calculation,
            concurrency=args.concurrency
        )

        print(f"\n=== Evaluation Complete ===")
        print(json.dumps(summary, indent=2))

    finally:
        runner.close()


if __name__ == "__main__":
    asyncio.run(main())

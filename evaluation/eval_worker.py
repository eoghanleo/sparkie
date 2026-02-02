"""
Async Evaluation Worker for Sparkie RAG Application

Background worker that processes EVAL_QUEUE and runs evaluation metrics
on logged interactions without blocking production requests.
"""

import asyncio
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List
import signal
import sys

import snowflake.connector
from snowflake.connector import DictCursor
from dotenv import load_dotenv
import os

from .eval_metrics_v2 import EvalMetricsV2 as EvalMetrics

load_dotenv()
logger = logging.getLogger(__name__)


class EvalWorker:
    """
    Background worker that claims items from EVAL_QUEUE and evaluates them
    """

    def __init__(
        self,
        worker_id: Optional[str] = None,
        batch_size: int = 10,
        poll_interval: int = 5,
        max_concurrent: int = 3
    ):
        self.worker_id = worker_id or f"worker-{uuid.uuid4().hex[:8]}"
        self.batch_size = batch_size
        self.poll_interval = poll_interval
        self.max_concurrent = max_concurrent
        self.running = False
        self.connection = None
        self.evaluator = None  # Will be initialized after connection

        logger.info(f"EvalWorker initialized: {self.worker_id}")

    def connect(self):
        """Establish Snowflake connection and initialize evaluator"""
        try:
            self.connection = snowflake.connector.connect(
                account=os.getenv('SNOWFLAKE_ACCOUNT'),
                user=os.getenv('SNOWFLAKE_USER'),
                password=os.getenv('SNOWFLAKE_PASSWORD'),
                warehouse=os.getenv('SNOWFLAKE_WAREHOUSE'),
                database=os.getenv('SNOWFLAKE_DATABASE'),
                schema=os.getenv('SNOWFLAKE_SCHEMA'),
                role=os.getenv('SNOWFLAKE_ROLE'),
            )
            logger.info(f"Worker {self.worker_id} connected to Snowflake")

            # Initialize evaluator with Snowflake connection for presigned URL generation
            self.evaluator = EvalMetrics(snowflake_conn=self.connection)
            logger.info(f"EvalMetrics initialized with Snowflake connection")

            return True
        except Exception as e:
            logger.error(f"Failed to connect to Snowflake: {e}")
            return False

    def close(self):
        """Close Snowflake connection"""
        if self.connection:
            self.connection.close()
            logger.info(f"Worker {self.worker_id} disconnected from Snowflake")

    async def start(self):
        """Start the worker loop"""
        self.running = True
        logger.info(f"Worker {self.worker_id} starting...")

        if not self.connect():
            logger.error("Failed to connect, worker exiting")
            return

        # Set up graceful shutdown
        loop = asyncio.get_event_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, self.stop)

        try:
            while self.running:
                await self._process_batch()
                await asyncio.sleep(self.poll_interval)

        except Exception as e:
            logger.error(f"Worker error: {e}", exc_info=True)
        finally:
            self.close()
            logger.info(f"Worker {self.worker_id} stopped")

    def stop(self):
        """Signal worker to stop gracefully"""
        logger.info(f"Worker {self.worker_id} received stop signal")
        self.running = False

    async def _process_batch(self):
        """Process a batch of eval queue items"""
        # Claim items from queue
        queue_items = self._claim_queue_items(self.batch_size)

        if not queue_items:
            logger.debug(f"No items in queue, sleeping...")
            return

        logger.info(f"Processing {len(queue_items)} items from queue")

        # Process items concurrently
        tasks = [
            self._evaluate_item(item)
            for item in queue_items[:self.max_concurrent]
        ]

        await asyncio.gather(*tasks, return_exceptions=True)

    def _claim_queue_items(self, limit: int) -> List[Dict[str, Any]]:
        """
        Claim pending items from EVAL_QUEUE

        Returns list of queue items with interaction data
        """
        if not self.connection:
            return []

        try:
            cursor = self.connection.cursor(DictCursor)

            # Find pending items
            cursor.execute("""
                SELECT
                    q.queue_id,
                    q.interaction_id,
                    q.eval_run_id,
                    i.user_query,
                    i.answer_text,
                    i.metadata
                FROM EVAL_QUEUE q
                JOIN RAG_INTERACTION i ON q.interaction_id = i.interaction_id
                WHERE q.status = 'pending'
                  AND (q.retry_count < q.max_retries OR q.retry_count IS NULL)
                ORDER BY q.priority ASC, q.queued_at ASC
                LIMIT %s
            """, (limit,))

            items = cursor.fetchall()

            # Claim them
            if items:
                queue_ids = [item['QUEUE_ID'] for item in items]
                placeholders = ','.join(['%s'] * len(queue_ids))

                cursor.execute(f"""
                    UPDATE EVAL_QUEUE
                    SET status = 'claimed',
                        claimed_at = CURRENT_TIMESTAMP(),
                        worker_id = %s
                    WHERE queue_id IN ({placeholders})
                """, [self.worker_id] + queue_ids)

                self.connection.commit()
                logger.info(f"Claimed {len(items)} items")

            cursor.close()
            return items

        except Exception as e:
            logger.error(f"Failed to claim queue items: {e}")
            self.connection.rollback()
            return []

    async def _evaluate_item(self, queue_item: Dict[str, Any]):
        """
        Evaluate a single interaction and store results

        Args:
            queue_item: Dict with queue_id, interaction_id, user_query, answer_text, metadata
        """
        queue_id = queue_item['QUEUE_ID']
        interaction_id = queue_item['INTERACTION_ID']
        eval_run_id = queue_item.get('EVAL_RUN_ID')

        logger.info(f"Evaluating interaction {interaction_id}")

        try:
            # Parse metadata to get retrieved context
            metadata = queue_item.get('METADATA', {})
            if isinstance(metadata, str):
                import json
                metadata = json.loads(metadata)

            # Build retrieved context for evaluators
            retrieved_context = self._build_retrieved_context(metadata)

            # Run evaluation
            eval_results = self.evaluator.evaluate_interaction(
                question=queue_item['USER_QUERY'],
                answer=queue_item['ANSWER_TEXT'],
                retrieved_context=retrieved_context,
                expected_answer=None,  # Not available for production queries
                expected_clause=None   # Not available for production queries
            )

            # Store results
            self._store_eval_results(interaction_id, eval_run_id, eval_results)

            # Mark queue item as completed
            self._complete_queue_item(queue_id, success=True)

            logger.info(f"Successfully evaluated {interaction_id}")

        except Exception as e:
            logger.error(f"Failed to evaluate {interaction_id}: {e}", exc_info=True)
            self._complete_queue_item(queue_id, success=False, error_msg=str(e))

    def _build_retrieved_context(self, metadata: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Extract retrieved context from interaction metadata

        Metadata structure:
        {
            'chunks_metadata': [
                {
                    'content_id': str,
                    'content_type': str,
                    'page_number': int,
                    'similarity': float,
                    'chunk_preview': str
                }
            ],
            'visual_metadata': [...]
        }
        """
        context = []

        # Add text chunks
        chunks_metadata = metadata.get('chunks_metadata', [])
        for chunk in chunks_metadata:
            context.append({
                'content_id': chunk.get('content_id'),
                'content_type': chunk.get('content_type'),
                'page_number': chunk.get('page_number'),
                'similarity': chunk.get('similarity'),
                'text_content': chunk.get('chunk_preview', chunk.get('description', ''))
            })

        # Add visual content
        visual_metadata = metadata.get('visual_metadata', [])
        for visual in visual_metadata:
            context.append({
                'content_id': visual.get('content_id'),
                'content_type': 'visual',
                'page_number': visual.get('page_number'),
                'similarity': visual.get('similarity'),
                'description': visual.get('description', ''),
                'image_url': visual.get('thumbnail_url', '')  # Include the stored presigned URL
            })

        return context

    def _store_eval_results(
        self,
        interaction_id: str,
        eval_run_id: Optional[str],
        eval_results: Dict[str, Any]
    ):
        """Store evaluation results in EVAL_RESULTS table"""
        if not self.connection:
            raise Exception("No database connection")

        try:
            eval_id = str(uuid.uuid4())
            cursor = self.connection.cursor()

            # Extract cited clauses
            import json
            cited_clauses_json = json.dumps(eval_results.get('cited_clauses', []))

            cursor.execute("""
                INSERT INTO EVAL_RESULTS (
                    eval_id,
                    interaction_id,
                    eval_run_id,
                    answer_relevance,
                    answer_completeness,
                    hallucination_score,
                    citation_accuracy,
                    correct_clause_ref,
                    cited_clauses,
                    expected_clause,
                    technical_accuracy,
                    judge_model,
                    judge_prompt_tokens,
                    judge_response_tokens,
                    judge_reasoning,
                    eval_method,
                    eval_version,
                    metadata
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s,
                    PARSE_JSON(%s), %s, %s, %s, %s, %s, %s, %s, %s,
                    PARSE_JSON(%s)
                )
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
                self.evaluator.judge_model,
                eval_results.get('judge_prompt_tokens'),
                eval_results.get('judge_response_tokens'),
                self._build_judge_reasoning(eval_results),
                'llm_judge',
                '1.0',
                json.dumps({
                    'hallucination_details': eval_results.get('hallucination_details'),
                    'citation_details': eval_results.get('citation_details'),
                    'relevance_details': eval_results.get('relevance_details'),
                    'completeness_details': eval_results.get('completeness_details'),
                    'unsupported_claims': eval_results.get('unsupported_claims', [])
                })
            ))

            self.connection.commit()
            cursor.close()
            logger.info(f"Stored eval results: {eval_id}")

        except Exception as e:
            logger.error(f"Failed to store eval results: {e}")
            self.connection.rollback()
            raise

    def _build_judge_reasoning(self, eval_results: Dict[str, Any]) -> str:
        """Combine all reasoning into single string for storage"""
        parts = []

        if eval_results.get('hallucination_details'):
            parts.append(f"Hallucination: {eval_results['hallucination_details']}")

        if eval_results.get('citation_details'):
            parts.append(f"Citations: {eval_results['citation_details']}")

        if eval_results.get('relevance_details'):
            parts.append(f"Relevance: {eval_results['relevance_details']}")

        if eval_results.get('completeness_details'):
            parts.append(f"Completeness: {eval_results['completeness_details']}")

        return " | ".join(parts)

    def _complete_queue_item(
        self,
        queue_id: str,
        success: bool,
        error_msg: Optional[str] = None
    ):
        """Mark queue item as completed or failed"""
        if not self.connection:
            return

        try:
            cursor = self.connection.cursor()

            if success:
                cursor.execute("""
                    UPDATE EVAL_QUEUE
                    SET status = 'completed',
                        completed_at = CURRENT_TIMESTAMP()
                    WHERE queue_id = %s
                """, (queue_id,))
            else:
                # Increment retry count and potentially mark as failed
                cursor.execute("""
                    UPDATE EVAL_QUEUE
                    SET retry_count = retry_count + 1,
                        status = CASE
                            WHEN retry_count + 1 >= max_retries THEN 'failed'
                            ELSE 'pending'
                        END,
                        error_message = %s,
                        claimed_at = NULL,
                        worker_id = NULL
                    WHERE queue_id = %s
                """, (error_msg, queue_id))

            self.connection.commit()
            cursor.close()

        except Exception as e:
            logger.error(f"Failed to complete queue item: {e}")
            self.connection.rollback()


async def main():
    """Main entry point for running eval worker"""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

    # Create and start worker
    worker = EvalWorker(
        batch_size=10,
        poll_interval=5,
        max_concurrent=3
    )

    await worker.start()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Worker interrupted by user")
        sys.exit(0)

"""
Interaction Logger for Sparkie RAG Application
Captures all user interactions to Snowflake RAG_SESSION and RAG_INTERACTION tables
"""

import uuid
import logging
from datetime import datetime, timezone
from typing import Optional, Dict, Any
import json
import asyncio
from functools import wraps

import snowflake.connector
from snowflake.connector import DictCursor
from dotenv import load_dotenv
import os

load_dotenv()

logger = logging.getLogger(__name__)


class InteractionLogger:
    """
    Handles logging of RAG interactions to Snowflake tables.
    Designed for async background operation to minimize user-facing latency.
    """

    def __init__(self):
        self.connection = None
        self.log_queue = asyncio.Queue()
        self._worker_task = None

    def connect(self):
        """Establish Snowflake connection"""
        try:
            # Use snowflake.connector (not Snowpark) for cursor-based operations
            self.connection = snowflake.connector.connect(
                account=os.getenv("SNOWFLAKE_ACCOUNT"),
                user=os.getenv("SNOWFLAKE_USER"),
                private_key=os.getenv("SNOWFLAKE_PRIVATE_KEY"),
                role=os.getenv("SNOWFLAKE_ROLE"),
                warehouse=os.getenv("SNOWFLAKE_WAREHOUSE"),
                database=os.getenv("SNOWFLAKE_DATABASE"),
                schema=os.getenv("SNOWFLAKE_SCHEMA")
            )
            logger.info("InteractionLogger connected to Snowflake")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to Snowflake: {e}")
            print(f"Failed to connect to Snowflake: {e}")
            return False

    def close(self):
        """Close Snowflake connection"""
        if self.connection:
            self.connection.close()
            logger.info("InteractionLogger disconnected from Snowflake")

    async def start_worker(self):
        """Start background worker for async logging"""
        if not self._worker_task:
            self._worker_task = asyncio.create_task(self._process_log_queue())
            logger.info("InteractionLogger background worker started")

    async def stop_worker(self):
        """Stop background worker gracefully"""
        if self._worker_task:
            # Wait for queue to drain
            await self.log_queue.join()
            self._worker_task.cancel()
            try:
                await self._worker_task
            except asyncio.CancelledError:
                pass
            logger.info("InteractionLogger background worker stopped")

    async def _process_log_queue(self):
        """Background worker that processes logging queue"""
        while True:
            try:
                log_item = await self.log_queue.get()
                log_type = log_item.get('type')

                if log_type == 'session':
                    self._insert_session_sync(log_item['data'])
                elif log_type == 'interaction':
                    self._insert_interaction_sync(log_item['data'])

                self.log_queue.task_done()

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error processing log queue: {e}")

    def log_session(
        self,
        session_id: str,
        user_id: Optional[str] = None,
        client_type: Optional[str] = None,
        app_version: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None
    ):
        """
        Queue a session creation log entry (async, non-blocking)

        Args:
            session_id: Unique session identifier
            user_id: Hashed user identifier (optional)
            client_type: 'web', 'mobile', etc.
            app_version: Application version string
            metadata: Additional context as JSON
        """
        data = {
            'session_id': session_id,
            'user_id': user_id,
            'client_type': client_type,
            'app_version': app_version,
            'metadata': json.dumps(metadata) if metadata else None
        }

        # Add to queue for async processing
        try:
            self.log_queue.put_nowait({'type': 'session', 'data': data})
        except Exception as e:
            logger.error(f"Failed to queue session log: {e}")

    def _insert_session_sync(self, data: Dict[str, Any]):
        """Synchronously insert session into Snowflake"""
        if not self.connection:
            if not self.connect():
                return

        try:
            self.session.sql(f"""
                INSERT INTO RAG_SESSION (session_id, user_id, client_type, app_version, metadata)
                SELECT '{data['session_id']}', '{data.get('user_id', '')}', '{data.get('client_type', '')}',
                       '{data.get('app_version', '')}', PARSE_JSON('{data.get('metadata', 'null')}')
            """).collect()
            logger.info(f"Logged session: {data['session_id']}")

        except Exception as e:
            logger.error(f"Failed to insert session: {e}")

    def _compute_kg_summary_metrics(self, metadata: Dict[str, Any]) -> Dict[str, Any]:
        """
        Compute KG summary metrics from retrieved chunks metadata.

        Returns a dict with:
        - retrieved_count_total, retrieved_count_text, retrieved_count_table, retrieved_count_visual
        - retrieved_count_by_kg_class (A/B/C/UNKNOWN counts)
        - avg_similarity, avg_rerank_score
        - pct_c_in_final_set, pct_unknown_in_final_set
        """
        chunks_metadata = metadata.get('chunks_metadata', [])
        visual_metadata = metadata.get('visual_metadata', [])
        all_items = chunks_metadata + visual_metadata

        if not all_items:
            return {}

        # Count by content type
        type_counts = {}
        kg_class_counts = {}
        similarities = []
        rerank_scores = []

        for item in all_items:
            # Content type counts
            content_type = item.get('content_type', 'unknown')
            type_counts[content_type] = type_counts.get(content_type, 0) + 1

            # KG class counts
            kg_class = item.get('kg_class', 'UNKNOWN')
            kg_class_counts[kg_class] = kg_class_counts.get(kg_class, 0) + 1

            # Collect scores
            if 'similarity' in item and item['similarity'] is not None:
                similarities.append(item['similarity'])
            if 'rerank_score' in item and item['rerank_score'] is not None:
                rerank_scores.append(item['rerank_score'])

        total_count = len(all_items)

        summary = {
            'retrieved_count_total': total_count,
            'retrieved_count_text': type_counts.get('text_chunk', 0),
            'retrieved_count_table': type_counts.get('structured_table', 0),
            'retrieved_count_visual': type_counts.get('visual_content', 0),
            'retrieved_count_by_kg_class': kg_class_counts,
            'avg_similarity': sum(similarities) / len(similarities) if similarities else None,
            'avg_rerank_score': sum(rerank_scores) / len(rerank_scores) if rerank_scores else None,
            'pct_c_in_final_set': (kg_class_counts.get('C', 0) / total_count * 100) if total_count > 0 else 0,
            'pct_unknown_in_final_set': (kg_class_counts.get('UNKNOWN', 0) / total_count * 100) if total_count > 0 else 0
        }

        return summary

    def log_interaction(
        self,
        interaction_id: str,
        session_id: str,
        user_query: str,
        sanitized_query: Optional[str] = None,
        query_type: Optional[str] = None,
        model_name: Optional[str] = None,
        answer_text: Optional[str] = None,
        answer_tokens: Optional[int] = None,
        prompt_tokens: Optional[int] = None,
        latency_ms: Optional[float] = None,
        total_cost_usd: Optional[float] = None,
        status: str = 'success',
        eval_run_id: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
        kg_config: Optional[Dict[str, Any]] = None
    ):
        """
        Queue an interaction log entry (async, non-blocking)

        Args:
            interaction_id: Unique interaction identifier
            session_id: Associated session ID
            user_query: Original user question
            sanitized_query: Cleaned/processed query
            query_type: 'COMPLIANCE', 'CALCULATION', 'FACTUAL', etc.
            model_name: LLM model used
            answer_text: Generated response
            answer_tokens: Tokens in response
            prompt_tokens: Tokens in prompt
            latency_ms: Total response time
            total_cost_usd: Estimated cost
            status: 'success', 'error', 'blocked'
            eval_run_id: Associated eval run if applicable
            metadata: Additional context (chunks, similarity scores, KG fields, etc.)
            kg_config: KG reranking configuration (weights, quotas, feature flag)
        """
        # Enrich metadata with KG summary metrics if available
        if metadata:
            kg_summary = self._compute_kg_summary_metrics(metadata)
            metadata['kg_summary'] = kg_summary

            # Add KG config to metadata if provided
            if kg_config:
                metadata['kg_config'] = kg_config

        data = {
            'interaction_id': interaction_id,
            'session_id': session_id,
            'user_query': user_query,
            'sanitized_query': sanitized_query,
            'query_type': query_type,
            'model_name': model_name,
            'answer_text': answer_text,
            'answer_tokens': answer_tokens,
            'prompt_tokens': prompt_tokens,
            'latency_ms': latency_ms,
            'total_cost_usd': total_cost_usd,
            'status': status,
            'eval_run_id': eval_run_id,
            'metadata': json.dumps(metadata) if metadata else None
        }

        # Add to queue for async processing
        try:
            self.log_queue.put_nowait({'type': 'interaction', 'data': data})
        except Exception as e:
            logger.error(f"Failed to queue interaction log: {e}")

    def _insert_interaction_sync(self, data: Dict[str, Any]):
        """Synchronously insert interaction into Snowflake"""
        if not self.connection:
            if not self.connect():
                return

        try:
            cursor = self.connection.cursor()
            cursor.execute("""
                INSERT INTO RAG_INTERACTION (
                    interaction_id, session_id, user_query, sanitized_query,
                    query_type, model_name, answer_text, answer_tokens,
                    prompt_tokens, latency_ms, total_cost_usd, status,
                    eval_run_id, metadata
                )
                SELECT
                    %(interaction_id)s, %(session_id)s, %(user_query)s,
                    %(sanitized_query)s, %(query_type)s, %(model_name)s,
                    %(answer_text)s, %(answer_tokens)s, %(prompt_tokens)s,
                    %(latency_ms)s, %(total_cost_usd)s, %(status)s,
                    %(eval_run_id)s, PARSE_JSON(%(metadata)s)
            """, data)
            self.connection.commit()
            cursor.close()
            logger.info(f"Logged interaction: {data['interaction_id']}")

        except Exception as e:
            logger.error(f"Failed to insert interaction: {e}")
            self.connection.rollback()

    def queue_for_evaluation(self, interaction_id: str, eval_run_id: Optional[str] = None, priority: int = 5):
        """
        Add interaction to EVAL_QUEUE for background evaluation

        Args:
            interaction_id: Interaction to evaluate
            eval_run_id: Optional eval run to associate with
            priority: 1=highest, 10=lowest
        """
        if not self.connection:
            if not self.connect():
                return

        try:
            queue_id = str(uuid.uuid4())
            cursor = self.connection.cursor()
            cursor.execute("""
                INSERT INTO EVAL_QUEUE (
                    queue_id, interaction_id, eval_run_id, priority
                ) VALUES (
                    %s, %s, %s, %s
                )
            """, (queue_id, interaction_id, eval_run_id, priority))
            self.connection.commit()
            cursor.close()
            logger.info(f"Queued interaction {interaction_id} for evaluation")

        except Exception as e:
            logger.error(f"Failed to queue for evaluation: {e}")
            self.connection.rollback()


# Global logger instance
_interaction_logger = None


def get_interaction_logger() -> InteractionLogger:
    """Get or create global interaction logger instance"""
    global _interaction_logger
    if _interaction_logger is None:
        _interaction_logger = InteractionLogger()
        _interaction_logger.connect()
    return _interaction_logger


def log_rag_interaction(func):
    """
    Decorator to automatically log RAG interactions from SparkieEngine.generate_response()

    Usage:
        @log_rag_interaction
        def generate_response(self, raw_question: str, session_id: str, ...):
            ...
    """
    @wraps(func)
    async def async_wrapper(*args, **kwargs):
        # Extract self and parameters
        self = args[0] if args else None
        # Handle both signatures: (self, raw_question, ...) and (self, chat_history, raw_question, ...)
        session_id = kwargs.get('session_id') or (args[3] if len(args) > 3 else None)
        raw_question = kwargs.get('raw_question') or (args[2] if len(args) > 2 else args[1] if len(args) > 1 else None)

        interaction_id = str(uuid.uuid4())
        start_time = datetime.now(timezone.utc)

        try:
            # Call original function
            result = await func(*args, **kwargs) if asyncio.iscoroutinefunction(func) else func(*args, **kwargs)

            # Extract metadata from result
            latency_ms = (datetime.now(timezone.utc) - start_time).total_seconds() * 1000

            # Extract KG configuration from result (if provided by engine)
            kg_config = result.get('kg_config', None)

            # Log interaction
            logger_instance = get_interaction_logger()
            logger_instance.log_interaction(
                interaction_id=interaction_id,
                session_id=session_id,
                user_query=raw_question,
                sanitized_query=result.get('sanitized_query'),
                model_name=result.get('model_name', 'meta-llama/llama-4-maverick-17b-128e-instruct'),
                answer_text=result.get('response'),
                latency_ms=result.get('total_time', 0) * 1000 if 'total_time' in result else latency_ms,
                status='success',
                metadata={
                    'chunks_used': result.get('chunks_used'),
                    'visual_content_count': result.get('visual_content_count'),
                    'retrieval_time': result.get('retrieval_time'),
                    'generation_time': result.get('generation_time'),
                    'chunks_metadata': result.get('chunks_metadata', []),
                    'visual_metadata': result.get('visual_metadata', [])
                },
                kg_config=kg_config
            )

            # Queue for evaluation
            logger_instance.queue_for_evaluation(interaction_id)

            # Add interaction_id to result for downstream tracking
            result['interaction_id'] = interaction_id

            return result

        except Exception as e:
            # Log failed interaction
            logger_instance = get_interaction_logger()
            logger_instance.log_interaction(
                interaction_id=interaction_id,
                session_id=session_id or 'unknown',
                user_query=raw_question or 'unknown',
                status='error',
                latency_ms=(datetime.now(timezone.utc) - start_time).total_seconds() * 1000,
                metadata={'error': str(e)}
            )
            raise

    @wraps(func)
    def sync_wrapper(*args, **kwargs):
        # Same logic for synchronous functions
        self = args[0] if args else None
        # Handle both signatures: (self, raw_question, ...) and (self, chat_history, raw_question, ...)
        session_id = kwargs.get('session_id') or (args[3] if len(args) > 3 else None)
        raw_question = kwargs.get('raw_question') or (args[2] if len(args) > 2 else args[1] if len(args) > 1 else None)

        # Generate session_id if not provided
        if not session_id:
            session_id = f"eval_session_{str(uuid.uuid4())[:8]}"

        interaction_id = str(uuid.uuid4())
        start_time = datetime.now(timezone.utc)

        try:
            result = func(*args, **kwargs)
            latency_ms = (datetime.now(timezone.utc) - start_time).total_seconds() * 1000

            # Extract KG configuration from result (if provided by engine)
            kg_config = result.get('kg_config', None)
            metadata = {
                'chunks_used': result.get('chunks_used'),
                'visual_content_count': result.get('visual_content_count'),
                'retrieval_time': result.get('retrieval_time'),
                'generation_time': result.get('generation_time'),
                'chunks_metadata': result.get('chunks_metadata', []),
                'visual_metadata': result.get('visual_metadata', [])
            }

            # Enrich metadata with KG summary metrics
            logger_instance = get_interaction_logger()
            kg_summary = logger_instance._compute_kg_summary_metrics(metadata)
            metadata['kg_summary'] = kg_summary
            if kg_config:
                metadata['kg_config'] = kg_config

            # For sync code, insert directly (no async queue)
            data = {
                'interaction_id': interaction_id,
                'session_id': session_id,
                'user_query': raw_question,
                'sanitized_query': result.get('sanitized_query'),
                'query_type': None,
                'model_name': result.get('model_name', 'meta-llama/llama-4-maverick-17b-128e-instruct'),
                'answer_text': result.get('response'),
                'answer_tokens': None,
                'prompt_tokens': None,
                'latency_ms': result.get('total_time', 0) * 1000 if 'total_time' in result else latency_ms,
                'total_cost_usd': None,
                'status': 'success',
                'eval_run_id': None,
                'metadata': json.dumps(metadata) if metadata else None
            }
            logger_instance._insert_interaction_sync(data)
            result['interaction_id'] = interaction_id

            return result

        except Exception as e:
            logger_instance = get_interaction_logger()
            logger_instance.log_interaction(
                interaction_id=interaction_id,
                session_id=session_id or 'unknown',
                user_query=raw_question or 'unknown',
                status='error',
                latency_ms=(datetime.now(timezone.utc) - start_time).total_seconds() * 1000,
                metadata={'error': str(e)}
            )
            raise

    # Return appropriate wrapper based on function type
    if asyncio.iscoroutinefunction(func):
        return async_wrapper
    else:
        return sync_wrapper

"""
Sparkie Engine V3 - Clause-Aware AS3000 Electrical Standards Assistant

Key Changes from V2:
1. Query-side semantic expansion (synonyms applied at search time)
2. Clause-aware storage with precise retrieval
3. New SPARKIE_V3_DB.CLAUSE_STORE schema
4. Definitions retrieved as individual chunks
5. Fallback to V2 if V3 not available

Usage:
    engine = SparkieEngineV3()
    response = engine.generate_response(chat_history, question)
"""

import os
import time
import uuid
import re
import json
import logging
from typing import List, Dict, Optional
from groq import Groq
from snowflake.snowpark.context import get_active_session
from snowflake.snowpark import Session
from dotenv import load_dotenv

# Import query expander
from app.query_expander import QueryExpander

# Load environment variables
load_dotenv()

# Constants
MODEL_NAME = 'meta-llama/llama-4-maverick-17b-128e-instruct'
EMBED_MODEL = 'snowflake-arctic-embed-l-v2.0'

# V3 Configuration
USE_V3_SCHEMA = True  # Set to False to fall back to V2
V3_CLAUSE_SEARCH_SERVICE = 'SPARKIE_V3_DB.CLAUSE_STORE.clause_search'  # Clause-only search
V3_UNIFIED_SEARCH_SERVICE = 'SPARKIE_V3_DB.CLAUSE_STORE.unified_search'  # Unified: clauses + visuals
V2_SEARCH_SERVICE = 'ELECTRICAL_STANDARDS_DB.EVALUATION.as3000_search'

# Retrieval settings
TOP_K = 10  # Total results (clauses + visuals combined)
MAX_VISUALS = 3  # Cap on visual content to prevent dilution
DEFINITION_BOOST = 0.1  # Boost for definition chunks when query asks "what is X"


class SparkieEngineV3:
    """
    V3 Sparkie Engine with clause-aware retrieval and query expansion.
    """

    def __init__(self, use_v3: bool = True):
        self.session = None
        self.groq_client = self._get_groq_client()
        self._initialized = False
        self.use_v3 = use_v3 and USE_V3_SCHEMA

        # Initialize query expander
        self.query_expander = QueryExpander()

        # Track which schema we're using
        self.active_schema = None

        logging.info(f"SparkieEngineV3 initialized (V3 schema: {self.use_v3})")

    def _get_groq_client(self):
        """Initialize Groq client."""
        api_key = os.getenv("GROQ_API_KEY")
        if not api_key:
            logging.warning("Groq API key not found.")
            return None
        return Groq(api_key=api_key)

    def _get_session(self):
        """Create and return Snowflake session."""
        try:
            return get_active_session()
        except:
            connection_parameters = {
                "account": os.getenv("SNOWFLAKE_ACCOUNT"),
                "user": os.getenv("SNOWFLAKE_USER"),
                "authenticator": os.getenv("SNOWFLAKE_AUTHENTICATOR"),
                "private_key": os.getenv("SNOWFLAKE_PRIVATE_KEY"),
                "role": "ACCOUNTADMIN",
                "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE"),
                "database": "SPARKIE_V3_DB" if self.use_v3 else os.getenv("SNOWFLAKE_DATABASE"),
                "schema": "CLAUSE_STORE" if self.use_v3 else os.getenv("SNOWFLAKE_SCHEMA")
            }
            return Session.builder.configs(connection_parameters).create()

    def _validate_session(self):
        """Check if Snowflake session is still valid."""
        if self.session is None:
            return False
        try:
            self.session.sql("SELECT 1").collect()
            return True
        except Exception as e:
            logging.warning(f"Session validation failed: {e}")
            return False

    def _ensure_initialized(self):
        """Lazy initialization with V3/V2 fallback."""
        if not self._initialized:
            try:
                self.session = self._get_session()
                self.session.sql("USE WAREHOUSE CORTEX_SEARCH_WH").collect()

                # Check if V3 schema exists
                if self.use_v3:
                    try:
                        self.session.sql("USE DATABASE SPARKIE_V3_DB").collect()
                        self.session.sql("USE SCHEMA CLAUSE_STORE").collect()
                        self.active_schema = 'V3'
                        logging.info("Using V3 schema (SPARKIE_V3_DB.CLAUSE_STORE)")
                    except Exception as e:
                        logging.warning(f"V3 schema not available, falling back to V2: {e}")
                        self.use_v3 = False
                        self.active_schema = 'V2'
                else:
                    self.active_schema = 'V2'

                self._initialized = True
                logging.info(f"SparkieEngineV3 initialized with {self.active_schema} schema")

            except Exception as e:
                logging.error(f"Initialization failed: {e}")
                raise

        elif not self._validate_session():
            logging.info("Session expired, reconnecting...")
            self._initialized = False
            self._ensure_initialized()

    def _detect_query_type(self, query: str) -> Dict:
        """
        Detect query type for optimized retrieval.

        Returns:
            Dict with query_type and metadata
        """
        query_lower = query.lower()

        # Definition query detection
        definition_patterns = [
            r'what is (?:a |an |the )?(.+?)(?:\?|$)',
            r'define (.+?)(?:\?|$)',
            r'definition of (.+?)(?:\?|$)',
            r'what does (.+?) mean',
        ]

        for pattern in definition_patterns:
            match = re.search(pattern, query_lower)
            if match:
                term = match.group(1).strip()
                return {
                    'query_type': 'definition',
                    'term': term,
                    'boost_definitions': True
                }

        # "What changed" query detection
        change_patterns = [
            r'what (?:has )?changed',
            r'what(?:\'s| is) new',
            r'new requirements?',
            r'amendments?',
            r'updates? (?:to|in)',
        ]

        for pattern in change_patterns:
            if re.search(pattern, query_lower):
                return {
                    'query_type': 'amendment',
                    'filter_amendments': True
                }

        # Table query detection
        if re.search(r'table \d+', query_lower):
            return {
                'query_type': 'table',
                'boost_tables': True
            }

        # Default
        return {
            'query_type': 'general'
        }

    def retrieve_content(self, query: str, limit: int = TOP_K) -> List[Dict]:
        """
        Retrieve content using query expansion and clause-aware search.

        Steps:
        1. Detect query type
        2. Expand query with synonyms
        3. Search via Cortex Search
        4. Apply type-specific boosting
        """
        self._ensure_initialized()

        if not self.session:
            logging.error("No session available")
            return []

        # Step 1: Detect query type
        query_info = self._detect_query_type(query)
        logging.info(f"Query type detected: {query_info['query_type']}")

        # Step 2: Expand query with synonyms
        expansion_result = self.query_expander.expand_with_metadata(query)
        expanded_query = expansion_result['expanded_query']

        if expansion_result['matched_terms']:
            logging.info(f"Query expanded with: {expansion_result['matched_terms']}")

        # Step 2b: For definition queries, also search with simplified query
        # Long natural language queries perform worse for definition retrieval
        if query_info.get('query_type') == 'definition' and query_info.get('term'):
            term = query_info['term']
            # Use both the original query AND a simplified definition query
            expanded_query = f"{term} definition {expanded_query}"
            logging.info(f"Definition query optimization: added '{term} definition'")

        # Step 2c: For scope/application queries, add key terms
        scope_patterns = [
            r'where (?:does|can|is|are).*(?:standard|AS/?NZS).*(?:appl|used)',
            r'(?:areas?|scope).*(?:standard|AS/?NZS).*(?:appl|used)',
            r'application.*(?:standard|AS/?NZS)',
        ]
        for pattern in scope_patterns:
            if re.search(pattern, query.lower()):
                expanded_query = f"application standard premises {expanded_query}"
                logging.info(f"Scope query optimization: added 'application standard premises'")
                break

        # Step 3: Search via Cortex Search
        if self.use_v3 and self.active_schema == 'V3':
            results = self._search_v3(expanded_query, limit, query_info)
        else:
            results = self._search_v2(expanded_query, limit)

        logging.info(f"Retrieved {len(results)} results")
        return results

    def _search_v3(self, query: str, limit: int, query_info: Dict) -> List[Dict]:
        """
        Search using V3 clause_search + optional visual search.

        Strategy:
        1. Search clause_search service (includes clauses AND tables with HTML)
        2. Optionally search unified_search for visuals (capped at MAX_VISUALS)
        3. Combine results up to TOP_K
        """
        try:
            # Step 1: Search clause_search (includes tables now)
            clause_results = self._search_clause_content(query, limit, query_info)
            logging.info(f"Clause search returned {len(clause_results)} results")

            # Step 2: Search for visuals (capped at MAX_VISUALS)
            visual_results = self._search_visual_content(query, MAX_VISUALS)
            logging.info(f"Visual search returned {len(visual_results)} results")

            # Step 3: Combine - clauses/tables first, then visuals
            remaining_slots = limit - len(visual_results)
            capped_clauses = clause_results[:remaining_slots]

            results = capped_clauses + visual_results
            results.sort(key=lambda x: x.get('score', 0), reverse=True)

            logging.info(f"Combined: {len(capped_clauses)} clauses/tables + {len(visual_results)} visuals = {len(results)} total")

            # Boost definitions if query is asking "what is X"
            if query_info.get('boost_definitions'):
                term_to_find = query_info.get('term', '').lower()
                for r in results:
                    if r.get('clause_type') == 'definition':
                        if r.get('term') and term_to_find in r['term'].lower():
                            r['score'] = r.get('score', 0) + DEFINITION_BOOST

                # Re-sort by score
                results.sort(key=lambda x: x.get('score', 0), reverse=True)

            return results

        except Exception as e:
            logging.error(f"V3 search failed: {e}")
            return []

    def _search_clause_content(self, query: str, limit: int, query_info: Dict) -> List[Dict]:
        """Search clause_search service (reliable clause retrieval)."""
        try:
            search_config = {
                "query": query,
                "columns": [
                    "clause_id", "clause_type", "clause_number", "term",
                    "table_number", "page_number", "section_number",
                    "is_normative", "is_amendment", "content", "title"
                ],
                "limit": limit
            }

            # Add filter for amendment queries
            if query_info.get('filter_amendments'):
                search_config["filter"] = {"@eq": {"is_amendment": True}}

            search_config_json = json.dumps(search_config)

            search_sql = f"""
            SELECT
                PARSE_JSON(
                    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                        '{V3_CLAUSE_SEARCH_SERVICE}',
                        ?
                    )
                ):"results" AS search_results
            """

            result = self.session.sql(search_sql, [search_config_json]).collect()

            if not result or not result[0]['SEARCH_RESULTS']:
                return []

            search_results = json.loads(result[0]['SEARCH_RESULTS'])

            results = []
            for item in search_results:
                results.append({
                    'clause_id': item.get('clause_id'),
                    'clause_type': item.get('clause_type'),
                    'clause_number': item.get('clause_number'),
                    'term': item.get('term'),
                    'content': item.get('content'),
                    'table_number': item.get('table_number'),
                    'figure_number': None,
                    'page_number': item.get('page_number'),
                    'section_number': item.get('section_number'),
                    'is_normative': item.get('is_normative'),
                    'is_amendment': item.get('is_amendment'),
                    'source': 'clause',
                    'is_visual': False,
                    'image_url': None,
                    'score': item.get('@scores', {}).get('reranker_score', 0)
                })

            return results

        except Exception as e:
            logging.error(f"Clause search failed: {e}")
            return []

    def _search_visual_content(self, query: str, limit: int) -> List[Dict]:
        """Search for visual content from unified_search with source=visual filter."""
        try:
            search_config = {
                "query": query,
                "columns": [
                    "content_id", "content_type", "figure_number",
                    "table_number_visual", "page_number", "section_number",
                    "pre_signed_url"
                ],
                "filter": {"@eq": {"source": "visual"}},
                "limit": limit
            }

            search_config_json = json.dumps(search_config)

            search_sql = f"""
            SELECT
                PARSE_JSON(
                    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                        '{V3_UNIFIED_SEARCH_SERVICE}',
                        ?
                    )
                ):"results" AS search_results
            """

            result = self.session.sql(search_sql, [search_config_json]).collect()

            if not result or not result[0]['SEARCH_RESULTS']:
                return []

            search_results = json.loads(result[0]['SEARCH_RESULTS'])

            results = []
            for item in search_results:
                results.append({
                    'clause_id': item.get('content_id'),
                    'clause_type': item.get('content_type'),
                    'clause_number': None,
                    'term': None,
                    'content': item.get('content'),
                    'table_number': item.get('table_number_visual'),
                    'figure_number': item.get('figure_number'),
                    'page_number': item.get('page_number'),
                    'section_number': item.get('section_number'),
                    'is_normative': None,
                    'is_amendment': None,
                    'source': 'visual',
                    'is_visual': True,
                    'image_url': item.get('pre_signed_url'),
                    'score': item.get('@scores', {}).get('reranker_score', 0) - 0.5  # Penalty vs clauses
                })

            return results

        except Exception as e:
            logging.error(f"Visual search failed: {e}")
            return []

    def _search_v2(self, query: str, limit: int) -> List[Dict]:
        """Fallback search using V2 schema."""
        try:
            search_config = {
                "query": query,
                "columns": ["content_id", "content_type", "label", "content"],
                "limit": limit
            }
            search_config_json = json.dumps(search_config)

            search_sql = f"""
            SELECT
                PARSE_JSON(
                    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                        '{V2_SEARCH_SERVICE}',
                        ?
                    )
                ):"results" AS search_results
            """

            result = self.session.sql(search_sql, [search_config_json]).collect()

            if not result or not result[0]['SEARCH_RESULTS']:
                return []

            search_results = json.loads(result[0]['SEARCH_RESULTS'])

            # Convert to compatible format
            results = []
            for item in search_results:
                results.append({
                    'clause_id': item.get('content_id'),
                    'clause_type': item.get('content_type'),
                    'content': item.get('content'),
                    'title': item.get('label'),
                    'score': item.get('score', 0)
                })

            return results

        except Exception as e:
            logging.error(f"V2 search failed: {e}")
            return []

    def _fetch_full_content(self, clause_ids: List[str]) -> Dict[str, Dict]:
        """
        Fetch full content for clauses including TABLE_HTML and IMAGE_URL.
        """
        if not clause_ids:
            return {}

        try:
            ids_str = ','.join([f"'{cid}'" for cid in clause_ids])

            if self.use_v3:
                query = f"""
                SELECT
                    CLAUSE_ID,
                    CONTENT,
                    TABLE_HTML,
                    IMAGE_URL,
                    THUMBNAIL_URL
                FROM SPARKIE_V3_DB.CLAUSE_STORE.CLAUSES
                WHERE CLAUSE_ID IN ({ids_str})
                """
            else:
                query = f"""
                SELECT
                    CHUNK_ID as CLAUSE_ID,
                    CHUNK as CONTENT,
                    TABLE_HTML,
                    NULL as IMAGE_URL,
                    NULL as THUMBNAIL_URL
                FROM ELECTRICAL_STANDARDS_DB.AS_STANDARDS.RAW_TEXT
                WHERE CHUNK_ID IN ({ids_str})
                """

            results = self.session.sql(query).collect()

            content_map = {}
            for row in results:
                # Convert Row to dict for easier access
                row_dict = row.asDict()
                content_map[row_dict['CLAUSE_ID']] = {
                    'content': row_dict.get('CONTENT'),
                    'table_html': row_dict.get('TABLE_HTML'),
                    'image_url': row_dict.get('IMAGE_URL'),
                    'thumbnail_url': row_dict.get('THUMBNAIL_URL')
                }

            return content_map

        except Exception as e:
            logging.error(f"Failed to fetch full content: {e}")
            return {}

    def generate_response(self, chat_history: List[Dict], question: str) -> Dict:
        """
        Generate response using clause-aware retrieval.

        Returns:
            Dict with response, retrieved content, timing metrics
        """
        start_time = time.time()

        # Retrieve relevant content
        retrieval_start = time.time()
        results = self.retrieve_content(question)
        retrieval_time = time.time() - retrieval_start

        if not results:
            return {
                'response': "I couldn't find relevant information in the AS3000 standards. Please try rephrasing your question.",
                'chunks_metadata': [],
                'retrieval_time': retrieval_time,
                'generation_time': 0
            }

        # Fetch full content for clause results (not visuals - they have content already)
        clause_ids = [r['clause_id'] for r in results if r.get('clause_id') and not r.get('is_visual')]
        full_content = self._fetch_full_content(clause_ids)

        # Build context for LLM
        context_parts = []
        chunks_metadata = []
        visual_metadata = []

        for i, result in enumerate(results[:TOP_K]):  # Limit to TOP_K for context
            clause_id = result.get('clause_id', '')
            clause_type = result.get('clause_type', '')
            is_visual = result.get('is_visual', False)

            # For visuals, content comes directly from search; for clauses, fetch full content
            if is_visual:
                content = result.get('content') or ''
                image_url = result.get('image_url')
            else:
                full = full_content.get(clause_id, {})
                content = full.get('content') or result.get('content') or ''
                image_url = None

            # Format based on type
            if clause_type == 'definition':
                term = result.get('term', '')
                context_parts.append(f"[Definition - {term} ({clause_id})]\n{content}")
            elif is_visual and result.get('figure_number'):
                fig_num = result.get('figure_number', '')
                context_parts.append(f"[Figure {fig_num}]\n{content}")
                if image_url:
                    context_parts.append(f"Image URL: {image_url}")
            elif is_visual and result.get('table_number'):
                table_num = result.get('table_number', '')
                context_parts.append(f"[Visual Table {table_num}]\n{content}")
            elif clause_type == 'table':
                table_num = result.get('table_number', '')
                context_parts.append(f"[Table {table_num}]\n{content}")
            else:
                clause_num = result.get('clause_number', clause_id)
                context_parts.append(f"[Clause {clause_num}]\n{content}")

            # Store metadata for eval - separate visuals from chunks
            metadata_entry = {
                'content_id': clause_id,
                'content_type': clause_type,
                'text_content': (content or '')[:500],
                'page_number': result.get('page_number'),
                'clause_number': result.get('clause_number'),
                'figure_number': result.get('figure_number'),
                'term': result.get('term'),
                'is_normative': result.get('is_normative'),
                'is_amendment': result.get('is_amendment'),
                'source': result.get('source')
            }

            if is_visual:
                metadata_entry['thumbnail_url'] = image_url
                metadata_entry['image_url'] = image_url
                visual_metadata.append(metadata_entry)
            else:
                chunks_metadata.append(metadata_entry)

        context = "\n\n".join(context_parts)

        # Generate response with LLM
        generation_start = time.time()
        response_text = self._generate_llm_response(question, context, chat_history)
        generation_time = time.time() - generation_start

        total_time = time.time() - start_time

        return {
            'response': response_text,
            'chunks_metadata': chunks_metadata,
            'visual_metadata': visual_metadata,
            'retrieval_time': retrieval_time,
            'generation_time': generation_time,
            'total_time': total_time,
            'schema_version': self.active_schema,
            'query_expanded': self.query_expander.expand(question) != question
        }

    def _generate_llm_response(self, question: str, context: str, chat_history: List[Dict]) -> str:
        """Generate response using Groq LLM."""
        if not self.groq_client:
            return "LLM client not available."

        system_prompt = """You are Sparkie, an expert assistant for Australian electricians working with AS/NZS 3000:2018 (Wiring Rules).

CRITICAL RULE: When the context contains multiple values that could answer the question, you MUST present ALL of them. NEVER choose one. The user needs to see all options to determine which applies to their situation.

Approach:
1. Scan ALL tables/clauses in context for values relevant to the question
2. If you find 2+ relevant values from different sources, list ALL of them
3. Only give a single answer if truly only one value exists in context

Format:
- List each value with its source (e.g., "X per Table A" and "Y per Table B")
- Be concise - no essays
- If context lacks the answer, say so"""

        messages = [
            {"role": "system", "content": system_prompt}
        ]

        # Add chat history (last 4 exchanges)
        for msg in chat_history[-8:]:
            role = msg.get('role', 'user')
            content = msg.get('content', '')
            if role in ['user', 'assistant'] and content:
                messages.append({"role": role, "content": content})

        # Add current question with context
        user_message = f"""Context from AS3000:
{context}

Question: {question}

Please provide a clear, accurate answer based on the AS3000 context above. Cite specific clause numbers."""

        messages.append({"role": "user", "content": user_message})

        try:
            response = self.groq_client.chat.completions.create(
                model=MODEL_NAME,
                messages=messages,
                temperature=0.1,
                max_tokens=1500
            )
            return response.choices[0].message.content.strip()

        except Exception as e:
            logging.error(f"LLM generation failed: {e}")
            return f"I encountered an error generating a response: {str(e)}"

    def close(self):
        """Close Snowflake session."""
        if self.session:
            try:
                self.session.close()
                logging.info("Session closed")
            except:
                pass


# Convenience function for quick testing
def ask(question: str) -> str:
    """Quick function to ask a question."""
    engine = SparkieEngineV3()
    result = engine.generate_response([], question)
    engine.close()
    return result['response']


if __name__ == "__main__":
    # Quick test
    import sys

    if len(sys.argv) > 1:
        question = " ".join(sys.argv[1:])
    else:
        question = "What is the definition of an alteration?"

    print(f"\nQuestion: {question}")
    print("-" * 60)

    engine = SparkieEngineV3()
    result = engine.generate_response([], question)

    print(f"\nResponse:\n{result['response']}")
    print(f"\n--- Metadata ---")
    print(f"Schema: {result.get('schema_version')}")
    print(f"Retrieval time: {result.get('retrieval_time', 0):.2f}s")
    print(f"Generation time: {result.get('generation_time', 0):.2f}s")
    print(f"Query expanded: {result.get('query_expanded')}")
    print(f"Chunks retrieved: {len(result.get('chunks_metadata', []))}")

    engine.close()

"""
Sparkie Engine - AS3000 Electrical Standards Assistant
Simple RAG engine for Australian electricians
"""

import os
import time
import uuid
import re
import base64
import json
from datetime import datetime
import logging
from typing import List, Dict, Optional
from groq import Groq
from snowflake.snowpark.context import get_active_session
from snowflake.snowpark import Session
from dotenv import load_dotenv

# Import evaluation framework
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from evaluation.interaction_logger import log_rag_interaction

# Load environment variables
load_dotenv()

# Constants
MODEL_NAME = 'meta-llama/llama-4-maverick-17b-128e-instruct'
FALLBACK_MODEL = 'MIXTRAL-8X7B'
EMBED_MODEL = 'snowflake-arctic-embed-l-v2.0'
EMBED_FN = 'SNOWFLAKE.CORTEX.EMBED_TEXT_1024'
TOP_K = 5  # Top relevant chunks for AS3000
SIMILARITY_THRESHOLD = 0.05  # Much lower threshold for better coverage

# ========== KG RERANKING CONFIGURATION ==========
# Feature flag to enable/disable KG reranking
USE_KG_RERANK = False

# Initial candidate set size (before reranking)
# Reduced from 40 to 30 for cost optimization (-25% vector compute)
KG_CANDIDATE_SET_SIZE = 30

# Final result set size (after reranking and quota selection)
KG_FINAL_K = 20

# KG boost/penalty weights for text chunks
# A = normative, unconditional → strong positive boost
KG_BOOST_A = 0.15
# B = normative, conditional → mild positive boost
KG_BOOST_B = 0.05
# C = non-normative → negative penalty (down-rank)
KG_PENALTY_C = -0.10
# UNKNOWN = not eligible for KG (tables/visuals) → neutral (no change)
KG_NEUTRAL_UNKNOWN = 0.0

# Quota constraints for final selection
# Minimum normative text items (A or B) to include if available
MIN_NORMATIVE_TEXT = 4
# Maximum non-normative text items (C) to include
MAX_NON_NORMATIVE_TEXT = 2
# Minimum non-text items (structured_table or visual_content with UNKNOWN) to include if available
MIN_UNKNOWN_NONTEXT = 2

# Debug logging for KG reranking
KG_DEBUG_LOGGING = True
# ================================================

class SparkieEngine:
    """Simple chat engine for AS3000 electrical standards assistance."""
    
    def __init__(self):
        self.session = None
        self.groq_client = self._get_groq_client()
        self._initialized = False
    
    def _validate_session(self):
        """Check if Snowflake session is still valid."""
        if self.session is None:
            return False
        try:
            # Simple query to test if session is alive
            self.session.sql("SELECT 1").collect()
            return True
        except Exception as e:
            error_msg = str(e)
            if "Authentication token has expired" in error_msg or "390114" in error_msg:
                logging.warning(f"Session expired, will reconnect: {error_msg}")
                return False
            # Other errors might be transient, so we'll try to continue
            logging.error(f"Session validation error: {e}")
            return False

    def _ensure_initialized(self):
        """Lazy initialization of Snowflake connection with session validation."""
        # First time initialization
        if not self._initialized:
            try:
                self.session = self._get_session()
                self._optimize_warehouse()
                self._initialized = True
                logging.info("Sparkie engine initialized successfully")
            except Exception as e:
                logging.error(f"Snowflake connection failed: {e}")
                self._initialized = True
        # Session renewal if expired
        elif not self._validate_session():
            logging.info("Session invalid, reconnecting...")
            try:
                if self.session:
                    try:
                        self.session.close()
                    except:
                        pass
                self.session = self._get_session()
                self._optimize_warehouse()
                logging.info("Session renewed successfully")
            except Exception as e:
                logging.error(f"Session renewal failed: {e}")
                raise
    
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
                "role": "ACCOUNTADMIN",  # Use ACCOUNTADMIN for Cortex Search access
                "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE"),
                "database": os.getenv("SNOWFLAKE_DATABASE"),
                "schema": os.getenv("SNOWFLAKE_SCHEMA")
            }
            return Session.builder.configs(connection_parameters).create()
    
    def _get_groq_client(self):
        """Initialize Groq client."""
        api_key = os.getenv("GROQ_API_KEY")
        if not api_key:
            logging.warning("Groq API key not found.")
            return None
        return Groq(api_key=api_key)
    
    def _optimize_warehouse(self):
        """Set warehouse for electrical RAG operations."""
        try:
            self.session.sql("USE WAREHOUSE ELECTRICAL_RAG_WH").collect()
            self.session.sql("ALTER SESSION SET USE_CACHED_RESULT = TRUE").collect()
            self.session.sql("ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = 300").collect()
            logging.info("Using ELECTRICAL_RAG_WH warehouse")
        except Exception as e:
            logging.error(f"Warehouse optimization failed: {e}")

    def enrich_electrician_question(self, raw_question: str, chat_history: list) -> str:
        """Enrich question with AS3000/electrical context."""
        # Add AS3000 context to help with retrieval
        enriched = f"AS3000 electrical standards query: {raw_question.strip()}"
        
        # Add context from recent conversation if this looks like a follow-up
        if len(chat_history) > 1:
            raw_lower = raw_question.lower()
            followup_patterns = [
                'what about', 'and', 'also', 'additionally', 'furthermore',
                'it', 'this', 'that', 'them', 'those', 'same'
            ]
            
            is_followup = any(pattern in raw_lower for pattern in followup_patterns)
            
            if is_followup and len(chat_history) >= 2:
                last_message = chat_history[-1].get('content', '')
                if len(last_message) > 30:
                    context_preview = last_message[:80].replace('\n', ' ').strip()
                    enriched += f" (Context: {context_preview}...)"
        
        return enriched

    def extract_references_from_chunks(self, text_chunks):
        """Extract table/figure references from retrieved text chunks."""
        references = set()

        # Common AS3000 reference patterns
        patterns = [
            r'[Tt]able\s+\d+(?:\.\d+)?',      # Table 8.2, table 3.1
            r'[Ff]igure\s+\d+(?:\.\d+)?',     # Figure 3.4, figure 2.1
            r'[Aa]ppendix\s+[A-Z]',           # Appendix A, appendix B
            r'[Cc]lause\s+\d+(?:\.\d+)*',     # Clause 2.3.1, clause 5
            r'[Ss]ection\s+\d+(?:\.\d+)*'     # Section 3, section 2.1
        ]

        for chunk in text_chunks:
            chunk_text = chunk.get('CHUNK', '') if isinstance(chunk, dict) else getattr(chunk, 'CHUNK', '')
            if chunk_text:
                for pattern in patterns:
                    matches = re.findall(pattern, chunk_text, re.IGNORECASE)
                    for match in matches:
                        references.add(match.strip())

        logging.info(f"Extracted references: {list(references)}")
        return list(references)

    def _kg_rerank_candidates(self, candidates: List) -> List:
        """
        Apply KG-based reranking to candidates using modality-aware scoring.

        KG Reranking Policy:
        - For text_chunk with KG_CLASS = 'A': Apply strong positive boost (normative, unconditional)
        - For text_chunk with KG_CLASS = 'B': Apply mild positive boost (normative, conditional)
        - For text_chunk with KG_CLASS = 'C': Apply negative penalty (non-normative, down-rank)
        - For structured_table or visual_content (KG_CLASS = UNKNOWN): Neutral (no penalty)

        IMPORTANT: UNKNOWN is not treated as non-normative. Tables and visuals are KG-ineligible
        but remain fully eligible for retrieval with no penalty applied.

        Args:
            candidates: List of candidate results from vector search

        Returns:
            Reranked list sorted by final score (similarity + kg_boost)
        """
        if not candidates:
            return []

        reranked = []

        for candidate in candidates:
            content_type = getattr(candidate, 'CONTENT_TYPE', '')
            kg_class = getattr(candidate, 'KG_CLASS', 'UNKNOWN')
            similarity = getattr(candidate, 'SIMILARITY', 0.0)

            # Determine KG boost/penalty based on content type and KG class
            kg_boost = 0.0

            if content_type == 'text_chunk':
                # Text chunks have KG classification
                if kg_class == 'A':
                    # Normative, unconditional → strong positive boost
                    kg_boost = KG_BOOST_A
                elif kg_class == 'B':
                    # Normative, conditional → mild positive boost
                    kg_boost = KG_BOOST_B
                elif kg_class == 'C':
                    # Non-normative → negative penalty (down-rank)
                    kg_boost = KG_PENALTY_C
                else:
                    # UNKNOWN for text (shouldn't happen, but treat as neutral)
                    kg_boost = KG_NEUTRAL_UNKNOWN
            else:
                # structured_table or visual_content → UNKNOWN is expected and neutral
                # These are KG-ineligible but remain fully eligible for retrieval
                # NO PENALTY: We must never treat UNKNOWN as non-normative
                kg_boost = KG_NEUTRAL_UNKNOWN

            # Calculate final reranked score
            rerank_score = similarity + kg_boost

            # Store both original similarity and reranked score
            # Create new object with additional rerank_score attribute
            reranked_obj = type('obj', (object,), {
                'CONTENT_ID': getattr(candidate, 'CONTENT_ID', ''),
                'CONTENT_TYPE': content_type,
                'TEXT_CONTENT': getattr(candidate, 'TEXT_CONTENT', ''),
                'VISUAL_URL': getattr(candidate, 'VISUAL_URL', None),
                'SEARCH_ID': getattr(candidate, 'SEARCH_ID', ''),
                'LABEL': getattr(candidate, 'LABEL', ''),
                'PAGE_NUMBER': getattr(candidate, 'PAGE_NUMBER', None),
                'SECTION_NAME': getattr(candidate, 'SECTION_NAME', None),
                'TABLE_NUMBER': getattr(candidate, 'TABLE_NUMBER', None),
                'TABLE_HTML': getattr(candidate, 'TABLE_HTML', None),
                'SIMILARITY': similarity,
                'RANK': getattr(candidate, 'RANK', 0),
                'KG_CLASS': kg_class,
                'REQUIREMENT_COUNT': getattr(candidate, 'REQUIREMENT_COUNT', None),
                'CONDITION_COUNT': getattr(candidate, 'CONDITION_COUNT', None),
                'NORMATIVE_CONFIDENCE_MAX': getattr(candidate, 'NORMATIVE_CONFIDENCE_MAX', None),
                'CONDITION_CONFIDENCE_MAX': getattr(candidate, 'CONDITION_CONFIDENCE_MAX', None),
                'RERANK_SCORE': rerank_score,
                'KG_BOOST': kg_boost
            })()

            reranked.append(reranked_obj)

        # Sort by reranked score (descending)
        reranked.sort(key=lambda x: getattr(x, 'RERANK_SCORE', 0), reverse=True)

        # Update RANK based on new order
        for i, item in enumerate(reranked):
            item.RANK = i + 1

        return reranked

    def _apply_quota_selection(self, reranked_candidates: List) -> List:
        """
        Apply quota-based selection to ensure appropriate mix of content types.

        Quota Policy:
        - Ensure at least MIN_NORMATIVE_TEXT normative text items (A or B) if available
        - Allow up to MAX_NON_NORMATIVE_TEXT non-normative text items (C)
        - Ensure at least MIN_UNKNOWN_NONTEXT non-text items (tables/visuals with UNKNOWN)
        - Fill remaining slots with best remaining candidates by score

        Args:
            reranked_candidates: Reranked list sorted by final score

        Returns:
            Final selection list of size KG_FINAL_K (or less if not enough candidates)
        """
        if not reranked_candidates:
            return []

        # Categorize candidates
        normative_text = []  # A or B text chunks
        non_normative_text = []  # C text chunks
        unknown_nontext = []  # structured_table or visual_content (UNKNOWN)

        for candidate in reranked_candidates:
            content_type = getattr(candidate, 'CONTENT_TYPE', '')
            kg_class = getattr(candidate, 'KG_CLASS', 'UNKNOWN')

            if content_type == 'text_chunk':
                if kg_class in ['A', 'B']:
                    normative_text.append(candidate)
                elif kg_class == 'C':
                    non_normative_text.append(candidate)
                else:
                    # Text with UNKNOWN class (shouldn't happen, but treat as normative)
                    normative_text.append(candidate)
            else:
                # structured_table or visual_content
                unknown_nontext.append(candidate)

        final_selection = []

        # Step 1: Add minimum normative text (A or B)
        normative_to_add = min(MIN_NORMATIVE_TEXT, len(normative_text))
        final_selection.extend(normative_text[:normative_to_add])

        # Step 2: Add minimum unknown non-text (tables/visuals)
        unknown_to_add = min(MIN_UNKNOWN_NONTEXT, len(unknown_nontext))
        final_selection.extend(unknown_nontext[:unknown_to_add])

        # Step 3: Fill remaining slots
        remaining_slots = KG_FINAL_K - len(final_selection)

        if remaining_slots > 0:
            # Combine remaining candidates
            remaining_candidates = (
                normative_text[normative_to_add:] +
                unknown_nontext[unknown_to_add:] +
                non_normative_text[:MAX_NON_NORMATIVE_TEXT]  # Cap C items
            )

            # Sort remaining by rerank score
            remaining_candidates.sort(key=lambda x: getattr(x, 'RERANK_SCORE', 0), reverse=True)

            # Add best remaining candidates
            final_selection.extend(remaining_candidates[:remaining_slots])

        # Final sort by rerank score to maintain ranking
        final_selection.sort(key=lambda x: getattr(x, 'RERANK_SCORE', 0), reverse=True)

        # Update RANK
        for i, item in enumerate(final_selection):
            item.RANK = i + 1

        return final_selection

    def _log_kg_rerank_debug(self, candidates: List, reranked: List, final: List):
        """
        Log debug information about KG reranking process.

        Shows top 20 candidates before/after rerank with:
        - content_id, content_type, kg_class, similarity, rerank_score
        """
        if not KG_DEBUG_LOGGING:
            return

        logging.info("\n" + "="*80)
        logging.info("KG RERANKING DEBUG - TOP 20 CANDIDATES")
        logging.info("="*80)

        # Before reranking
        logging.info("\nBEFORE RERANK (sorted by similarity):")
        logging.info(f"{'Rank':<6}{'Content ID':<25}{'Type':<20}{'KG Class':<12}{'Sim Score':<12}")
        logging.info("-" * 75)

        for i, c in enumerate(candidates[:20], 1):
            content_id = getattr(c, 'CONTENT_ID', '')[:22]
            content_type = getattr(c, 'CONTENT_TYPE', '')[:17]
            kg_class = getattr(c, 'KG_CLASS', 'UNKNOWN')
            similarity = getattr(c, 'SIMILARITY', 0.0)
            logging.info(f"{i:<6}{content_id:<25}{content_type:<20}{kg_class:<12}{similarity:<12.4f}")

        # After reranking
        logging.info("\nAFTER RERANK (sorted by rerank_score):")
        logging.info(f"{'Rank':<6}{'Content ID':<25}{'Type':<20}{'KG Class':<12}{'Sim':<10}{'Boost':<10}{'Rerank':<10}")
        logging.info("-" * 95)

        for i, r in enumerate(reranked[:20], 1):
            content_id = getattr(r, 'CONTENT_ID', '')[:22]
            content_type = getattr(r, 'CONTENT_TYPE', '')[:17]
            kg_class = getattr(r, 'KG_CLASS', 'UNKNOWN')
            similarity = getattr(r, 'SIMILARITY', 0.0)
            kg_boost = getattr(r, 'KG_BOOST', 0.0)
            rerank_score = getattr(r, 'RERANK_SCORE', 0.0)
            logging.info(f"{i:<6}{content_id:<25}{content_type:<20}{kg_class:<12}{similarity:<10.4f}{kg_boost:<10.4f}{rerank_score:<10.4f}")

        # Final selection
        logging.info("\nFINAL SELECTION (after quota constraints):")
        logging.info(f"{'Rank':<6}{'Content ID':<25}{'Type':<20}{'KG Class':<12}{'Rerank':<10}")
        logging.info("-" * 75)

        for i, f in enumerate(final, 1):
            content_id = getattr(f, 'CONTENT_ID', '')[:22]
            content_type = getattr(f, 'CONTENT_TYPE', '')[:17]
            kg_class = getattr(f, 'KG_CLASS', 'UNKNOWN')
            rerank_score = getattr(f, 'RERANK_SCORE', 0.0)
            logging.info(f"{i:<6}{content_id:<25}{content_type:<20}{kg_class:<12}{rerank_score:<10.4f}")

        # Summary stats
        final_types = {}
        final_kg_classes = {}
        for f in final:
            ct = getattr(f, 'CONTENT_TYPE', 'unknown')
            kg = getattr(f, 'KG_CLASS', 'UNKNOWN')
            final_types[ct] = final_types.get(ct, 0) + 1
            final_kg_classes[kg] = final_kg_classes.get(kg, 0) + 1

        logging.info("\nFINAL SELECTION SUMMARY:")
        logging.info(f"  Total items: {len(final)}")
        logging.info(f"  By content type: {final_types}")
        logging.info(f"  By KG class: {final_kg_classes}")
        logging.info("="*80 + "\n")

    def retrieve_unified_content(self, search_query: str):
        """Retrieve all AS3000 content (text, tables, visual) from unified view via Cortex Search."""
        print(f"\n=== RETRIEVE_UNIFIED_CONTENT CALLED ===")
        print(f"Search Query: {search_query}")
        logging.info(f"=== RETRIEVE_UNIFIED_CONTENT CALLED ===")

        try:
            # Ensure we're initialized
            print(f"=== ENSURING INITIALIZATION ===")
            self._ensure_initialized()

            if not self.session:
                print(f"=== ERROR: SESSION IS NONE AFTER INIT ===")
                logging.error("Session is None after initialization")
                return []

            print(f"=== SESSION OK, SWITCHING TO CORTEX WAREHOUSE ===")

            # Use cortex search warehouse for best performance
            try:
                self.session.sql("USE WAREHOUSE cortex_search_wh").collect()
                print(f"=== WAREHOUSE SWITCHED TO CORTEX_SEARCH_WH ===")
            except Exception as warehouse_error:
                print(f"=== WAREHOUSE SWITCH FAILED: {warehouse_error} ===")
                logging.error(f"Warehouse switch failed: {warehouse_error}")

                # Check if it's a token expiration error - if so, renew session and retry
                error_msg = str(warehouse_error)
                if "Authentication token has expired" in error_msg or "390114" in error_msg:
                    logging.warning("Token expired during warehouse switch, renewing session...")
                    try:
                        if self.session:
                            try:
                                self.session.close()
                            except:
                                pass
                        self.session = self._get_session()
                        self._optimize_warehouse()
                        # Retry warehouse switch
                        self.session.sql("USE WAREHOUSE cortex_search_wh").collect()
                        print(f"=== SESSION RENEWED AND WAREHOUSE SWITCHED ===")
                        logging.info("Session renewed and warehouse switched successfully")
                    except Exception as renewal_error:
                        logging.error(f"Session renewal failed: {renewal_error}")
                        # Continue with current warehouse

            print(f"=== STARTING UNIFIED RETRIEVAL FOR: {search_query} ===")
            logging.info(f"Starting unified retrieval for: {search_query}")

            # Unified Cortex Search for all content types from AS3000_UNIFIED_VIEW
            print(f"=== CALLING UNIFIED VIEW SEARCH ===")
            all_results = self._get_unified_view_content(search_query)
            print(f"=== UNIFIED VIEW SEARCH RETURNED {len(all_results)} TOTAL ITEMS ===")

            # Count content types for logging
            text_count = len([r for r in all_results if getattr(r, 'CONTENT_TYPE', '') == 'text_chunk'])
            table_count = len([r for r in all_results if getattr(r, 'CONTENT_TYPE', '') == 'structured_table'])
            visual_count = len([r for r in all_results if getattr(r, 'CONTENT_TYPE', '') == 'visual_content'])

            print(f"=== BREAKDOWN: {table_count} tables + {text_count} text + {visual_count} visual ===")
            logging.info(f"Retrieved {len(all_results)} total items: {table_count} tables + {text_count} text + {visual_count} visual")

            return all_results

        except Exception as e:
            print(f"=== RETRIEVE_UNIFIED_CONTENT ERROR: {e} ===")
            logging.error(f"Unified content retrieval error: {e}")
            import traceback
            print(f"=== FULL TRACEBACK: {traceback.format_exc()} ===")
            return []

    def _get_unified_view_content(self, query: str, limit: int = None):
        """Get all content types from AS3000_UNIFIED_VIEW using Cortex Search."""
        import time
        start_time = time.time()

        # Use KG_CANDIDATE_SET_SIZE if KG reranking is enabled, otherwise use provided limit or default
        if limit is None:
            limit = KG_CANDIDATE_SET_SIZE if USE_KG_RERANK else 20

        print(f"=== UNIFIED VIEW SEARCH STARTING ===")
        print(f"Query: {query}")
        print(f"Candidate limit: {limit} (KG reranking: {'ON' if USE_KG_RERANK else 'OFF'})")
        logging.info(f"=== UNIFIED VIEW SEARCH STARTING ===")
        logging.info(f"KG reranking enabled: {USE_KG_RERANK}, candidate limit: {limit}")

        try:
            import json

            # Use SNOWFLAKE.CORTEX.SEARCH_PREVIEW function with fully qualified name
            search_sql = f"""
            SELECT
                PARSE_JSON(
                    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                        'ELECTRICAL_STANDARDS_DB.EVALUATION.as3000_search',
                        ?
                    )
                ):"results" AS search_results
            """

            # Build the search query JSON
            # NOTE: KG fields are fetched separately since they're not in Cortex Search index
            search_config = {
                "query": query,
                "columns": ["content_id", "content_type", "label", "content"],
                "limit": limit
            }
            search_config_json = json.dumps(search_config)

            print(f"=== EXECUTING CORTEX SEARCH (LIMIT {limit}) ===")
            print(f"=== SEARCH CONFIG: {search_config_json} ===")
            logging.info(f"Search config JSON: {search_config_json}")
            cortex_start = time.time()
            result = self.session.sql(search_sql, (search_config_json,)).collect()
            cortex_time = time.time() - cortex_start
            print(f"=== CORTEX SEARCH COMPLETED IN {cortex_time:.3f}s ===")

            # Use Cortex Search results directly - no second query needed
            enriched_results = []
            if result and len(result) > 0:
                search_results_json = result[0]['SEARCH_RESULTS']

                if search_results_json:
                    results_list = json.loads(search_results_json) if isinstance(search_results_json, str) else search_results_json

                    print(f"=== CORTEX SEARCH RETURNED {len(results_list)} RESULTS ===")

                    # Debug: Log first 5 content_ids returned by Cortex Search
                    for i, r in enumerate(results_list[:5], 1):
                        cid = r.get('content_id', 'NO_ID')
                        ctype = r.get('content_type', 'NO_TYPE')
                        label_preview = r.get('label', '')[:50]
                        print(f"  [{i}] {cid} ({ctype}): {label_preview}...")
                        logging.info(f"  [{i}] {cid} ({ctype}): {label_preview}...")

                    # Fetch KG fields from unified view for all content_ids
                    content_ids = [r.get('content_id', '') for r in results_list if r.get('content_id')]
                    kg_fields_map = self._fetch_kg_fields(content_ids) if content_ids else {}

                    # Use Cortex Search results directly
                    for idx, r in enumerate(results_list):
                        content_id = r.get('content_id', '')
                        content_type = r.get('content_type', '')
                        label = r.get('label', '')
                        content = r.get('content', '')
                        scores = r.get('@scores', {})
                        similarity = scores.get('cosine_similarity', 0.9) if scores else 0.9

                        # Get KG fields from separate fetch
                        kg_fields = kg_fields_map.get(content_id, {})
                        kg_class = kg_fields.get('kg_class', 'UNKNOWN')
                        requirement_count = kg_fields.get('requirement_count', None)
                        condition_count = kg_fields.get('condition_count', None)
                        normative_confidence_max = kg_fields.get('normative_confidence_max', None)
                        condition_confidence_max = kg_fields.get('condition_confidence_max', None)

                        # Extract VISUAL_URL from content if it's visual content
                        # (for visual: content = "url description")
                        visual_url = None
                        text_content = content
                        if content_type == 'visual_content' and content:
                            parts = content.split(' ', 1)
                            if len(parts) == 2 and parts[0].startswith('http'):
                                visual_url = parts[0]
                                text_content = parts[1]

                        result_obj = type('obj', (object,), {
                            'CONTENT_ID': content_id,
                            'CONTENT_TYPE': content_type,
                            'TEXT_CONTENT': text_content,
                            'VISUAL_URL': visual_url,
                            'SEARCH_ID': content_id.replace('TEXT_', '').replace('VISUAL_', ''),
                            'LABEL': label[:200] if label else '',
                            'PAGE_NUMBER': None,
                            'SECTION_NAME': None,
                            'TABLE_NUMBER': None,
                            'TABLE_HTML': None,
                            'SIMILARITY': float(similarity),
                            'RANK': idx + 1,
                            'KG_CLASS': kg_class if kg_class else 'UNKNOWN',
                            'REQUIREMENT_COUNT': requirement_count,
                            'CONDITION_COUNT': condition_count,
                            'NORMATIVE_CONFIDENCE_MAX': normative_confidence_max,
                            'CONDITION_CONFIDENCE_MAX': condition_confidence_max
                        })()
                        enriched_results.append(result_obj)

            # Log content type breakdown
            content_types = {}
            for r in enriched_results:
                ct = getattr(r, 'CONTENT_TYPE', 'unknown')
                content_types[ct] = content_types.get(ct, 0) + 1
            print(f"=== CONTENT TYPE BREAKDOWN: {content_types} ===")

            # Apply KG reranking if enabled
            if USE_KG_RERANK and enriched_results:
                print(f"=== APPLYING KG RERANKING ===")
                logging.info(f"Applying KG reranking to {len(enriched_results)} candidates")

                # Step 1: Rerank candidates using KG class
                reranked_results = self._kg_rerank_candidates(enriched_results)

                # Step 2: Apply quota-based selection
                final_results = self._apply_quota_selection(reranked_results)

                # Step 3: Log debug info
                self._log_kg_rerank_debug(enriched_results, reranked_results, final_results)

                print(f"=== KG RERANKING COMPLETE: {len(enriched_results)} -> {len(final_results)} ===")
                logging.info(f"KG reranking complete: {len(enriched_results)} candidates -> {len(final_results)} final")

                return final_results
            else:
                if USE_KG_RERANK:
                    print(f"=== KG RERANKING SKIPPED: No candidates ===")
                else:
                    print(f"=== KG RERANKING DISABLED ===")
                return enriched_results

        except Exception as e:
            logging.error(f"Cortex Search error: {e}")
            import traceback
            logging.error(f"Traceback: {traceback.format_exc()}")
            return []

    def _fetch_kg_fields(self, content_ids: List[str]) -> Dict[str, Dict]:
        """
        Fetch KG fields from AS3000_UNIFIED_VIEW for given content_ids.

        Args:
            content_ids: List of content IDs to fetch KG data for

        Returns:
            Dict mapping content_id to dict of KG fields:
            {
                'content_id': {
                    'kg_class': str,
                    'requirement_count': int,
                    'condition_count': int,
                    'normative_confidence_max': float,
                    'condition_confidence_max': float
                }
            }
        """
        if not content_ids or not self.session:
            return {}

        try:
            # Build IN clause - escape single quotes
            escaped_ids = [cid.replace("'", "''") for cid in content_ids]
            ids_list = "','".join(escaped_ids)

            query = f"""
                SELECT
                    CONTENT_ID,
                    KG_CLASS,
                    REQUIREMENT_COUNT,
                    CONDITION_COUNT,
                    NORMATIVE_CONFIDENCE_MAX,
                    CONDITION_CONFIDENCE_MAX
                FROM ELECTRICAL_STANDARDS_DB.AS_STANDARDS.AS3000_UNIFIED_VIEW
                WHERE CONTENT_ID IN ('{ids_list}')
            """

            print(f"=== FETCHING KG FIELDS FOR {len(content_ids)} CONTENT_IDS ===")
            results = self.session.sql(query).collect()
            print(f"=== KG FIELDS FETCH RETURNED {len(results)} ROWS ===")

            # Build map
            kg_map = {}
            for row in results:
                kg_map[row['CONTENT_ID']] = {
                    'kg_class': row['KG_CLASS'] if row['KG_CLASS'] else 'UNKNOWN',
                    'requirement_count': row['REQUIREMENT_COUNT'],
                    'condition_count': row['CONDITION_COUNT'],
                    'normative_confidence_max': row['NORMATIVE_CONFIDENCE_MAX'],
                    'condition_confidence_max': row['CONDITION_CONFIDENCE_MAX']
                }

            print(f"=== KG FIELDS MAP BUILT: {len(kg_map)} entries ===")
            return kg_map

        except Exception as e:
            logging.error(f"Failed to fetch KG fields: {e}")
            import traceback
            logging.error(f"Traceback: {traceback.format_exc()}")
            return {}

    def get_image_data_for_vision(self, unified_results: List) -> List[Dict]:
        """Get image data for vision model from unified results with VISUAL_URL."""
        if not unified_results:
            return []

        vision_images = []
        # Extract visual content from unified results
        visual_items = [r for r in unified_results if getattr(r, 'VISUAL_URL', None)]

        for result in visual_items[:3]:  # Top 3 visual items (optimized based on eval analysis)
            try:
                visual_url = getattr(result, 'VISUAL_URL', '')
                content_id = getattr(result, 'CONTENT_ID', '')

                if visual_url:
                    vision_images.append({
                        "type": "image_url",
                        "image_url": {"url": visual_url}
                    })
                    logging.info(f"Added visual content: {content_id}")

            except Exception as e:
                logging.error(f"Error processing visual content: {e}")
                continue

        logging.info(f"Prepared {len(vision_images)} visual images for vision model from unified results")
        return vision_images

    @log_rag_interaction
    def generate_response(self, chat_history: list, raw_question: str) -> dict:
        """Generate response for electrician queries."""
        print(f"=== GENERATE_RESPONSE CALLED with question: {raw_question} ===")
        try:
            print(f"=== INSIDE TRY BLOCK ===")
            self._ensure_initialized()
            # Use raw question directly for better search matches
            search_query = raw_question.strip()

            # Track timing
            retrieval_start = time.time()

            # Retrieve all content (text, tables, visual) from unified view
            print(f"=== SESSION CHECK: {self.session is not None} ===")
            print(f"=== CALLING RETRIEVE_UNIFIED_CONTENT ===")
            unified_results = self.retrieve_unified_content(search_query)
            logging.info(f"Unified content results: {len(unified_results)} items (text + tables + visual from AS3000_UNIFIED_VIEW)")

            # Cap visual content at 3 items (optimized based on eval analysis: 1-2 visuals perform best)
            MAX_VISUALS = 3
            visual_items = [r for r in unified_results if getattr(r, 'CONTENT_TYPE', '') == 'visual_content']
            non_visual_items = [r for r in unified_results if getattr(r, 'CONTENT_TYPE', '') != 'visual_content']
            if len(visual_items) > MAX_VISUALS:
                logging.info(f"Capping visuals from {len(visual_items)} to {MAX_VISUALS}")
                visual_items = visual_items[:MAX_VISUALS]
            unified_results = non_visual_items + visual_items

            retrieval_time = time.time() - retrieval_start
            
            if not unified_results:
                return {
                    "response": "I don't have specific information about that in the AS3000 standards. Please consult the full AS3000:2018 document or contact a qualified electrical contractor."
                }
            
            # Build context from unified AS3000 content
            # IMPORTANT: Include content_ids so citations can be traced back to source chunks
            context_section = "AS3000 Electrical Standards Information:\n\n"

            # Process all unified results (text, tables, and visual)
            for i, result in enumerate(unified_results, 1):
                content_id = getattr(result, 'CONTENT_ID', '')
                content_type = getattr(result, 'CONTENT_TYPE', '')
                text_content = getattr(result, 'TEXT_CONTENT', '')
                visual_url = getattr(result, 'VISUAL_URL', '')
                table_number = getattr(result, 'TABLE_NUMBER', '')
                table_html = getattr(result, 'TABLE_HTML', '')
                label = getattr(result, 'LABEL', '')
                page_num = getattr(result, 'PAGE_NUMBER', '')
                similarity = getattr(result, 'SIMILARITY', 0)

                # Handle structured tables
                if content_type == 'structured_table' and table_number:
                    context_section += f"[{i}] [ID: {content_id}] AS3000 Table {table_number} (Page {page_num})\n"
                    if text_content:
                        context_section += f"{text_content}\n"
                    context_section += "\n"

                # Handle visual content
                elif content_type == 'visual_content' and visual_url:
                    context_section += f"[{i}] [ID: {content_id}] AS3000 Visual Content (Page {page_num})\n"
                    context_section += f"{label}\n"
                    context_section += f"Visual available in attached images\n\n"

                # Handle text chunks
                else:
                    context_section += f"[{i}] [ID: {content_id}] AS3000 Content (Page {page_num})\n"
                    context_section += f"{label}\n"
                    if text_content:
                        context_section += f"{text_content}\n"
                    context_section += "\n"

            # Extract vision images from unified results
            vision_images = self.get_image_data_for_vision(unified_results)
            
            # Generate response using retrieved content
            generation_start = time.time()
            
            if self.groq_client:
                try:
                    system_prompt = """You are Sparkie, an expert assistant for Australian electricians. Be conversational and helpful while providing precise AS/NZS 3000 answers.

## CRITICAL: AMBIGUITY CHECK FIRST (MANDATORY)
Before providing ANY answer, you MUST check if the question lacks essential details:

**For resistance/impedance questions, ALWAYS ask about:**
- Disconnection time requirement (0.4s vs 5.0s)
- Resistance type needed (Rphe earth fault loop vs Re earth electrode)
- Conductor sizes (active and earth conductor mm²)
- Installation method or environment

**For other electrical questions, check for:**
- Multiple device types (MCB Type B/C/D, HRC fuses, etc.)
- Different ratings or configurations
- Installation conditions
- Environmental factors

## WHEN TO ASK FOR CLARIFICATION
If ANY essential parameter is missing, respond conversationally:
"I need a bit more info to give you the right answer. For [device type], I can see different values depending on:
- [List the missing parameters]
- [Any other relevant factors]

Can you clarify which specific value you need?"

## WHEN QUESTION IS COMPLETE
Only provide direct answers when ALL parameters are specified.

**Keep responses short and conversational:**
- Lead with the direct answer
- Show which table/source
- Mention any important notes

## CITATION REQUIREMENTS
When providing answers, cite your sources using professional references only. DO NOT include internal content IDs in your response.

**Citation format:**
- Use clause numbers: "According to Clause 3.7.2..."
- Use table references: "As per AS3000 Table 2.6..."
- Use figure/diagram references: "See Figure 4.1..." or "As shown in the diagram..."
- Keep citations clean and professional for the customer

**Example citations:**
- "The maximum value is 230 ohms as per AS3000 Table 2.6"
- "According to Clause 1.4.79, definitions include..."
- "See the diagram showing the connection requirements"

## RESPONSE STYLE
- Sound like a helpful electrician, not a textbook
- Use "mate" occasionally but professionally
- Ask follow-up questions when details are missing
- Be precise but friendly

## EXAMPLE RESPONSES

**Ambiguous question:**
"I need to know which specific value you're after, mate. For [device type] questions, there are different limits depending on:
- [Parameter 1]
- [Parameter 2]
- [Parameter 3]

What's your specific setup?"

**Complete question:**
"[Direct answer] from [AS3000 Source]. [Brief context note if relevant]."

## OUTPUT FORMAT FOR COMPLETE ANSWERS
[Direct answer with inline citations to clauses/tables]

---

**References:**
- List all AS3000 clauses, tables, and figures used
- Keep it clean and professional"""

                    # Build user message content (text + optional images)
                    user_content = [
                        {"type": "text", "text": f"""Question: {raw_question}

{context_section}

Give ONLY the direct answer - no explanations or calculations. If tables show values, state them immediately. List AS3000 references."""}
                    ]
                    
                    # Add vision images if available
                    if vision_images:
                        user_content.extend(vision_images)
                        logging.info(f"Added {len(vision_images)} images to vision request")
                    
                    messages = [
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_content}
                    ]

                    # Log what we're sending 
                    logging.info(f"=== TEXT RETRIEVAL DEBUG ===")
                    logging.info(f"Question: {raw_question}")
                    logging.info(f"Retrieved {len(unified_results)} text content items (RAW_TEXT only)")
                    
                    # Log the text context being sent
                    context_preview = context_section[:300] + "..." if len(context_section) > 300 else context_section
                    logging.info(f"Text context preview: {context_preview}")
                    
                    completion = self.groq_client.chat.completions.create(
                        model=MODEL_NAME,
                        messages=messages,
                        temperature=0.1,  # Even lower temperature for more consistency
                        max_tokens=1200,  # Increased for vision analysis
                        top_p=0.8,  # Lower top_p for more deterministic responses
                        seed=42  # Add seed for reproducibility
                    )
                    
                    response = completion.choices[0].message.content.strip()
                    
                    # Log the raw response for debugging
                    logging.info(f"Raw LLM response: {response}")
                    logging.info(f"=== END VISION DEBUG ===")
                    
                    # Log token usage if available
                    if hasattr(completion, 'usage'):
                        logging.info(f"Token usage: {completion.usage}")
                    
                    # Log model parameters used
                    logging.info(f"Model params: temp=0.1, top_p=0.8, seed=42")
                    
                except Exception as e:
                    logging.error(f"Groq vision generation failed with model {MODEL_NAME}: {str(e)}")
                    logging.error(f"Vision images prepared: {len(vision_images) if 'vision_images' in locals() else 0}")
                    logging.error(f"Message structure: {type(messages[1]['content']) if len(messages) > 1 else 'No messages'}")

                    # Retry without vision images (text-only fallback)
                    try:
                        logging.info("Retrying with text-only (no vision images)")
                        text_only_messages = [
                            {"role": "system", "content": system_prompt},
                            {"role": "user", "content": f"""Question: {raw_question}

{context_section}

Give ONLY the direct answer - no explanations or calculations. If tables show values, state them immediately. List AS3000 references."""}
                        ]

                        completion = self.groq_client.chat.completions.create(
                            model=MODEL_NAME,
                            messages=text_only_messages,
                            temperature=0.1,
                            max_tokens=1200,
                            top_p=0.8,
                            seed=42
                        )

                        response = completion.choices[0].message.content.strip()
                        logging.info("Text-only fallback succeeded")
                    except Exception as text_error:
                        logging.error(f"Text-only fallback also failed: {str(text_error)}")
                        response = f"Based on the AS3000 standards: {unified_results[0].TEXT_CONTENT[:200] if unified_results else 'No content found'}... Please consult AS3000:2018 for complete details."
            else:
                # Fallback when Groq unavailable
                response = f"Based on the AS3000 standards: {unified_results[0].TEXT_CONTENT[:200] if unified_results else 'No content found'}... Please consult AS3000:2018 for complete details."
            
            generation_time = time.time() - generation_start
            
            print(f"=== STARTING METADATA PREP ===")
            print(f"About to prepare metadata for {len(unified_results)} unified results")
            
            # Prepare metadata for sidebar from unified results
            chunks_metadata = []
            visual_metadata = []

            for i, result in enumerate(unified_results):
                similarity_val = getattr(result, 'SIMILARITY', 0)
                content_type = getattr(result, 'CONTENT_TYPE', '')
                content_id = getattr(result, 'CONTENT_ID', '')
                label = getattr(result, 'LABEL', '')
                text_content = getattr(result, 'TEXT_CONTENT', '')
                visual_url = getattr(result, 'VISUAL_URL', '')
                page_number = getattr(result, 'PAGE_NUMBER', '')
                table_number = getattr(result, 'TABLE_NUMBER', '')

                # Get KG fields
                kg_class = getattr(result, 'KG_CLASS', 'UNKNOWN')
                requirement_count = getattr(result, 'REQUIREMENT_COUNT', None)
                condition_count = getattr(result, 'CONDITION_COUNT', None)
                normative_confidence_max = getattr(result, 'NORMATIVE_CONFIDENCE_MAX', None)
                condition_confidence_max = getattr(result, 'CONDITION_CONFIDENCE_MAX', None)
                rerank_score = getattr(result, 'RERANK_SCORE', None)

                # Separate visual content into visual_metadata
                if content_type == 'visual_content' and visual_url:
                    visual_data = {
                        "content_id": content_id,
                        "page_number": page_number,
                        "description": label[:100] + "..." if len(label) > 100 else label,
                        "similarity": float(similarity_val) if similarity_val else 0.0,
                        "thumbnail_url": visual_url,
                        "rank": i + 1,
                        "kg_class": kg_class,
                        "rerank_score": float(rerank_score) if rerank_score is not None else None
                    }
                    visual_metadata.append(visual_data)

                # All content types go into chunks_metadata
                else:
                    chunk_data = {
                        "content_id": content_id,
                        "content_type": content_type,
                        "table_number": table_number,
                        "page_number": page_number,
                        "similarity": float(similarity_val) if similarity_val else 0.0,
                        "rank": i + 1,
                        "search_method": "Unified Cortex Search" + (" + KG Rerank" if USE_KG_RERANK else ""),
                        "description": label[:100] + "..." if len(label) > 100 else label,
                        "chunk_preview": text_content[:150] + "..." if len(text_content) > 150 else text_content,
                        "is_table": content_type == 'structured_table',
                        "visual_url": visual_url if visual_url else None,
                        "kg_class": kg_class,
                        "requirement_count": requirement_count,
                        "condition_count": condition_count,
                        "normative_confidence_max": float(normative_confidence_max) if normative_confidence_max is not None else None,
                        "condition_confidence_max": float(condition_confidence_max) if condition_confidence_max is not None else None,
                        "rerank_score": float(rerank_score) if rerank_score is not None else None
                    }
                    chunks_metadata.append(chunk_data)

            # Debug logging
            print(f"=== UNIFIED SEARCH METADATA DEBUG ===")
            print(f"Total unified results: {len(unified_results)}")
            print(f"Chunks metadata: {len(chunks_metadata)}")
            print(f"Visual metadata: {len(visual_metadata)}")
            text_count = len([r for r in unified_results if getattr(r, 'CONTENT_TYPE', '') == 'text_chunk'])
            table_count = len([r for r in unified_results if getattr(r, 'CONTENT_TYPE', '') == 'structured_table'])
            visual_count = len([r for r in unified_results if getattr(r, 'CONTENT_TYPE', '') == 'visual_content'])
            print(f"Content breakdown: {text_count} text + {table_count} tables + {visual_count} visual")
            print(f"=== END METADATA DEBUG ===")

            return {
                "response": response,
                "retrieval_time": retrieval_time,
                "generation_time": generation_time,
                "chunks_used": len(unified_results),
                "visual_content_count": visual_count if 'visual_count' in locals() else 0,
                "chunks_metadata": chunks_metadata,
                "visual_metadata": visual_metadata,
                "kg_config": {
                    "use_kg_rerank": USE_KG_RERANK,
                    "kg_candidate_set_size": KG_CANDIDATE_SET_SIZE,
                    "kg_final_k": KG_FINAL_K,
                    "kg_weight_A": KG_BOOST_A,
                    "kg_weight_B": KG_BOOST_B,
                    "kg_weight_C": KG_PENALTY_C,
                    "kg_weight_UNKNOWN": KG_NEUTRAL_UNKNOWN,
                    "min_normative_text": MIN_NORMATIVE_TEXT,
                    "max_non_normative_text": MAX_NON_NORMATIVE_TEXT,
                    "min_unknown_nontext": MIN_UNKNOWN_NONTEXT
                }
            }
            
        except Exception as e:
            import traceback
            logging.error(f"Generation error: {str(e)}")
            logging.error(f"Full traceback: {traceback.format_exc()}")
            return {
                "response": "I'm experiencing technical difficulties. Please try rephrasing your question or consult AS3000:2018 directly.",
                "retrieval_time": 0,
                "generation_time": 0,
                "chunks_used": 0,
                "visual_content_count": 0,
                "chunks_metadata": [],
                "visual_metadata": []
            }
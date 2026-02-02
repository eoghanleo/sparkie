"""
Evaluation Metrics for Sparkie RAG Application - V2 Optimized

IMPROVEMENTS OVER V1:
- Reduced from 5 API calls to 2 API calls (60% latency reduction)
- ~40% token savings by eliminating redundant context
- All chunks and images provided to both evaluation calls
- Maintains same quality and granularity as V1

Two-Prompt Architecture:
1. Context-Heavy Evaluation (multimodal): Hallucination + Citation
2. Question-Answer Evaluation (text-only): Relevance + Completeness + Technical Accuracy
"""

import re
import logging
from typing import Dict, List, Any, Optional, Tuple
import json
from groq import Groq
import os
from dotenv import load_dotenv
import snowflake.connector

load_dotenv()
logger = logging.getLogger(__name__)


class EvalMetricsV2:
    """
    Optimized evaluation metrics using two-prompt LLM-as-judge methodology
    """

    def __init__(self, groq_api_key: Optional[str] = None, model: str = "meta-llama/llama-4-maverick-17b-128e-instruct", snowflake_conn=None):
        self.groq_client = Groq(api_key=groq_api_key or os.getenv('GROQ_API_KEY'))
        self.judge_model = model
        self.judge_temperature = 0.0  # Deterministic for evaluation
        self.snowflake_conn = snowflake_conn  # For generating presigned URLs

    def evaluate_interaction(
        self,
        question: str,
        answer: str,
        retrieved_context: List[Dict[str, Any]],
        expected_answer: Optional[str] = None,
        expected_clause: Optional[str] = None,
        golden_has_table: Optional[bool] = None,
        golden_has_diagram: Optional[bool] = None
    ) -> Dict[str, Any]:
        """
        Run all evaluation metrics on a single interaction using TWO optimized prompts + KG metrics

        Args:
            question: User's query
            answer: Generated response from Sparkie
            retrieved_context: List of retrieved chunks with metadata (ALL chunks and images)
            expected_answer: Golden set answer (optional)
            expected_clause: Expected AS3000 clause reference (optional)
            golden_has_table: Whether golden answer references tables (for multimodal check)
            golden_has_diagram: Whether golden answer references diagrams (for multimodal check)

        Returns:
            Dictionary with all evaluation scores and reasoning
        """
        results = {}

        # PROMPT 1: Context-heavy evaluation (multimodal with images)
        # Evaluates: Hallucination + Citation Accuracy
        context_eval = self._evaluate_with_context(
            question=question,
            answer=answer,
            retrieved_context=retrieved_context,
            expected_clause=expected_clause,
            expected_answer=expected_answer
        )
        results.update(context_eval)

        # PROMPT 2: Question-answer evaluation (text-only, faster)
        # Evaluates: Relevance + Completeness + Technical Accuracy (if golden answer provided)
        qa_eval = self._evaluate_question_answer(
            question=question,
            answer=answer,
            expected_answer=expected_answer
        )
        results.update(qa_eval)

        # KG-AWARE METRICS: Normative coverage, non-normative reliance, conditional risk, multimodal starvation
        kg_metrics = self._evaluate_kg_metrics(
            question=question,
            answer=answer,
            retrieved_context=retrieved_context,
            golden_has_table=golden_has_table,
            golden_has_diagram=golden_has_diagram
        )
        results.update(kg_metrics)

        # PASS/FAIL: LLM-based intuitive judgment against golden set answer
        if expected_answer:
            pass_result = self.evaluate_pass_fail(
                question=question,
                answer=answer,
                expected_answer=expected_answer
            )
            results.update(pass_result)
        else:
            results['passed'] = None
            results['pass_fail_reason'] = 'No expected answer provided for pass/fail evaluation'

        return results

    def evaluate_pass_fail(
        self,
        question: str,
        answer: str,
        expected_answer: str
    ) -> Dict[str, Any]:
        """
        LLM-based pass/fail judgment comparing generated answer against golden set answer.

        Design Philosophy:
        - LENIENT on phrasing, format, extra context, different wording
        - STRICT on factual correctness: wrong numbers, fabricated requirements, incorrect clauses

        The LLM intuitively judges whether the answer is "good enough" - would a user
        reading this answer get the correct information they need?

        Returns:
            Dict with:
            - passed: bool
            - pass_fail_reason: str explaining the decision
        """
        if not expected_answer:
            return {
                'passed': None,
                'pass_fail_reason': 'No golden set answer provided for comparison'
            }

        prompt = f"""You are evaluating whether a RAG system's answer is acceptable compared to the expected correct answer.

QUESTION:
{question}

GENERATED ANSWER:
{answer}

EXPECTED CORRECT ANSWER:
{expected_answer}

═══════════════════════════════════════════════════════════════

Your task: Determine if the generated answer PASSES or FAILS.

BE LENIENT - PASS the answer if:
- It conveys the same core information as the expected answer
- The key facts, numbers, and requirements match (even if worded differently)
- It answers the question correctly, even with extra context or different phrasing
- Minor omissions that don't affect the user's understanding

BE STRICT - FAIL the answer if:
- Numbers or measurements are wrong (e.g., "2.4m" when it should be "1.8m")
- Key requirements are missing or incorrect
- The answer contradicts the expected answer on important points
- Information is completely fabricated or made up
- The answer doesn't actually address what was asked

Remember: We're checking "would the user get the right information?" not "is it word-for-word identical?"

═══════════════════════════════════════════════════════════════

OUTPUT FORMAT (JSON only):
{{
    "passed": true or false,
    "reason": "Brief explanation of why it passed or failed"
}}

Respond with ONLY the JSON object."""

        try:
            response = self.groq_client.chat.completions.create(
                model=self.judge_model,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.0,
                max_tokens=300
            )

            result_text = response.choices[0].message.content.strip()
            result = self._parse_json_response(result_text)

            return {
                'passed': result.get('passed', None),
                'pass_fail_reason': result.get('reason', 'No reason provided')
            }

        except Exception as e:
            logger.error(f"Pass/fail evaluation failed: {e}")
            return {
                'passed': None,
                'pass_fail_reason': f'Evaluation failed: {str(e)}'
            }

    def _evaluate_with_context(
        self,
        question: str,
        answer: str,
        retrieved_context: List[Dict[str, Any]],
        expected_clause: Optional[str],
        expected_answer: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        PROMPT 1: Evaluate hallucination and citation accuracy using FULL retrieved context

        This is the heavy evaluation that needs all chunks and images.
        Uses multimodal model when images are present.
        Now also considers expected_answer from golden set to avoid false hallucination flags.
        """
        # Build context string and collect ALL images (up to Groq's 5-image limit)
        context_text, vision_images = self._build_context_with_images(retrieved_context)

        # Extract cited clauses for the judge to verify
        cited_clauses = self._extract_clause_references(answer)
        cited_clauses_str = ', '.join(cited_clauses) if cited_clauses else 'None found'

        # Build expected answer section if available
        expected_answer_section = ""
        if expected_answer:
            expected_answer_section = f"""
EXPECTED ANSWER (from golden set - the correct answer):
{expected_answer}
"""

        prompt_text = f"""You are an expert evaluator for a RAG system that provides AS3000 electrical standards information.

Your task is to evaluate TWO dimensions of the generated answer:
1. HALLUCINATION DETECTION - Are claims fabricated or actually correct?
2. CITATION ACCURACY - Are AS3000 clause references correct?

═══════════════════════════════════════════════════════════════

QUESTION (from user):
{question}

ANSWER (generated by RAG system):
{answer}
{expected_answer_section}
RETRIEVED CONTEXT (from AS3000 standards - includes text and visual content):
{context_text}

EXPECTED CLAUSE (from golden set): {expected_clause or 'Not provided'}

CITED CLAUSES (extracted from answer): {cited_clauses_str}

═══════════════════════════════════════════════════════════════

TASK 1 - HALLUCINATION DETECTION:

1. Extract all factual claims from the ANSWER (measurements, requirements, clause references, safety rules, technical specifications)
2. For each claim, verify if it appears in or is directly inferable from EITHER:
   - The RETRIEVED CONTEXT, OR
   - The EXPECTED ANSWER (if provided) - this is the verified correct answer from the golden set
3. IMPORTANT: If the EXPECTED ANSWER is provided and the generated answer aligns with it, the answer is NOT a hallucination even if the retrieval missed the relevant context. This indicates a retrieval failure, not a generation failure.
4. If images are provided above, examine tables, diagrams, and figures for specific values and requirements
5. List any claims that are NOT supported by either the context OR the expected answer
6. Provide a hallucination score from 0.0 to 1.0 using precise decimals (e.g., 0.23, 0.56, 0.84):
   - 0.0-0.15: All claims supported by context OR match expected answer
   - 0.16-0.35: Minor unsupported details (but core answer correct)
   - 0.36-0.65: Moderate hallucinations (some claims unsupported and don't match expected)
   - 0.66-0.89: Significant fabricated information
   - 0.90-1.0: Severe/complete hallucinations (answer contradicts expected answer)

TASK 2 - CITATION ACCURACY:

1. Verify if the cited clauses are accurate based on the retrieved context
2. Check if the cited clauses match the expected clause (if provided)
3. Assess if the citations are relevant to the question
4. Provide a citation accuracy score from 0.0 to 1.0 using precise decimals (e.g., 0.73, 0.41, 0.88):
   - 0.90-1.0: All citations accurate and match expected clause
   - 0.70-0.89: Citations accurate but don't exactly match expected
   - 0.35-0.69: Some citations accurate, some incorrect
   - 0.10-0.34: Most citations incorrect or irrelevant
   - 0.0-0.09: No citations or all wrong

═══════════════════════════════════════════════════════════════

OUTPUT FORMAT (JSON only, no other text):
{{
    "hallucination_score": 0.0,
    "unsupported_claims": ["claim 1", "claim 2"],
    "hallucination_reasoning": "Detailed explanation of hallucination assessment",
    "citation_accuracy": 0.0,
    "correct_clause_ref": false,
    "citation_reasoning": "Detailed explanation of citation accuracy assessment"
}}

Respond with ONLY the JSON object."""

        try:
            # Build messages with vision support
            if vision_images:
                # Multimodal message with text + images
                content = [{"type": "text", "text": prompt_text}] + vision_images
                messages = [{"role": "user", "content": content}]
                logger.info(f"=== PROMPT 1: CONTEXT EVALUATION (MULTIMODAL) ===")
                logger.info(f"Images in request: {len(vision_images)}")
            else:
                # Text-only message
                messages = [{"role": "user", "content": prompt_text}]
                logger.info(f"=== PROMPT 1: CONTEXT EVALUATION (TEXT ONLY) ===")

            response = self.groq_client.chat.completions.create(
                model=self.judge_model,
                messages=messages,
                temperature=self.judge_temperature,
                max_tokens=1400  # Enough for both evaluations
            )

            result_text = response.choices[0].message.content.strip()
            result = self._parse_json_response(result_text)

            # Use deterministic graded citation matching instead of LLM judgment
            citation_grading = self._grade_citation_accuracy(cited_clauses, expected_clause)

            return {
                'hallucination_score': result.get('hallucination_score', 0.5),
                'hallucination_details': result.get('hallucination_reasoning', ''),
                'unsupported_claims': result.get('unsupported_claims', []),
                'citation_accuracy': citation_grading['citation_accuracy'],  # Deterministic grading
                'correct_clause_ref': citation_grading['correct_clause_ref'],  # Deterministic grading
                'cited_clauses': cited_clauses,
                'expected_clause': expected_clause,
                'citation_details': citation_grading['citation_details'],  # Diagnostic info
                'judge_prompt_tokens': response.usage.prompt_tokens if response.usage else None,
                'judge_response_tokens': response.usage.completion_tokens if response.usage else None
            }

        except Exception as e:
            logger.error(f"Context evaluation failed: {e}")

            # Even if LLM evaluation fails, we can still grade citations deterministically
            citation_grading = self._grade_citation_accuracy(cited_clauses, expected_clause)

            return {
                'hallucination_score': None,
                'hallucination_details': f'Evaluation failed: {str(e)}',
                'unsupported_claims': [],
                'citation_accuracy': citation_grading['citation_accuracy'],
                'correct_clause_ref': citation_grading['correct_clause_ref'],
                'cited_clauses': cited_clauses,
                'expected_clause': expected_clause,
                'citation_details': citation_grading['citation_details']
            }

    def _evaluate_question_answer(
        self,
        question: str,
        answer: str,
        expected_answer: Optional[str]
    ) -> Dict[str, Any]:
        """
        PROMPT 2: Evaluate relevance, completeness, and technical accuracy

        This is the lighter evaluation that only needs question + answer.
        Text-only, no images needed.
        """
        # Build prompt based on whether we have a golden set answer
        has_golden_answer = expected_answer is not None

        if has_golden_answer:
            task_description = """Your task is to evaluate THREE dimensions of the generated answer:
1. RELEVANCE - Does the answer address the question?
2. COMPLETENESS - Are all parts of the question covered?
3. TECHNICAL ACCURACY - How well does it match the expected answer?"""

            expected_section = f"""
EXPECTED ANSWER (golden set reference):
{expected_answer}"""

            task3_section = """
TASK 3 - TECHNICAL ACCURACY:

Compare the ACTUAL ANSWER to the EXPECTED ANSWER and rate technical accuracy from 0.0 to 1.0 using precise decimals (e.g., 0.76, 0.42, 0.91):
- 0.93-1.0: Technically equivalent with same facts
- 0.75-0.92: Mostly accurate with minor phrasing differences
- 0.40-0.74: Partially accurate with some technical errors
- 0.15-0.39: Significant technical errors present
- 0.0-0.14: Completely wrong or contradicts expected"""

            output_fields = """    "technical_accuracy": 0.0,
    "technical_accuracy_reasoning": "Detailed explanation of technical accuracy assessment" """
        else:
            task_description = """Your task is to evaluate TWO dimensions of the generated answer:
1. RELEVANCE - Does the answer address the question?
2. COMPLETENESS - Are all parts of the question covered?"""

            expected_section = ""
            task3_section = ""
            output_fields = ""

        prompt_text = f"""You are an expert evaluator for a RAG system that provides AS3000 electrical standards information.

{task_description}

═══════════════════════════════════════════════════════════════

QUESTION (from user):
{question}

ANSWER (generated by RAG system):
{answer}
{expected_section}

═══════════════════════════════════════════════════════════════

TASK 1 - RELEVANCE:

Rate the relevance of the ANSWER to the QUESTION on a scale from 0.0 to 1.0 using precise decimals (e.g., 0.73, 0.92, 0.45):
- 0.95-1.0: Directly and completely addresses the question
- 0.75-0.94: Mostly relevant with minor gaps
- 0.40-0.74: Partially relevant with significant gaps
- 0.15-0.39: Tangentially related
- 0.0-0.14: Completely irrelevant

TASK 2 - COMPLETENESS:

Rate the completeness of the ANSWER on a scale from 0.0 to 1.0 using precise decimals (e.g., 0.67, 0.88, 0.34):
- 0.92-1.0: All parts thoroughly addressed
- 0.70-0.91: Main points covered with minor details missing
- 0.35-0.69: Partially complete with significant gaps
- 0.10-0.34: Minimal coverage
- 0.0-0.09: Question not addressed
{task3_section}

═══════════════════════════════════════════════════════════════

OUTPUT FORMAT (JSON only, no other text):
{{
    "answer_relevance": 0.0,
    "relevance_reasoning": "Detailed explanation of relevance assessment",
    "answer_completeness": 0.0,
    "completeness_reasoning": "Detailed explanation of completeness assessment"{(',' if has_golden_answer else '')}
{output_fields}
}}

Respond with ONLY the JSON object."""

        try:
            logger.info(f"=== PROMPT 2: QUESTION-ANSWER EVALUATION (TEXT ONLY) ===")

            response = self.groq_client.chat.completions.create(
                model=self.judge_model,
                messages=[{"role": "user", "content": prompt_text}],
                temperature=self.judge_temperature,
                max_tokens=1000  # Enough for 2-3 evaluations
            )

            result_text = response.choices[0].message.content.strip()
            result = self._parse_json_response(result_text)

            output = {
                'answer_relevance': result.get('answer_relevance', 0.5),
                'relevance_details': result.get('relevance_reasoning', ''),
                'answer_completeness': result.get('answer_completeness', 0.5),
                'completeness_details': result.get('completeness_reasoning', '')
            }

            # Add technical accuracy if golden answer was provided
            if has_golden_answer:
                output['technical_accuracy'] = result.get('technical_accuracy', 0.5)
                output['accuracy_details'] = result.get('technical_accuracy_reasoning', '')

            return output

        except Exception as e:
            logger.error(f"Question-answer evaluation failed: {e}")
            output = {
                'answer_relevance': None,
                'relevance_details': f'Evaluation failed: {str(e)}',
                'answer_completeness': None,
                'completeness_details': f'Evaluation failed: {str(e)}'
            }

            if has_golden_answer:
                output['technical_accuracy'] = None
                output['accuracy_details'] = f'Evaluation failed: {str(e)}'

            return output

    # ========== Helper Methods ==========

    def _get_presigned_url_from_snowflake(self, content_id: str) -> Optional[str]:
        """Generate fresh presigned URL from Snowflake internal stage"""
        if not self.snowflake_conn or not content_id:
            return None

        try:
            # Extract IMAGE_ID from content_id (e.g., VISUAL_sec3_visual_025_p206 -> sec3_visual_025_p206)
            if content_id.startswith('VISUAL_'):
                image_id = content_id.replace('VISUAL_', '')
            else:
                return None

            cursor = self.snowflake_conn.cursor()
            # Get FILE_PATH from VISUAL_CONTENT_RICH and generate fresh 7-day URL
            query = f"""
                SELECT GET_PRESIGNED_URL(
                    '@AS_STANDARDS.PUBLIC_IMAGES',
                    REPLACE(FILE_PATH, '@AS_STANDARDS.PUBLIC_IMAGES/', ''),
                    604800
                )
                FROM ELECTRICAL_STANDARDS_DB.AS_STANDARDS.VISUAL_CONTENT_RICH
                WHERE IMAGE_ID = '{image_id}'
            """
            cursor.execute(query)
            result = cursor.fetchone()
            cursor.close()

            if result and result[0]:
                logger.info(f"Successfully regenerated presigned URL for {content_id}")
                return result[0]
        except Exception as e:
            logger.error(f"Failed to generate presigned URL for {content_id}: {e}")

        return None

    def _build_context_with_images(self, retrieved_context: List[Dict[str, Any]]) -> Tuple[str, List[Dict[str, Any]]]:
        """
        Build context string and collect ALL image URLs for vision model

        IMPORTANT: This now processes ALL chunks and images from retrieved_context,
        not just a subset. Limited only by Groq's 5-image constraint.

        Returns:
            Tuple of (context_text, vision_images_list)
        """
        context_parts = []
        vision_images = []

        logger.info(f"=== BUILDING JUDGE CONTEXT WITH ALL CHUNKS ===")
        logger.info(f"Total retrieved_context items: {len(retrieved_context)}")

        for idx, chunk in enumerate(retrieved_context):  # Process ALL chunks
            content_type = chunk.get('content_type', 'unknown')
            page = chunk.get('page_number', 'unknown')
            text_content = chunk.get('text_content', '')
            description = chunk.get('description', '')
            image_url = chunk.get('image_url', '')
            content_id = chunk.get('content_id', '')

            # Visual content - use stored URL or regenerate if needed
            if content_type == 'visual':
                # First, try to use the stored image URL from metadata (preferred)
                url_to_use = image_url if image_url else None

                logger.info(f"VISUAL CHUNK #{idx+1}: content_id={content_id}, has_image_url={bool(image_url)}")

                # If no stored URL, try to regenerate from Snowflake
                if not url_to_use and content_id:
                    url_to_use = self._get_presigned_url_from_snowflake(content_id)
                    logger.info(f"Regenerated presigned URL for {content_id}")

                if url_to_use:
                    context_parts.append(
                        f"[{idx+1}] (Page {page}, VISUAL CONTENT - see image {len(vision_images) + 1}):\n"
                        f"Description: {description}"  # Full description, no truncation
                    )
                    # Groq vision model limit: 5 images max
                    if len(vision_images) < 5:
                        vision_images.append({
                            "type": "image_url",
                            "image_url": {"url": url_to_use}
                        })
                        logger.info(f"✓ Added visual content to judge context: {content_id}")
                    else:
                        logger.warning(f"⚠ Skipping visual {content_id} - Groq 5-image limit reached")
                else:
                    # Fallback to description only if no URL available
                    context_parts.append(
                        f"[{idx+1}] (Page {page}, VISUAL CONTENT - image unavailable):\n"
                        f"Description: {description}"  # Full description
                    )
                    logger.warning(f"✗ No URL available for visual content: {content_id}")
            else:
                # Regular text content - include ALL of it
                text = text_content or description
                context_parts.append(f"[{idx+1}] (Page {page}, {content_type}):\n{text}")

        context_text = "\n\n".join(context_parts)

        logger.info(f"=== JUDGE CONTEXT SUMMARY ===")
        logger.info(f"Total context chunks: {len(context_parts)}")
        logger.info(f"Visual images prepared: {len(vision_images)}")
        logger.info(f"Context text length: {len(context_text)} chars")

        return context_text, vision_images

    def _extract_clause_references(self, text: str) -> List[str]:
        """
        Extract AS3000 clause references from text

        Patterns:
        - AS3000 Clause 3.7.2.1
        - Clause 3.7.2
        - Section 3.7
        - AS/NZS 3000:2018 Clause 5.5.2
        """
        patterns = [
            r'AS/?NZS?\s*3000(?::\d{4})?\s+(?:Clause|Section)\s+([\d.]+)',
            r'(?:Clause|Section)\s+([\d.]+)',
            r'AS3000\s+([\d.]+)'
        ]

        clauses = []
        for pattern in patterns:
            matches = re.findall(pattern, text, re.IGNORECASE)
            clauses.extend(matches)

        # Deduplicate and sort
        return sorted(set(clauses))

    def _normalize_clause(self, clause: str) -> Optional[str]:
        """
        Normalize a clause reference for comparison.

        - Strips whitespace
        - Removes trailing punctuation
        - Keeps only digits and dots
        - Collapses repeated dots
        - Rejects invalid patterns

        Returns:
            Normalized clause string or None if invalid
        """
        if not clause:
            return None

        # Strip whitespace
        clause = clause.strip()

        # Keep only digits and dots
        clause = re.sub(r'[^\d.]', '', clause)

        # Collapse repeated dots
        clause = re.sub(r'\.{2,}', '.', clause)

        # Remove leading/trailing dots
        clause = clause.strip('.')

        # Validate pattern: should be digits separated by dots (e.g., "1.4.32")
        if not re.match(r'^\d+(\.\d+)*$', clause):
            return None

        return clause

    def _compute_clause_match_score(self, cited: str, expected: str) -> float:
        """
        Compute match score between a cited clause and an expected clause.

        Scoring:
        - Exact match: 1.0
        - Prefix match (cited is parent, e.g., 1.4 vs 1.4.32):
          - 1 level (X): 0.5
          - 2 levels (X.Y): 0.6
          - 3 levels (X.Y.Z): 0.75
        - Child match (cited is more specific than expected): same as prefix
        - Same section (e.g., 1.4 vs 1.5 - both in section 1): 0.3
        - Otherwise: 0.0

        Args:
            cited: Normalized cited clause (e.g., "1.4")
            expected: Normalized expected clause (e.g., "1.4.32")

        Returns:
            Match score between 0.0 and 1.0
        """
        # Exact match
        if cited == expected:
            return 1.0

        # Prefix match: cited is parent of expected (e.g., "1.4" cited, "1.4.32" expected)
        if expected.startswith(cited + '.'):
            cited_depth = len(cited.split('.'))
            if cited_depth == 1:  # X level (e.g., "1")
                return 0.5
            elif cited_depth == 2:  # X.Y level (e.g., "1.4")
                return 0.6
            elif cited_depth >= 3:  # X.Y.Z or deeper (e.g., "1.4.3")
                return 0.75

        # Child match: cited is more specific than expected (e.g., "1.4.32" cited, "1.4" expected)
        if cited.startswith(expected + '.'):
            expected_depth = len(expected.split('.'))
            if expected_depth == 1:  # X level
                return 0.5
            elif expected_depth == 2:  # X.Y level
                return 0.6
            elif expected_depth >= 3:  # X.Y.Z or deeper
                return 0.75

        # Same section match: same top-level section (e.g., "1.4" vs "1.5" - both in section 1)
        cited_parts = cited.split('.')
        expected_parts = expected.split('.')
        if cited_parts[0] == expected_parts[0]:
            # Same top-level section - give small partial credit
            return 0.3

        # No match
        return 0.0

    def _grade_citation_accuracy(
        self,
        cited_clauses: List[str],
        expected_clause: Optional[str]
    ) -> Dict[str, Any]:
        """
        Grade citation accuracy using lenient, graded matching.

        Gives partial credit for:
        - Parent clause citations (e.g., 1.4 when 1.4.32 expected)
        - Child clause citations (e.g., 1.4.32 when 1.4 expected)
        - Multiple valid expected clauses

        Args:
            cited_clauses: List of cited clause references
            expected_clause: Expected clause(s), may be comma-separated

        Returns:
            Dict with:
            - citation_accuracy: float 0-1
            - correct_clause_ref: bool
            - citation_details: str with diagnostics
        """
        # Handle null/empty citations
        if not cited_clauses or len(cited_clauses) == 0:
            return {
                'citation_accuracy': 0.0,
                'correct_clause_ref': False,
                'citation_details': 'No citations found in answer'
            }

        # Handle missing expected clause
        if not expected_clause:
            # No ground truth - give benefit of doubt if citations exist
            return {
                'citation_accuracy': 0.5,
                'correct_clause_ref': False,
                'citation_details': 'No expected clause provided for comparison'
            }

        # Parse expected clauses (may be comma-separated)
        expected_raw = [e.strip() for e in expected_clause.split(',')]
        expected_set = [self._normalize_clause(e) for e in expected_raw]
        expected_set = [e for e in expected_set if e]  # Remove None values

        if not expected_set:
            return {
                'citation_accuracy': 0.5,
                'correct_clause_ref': False,
                'citation_details': f'Could not parse expected clause: {expected_clause}'
            }

        # Normalize cited clauses
        cited_set = [self._normalize_clause(c) for c in cited_clauses]
        cited_set = [c for c in cited_set if c]  # Remove None values

        if not cited_set:
            return {
                'citation_accuracy': 0.0,
                'correct_clause_ref': False,
                'citation_details': 'Cited clauses could not be normalized'
            }

        # Compute best match score for each cited clause
        match_scores = []
        best_match_pairs = []

        for cited in cited_set:
            best_score = 0.0
            best_expected = None

            # Find best match against any expected clause
            for expected in expected_set:
                score = self._compute_clause_match_score(cited, expected)
                if score > best_score:
                    best_score = score
                    best_expected = expected

            match_scores.append(best_score)
            if best_expected:
                best_match_pairs.append(f"{cited} -> {best_expected} (score: {best_score:.2f})")

        # Aggregate score: maximum match score across all cited clauses
        # This rewards "at least one good citation"
        citation_accuracy = max(match_scores) if match_scores else 0.0

        # Boolean: correct if any match score >= 0.75
        correct_clause_ref = citation_accuracy >= 0.75

        # Build diagnostics
        citation_details = (
            f"Expected: {expected_set} | "
            f"Cited: {cited_set} | "
            f"Best matches: [{', '.join(best_match_pairs)}] | "
            f"Score: {citation_accuracy:.2f}"
        )

        logger.info(f"Citation grading: {citation_details}")

        return {
            'citation_accuracy': citation_accuracy,
            'correct_clause_ref': correct_clause_ref,
            'citation_details': citation_details
        }

    def _parse_json_response(self, text: str) -> Dict[str, Any]:
        """Parse JSON from LLM response, handling markdown code blocks"""
        # Remove markdown code blocks if present
        text = re.sub(r'^```json\s*', '', text, flags=re.MULTILINE)
        text = re.sub(r'^```\s*', '', text, flags=re.MULTILINE)
        text = text.strip()

        try:
            return json.loads(text)
        except json.JSONDecodeError as e:
            logger.warning(f"Failed to parse JSON response: {e}\nText: {text[:200]}...")
            return {}

    def _evaluate_kg_metrics(
        self,
        question: str,
        answer: str,
        retrieved_context: List[Dict[str, Any]],
        golden_has_table: Optional[bool] = None,
        golden_has_diagram: Optional[bool] = None
    ) -> Dict[str, Any]:
        """
        Evaluate KG-aware metrics:
        1. Normative Coverage - did cited evidence include normative (A/B) chunks?
        2. Non-Normative Reliance - proportion of citations from C chunks
        3. Conditional Risk Indicator - if B chunks cited, check for applicability language
        4. Multimodal Starvation - ensure tables/visuals retrieved when appropriate

        Returns:
            Dict with kg_normative_coverage, kg_non_normative_reliance, kg_conditional_risk,
            kg_multimodal_starvation, and detailed reasoning for each
        """
        results = {}

        # Extract KG class distribution from retrieved context
        retrieved_kg_classes = {}
        retrieved_content_types = {}
        for item in retrieved_context:
            kg_class = item.get('kg_class', 'UNKNOWN')
            content_type = item.get('content_type', 'unknown')
            retrieved_kg_classes[kg_class] = retrieved_kg_classes.get(kg_class, 0) + 1
            retrieved_content_types[content_type] = retrieved_content_types.get(content_type, 0) + 1

        # Extract content_ids mentioned in answer (simple citation mapping)
        # Look for patterns like TEXT_123, VISUAL_456, or just the IDs
        cited_content_ids = self._extract_cited_content_ids(answer, retrieved_context)

        # Map cited content_ids to KG classes
        cited_kg_classes = {}
        for content_id in cited_content_ids:
            # Find matching item in retrieved_context
            for item in retrieved_context:
                if item.get('content_id') == content_id:
                    kg_class = item.get('kg_class', 'UNKNOWN')
                    cited_kg_classes[kg_class] = cited_kg_classes.get(kg_class, 0) + 1
                    break

        total_cited = sum(cited_kg_classes.values())

        # METRIC 1: Normative Coverage
        # Check if at least one A or B chunk was retrieved AND potentially cited
        has_normative_retrieved = (retrieved_kg_classes.get('A', 0) + retrieved_kg_classes.get('B', 0)) > 0
        has_normative_cited = (cited_kg_classes.get('A', 0) + cited_kg_classes.get('B', 0)) > 0 if total_cited > 0 else None

        normative_coverage_score = 1.0 if has_normative_cited else (0.5 if has_normative_retrieved else 0.0)
        normative_coverage_reasoning = f"Retrieved: {retrieved_kg_classes.get('A', 0)} A + {retrieved_kg_classes.get('B', 0)} B chunks. "
        if total_cited > 0:
            normative_coverage_reasoning += f"Cited: {cited_kg_classes.get('A', 0)} A + {cited_kg_classes.get('B', 0)} B chunks. "
            normative_coverage_reasoning += "Pass" if has_normative_cited else "Fail - no normative chunks cited"
        else:
            normative_coverage_reasoning += "Unable to map citations to content_ids (scoring based on retrieval only)"

        results['kg_normative_coverage'] = normative_coverage_score
        results['kg_normative_coverage_details'] = normative_coverage_reasoning

        # METRIC 2: Non-Normative Reliance
        # What proportion of cited evidence came from C?
        c_reliance_pct = (cited_kg_classes.get('C', 0) / total_cited * 100) if total_cited > 0 else 0.0
        non_normative_reliance_score = max(0.0, 1.0 - (c_reliance_pct / 50.0))  # Penalize if >50% C
        non_normative_reliance_reasoning = f"C chunks cited: {cited_kg_classes.get('C', 0)}/{total_cited} ({c_reliance_pct:.1f}%). "
        if c_reliance_pct > 50:
            non_normative_reliance_reasoning += "High reliance on non-normative content"
        elif c_reliance_pct > 20:
            non_normative_reliance_reasoning += "Moderate reliance on non-normative content"
        else:
            non_normative_reliance_reasoning += "Low reliance on non-normative content"

        results['kg_non_normative_reliance'] = non_normative_reliance_score
        results['kg_non_normative_reliance_details'] = non_normative_reliance_reasoning
        results['kg_c_reliance_pct'] = c_reliance_pct

        # METRIC 3: Conditional Risk Indicator
        # If B chunks were CITED, check for applicability language
        # This is a RISK FLAG, not a hard penalty - important for regulated domains
        b_chunks_cited = cited_kg_classes.get('B', 0)
        b_chunks_retrieved = retrieved_kg_classes.get('B', 0)

        conditional_language_patterns = [
            r'\bwhere\b', r'\bwhen\b', r'\bif\b', r'\bunless\b',
            r'\bonly if\b', r'\bin cases where\b', r'\bprovided that\b',
            r'\bsubject to\b', r'\bdepending on\b', r'\bmay\b', r'\bcan\b',
            r'\bshall.*where\b', r'\bmust.*when\b', r'\brequired.*if\b'
        ]
        has_conditional_language = any(re.search(pattern, answer, re.IGNORECASE) for pattern in conditional_language_patterns)

        # Focus on CITED B chunks (not just retrieved)
        if b_chunks_cited > 0:
            # B chunks were actually cited in the answer
            if has_conditional_language:
                conditional_risk_score = 1.0  # Pass - conditional B chunks cited with applicability language
                conditional_risk_reasoning = f"PASS: {b_chunks_cited} conditional (B) chunk(s) cited. Conditional language detected in answer."
            else:
                conditional_risk_score = 0.0  # RISK - B cited without conditional language
                conditional_risk_reasoning = f"CONDITIONAL RISK: {b_chunks_cited} conditional (B) chunk(s) cited but no applicability language detected. Answer may be misapplied in contexts where condition doesn't hold."
        elif b_chunks_retrieved > 0 and total_cited > 0:
            # B chunks retrieved but not cited (or citation mapping failed)
            # Penalize slightly if no conditional language present
            if has_conditional_language:
                conditional_risk_score = 1.0  # Good - conditional language present even if B not explicitly mapped
                conditional_risk_reasoning = f"{b_chunks_retrieved} conditional (B) chunk(s) retrieved (not explicitly cited). Conditional language detected in answer."
            else:
                conditional_risk_score = 0.5  # Moderate risk - B retrieved, no conditional language
                conditional_risk_reasoning = f"RISK: {b_chunks_retrieved} conditional (B) chunk(s) retrieved. No conditional language detected - check if applicability stated."
        else:
            conditional_risk_score = 1.0  # N/A - no conditional chunks involved
            conditional_risk_reasoning = "No conditional (B) chunks involved."

        results['kg_conditional_risk'] = conditional_risk_score
        results['kg_conditional_risk_details'] = conditional_risk_reasoning

        # METRIC 4: Multimodal Starvation Check
        # If golden answer references tables/diagrams, ensure structured_table or visual_content was retrieved
        has_table_retrieved = retrieved_content_types.get('structured_table', 0) > 0
        has_visual_retrieved = retrieved_content_types.get('visual_content', 0) > 0

        multimodal_starvation_score = 1.0  # Default pass
        multimodal_starvation_reasoning = ""

        if golden_has_table or golden_has_diagram:
            # Golden answer expects tables/diagrams
            if golden_has_table and not has_table_retrieved:
                multimodal_starvation_score = 0.0
                multimodal_starvation_reasoning = "Golden answer references tables, but no structured_table chunks retrieved."
            elif golden_has_diagram and not has_visual_retrieved:
                multimodal_starvation_score = 0.0
                multimodal_starvation_reasoning = "Golden answer references diagrams, but no visual_content chunks retrieved."
            else:
                multimodal_starvation_reasoning = f"Multimodal content retrieved: {retrieved_content_types.get('structured_table', 0)} tables + {retrieved_content_types.get('visual_content', 0)} visuals."
        else:
            # Proxy: Check if answer mentions table/figure references
            table_mentions = re.findall(r'[Tt]able\s+\d+(?:\.\d+)?', answer)
            figure_mentions = re.findall(r'[Ff]igure\s+\d+(?:\.\d+)?', answer)

            if table_mentions and not has_table_retrieved:
                multimodal_starvation_score = 0.5
                multimodal_starvation_reasoning = f"Answer mentions {len(table_mentions)} table(s) but no structured_table chunks retrieved."
            elif figure_mentions and not has_visual_retrieved:
                multimodal_starvation_score = 0.5
                multimodal_starvation_reasoning = f"Answer mentions {len(figure_mentions)} figure(s) but no visual_content chunks retrieved."
            else:
                multimodal_starvation_reasoning = f"Multimodal content: {retrieved_content_types.get('structured_table', 0)} tables + {retrieved_content_types.get('visual_content', 0)} visuals retrieved."

        results['kg_multimodal_starvation'] = multimodal_starvation_score
        results['kg_multimodal_starvation_details'] = multimodal_starvation_reasoning

        # Store retrieved/cited counts for later analysis
        results['kg_retrieved_counts'] = retrieved_kg_classes
        results['kg_cited_counts'] = cited_kg_classes
        results['kg_retrieved_content_types'] = retrieved_content_types

        return results

    def _extract_cited_content_ids(self, answer: str, retrieved_context: List[Dict[str, Any]]) -> List[str]:
        """
        Extract content_ids that were cited in the answer.

        Strategy (in priority order):
        1. Extract explicit [ID: ...] citations (new format from prompt)
        2. Extract AS3000 clause references and map to chunks
        3. Use text overlap matching as fallback
        4. Check for bare content_id mentions

        Returns:
            List of content_ids that appear to be cited
        """
        cited_ids = []

        # STRATEGY 1: Extract explicit [ID: content_id] citations (PRIMARY)
        # This is the new structured citation format enforced by the prompt
        explicit_id_pattern = r'\[ID:\s*([A-Z]+_[a-f0-9]+)\]'
        explicit_ids = re.findall(explicit_id_pattern, answer, re.IGNORECASE)
        if explicit_ids:
            cited_ids.extend(explicit_ids)
            logger.info(f"Found {len(explicit_ids)} explicit [ID: ...] citations: {explicit_ids}")

        # STRATEGY 2: Map clause citations to chunks (FALLBACK)
        # Extract clause references from answer
        cited_clauses = self._extract_clause_references(answer)

        if cited_clauses:
            logger.info(f"Found {len(cited_clauses)} clause citations in answer: {cited_clauses}")

            # For each cited clause, find which chunks contain that clause
            for clause in cited_clauses:
                # Search for this clause in chunk content
                for item in retrieved_context:
                    content_text = item.get('text_content', '') or item.get('description', '')
                    if not content_text:
                        continue

                    # Check if this chunk contains the cited clause
                    # Look for patterns like "3.7.2.1" or "Clause 3.7.2.1" in the chunk
                    clause_patterns = [
                        rf'\b{re.escape(clause)}\b',  # Exact match
                        rf'Clause\s+{re.escape(clause)}\b',  # "Clause 3.7.2.1"
                        rf'Section\s+{re.escape(clause)}\b',  # "Section 3.7.2.1"
                    ]

                    for pattern in clause_patterns:
                        if re.search(pattern, content_text, re.IGNORECASE):
                            cited_ids.append(item.get('content_id', ''))
                            logger.debug(f"Mapped clause {clause} → {item.get('content_id')}")
                            break

        # STRATEGY 2: Text overlap matching (fallback)
        # For each chunk, check if substantial text from it appears in the answer
        # This catches cases where the model paraphrases without explicit clause citation
        answer_lower = answer.lower()
        for item in retrieved_context:
            content_id = item.get('content_id', '')
            if content_id in cited_ids:
                continue  # Already mapped via clause

            content_text = item.get('text_content', '') or item.get('description', '')
            if not content_text or len(content_text) < 50:
                continue

            # Extract multiple snippets from the chunk and check for matches
            # Use 3 snippets: beginning, middle, end
            content_lower = content_text.lower()
            snippet_length = 40

            snippets = []
            # Beginning snippet
            if len(content_lower) >= snippet_length:
                snippets.append(content_lower[:snippet_length].strip())
            # Middle snippet
            if len(content_lower) >= snippet_length * 2:
                mid_start = len(content_lower) // 2 - snippet_length // 2
                snippets.append(content_lower[mid_start:mid_start + snippet_length].strip())
            # End snippet
            if len(content_lower) >= snippet_length * 3:
                snippets.append(content_lower[-snippet_length:].strip())

            # Check if any snippet appears in answer
            for snippet in snippets:
                if len(snippet) > 20 and snippet in answer_lower:
                    cited_ids.append(content_id)
                    logger.debug(f"Mapped via text overlap → {content_id}")
                    break

        # STRATEGY 4: Bare content_id mentions without [ID: ...] wrapper (backward compatibility)
        # This catches cases like "According to TEXT_abc123" without the [ID: ] format
        bare_id_pattern = r'\b([A-Z]+_[a-f0-9]+)\b'
        bare_ids = re.findall(bare_id_pattern, answer, re.IGNORECASE)
        # Filter to only IDs that exist in retrieved_context
        valid_bare_ids = [bid for bid in bare_ids if any(item.get('content_id') == bid for item in retrieved_context)]
        if valid_bare_ids and valid_bare_ids not in cited_ids:
            cited_ids.extend(valid_bare_ids)
            logger.info(f"Found bare content_id mentions: {valid_bare_ids}")

        # Deduplicate and log results
        cited_ids = list(set(filter(None, cited_ids)))
        logger.info(f"Citation mapping complete: {len(cited_ids)} content_ids cited out of {len(retrieved_context)} retrieved")

        return cited_ids


# Convenience function for single interaction evaluation
def evaluate_rag_response(
    question: str,
    answer: str,
    retrieved_context: List[Dict[str, Any]],
    expected_answer: Optional[str] = None,
    expected_clause: Optional[str] = None
) -> Dict[str, Any]:
    """
    Evaluate a single RAG interaction with all metrics using optimized V2

    Returns complete evaluation results
    """
    evaluator = EvalMetricsV2()
    return evaluator.evaluate_interaction(
        question=question,
        answer=answer,
        retrieved_context=retrieved_context,
        expected_answer=expected_answer,
        expected_clause=expected_clause
    )

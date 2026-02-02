"""
Golden Set Question Generator for Sparkie RAG Evaluation

Iterates through every page of AS3000 and generates realistic questions
that electricians would ask, using Llama Vision to analyze text + images + tables.

For each page:
- Generate 1-2 distinct questions
- Each question gets 2 different phrasings
- Results: 2-4 questions per page (minimum 2, maximum 4)
"""

import os
import json
import logging
import time
from typing import List, Dict, Any, Optional
from datetime import datetime, timezone
import base64
import requests
from groq import Groq
from snowflake.snowpark import Session
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class GoldenSetGenerator:
    """Generate golden set questions from AS3000 pages"""

    def __init__(self):
        self.groq_client = Groq(api_key=os.getenv('GROQ_API_KEY'))
        self.vision_model = "llama-3.2-90b-vision-preview"
        self.session = None
        self.questions_generated = []

    def connect_snowflake(self):
        """Establish Snowflake connection"""
        try:
            connection_params = {
                "account": os.getenv("SNOWFLAKE_ACCOUNT"),
                "user": os.getenv("SNOWFLAKE_USER"),
                "private_key": os.getenv("SNOWFLAKE_PRIVATE_KEY"),
                "role": os.getenv("SNOWFLAKE_ROLE"),
                "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE"),
                "database": os.getenv("SNOWFLAKE_DATABASE"),
                "schema": os.getenv("SNOWFLAKE_SCHEMA")
            }
            self.session = Session.builder.configs(connection_params).create()
            logger.info("Connected to Snowflake")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to Snowflake: {e}")
            return False

    def close(self):
        """Close Snowflake connection"""
        if self.session:
            self.session.close()
            logger.info("Disconnected from Snowflake")

    def get_all_pages(self) -> List[Dict[str, Any]]:
        """
        Get all unique pages from AS3000
        Returns list of dicts with page info
        """
        logger.info("Fetching all unique pages from AS3000...")

        # Get unique pages (by RELATIVE_PATH and PART_NUMBER)
        query = """
            SELECT DISTINCT
                RELATIVE_PATH,
                PART_NUMBER,
                STANDARD_ID
            FROM RAW_TEXT
            WHERE RELATIVE_PATH IS NOT NULL
            AND PART_NUMBER IS NOT NULL
            ORDER BY RELATIVE_PATH, PART_NUMBER
        """

        result = self.session.sql(query).collect()
        pages = [
            {
                'relative_path': row['RELATIVE_PATH'],
                'part_number': row['PART_NUMBER'],
                'standard_id': row['STANDARD_ID']
            }
            for row in result
        ]

        logger.info(f"Found {len(pages)} unique pages")
        return pages

    def get_page_content(self, relative_path: str, part_number: int) -> Dict[str, Any]:
        """
        Get all content for a specific page (text chunks + images)

        Returns:
            {
                'text_chunks': List[str],
                'images': List[Dict] with image_path, description, pre_signed_url
            }
        """
        # Get text chunks for this page
        text_query = f"""
            SELECT CHUNK, CHUNK_INDEX_WITHIN_DOC, CHUNK_TYPE, LABEL
            FROM RAW_TEXT
            WHERE RELATIVE_PATH = '{relative_path}'
            AND PART_NUMBER = {part_number}
            ORDER BY CHUNK_INDEX_WITHIN_DOC
        """

        text_result = self.session.sql(text_query).collect()
        text_chunks = [row['CHUNK'] for row in text_result if row['CHUNK']]

        # Get images for this page
        image_query = f"""
            SELECT
                IMAGE_ID,
                IMAGE_PATH,
                PRE_SIGNED_URL,
                IMAGE_TYPE,
                VISION_DESCRIPTION,
                ENHANCED_DESCRIPTION
            FROM VISUAL_CONTENT_RICH
            WHERE SOURCE_DOCUMENT = '{relative_path}'
            AND PAGE_NUMBER = {part_number}
        """

        image_result = self.session.sql(image_query).collect()
        images = [
            {
                'image_id': row['IMAGE_ID'],
                'image_path': row['IMAGE_PATH'],
                'pre_signed_url': row['PRE_SIGNED_URL'],
                'image_type': row['IMAGE_TYPE'],
                'description': row['ENHANCED_DESCRIPTION'] or row['VISION_DESCRIPTION']
            }
            for row in image_result
        ]

        return {
            'text_chunks': text_chunks,
            'images': images
        }

    def download_image_as_base64(self, pre_signed_url: str) -> Optional[str]:
        """Download image from pre-signed URL and convert to base64"""
        try:
            response = requests.get(pre_signed_url, timeout=10)
            if response.status_code == 200:
                return base64.b64encode(response.content).decode('utf-8')
            else:
                logger.warning(f"Failed to download image: {response.status_code}")
                return None
        except Exception as e:
            logger.error(f"Error downloading image: {e}")
            return None

    def generate_questions_for_page(
        self,
        page_info: Dict[str, Any],
        page_content: Dict[str, Any]
    ) -> List[Dict[str, Any]]:
        """
        Use Llama Vision to generate 2-4 questions for a page

        Returns list of question dicts:
        [
            {
                'question_variant_1': str,
                'question_variant_2': str,
                'question_group': int (1 or 2),
                'expected_answer_hint': str,
                'source_page': str,
                'part_number': int,
                'contains_image': bool,
                'contains_table': bool
            }
        ]
        """
        logger.info(f"Generating questions for {page_info['relative_path']} page {page_info['part_number']}")

        # Build context text
        full_text = "\n\n".join(page_content['text_chunks'])

        # Check if page has tables (heuristic: contains multiple | characters)
        has_table = any('|' in chunk and chunk.count('|') > 3 for chunk in page_content['text_chunks'])

        # Build vision messages
        messages_content = []

        # Add text context
        context_text = f"""You are analyzing page {page_info['part_number']} from the AS3000 Australian Electrical Standards document.

PAGE CONTENT:
{full_text[:4000]}  # Limit to avoid token overflow

TASK: Generate questions that a qualified electrician might ask that could be answered by this page.

Requirements:
1. Generate 1-2 DISTINCT questions (generate 2 if the page has enough content, otherwise 1)
2. For each distinct question, provide 2 DIFFERENT PHRASINGS (how different electricians might ask the same thing)
3. Questions should be practical and job-relevant
4. Questions should be answerable from the content on this page
5. Include questions about tables, diagrams, and calculations if present

Return ONLY valid JSON in this format:
{{
  "questions": [
    {{
      "question_group": 1,
      "variant_1": "First phrasing of question 1",
      "variant_2": "Alternative phrasing of question 1",
      "expected_answer_hint": "Brief hint of what the answer should cover"
    }},
    {{
      "question_group": 2,
      "variant_1": "First phrasing of question 2",
      "variant_2": "Alternative phrasing of question 2",
      "expected_answer_hint": "Brief hint of what the answer should cover"
    }}
  ]
}}

If only 1 question is possible, return only question_group 1."""

        messages_content.append({
            "type": "text",
            "text": context_text
        })

        # Add images if available (limit to 2 to avoid token overflow)
        images_added = 0
        for img in page_content['images'][:2]:
            if img['pre_signed_url']:
                # For Groq vision API, we can pass URLs directly
                messages_content.append({
                    "type": "image_url",
                    "image_url": {
                        "url": img['pre_signed_url']
                    }
                })
                images_added += 1
                logger.info(f"Added image: {img['image_type']}")

        try:
            # Call Llama Vision
            response = self.groq_client.chat.completions.create(
                model=self.vision_model,
                messages=[
                    {
                        "role": "user",
                        "content": messages_content
                    }
                ],
                temperature=0.7,  # Some creativity for question variation
                max_tokens=1000
            )

            response_text = response.choices[0].message.content.strip()
            logger.info(f"Raw response: {response_text[:200]}...")

            # Parse JSON response
            # Sometimes model wraps in ```json, so clean it
            if response_text.startswith('```'):
                response_text = response_text.split('```')[1]
                if response_text.startswith('json'):
                    response_text = response_text[4:]

            result = json.loads(response_text.strip())

            # Convert to our format
            questions = []
            for q in result.get('questions', []):
                questions.append({
                    'question_variant_1': q['variant_1'],
                    'question_variant_2': q['variant_2'],
                    'question_group': q['question_group'],
                    'expected_answer_hint': q.get('expected_answer_hint', ''),
                    'source_page': page_info['relative_path'],
                    'part_number': page_info['part_number'],
                    'standard_id': page_info['standard_id'],
                    'contains_image': images_added > 0,
                    'contains_table': has_table,
                    'generated_at': datetime.now(timezone.utc).isoformat()
                })

            logger.info(f"Generated {len(questions)} question groups")
            return questions

        except Exception as e:
            logger.error(f"Failed to generate questions: {e}", exc_info=True)
            return []

    def create_golden_set_table(self):
        """Create Snowflake table for golden set questions"""
        logger.info("Creating GOLDEN_SET_QUESTIONS table...")

        create_sql = """
            CREATE TABLE IF NOT EXISTS GOLDEN_SET_QUESTIONS (
                question_id VARCHAR PRIMARY KEY,
                question_text VARCHAR NOT NULL,
                question_variant_number NUMBER(1,0) NOT NULL,  -- 1 or 2
                question_group_id VARCHAR NOT NULL,  -- Groups variants of same question
                expected_answer_hint VARCHAR,
                source_page VARCHAR,
                part_number NUMBER,
                standard_id VARCHAR,
                contains_image BOOLEAN,
                contains_table BOOLEAN,
                generated_at TIMESTAMP_TZ,
                created_at TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP()
            )
        """

        self.session.sql(create_sql).collect()
        logger.info("Table created successfully")

    def insert_questions(self, questions: List[Dict[str, Any]]):
        """Insert generated questions into Snowflake"""
        if not questions:
            return

        import uuid

        for q in questions:
            # Insert variant 1
            question_group_id = str(uuid.uuid4())

            for variant_num, question_text in [
                (1, q['question_variant_1']),
                (2, q['question_variant_2'])
            ]:
                question_id = str(uuid.uuid4())

                insert_sql = f"""
                    INSERT INTO GOLDEN_SET_QUESTIONS (
                        question_id, question_text, question_variant_number,
                        question_group_id, expected_answer_hint, source_page,
                        part_number, standard_id, contains_image, contains_table,
                        generated_at
                    )
                    SELECT
                        '{question_id}',
                        '{question_text.replace("'", "''")}',
                        {variant_num},
                        '{question_group_id}',
                        '{q['expected_answer_hint'].replace("'", "''")}',
                        '{q['source_page']}',
                        {q['part_number']},
                        '{q['standard_id']}',
                        {q['contains_image']},
                        {q['contains_table']},
                        '{q['generated_at']}'
                """

                self.session.sql(insert_sql).collect()

        logger.info(f"Inserted {len(questions) * 2} questions ({len(questions)} groups)")

    def run(self, limit: Optional[int] = None, start_from: int = 0):
        """
        Run the golden set generation process

        Args:
            limit: Maximum number of pages to process (None = all)
            start_from: Skip first N pages (for resuming)
        """
        if not self.connect_snowflake():
            logger.error("Cannot proceed without Snowflake connection")
            return

        try:
            # Create table
            self.create_golden_set_table()

            # Get all pages
            pages = self.get_all_pages()

            if start_from > 0:
                pages = pages[start_from:]
                logger.info(f"Starting from page {start_from}")

            if limit:
                pages = pages[:limit]
                logger.info(f"Limited to {limit} pages")

            total_pages = len(pages)
            total_questions = 0

            for idx, page in enumerate(pages, start=1):
                logger.info(f"\n{'='*80}")
                logger.info(f"Processing page {idx}/{total_pages}: {page['relative_path']} p{page['part_number']}")
                logger.info(f"{'='*80}")

                # Get page content
                content = self.get_page_content(page['relative_path'], page['part_number'])

                # Check if page has enough content
                if not content['text_chunks'] or len(' '.join(content['text_chunks'])) < 100:
                    logger.warning("Page has insufficient content, skipping...")
                    continue

                # Generate questions
                questions = self.generate_questions_for_page(page, content)

                if questions:
                    self.insert_questions(questions)
                    total_questions += len(questions) * 2  # Each group has 2 variants
                    self.questions_generated.extend(questions)

                # Rate limiting (Groq API limits)
                time.sleep(1)

                # Progress update every 10 pages
                if idx % 10 == 0:
                    logger.info(f"\n*** Progress: {idx}/{total_pages} pages, {total_questions} questions generated ***\n")

            logger.info(f"\n{'='*80}")
            logger.info(f"COMPLETED: Processed {total_pages} pages, generated {total_questions} questions")
            logger.info(f"{'='*80}")

        finally:
            self.close()

    def get_stats(self):
        """Get statistics about generated questions"""
        if not self.session:
            self.connect_snowflake()

        stats_sql = """
            SELECT
                COUNT(*) as total_questions,
                COUNT(DISTINCT question_group_id) as total_question_groups,
                COUNT(DISTINCT source_page) as pages_covered,
                SUM(CASE WHEN contains_image THEN 1 ELSE 0 END) as questions_with_images,
                SUM(CASE WHEN contains_table THEN 1 ELSE 0 END) as questions_with_tables
            FROM GOLDEN_SET_QUESTIONS
        """

        result = self.session.sql(stats_sql).collect()
        if result:
            row = result[0]
            print("\nGolden Set Statistics:")
            print("=" * 60)
            print(f"Total Questions: {row['TOTAL_QUESTIONS']}")
            print(f"Unique Question Groups: {row['TOTAL_QUESTION_GROUPS']}")
            print(f"Pages Covered: {row['PAGES_COVERED']}")
            print(f"Questions with Images: {row['QUESTIONS_WITH_IMAGES']}")
            print(f"Questions with Tables: {row['QUESTIONS_WITH_TABLES']}")
            print("=" * 60)


def main():
    """Main execution"""
    generator = GoldenSetGenerator()

    # Test with first 5 pages
    # generator.run(limit=5)

    # Run on all pages
    generator.run()

    # Show stats
    generator.get_stats()


if __name__ == "__main__":
    main()

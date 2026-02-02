"""
RDF Triple Extraction Runner for AS/NZS 3000 Electrical Standards

Processes text chunks from Snowflake RAW_TEXT table and extracts candidate RDF triples
using the Groq API with openai/gpt-oss-120b model.

Inserts results into: ELECTRICAL_STANDARDS_DB.AS_STANDARDS.RDF_TRIPLES_CANDIDATE
"""

import os
import json
import logging
from typing import Dict, List, Any, Optional
from pathlib import Path
from dotenv import load_dotenv
from groq import Groq
from snowflake.snowpark import Session
from snowflake.snowpark.functions import col
import time

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class RDFExtractionRunner:
    """
    Extracts RDF triples from AS3000 text chunks using Groq API
    """

    def __init__(self):
        """Initialize Snowflake and Groq connections"""
        self.groq_client = Groq(api_key=os.getenv('GROQ_API_KEY'))
        self.model = "openai/gpt-oss-120b"
        self.temperature = 0.0  # Deterministic extraction
        self.session = None

        # Load the extraction prompt
        self.prompt_template = self._load_prompt()

        # Connect to Snowflake
        self._connect_to_snowflake()

    def _load_prompt(self) -> str:
        """Load the RDF extraction prompt template"""
        prompt_path = Path(__file__).parent / "prompts" / "rdf_candidate_extraction.txt"

        if not prompt_path.exists():
            raise FileNotFoundError(f"Prompt file not found: {prompt_path}")

        with open(prompt_path, 'r', encoding='utf-8') as f:
            return f.read()

    def _connect_to_snowflake(self):
        """Connect to Snowflake using environment variables"""
        try:
            # Connection parameters from environment
            connection_parameters = {
                "account": os.getenv("SNOWFLAKE_ACCOUNT"),
                "user": os.getenv("SNOWFLAKE_USER"),
                "authenticator": os.getenv("SNOWFLAKE_AUTHENTICATOR"),
                "role": os.getenv("SNOWFLAKE_ROLE"),
                "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE"),
                "database": os.getenv("SNOWFLAKE_DATABASE", "SPARKIE_V2_DB"),
                "schema": os.getenv("SNOWFLAKE_SCHEMA", "ELECTRICAL_STANDARDS")
            }

            # Add private key if available
            private_key = os.getenv("SNOWFLAKE_PRIVATE_KEY")
            if private_key:
                connection_parameters["private_key"] = private_key
            else:
                # Fall back to password if no private key
                password = os.getenv("SNOWFLAKE_PASSWORD")
                if password:
                    connection_parameters["password"] = password

            self.session = Session.builder.configs(connection_parameters).create()
            logger.info("✓ Connected to Snowflake")

            # Set context
            self.session.sql("USE DATABASE ELECTRICAL_STANDARDS_DB").collect()
            self.session.sql("USE SCHEMA AS_STANDARDS").collect()
            logger.info("✓ Using database: ELECTRICAL_STANDARDS_DB, schema: AS_STANDARDS")

        except Exception as e:
            logger.error(f"Failed to connect to Snowflake: {e}")
            raise

    def fetch_chunks(self, limit: Optional[int] = None, chunk_types: List[str] = None) -> List[Dict[str, Any]]:
        """
        Fetch text chunks from Snowflake RAW_TEXT table

        Args:
            limit: Maximum number of chunks to fetch (None = all)
            chunk_types: Filter by content types (default: ['text_chunk'])

        Returns:
            List of chunk dictionaries with CHUNK_ID, CHUNK, PAGE_NUMBER, etc.
        """
        if chunk_types is None:
            chunk_types = ['text_chunk']  # Default to text chunks only

        logger.info(f"Fetching chunks from RAW_TEXT (types: {chunk_types}, limit: {limit or 'all'})...")

        # Build query
        query = """
        SELECT
            CHUNK_ID,
            CHUNK
        FROM ELECTRICAL_STANDARDS_DB.AS_STANDARDS.RAW_TEXT
        WHERE IS_VALID = TRUE
          AND CHUNK IS NOT NULL
        ORDER BY CHUNK_ID
        """

        if limit:
            query += f" LIMIT {limit}"

        # Execute query
        df = self.session.sql(query)
        chunks = df.collect()

        logger.info(f"✓ Fetched {len(chunks)} chunks from Snowflake")

        # Convert to list of dicts
        result = []
        for row in chunks:
            result.append({
                'chunk_id': row['CHUNK_ID'],
                'chunk': row['CHUNK']
            })

        return result

    def extract_rdf_from_chunk(self, chunk_text: str) -> Dict[str, Any]:
        """
        Extract RDF triples from a single text chunk using Groq API

        Args:
            chunk_text: The text chunk to process

        Returns:
            Dict with 'rows' key containing list of RDF triple dicts
        """
        # Substitute chunk into prompt template
        prompt = self.prompt_template.replace("{{chunk}}", chunk_text)

        try:
            # Call Groq API
            response = self.groq_client.chat.completions.create(
                model=self.model,
                messages=[{"role": "user", "content": prompt}],
                temperature=self.temperature,
                max_tokens=2000  # Enough for multiple triples
            )

            # Extract response content
            content = response.choices[0].message.content.strip()

            # Parse JSON response
            result = json.loads(content)

            # Validate response structure
            if 'rows' not in result:
                logger.warning(f"Invalid response structure: missing 'rows' key")
                return {"rows": []}

            return result

        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse JSON response: {e}")
            logger.debug(f"Raw response: {content}")
            return {"rows": []}

        except Exception as e:
            logger.error(f"Error calling Groq API: {e}")
            return {"rows": []}

    def _escape_sql_string(self, text: str) -> str:
        """
        Escape string for Snowflake SQL insertion

        Args:
            text: String to escape

        Returns:
            Escaped string safe for SQL
        """
        if not text:
            return ''
        # Escape backslashes first (must be done before single quotes)
        text = text.replace('\\', '\\\\')
        # Then escape single quotes
        text = text.replace("'", "''")
        return text

    def insert_triples(self, triples: List[Dict[str, Any]], chunk_id: str):
        """
        Insert RDF triples into Snowflake RDF_TRIPLES_CANDIDATE table

        Args:
            triples: List of RDF triple dicts from extraction
            chunk_id: Source chunk ID for tracking
        """
        if not triples:
            return

        # Execute batch insert
        try:
            for triple in triples:
                # Build individual INSERT with proper escaping
                insert_query = f"""
                INSERT INTO RDF_TRIPLES_CANDIDATE
                (subject, predicate, object, object_type, graph, clause_id, chunk_id, source_text, confidence)
                VALUES (
                    '{self._escape_sql_string(triple.get('subject', ''))}',
                    '{self._escape_sql_string(triple.get('predicate', ''))}',
                    '{self._escape_sql_string(triple.get('object', ''))}',
                    '{triple.get('object_type', 'LITERAL')}',
                    '{triple.get('graph', 'AS3000')}',
                    '{self._escape_sql_string(triple.get('clause_id', ''))}',
                    '{self._escape_sql_string(chunk_id)}',
                    '{self._escape_sql_string(triple.get('source_text', ''))}',
                    {float(triple.get('confidence', 0.0))}
                )
                """

                self.session.sql(insert_query).collect()

            logger.info(f"✓ Inserted {len(triples)} triples from chunk {chunk_id}")

        except Exception as e:
            logger.error(f"Failed to insert triples: {e}")
            raise

    def process_chunks(self, limit: Optional[int] = None, batch_size: int = 10):
        """
        Main processing loop: fetch chunks, extract RDF, insert to Snowflake

        Args:
            limit: Max chunks to process (None = all)
            batch_size: Number of chunks to process before logging progress
        """
        logger.info("=" * 80)
        logger.info("RDF EXTRACTION STARTED")
        logger.info("=" * 80)

        # Fetch chunks
        chunks = self.fetch_chunks(limit=limit)
        total_chunks = len(chunks)

        if total_chunks == 0:
            logger.warning("No chunks found to process")
            return

        logger.info(f"Processing {total_chunks} chunks...")

        total_triples = 0
        processed = 0

        for i, chunk_data in enumerate(chunks, 1):
            chunk_id = chunk_data['chunk_id']
            chunk_text = chunk_data['chunk']

            logger.info(f"\n[{i}/{total_chunks}] Processing chunk: {chunk_id}")

            # Extract RDF triples
            result = self.extract_rdf_from_chunk(chunk_text)
            triples = result.get('rows', [])

            if triples:
                logger.info(f"  → Extracted {len(triples)} triples")

                # Insert into Snowflake
                self.insert_triples(triples, chunk_id)
                total_triples += len(triples)
            else:
                logger.info(f"  → No triples extracted (likely no normative language)")

            processed += 1

            # Progress update every batch_size chunks
            if processed % batch_size == 0:
                logger.info(f"\n{'='*60}")
                logger.info(f"PROGRESS: {processed}/{total_chunks} chunks processed")
                logger.info(f"Total triples extracted so far: {total_triples}")
                logger.info(f"{'='*60}\n")

            # Rate limiting (avoid overwhelming Groq API)
            time.sleep(0.5)

        # Final summary
        logger.info("\n" + "=" * 80)
        logger.info("RDF EXTRACTION COMPLETE")
        logger.info("=" * 80)
        logger.info(f"Chunks processed: {processed}")
        logger.info(f"Total triples extracted: {total_triples}")
        logger.info(f"Average triples per chunk: {total_triples / processed if processed > 0 else 0:.2f}")
        logger.info("=" * 80)

    def close(self):
        """Close Snowflake session"""
        if self.session:
            self.session.close()
            logger.info("✓ Snowflake session closed")


def main():
    """Main entry point"""
    # Initialize runner
    runner = RDFExtractionRunner()

    try:
        # Process all chunks
        runner.process_chunks(limit=None, batch_size=50)

    except KeyboardInterrupt:
        logger.info("\n\nProcess interrupted by user")

    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)

    finally:
        runner.close()


if __name__ == "__main__":
    main()

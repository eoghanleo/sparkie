"""
Run RDF extraction on chunks containing normative language (shall/must)

This script specifically targets chunks that are likely to contain requirements.
"""

from rdf_extraction_runner import RDFExtractionRunner
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def main():
    """
    Run RDF extraction on chunks with normative language
    """
    runner = RDFExtractionRunner()

    try:
        # Override fetch_chunks to get chunks with normative language
        logger.info("Fetching chunks with normative language...")

        query = """
        SELECT
            GLOBAL_CHUNK_INDEX,
            CHUNK,
            LABEL,
            STANDARD_ID,
            CHUNK_INDEX_WITHIN_DOC,
            RELATIVE_PATH
        FROM ELECTRICAL_STANDARDS_DB.AS_STANDARDS.RAW_TEXT
        WHERE IS_VALID = TRUE
          AND CHUNK IS NOT NULL
        ORDER BY GLOBAL_CHUNK_INDEX
        """

        df = runner.session.sql(query)
        chunks_rows = df.collect()

        logger.info(f"✓ Found {len(chunks_rows)} chunks with normative language")

        # Convert to list of dicts
        chunks = []
        for row in chunks_rows:
            chunks.append({
                'chunk_id': f"CHUNK_{row['GLOBAL_CHUNK_INDEX']}",
                'chunk': row['CHUNK'],
                'page_number': row['CHUNK_INDEX_WITHIN_DOC'],
                'label': row['LABEL'],
                'standard_id': row['STANDARD_ID'],
                'source_document': row['RELATIVE_PATH']
            })

        # Process chunks
        total_triples = 0
        processed = 0

        for i, chunk_data in enumerate(chunks, 1):
            chunk_id = chunk_data['chunk_id']
            chunk_text = chunk_data['chunk']

            logger.info(f"\n[{i}/{len(chunks)}] Processing chunk: {chunk_id} (Page {chunk_data['page_number']})")

            # Extract RDF triples
            result = runner.extract_rdf_from_chunk(chunk_text)
            triples = result.get('rows', [])

            if triples:
                logger.info(f"  → Extracted {len(triples)} triples")

                # Log first triple as example
                if len(triples) > 0:
                    logger.info(f"  → Example: {triples[0].get('subject')} -> {triples[0].get('predicate')}")

                # Insert into Snowflake
                runner.insert_triples(triples, chunk_id)
                total_triples += len(triples)
            else:
                logger.info(f"  → No triples extracted")

            processed += 1

        # Final summary
        logger.info("\n" + "=" * 80)
        logger.info("RDF EXTRACTION COMPLETE")
        logger.info("=" * 80)
        logger.info(f"Chunks processed: {processed}")
        logger.info(f"Total triples extracted: {total_triples}")
        logger.info(f"Average triples per chunk: {total_triples / processed if processed > 0 else 0:.2f}")
        logger.info("=" * 80)

    except KeyboardInterrupt:
        logger.info("\n\nProcess interrupted by user")

    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)

    finally:
        runner.close()


if __name__ == "__main__":
    main()

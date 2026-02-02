#!/usr/bin/env python3
"""
Snowflake Semantic Mapping Loader
Loads enhanced labels with Australian electrician terminology into RAW_TEXT table
"""

import pandas as pd
import os
import time
from datetime import datetime
import logging
from snowflake.snowpark.context import get_active_session
from snowflake.snowpark import Session
from dotenv import load_dotenv
import glob

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

class SnowflakeSemanticLoader:
    def __init__(self):
        self.session = None
        self._connect_to_snowflake()

    def _connect_to_snowflake(self):
        """Connect to Snowflake using environment variables."""
        try:
            # Try to get active session first (if running in Snowflake)
            self.session = get_active_session()
            logging.info("Using active Snowflake session")
        except:
            # Create new session with credentials
            connection_parameters = {
                "account": os.getenv("SNOWFLAKE_ACCOUNT"),
                "user": os.getenv("SNOWFLAKE_USER"),
                "authenticator": os.getenv("SNOWFLAKE_AUTHENTICATOR"),
                "private_key": os.getenv("SNOWFLAKE_PRIVATE_KEY"),
                "role": os.getenv("SNOWFLAKE_ROLE"),
                "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE"),
                "database": os.getenv("SNOWFLAKE_DATABASE"),
                "schema": os.getenv("SNOWFLAKE_SCHEMA")
            }
            self.session = Session.builder.configs(connection_parameters).create()
            logging.info("Created new Snowflake session")

        # Set up warehouse and session settings
        self.session.sql("USE WAREHOUSE ELECTRICAL_RAG_WH").collect()
        self.session.sql("USE DATABASE ELECTRICAL_STANDARDS_DB").collect()
        self.session.sql("USE SCHEMA AS_STANDARDS").collect()
        self.session.sql("ALTER SESSION SET USE_CACHED_RESULT = TRUE").collect()
        self.session.sql("ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = 600").collect()
        logging.info("Snowflake session configured")

    def load_progress_files(self):
        """Load all semantic mapping progress files and combine them."""
        logging.info("Loading semantic mapping progress files...")

        # Find all progress files
        progress_files = sorted(glob.glob('semantic_mapping_progress_*.csv'))

        if not progress_files:
            logging.error("No progress files found!")
            return None

        logging.info(f"Found {len(progress_files)} progress files")

        # Load and combine all files
        all_data = []
        for file in progress_files:
            try:
                df = pd.read_csv(file)
                all_data.append(df)
                logging.info(f"Loaded {len(df)} records from {file}")
            except Exception as e:
                logging.error(f"Error loading {file}: {e}")

        if not all_data:
            logging.error("No data loaded from progress files!")
            return None

        # Combine all dataframes
        combined_df = pd.concat(all_data, ignore_index=True)

        # Remove duplicates (keep the latest version of each chunk)
        combined_df = combined_df.drop_duplicates(subset=['CHUNK_ID'], keep='last')

        logging.info(f"Combined data: {len(combined_df)} unique enhanced labels")
        return combined_df

    def validate_chunk_ids(self, semantic_df):
        """Validate that chunk IDs exist in RAW_TEXT table with content_type='text_chunk'."""
        logging.info("Validating chunk IDs against RAW_TEXT table...")

        # Get all chunk IDs from semantic data
        chunk_ids = semantic_df['CHUNK_ID'].tolist()
        chunk_ids_str = "', '".join(chunk_ids)

        # Query RAW_TEXT to find matching records
        query = f"""
        SELECT CHUNK_ID, CONTENT_TYPE
        FROM RAW_TEXT
        WHERE CHUNK_ID IN ('{chunk_ids_str}')
        AND CONTENT_TYPE = 'text_chunk'
        """

        try:
            result = self.session.sql(query).collect()
            valid_chunk_ids = set([row[0] for row in result])

            logging.info(f"Found {len(valid_chunk_ids)} valid chunk IDs in RAW_TEXT")
            logging.info(f"Total semantic mappings: {len(chunk_ids)}")

            # Filter semantic data to only include valid chunk IDs
            valid_semantic_df = semantic_df[semantic_df['CHUNK_ID'].isin(valid_chunk_ids)]

            logging.info(f"Will update {len(valid_semantic_df)} records")

            if len(valid_semantic_df) != len(semantic_df):
                invalid_count = len(semantic_df) - len(valid_semantic_df)
                logging.warning(f"Skipping {invalid_count} records with invalid/missing chunk IDs")

            return valid_semantic_df

        except Exception as e:
            logging.error(f"Error validating chunk IDs: {e}")
            return None

    def update_raw_text_table(self, semantic_df, batch_size=100):
        """Update RAW_TEXT table with enhanced labels in batches."""
        logging.info(f"Starting update of RAW_TEXT table with {len(semantic_df)} records...")

        total_updated = 0
        total_batches = (len(semantic_df) + batch_size - 1) // batch_size

        for i in range(0, len(semantic_df), batch_size):
            batch_df = semantic_df.iloc[i:i + batch_size]
            batch_num = (i // batch_size) + 1

            logging.info(f"Processing batch {batch_num}/{total_batches} ({len(batch_df)} records)")

            try:
                # Build UPDATE statement for this batch
                update_cases = []
                chunk_ids = []

                for _, row in batch_df.iterrows():
                    chunk_id = row['CHUNK_ID']
                    enhanced_label = row['LABEL_WITH_SEMANTIC_MAP'].replace("'", "''")  # Escape quotes

                    update_cases.append(f"WHEN '{chunk_id}' THEN '{enhanced_label}'")
                    chunk_ids.append(f"'{chunk_id}'")

                chunk_ids_str = ', '.join(chunk_ids)
                update_cases_str = ' '.join(update_cases)

                # Execute batch update
                update_query = f"""
                UPDATE RAW_TEXT
                SET LABEL_WITH_SEMANTIC_MAP = CASE CHUNK_ID
                    {update_cases_str}
                END
                WHERE CHUNK_ID IN ({chunk_ids_str})
                AND CONTENT_TYPE = 'text_chunk'
                """

                result = self.session.sql(update_query).collect()

                batch_updated = len(batch_df)
                total_updated += batch_updated

                logging.info(f"Batch {batch_num} completed: {batch_updated} records updated")

                # Small delay between batches to avoid overwhelming Snowflake
                time.sleep(0.1)

            except Exception as e:
                logging.error(f"Error in batch {batch_num}: {e}")
                logging.error(f"Problematic chunk IDs in this batch: {batch_df['CHUNK_ID'].tolist()}")
                continue

        logging.info(f"Update complete! Total records updated: {total_updated}")
        return total_updated

    def verify_updates(self, semantic_df):
        """Verify that the updates were applied correctly."""
        logging.info("Verifying updates...")

        # Sample a few chunk IDs to verify
        sample_chunk_ids = semantic_df['CHUNK_ID'].head(5).tolist()
        chunk_ids_str = "', '".join(sample_chunk_ids)

        query = f"""
        SELECT CHUNK_ID,
               LABEL_WITH_SEMANTIC_MAP IS NOT NULL as HAS_SEMANTIC_MAP,
               LENGTH(LABEL_WITH_SEMANTIC_MAP) as LABEL_LENGTH
        FROM RAW_TEXT
        WHERE CHUNK_ID IN ('{chunk_ids_str}')
        AND CONTENT_TYPE = 'text_chunk'
        """

        try:
            result = self.session.sql(query).collect()
            logging.info("Sample verification results:")
            for row in result:
                logging.info(f"  Chunk {row[0]}: "
                           f"Has semantic map: {row[1]}, "
                           f"Label length: {row[2]}")

            # Get overall statistics
            stats_query = f"""
            SELECT
                COUNT(*) as TOTAL_TEXT_CHUNKS,
                COUNT(LABEL_WITH_SEMANTIC_MAP) as CHUNKS_WITH_SEMANTIC_MAP,
                AVG(LENGTH(LABEL_WITH_SEMANTIC_MAP)) as AVG_LABEL_LENGTH
            FROM RAW_TEXT
            WHERE CONTENT_TYPE = 'text_chunk'
            """

            stats_result = self.session.sql(stats_query).collect()
            stats = stats_result[0]

            logging.info(f"Overall statistics:")
            logging.info(f"  Total text chunks: {stats[0]}")
            logging.info(f"  Chunks with semantic map: {stats[1]}")
            logging.info(f"  Average label length: {stats[2]:.1f} characters")

            coverage = (stats[1] / stats[0]) * 100 if stats[0] > 0 else 0
            logging.info(f"  Semantic mapping coverage: {coverage:.1f}%")

        except Exception as e:
            logging.error(f"Error during verification: {e}")

def main():
    """Main execution function."""
    logging.info("=== Snowflake Semantic Mapping Loader Started ===")

    loader = SnowflakeSemanticLoader()

    # Step 1: Load and combine all progress files
    semantic_df = loader.load_progress_files()
    if semantic_df is None:
        logging.error("Failed to load semantic mapping data")
        return

    # Step 2: Validate chunk IDs against RAW_TEXT table
    valid_semantic_df = loader.validate_chunk_ids(semantic_df)
    if valid_semantic_df is None or len(valid_semantic_df) == 0:
        logging.error("No valid chunk IDs found for update")
        return

    # Step 3: Update RAW_TEXT table
    updated_count = loader.update_raw_text_table(valid_semantic_df)

    # Step 4: Verify updates
    loader.verify_updates(valid_semantic_df)

    logging.info(f"=== Semantic Mapping Load Complete: {updated_count} records updated ===")

if __name__ == "__main__":
    main()
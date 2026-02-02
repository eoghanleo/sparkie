"""
Setup script for Sparkie Evaluation Framework

One-command setup for database tables and configuration
"""

import argparse
import sys
import os
from pathlib import Path

from snowflake.snowpark import Session
from dotenv import load_dotenv

load_dotenv()


def read_sql_file(filepath: str) -> str:
    """Read SQL file content"""
    with open(filepath, 'r', encoding='utf-8') as f:
        return f.read()


def execute_sql_script(session, sql_script: str):
    """Execute SQL script with multiple statements"""
    # Split by semicolons and execute each statement
    statements = [s.strip() for s in sql_script.split(';') if s.strip()]

    for i, statement in enumerate(statements, 1):
        # Skip comments and empty lines
        if statement.startswith('--') or not statement:
            continue

        try:
            print(f"Executing statement {i}/{len(statements)}...")
            session.sql(statement).collect()
            print(f"  [OK] Success")
        except Exception as e:
            print(f"  [ERROR] {e}")
            # Continue with other statements
            continue


def create_tables():
    """Create Snowflake tables for evaluation framework"""
    print("="*60)
    print("SPARKIE EVALUATION FRAMEWORK SETUP")
    print("="*60)

    # Connect to Snowflake
    print("\n1. Connecting to Snowflake...")
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
        session = Session.builder.configs(connection_params).create()
        print("   [OK] Connected successfully")
    except Exception as e:
        print(f"   [ERROR] Connection failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    # Load SQL schema
    print("\n2. Loading schema definition...")
    script_dir = Path(__file__).parent
    schema_file = script_dir / 'schema_eval_tables.sql'

    if not schema_file.exists():
        print(f"   [ERROR] Schema file not found: {schema_file}")
        session.close()
        sys.exit(1)

    sql_script = read_sql_file(schema_file)
    print(f"   [OK] Loaded {len(sql_script)} characters")

    # Execute schema
    print("\n3. Creating tables and views...")
    execute_sql_script(session, sql_script)

    # Verify tables exist
    print("\n4. Verifying tables...")
    tables_to_check = [
        'EVAL_RESULTS',
        'EVAL_RUNS',
        'GOLDEN_SET',
        'EVAL_QUEUE'
    ]

    for table in tables_to_check:
        try:
            result = session.sql(f"SELECT COUNT(*) as cnt FROM {table}").collect()
            count = result[0]['CNT'] if result else 0
            print(f"   [OK] {table}: {count} rows")
        except Exception as e:
            print(f"   [ERROR] {table}: {e}")

    session.close()

    print("\n" + "="*60)
    print("SETUP COMPLETE!")
    print("="*60)
    print("\nNext steps:")
    print("1. Integrate interaction_logger.py into your FastAPI app")
    print("2. Start the eval worker: python evaluation/eval_worker.py")
    print("3. Run golden set tests: python evaluation/golden_set_runner.py")
    print("4. View dashboard: python evaluation/dashboard.py")
    print("\nSee README.md for detailed instructions.")


def load_golden_set(csv_path: str):
    """Load test questions into GOLDEN_SET table"""
    import csv
    import uuid

    print(f"Loading golden set from: {csv_path}")

    # Connect to Snowflake
    connection = snowflake.connector.connect(
        account=os.getenv('SNOWFLAKE_ACCOUNT'),
        user=os.getenv('SNOWFLAKE_USER'),
        password=os.getenv('SNOWFLAKE_PASSWORD'),
        warehouse=os.getenv('SNOWFLAKE_WAREHOUSE'),
        database=os.getenv('SNOWFLAKE_DATABASE'),
        schema=os.getenv('SNOWFLAKE_SCHEMA'),
        role=os.getenv('SNOWFLAKE_ROLE'),
    )

    cursor = connection.cursor()

    # Load CSV
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)

        count = 0
        for row in reader:
            golden_id = str(uuid.uuid4())

            cursor.execute("""
                INSERT INTO GOLDEN_SET (
                    golden_id,
                    question,
                    question_type,
                    expected_answer,
                    clause_reference,
                    chunk_id,
                    content_type,
                    source_path,
                    answer_length
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s
                )
            """, (
                golden_id,
                row.get('question'),
                row.get('type'),
                row.get('expected_answer'),
                row.get('clause_reference'),
                row.get('chunk_id'),
                row.get('content_type'),
                row.get('source_path'),
                row.get('answer_length')
            ))

            count += 1

            if count % 100 == 0:
                print(f"  Loaded {count} questions...")
                connection.commit()

    connection.commit()
    cursor.close()
    connection.close()

    print(f"✓ Loaded {count} questions into GOLDEN_SET")


def main():
    parser = argparse.ArgumentParser(
        description='Setup Sparkie Evaluation Framework'
    )

    parser.add_argument(
        '--create-tables',
        action='store_true',
        help='Create evaluation tables in Snowflake'
    )

    parser.add_argument(
        '--load-golden-set',
        type=str,
        metavar='CSV_PATH',
        help='Load test questions from CSV into GOLDEN_SET table'
    )

    args = parser.parse_args()

    if args.create_tables:
        create_tables()

    if args.load_golden_set:
        load_golden_set(args.load_golden_set)

    if not args.create_tables and not args.load_golden_set:
        parser.print_help()


if __name__ == "__main__":
    main()

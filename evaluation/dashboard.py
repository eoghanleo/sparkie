"""
Simple CLI Dashboard for Sparkie Evaluation Metrics

Displays real-time evaluation metrics in the terminal
"""

import snowflake.connector
from snowflake.connector import DictCursor
from dotenv import load_dotenv
import os
from datetime import datetime, timedelta
from typing import Dict, Any, List
import sys

load_dotenv()


class EvalDashboard:
    """Simple terminal dashboard for eval metrics"""

    def __init__(self):
        self.connection = None

    def connect(self):
        """Connect to Snowflake"""
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
            return True
        except Exception as e:
            print(f"Failed to connect: {e}")
            return False

    def close(self):
        """Close connection"""
        if self.connection:
            self.connection.close()

    def fetch_query(self, query: str) -> List[Dict[str, Any]]:
        """Execute query and return results"""
        if not self.connection:
            return []

        try:
            cursor = self.connection.cursor(DictCursor)
            cursor.execute(query)
            results = cursor.fetchall()
            cursor.close()
            return results
        except Exception as e:
            print(f"Query failed: {e}")
            return []

    def display_overview(self):
        """Display system overview metrics"""
        query = """
        SELECT
            COUNT(DISTINCT i.interaction_id) as total_interactions,
            COUNT(DISTINCT e.eval_id) as total_evaluations,
            ROUND(AVG(e.answer_relevance), 3) as avg_relevance,
            ROUND(AVG(e.hallucination_score), 3) as avg_hallucination,
            ROUND(AVG(e.citation_accuracy), 3) as avg_citation_accuracy,
            ROUND(AVG(i.latency_ms), 1) as avg_latency_ms,
            SUM(CASE WHEN i.status = 'error' THEN 1 ELSE 0 END) as error_count
        FROM RAG_INTERACTION i
        LEFT JOIN EVAL_RESULTS e ON i.interaction_id = e.interaction_id
        WHERE i.ts >= DATEADD(day, -7, CURRENT_TIMESTAMP());
        """

        results = self.fetch_query(query)
        if not results:
            print("No data available")
            return

        data = results[0]

        print("\n" + "="*60)
        print("SPARKIE RAG EVALUATION DASHBOARD - LAST 7 DAYS")
        print("="*60)
        print(f"\nTotal Interactions:     {data.get('TOTAL_INTERACTIONS', 0):,}")
        print(f"Total Evaluations:      {data.get('TOTAL_EVALUATIONS', 0):,}")
        print(f"Error Count:            {data.get('ERROR_COUNT', 0):,}")
        print(f"\nAvg Latency:            {data.get('AVG_LATENCY_MS', 0):.1f} ms")
        print(f"\n--- QUALITY METRICS ---")
        print(f"Answer Relevance:       {self._format_score(data.get('AVG_RELEVANCE'))} (target: ≥0.70)")
        print(f"Hallucination Score:    {self._format_score(data.get('AVG_HALLUCINATION'))} (target: ≤0.30)")
        print(f"Citation Accuracy:      {self._format_score(data.get('AVG_CITATION_ACCURACY'))} (target: ≥0.80)")

    def display_daily_trend(self):
        """Display daily performance trend"""
        query = """
        SELECT
            DATE_TRUNC('day', i.ts) as date,
            COUNT(*) as interactions,
            ROUND(AVG(e.answer_relevance), 3) as avg_relevance,
            ROUND(AVG(e.hallucination_score), 3) as avg_hallucination,
            ROUND(AVG(e.citation_accuracy), 3) as avg_citation
        FROM RAG_INTERACTION i
        LEFT JOIN EVAL_RESULTS e ON i.interaction_id = e.interaction_id
        WHERE i.ts >= DATEADD(day, -7, CURRENT_TIMESTAMP())
        GROUP BY DATE_TRUNC('day', i.ts)
        ORDER BY date DESC
        LIMIT 7;
        """

        results = self.fetch_query(query)
        if not results:
            return

        print("\n" + "-"*60)
        print("DAILY TREND (Last 7 Days)")
        print("-"*60)
        print(f"{'Date':<12} {'Interactions':>12} {'Relevance':>10} {'Halluc':>10} {'Citation':>10}")
        print("-"*60)

        for row in results:
            date_str = row['DATE'].strftime('%Y-%m-%d') if row.get('DATE') else 'N/A'
            print(f"{date_str:<12} {row.get('INTERACTIONS', 0):>12,} "
                  f"{self._format_score(row.get('AVG_RELEVANCE')):>10} "
                  f"{self._format_score(row.get('AVG_HALLUCINATION')):>10} "
                  f"{self._format_score(row.get('AVG_CITATION')):>10}")

    def display_golden_set_runs(self):
        """Display recent golden set evaluation runs"""
        query = """
        SELECT
            run_name,
            started_at,
            interactions_evaluated,
            avg_answer_relevance,
            avg_hallucination_score,
            avg_citation_accuracy,
            pass_rate,
            status
        FROM EVAL_RUNS
        WHERE run_type = 'golden_set'
        ORDER BY started_at DESC
        LIMIT 5;
        """

        results = self.fetch_query(query)
        if not results:
            print("\nNo golden set runs found")
            return

        print("\n" + "-"*60)
        print("RECENT GOLDEN SET EVALUATIONS")
        print("-"*60)

        for row in results:
            print(f"\nRun: {row.get('RUN_NAME', 'Unknown')}")
            print(f"  Started: {row.get('STARTED_AT')}")
            print(f"  Status: {row.get('STATUS', 'unknown')}")
            print(f"  Interactions: {row.get('INTERACTIONS_EVALUATED', 0)}")
            print(f"  Relevance: {self._format_score(row.get('AVG_ANSWER_RELEVANCE'))}")
            print(f"  Hallucination: {self._format_score(row.get('AVG_HALLUCINATION_SCORE'))}")
            print(f"  Citation Accuracy: {self._format_score(row.get('AVG_CITATION_ACCURACY'))}")
            print(f"  Pass Rate: {self._format_score(row.get('PASS_RATE'))}")

    def display_hallucination_breakdown(self):
        """Display hallucination score distribution"""
        query = """
        SELECT
            CASE
                WHEN hallucination_score = 0 THEN '0.00 - Perfect'
                WHEN hallucination_score <= 0.2 THEN '0.01-0.20 - Excellent'
                WHEN hallucination_score <= 0.4 THEN '0.21-0.40 - Good'
                WHEN hallucination_score <= 0.6 THEN '0.41-0.60 - Concerning'
                WHEN hallucination_score <= 0.8 THEN '0.61-0.80 - Poor'
                ELSE '0.81-1.00 - Severe'
            END as hallucination_range,
            COUNT(*) as count
        FROM EVAL_RESULTS
        WHERE evaluated_at >= DATEADD(day, -7, CURRENT_TIMESTAMP())
        GROUP BY hallucination_range
        ORDER BY hallucination_range;
        """

        results = self.fetch_query(query)
        if not results:
            return

        print("\n" + "-"*60)
        print("HALLUCINATION SCORE DISTRIBUTION")
        print("-"*60)

        total = sum(row.get('COUNT', 0) for row in results)

        for row in results:
            count = row.get('COUNT', 0)
            pct = (count / total * 100) if total > 0 else 0
            bar = "█" * int(pct / 2)
            print(f"{row.get('HALLUCINATION_RANGE', 'Unknown'):<25} {count:>5} ({pct:>5.1f}%) {bar}")

    def display_alerts(self):
        """Display any active alerts"""
        # Check for high hallucination rate
        query = """
        SELECT
            COUNT(*) as recent_interactions,
            SUM(CASE WHEN e.hallucination_score > 0.5 THEN 1 ELSE 0 END) as high_hallucination_count,
            ROUND(SUM(CASE WHEN e.hallucination_score > 0.5 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as hallucination_rate_pct
        FROM RAG_INTERACTION i
        JOIN EVAL_RESULTS e ON i.interaction_id = e.interaction_id
        WHERE i.ts >= DATEADD(hour, -1, CURRENT_TIMESTAMP());
        """

        results = self.fetch_query(query)
        if not results or not results[0].get('RECENT_INTERACTIONS'):
            return

        data = results[0]
        halluc_rate = data.get('HALLUCINATION_RATE_PCT', 0) or 0

        print("\n" + "-"*60)
        print("ALERTS (Last Hour)")
        print("-"*60)

        if halluc_rate > 20:
            print(f"⚠️  HIGH HALLUCINATION RATE: {halluc_rate:.1f}% (threshold: 20%)")
        else:
            print(f"✓  Hallucination rate OK: {halluc_rate:.1f}%")

    def _format_score(self, score):
        """Format score for display"""
        if score is None:
            return "N/A"
        return f"{score:.3f}"

    def run(self):
        """Run the dashboard"""
        if not self.connect():
            return

        try:
            self.display_overview()
            self.display_daily_trend()
            self.display_hallucination_breakdown()
            self.display_golden_set_runs()
            self.display_alerts()

            print("\n" + "="*60)
            print(f"Dashboard generated at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            print("="*60 + "\n")

        finally:
            self.close()


if __name__ == "__main__":
    dashboard = EvalDashboard()
    dashboard.run()

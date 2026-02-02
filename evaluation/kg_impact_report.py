"""
KG Impact Report - Compare KG-OFF vs KG-ON evaluation runs

Analyzes the impact of KG reranking on RAG performance by comparing
evaluation metrics between runs with KG disabled vs enabled.
"""

import logging
from typing import Dict, List, Any, Optional, Tuple
import pandas as pd
import snowflake.connector
from snowflake.connector import DictCursor
import os
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)


class KGImpactAnalyzer:
    """
    Analyzes KG impact by comparing evaluation runs with different KG configurations.
    """

    def __init__(self, snowflake_conn=None):
        self.connection = snowflake_conn
        if not self.connection:
            self.connect()

    def connect(self):
        """Establish Snowflake connection"""
        try:
            self.connection = snowflake.connector.connect(
                account=os.getenv('SNOWFLAKE_ACCOUNT'),
                user=os.getenv('SNOWFLAKE_USER'),
                private_key=os.getenv('SNOWFLAKE_PRIVATE_KEY'),
                warehouse=os.getenv('SNOWFLAKE_WAREHOUSE'),
                database=os.getenv('SNOWFLAKE_DATABASE'),
                schema=os.getenv('SNOWFLAKE_SCHEMA'),
                role=os.getenv('SNOWFLAKE_ROLE'),
            )
            logger.info("KGImpactAnalyzer connected to Snowflake")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to Snowflake: {e}")
            return False

    def close(self):
        """Close Snowflake connection"""
        if self.connection:
            self.connection.close()

    def compare_eval_runs(
        self,
        kg_off_run_id: str,
        kg_on_run_id: str,
        output_format: str = 'dict'
    ) -> Dict[str, Any]:
        """
        Compare two evaluation runs: one with KG OFF, one with KG ON.

        Args:
            kg_off_run_id: Eval run ID for KG disabled run
            kg_on_run_id: Eval run ID for KG enabled run
            output_format: 'dict', 'dataframe', or 'csv'

        Returns:
            Comparison report with delta metrics
        """
        if not self.connection:
            logger.error("No database connection")
            return {}

        try:
            cursor = self.connection.cursor(DictCursor)

            # Fetch evaluation results for both runs
            kg_off_results = self._fetch_eval_results(cursor, kg_off_run_id)
            kg_on_results = self._fetch_eval_results(cursor, kg_on_run_id)

            cursor.close()

            if not kg_off_results or not kg_on_results:
                logger.error(f"Failed to fetch results for runs: {kg_off_run_id}, {kg_on_run_id}")
                return {}

            # Compute delta metrics
            report = self._compute_delta_metrics(kg_off_results, kg_on_results)
            report['kg_off_run_id'] = kg_off_run_id
            report['kg_on_run_id'] = kg_on_run_id

            # Format output
            if output_format == 'dataframe':
                return self._format_as_dataframe(report)
            elif output_format == 'csv':
                return self._save_as_csv(report, f"kg_impact_{kg_off_run_id}_vs_{kg_on_run_id}.csv")
            else:
                return report

        except Exception as e:
            logger.error(f"Failed to compare eval runs: {e}")
            return {}

    def _fetch_eval_results(self, cursor, eval_run_id: str) -> List[Dict[str, Any]]:
        """
        Fetch evaluation results for a given run from EVAL_RESULTS table.

        Returns:
            List of evaluation result dicts
        """
        query = f"""
            SELECT
                interaction_id,
                question_id,
                hallucination_score,
                citation_accuracy,
                answer_relevance,
                answer_completeness,
                technical_accuracy,
                kg_normative_coverage,
                kg_non_normative_reliance,
                kg_c_reliance_pct,
                kg_conditional_risk,
                kg_multimodal_starvation,
                kg_retrieved_counts,
                kg_cited_counts,
                metadata
            FROM EVAL_RESULTS
            WHERE eval_run_id = '{eval_run_id}'
            ORDER BY interaction_id
        """

        try:
            cursor.execute(query)
            rows = cursor.fetchall()

            results = []
            for row in rows:
                results.append({
                    'interaction_id': row['INTERACTION_ID'],
                    'question_id': row.get('QUESTION_ID'),
                    'hallucination_score': row.get('HALLUCINATION_SCORE'),
                    'citation_accuracy': row.get('CITATION_ACCURACY'),
                    'answer_relevance': row.get('ANSWER_RELEVANCE'),
                    'answer_completeness': row.get('ANSWER_COMPLETENESS'),
                    'technical_accuracy': row.get('TECHNICAL_ACCURACY'),
                    'kg_normative_coverage': row.get('KG_NORMATIVE_COVERAGE'),
                    'kg_non_normative_reliance': row.get('KG_NON_NORMATIVE_RELIANCE'),
                    'kg_c_reliance_pct': row.get('KG_C_RELIANCE_PCT'),
                    'kg_conditional_risk': row.get('KG_CONDITIONAL_RISK'),
                    'kg_multimodal_starvation': row.get('KG_MULTIMODAL_STARVATION'),
                    'kg_retrieved_counts': row.get('KG_RETRIEVED_COUNTS'),
                    'kg_cited_counts': row.get('KG_CITED_COUNTS'),
                    'metadata': row.get('METADATA')
                })

            logger.info(f"Fetched {len(results)} evaluation results for run {eval_run_id}")
            return results

        except Exception as e:
            logger.error(f"Failed to fetch eval results for {eval_run_id}: {e}")
            return []

    def _compute_delta_metrics(
        self,
        kg_off_results: List[Dict[str, Any]],
        kg_on_results: List[Dict[str, Any]]
    ) -> Dict[str, Any]:
        """
        Compute delta metrics between KG-OFF and KG-ON runs.

        Returns:
            Dict with delta_hallucination_rate, delta_citation_accuracy, etc.
        """
        # Helper to compute mean
        def mean(values):
            valid = [v for v in values if v is not None]
            return sum(valid) / len(valid) if valid else None

        # Compute means for KG-OFF
        kg_off_metrics = {
            'hallucination_score': mean([r['hallucination_score'] for r in kg_off_results]),
            'citation_accuracy': mean([r['citation_accuracy'] for r in kg_off_results]),
            'answer_relevance': mean([r['answer_relevance'] for r in kg_off_results]),
            'answer_completeness': mean([r['answer_completeness'] for r in kg_off_results]),
            'technical_accuracy': mean([r['technical_accuracy'] for r in kg_off_results]),
            'kg_normative_coverage': mean([r['kg_normative_coverage'] for r in kg_off_results]),
            'kg_non_normative_reliance': mean([r['kg_non_normative_reliance'] for r in kg_off_results]),
            'kg_c_reliance_pct': mean([r['kg_c_reliance_pct'] for r in kg_off_results]),
            'kg_conditional_risk': mean([r['kg_conditional_risk'] for r in kg_off_results]),
            'kg_multimodal_starvation': mean([r['kg_multimodal_starvation'] for r in kg_off_results])
        }

        # Compute means for KG-ON
        kg_on_metrics = {
            'hallucination_score': mean([r['hallucination_score'] for r in kg_on_results]),
            'citation_accuracy': mean([r['citation_accuracy'] for r in kg_on_results]),
            'answer_relevance': mean([r['answer_relevance'] for r in kg_on_results]),
            'answer_completeness': mean([r['answer_completeness'] for r in kg_on_results]),
            'technical_accuracy': mean([r['technical_accuracy'] for r in kg_on_results]),
            'kg_normative_coverage': mean([r['kg_normative_coverage'] for r in kg_on_results]),
            'kg_non_normative_reliance': mean([r['kg_non_normative_reliance'] for r in kg_on_results]),
            'kg_c_reliance_pct': mean([r['kg_c_reliance_pct'] for r in kg_on_results]),
            'kg_conditional_risk': mean([r['kg_conditional_risk'] for r in kg_on_results]),
            'kg_multimodal_starvation': mean([r['kg_multimodal_starvation'] for r in kg_on_results])
        }

        # Compute deltas (KG-ON - KG-OFF)
        # Negative delta for hallucination is good (lower is better)
        # Positive delta for others is good (higher is better)
        deltas = {
            'delta_hallucination_rate': (kg_on_metrics['hallucination_score'] - kg_off_metrics['hallucination_score'])
                if kg_on_metrics['hallucination_score'] is not None and kg_off_metrics['hallucination_score'] is not None else None,
            'delta_citation_accuracy': (kg_on_metrics['citation_accuracy'] - kg_off_metrics['citation_accuracy'])
                if kg_on_metrics['citation_accuracy'] is not None and kg_off_metrics['citation_accuracy'] is not None else None,
            'delta_answer_relevance': (kg_on_metrics['answer_relevance'] - kg_off_metrics['answer_relevance'])
                if kg_on_metrics['answer_relevance'] is not None and kg_off_metrics['answer_relevance'] is not None else None,
            'delta_answer_completeness': (kg_on_metrics['answer_completeness'] - kg_off_metrics['answer_completeness'])
                if kg_on_metrics['answer_completeness'] is not None and kg_off_metrics['answer_completeness'] is not None else None,
            'delta_technical_accuracy': (kg_on_metrics['technical_accuracy'] - kg_off_metrics['technical_accuracy'])
                if kg_on_metrics['technical_accuracy'] is not None and kg_off_metrics['technical_accuracy'] is not None else None,
            'delta_normative_coverage': (kg_on_metrics['kg_normative_coverage'] - kg_off_metrics['kg_normative_coverage'])
                if kg_on_metrics['kg_normative_coverage'] is not None and kg_off_metrics['kg_normative_coverage'] is not None else None,
            'change_in_c_reliance': (kg_on_metrics['kg_c_reliance_pct'] - kg_off_metrics['kg_c_reliance_pct'])
                if kg_on_metrics['kg_c_reliance_pct'] is not None and kg_off_metrics['kg_c_reliance_pct'] is not None else None,
            'change_in_unknown_inclusion': self._compute_unknown_inclusion_delta(kg_off_results, kg_on_results)
        }

        # Package report
        report = {
            'kg_off_metrics': kg_off_metrics,
            'kg_on_metrics': kg_on_metrics,
            'deltas': deltas,
            'kg_off_count': len(kg_off_results),
            'kg_on_count': len(kg_on_results),
            'summary': self._generate_summary(deltas)
        }

        return report

    def _compute_unknown_inclusion_delta(
        self,
        kg_off_results: List[Dict[str, Any]],
        kg_on_results: List[Dict[str, Any]]
    ) -> Optional[float]:
        """
        Compute change in UNKNOWN (tables/visuals) inclusion rate.

        Returns:
            Percentage point change in UNKNOWN inclusion
        """
        def compute_unknown_pct(results):
            total_retrieved = 0
            unknown_count = 0

            for r in results:
                kg_retrieved_counts = r.get('kg_retrieved_counts', {})
                if isinstance(kg_retrieved_counts, str):
                    import json
                    try:
                        kg_retrieved_counts = json.loads(kg_retrieved_counts)
                    except:
                        kg_retrieved_counts = {}

                unknown_count += kg_retrieved_counts.get('UNKNOWN', 0)
                total_retrieved += sum(kg_retrieved_counts.values())

            return (unknown_count / total_retrieved * 100) if total_retrieved > 0 else 0.0

        kg_off_unknown_pct = compute_unknown_pct(kg_off_results)
        kg_on_unknown_pct = compute_unknown_pct(kg_on_results)

        return kg_on_unknown_pct - kg_off_unknown_pct

    def _generate_summary(self, deltas: Dict[str, Any]) -> str:
        """
        Generate human-readable summary of KG impact.

        Returns:
            Summary string
        """
        summary_lines = []
        summary_lines.append("=" * 60)
        summary_lines.append("KG IMPACT SUMMARY")
        summary_lines.append("=" * 60)

        # Hallucination
        if deltas['delta_hallucination_rate'] is not None:
            if deltas['delta_hallucination_rate'] < -0.05:
                summary_lines.append(f"✓ Hallucination DECREASED by {abs(deltas['delta_hallucination_rate']):.3f} (GOOD)")
            elif deltas['delta_hallucination_rate'] > 0.05:
                summary_lines.append(f"✗ Hallucination INCREASED by {deltas['delta_hallucination_rate']:.3f} (BAD)")
            else:
                summary_lines.append(f"~ Hallucination unchanged ({deltas['delta_hallucination_rate']:.3f})")

        # Citation accuracy
        if deltas['delta_citation_accuracy'] is not None:
            if deltas['delta_citation_accuracy'] > 0.05:
                summary_lines.append(f"✓ Citation accuracy IMPROVED by {deltas['delta_citation_accuracy']:.3f} (GOOD)")
            elif deltas['delta_citation_accuracy'] < -0.05:
                summary_lines.append(f"✗ Citation accuracy DECREASED by {abs(deltas['delta_citation_accuracy']):.3f} (BAD)")
            else:
                summary_lines.append(f"~ Citation accuracy unchanged ({deltas['delta_citation_accuracy']:.3f})")

        # Normative coverage
        if deltas['delta_normative_coverage'] is not None:
            if deltas['delta_normative_coverage'] > 0.05:
                summary_lines.append(f"✓ Normative coverage IMPROVED by {deltas['delta_normative_coverage']:.3f} (GOOD)")
            elif deltas['delta_normative_coverage'] < -0.05:
                summary_lines.append(f"✗ Normative coverage DECREASED by {abs(deltas['delta_normative_coverage']):.3f} (BAD)")
            else:
                summary_lines.append(f"~ Normative coverage unchanged ({deltas['delta_normative_coverage']:.3f})")

        # C reliance
        if deltas['change_in_c_reliance'] is not None:
            if deltas['change_in_c_reliance'] < -5.0:
                summary_lines.append(f"✓ C reliance DECREASED by {abs(deltas['change_in_c_reliance']):.1f}% (GOOD)")
            elif deltas['change_in_c_reliance'] > 5.0:
                summary_lines.append(f"✗ C reliance INCREASED by {deltas['change_in_c_reliance']:.1f}% (BAD)")
            else:
                summary_lines.append(f"~ C reliance unchanged ({deltas['change_in_c_reliance']:.1f}%)")

        # UNKNOWN inclusion
        if deltas['change_in_unknown_inclusion'] is not None:
            if deltas['change_in_unknown_inclusion'] < -10.0:
                summary_lines.append(f"⚠ UNKNOWN inclusion DECREASED by {abs(deltas['change_in_unknown_inclusion']):.1f}% (Multimodal starvation risk)")
            elif deltas['change_in_unknown_inclusion'] > 10.0:
                summary_lines.append(f"✓ UNKNOWN inclusion INCREASED by {deltas['change_in_unknown_inclusion']:.1f}% (Better multimodal coverage)")
            else:
                summary_lines.append(f"~ UNKNOWN inclusion unchanged ({deltas['change_in_unknown_inclusion']:.1f}%)")

        summary_lines.append("=" * 60)

        return "\n".join(summary_lines)

    def _format_as_dataframe(self, report: Dict[str, Any]) -> pd.DataFrame:
        """
        Format report as pandas DataFrame for easy viewing.

        Returns:
            DataFrame with metrics comparison
        """
        data = {
            'Metric': [],
            'KG OFF': [],
            'KG ON': [],
            'Delta': []
        }

        metrics_map = {
            'hallucination_score': 'Hallucination Score',
            'citation_accuracy': 'Citation Accuracy',
            'answer_relevance': 'Answer Relevance',
            'answer_completeness': 'Answer Completeness',
            'technical_accuracy': 'Technical Accuracy',
            'kg_normative_coverage': 'Normative Coverage',
            'kg_c_reliance_pct': 'C Reliance %'
        }

        for key, label in metrics_map.items():
            kg_off_val = report['kg_off_metrics'].get(key)
            kg_on_val = report['kg_on_metrics'].get(key)

            data['Metric'].append(label)
            data['KG OFF'].append(f"{kg_off_val:.3f}" if kg_off_val is not None else "N/A")
            data['KG ON'].append(f"{kg_on_val:.3f}" if kg_on_val is not None else "N/A")

            # Compute delta
            if kg_off_val is not None and kg_on_val is not None:
                delta = kg_on_val - kg_off_val
                data['Delta'].append(f"{delta:+.3f}")
            else:
                data['Delta'].append("N/A")

        df = pd.DataFrame(data)
        return df

    def _save_as_csv(self, report: Dict[str, Any], filename: str) -> str:
        """
        Save report as CSV file.

        Returns:
            Path to saved CSV
        """
        df = self._format_as_dataframe(report)
        df.to_csv(filename, index=False)
        logger.info(f"Saved KG impact report to {filename}")
        return filename

    def compare_question_subsets(
        self,
        kg_off_run_id: str,
        kg_on_run_id: str,
        group_by: str = 'has_table'
    ) -> Dict[str, Any]:
        """
        Compare KG impact across question subsets (e.g., questions with/without tables).

        Args:
            kg_off_run_id: Eval run ID for KG disabled run
            kg_on_run_id: Eval run ID for KG enabled run
            group_by: Field to group by ('has_table', 'has_diagram', 'has_calculation')

        Returns:
            Comparison report grouped by subset
        """
        # TODO: Implement subset analysis
        pass


# Convenience function
def generate_kg_impact_report(
    kg_off_run_id: str,
    kg_on_run_id: str,
    output_format: str = 'dict'
) -> Dict[str, Any]:
    """
    Generate KG impact report comparing two evaluation runs.

    Args:
        kg_off_run_id: Eval run with KG disabled
        kg_on_run_id: Eval run with KG enabled
        output_format: 'dict', 'dataframe', or 'csv'

    Returns:
        Comparison report
    """
    analyzer = KGImpactAnalyzer()
    report = analyzer.compare_eval_runs(kg_off_run_id, kg_on_run_id, output_format)
    analyzer.close()
    return report

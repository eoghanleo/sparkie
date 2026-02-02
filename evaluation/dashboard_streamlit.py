"""
Streamlit Dashboard for Sparkie RAG Evaluation System

Displays evaluation metrics, test runs, and detailed question-level analysis
with visual content inspection.
"""

import streamlit as st
import snowflake.connector
from dotenv import load_dotenv
import os
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from datetime import datetime, timedelta
import json

load_dotenv()

# Page config
st.set_page_config(
    page_title="Sparkie Evaluation Dashboard",
    page_icon="⚡",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Modern Blue-Themed CSS
st.markdown("""
<style>
    /* Main color palette - Modern Blues */
    :root {
        --primary-blue: #1e3a8a;
        --secondary-blue: #3b82f6;
        --light-blue: #60a5fa;
        --accent-blue: #0ea5e9;
        --success-green: #10b981;
        --warning-orange: #f59e0b;
        --bg-dark: #0f172a;
        --bg-light: #f8fafc;
        --card-bg: #ffffff;
    }

    /* Main app background */
    .stApp {
        background: linear-gradient(135deg, #f8fafc 0%, #e0f2fe 100%);
    }

    /* Sidebar styling */
    [data-testid="stSidebar"] {
        background: white;
        border-right: 2px solid #e2e8f0;
    }

    [data-testid="stSidebar"] .stMarkdown {
        color: var(--primary-blue) !important;
    }

    [data-testid="stSidebar"] h1,
    [data-testid="stSidebar"] h2,
    [data-testid="stSidebar"] h3 {
        color: var(--primary-blue) !important;
    }

    [data-testid="stSidebar"] .stRadio > label {
        color: var(--primary-blue) !important;
        font-weight: 600;
    }

    [data-testid="stSidebar"] [data-baseweb="radio"] > div {
        background-color: #f8fafc;
        padding: 12px;
        border-radius: 8px;
        margin: 4px 0;
        border: 2px solid transparent;
        transition: all 0.2s ease;
    }

    [data-testid="stSidebar"] [data-baseweb="radio"] > div:hover {
        border-color: var(--secondary-blue);
        background-color: #e0f2fe;
    }

    [data-testid="stSidebar"] [data-baseweb="radio"] [data-checked="true"] {
        background: linear-gradient(135deg, var(--secondary-blue) 0%, var(--accent-blue) 100%);
        color: white;
        border-color: var(--secondary-blue);
    }

    /* Metric cards with modern shadow and border */
    div[data-testid="stMetric"] {
        background: white;
        padding: 20px;
        border-radius: 12px;
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
        border-left: 4px solid var(--secondary-blue);
        transition: transform 0.2s ease, box-shadow 0.2s ease;
    }

    div[data-testid="stMetric"]:hover {
        transform: translateY(-2px);
        box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05);
    }

    div[data-testid="stMetric"] label {
        color: var(--primary-blue) !important;
        font-weight: 600 !important;
        font-size: 0.875rem !important;
        text-transform: uppercase;
        letter-spacing: 0.05em;
    }

    div[data-testid="stMetric"] [data-testid="stMetricValue"] {
        color: var(--primary-blue) !important;
        font-size: 2rem !important;
        font-weight: 700 !important;
    }

    /* Headers */
    h1 {
        color: var(--primary-blue) !important;
        font-weight: 800 !important;
        background: linear-gradient(135deg, #1e3a8a 0%, #3b82f6 100%);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
        background-clip: text;
    }

    h2 {
        color: var(--primary-blue) !important;
        font-weight: 700 !important;
        margin-top: 2rem !important;
    }

    h3 {
        color: var(--secondary-blue) !important;
        font-weight: 600 !important;
    }

    /* Tabs */
    .stTabs [data-baseweb="tab-list"] {
        gap: 8px;
        background-color: white;
        padding: 8px;
        border-radius: 12px;
        box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.1);
    }

    .stTabs [data-baseweb="tab"] {
        background-color: transparent;
        border-radius: 8px;
        color: var(--primary-blue);
        font-weight: 600;
        padding: 12px 24px;
    }

    .stTabs [data-baseweb="tab"]:hover {
        background-color: var(--bg-light);
    }

    .stTabs [aria-selected="true"] {
        background: linear-gradient(135deg, var(--secondary-blue) 0%, var(--accent-blue) 100%);
        color: white !important;
    }

    /* Buttons */
    .stButton button {
        background: linear-gradient(135deg, var(--secondary-blue) 0%, var(--accent-blue) 100%);
        color: white;
        border: none;
        border-radius: 8px;
        padding: 12px 24px;
        font-weight: 600;
        box-shadow: 0 4px 6px -1px rgba(59, 130, 246, 0.3);
        transition: all 0.2s ease;
    }

    .stButton button:hover {
        transform: translateY(-1px);
        box-shadow: 0 10px 15px -3px rgba(59, 130, 246, 0.4);
    }

    /* Selectbox and inputs */
    .stSelectbox > div > div {
        background-color: white;
        border: 2px solid #e2e8f0;
        border-radius: 8px;
        transition: border-color 0.2s ease;
    }

    .stSelectbox > div > div:focus-within {
        border-color: var(--secondary-blue);
        box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
    }

    /* Info, Success, Warning boxes */
    .stAlert {
        border-radius: 12px;
        border-left: 4px solid var(--secondary-blue);
        background-color: white;
        padding: 16px;
        box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.1);
    }

    div[data-baseweb="notification"] {
        border-radius: 12px;
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
    }

    /* Expander */
    .streamlit-expanderHeader {
        background-color: white;
        border-radius: 8px;
        border: 1px solid #e2e8f0;
        font-weight: 600;
        color: var(--primary-blue);
        transition: all 0.2s ease;
    }

    .streamlit-expanderHeader:hover {
        background-color: var(--bg-light);
        border-color: var(--secondary-blue);
    }

    /* DataFrame/Table */
    .dataframe {
        border: none !important;
        border-radius: 12px;
        overflow: hidden;
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
    }

    .dataframe thead th {
        background: linear-gradient(135deg, var(--primary-blue) 0%, var(--secondary-blue) 100%);
        color: white !important;
        font-weight: 600;
        padding: 12px;
    }

    .dataframe tbody tr:nth-child(even) {
        background-color: #f8fafc;
    }

    .dataframe tbody tr:hover {
        background-color: #e0f2fe;
    }

    /* Code blocks */
    .stCodeBlock {
        border-radius: 8px;
        border-left: 4px solid var(--accent-blue);
    }

    /* Plotly charts */
    .js-plotly-plot {
        border-radius: 12px;
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
        background-color: white;
        padding: 16px;
    }
</style>
""", unsafe_allow_html=True)


@st.cache_resource
def get_snowflake_connection():
    """Create cached Snowflake connection"""
    try:
        conn = snowflake.connector.connect(
            account=os.getenv('SNOWFLAKE_ACCOUNT'),
            user=os.getenv('SNOWFLAKE_USER'),
            private_key=os.getenv('SNOWFLAKE_PRIVATE_KEY'),
            warehouse=os.getenv('SNOWFLAKE_WAREHOUSE'),
            database=os.getenv('SNOWFLAKE_DATABASE'),
            schema=os.getenv('SNOWFLAKE_SCHEMA'),
            role=os.getenv('SNOWFLAKE_ROLE'),
        )
        return conn
    except Exception as e:
        st.error(f"Failed to connect to Snowflake: {e}")
        return None


def query_snowflake(query, params=None):
    """Execute Snowflake query and return DataFrame"""
    conn = get_snowflake_connection()
    if not conn:
        return pd.DataFrame()

    try:
        if params:
            df = pd.read_sql(query, conn, params=params)
        else:
            df = pd.read_sql(query, conn)
        return df
    except Exception as e:
        st.error(f"Query failed: {e}")
        return pd.DataFrame()


def get_overview_metrics():
    """Get high-level overview metrics"""
    query = """
    SELECT
        COUNT(DISTINCT e.eval_run_id) as total_runs,
        COUNT(DISTINCT e.eval_id) as total_evaluations,
        ROUND(AVG(e.answer_relevance), 3) as avg_relevance,
        ROUND(AVG(e.hallucination_score), 3) as avg_hallucination,
        ROUND(AVG(e.citation_accuracy), 3) as avg_citation_accuracy,
        ROUND(AVG(e.answer_completeness), 3) as avg_completeness,
        ROUND(AVG(e.technical_accuracy), 3) as avg_technical_accuracy,
        ROUND(AVG(e.kg_normative_coverage), 3) as avg_kg_normative_coverage,
        ROUND(AVG(e.kg_non_normative_reliance), 3) as avg_kg_non_normative_reliance,
        ROUND(AVG(e.kg_c_reliance_pct), 3) as avg_kg_c_reliance_pct,
        ROUND(AVG(e.kg_conditional_risk), 3) as avg_kg_conditional_risk,
        ROUND(AVG(e.kg_multimodal_starvation), 3) as avg_kg_multimodal_starvation
    FROM TEST_DB.CORTEX.EVAL_RESULTS e
    WHERE e.evaluated_at >= DATEADD(day, -30, CURRENT_TIMESTAMP())
    """
    return query_snowflake(query)


def get_eval_runs():
    """Get all evaluation runs with all metrics calculated on-the-fly from EVAL_RESULTS"""
    query = """
    SELECT
        r.eval_run_id,
        r.run_name,
        r.started_at,
        r.completed_at,
        r.status,
        r.sample_size,
        -- Calculate all metrics from EVAL_RESULTS (handles case where EVAL_RUNS aggregates are NULL)
        COALESCE(r.interactions_evaluated, COUNT(DISTINCT e.eval_id)) as interactions_evaluated,
        COALESCE(r.avg_answer_relevance, ROUND(AVG(e.answer_relevance), 3)) as avg_answer_relevance,
        COALESCE(r.avg_hallucination_score, ROUND(AVG(e.hallucination_score), 3)) as avg_hallucination_score,
        COALESCE(r.avg_citation_accuracy, ROUND(AVG(e.citation_accuracy), 3)) as avg_citation_accuracy,
        COALESCE(r.pass_rate,
            SUM(CASE WHEN e.answer_relevance >= 0.7
                     AND e.hallucination_score <= 0.3
                     AND e.citation_accuracy >= 0.8
                THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(e.eval_id), 0)
        ) as pass_rate,
        r.summary_metrics,
        -- Calculate KG metrics from EVAL_RESULTS
        ROUND(AVG(e.kg_normative_coverage), 3) as avg_kg_normative_coverage,
        ROUND(AVG(e.kg_non_normative_reliance), 3) as avg_kg_non_normative_reliance,
        ROUND(AVG(e.kg_conditional_risk), 3) as avg_kg_conditional_risk,
        ROUND(AVG(e.kg_multimodal_starvation), 3) as avg_kg_multimodal_starvation
    FROM TEST_DB.CORTEX.EVAL_RUNS r
    LEFT JOIN TEST_DB.CORTEX.EVAL_RESULTS e ON r.eval_run_id = e.eval_run_id
    GROUP BY r.eval_run_id, r.run_name, r.started_at, r.completed_at, r.status,
             r.sample_size, r.interactions_evaluated, r.avg_answer_relevance,
             r.avg_hallucination_score, r.avg_citation_accuracy, r.pass_rate, r.summary_metrics
    ORDER BY r.started_at DESC
    """
    return query_snowflake(query)


def get_eval_results_for_run(eval_run_id):
    """Get detailed results for a specific eval run"""
    query = f"""
    SELECT
        e.eval_id,
        e.interaction_id,
        COALESCE(e.metadata:user_query::STRING, MAX(g.question_text)) as user_query,
        e.metadata:generated_answer::STRING as answer_text,
        e.answer_relevance,
        e.hallucination_score,
        e.citation_accuracy,
        e.answer_completeness,
        e.technical_accuracy,
        e.judge_reasoning,
        e.metadata,
        e.evaluated_at,
        e.expected_clause,
        e.kg_normative_coverage,
        e.kg_non_normative_reliance,
        e.kg_c_reliance_pct,
        e.kg_conditional_risk,
        e.kg_multimodal_starvation
    FROM TEST_DB.CORTEX.EVAL_RESULTS e
    LEFT JOIN TEST_DB.CORTEX.GOLDEN_SET_QUESTIONS g ON g.clause_number = e.expected_clause
    WHERE e.eval_run_id = '{eval_run_id}'
    GROUP BY e.eval_id, e.interaction_id, e.metadata:user_query::STRING,
             e.metadata:generated_answer::STRING, e.answer_relevance, e.hallucination_score,
             e.citation_accuracy, e.answer_completeness, e.technical_accuracy,
             e.judge_reasoning, e.metadata, e.evaluated_at, e.expected_clause,
             e.kg_normative_coverage, e.kg_non_normative_reliance, e.kg_c_reliance_pct,
             e.kg_conditional_risk, e.kg_multimodal_starvation
    ORDER BY e.evaluated_at
    """
    return query_snowflake(query)


def get_hallucination_distribution():
    """Get hallucination score distribution"""
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
    FROM TEST_DB.CORTEX.EVAL_RESULTS
    WHERE evaluated_at >= DATEADD(day, -30, CURRENT_TIMESTAMP())
    GROUP BY hallucination_range
    ORDER BY hallucination_range
    """
    return query_snowflake(query)


def get_kg_class_distribution():
    """Get KG class distribution from retrieved and cited chunks (stored in metadata)"""
    query = """
    SELECT
        metadata
    FROM TEST_DB.CORTEX.EVAL_RESULTS
    WHERE evaluated_at >= DATEADD(day, -30, CURRENT_TIMESTAMP())
        AND metadata IS NOT NULL
    """
    return query_snowflake(query)


def show_overview_page():
    """Display overview dashboard page"""
    st.title("⚡ Sparkie RAG Evaluation Dashboard")
    st.markdown("### System Performance Overview (Last 30 Days)")

    # Get metrics
    metrics_df = get_overview_metrics()

    if metrics_df.empty:
        st.warning("No evaluation data available")
        return

    metrics = metrics_df.iloc[0]

    # Top-level metrics
    col1, col2, col3, col4, col5 = st.columns(5)

    with col1:
        st.metric(
            "Total Runs",
            f"{int(metrics['TOTAL_RUNS'])}"
        )

    with col2:
        st.metric(
            "Total Evaluations",
            f"{int(metrics['TOTAL_EVALUATIONS'])}"
        )

    with col3:
        halluc_score = metrics['AVG_HALLUCINATION']
        st.metric(
            "Avg Hallucination",
            f"{halluc_score:.3f}"
        )

    with col4:
        relevance = metrics['AVG_RELEVANCE']
        st.metric(
            "Avg Relevance",
            f"{relevance:.3f}"
        )

    with col5:
        citation = metrics['AVG_CITATION_ACCURACY']
        st.metric(
            "Avg Citation Accuracy",
            f"{citation:.3f}"
        )

    st.markdown("---")

    # Knowledge Graph Metrics
    st.markdown("### 🧠 Knowledge Graph Metrics")

    col1, col2, col3, col4 = st.columns(4)

    with col1:
        kg_normative = metrics.get('AVG_KG_NORMATIVE_COVERAGE')
        st.metric(
            "Normative Coverage",
            f"{kg_normative:.3f}" if pd.notna(kg_normative) else "N/A",
            help="Proportion of answers citing normative (A/B) chunks from KG"
        )

    with col2:
        kg_non_norm = metrics.get('AVG_KG_NON_NORMATIVE_RELIANCE')
        st.metric(
            "Non-Normative Reliance",
            f"{kg_non_norm:.3f}" if pd.notna(kg_non_norm) else "N/A",
            help="Score indicating reliance on non-normative (C) chunks"
        )

    with col3:
        kg_cond_risk = metrics.get('AVG_KG_CONDITIONAL_RISK')
        st.metric(
            "Conditional Risk",
            f"{kg_cond_risk:.3f}" if pd.notna(kg_cond_risk) else "N/A",
            help="Risk of misapplying conditional (B) requirements"
        )

    with col4:
        kg_multimodal = metrics.get('AVG_KG_MULTIMODAL_STARVATION')
        st.metric(
            "Multimodal Coverage",
            f"{kg_multimodal:.3f}" if pd.notna(kg_multimodal) else "N/A",
            help="Proper retrieval of tables/diagrams when needed"
        )

    # Show C-chunk reliance percentage
    c_reliance = metrics.get('AVG_KG_C_RELIANCE_PCT')
    if pd.notna(c_reliance):
        st.caption(f"📊 Average C-chunk reliance: {c_reliance:.1f}%")

    st.markdown("---")

    # Quality metrics breakdown
    col1, col2 = st.columns(2)

    with col1:
        st.markdown("### 📊 Quality Metrics Breakdown")
        quality_metrics = pd.DataFrame({
            'Metric': ['Answer Relevance', 'Hallucination Score', 'Citation Accuracy', 'Completeness', 'Technical Accuracy'],
            'Score': [
                metrics['AVG_RELEVANCE'],
                metrics['AVG_HALLUCINATION'],
                metrics['AVG_CITATION_ACCURACY'],
                metrics['AVG_COMPLETENESS'],
                metrics['AVG_TECHNICAL_ACCURACY']
            ],
            'Target': [0.90, 0.20, 0.80, 0.85, 0.90]
        })

        fig = go.Figure()
        fig.add_trace(go.Bar(
            name='Current',
            x=quality_metrics['Metric'],
            y=quality_metrics['Score'],
            marker_color='lightblue'
        ))
        fig.add_trace(go.Bar(
            name='Target',
            x=quality_metrics['Metric'],
            y=quality_metrics['Target'],
            marker_color='lightcoral'
        ))
        fig.update_layout(
            barmode='group',
            height=400,
            yaxis_title="Score",
            xaxis_title="",
            legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1)
        )
        st.plotly_chart(fig, use_container_width=True)

    with col2:
        st.markdown("### 🎯 Hallucination Distribution")
        halluc_df = get_hallucination_distribution()

        if not halluc_df.empty:
            fig = px.pie(
                halluc_df,
                values='COUNT',
                names='HALLUCINATION_RANGE',
                title="",
                color_discrete_sequence=px.colors.sequential.Blues_r
            )
            fig.update_traces(textposition='inside', textinfo='percent+label')
            fig.update_layout(height=400)
            st.plotly_chart(fig, use_container_width=True)

    # KG Metrics Visualization
    st.markdown("---")
    col1, col2 = st.columns(2)

    with col1:
        st.markdown("### 🧠 KG Quality Metrics")
        kg_metrics_df = pd.DataFrame({
            'Metric': ['Normative Coverage', 'Non-Norm Reliance', 'Conditional Risk', 'Multimodal Coverage'],
            'Score': [
                metrics.get('AVG_KG_NORMATIVE_COVERAGE', 0),
                metrics.get('AVG_KG_NON_NORMATIVE_RELIANCE', 0),
                metrics.get('AVG_KG_CONDITIONAL_RISK', 0),
                metrics.get('AVG_KG_MULTIMODAL_STARVATION', 0)
            ],
            'Target': [0.90, 0.85, 0.90, 0.95]
        })

        # Filter out None/NaN values
        kg_metrics_df = kg_metrics_df[kg_metrics_df['Score'].notna()]

        if not kg_metrics_df.empty:
            fig = go.Figure()
            fig.add_trace(go.Bar(
                name='Current',
                x=kg_metrics_df['Metric'],
                y=kg_metrics_df['Score'],
                marker_color='#60a5fa'
            ))
            fig.add_trace(go.Bar(
                name='Target',
                x=kg_metrics_df['Metric'],
                y=kg_metrics_df['Target'],
                marker_color='#f59e0b'
            ))
            fig.update_layout(
                barmode='group',
                height=400,
                yaxis_title="Score",
                xaxis_title="",
                legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1)
            )
            st.plotly_chart(fig, use_container_width=True)
        else:
            st.info("No KG metrics data available yet")

    with col2:
        st.markdown("### 📚 KG Class Distribution")
        kg_dist_df = get_kg_class_distribution()

        if not kg_dist_df.empty:
            # Aggregate KG class counts across all evaluations
            total_kg_counts = {'A': 0, 'B': 0, 'C': 0, 'UNKNOWN': 0}

            for idx, row in kg_dist_df.iterrows():
                metadata = row['METADATA']
                if metadata:
                    try:
                        # Parse metadata if it's a string
                        if isinstance(metadata, str):
                            metadata_dict = json.loads(metadata)
                        else:
                            metadata_dict = metadata

                        # Extract kg_retrieved_counts from metadata
                        retrieved_counts = metadata_dict.get('kg_retrieved_counts', {})

                        if retrieved_counts:
                            for kg_class, count in retrieved_counts.items():
                                if kg_class in total_kg_counts:
                                    total_kg_counts[kg_class] += count
                    except (json.JSONDecodeError, TypeError, AttributeError):
                        pass

            # Filter out zero counts
            total_kg_counts = {k: v for k, v in total_kg_counts.items() if v > 0}

            if total_kg_counts:
                kg_df = pd.DataFrame(list(total_kg_counts.items()), columns=['KG Class', 'Count'])
                kg_df['Class Name'] = kg_df['KG Class'].map({
                    'A': 'A - Mandatory',
                    'B': 'B - Conditional',
                    'C': 'C - Non-Normative',
                    'UNKNOWN': 'Unknown'
                })

                fig = px.pie(
                    kg_df,
                    values='Count',
                    names='Class Name',
                    title="",
                    color='KG Class',
                    color_discrete_map={
                        'A': '#10b981',  # Green for mandatory
                        'B': '#f59e0b',  # Orange for conditional
                        'C': '#3b82f6',  # Blue for non-normative
                        'UNKNOWN': '#9ca3af'  # Gray for unknown
                    }
                )
                fig.update_traces(textposition='inside', textinfo='percent+label')
                fig.update_layout(height=400)
                st.plotly_chart(fig, use_container_width=True)
            else:
                st.info("No KG class distribution data available")
        else:
            st.info("No KG class distribution data available")


def show_eval_runs_page():
    """Display evaluation runs page"""
    st.title("📋 Evaluation Runs")
    st.markdown("### Historical Test Runs")

    runs_df = get_eval_runs()

    if runs_df.empty:
        st.warning("No evaluation runs found")
        return

    # Format and display runs table
    display_df = runs_df.copy()
    display_df['STARTED_AT'] = pd.to_datetime(display_df['STARTED_AT']).dt.strftime('%Y-%m-%d %H:%M')

    # Convert numeric columns and round
    display_df['AVG_HALLUCINATION_SCORE'] = pd.to_numeric(display_df['AVG_HALLUCINATION_SCORE'], errors='coerce').round(3)
    display_df['AVG_ANSWER_RELEVANCE'] = pd.to_numeric(display_df['AVG_ANSWER_RELEVANCE'], errors='coerce').round(3)
    display_df['AVG_CITATION_ACCURACY'] = pd.to_numeric(display_df['AVG_CITATION_ACCURACY'], errors='coerce').round(3)
    display_df['PASS_RATE'] = (pd.to_numeric(display_df['PASS_RATE'], errors='coerce') * 100).round(1).astype(str) + '%'

    st.dataframe(
        display_df[[
            'RUN_NAME', 'STARTED_AT', 'STATUS', 'INTERACTIONS_EVALUATED',
            'AVG_ANSWER_RELEVANCE', 'AVG_HALLUCINATION_SCORE',
            'AVG_CITATION_ACCURACY', 'PASS_RATE'
        ]],
        use_container_width=True,
        height=400
    )

    # Run selector for detailed view
    st.markdown("---")
    st.markdown("### 🔍 Detailed Run Analysis")

    selected_run_name = st.selectbox(
        "Select a run to view details:",
        options=runs_df['RUN_NAME'].tolist()
    )

    if selected_run_name:
        selected_run = runs_df[runs_df['RUN_NAME'] == selected_run_name].iloc[0]
        eval_run_id = selected_run['EVAL_RUN_ID']

        # Show run summary - Standard Metrics
        st.markdown("**Standard Metrics:**")
        col1, col2, col3, col4 = st.columns(4)
        with col1:
            interactions = selected_run['INTERACTIONS_EVALUATED']
            st.metric("Questions Evaluated", int(interactions) if pd.notna(interactions) else "In Progress")
        with col2:
            pass_rate = selected_run['PASS_RATE']
            st.metric("Pass Rate", f"{pass_rate*100:.1f}%" if pd.notna(pass_rate) else "N/A")
        with col3:
            halluc = selected_run['AVG_HALLUCINATION_SCORE']
            st.metric("Avg Hallucination", f"{halluc:.3f}" if pd.notna(halluc) else "N/A")
        with col4:
            relevance = selected_run['AVG_ANSWER_RELEVANCE']
            st.metric("Avg Relevance", f"{relevance:.3f}" if pd.notna(relevance) else "N/A")

        # Show KG metrics if available
        if any([pd.notna(selected_run.get('AVG_KG_NORMATIVE_COVERAGE')),
                pd.notna(selected_run.get('AVG_KG_NON_NORMATIVE_RELIANCE')),
                pd.notna(selected_run.get('AVG_KG_CONDITIONAL_RISK')),
                pd.notna(selected_run.get('AVG_KG_MULTIMODAL_STARVATION'))]):
            st.markdown("**Knowledge Graph Metrics:**")
            col1, col2, col3, col4 = st.columns(4)
            with col1:
                kg_norm = selected_run.get('AVG_KG_NORMATIVE_COVERAGE')
                st.metric("Normative Coverage", f"{kg_norm:.3f}" if pd.notna(kg_norm) else "N/A")
            with col2:
                kg_non_norm = selected_run.get('AVG_KG_NON_NORMATIVE_RELIANCE')
                st.metric("Non-Norm Reliance", f"{kg_non_norm:.3f}" if pd.notna(kg_non_norm) else "N/A")
            with col3:
                kg_cond = selected_run.get('AVG_KG_CONDITIONAL_RISK')
                st.metric("Conditional Risk", f"{kg_cond:.3f}" if pd.notna(kg_cond) else "N/A")
            with col4:
                kg_multi = selected_run.get('AVG_KG_MULTIMODAL_STARVATION')
                st.metric("Multimodal Coverage", f"{kg_multi:.3f}" if pd.notna(kg_multi) else "N/A")

        # Get detailed results
        results_df = get_eval_results_for_run(eval_run_id)

        if not results_df.empty:
            st.markdown(f"#### Question-Level Results ({len(results_df)} questions for run {eval_run_id})")

            # Create tabs for standard and KG metrics
            tab1, tab2 = st.tabs(["📊 Standard Metrics", "🧠 KG Metrics"])

            with tab1:
                # Show results table
                display_results = results_df.copy()
                display_results['USER_QUERY'] = display_results['USER_QUERY'].str[:80] + '...'

                # Convert to numeric and round
                display_results['HALLUCINATION_SCORE'] = pd.to_numeric(display_results['HALLUCINATION_SCORE'], errors='coerce').round(3)
                display_results['ANSWER_RELEVANCE'] = pd.to_numeric(display_results['ANSWER_RELEVANCE'], errors='coerce').round(3)
                display_results['CITATION_ACCURACY'] = pd.to_numeric(display_results['CITATION_ACCURACY'], errors='coerce').round(3)
                display_results['ANSWER_COMPLETENESS'] = pd.to_numeric(display_results['ANSWER_COMPLETENESS'], errors='coerce').round(3)
                display_results['TECHNICAL_ACCURACY'] = pd.to_numeric(display_results['TECHNICAL_ACCURACY'], errors='coerce').round(3)

                st.dataframe(
                    display_results[[
                        'USER_QUERY', 'ANSWER_RELEVANCE', 'HALLUCINATION_SCORE',
                        'CITATION_ACCURACY', 'ANSWER_COMPLETENESS', 'TECHNICAL_ACCURACY'
                    ]],
                    use_container_width=True,
                    height=400
                )

            with tab2:
                # Show KG metrics table
                display_kg = results_df.copy()
                display_kg['USER_QUERY'] = display_kg['USER_QUERY'].str[:60] + '...'

                # Convert to numeric and round KG metrics if they exist
                kg_cols_to_display = []
                if 'KG_NORMATIVE_COVERAGE' in display_kg.columns:
                    display_kg['KG_NORMATIVE_COVERAGE'] = pd.to_numeric(display_kg['KG_NORMATIVE_COVERAGE'], errors='coerce').round(3)
                    kg_cols_to_display.append('KG_NORMATIVE_COVERAGE')
                if 'KG_NON_NORMATIVE_RELIANCE' in display_kg.columns:
                    display_kg['KG_NON_NORMATIVE_RELIANCE'] = pd.to_numeric(display_kg['KG_NON_NORMATIVE_RELIANCE'], errors='coerce').round(3)
                    kg_cols_to_display.append('KG_NON_NORMATIVE_RELIANCE')
                if 'KG_C_RELIANCE_PCT' in display_kg.columns:
                    display_kg['KG_C_RELIANCE_PCT'] = pd.to_numeric(display_kg['KG_C_RELIANCE_PCT'], errors='coerce').round(1)
                    kg_cols_to_display.append('KG_C_RELIANCE_PCT')
                if 'KG_CONDITIONAL_RISK' in display_kg.columns:
                    display_kg['KG_CONDITIONAL_RISK'] = pd.to_numeric(display_kg['KG_CONDITIONAL_RISK'], errors='coerce').round(3)
                    kg_cols_to_display.append('KG_CONDITIONAL_RISK')
                if 'KG_MULTIMODAL_STARVATION' in display_kg.columns:
                    display_kg['KG_MULTIMODAL_STARVATION'] = pd.to_numeric(display_kg['KG_MULTIMODAL_STARVATION'], errors='coerce').round(3)
                    kg_cols_to_display.append('KG_MULTIMODAL_STARVATION')

                if kg_cols_to_display:
                    st.dataframe(
                        display_kg[['USER_QUERY'] + kg_cols_to_display],
                        use_container_width=True,
                        height=400
                    )
                else:
                    st.info("No KG metrics available for this evaluation run")

            # Question drill-down
            st.markdown("---")
            st.markdown("#### 🔎 Question Details")

            question_options = [f"Q{i+1}: {(row['USER_QUERY'][:60] if pd.notna(row['USER_QUERY']) else 'N/A')}..."
                              for i, row in results_df.iterrows()]
            selected_q_idx = st.selectbox(
                "Select a question to inspect:",
                options=range(len(question_options)),
                format_func=lambda x: question_options[x]
            )

            selected_result = results_df.iloc[selected_q_idx]

            col1, col2 = st.columns([2, 1])

            with col1:
                st.markdown("**Question:**")
                user_query = selected_result['USER_QUERY']
                st.info(user_query if pd.notna(user_query) else "N/A")

                st.markdown("**Generated Answer:**")
                # SQL query already extracts from COALESCE(i.answer_text, e.metadata:generated_answer::STRING, '')
                answer_text = selected_result['ANSWER_TEXT']
                if not answer_text or pd.isna(answer_text):
                    st.warning("No generated answer available (older evaluation run)")
                else:
                    st.success(answer_text)

                st.markdown("**Judge Reasoning:**")
                judge_reasoning = selected_result['JUDGE_REASONING']
                st.text_area(
                    "Reasoning",
                    value=judge_reasoning if pd.notna(judge_reasoning) else "No reasoning provided",
                    height=200,
                    disabled=True,
                    label_visibility="collapsed"
                )

            with col2:
                st.markdown("**Scores:**")
                relevance = selected_result['ANSWER_RELEVANCE']
                st.metric("Answer Relevance", f"{relevance:.3f}" if pd.notna(relevance) else "N/A")

                halluc = selected_result['HALLUCINATION_SCORE']
                st.metric("Hallucination", f"{halluc:.3f}" if pd.notna(halluc) else "N/A")

                citation = selected_result['CITATION_ACCURACY']
                st.metric("Citation Accuracy", f"{citation:.3f}" if pd.notna(citation) else "N/A")

                completeness = selected_result['ANSWER_COMPLETENESS']
                st.metric("Completeness", f"{completeness:.3f}" if pd.notna(completeness) else "N/A")

                technical = selected_result['TECHNICAL_ACCURACY']
                st.metric("Technical Accuracy", f"{technical:.3f}" if pd.notna(technical) else "N/A")

            # KG Metrics Section
            st.markdown("---")
            st.markdown("### 🧠 Knowledge Graph Metrics")

            # Parse metadata for KG details
            kg_details = {}
            if selected_result['METADATA']:
                try:
                    metadata = json.loads(selected_result['METADATA']) if isinstance(selected_result['METADATA'], str) else selected_result['METADATA']
                    kg_details = {
                        'normative_coverage_details': metadata.get('kg_normative_coverage_details', ''),
                        'non_normative_reliance_details': metadata.get('kg_non_normative_reliance_details', ''),
                        'conditional_risk_details': metadata.get('kg_conditional_risk_details', ''),
                        'multimodal_starvation_details': metadata.get('kg_multimodal_starvation_details', ''),
                        'retrieved_counts': metadata.get('kg_retrieved_counts', {}),
                        'cited_counts': metadata.get('kg_cited_counts', {}),
                        'retrieved_content_types': metadata.get('kg_retrieved_content_types', {})
                    }
                except (json.JSONDecodeError, TypeError) as e:
                    st.warning(f"Could not parse metadata: {e}")

            kg_col1, kg_col2, kg_col3, kg_col4 = st.columns(4)

            with kg_col1:
                kg_norm = selected_result.get('KG_NORMATIVE_COVERAGE')
                st.metric(
                    "Normative Coverage",
                    f"{kg_norm:.3f}" if pd.notna(kg_norm) else "N/A",
                    help="Did answer cite normative (A/B) chunks?"
                )

            with kg_col2:
                kg_non_norm = selected_result.get('KG_NON_NORMATIVE_RELIANCE')
                st.metric(
                    "Non-Norm Reliance",
                    f"{kg_non_norm:.3f}" if pd.notna(kg_non_norm) else "N/A",
                    help="Reliance on non-normative (C) content"
                )

            with kg_col3:
                kg_cond = selected_result.get('KG_CONDITIONAL_RISK')
                st.metric(
                    "Conditional Risk",
                    f"{kg_cond:.3f}" if pd.notna(kg_cond) else "N/A",
                    help="Risk of misapplying conditional (B) requirements"
                )

            with kg_col4:
                kg_multi = selected_result.get('KG_MULTIMODAL_STARVATION')
                st.metric(
                    "Multimodal Coverage",
                    f"{kg_multi:.3f}" if pd.notna(kg_multi) else "N/A",
                    help="Were tables/diagrams retrieved when needed?"
                )

            # Show KG details with expanders
            if any(kg_details.values()):
                col1, col2 = st.columns(2)

                with col1:
                    # KG reasoning details
                    st.markdown("**KG Analysis Details:**")

                    if kg_details.get('normative_coverage_details'):
                        with st.expander("📋 Normative Coverage Details"):
                            st.text(kg_details['normative_coverage_details'])

                    if kg_details.get('non_normative_reliance_details'):
                        with st.expander("📋 Non-Normative Reliance Details"):
                            st.text(kg_details['non_normative_reliance_details'])
                            c_pct = selected_result.get('KG_C_RELIANCE_PCT')
                            if pd.notna(c_pct):
                                st.caption(f"C-chunk reliance: {c_pct:.1f}%")

                with col2:
                    if kg_details.get('conditional_risk_details'):
                        with st.expander("⚠️ Conditional Risk Details"):
                            st.text(kg_details['conditional_risk_details'])

                    if kg_details.get('multimodal_starvation_details'):
                        with st.expander("🎨 Multimodal Coverage Details"):
                            st.text(kg_details['multimodal_starvation_details'])

            # Show KG class distribution for this question
            if kg_details.get('retrieved_counts'):
                st.markdown("---")
                st.markdown("**KG Class Distribution for This Question:**")

                col1, col2, col3 = st.columns(3)

                try:
                    retrieved_counts = kg_details['retrieved_counts']
                    cited_counts = kg_details.get('cited_counts', {})

                    with col1:
                        st.markdown("**Retrieved:**")
                        for kg_class in ['A', 'B', 'C', 'UNKNOWN']:
                            count = retrieved_counts.get(kg_class, 0)
                            if count > 0:
                                class_name = {'A': 'Mandatory', 'B': 'Conditional', 'C': 'Non-Normative', 'UNKNOWN': 'Unknown'}[kg_class]
                                st.caption(f"{kg_class} ({class_name}): {count}")

                    with col2:
                        st.markdown("**Cited:**")
                        if cited_counts:
                            for kg_class in ['A', 'B', 'C', 'UNKNOWN']:
                                count = cited_counts.get(kg_class, 0)
                                if count > 0:
                                    class_name = {'A': 'Mandatory', 'B': 'Conditional', 'C': 'Non-Normative', 'UNKNOWN': 'Unknown'}[kg_class]
                                    st.caption(f"{kg_class} ({class_name}): {count}")
                        else:
                            st.caption("Citation mapping not available")

                    with col3:
                        # Show content type distribution
                        content_types = kg_details.get('retrieved_content_types', {})
                        if content_types:
                            st.markdown("**Content Types:**")
                            for ctype, count in content_types.items():
                                if count > 0:
                                    st.caption(f"{ctype}: {count}")

                except (KeyError, TypeError) as e:
                    st.warning(f"Could not display KG counts: {e}")

            # Show judge context if available
            if selected_result['METADATA']:
                try:
                    metadata = json.loads(selected_result['METADATA']) if isinstance(selected_result['METADATA'], str) else selected_result['METADATA']
                    judge_context_summary = metadata.get('judge_context_summary', {})
                    judge_context_full = metadata.get('judge_context_full', [])

                    if judge_context_summary:
                        st.markdown("---")
                        st.markdown("### 📚 Judge Context")
                        col1, col2, col3 = st.columns(3)
                        with col1:
                            st.metric("Total Chunks", judge_context_summary.get('total_chunks', 0))
                        with col2:
                            st.metric("Text Chunks", judge_context_summary.get('text_chunks', 0))
                        with col3:
                            st.metric("Visual Chunks", judge_context_summary.get('visual_chunks', 0))

                        # Show full context chunks
                        if judge_context_full:
                            st.markdown("---")
                            st.markdown("**Retrieved Context Chunks:**")

                            for idx, chunk in enumerate(judge_context_full, 1):
                                content_type = chunk.get('content_type', 'text')

                                with st.expander(f"Chunk {idx}: {content_type.upper()} - {chunk.get('content_id', 'Unknown')[:50]}"):
                                    if content_type == 'visual':
                                        # Show visual content with thumbnail
                                        st.markdown(f"**Visual Type:** {chunk.get('visual_type', 'N/A')}")
                                        st.markdown(f"**Caption:** {chunk.get('caption', 'N/A')}")

                                        # Show thumbnail if available
                                        thumbnail_url = chunk.get('thumbnail_url') or chunk.get('image_url')
                                        if thumbnail_url:
                                            try:
                                                st.image(thumbnail_url, caption=f"Visual {idx}", use_column_width=True)
                                            except:
                                                st.info(f"Thumbnail URL: {thumbnail_url}")

                                        # Show extracted text
                                        if chunk.get('extracted_text'):
                                            st.markdown("**Extracted Text:**")
                                            st.text_area(f"Text {idx}", chunk.get('extracted_text'), height=300, disabled=True, label_visibility="collapsed", max_chars=None)
                                    else:
                                        # Show text chunk
                                        text_content = chunk.get('text_content', 'N/A')
                                        st.text_area(f"Text {idx}", text_content, height=300, disabled=True, label_visibility="collapsed", max_chars=None)
                                        if chunk.get('label'):
                                            st.caption(f"Source: {chunk.get('label')}")

                except (json.JSONDecodeError, TypeError) as e:
                    st.warning(f"Could not parse metadata: {e}")


def main():
    """Main dashboard application"""

    # Sidebar navigation
    st.sidebar.title("Navigation")
    page = st.sidebar.radio(
        "Go to:",
        ["📊 Overview", "📋 Evaluation Runs"]
    )

    st.sidebar.markdown("---")
    st.sidebar.markdown("### About")
    st.sidebar.info(
        "**Sparkie RAG Evaluation Dashboard**\n\n"
        "Monitor and analyze the performance of your RAG system "
        "with multimodal evaluation metrics and Knowledge Graph-aware analysis.\n\n"
        "**KG Metrics:**\n"
        "• Normative Coverage (A/B chunks)\n"
        "• Non-Normative Reliance (C chunks)\n"
        "• Conditional Risk (B chunk applicability)\n"
        "• Multimodal Coverage (tables/diagrams)"
    )

    # Route to selected page
    if page == "📊 Overview":
        show_overview_page()
    elif page == "📋 Evaluation Runs":
        show_eval_runs_page()


if __name__ == "__main__":
    main()

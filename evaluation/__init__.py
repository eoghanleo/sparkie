"""
Sparkie RAG Evaluation Framework

A comprehensive evaluation and observability system for RAG applications.
"""

__version__ = "1.0.0"

from .interaction_logger import (
    InteractionLogger,
    get_interaction_logger,
    log_rag_interaction
)

from .eval_metrics import (
    EvalMetrics,
    evaluate_rag_response
)

from .eval_worker import EvalWorker
from .golden_set_runner import GoldenSetRunner
from .dashboard import EvalDashboard

__all__ = [
    'InteractionLogger',
    'get_interaction_logger',
    'log_rag_interaction',
    'EvalMetrics',
    'evaluate_rag_response',
    'EvalWorker',
    'GoldenSetRunner',
    'EvalDashboard'
]

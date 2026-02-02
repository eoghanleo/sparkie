"""
QUERY EXPANDER FOR SPARKIE V3
Expands user queries with electrician synonyms at search time.

This replaces the ingestion-time semantic mapping with query-time expansion,
providing the same retrieval benefits without baking synonyms into embeddings.

Benefits:
- Update mappings without re-embedding
- Cleaner stored content
- Faster ingestion pipeline
- Same retrieval quality

Usage:
    expander = QueryExpander('path/to/wiring_focused_semantic_mapping.csv')
    expanded = expander.expand("What is RCD protection for bathrooms?")
    # Returns: "What is RCD ELCB safety switch protection for bathrooms loo wet areas?"
"""

import re
import csv
import ast
import logging
from pathlib import Path
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)


class QueryExpander:
    """
    Expand queries with electrician synonyms at search time.

    Loads mappings from CSV and applies them to incoming queries
    before embedding for Cortex Search.
    """

    def __init__(self, mappings_path: Optional[str] = None):
        """
        Initialize with semantic mappings CSV.

        Args:
            mappings_path: Path to CSV with TECHNICAL_TERM,SPARKIE_SYNONYMS columns.
                          If None, uses default path relative to this file.
        """
        if mappings_path is None:
            # Default to the existing mappings file
            mappings_path = Path(__file__).parent.parent / "data" / "wiring_focused_semantic_mapping.csv"

        self.mappings_path = Path(mappings_path)
        self.mappings: Dict[str, List[str]] = {}
        self.patterns: List[Tuple[re.Pattern, str, List[str]]] = []

        self._load_mappings()
        self._compile_patterns()

        logger.info(f"QueryExpander initialized with {len(self.mappings)} mappings")

    def _load_mappings(self):
        """Load mappings from CSV file"""
        if not self.mappings_path.exists():
            logger.warning(f"Mappings file not found: {self.mappings_path}")
            return

        try:
            with open(self.mappings_path, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    term = row.get('TECHNICAL_TERM', '').strip()
                    synonyms_str = row.get('SPARKIE_SYNONYMS', '').strip()

                    if not term or not synonyms_str:
                        continue

                    # Parse the synonyms list (stored as Python list literal)
                    try:
                        synonyms = ast.literal_eval(synonyms_str)
                        if isinstance(synonyms, list):
                            self.mappings[term.upper()] = synonyms
                    except (ValueError, SyntaxError) as e:
                        logger.warning(f"Failed to parse synonyms for '{term}': {e}")

            logger.info(f"Loaded {len(self.mappings)} semantic mappings")

        except Exception as e:
            logger.error(f"Failed to load mappings: {e}")

    def _compile_patterns(self):
        """
        Pre-compile regex patterns for fast matching.

        Sorts by length (longest first) to avoid partial matches.
        E.g., "RCD PROTECTION" should match before "RCD"
        """
        # Sort terms by length (longest first)
        sorted_terms = sorted(self.mappings.keys(), key=len, reverse=True)

        for term in sorted_terms:
            # Create pattern with word boundaries
            # Use re.escape to handle special characters
            pattern = re.compile(
                rf'\b{re.escape(term)}\b',
                re.IGNORECASE
            )
            self.patterns.append((pattern, term, self.mappings[term]))

    def expand(self, query: str, max_synonyms_per_term: int = 3) -> str:
        """
        Expand query with synonyms.

        Args:
            query: Original user query
            max_synonyms_per_term: Limit synonyms per matched term (to avoid query explosion)

        Returns:
            Expanded query with synonyms appended

        Example:
            Input:  "What is the RCD protection requirement for bathrooms?"
            Output: "What is the RCD ELCB safety switch protection requirement
                     for bathrooms loo wet areas?"
        """
        if not self.patterns:
            return query

        expanded = query
        matched_terms = set()

        for pattern, term, synonyms in self.patterns:
            # Check if pattern matches
            if pattern.search(query):
                # Avoid duplicate expansions
                if term in matched_terms:
                    continue
                matched_terms.add(term)

                # Limit synonyms to avoid query explosion
                limited_synonyms = synonyms[:max_synonyms_per_term]
                synonym_str = ' '.join(limited_synonyms)

                # Append synonyms after the first match of the term
                # This preserves the original query structure
                def replacer(match):
                    return f"{match.group(0)} {synonym_str}"

                expanded = pattern.sub(replacer, expanded, count=1)

        if matched_terms:
            logger.debug(f"Expanded query with terms: {matched_terms}")

        return expanded

    def expand_with_metadata(self, query: str) -> Dict:
        """
        Expand query and return metadata about expansions.

        Returns:
            Dict with:
            - expanded_query: str
            - matched_terms: List[str]
            - synonyms_added: List[str]
        """
        matched_terms = []
        synonyms_added = []
        expanded = query

        for pattern, term, synonyms in self.patterns:
            if pattern.search(query):
                if term not in matched_terms:
                    matched_terms.append(term)
                    limited_synonyms = synonyms[:3]
                    synonyms_added.extend(limited_synonyms)
                    synonym_str = ' '.join(limited_synonyms)

                    def replacer(match):
                        return f"{match.group(0)} {synonym_str}"

                    expanded = pattern.sub(replacer, expanded, count=1)

        return {
            'original_query': query,
            'expanded_query': expanded,
            'matched_terms': matched_terms,
            'synonyms_added': synonyms_added,
            'expansion_count': len(matched_terms)
        }

    def get_synonyms(self, term: str) -> List[str]:
        """
        Get synonyms for a specific term.

        Args:
            term: Technical term to look up

        Returns:
            List of synonyms, or empty list if not found
        """
        return self.mappings.get(term.upper(), [])

    def add_mapping(self, term: str, synonyms: List[str]):
        """
        Add or update a mapping at runtime.

        Args:
            term: Technical term
            synonyms: List of synonyms
        """
        self.mappings[term.upper()] = synonyms
        # Recompile patterns
        self._compile_patterns()

    def stats(self) -> Dict:
        """Return statistics about loaded mappings"""
        total_synonyms = sum(len(syns) for syns in self.mappings.values())
        return {
            'total_terms': len(self.mappings),
            'total_synonyms': total_synonyms,
            'avg_synonyms_per_term': total_synonyms / len(self.mappings) if self.mappings else 0,
            'mappings_file': str(self.mappings_path)
        }


# Singleton instance for easy import
_default_expander: Optional[QueryExpander] = None


def get_expander() -> QueryExpander:
    """Get or create the default QueryExpander instance"""
    global _default_expander
    if _default_expander is None:
        _default_expander = QueryExpander()
    return _default_expander


def expand_query(query: str) -> str:
    """Convenience function to expand a query using the default expander"""
    return get_expander().expand(query)


# Quick test
if __name__ == "__main__":
    import sys

    # Initialize expander
    expander = QueryExpander()

    # Print stats
    print("Query Expander Stats:")
    for key, value in expander.stats().items():
        print(f"  {key}: {value}")

    # Test queries
    test_queries = [
        "What is RCD protection?",
        "What size earth wire do I need?",
        "Bathroom wiring requirements",
        "32A circuit installation",
        "TPS cable specifications",
        "What are the earthing requirements?",
    ]

    print("\nTest Expansions:")
    print("-" * 60)

    for query in test_queries:
        result = expander.expand_with_metadata(query)
        print(f"\nOriginal: {query}")
        print(f"Expanded: {result['expanded_query']}")
        if result['matched_terms']:
            print(f"Matched:  {result['matched_terms']}")

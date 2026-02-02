#!/usr/bin/env python3
"""
Semantic Mapping Processor for AS3000 Labels
Processes electrical labels using Groq API to add colloquial electrician terms
"""

import pandas as pd
import json
import time
import os
from groq import Groq
from dotenv import load_dotenv
import csv
import re

# Load environment variables
load_dotenv()

class SemanticMappingProcessor:
    def __init__(self):
        self.client = Groq(api_key=os.getenv('GROQ_API_KEY'))
        self.model = "llama-3.3-70b-versatile"  # Fast model for processing

    def load_data(self):
        """Load the CSV files"""
        print("Loading data files...")

        # Load structured table chunks to be processed
        self.chunks_df = pd.read_csv('structured_table_labels.csv')
        print(f"Loaded {len(self.chunks_df)} structured table chunks to process")

        # Load semantic mappings
        self.mappings_df = pd.read_csv('semantic mapping - technical and sparkie terms.csv')
        print(f"Loaded {len(self.mappings_df)} semantic mappings")

        # Parse the JSON-like sparkie synonyms
        self.semantic_dict = {}
        for _, row in self.mappings_df.iterrows():
            technical_term = row['TECHNICAL_TERM']
            try:
                # Parse the JSON array of synonyms
                synonyms = json.loads(row['SPARKIE_SYNONYMS'].replace("'", '"'))
                self.semantic_dict[technical_term.upper()] = synonyms
            except json.JSONDecodeError:
                print(f"Warning: Could not parse synonyms for {technical_term}")
                continue

        print(f"Parsed {len(self.semantic_dict)} semantic mappings")

    def create_semantic_prompt(self):
        """Create the semantic mapping context for the LLM prompt"""
        mapping_text = "SEMANTIC MAPPINGS (Technical Term -> Sparkie Synonyms):\n"
        for technical, synonyms in self.semantic_dict.items():
            mapping_text += f"- {technical}: {', '.join(synonyms)}\n"
        return mapping_text

    def process_label(self, label, chunk_id):
        """Process a single label using Groq API"""

        semantic_context = self.create_semantic_prompt()

        prompt = f"""You are helping to enhance electrical standards labels for better searchability by electricians.

{semantic_context}

TASK: Transform the technical label below by adding colloquial electrician synonyms from the mappings above.

RULES:
1. Keep the original sentence structure intact
2. When you find a technical term that has sparkie synonyms, add ALL the synonyms right after the technical term
3. Use spaces to separate multiple synonyms
4. Don't worry about grammar - focus on semantic coverage
5. Only add synonyms that are relevant to the context

EXAMPLE:
Input: "Zoning requirements for fixed water containers under 40L"
Output: "Zoning requirements minimum clearances for fixed water containers sink basin under 40L"

LABEL TO TRANSFORM:
{label}

ENHANCED LABEL:"""

        max_retries = 3
        for attempt in range(max_retries):
            try:
                response = self.client.chat.completions.create(
                    messages=[
                        {"role": "user", "content": prompt}
                    ],
                    model=self.model,
                    temperature=0.1,
                    max_tokens=500
                )

                enhanced_label = response.choices[0].message.content.strip()

                # Clean up any extra text the model might add
                if enhanced_label.startswith("ENHANCED LABEL:"):
                    enhanced_label = enhanced_label.replace("ENHANCED LABEL:", "").strip()

                return enhanced_label

            except Exception as e:
                print(f"Error processing chunk {chunk_id} (attempt {attempt + 1}/{max_retries}): {e}")
                if attempt < max_retries - 1:
                    print(f"Retrying in {2 ** attempt} seconds...")
                    time.sleep(2 ** attempt)  # Exponential backoff
                else:
                    print(f"Failed after {max_retries} attempts, returning original label")
                    return label  # Return original label if all retries fail

    def process_all_chunks(self, start_index=0, batch_size=10, max_chunks=None):
        """Process all chunks with progress tracking"""

        results = []
        total_chunks = len(self.chunks_df) if max_chunks is None else min(len(self.chunks_df), max_chunks)

        print(f"Processing {total_chunks} chunks starting from index {start_index}...")

        for i, (index, row) in enumerate(self.chunks_df.iterrows()):
            if i < start_index:
                continue
            if max_chunks is not None and i >= max_chunks:
                break

            chunk_id = row['CHUNK_ID']
            label = row['LABEL']

            print(f"Processing {i+1}/{total_chunks}: {chunk_id}")
            try:
                print(f"Original: {label[:100].encode('ascii', 'ignore').decode('ascii')}...")
            except:
                print(f"Original: [contains special characters]")

            enhanced_label = self.process_label(label, chunk_id)

            try:
                print(f"Enhanced: {enhanced_label[:100].encode('ascii', 'ignore').decode('ascii')}...")
            except:
                print(f"Enhanced: [contains special characters]")
            print("-" * 50)

            results.append({
                'CHUNK_ID': chunk_id,
                'LABEL_WITH_SEMANTIC_MAP': enhanced_label
            })

            # Save progress every batch_size items
            if (i + 1) % batch_size == 0:
                self.save_progress(results, f"semantic_mapping_progress_{i+1}.csv")
                print(f"Progress saved at {i+1} items")

            # Rate limiting - be nice to the API
            time.sleep(1.0)  # Increased from 0.5s to 1.0s

        return results

    def save_progress(self, results, filename):
        """Save intermediate results"""
        df = pd.DataFrame(results)
        df.to_csv(filename, index=False, quoting=csv.QUOTE_ALL)
        print(f"Saved {len(results)} results to {filename}")

    def save_final_results(self, results):
        """Save the final results"""
        output_file = "structured_table_enhanced_labels.csv"
        df = pd.DataFrame(results)
        df.to_csv(output_file, index=False, quoting=csv.QUOTE_ALL)
        print(f"Final results saved to {output_file}")
        print(f"Total processed: {len(results)} structured table chunks")
        return output_file

def main():
    """Main processing function"""
    processor = SemanticMappingProcessor()

    # Load the data
    processor.load_data()

    # Process all structured table chunks from the beginning
    results = processor.process_all_chunks(start_index=0, batch_size=10, max_chunks=None)

    # Save final results
    output_file = processor.save_final_results(results)
    print(f"Processing complete! Results saved to {output_file}")

if __name__ == "__main__":
    main()
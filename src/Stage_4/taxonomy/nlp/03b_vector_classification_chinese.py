#!/usr/bin/env python3
"""
Vector Classification using Chinese Categories and Vernaculars

Uses KaLM-Embedding-Gemma3-12B-2511 via vLLM to classify genera
based on Chinese vernacular names and functional categories.

Input:
    - data/taxonomy/genus_vernacular_aggregations_chinese.parquet
    - data/taxonomy/functional_categories_bilingual.parquet

Output:
    - data/taxonomy/vector_classifications_kalm_chinese.parquet

Prerequisites:
    - vLLM server running on localhost:8000
    - KaLM-Embedding-Gemma3-12B-2511 model loaded

Date: 2025-11-15
"""

import pandas as pd
import numpy as np
import duckdb
from openai import OpenAI
from sklearn.metrics.pairwise import cosine_similarity
from tqdm import tqdm
import time

# ============================================================================
# Configuration
# ============================================================================

VLLM_URL = "http://localhost:8000/v1"
MODEL_NAME = "tencent/KaLM-Embedding-Gemma3-12B-2511"

GENUS_FILE = "/home/olier/ellenberg/data/taxonomy/genus_vernacular_aggregations_chinese.parquet"
CATEGORIES_FILE = "/home/olier/ellenberg/data/taxonomy/functional_categories_bilingual.parquet"
OUTPUT_FILE = "/home/olier/ellenberg/data/taxonomy/vector_classifications_kalm_chinese.parquet"

BATCH_SIZE = 128
SIMILARITY_THRESHOLD = 0.42  # Lowered from 0.45 for 98.0% coverage (threshold analysis)

# ============================================================================
# Setup
# ============================================================================

print("=" * 80)
print("Vector Classification - Chinese Categories")
print("=" * 80)
print()

# Initialize vLLM client
client = OpenAI(api_key="EMPTY", base_url=VLLM_URL)

# ============================================================================
# Helper Functions
# ============================================================================

def get_embeddings_batch(texts, show_progress=False):
    """Get embeddings for a batch of texts using vLLM."""
    # Call vLLM embedding API
    response = client.embeddings.create(
        input=texts,
        model=MODEL_NAME
    )

    # Extract embeddings
    embeddings = np.array([item.embedding for item in response.data])

    # Normalize for cosine similarity
    embeddings = embeddings / np.linalg.norm(embeddings, axis=1, keepdims=True)

    return embeddings

# ============================================================================
# Load Data
# ============================================================================

print("Loading data...")

# Use DuckDB to avoid PyArrow compatibility issues
con = duckdb.connect()

# Load genera with Chinese vernaculars
genera_df = con.execute(f"SELECT * FROM read_parquet('{GENUS_FILE}')").fetchdf()
print(f"  Loaded {len(genera_df):,} genera with Chinese vernaculars")

# Load bilingual categories (use Chinese column)
categories_df = con.execute(f"SELECT * FROM read_parquet('{CATEGORIES_FILE}')").fetchdf()
print(f"  Loaded {len(categories_df):,} bilingual categories")

con.close()
print()

# ============================================================================
# Create Category Embeddings (Prototypes)
# ============================================================================

print("Creating category prototype embeddings...")

# Use Chinese categories
category_names = categories_df['category_zh'].tolist()
category_indices = categories_df['index'].tolist()

# Get embeddings for all categories
category_embeddings = get_embeddings_batch(category_names)
print(f"  Created {len(category_embeddings)} category prototypes (3840-dim)")
print()

# Create mapping from index to category
index_to_category_zh = dict(zip(categories_df['index'], categories_df['category_zh']))
index_to_category_en = dict(zip(categories_df['index'], categories_df['category_en']))

# ============================================================================
# Classify Genera (Batch Processing)
# ============================================================================

print(f"Classifying {len(genera_df):,} genera...")
print(f"Batch size: {BATCH_SIZE}")
print(f"Similarity threshold: {SIMILARITY_THRESHOLD}")
print()

results = []
total_batches = (len(genera_df) + BATCH_SIZE - 1) // BATCH_SIZE

# Process in batches
for batch_idx in tqdm(range(total_batches), desc="Processing batches"):
    start_idx = batch_idx * BATCH_SIZE
    end_idx = min(start_idx + BATCH_SIZE, len(genera_df))

    batch_df = genera_df.iloc[start_idx:end_idx]

    # Get vernacular strings for this batch
    vernacular_texts = batch_df['vernaculars_all'].tolist()

    # Get embeddings for this batch
    genus_embeddings = get_embeddings_batch(vernacular_texts)

    # Compute cosine similarities (vectorized)
    # Shape: (batch_size, n_categories)
    similarities = cosine_similarity(genus_embeddings, category_embeddings)

    # For each genus in batch, find best matches
    for i, (_, row) in enumerate(batch_df.iterrows()):
        genus_similarities = similarities[i]

        # Get top 3 matches
        top3_indices = np.argsort(genus_similarities)[-3:][::-1]
        top3_scores = genus_similarities[top3_indices]
        top3_category_indices = [category_indices[idx] for idx in top3_indices]
        top3_categories_zh = [index_to_category_zh[idx] for idx in top3_category_indices]
        top3_categories_en = [index_to_category_en[idx] for idx in top3_category_indices]

        # Accept best match if above threshold
        best_similarity = top3_scores[0]
        if best_similarity >= SIMILARITY_THRESHOLD:
            best_index = top3_category_indices[0]
            best_category_zh = top3_categories_zh[0]
            best_category_en = top3_categories_en[0]
        else:
            best_index = None
            best_category_zh = None
            best_category_en = None

        results.append({
            'genus': row['genus'],
            'category_index': best_index,
            'vector_category_zh': best_category_zh,
            'vector_category_en': best_category_en,
            'vector_similarity': best_similarity,
            'vector_top3_indices': ';'.join(top3_category_indices),
            'vector_top3_categories_zh': ';'.join(top3_categories_zh),
            'vector_top3_categories_en': ';'.join(top3_categories_en),
            'vector_top3_scores': ';'.join([f"{s:.4f}" for s in top3_scores])
        })

# ============================================================================
# Create Results DataFrame
# ============================================================================

print("\nCreating results dataframe...")
results_df = pd.DataFrame(results)

# ============================================================================
# Summary Statistics
# ============================================================================

print("\n" + "=" * 80)
print("Summary Statistics")
print("=" * 80)

categorized = results_df['vector_category_zh'].notna()
n_categorized = categorized.sum()
n_uncategorized = (~categorized).sum()

print(f"\nTotal genera processed: {len(results_df):,}")
print(f"Categorized: {n_categorized:,} ({n_categorized/len(results_df)*100:.1f}%)")
print(f"Uncategorized: {n_uncategorized:,} ({n_uncategorized/len(results_df)*100:.1f}%)")

print(f"\nSimilarity statistics (categorized genera):")
categorized_similarities = results_df[categorized]['vector_similarity']
print(f"  Mean: {categorized_similarities.mean():.4f}")
print(f"  Median: {categorized_similarities.median():.4f}")
print(f"  Min: {categorized_similarities.min():.4f}")
print(f"  Max: {categorized_similarities.max():.4f}")

print(f"\nTop 10 categories (Chinese):")
top_categories_zh = results_df[categorized]['vector_category_zh'].value_counts().head(10)
for i, (cat, count) in enumerate(top_categories_zh.items(), 1):
    # Find corresponding English category
    cat_en = results_df[results_df['vector_category_zh'] == cat]['vector_category_en'].iloc[0]
    pct = count / n_categorized * 100
    print(f"  {i}. {cat} ({cat_en}): {count:,} ({pct:.1f}%)")

# ============================================================================
# Write Output
# ============================================================================

print(f"\nWriting output...")
print(f"  Output: {OUTPUT_FILE}")

results_df.to_parquet(OUTPUT_FILE, index=False)

print(f"\n✓ Successfully wrote {len(results_df):,} classified genera")

# ============================================================================
# Done
# ============================================================================

print("\n" + "=" * 80)
print("Complete")
print("=" * 80)
print()

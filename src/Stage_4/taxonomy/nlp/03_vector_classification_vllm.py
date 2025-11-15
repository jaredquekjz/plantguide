#!/usr/bin/env python3
"""
Vector-based Classification using KaLM via vLLM Server
GPU-accelerated, SOTA embedding model for organism categorization

Dependencies:
- vLLM server running on localhost:8000
- conda AI environment with openai, pandas, numpy, sklearn
"""

import pandas as pd
import numpy as np
from openai import OpenAI
from sklearn.metrics.pairwise import cosine_similarity
from tqdm import tqdm
import time
import sys
import os
import duckdb

# ============================================================================
# Configuration
# ============================================================================

VLLM_BASE_URL = "http://localhost:8000/v1"
MODEL_NAME = "tencent/KaLM-Embedding-Gemma3-12B-2511"
BATCH_SIZE = 128  # Optimal for RTX 6000 Ada with 48GB VRAM
MIN_SIMILARITY = 0.5  # Threshold for accepting a category match

DATA_DIR = "/home/olier/ellenberg/data/taxonomy"

# Test mode: limit number of genera to process
TEST_MODE = os.environ.get('TEST_MODE', 'false').lower() == 'true'
TEST_LIMIT = int(os.environ.get('TEST_LIMIT', '100'))

print("=" * 80)
print("KaLM Vector Classification Pipeline")
print("=" * 80)
print(f"Model: {MODEL_NAME}")
print(f"vLLM Server: {VLLM_BASE_URL}")
print(f"Batch Size: {BATCH_SIZE}")
print(f"Min Similarity: {MIN_SIMILARITY}")
print("=" * 80)

# ============================================================================
# vLLM Client Setup
# ============================================================================

client = OpenAI(
    base_url=VLLM_BASE_URL,
    api_key="dummy"  # vLLM doesn't require real API key
)

def get_embeddings_batch(texts, show_progress=False):
    """
    Get embeddings from vLLM server

    Args:
        texts: List of strings to embed
        show_progress: Show progress for this batch

    Returns:
        numpy array of normalized embeddings
    """
    try:
        response = client.embeddings.create(
            input=texts,
            model=MODEL_NAME
        )

        # Extract embeddings and convert to numpy array
        embeddings = np.array([item.embedding for item in response.data])

        # Normalize for cosine similarity
        norms = np.linalg.norm(embeddings, axis=1, keepdims=True)
        embeddings = embeddings / norms

        return embeddings

    except Exception as e:
        print(f"\n❌ Error getting embeddings: {e}")
        return None

# ============================================================================
# Load Data
# ============================================================================

print("\n📂 Loading data...")

# Use DuckDB to read parquet files (PyArrow compatibility)
con = duckdb.connect()

if TEST_MODE:
    print(f"\n⚠️  TEST MODE: Processing only {TEST_LIMIT} genera")
    genus_query = f"SELECT * FROM read_parquet('{DATA_DIR}/genus_vernacular_aggregations.parquet') LIMIT {TEST_LIMIT}"
else:
    genus_query = f"SELECT * FROM read_parquet('{DATA_DIR}/genus_vernacular_aggregations.parquet')"

genus_data = con.execute(genus_query).fetchdf()
functional_categories = con.execute(
    f"SELECT * FROM read_parquet('{DATA_DIR}/functional_categories.parquet')"
).fetchdf()

con.close()

print(f"  ✓ Genera: {len(genus_data):,}")
print(f"  ✓ Categories: {len(functional_categories):,}")

# ============================================================================
# Create Category Prototypes
# ============================================================================

print("\n🧬 Creating category prototype embeddings...")

# Use category names directly as prototypes
# The category names themselves (e.g., "bees", "butterflies", "oaks") are semantic
category_names = functional_categories['category'].unique().tolist()
all_category_texts = category_names
category_text_mapping = {i: cat for i, cat in enumerate(category_names)}

print(f"  Categories to classify: {len(category_names)}")

# Get embeddings for all categories at once
print(f"  Processing {len(all_category_texts)} categories...")
category_embeddings_array = get_embeddings_batch(all_category_texts, show_progress=True)

if category_embeddings_array is None:
    print("❌ Failed to get category embeddings. Exiting.")
    sys.exit(1)

# Map back to category names
valid_categories = []
valid_embeddings = []
for idx, emb in enumerate(category_embeddings_array):
    cat = category_text_mapping[idx]
    valid_categories.append(cat)
    valid_embeddings.append(emb)

# Create matrix for vectorized similarity computation
category_matrix = np.vstack(valid_embeddings)

print(f"  ✓ Created {len(valid_categories)} category prototypes")

# ============================================================================
# Classify All Genera
# ============================================================================

print("\n🔬 Classifying all genera...")
print(f"  Total genera: {len(genus_data):,}")
print(f"  Batch size: {BATCH_SIZE}")
print(f"  Estimated batches: {(len(genus_data) + BATCH_SIZE - 1) // BATCH_SIZE}")

results = []
start_time = time.time()

# Process in batches
for batch_idx in tqdm(range(0, len(genus_data), BATCH_SIZE), desc="Processing batches"):
    batch = genus_data.iloc[batch_idx:batch_idx + BATCH_SIZE]

    # Get embeddings for batch
    batch_texts = batch['vernaculars_all'].tolist()
    genus_embeddings = get_embeddings_batch(batch_texts)

    if genus_embeddings is None:
        print(f"\n⚠️  Batch {batch_idx // BATCH_SIZE} failed, skipping...")
        continue

    # Compute similarities to all categories (vectorized!)
    similarities = cosine_similarity(genus_embeddings, category_matrix)

    # For each genus in batch
    for i, (genus_idx, genus_row) in enumerate(batch.iterrows()):
        genus_sims = similarities[i]

        # Find best matches
        best_idx = genus_sims.argmax()
        best_similarity = genus_sims[best_idx]
        best_category = valid_categories[best_idx]

        # Get top 3 for debugging
        top3_indices = genus_sims.argsort()[-3:][::-1]
        top3_categories = [valid_categories[idx] for idx in top3_indices]
        top3_scores = [genus_sims[idx] for idx in top3_indices]

        results.append({
            'genus': genus_row['genus'],
            'vector_category': best_category if best_similarity >= MIN_SIMILARITY else None,
            'vector_similarity': float(best_similarity),
            'vector_top3_categories': ';'.join(top3_categories),
            'vector_top3_scores': ';'.join([f"{s:.3f}" for s in top3_scores])
        })

    # Small delay to not overwhelm server
    time.sleep(0.01)

elapsed_time = time.time() - start_time

# ============================================================================
# Save Results
# ============================================================================

print(f"\n💾 Saving results...")
results_df = pd.DataFrame(results)
output_path = f"{DATA_DIR}/vector_classifications_kalm.parquet"
results_df.to_parquet(output_path)

print(f"\n{'=' * 80}")
print("✅ CLASSIFICATION COMPLETE")
print(f"{'=' * 80}")
print(f"Classified: {len(results_df):,} genera")
print(f"Output: {output_path}")
print(f"Processing time: {elapsed_time/60:.1f} minutes")
print(f"Throughput: {len(results_df)/elapsed_time:.1f} genera/second")

# Statistics
categorized = results_df['vector_category'].notna().sum()
pct_categorized = 100 * categorized / len(results_df)
mean_sim = results_df['vector_similarity'].mean()
median_sim = results_df['vector_similarity'].median()

print(f"\n📊 Classification Statistics:")
print(f"  Categorized: {categorized:,} ({pct_categorized:.1f}%)")
print(f"  Uncategorized: {len(results_df) - categorized:,} ({100-pct_categorized:.1f}%)")
print(f"  Mean similarity: {mean_sim:.3f}")
print(f"  Median similarity: {median_sim:.3f}")

# Top categories
print(f"\n🏆 Top 10 Categories:")
top_cats = results_df[results_df['vector_category'].notna()]['vector_category'].value_counts().head(10)
for cat, count in top_cats.items():
    pct = 100 * count / len(results_df)
    print(f"  {cat:20s}: {count:5,} ({pct:5.1f}%)")

print(f"\n{'=' * 80}")
print("🎉 Pipeline complete!")
print(f"{'=' * 80}\n")

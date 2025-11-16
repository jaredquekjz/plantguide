#!/usr/bin/env python3
"""
Kimi API - Test 30 Compound Name Cases Where Vectors Failed

Tests cases like:
- "duckweed weevil" (vector → duckweeds, should be → weevils)
- "sugar maple borer" (vector → maples, should be → beetles)
- "fruit bat" (vector → strawberries, should be → bats)

These are the hardest cases where the organism name contains its food source.

Date: 2025-11-15
"""

import os
import asyncio
import pandas as pd
import duckdb
from openai import AsyncOpenAI
from tqdm.asyncio import tqdm_asyncio

# ============================================================================
# Configuration
# ============================================================================

API_KEY = os.getenv("MOONSHOT_API_KEY")
if not API_KEY:
    print("ERROR: MOONSHOT_API_KEY environment variable not set!")
    print("Please run: export MOONSHOT_API_KEY='your-key-here'")
    exit(1)

BASE_URL = "https://api.moonshot.ai/v1"
MODEL = "kimi-k2-thinking"

# Data files
FAILURE_ANALYSIS = "/home/olier/ellenberg/reports/taxonomy/classification_failure_analysis.csv"
ENGLISH_VERN = "/home/olier/ellenberg/data/taxonomy/genus_vernacular_aggregations.parquet"
CHINESE_VERN = "/home/olier/ellenberg/data/taxonomy/genus_vernacular_aggregations_chinese.parquet"

OUTPUT_FILE = "/home/olier/ellenberg/reports/taxonomy/kimi_compound_name_test_30.csv"

# Request settings
BATCH_SIZE = 10
MAX_RETRIES = 3

PROMPT_TEMPLATE = """Based on the vernacular names provided, identify what TYPE of organism this is and output a GENERIC CATEGORY label.

IMPORTANT: We need a category for grouping in reports (e.g., "25% Bees, 30% Butterflies").
- Output the ORGANISM TYPE, not specific names
- Example: "duckweed weevil" → output "Weevils" (NOT "Duckweed weevil")
- Example: "carpenter bee" → output "Bees" (NOT "Carpenter bees")
- Example: "garden tiger moth" → output "Moths" (NOT "Garden tiger moth")

Rules:
- Use the most common/obvious organism type from the English names
- Always use plural form (e.g., "Aphids", "Beetles", "Bees", "Moths", "Butterflies")
- Keep it simple and generic (1-2 words max)
- Output ONLY in English, even if Chinese names are provided

Genus: {genus}
English names: {english}
Chinese names: {chinese}

Output ONLY the generic category, nothing else."""

# ============================================================================
# Setup
# ============================================================================

print("=" * 80)
print("Kimi API - Testing 30 Compound Name Failures")
print("=" * 80)
print()
print(f"API Key: {API_KEY[:10]}...{API_KEY[-4:]}")
print(f"Model: {MODEL}")
print(f"Batch size: {BATCH_SIZE}")
print()

# Initialize async client
client = AsyncOpenAI(
    api_key=API_KEY,
    base_url=BASE_URL
)

# ============================================================================
# Load Data
# ============================================================================

print("Loading data...")

# Load failure analysis
failures_df = pd.read_csv(FAILURE_ANALYSIS)
print(f"  Failures analyzed: {len(failures_df):,}")

# Get top 30 compound name failures (prioritize high similarity but wrong category)
# These are cases where vector was CONFIDENT but WRONG
compound_failures = failures_df.head(30).copy()
print(f"  Selected for testing: {len(compound_failures)}")

# Load vernaculars
con = duckdb.connect()
english_df = con.execute(f"SELECT * FROM read_parquet('{ENGLISH_VERN}')").fetchdf()
chinese_df = con.execute(f"SELECT * FROM read_parquet('{CHINESE_VERN}')").fetchdf()
con.close()

print(f"  English vernaculars: {len(english_df):,} genera")
print(f"  Chinese vernaculars: {len(chinese_df):,} genera")
print()

# ============================================================================
# Prepare Request Data
# ============================================================================

print("Preparing test cases...")

request_data = []

for _, row in compound_failures.iterrows():
    genus = row['genus']

    # Get English vernaculars
    eng_row = english_df[english_df['genus'] == genus]
    eng_vern = eng_row['vernaculars_all'].values[0] if len(eng_row) > 0 else "none"

    # Get Chinese vernaculars
    chn_row = chinese_df[chinese_df['genus'] == genus]
    chn_vern = chn_row['vernaculars_all'].values[0] if len(chn_row) > 0 else "none"

    # Truncate if too long
    if len(eng_vern) > 200:
        eng_vern = eng_vern[:200] + "..."
    if len(chn_vern) > 150:
        chn_vern = chn_vern[:150] + "..."

    request_data.append({
        'genus': genus,
        'english': eng_vern,
        'chinese': chn_vern,
        'vector_guess': row['assigned_category'],
        'vector_similarity': row['similarity']
    })

print(f"  Prepared {len(request_data)} test requests")
print()

# Display sample
print("Sample test cases (first 5):")
print("-" * 80)
for i, data in enumerate(request_data[:5], 1):
    print(f"\n{i}. {data['genus']}")
    print(f"   English: {data['english'][:60]}...")
    print(f"   Vector guessed: {data['vector_guess']} (similarity: {data['vector_similarity']:.3f})")

print("\n")

# ============================================================================
# Async Request Function
# ============================================================================

async def get_gardener_label(data, semaphore):
    """Get gardener-friendly label for a genus with retry logic."""

    async with semaphore:
        genus = data['genus']

        prompt = PROMPT_TEMPLATE.format(
            genus=genus,
            english=data['english'],
            chinese=data['chinese']
        )

        for attempt in range(MAX_RETRIES):
            try:
                response = await client.chat.completions.create(
                    model=MODEL,
                    messages=[
                        {
                            "role": "system",
                            "content": "You are a gardening expert. Provide concise, clear common names."
                        },
                        {
                            "role": "user",
                            "content": prompt
                        }
                    ],
                    temperature=0.3,
                    max_tokens=500  # kimi-k2-thinking needs ~170 tokens (reasoning + answer)
                )

                label = response.choices[0].message.content.strip()
                label = label.strip('."\'')

                return {
                    'genus': genus,
                    'english_vern': data['english'][:60] + "..." if len(data['english']) > 60 else data['english'],
                    'chinese_vern': data['chinese'][:30] + "..." if len(data['chinese']) > 30 else data['chinese'],
                    'vector_guess': data['vector_guess'],
                    'vector_similarity': data['vector_similarity'],
                    'kimi_label': label,
                    'success': True,
                    'error': None
                }

            except Exception as e:
                if attempt == MAX_RETRIES - 1:
                    return {
                        'genus': genus,
                        'english_vern': data['english'][:60],
                        'chinese_vern': data['chinese'][:30],
                        'vector_guess': data['vector_guess'],
                        'vector_similarity': data['vector_similarity'],
                        'kimi_label': None,
                        'success': False,
                        'error': str(e)
                    }
                await asyncio.sleep(1)

# ============================================================================
# Process Batch
# ============================================================================

async def process_batch(batch, semaphore):
    """Process a batch of requests concurrently."""
    tasks = [get_gardener_label(data, semaphore) for data in batch]
    return await asyncio.gather(*tasks)

async def main():
    """Main async function."""
    semaphore = asyncio.Semaphore(BATCH_SIZE)
    results = await process_batch(request_data, semaphore)
    return results

# ============================================================================
# Run Processing
# ============================================================================

print("Starting API requests...")
print(f"Processing {len(request_data)} compound name test cases...\\n")

results = asyncio.run(main())

# ============================================================================
# Display Results
# ============================================================================

print("\\n" + "=" * 80)
print("RESULTS - Compound Name Test")
print("=" * 80)
print()

results_df = pd.DataFrame(results)

n_success = results_df['success'].sum()
n_failed = (~results_df['success']).sum()

print(f"Success: {n_success}/{len(results_df)}")
print(f"Failed: {n_failed}/{len(results_df)}")
print()

if n_success > 0:
    print("Kimi vs Vector Comparison:")
    print("-" * 80)
    successful = results_df[results_df['success']].copy()

    for _, row in successful.iterrows():
        print(f"\\n{row['genus']:20s}")
        print(f"  English: {row['english_vern']}")
        print(f"  Vector → {row['vector_guess']} (similarity: {row['vector_similarity']:.3f})")
        print(f"  Kimi   → {row['kimi_label']}")

if n_failed > 0:
    print("\\nErrors:")
    print("-" * 80)
    failed = results_df[~results_df['success']]
    for _, row in failed.iterrows():
        print(f"{row['genus']:20s} → ERROR: {row['error']}")

# Save
print(f"\\nSaving to: {OUTPUT_FILE}")
results_df.to_csv(OUTPUT_FILE, index=False)

print(f"\\n✓ Test complete")
print("=" * 80)

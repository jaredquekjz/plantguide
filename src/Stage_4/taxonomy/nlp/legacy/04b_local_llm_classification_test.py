#!/usr/bin/env python3
"""
Local LLM-Based Organism Classification Test

Uses vLLM server (localhost:8000) to classify organisms.
Tests whether LLM reasoning can overcome vector similarity limitations.

Input:
    - data/taxonomy/genus_vernacular_aggregations.parquet

Output:
    - reports/taxonomy/local_llm_classification_test.csv

Prerequisites:
    - vLLM server running on localhost:8000 with instruction-tuned model

Date: 2025-11-15
"""

import pandas as pd
import duckdb
from openai import OpenAI
from tqdm import tqdm
import time

# ============================================================================
# Configuration
# ============================================================================

VLLM_URL = "http://localhost:8000/v1"
MODEL_NAME = "meta-llama/Llama-3.3-70B-Instruct"  # Or whatever model is loaded

GENUS_FILE = "/home/olier/ellenberg/data/taxonomy/genus_vernacular_aggregations.parquet"
OUTPUT_FILE = "/home/olier/ellenberg/reports/taxonomy/local_llm_classification_test.csv"

# Test on same problematic cases from failure analysis
TEST_GENERA = [
    "Tanysphyrus",  # duckweed weevil → should be weevils
    "Glycobius",    # sugar maple borer → should be beetles
    "Paragrilus",   # metallic woodborer → should be beetles
    "Euschemon",    # regent skipper → should be butterflies
    "Eidolon",      # straw-colored fruit bat → should be bats
    "Symbrenthia",  # jesters → should be butterflies
    "Rhizophora",   # red mangrove → should be trees
    "Liparis",      # orchids → should be orchids
    "Boloria",      # fritillary → should be butterflies
    "Arctia",       # tiger moth → should be moths
    "Heilipus",     # avocado weevil → should be weevils
    "Oxya",         # rice grasshopper → should be grasshoppers
    "Apodemia",     # metalmark → should be butterflies
    "Graphium",     # swallowtail → should be butterflies
]

# Simplified category list for testing
CATEGORIES = [
    "bees", "butterflies", "moths", "beetles", "weevils", "grasshoppers",
    "flies", "wasps", "ants", "spiders", "dragonflies",
    "birds", "bats", "mammals",
    "trees", "shrubs", "flowers", "orchids", "grasses", "ferns"
]

SYSTEM_PROMPT = """You are a biological taxonomist. Classify organisms into functional categories based on their scientific genus name and common names.

CRITICAL RULES:
1. Many insect names follow "[host plant] + [insect type]" (e.g., "oak gall wasp" IS a wasp, NOT oak)
2. Focus on what the ORGANISM IS, not what it eats or where it lives
3. "borer" beetles are BEETLES
4. "skipper" butterflies are BUTTERFLIES (not skinks)
5. Parse compound names carefully

Respond with ONLY the category name, nothing else."""

USER_PROMPT_TEMPLATE = """Genus: {genus}
Common names: {vernaculars}

Categories: {categories}

Category:"""

# ============================================================================
# Setup
# ============================================================================

print("=" * 80)
print("Local LLM Classification Test (vLLM)")
print("=" * 80)
print()

# Initialize vLLM client
client = OpenAI(api_key="EMPTY", base_url=VLLM_URL)

# Test connection
try:
    models = client.models.list()
    print(f"✓ Connected to vLLM server")
    print(f"  Available models: {[m.id for m in models.data]}")
    print()
except Exception as e:
    print(f"ERROR: Cannot connect to vLLM server at {VLLM_URL}")
    print(f"  {e}")
    print("\nPlease ensure vLLM is running with an instruction-tuned model")
    exit(1)

# ============================================================================
# Load Data
# ============================================================================

print("Loading vernacular data...")
con = duckdb.connect()
genera_df = con.execute(f"SELECT * FROM read_parquet('{GENUS_FILE}')").fetchdf()
con.close()

print(f"  Loaded {len(genera_df):,} genera")
print()

# Filter to test cases
test_df = genera_df[genera_df['genus'].isin(TEST_GENERA)].copy()
print(f"Testing on {len(test_df)} genera")
print()

# ============================================================================
# LLM Classification
# ============================================================================

print("Classifying with local LLM...")
print()

results = []

for idx, row in tqdm(test_df.iterrows(), total=len(test_df), desc="Classifying"):
    genus = row['genus']
    vernaculars = row['vernaculars_all']

    # Truncate if too long
    if len(vernaculars) > 300:
        vernaculars = vernaculars[:300] + "..."

    # Create prompt
    user_prompt = USER_PROMPT_TEMPLATE.format(
        genus=genus,
        vernaculars=vernaculars,
        categories=", ".join(CATEGORIES)
    )

    # Call vLLM
    try:
        response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_prompt}
            ],
            max_tokens=20,
            temperature=0.0
        )

        category = response.choices[0].message.content.strip().lower()

        # Extract just the category word
        category = category.split()[0].strip('.,;:')

        # Validate category
        if category not in CATEGORIES:
            # Try to find closest match
            for cat in CATEGORIES:
                if cat in category or category in cat:
                    category = cat
                    break
            else:
                category = "unknown"

        results.append({
            'genus': genus,
            'vernaculars': vernaculars[:100],
            'llm_category': category,
            'success': True
        })

    except Exception as e:
        print(f"  Error classifying {genus}: {e}")
        results.append({
            'genus': genus,
            'vernaculars': vernaculars[:100],
            'llm_category': 'error',
            'success': False
        })

    time.sleep(0.5)  # Rate limiting

# ============================================================================
# Create Results DataFrame
# ============================================================================

results_df = pd.DataFrame(results)

# ============================================================================
# Write Output
# ============================================================================

print()
print("Writing output...")
print(f"  Output: {OUTPUT_FILE}")

results_df.to_csv(OUTPUT_FILE, index=False)

print(f"\n✓ Successfully classified {len(results_df)} genera")

# ============================================================================
# Display Results
# ============================================================================

print("\n" + "=" * 80)
print("LLM Classification Results")
print("=" * 80)
print()

# Expected categories (manual ground truth)
expected = {
    "Tanysphyrus": "weevils",
    "Glycobius": "beetles",
    "Paragrilus": "beetles",
    "Euschemon": "butterflies",
    "Eidolon": "bats",
    "Symbrenthia": "butterflies",
    "Rhizophora": "trees",
    "Liparis": "orchids",
    "Boloria": "butterflies",
    "Arctia": "moths",
    "Heilipus": "weevils",
    "Oxya": "grasshoppers",
    "Apodemia": "butterflies",
    "Graphium": "butterflies"
}

correct = 0
total = 0

for idx, row in results_df.iterrows():
    genus = row['genus']
    llm_cat = row['llm_category']
    exp_cat = expected.get(genus, "?")

    is_correct = llm_cat == exp_cat
    if is_correct:
        correct += 1
        marker = "✓"
    else:
        marker = "✗"

    total += 1

    print(f"{marker} {genus:15s} → {llm_cat:15s} (expected: {exp_cat})")

accuracy = correct / total * 100 if total > 0 else 0
print()
print(f"Accuracy: {correct}/{total} ({accuracy:.1f}%)")

print("\n" + "=" * 80)
print("Complete")
print("=" * 80)
print()

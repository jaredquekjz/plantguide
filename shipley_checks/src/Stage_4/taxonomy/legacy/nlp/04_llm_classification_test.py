#!/usr/bin/env python3
"""
LLM-Based Organism Classification Test

Uses Claude API to classify organisms based on genus name + vernacular names.
Tests whether LLM reasoning + knowledge can overcome vector similarity limitations.

Input:
    - data/taxonomy/genus_vernacular_aggregations.parquet

Output:
    - reports/taxonomy/llm_classification_test.csv

Prerequisites:
    - ANTHROPIC_API_KEY environment variable

Date: 2025-11-15
"""

import os
import pandas as pd
import duckdb
from anthropic import Anthropic
from tqdm import tqdm
import time
import json

# ============================================================================
# Configuration
# ============================================================================

GENUS_FILE = "/home/olier/ellenberg/data/taxonomy/genus_vernacular_aggregations.parquet"
OUTPUT_FILE = "/home/olier/ellenberg/reports/taxonomy/llm_classification_test.csv"

# Test on same problematic cases from failure analysis
TEST_GENERA = [
    "Tanysphyrus",  # duckweed weevil → should be weevils
    "Glycobius",    # sugar maple borer → should be beetles
    "Paragrilus",   # metallic woodborer → should be beetles
    "Euschemon",    # regent skipper → should be butterflies
    "Eidolon",      # straw-colored fruit bat → should be bats
    "Symbrenthia",  # jesters → should be butterflies
    "Rhizophora",   # red mangrove → should be mangroves/trees
    "Liparis",      # orchids → should be orchids
    "Boloria",      # fritillary → should be butterflies
    "Arctia",       # tiger moth → should be moths
    "Heilipus",     # avocado weevil → should be weevils
    "Oxya",         # rice grasshopper → should be grasshoppers
    "Apodemia",     # metalmark → should be butterflies
    "Graphium",     # swallowtail → should be butterflies
    # Add some more challenging cases
    "Apis",         # honey bee
    "Bombus",       # bumblebee
    "Papilio",      # swallowtail butterflies
    "Danaus",       # monarch butterfly
    "Helianthus",   # sunflower
    "Quercus",      # oak
]

# Functional categories (same as vector classification)
CATEGORIES = [
    "bees", "butterflies", "moths", "beetles", "weevils", "grasshoppers",
    "flies", "wasps", "ants", "spiders", "dragonflies", "damselflies",
    "lacewings", "ladybugs", "hoverflies", "sawflies", "aphids", "scale insects",
    "leafhoppers", "assassin bugs", "ground beetles", "carrion beetles",
    "caterpillars", "stick insects", "mantises",
    "birds", "songbirds", "raptors", "woodpeckers", "hummingbirds", "swallows",
    "mammals", "rodents", "bats", "deer", "squirrels", "mice",
    "trees", "oaks", "maples", "pines", "willows", "birches",
    "shrubs", "roses", "rhododendrons", "viburnums", "hollies",
    "flowers", "wildflowers", "lilies", "orchids", "sunflowers",
    "grasses", "sedges", "ferns", "mosses", "liverworts"
]

PROMPT_TEMPLATE = """You are a biological taxonomist. Given a genus name and its common/vernacular names, classify it into ONE of the following functional categories:

{categories}

IMPORTANT:
- Many insect names follow "[host plant] + [insect type]" pattern (e.g., "oak gall wasp" is a WASP, not oak)
- Focus on what the ORGANISM IS, not what it eats or where it lives
- "borer" beetles are BEETLES, not related to birds
- "skipper" butterflies are BUTTERFLIES, not lizards (skinks)
- Use your biological knowledge to disambiguate

Genus: {genus}
Common names: {vernaculars}

Respond with ONLY the category name from the list above, nothing else. If uncertain, respond with "unknown"."""

# ============================================================================
# Setup
# ============================================================================

print("=" * 80)
print("LLM-Based Classification Test")
print("=" * 80)
print()

# Check API key
api_key = os.getenv("ANTHROPIC_API_KEY")
if not api_key:
    print("ERROR: ANTHROPIC_API_KEY environment variable not set")
    print("Please set it with your Anthropic API key")
    exit(1)

client = Anthropic(api_key=api_key)

# ============================================================================
# Load Data
# ============================================================================

print("Loading vernacular data...")
con = duckdb.connect()
genera_df = con.execute(f"SELECT * FROM read_parquet('{GENUS_FILE}')").fetchdf()
con.close()

print(f"  Loaded {len(genera_df):,} genera with vernaculars")
print()

# Filter to test cases
test_df = genera_df[genera_df['genus'].isin(TEST_GENERA)].copy()
print(f"Testing on {len(test_df)} genera")
print()

# ============================================================================
# LLM Classification
# ============================================================================

print("Classifying with Claude API...")
print()

results = []

for idx, row in tqdm(test_df.iterrows(), total=len(test_df), desc="Classifying"):
    genus = row['genus']
    vernaculars = row['vernaculars_all']

    # Truncate if too long (Claude has token limits)
    if len(vernaculars) > 500:
        vernaculars = vernaculars[:500] + "..."

    # Create prompt
    prompt = PROMPT_TEMPLATE.format(
        categories=", ".join(CATEGORIES),
        genus=genus,
        vernaculars=vernaculars
    )

    # Call Claude API
    try:
        response = client.messages.create(
            model="claude-3-5-sonnet-20241022",
            max_tokens=50,
            messages=[{
                "role": "user",
                "content": prompt
            }]
        )

        category = response.content[0].text.strip().lower()

        # Validate category
        if category not in CATEGORIES and category != "unknown":
            print(f"  Warning: {genus} returned invalid category '{category}'")
            category = "unknown"

        results.append({
            'genus': genus,
            'vernaculars': vernaculars,
            'llm_category': category,
            'success': True
        })

    except Exception as e:
        print(f"  Error classifying {genus}: {e}")
        results.append({
            'genus': genus,
            'vernaculars': vernaculars,
            'llm_category': 'error',
            'success': False
        })

    # Rate limiting - be nice to the API
    time.sleep(1)

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

for idx, row in results_df.iterrows():
    print(f"{row['genus']:20s} → {row['llm_category']}")
    if len(row['vernaculars']) <= 60:
        print(f"  Vernaculars: {row['vernaculars']}")
    else:
        print(f"  Vernaculars: {row['vernaculars'][:60]}...")
    print()

print("=" * 80)
print("Complete")
print("=" * 80)
print()

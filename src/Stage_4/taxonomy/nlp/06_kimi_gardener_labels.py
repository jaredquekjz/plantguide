#!/usr/bin/env python3
"""
Kimi API - Generate Gardener-Friendly Labels for Animal Genera

Uses Moonshot (Kimi) API with concurrent requests to generate
simple, gardener-friendly common names for beneficial organisms.

Only processes ANIMAL genera (insects, birds, mammals, etc.)

Output: Single common name per genus that gardeners can understand.

Date: 2025-11-15
"""

import os
import time
import pandas as pd
import duckdb
from collections import deque
from openai import OpenAI

# ============================================================================
# Configuration
# ============================================================================

API_KEY = os.getenv("MOONSHOT_API_KEY")
if not API_KEY:
    print("ERROR: MOONSHOT_API_KEY environment variable not set!")
    print("Please run: export MOONSHOT_API_KEY='your-key-here'")
    exit(1)

BASE_URL = "https://api.moonshot.ai/v1"
MODEL = "kimi-k2-turbo-preview"

# Data files
ORGANISMS_FILE = "/home/olier/ellenberg/data/taxonomy/animal_genera_with_vernaculars.parquet"  # Pre-filtered: Metazoa + has vernaculars + deduplicated
ENGLISH_VERN = "/home/olier/ellenberg/data/taxonomy/genus_vernacular_aggregations.parquet"
CHINESE_VERN = "/home/olier/ellenberg/data/taxonomy/genus_vernacular_aggregations_chinese.parquet"

OUTPUT_FILE = "/home/olier/ellenberg/data/taxonomy/kimi_gardener_labels.csv"

# Rate limiting settings
MAX_REQUESTS_PER_MINUTE = 200
MAX_RETRIES = 3

# Test mode flag - set to False for full production run
TEST_MODE = False
TEST_LIMIT = 100

PROMPT_TEMPLATE = """Based on the vernacular names provided, categorize this organism into ONE of the standard gardening categories below.

STANDARD CATEGORIES (use these first):
- Moths
- Beetles
- Butterflies
- Flies
- Wasps
- Bees
- Bugs
- Ants
- Aphids
- Leafhoppers
- Spiders
- Scales
- Grasshoppers
- Thrips
- Mites
- Snails
- Dragonflies
- Lacewings
- Birds
- Bats
- Millipedes
- Centipedes
- Springtails
- Nematodes
- Earwigs
- Termites
- Cockroaches
- Mantises
- Stick insects
- Lice
- Fleas
- Ticks
- Psyllids
- Planthoppers
- Treehoppers
- Cicadas
- Spittlebugs
- Barklice

FALLBACK: If the organism clearly does not fit any standard category above, output the most appropriate generic category (e.g., "Crabs", "Snakes", "Frogs", "Fish"). Always use plural form.

RULES:
- Output ONLY the category name, nothing else
- Use the STANDARD CATEGORIES whenever possible
- Always use plural form
- Focus on the organism TYPE, not specific names or host plants
- Example: "carpenter bee" → "Bees"
- Example: "duckweed weevil" → "Beetles"
- Example: "julia butterfly" → "Butterflies"

Genus: {genus}
English names: {english}
Chinese names: {chinese}

Output ONLY the category name:"""

# ============================================================================
# Setup
# ============================================================================

print("=" * 80)
print("Kimi API - Gardener-Friendly Labels for Animals")
print("=" * 80)
print()
print(f"API Key: {API_KEY[:10]}...{API_KEY[-4:]}")
print(f"Model: {MODEL}")
print(f"Rate limit: {MAX_REQUESTS_PER_MINUTE} requests/minute (sequential processing)")
print()

# ============================================================================
# Load Data
# ============================================================================

print("Loading data...")
con = duckdb.connect()

# Load animal genera (pre-filtered: Metazoa + has vernaculars + deduplicated)
genera_df = con.execute(f"SELECT * FROM read_parquet('{ORGANISMS_FILE}')").fetchdf()
print(f"  Animal genera: {len(genera_df):,}")
print(f"  Filters: Metazoa only + has vernaculars + deduplicated")

# Extract genus list (already unique, one per row)
animal_genera = genera_df['genus'].values
print(f"  Genera to process: {len(animal_genera):,}")

# Load vernaculars (FILTER TO ANIMALIA KINGDOM to prevent plant contamination)
print("  Loading vernaculars (filtering to Animalia kingdom to prevent homonym contamination)...")
english_df = con.execute(f"""
    SELECT genus, vernaculars_all, n_vernaculars
    FROM read_parquet('{ENGLISH_VERN}')
    WHERE kingdom = 'Animalia'
""").fetchdf()
print(f"  English vernaculars: {len(english_df):,} animal genera")

chinese_df = con.execute(f"""
    SELECT genus, vernaculars_all, n_vernaculars
    FROM read_parquet('{CHINESE_VERN}')
    WHERE kingdom = 'Animalia'
""").fetchdf()
print(f"  Chinese vernaculars: {len(chinese_df):,} animal genera")

con.close()
print()

# ============================================================================
# Prepare Request Data
# ============================================================================

print("Preparing request data...")

request_data = []

# Apply test mode limit if enabled
genera_to_process = animal_genera[:TEST_LIMIT] if TEST_MODE else animal_genera

print(f"{'TEST MODE: ' if TEST_MODE else ''}Processing {len(genera_to_process):,} genera")
print()

for genus in genera_to_process:
    # Get English vernaculars
    eng_row = english_df[english_df['genus'] == genus]
    eng_vern = eng_row['vernaculars_all'].values[0] if len(eng_row) > 0 else "none"

    # Get Chinese vernaculars
    chn_row = chinese_df[chinese_df['genus'] == genus]
    chn_vern = chn_row['vernaculars_all'].values[0] if len(chn_row) > 0 else "none"

    # For API prompt: truncate long strings
    eng_vern_truncated = eng_vern[:200] + "..." if len(eng_vern) > 200 else eng_vern
    chn_vern_truncated = chn_vern[:150] + "..." if len(chn_vern) > 150 else chn_vern

    request_data.append({
        'genus': genus,
        'english_full': eng_vern,  # Store full for output
        'chinese_full': chn_vern,  # Store full for output
        'english': eng_vern_truncated,  # Truncated for API
        'chinese': chn_vern_truncated   # Truncated for API
    })

print(f"  Prepared {len(request_data)} animal genera for processing")
print(f"  (English + Chinese vernaculars where available)")
print()

# ============================================================================
# Synchronous Request Function with Rate Limiting
# ============================================================================

# Initialize synchronous client
sync_client = OpenAI(
    api_key=API_KEY,
    base_url=BASE_URL
)

def get_gardener_label(data, request_timestamps):
    """Get gardener-friendly label for a genus with retry logic and rate limiting."""

    genus = data['genus']

    # Rate limiting: ensure we don't exceed MAX_REQUESTS_PER_MINUTE
    current_time = time.time()

    # Remove timestamps older than 60 seconds
    while request_timestamps and current_time - request_timestamps[0] > 60:
        request_timestamps.popleft()

    # If we've hit the limit, sleep until we can send another request
    if len(request_timestamps) >= MAX_REQUESTS_PER_MINUTE:
        sleep_time = 60 - (current_time - request_timestamps[0])
        if sleep_time > 0:
            print(f"  [Rate limit] Sleeping {sleep_time:.1f}s...", end=" ", flush=True)
            time.sleep(sleep_time)
            # Clear old timestamps after sleep
            current_time = time.time()
            while request_timestamps and current_time - request_timestamps[0] > 60:
                request_timestamps.popleft()

    # Record this request
    request_timestamps.append(time.time())

    prompt = PROMPT_TEMPLATE.format(
        genus=genus,
        english=data['english'],
        chinese=data['chinese']
    )

    for attempt in range(MAX_RETRIES):
        try:
            response = sync_client.chat.completions.create(
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
                max_tokens=200
            )

            label = response.choices[0].message.content.strip()
            label = label.strip('."\'')

            return {
                'genus': genus,
                'english_vernacular': data['english_full'],
                'chinese_vernacular': data['chinese_full'],
                'kimi_label': label,
                'success': True,
                'error': None
            }

        except Exception as e:
            if attempt == MAX_RETRIES - 1:
                return {
                    'genus': genus,
                    'english_vernacular': data['english_full'],
                    'chinese_vernacular': data['chinese_full'],
                    'kimi_label': None,
                    'success': False,
                    'error': str(e)
                }
            time.sleep(1)

# ============================================================================
# Run Processing with Incremental Output and Rate Limiting
# ============================================================================

print("Starting API requests...")
mode_str = "TEST MODE - " if TEST_MODE else ""
print(f"{mode_str}Processing {len(request_data)} animal genera (Metazoa only)...\n")

# Initialize output file with header
output_df = pd.DataFrame(columns=['genus', 'english_vernacular', 'chinese_vernacular', 'kimi_label', 'success', 'error'])
output_df.to_csv(OUTPUT_FILE, index=False)
print(f"Initialized output file: {OUTPUT_FILE}\n")

# Track request timestamps for rate limiting
request_timestamps = deque()

# Process sequentially with incremental output every 50 genera
CHUNK_SIZE = 50
total_genera = len(request_data)
all_results = []
chunk_results = []

start_time = time.time()

for idx, data in enumerate(request_data, 1):
    # Process one request
    result = get_gardener_label(data, request_timestamps)
    all_results.append(result)
    chunk_results.append(result)

    # Every CHUNK_SIZE genera, write to CSV and show progress
    if idx % CHUNK_SIZE == 0 or idx == total_genera:
        # Append to CSV
        chunk_df = pd.DataFrame(chunk_results)
        chunk_df.to_csv(OUTPUT_FILE, mode='a', header=False, index=False)

        # Calculate stats
        n_success = sum(1 for r in chunk_results if r['success'])
        n_failed = len(chunk_results) - n_success
        elapsed = time.time() - start_time
        rate = idx / (elapsed / 60)  # requests per minute
        eta_minutes = (total_genera - idx) / rate if rate > 0 else 0

        # Show progress
        print(f"Progress: {idx:4d}/{total_genera} | Success: {n_success:2d}/{len(chunk_results):2d} | "
              f"Rate: {rate:5.1f} req/min | ETA: {eta_minutes:.1f} min")

        # Reset chunk
        chunk_results = []

results = all_results

# ============================================================================
# Display Results
# ============================================================================

print("\n" + "=" * 80)
print("RESULTS - SANITY CHECK")
print("=" * 80)
print()

results_df = pd.DataFrame(results)

n_success = results_df['success'].sum()
n_failed = (~results_df['success']).sum()

print(f"Success: {n_success}/{len(results_df)}")
print(f"Failed: {n_failed}/{len(results_df)}")
print()

if n_success > 0:
    print("Generated Labels (sample - first 10):")
    print("-" * 80)
    successful = results_df[results_df['success']].head(10)
    for _, row in successful.iterrows():
        print(f"\n{row['genus']:20s} → {row['kimi_label']}")
        eng = row['english_vernacular']
        print(f"  English: {eng[:80]}{'...' if len(eng) > 80 else ''}")
        if row['chinese_vernacular'] != 'none':
            chn = row['chinese_vernacular']
            print(f"  Chinese: {chn[:60]}{'...' if len(chn) > 60 else ''}")

if n_failed > 0:
    print("\nErrors:")
    print("-" * 80)
    failed = results_df[~results_df['success']]
    for _, row in failed.iterrows():
        print(f"{row['genus']:20s} → ERROR: {row['error']}")

# Save
print(f"\nSaving to: {OUTPUT_FILE}")
results_df.to_csv(OUTPUT_FILE, index=False)

print(f"\n✓ Processing complete - {n_success}/{len(results_df)} genera successfully labeled")
print("\n" + "=" * 80)

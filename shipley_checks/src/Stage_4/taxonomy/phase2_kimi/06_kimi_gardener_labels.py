#!/usr/bin/env python3
"""
Kimi API - Generate Gardener-Friendly Labels for Animal Genera

Uses Moonshot (Kimi) API with 2 concurrent requests to generate
simple, gardener-friendly common names for beneficial organisms.

Only processes ANIMAL genera (insects, birds, mammals, etc.)

Output: Single common name per genus that gardeners can understand.

Date: 2025-11-16
"""

import os
import time
import asyncio
import pandas as pd
import duckdb
from collections import deque
from openai import AsyncOpenAI

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
ORGANISMS_FILE = "/home/olier/ellenberg/data/taxonomy/animal_genera_with_vernaculars.parquet"
ENGLISH_VERN = "/home/olier/ellenberg/data/taxonomy/genus_vernacular_aggregations.parquet"
CHINESE_VERN = "/home/olier/ellenberg/data/taxonomy/genus_vernacular_aggregations_chinese.parquet"

OUTPUT_FILE = "/home/olier/ellenberg/data/taxonomy/kimi_gardener_labels.csv"

# Rate limiting settings
MAX_REQUESTS_PER_MINUTE = 200
MAX_CONCURRENT = 2  # 2 concurrent requests
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
print(f"Concurrency: {MAX_CONCURRENT} concurrent requests")
print(f"Rate limit: {MAX_REQUESTS_PER_MINUTE} requests/minute")
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
# Async Request Function with Rate Limiting
# ============================================================================

# Shared state for rate limiting
request_timestamps = deque()
rate_limit_lock = asyncio.Lock()

async def get_gardener_label(data, client, semaphore):
    """Get gardener-friendly label for a genus with retry logic and rate limiting."""

    genus = data['genus']

    async with semaphore:  # Limit concurrent requests
        # Rate limiting
        async with rate_limit_lock:
            current_time = time.time()

            # Remove timestamps older than 60 seconds
            while request_timestamps and current_time - request_timestamps[0] > 60:
                request_timestamps.popleft()

            # If we've hit the limit, sleep until we can send another request
            if len(request_timestamps) >= MAX_REQUESTS_PER_MINUTE:
                sleep_time = 60 - (current_time - request_timestamps[0])
                if sleep_time > 0:
                    await asyncio.sleep(sleep_time)
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
                    max_tokens=200
                )

                label = response.choices[0].message.content.strip()

                return {
                    'genus': genus,
                    'english_vernacular': data['english_full'],
                    'chinese_vernacular': data['chinese_full'],
                    'kimi_label': label,
                    'success': True,
                    'error': ''
                }

            except Exception as e:
                error_msg = str(e)

                if attempt < MAX_RETRIES - 1:
                    await asyncio.sleep(2 ** attempt)  # Exponential backoff
                    continue
                else:
                    return {
                        'genus': genus,
                        'english_vernacular': data['english_full'],
                        'chinese_vernacular': data['chinese_full'],
                        'kimi_label': '',
                        'success': False,
                        'error': error_msg
                    }

# ============================================================================
# Main Processing Loop
# ============================================================================

async def main():
    """Main async processing loop."""

    # Initialize async client
    async_client = AsyncOpenAI(
        api_key=API_KEY,
        base_url=BASE_URL
    )

    # Create semaphore to limit concurrent requests
    semaphore = asyncio.Semaphore(MAX_CONCURRENT)

    # Write CSV header
    with open(OUTPUT_FILE, 'w') as f:
        f.write("genus,english_vernacular,chinese_vernacular,kimi_label,success,error\n")

    print(f"Starting processing with {MAX_CONCURRENT} concurrent requests...")
    print(f"Output file: {OUTPUT_FILE}")
    print()

    # Process in chunks for incremental output
    CHUNK_SIZE = 50
    total_genera = len(request_data)
    all_results = []

    start_time = time.time()

    for chunk_start in range(0, total_genera, CHUNK_SIZE):
        chunk_end = min(chunk_start + CHUNK_SIZE, total_genera)
        chunk_data = request_data[chunk_start:chunk_end]

        # Process chunk concurrently
        tasks = [get_gardener_label(data, async_client, semaphore) for data in chunk_data]
        chunk_results = await asyncio.gather(*tasks)

        all_results.extend(chunk_results)

        # Write chunk to CSV
        chunk_df = pd.DataFrame(chunk_results)
        chunk_df.to_csv(OUTPUT_FILE, mode='a', header=False, index=False)

        # Calculate stats
        n_success = sum(1 for r in chunk_results if r['success'])
        n_failed = len(chunk_results) - n_success
        elapsed = time.time() - start_time
        rate = chunk_end / (elapsed / 60)  # requests per minute
        eta_minutes = (total_genera - chunk_end) / rate if rate > 0 else 0

        # Show progress
        print(f"Progress: {chunk_end:4d}/{total_genera} | Success: {n_success:2d}/{len(chunk_results):2d} | "
              f"Rate: {rate:5.1f} req/min | ETA: {eta_minutes:.1f} min")

    await async_client.close()

    print()
    print("=" * 80)
    print("Processing complete!")
    print("=" * 80)
    print()

    # Final summary
    total_success = sum(1 for r in all_results if r['success'])
    total_failed = len(all_results) - total_success
    total_time = time.time() - start_time

    print(f"Total processed: {len(all_results):,}")
    print(f"  Successful: {total_success:,} ({100*total_success/len(all_results):.1f}%)")
    print(f"  Failed: {total_failed:,}")
    print(f"Total time: {total_time/60:.1f} minutes")
    print(f"Average rate: {len(all_results)/(total_time/60):.1f} req/min")
    print()
    print(f"Output: {OUTPUT_FILE}")

# ============================================================================
# Run
# ============================================================================

if __name__ == "__main__":
    asyncio.run(main())

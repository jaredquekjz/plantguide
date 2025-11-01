#!/usr/bin/env python3
"""
Stage 4: Extract GloBI Interactions for Final Dataset (11,680 species)

Matches the WFO IDs from the final Stage 3 dataset against GloBI interactions,
capturing all biotic interactions where the plant species appears as either
source or target.

This captures:
- Pollinators (insects/animals that pollinate the plant)
- Herbivores (animals that eat the plant)
- Pathogens (fungi/bacteria that attack the plant)
- Parasites, mutualists, dispersers, etc.

Input:
- model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet
- data/stage1/globi_interactions_plants_wfo.parquet

Output:
- data/stage4/globi_interactions_final_dataset_11680.parquet
"""

import duckdb
from pathlib import Path
from datetime import datetime

# Paths
final_dataset = 'model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet'
globi_plants = 'data/stage1/globi_interactions_plants_wfo.parquet'
output_dir = Path('data/stage4')
output_dir.mkdir(parents=True, exist_ok=True)
output_file = output_dir / 'globi_interactions_final_dataset_11680.parquet'

print("="*80)
print("Stage 4: GloBI Interactions Extraction")
print("="*80)
print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
print()

con = duckdb.connect()

# Step 1: Extract WFO IDs from final dataset
print("Step 1: Extracting WFO IDs from final dataset...")
final_wfo_ids = con.execute("""
    SELECT DISTINCT wfo_taxon_id
    FROM read_parquet(?)
    WHERE wfo_taxon_id IS NOT NULL
""", [final_dataset]).fetchdf()

print(f"  - Found {len(final_wfo_ids):,} unique WFO IDs in final dataset")
print()

# Step 2: Match interactions (bidirectional: source OR target)
print("Step 2: Matching GloBI interactions...")
print("  - Matching on BOTH source_wfo_taxon_id AND target_wfo_taxon_id")
print("  - This captures interactions where plant is either actor or recipient")
print()

result = con.execute("""
    WITH final_wfo AS (
        SELECT DISTINCT wfo_taxon_id
        FROM read_parquet(?)
        WHERE wfo_taxon_id IS NOT NULL
    )
    SELECT g.*
    FROM read_parquet(?) g
    WHERE g.source_wfo_taxon_id IN (SELECT wfo_taxon_id FROM final_wfo)
       OR g.target_wfo_taxon_id IN (SELECT wfo_taxon_id FROM final_wfo)
""", [final_dataset, globi_plants]).fetchdf()

print(f"  - Matched {len(result):,} interaction records")
print()

# Step 3: Summary statistics
print("Step 3: Interaction summary...")

# Count by interaction type
by_type = con.execute("""
    WITH final_wfo AS (
        SELECT DISTINCT wfo_taxon_id
        FROM read_parquet(?)
        WHERE wfo_taxon_id IS NOT NULL
    ),
    matched_interactions AS (
        SELECT g.*
        FROM read_parquet(?) g
        WHERE g.source_wfo_taxon_id IN (SELECT wfo_taxon_id FROM final_wfo)
           OR g.target_wfo_taxon_id IN (SELECT wfo_taxon_id FROM final_wfo)
    )
    SELECT
        interactionTypeName,
        COUNT(*) as interaction_count,
        COUNT(DISTINCT source_wfo_taxon_id) as distinct_source_species,
        COUNT(DISTINCT target_wfo_taxon_id) as distinct_target_species
    FROM matched_interactions
    GROUP BY interactionTypeName
    ORDER BY interaction_count DESC
""", [final_dataset, globi_plants]).fetchdf()

print("\nTop 15 Interaction Types:")
print(by_type.head(15).to_string(index=False))
print()

# Count matched species
matched_species = con.execute("""
    WITH final_wfo AS (
        SELECT DISTINCT wfo_taxon_id
        FROM read_parquet(?)
        WHERE wfo_taxon_id IS NOT NULL
    ),
    matched_interactions AS (
        SELECT g.*
        FROM read_parquet(?) g
        WHERE g.source_wfo_taxon_id IN (SELECT wfo_taxon_id FROM final_wfo)
           OR g.target_wfo_taxon_id IN (SELECT wfo_taxon_id FROM final_wfo)
    )
    SELECT COUNT(DISTINCT matched_wfo) as species_with_interactions
    FROM (
        SELECT source_wfo_taxon_id as matched_wfo
        FROM matched_interactions
        WHERE source_wfo_taxon_id IN (SELECT wfo_taxon_id FROM final_wfo)
        UNION
        SELECT target_wfo_taxon_id as matched_wfo
        FROM matched_interactions
        WHERE target_wfo_taxon_id IN (SELECT wfo_taxon_id FROM final_wfo)
    )
""", [final_dataset, globi_plants]).fetchone()

print(f"Species Coverage:")
print(f"  - {matched_species[0]:,} out of {len(final_wfo_ids):,} species have recorded interactions")
print(f"  - Coverage: {100*matched_species[0]/len(final_wfo_ids):.1f}%")
print()

# Step 4: Save to parquet
print(f"Step 4: Saving to {output_file}...")
result.to_parquet(output_file, compression='zstd')

print(f"  - Saved {len(result):,} rows")
print(f"  - File: {output_file}")
print()

print("="*80)
print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
print("="*80)

con.close()

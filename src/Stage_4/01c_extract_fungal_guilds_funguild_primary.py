#!/usr/bin/env python3
"""
Extract fungal guild classifications using FunGuild as PRIMARY database.
This compares against the FungalTraits-based approach in 01b.

IMPORTANT: Filters FunGuild by confidence level (Probable + Highly Probable only).
Research shows "Possible" confidence should be EXCLUDED (Tanunchai et al. 2022).

Guild categories:
1. Pathogenic (plant pathogens, animal pathogens)
2. Mycorrhizal (AMF, EMF, ericoid, etc.)
3. Biocontrol (mycoparasites, entomopathogens)
4. Endophytic (plant endophytes)
5. Saprotrophic (decomposers)

Uses DuckDB for all data operations (mandated in CLAUDE.md).

Reference: Tanunchai et al. (2022) Microbial Ecology
"""

import duckdb
import sys
from pathlib import Path

# Paths (matching 01b_extract_fungal_guilds.py)
PLANT_DATASET_PATH = 'model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet'
GLOBI_PATH = 'data/stage4/globi_interactions_final_dataset_11680.parquet'
FUNGUILD_PATH = 'data/funguild/funguild.parquet'
OUTPUT_PATH = 'data/stage4/plant_fungal_guilds_funguild_primary.parquet'

def main():
    print("=== Fungal Guild Extraction (FunGuild Primary) ===\n")

    # Connect to DuckDB
    con = duckdb.connect()

    # Extract fungal guilds using single SQL query
    print("Extracting fungal guilds from GloBI + FunGuild...")

    result = con.execute(f"""
    WITH
    -- Step 0: Get the 11,680 plants from the production dataset
    target_plants AS (
        SELECT DISTINCT wfo_taxon_id as plant_wfo_id
        FROM read_parquet('{PLANT_DATASET_PATH}')
    ),

    -- Step 1: Pre-process FunGuild to extract genus names
    -- FILTER BY CONFIDENCE: Only 'Probable' and 'Highly Probable' (exclude 'Possible')
    funguild_genus AS (
        SELECT DISTINCT
            CASE
                -- For genus-level records (13), use taxon directly
                WHEN taxonomicLevel = '13' THEN LOWER(TRIM(taxon))
                -- For species-level records (20), extract first word
                WHEN taxonomicLevel = '20' THEN LOWER(TRIM(SPLIT_PART(REPLACE(taxon, '_', ' '), ' ', 1)))
                -- For other levels, try to extract genus
                ELSE LOWER(TRIM(SPLIT_PART(taxon, ' ', 1)))
            END as genus,
            trophicMode,
            guild,
            confidenceRanking,
            -- Guild classifications
            (guild LIKE '%Plant Pathogen%' OR guild LIKE '%Animal Pathogen%') as is_pathogen,
            (guild LIKE '%Plant Pathogen%' AND confidenceRanking = 'Highly Probable') as is_pathogen_high_conf,
            (guild LIKE '%mycorrhizal%') as is_mycorrhizal,
            (guild LIKE '%Ectomycorrhizal%') as is_emf,
            (guild LIKE '%Arbuscular%') as is_amf,
            (guild LIKE '%Mycoparasite%' OR guild LIKE '%Fungicolous%') as is_biocontrol_guild,
            (guild LIKE '%Endophyte%') as is_endophytic,
            (guild LIKE '%Saprotroph%') as is_saprotrophic
        FROM read_parquet('{FUNGUILD_PATH}')
        WHERE taxonomicLevel IN ('13', '20')  -- Only genus and species levels
          AND confidenceRanking IN ('Probable', 'Highly Probable')  -- EXCLUDE 'Possible' per research
    ),

    -- Step 2: Get all hasHost fungi from GloBI
    hashost_fungi AS (
        SELECT
            g.target_wfo_taxon_id,
            LOWER(COALESCE(g.sourceTaxonGenusName, SPLIT_PART(g.sourceTaxonName, ' ', 1))) as genus
        FROM read_parquet('{GLOBI_PATH}') g
        WHERE g.interactionTypeName = 'hasHost'
          AND g.sourceTaxonKingdomName = 'Fungi'
    ),

    -- Step 3: Simple genus-level join (like FungalTraits)
    fg_matches AS (
        SELECT
            h.target_wfo_taxon_id,
            h.genus,
            fg.guild as fg_guild,
            fg.confidenceRanking,
            fg.is_pathogen,
            fg.is_pathogen_high_conf,
            fg.is_mycorrhizal,
            fg.is_emf,
            fg.is_amf,
            -- Biocontrol includes guild-based + known genera
            (fg.is_biocontrol_guild OR h.genus IN ('trichoderma', 'beauveria', 'metarhizium', 'lecanicillium', 'paecilomyces')) as is_biocontrol,
            (h.genus = 'trichoderma') as is_trichoderma,
            (h.genus IN ('beauveria', 'metarhizium')) as is_beauveria_metarhizium,
            fg.is_endophytic,
            fg.is_saprotrophic
        FROM hashost_fungi h
        LEFT JOIN funguild_genus fg ON h.genus = fg.genus
    ),

    -- Step 4: Aggregate by plant with LIST for each guild
    plant_fungi_aggregated AS (
        SELECT
            target_wfo_taxon_id as plant_wfo_id,

            -- Pathogenic
            LIST(DISTINCT CASE WHEN is_pathogen THEN genus END) FILTER (WHERE is_pathogen) as pathogenic_fungi,
            LIST(DISTINCT CASE WHEN is_pathogen_high_conf THEN genus END) FILTER (WHERE is_pathogen_high_conf) as pathogenic_fungi_high_conf,

            -- Mycorrhizal
            LIST(DISTINCT CASE WHEN is_mycorrhizal THEN genus END) FILTER (WHERE is_mycorrhizal) as mycorrhizal_fungi,
            LIST(DISTINCT CASE WHEN is_amf THEN genus END) FILTER (WHERE is_amf) as amf_fungi,
            LIST(DISTINCT CASE WHEN is_emf THEN genus END) FILTER (WHERE is_emf) as emf_fungi,

            -- Biocontrol
            LIST(DISTINCT CASE WHEN is_biocontrol THEN genus END) FILTER (WHERE is_biocontrol) as biocontrol_fungi,

            -- Endophytic
            LIST(DISTINCT CASE WHEN is_endophytic THEN genus END) FILTER (WHERE is_endophytic) as endophytic_fungi,

            -- Saprotrophic
            LIST(DISTINCT CASE WHEN is_saprotrophic THEN genus END) FILTER (WHERE is_saprotrophic) as saprotrophic_fungi,

            -- Special high-value genera
            SUM(CASE WHEN is_trichoderma THEN 1 ELSE 0 END) as trichoderma_count,
            SUM(CASE WHEN is_beauveria_metarhizium THEN 1 ELSE 0 END) as beauveria_metarhizium_count,

            -- Match statistics
            COUNT(DISTINCT genus) as total_fungal_genera,
            COUNT(DISTINCT CASE WHEN fg_guild IS NOT NULL THEN genus END) as matched_genera,
            COUNT(DISTINCT CASE WHEN fg_guild IS NULL THEN genus END) as unmatched_genera

        FROM fg_matches
        GROUP BY target_wfo_taxon_id
    )

    -- Final output: Join with target plants to ensure we have all 11,680
    SELECT
        tp.plant_wfo_id,
        pf.pathogenic_fungi,
        pf.pathogenic_fungi_high_conf,
        pf.mycorrhizal_fungi,
        pf.amf_fungi,
        pf.emf_fungi,
        pf.biocontrol_fungi,
        pf.endophytic_fungi,
        pf.saprotrophic_fungi,
        COALESCE(pf.trichoderma_count, 0) as trichoderma_count,
        COALESCE(pf.beauveria_metarhizium_count, 0) as beauveria_metarhizium_count,
        COALESCE(pf.total_fungal_genera, 0) as total_fungal_genera,
        COALESCE(pf.matched_genera, 0) as matched_genera,
        COALESCE(pf.unmatched_genera, 0) as unmatched_genera
    FROM target_plants tp
    LEFT JOIN plant_fungi_aggregated pf ON tp.plant_wfo_id = pf.plant_wfo_id
    ORDER BY tp.plant_wfo_id
    """).df()

    # Save to parquet
    result.to_parquet(OUTPUT_PATH, compression='zstd', index=False)

    # Print summary statistics
    print(f"\n=== Results ===")
    print(f"Total plants processed: {len(result):,}")
    print(f"Plants with guild assignments: {(result['matched_genera'] > 0).sum():,}")
    print(f"\n=== Guild Coverage ===")
    print(f"Pathogenic: {(result['pathogenic_fungi'].notna() & (result['pathogenic_fungi'].str.len() > 0)).sum():,} plants")
    print(f"  - High confidence: {(result['pathogenic_fungi_high_conf'].notna() & (result['pathogenic_fungi_high_conf'].str.len() > 0)).sum():,} plants")
    print(f"Mycorrhizal: {(result['mycorrhizal_fungi'].notna() & (result['mycorrhizal_fungi'].str.len() > 0)).sum():,} plants")
    print(f"  - EMF: {(result['emf_fungi'].notna() & (result['emf_fungi'].str.len() > 0)).sum():,} plants")
    print(f"  - AMF: {(result['amf_fungi'].notna() & (result['amf_fungi'].str.len() > 0)).sum():,} plants")
    print(f"Biocontrol: {(result['biocontrol_fungi'].notna() & (result['biocontrol_fungi'].str.len() > 0)).sum():,} plants")
    print(f"  - Trichoderma: {(result['trichoderma_count'] > 0).sum():,} plants")
    print(f"  - Beauveria/Metarhizium: {(result['beauveria_metarhizium_count'] > 0).sum():,} plants")
    print(f"Endophytic: {(result['endophytic_fungi'].notna() & (result['endophytic_fungi'].str.len() > 0)).sum():,} plants")
    print(f"Saprotrophic: {(result['saprotrophic_fungi'].notna() & (result['saprotrophic_fungi'].str.len() > 0)).sum():,} plants")

    # Matching statistics
    print(f"\n=== Matching Statistics ===")
    print(f"Total fungal genera: {result['total_fungal_genera'].sum():,}")
    print(f"Matched genera: {result['matched_genera'].sum():,}")
    print(f"Unmatched genera: {result['unmatched_genera'].sum():,}")
    match_rate = result['matched_genera'].sum() / result['total_fungal_genera'].sum() * 100
    print(f"Match rate: {match_rate:.1f}%")

    print(f"\nOutput saved to: {OUTPUT_PATH}")

if __name__ == '__main__':
    main()

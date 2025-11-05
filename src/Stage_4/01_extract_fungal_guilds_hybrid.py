#!/usr/bin/env python3
"""
Stage 4.1: Extract Fungal Guilds - HYBRID APPROACH (Research-Validated)

Strategy: BROAD MINING + FungalTraits/FunGuild VALIDATION
- Extraction: Use broad relationships (hasHost, parasiteOf, pathogenOf, interactsWith)
- Validation: FungalTraits PRIMARY + FunGuild FALLBACK
- FungalTraits: Expert-curated (128 mycologists), sorts into 8 guilds
- FunGuild: Fills gaps for unmatched genera (confidence-filtered)
- Rationale: Cast wide net, let validation databases sort fungi into guilds

Reference: Tanunchai et al. (2022) Microbial Ecology

Usage:
    python src/Stage_4/01_extract_fungal_guilds_hybrid.py
    python src/Stage_4/01_extract_fungal_guilds_hybrid.py --test --limit 100
"""

import argparse
import duckdb
from pathlib import Path
from datetime import datetime

def extract_hybrid_guilds(limit=None):
    """Extract fungal guilds using FungalTraits + FunGuild hybrid approach."""

    output_dir = Path('data/stage4')
    output_dir.mkdir(parents=True, exist_ok=True)

    print("="*80)
    print("STAGE 4.1: Fungal Guild Extraction - HYBRID APPROACH")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    if limit:
        print(f"TEST MODE: Processing first {limit} plants only")
        print()

    print("Strategy: BROAD MINING + FungalTraits/FunGuild VALIDATION")
    print("  - Extraction: hasHost, parasiteOf, pathogenOf, interactsWith")
    print("  - FungalTraits: Expert-curated (128 mycologists) - PRIMARY")
    print("  - FunGuild: Fills gaps (confidence-filtered) - FALLBACK")
    print("  - Rationale: Cast wide net, let validation sort into guilds")
    print()

    con = duckdb.connect()

    # Paths
    FUNGALTRAITS_PATH = "data/fungaltraits/fungaltraits.parquet"
    FUNGUILD_PATH = "data/funguild/funguild.parquet"
    PLANT_DATASET_PATH = "model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet"
    GLOBI_PATH = "data/stage4/globi_interactions_final_dataset_11680.parquet"

    # Limit clause for test mode
    if limit:
        limit_clause = f"LIMIT {limit}"
    else:
        limit_clause = ""

    print("Extracting fungi with hybrid approach (single DuckDB query)...")
    print()

    result = con.execute(f"""
        WITH
        -- Step 1: Get target plants
        target_plants AS (
            SELECT wfo_taxon_id, wfo_scientific_name, family, genus
            FROM read_parquet('{PLANT_DATASET_PATH}')
            ORDER BY wfo_scientific_name
            {limit_clause}
        ),

        -- Step 2: Get all fungi from GloBI using BROAD relationship mining
        -- Strategy: Cast wide net, let FungalTraits validate and sort into guilds
        hashost_fungi AS (
            SELECT
                g.target_wfo_taxon_id,
                LOWER(COALESCE(g.sourceTaxonGenusName, SPLIT_PART(g.sourceTaxonName, ' ', 1))) as genus,
                g.sourceTaxonPhylumName as phylum
            FROM read_parquet('{GLOBI_PATH}') g
            WHERE g.interactionTypeName IN ('hasHost', 'parasiteOf', 'pathogenOf', 'interactsWith')
              AND g.sourceTaxonKingdomName = 'Fungi'
              AND g.target_wfo_taxon_id IN (SELECT wfo_taxon_id FROM target_plants)
        ),

        -- Step 3: Match with FungalTraits (PRIMARY)
        ft_matches AS (
            SELECT
                h.target_wfo_taxon_id,
                h.genus,
                'FungalTraits' as source,
                -- Guild flags
                (f.primary_lifestyle = 'plant_pathogen' OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'pathogen')) as is_pathogen,
                (f.Specific_hosts IS NOT NULL) as is_host_specific,
                (f.primary_lifestyle = 'arbuscular_mycorrhizal') as is_amf,
                (f.primary_lifestyle = 'ectomycorrhizal') as is_emf,
                (f.primary_lifestyle = 'mycoparasite') as is_mycoparasite,
                (f.primary_lifestyle = 'animal_parasite' OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'animal_parasite') OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'arthropod')) as is_entomopathogenic,
                (f.primary_lifestyle IN ('foliar_endophyte', 'root_endophyte') OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'endophyte')) as is_endophytic,
                (f.primary_lifestyle IN ('wood_saprotroph', 'litter_saprotroph', 'soil_saprotroph', 'unspecified_saprotroph', 'dung_saprotroph', 'nectar/tap_saprotroph', 'pollen_saprotroph')
                 OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'saprotroph') OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'decomposer')) as is_saprotrophic,
                (h.genus = 'trichoderma') as is_trichoderma,
                (h.genus IN ('beauveria', 'metarhizium')) as is_beauveria_metarhizium
            FROM hashost_fungi h
            LEFT JOIN read_parquet('{FUNGALTRAITS_PATH}') f
                ON LOWER(h.genus) = LOWER(f.GENUS)
                AND (
                    -- For 6 homonyms, require Phylum match
                    (h.genus IN ('adelolecia', 'campanulospora', 'caudospora', 'echinoascotheca', 'paranectriella', 'phialophoropsis')
                     AND h.phylum = f.Phylum)
                    OR
                    -- For all others, genus match sufficient
                    (h.genus NOT IN ('adelolecia', 'campanulospora', 'caudospora', 'echinoascotheca', 'paranectriella', 'phialophoropsis'))
                )
            WHERE f.GENUS IS NOT NULL  -- Successfully matched to FungalTraits
        ),

        -- Step 4: Get unmatched genera for FunGuild fallback
        unmatched_genera AS (
            SELECT DISTINCT genus, target_wfo_taxon_id, phylum
            FROM hashost_fungi
            WHERE genus NOT IN (SELECT DISTINCT genus FROM ft_matches)
        ),

        -- Step 5: Match unmatched genera with FunGuild (FALLBACK)
        -- CRITICAL: Filter by confidence (Probable + Highly Probable only)
        fg_genus_lookup AS (
            SELECT DISTINCT
                CASE
                    WHEN taxonomicLevel = '13' THEN LOWER(TRIM(taxon))
                    WHEN taxonomicLevel = '20' THEN LOWER(TRIM(SPLIT_PART(REPLACE(taxon, '_', ' '), ' ', 1)))
                END as genus,
                guild,
                confidenceRanking,
                (guild LIKE '%Plant Pathogen%' OR guild LIKE '%Animal Pathogen%') as is_pathogen,
                (guild LIKE '%mycorrhizal%') as is_mycorrhizal,
                (guild LIKE '%Ectomycorrhizal%') as is_emf,
                (guild LIKE '%Arbuscular%') as is_amf,
                (guild LIKE '%Mycoparasite%' OR guild LIKE '%Fungicolous%') as is_biocontrol_guild,
                (guild LIKE '%Endophyte%') as is_endophytic,
                (guild LIKE '%Saprotroph%') as is_saprotrophic
            FROM read_parquet('{FUNGUILD_PATH}')
            WHERE taxonomicLevel IN ('13', '20')
              AND confidenceRanking IN ('Probable', 'Highly Probable')  -- EXCLUDE 'Possible'
        ),

        fg_matches AS (
            SELECT
                u.target_wfo_taxon_id,
                u.genus,
                'FunGuild' as source,
                -- Guild flags
                COALESCE(fg.is_pathogen, FALSE) as is_pathogen,
                FALSE as is_host_specific,  -- FunGuild doesn't have host-specific info
                COALESCE(fg.is_amf, FALSE) as is_amf,
                COALESCE(fg.is_emf, FALSE) as is_emf,
                COALESCE(fg.is_biocontrol_guild, FALSE) as is_mycoparasite,
                FALSE as is_entomopathogenic,  -- Simplified
                COALESCE(fg.is_endophytic, FALSE) as is_endophytic,
                COALESCE(fg.is_saprotrophic, FALSE) as is_saprotrophic,
                (u.genus = 'trichoderma') as is_trichoderma,
                (u.genus IN ('beauveria', 'metarhizium')) as is_beauveria_metarhizium
            FROM unmatched_genera u
            LEFT JOIN fg_genus_lookup fg ON u.genus = fg.genus
        ),

        -- Step 6: UNION all matches (FungalTraits + FunGuild)
        all_matches AS (
            SELECT * FROM ft_matches
            UNION ALL
            SELECT * FROM fg_matches
        ),

        -- Step 7: Aggregate by plant
        plant_fungi_aggregated AS (
            SELECT
                target_wfo_taxon_id as plant_wfo_id,

                -- Pathogenic
                LIST(DISTINCT CASE WHEN is_pathogen THEN genus END) FILTER (WHERE is_pathogen) as pathogenic_fungi,
                LIST(DISTINCT CASE WHEN is_pathogen AND is_host_specific THEN genus END) FILTER (WHERE is_pathogen AND is_host_specific) as pathogenic_fungi_host_specific,

                -- Mycorrhizal
                LIST(DISTINCT CASE WHEN is_amf THEN genus END) FILTER (WHERE is_amf) as amf_fungi,
                LIST(DISTINCT CASE WHEN is_emf THEN genus END) FILTER (WHERE is_emf) as emf_fungi,

                -- Biocontrol
                LIST(DISTINCT CASE WHEN is_mycoparasite THEN genus END) FILTER (WHERE is_mycoparasite) as mycoparasite_fungi,
                LIST(DISTINCT CASE WHEN is_entomopathogenic THEN genus END) FILTER (WHERE is_entomopathogenic) as entomopathogenic_fungi,

                -- Endophytic
                LIST(DISTINCT CASE WHEN is_endophytic THEN genus END) FILTER (WHERE is_endophytic) as endophytic_fungi,

                -- Saprotrophic
                LIST(DISTINCT CASE WHEN is_saprotrophic THEN genus END) FILTER (WHERE is_saprotrophic) as saprotrophic_fungi,

                -- Multi-guild
                SUM(CASE WHEN is_trichoderma THEN 1 ELSE 0 END) as trichoderma_count,
                SUM(CASE WHEN is_beauveria_metarhizium THEN 1 ELSE 0 END) as beauveria_metarhizium_count,

                -- Source tracking
                SUM(CASE WHEN source = 'FungalTraits' THEN 1 ELSE 0 END) as ft_genera_count,
                SUM(CASE WHEN source = 'FunGuild' THEN 1 ELSE 0 END) as fg_genera_count
            FROM all_matches
            GROUP BY target_wfo_taxon_id
        )

        -- Step 8: Join back to plants
        SELECT
            p.wfo_taxon_id as plant_wfo_id,
            p.wfo_scientific_name,
            p.family,
            p.genus,

            -- Guilds
            COALESCE(f.pathogenic_fungi, []) as pathogenic_fungi,
            COALESCE(LEN(f.pathogenic_fungi), 0) as pathogenic_fungi_count,
            COALESCE(f.pathogenic_fungi_host_specific, []) as pathogenic_fungi_host_specific,
            COALESCE(LEN(f.pathogenic_fungi_host_specific), 0) as pathogenic_fungi_host_specific_count,

            COALESCE(f.amf_fungi, []) as amf_fungi,
            COALESCE(LEN(f.amf_fungi), 0) as amf_fungi_count,
            COALESCE(f.emf_fungi, []) as emf_fungi,
            COALESCE(LEN(f.emf_fungi), 0) as emf_fungi_count,
            COALESCE(LEN(f.amf_fungi), 0) + COALESCE(LEN(f.emf_fungi), 0) as mycorrhizae_total_count,

            COALESCE(f.mycoparasite_fungi, []) as mycoparasite_fungi,
            COALESCE(LEN(f.mycoparasite_fungi), 0) as mycoparasite_fungi_count,
            COALESCE(f.entomopathogenic_fungi, []) as entomopathogenic_fungi,
            COALESCE(LEN(f.entomopathogenic_fungi), 0) as entomopathogenic_fungi_count,
            COALESCE(LEN(f.mycoparasite_fungi), 0) + COALESCE(LEN(f.entomopathogenic_fungi), 0) as biocontrol_total_count,

            COALESCE(f.endophytic_fungi, []) as endophytic_fungi,
            COALESCE(LEN(f.endophytic_fungi), 0) as endophytic_fungi_count,

            COALESCE(f.saprotrophic_fungi, []) as saprotrophic_fungi,
            COALESCE(LEN(f.saprotrophic_fungi), 0) as saprotrophic_fungi_count,

            COALESCE(f.trichoderma_count, 0) as trichoderma_count,
            COALESCE(f.beauveria_metarhizium_count, 0) as beauveria_metarhizium_count,

            -- Source tracking
            COALESCE(f.ft_genera_count, 0) as fungaltraits_genera,
            COALESCE(f.fg_genera_count, 0) as funguild_genera
        FROM target_plants p
        LEFT JOIN plant_fungi_aggregated f ON p.wfo_taxon_id = f.plant_wfo_id
        ORDER BY p.wfo_scientific_name
    """).fetchdf()

    print(f"  ✓ Processed {len(result):,} plants")
    print()

    # Save
    output_file = output_dir / ('plant_fungal_guilds_hybrid_test.parquet' if limit else 'plant_fungal_guilds_hybrid.parquet')
    print(f"Saving to {output_file}...")
    result.to_parquet(output_file, compression='zstd', index=False)
    print(f"  ✓ Saved")
    print()

    # Summary
    print("="*80)
    print("SUMMARY STATISTICS")
    print("="*80)

    stats = con.execute("""
        SELECT
            COUNT(*) as total_plants,
            SUM(CASE WHEN pathogenic_fungi_count > 0 THEN 1 ELSE 0 END) as plants_with_pathogens,
            SUM(CASE WHEN mycorrhizae_total_count > 0 THEN 1 ELSE 0 END) as plants_with_mycorrhizae,
            SUM(CASE WHEN biocontrol_total_count > 0 THEN 1 ELSE 0 END) as plants_with_biocontrol,
            SUM(CASE WHEN endophytic_fungi_count > 0 THEN 1 ELSE 0 END) as plants_with_endophytic,
            SUM(CASE WHEN saprotrophic_fungi_count > 0 THEN 1 ELSE 0 END) as plants_with_saprotrophic,
            SUM(fungaltraits_genera) as total_ft_genera,
            SUM(funguild_genera) as total_fg_genera
        FROM read_parquet('data/stage4/plant_fungal_guilds_hybrid.parquet')
    """).fetchone()

    total, path, myc, bio, endo, sapro, ft_gen, fg_gen = stats

    print(f"Total plants: {total:,}")
    print()
    print("Plants with fungi by guild:")
    print(f"  - Pathogenic: {path:,} ({path/total*100:.1f}%)")
    print(f"  - Mycorrhizal: {myc:,} ({myc/total*100:.1f}%)")
    print(f"  - Biocontrol: {bio:,} ({bio/total*100:.1f}%)")
    print(f"  - Endophytic: {endo:,} ({endo/total*100:.1f}%)")
    print(f"  - Saprotrophic: {sapro:,} ({sapro/total*100:.1f}%)")
    print()
    print("Data source breakdown:")
    print(f"  - FungalTraits genera: {ft_gen:,}")
    print(f"  - FunGuild genera (fallback): {fg_gen:,}")
    print(f"  - FunGuild contribution: {fg_gen/(ft_gen+fg_gen)*100:.1f}%")
    print()
    print("="*80)
    print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Output: {output_file}")
    print("="*80)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Extract fungal guild profiles using hybrid approach (DuckDB-optimized)')
    parser.add_argument('--test', action='store_true', help='Run in test mode on limited plants')
    parser.add_argument('--limit', type=int, default=100, help='Number of plants to process in test mode')

    args = parser.parse_args()

    if args.test:
        extract_hybrid_guilds(limit=args.limit)
    else:
        extract_hybrid_guilds()

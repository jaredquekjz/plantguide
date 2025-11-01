#!/usr/bin/env python3
"""
Stage 4.1b: Extract Fungal Guild Classifications (DuckDB-optimized)

Extracts and classifies all hasHost fungi from GloBI using FungalTraits database.
Implements all 5 functional guilds plus multi-guild tracking.

PERFORMANCE: Fully DuckDB-based for 10-100× speedup over pandas loops.

Usage:
    python src/Stage_4/01b_extract_fungal_guilds.py
    python src/Stage_4/01b_extract_fungal_guilds.py --test --limit 100
"""

import argparse
import duckdb
from pathlib import Path
from datetime import datetime

def extract_fungal_guilds(limit=None):
    """Extract fungal guild profiles using pure DuckDB SQL."""

    output_dir = Path('data/stage4')
    output_dir.mkdir(parents=True, exist_ok=True)

    print("="*80)
    print("STAGE 4.1b: Extract Fungal Guild Profiles (DuckDB-optimized)")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    if limit:
        print(f"TEST MODE: Processing first {limit} plants only")
    print()

    con = duckdb.connect()

    # Paths
    FUNGALTRAITS_PATH = "data/fungaltraits/fungaltraits.parquet"
    PLANT_DATASET_PATH = "model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet"
    GLOBI_PATH = "data/stage4/globi_interactions_final_dataset_11680.parquet"

    # Build complete query in DuckDB SQL
    print("Extracting and classifying fungi (single DuckDB query)...")
    print()

    if limit:
        limit_clause = f"LIMIT {limit}"
    else:
        limit_clause = ""

    result = con.execute(f"""
        -- Step 1: Get plant IDs to process
        WITH plants AS (
            SELECT wfo_taxon_id, wfo_scientific_name, family, genus
            FROM read_parquet('{PLANT_DATASET_PATH}')
            ORDER BY wfo_scientific_name
            {limit_clause}
        ),

        -- Step 2: Extract hasHost fungi from GloBI for our plants
        hashost_fungi AS (
            SELECT
                g.target_wfo_taxon_id,
                g.sourceTaxonName,
                COALESCE(g.sourceTaxonGenusName, SPLIT_PART(g.sourceTaxonName, ' ', 1)) as genus,
                g.sourceTaxonPhylumName as phylum
            FROM read_parquet('{GLOBI_PATH}') g
            WHERE g.interactionTypeName = 'hasHost'
              AND g.sourceTaxonKingdomName = 'Fungi'
              AND g.target_wfo_taxon_id IN (SELECT wfo_taxon_id FROM plants)
        ),

        -- Step 3: Match to FungalTraits by genus (with Phylum for 6 homonyms)
        -- Homonyms: Adelolecia, Campanulospora, Caudospora, Echinoascotheca, Paranectriella, Phialophoropsis
        ft_matches AS (
            SELECT
                h.target_wfo_taxon_id,
                h.genus,
                f.primary_lifestyle,
                f.Secondary_lifestyle,
                f.Specific_hosts,
                -- Guild classifications (inline boolean logic)
                -- Note: Fungi can have MULTIPLE guilds (e.g., pathogen + endophyte)
                (f.primary_lifestyle = 'plant_pathogen' OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'pathogen')) as is_pathogen,
                (f.Specific_hosts IS NOT NULL) as is_host_specific,
                (f.primary_lifestyle = 'arbuscular_mycorrhizal') as is_amf,
                (f.primary_lifestyle = 'ectomycorrhizal') as is_emf,
                (f.primary_lifestyle = 'mycoparasite') as is_mycoparasite,
                (f.primary_lifestyle = 'animal_parasite' OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'animal_parasite') OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'arthropod')) as is_entomopathogenic,
                (f.primary_lifestyle IN ('foliar_endophyte', 'root_endophyte') OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'endophyte')) as is_endophytic,
                (f.primary_lifestyle IN ('wood_saprotroph', 'litter_saprotroph', 'soil_saprotroph', 'unspecified_saprotroph', 'dung_saprotroph', 'nectar/tap_saprotroph', 'pollen_saprotroph')
                 OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'saprotroph') OR CONTAINS(LOWER(COALESCE(f.Secondary_lifestyle, '')), 'decomposer')) as is_saprotrophic,
                (h.genus = 'Trichoderma') as is_trichoderma,
                (h.genus IN ('Beauveria', 'Metarhizium')) as is_beauveria_metarhizium
            FROM hashost_fungi h
            LEFT JOIN read_parquet('{FUNGALTRAITS_PATH}') f
                ON h.genus = f.GENUS
                AND (
                    -- For 6 homonyms, require Phylum match too
                    (h.genus IN ('Adelolecia', 'Campanulospora', 'Caudospora', 'Echinoascotheca', 'Paranectriella', 'Phialophoropsis')
                     AND h.phylum = f.Phylum)
                    OR
                    -- For all other genera, genus match is sufficient
                    (h.genus NOT IN ('Adelolecia', 'Campanulospora', 'Caudospora', 'Echinoascotheca', 'Paranectriella', 'Phialophoropsis'))
                )
        ),

        -- Step 4: Aggregate by plant with LIST for each guild
        plant_fungi_aggregated AS (
            SELECT
                target_wfo_taxon_id as plant_wfo_id,

                -- Guild 1: Pathogenic
                LIST(DISTINCT CASE WHEN is_pathogen THEN genus END) FILTER (WHERE is_pathogen) as pathogenic_fungi,
                LIST(DISTINCT CASE WHEN is_pathogen AND is_host_specific THEN genus END) FILTER (WHERE is_pathogen AND is_host_specific) as pathogenic_fungi_host_specific,

                -- Guild 2: Mycorrhizal
                LIST(DISTINCT CASE WHEN is_amf THEN genus END) FILTER (WHERE is_amf) as amf_fungi,
                LIST(DISTINCT CASE WHEN is_emf THEN genus END) FILTER (WHERE is_emf) as emf_fungi,

                -- Guild 3: Biocontrol
                LIST(DISTINCT CASE WHEN is_mycoparasite THEN genus END) FILTER (WHERE is_mycoparasite) as mycoparasite_fungi,
                LIST(DISTINCT CASE WHEN is_entomopathogenic THEN genus END) FILTER (WHERE is_entomopathogenic) as entomopathogenic_fungi,

                -- Guild 4: Endophytic
                LIST(DISTINCT CASE WHEN is_endophytic THEN genus END) FILTER (WHERE is_endophytic) as endophytic_fungi,

                -- Guild 5: Saprotrophic
                LIST(DISTINCT CASE WHEN is_saprotrophic THEN genus END) FILTER (WHERE is_saprotrophic) as saprotrophic_fungi,

                -- Multi-guild counts
                SUM(CASE WHEN is_trichoderma THEN 1 ELSE 0 END) as trichoderma_count,
                SUM(CASE WHEN is_beauveria_metarhizium THEN 1 ELSE 0 END) as beauveria_metarhizium_count
            FROM ft_matches
            GROUP BY target_wfo_taxon_id
        )

        -- Step 5: Join back to plants (LEFT JOIN to include plants with no fungi)
        SELECT
            p.wfo_taxon_id as plant_wfo_id,
            p.wfo_scientific_name,
            p.family,
            p.genus,

            -- Guild 1: Pathogenic
            COALESCE(f.pathogenic_fungi, []) as pathogenic_fungi,
            COALESCE(LEN(f.pathogenic_fungi), 0) as pathogenic_fungi_count,
            COALESCE(f.pathogenic_fungi_host_specific, []) as pathogenic_fungi_host_specific,
            COALESCE(LEN(f.pathogenic_fungi_host_specific), 0) as pathogenic_fungi_host_specific_count,

            -- Guild 2: Mycorrhizal
            COALESCE(f.amf_fungi, []) as amf_fungi,
            COALESCE(LEN(f.amf_fungi), 0) as amf_fungi_count,
            COALESCE(f.emf_fungi, []) as emf_fungi,
            COALESCE(LEN(f.emf_fungi), 0) as emf_fungi_count,
            COALESCE(LEN(f.amf_fungi), 0) + COALESCE(LEN(f.emf_fungi), 0) as mycorrhizae_total_count,

            -- Guild 3: Biocontrol
            COALESCE(f.mycoparasite_fungi, []) as mycoparasite_fungi,
            COALESCE(LEN(f.mycoparasite_fungi), 0) as mycoparasite_fungi_count,
            COALESCE(f.entomopathogenic_fungi, []) as entomopathogenic_fungi,
            COALESCE(LEN(f.entomopathogenic_fungi), 0) as entomopathogenic_fungi_count,
            COALESCE(LEN(f.mycoparasite_fungi), 0) + COALESCE(LEN(f.entomopathogenic_fungi), 0) as biocontrol_total_count,

            -- Guild 4: Endophytic
            COALESCE(f.endophytic_fungi, []) as endophytic_fungi,
            COALESCE(LEN(f.endophytic_fungi), 0) as endophytic_fungi_count,

            -- Guild 5: Saprotrophic
            COALESCE(f.saprotrophic_fungi, []) as saprotrophic_fungi,
            COALESCE(LEN(f.saprotrophic_fungi), 0) as saprotrophic_fungi_count,

            -- Multi-guild
            COALESCE(f.trichoderma_count, 0) as trichoderma_count,
            COALESCE(f.beauveria_metarhizium_count, 0) as beauveria_metarhizium_count
        FROM plants p
        LEFT JOIN plant_fungi_aggregated f ON p.wfo_taxon_id = f.plant_wfo_id
        ORDER BY p.wfo_scientific_name
    """).fetchdf()

    print(f"  ✓ Processed {len(result):,} plants")
    print()

    # Save
    output_file = output_dir / ('plant_fungal_guilds_test.parquet' if limit else 'plant_fungal_guilds.parquet')
    print(f"Saving to {output_file}...")
    result.to_parquet(output_file, compression='zstd', index=False)
    print(f"  ✓ Saved")
    print()

    # Summary statistics
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
            SUM(CASE WHEN trichoderma_count > 0 THEN 1 ELSE 0 END) as plants_with_trichoderma,
            SUM(CASE WHEN beauveria_metarhizium_count > 0 THEN 1 ELSE 0 END) as plants_with_beauveria_metarhizium,
            AVG(pathogenic_fungi_count) as avg_pathogens,
            AVG(mycorrhizae_total_count) as avg_mycorrhizae,
            AVG(endophytic_fungi_count) as avg_endophytic,
            AVG(saprotrophic_fungi_count) as avg_saprotrophic
        FROM result
    """).fetchone()

    print(f"Total plants: {stats[0]:,}")
    print()
    print(f"Plants with fungi by guild:")
    print(f"  - Pathogenic: {stats[1]:,} ({100*stats[1]/stats[0]:.1f}%)")
    print(f"  - Mycorrhizal: {stats[2]:,} ({100*stats[2]/stats[0]:.1f}%)")
    print(f"  - Biocontrol: {stats[3]:,} ({100*stats[3]/stats[0]:.1f}%)")
    print(f"  - Endophytic: {stats[4]:,} ({100*stats[4]/stats[0]:.1f}%)")
    print(f"  - Saprotrophic: {stats[5]:,} ({100*stats[5]/stats[0]:.1f}%)")
    print(f"  - Trichoderma: {stats[6]:,} ({100*stats[6]/stats[0]:.1f}%)")
    print(f"  - Beauveria/Metarhizium: {stats[7]:,} ({100*stats[7]/stats[0]:.1f}%)")
    print()
    print(f"Average fungal genera per plant:")
    print(f"  - Pathogenic: {stats[8]:.1f}")
    print(f"  - Mycorrhizal: {stats[9]:.1f}")
    print(f"  - Endophytic: {stats[10]:.1f}")
    print(f"  - Saprotrophic: {stats[11]:.1f}")
    print()

    # Show example: plants with richest fungal communities
    print("Example: Plants with richest fungal communities")
    examples = con.execute("""
        SELECT
            wfo_scientific_name,
            pathogenic_fungi_count,
            mycorrhizae_total_count,
            biocontrol_total_count,
            endophytic_fungi_count,
            saprotrophic_fungi_count,
            trichoderma_count
        FROM result
        WHERE pathogenic_fungi_count + mycorrhizae_total_count + biocontrol_total_count +
              endophytic_fungi_count + saprotrophic_fungi_count > 0
        ORDER BY pathogenic_fungi_count + mycorrhizae_total_count + biocontrol_total_count +
                 endophytic_fungi_count + saprotrophic_fungi_count DESC
        LIMIT 5
    """).fetchdf()
    print(examples.to_string(index=False))
    print()

    print("="*80)
    print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Output: {output_file}")
    print("="*80)

    con.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Extract fungal guild profiles from GloBI+FungalTraits (DuckDB-optimized)')
    parser.add_argument('--test', action='store_true', help='Run in test mode on limited plants')
    parser.add_argument('--limit', type=int, default=100, help='Number of plants to process in test mode')

    args = parser.parse_args()

    if args.test:
        extract_fungal_guilds(limit=args.limit)
    else:
        extract_fungal_guilds()

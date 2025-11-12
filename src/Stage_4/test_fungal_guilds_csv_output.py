#!/usr/bin/env python3
"""
Generate Python Baseline CSV for Fungal Guilds Extraction (Validation Experiment)

Purpose:
- Run the existing fungal guilds hybrid extraction (8 CTE DuckDB query)
- Output deterministic CSV with sorted rows and sorted list columns
- Generate MD5/SHA256 checksums for validation against pure R implementation

Usage:
    python src/Stage_4/test_fungal_guilds_csv_output.py
"""

import duckdb
import hashlib
import pandas as pd
from pathlib import Path
from datetime import datetime

def generate_baseline_csv():
    """Generate Python baseline CSV with checksums."""

    validation_dir = Path('shipley_checks/validation')
    validation_dir.mkdir(parents=True, exist_ok=True)

    print("="*80)
    print("PYTHON BASELINE: Fungal Guilds CSV Generation")
    print("="*80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    con = duckdb.connect()

    # Paths
    FUNGALTRAITS_PATH = "data/fungaltraits/fungaltraits.parquet"
    FUNGUILD_PATH = "data/funguild/funguild.parquet"
    PLANT_DATASET_PATH = "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet"
    GLOBI_PATH = "data/stage1/globi_interactions_plants_wfo.parquet"

    print("Running 8-CTE extraction query (Python DuckDB)...")
    print()

    # Run the full extraction query (same as 01_extract_fungal_guilds_hybrid.py)
    result = con.execute(f"""
        WITH
        -- Step 1: Get target plants
        target_plants AS (
            SELECT wfo_taxon_id, wfo_scientific_name, family, genus
            FROM read_parquet('{PLANT_DATASET_PATH}')
            ORDER BY wfo_scientific_name
        ),

        -- Step 2: Get all fungi from GloBI using BROAD relationship mining
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
            WHERE f.GENUS IS NOT NULL
        ),

        -- Step 4: Get unmatched genera for FunGuild fallback
        unmatched_genera AS (
            SELECT DISTINCT genus, target_wfo_taxon_id, phylum
            FROM hashost_fungi
            WHERE genus NOT IN (SELECT DISTINCT genus FROM ft_matches)
        ),

        -- Step 5: Match unmatched genera with FunGuild (FALLBACK)
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
              AND confidenceRanking IN ('Probable', 'Highly Probable')
        ),

        fg_matches AS (
            SELECT
                u.target_wfo_taxon_id,
                u.genus,
                'FunGuild' as source,
                -- Guild flags
                COALESCE(fg.is_pathogen, FALSE) as is_pathogen,
                FALSE as is_host_specific,
                COALESCE(fg.is_amf, FALSE) as is_amf,
                COALESCE(fg.is_emf, FALSE) as is_emf,
                COALESCE(fg.is_biocontrol_guild, FALSE) as is_mycoparasite,
                FALSE as is_entomopathogenic,
                COALESCE(fg.is_endophytic, FALSE) as is_endophytic,
                COALESCE(fg.is_saprotrophic, FALSE) as is_saprotrophic,
                (u.genus = 'trichoderma') as is_trichoderma,
                (u.genus IN ('beauveria', 'metarhizium')) as is_beauveria_metarhizium
            FROM unmatched_genera u
            LEFT JOIN fg_genus_lookup fg ON u.genus = fg.genus
        ),

        -- Step 6: UNION all matches
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

    print(f"  ✓ Extracted {len(result):,} plants")
    print()

    # CRITICAL: Sort by plant_wfo_id for deterministic row order
    print("Sorting rows by plant_wfo_id for deterministic output...")
    result = result.sort_values('plant_wfo_id').reset_index(drop=True)
    print("  ✓ Sorted")
    print()

    # Convert list columns to sorted pipe-separated strings
    list_cols = [
        'pathogenic_fungi',
        'pathogenic_fungi_host_specific',
        'amf_fungi',
        'emf_fungi',
        'mycoparasite_fungi',
        'entomopathogenic_fungi',
        'endophytic_fungi',
        'saprotrophic_fungi'
    ]

    print("Converting list columns to sorted pipe-separated strings...")
    for col in list_cols:
        result[col + '_csv'] = result[col].apply(
            lambda x: '|'.join(sorted(x)) if isinstance(x, list) and len(x) > 0 else ''
        )
    print("  ✓ Converted")
    print()

    # Drop original list columns (keep only CSV-compatible versions)
    result_csv = result.drop(columns=list_cols)

    # Rename CSV columns to remove _csv suffix
    rename_map = {col + '_csv': col for col in list_cols}
    result_csv = result_csv.rename(columns=rename_map)

    # Save CSV
    csv_file = validation_dir / 'fungal_guilds_python_baseline.csv'
    print(f"Saving CSV to {csv_file}...")
    result_csv.to_csv(csv_file, index=False)
    print(f"  ✓ Saved ({csv_file.stat().st_size / 1024 / 1024:.2f} MB)")
    print()

    # Generate checksums
    print("Generating checksums...")
    with open(csv_file, 'rb') as f:
        content = f.read()
        md5_hash = hashlib.md5(content).hexdigest()
        sha256_hash = hashlib.sha256(content).hexdigest()

    print(f"  MD5:    {md5_hash}")
    print(f"  SHA256: {sha256_hash}")
    print()

    # Save checksums
    checksum_file = validation_dir / 'fungal_guilds_python_baseline.checksums.txt'
    with open(checksum_file, 'w') as f:
        f.write(f"MD5:    {md5_hash}\n")
        f.write(f"SHA256: {sha256_hash}\n")
        f.write(f"\n")
        f.write(f"File: {csv_file}\n")
        f.write(f"Size: {csv_file.stat().st_size:,} bytes\n")
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

    print(f"  ✓ Checksums saved to {checksum_file}")
    print()

    # Generate summary statistics
    print("="*80)
    print("SUMMARY STATISTICS")
    print("="*80)

    stats = {
        'total_plants': len(result_csv),
        'plants_with_pathogens': (result_csv['pathogenic_fungi_count'] > 0).sum(),
        'plants_with_mycorrhizae': (result_csv['mycorrhizae_total_count'] > 0).sum(),
        'plants_with_biocontrol': (result_csv['biocontrol_total_count'] > 0).sum(),
        'plants_with_endophytic': (result_csv['endophytic_fungi_count'] > 0).sum(),
        'plants_with_saprotrophic': (result_csv['saprotrophic_fungi_count'] > 0).sum(),
        'total_ft_genera': result_csv['fungaltraits_genera'].sum(),
        'total_fg_genera': result_csv['funguild_genera'].sum()
    }

    print(f"Total plants: {stats['total_plants']:,}")
    print()
    print("Plants with fungi by guild:")
    print(f"  - Pathogenic: {stats['plants_with_pathogens']:,} ({stats['plants_with_pathogens']/stats['total_plants']*100:.1f}%)")
    print(f"  - Mycorrhizal: {stats['plants_with_mycorrhizae']:,} ({stats['plants_with_mycorrhizae']/stats['total_plants']*100:.1f}%)")
    print(f"  - Biocontrol: {stats['plants_with_biocontrol']:,} ({stats['plants_with_biocontrol']/stats['total_plants']*100:.1f}%)")
    print(f"  - Endophytic: {stats['plants_with_endophytic']:,} ({stats['plants_with_endophytic']/stats['total_plants']*100:.1f}%)")
    print(f"  - Saprotrophic: {stats['plants_with_saprotrophic']:,} ({stats['plants_with_saprotrophic']/stats['total_plants']*100:.1f}%)")
    print()
    print("Data source breakdown:")
    print(f"  - FungalTraits genera: {stats['total_ft_genera']:,}")
    print(f"  - FunGuild genera (fallback): {stats['total_fg_genera']:,}")
    print(f"  - FunGuild contribution: {stats['total_fg_genera']/(stats['total_ft_genera']+stats['total_fg_genera'])*100:.1f}%")
    print()

    # Save summary
    summary_file = validation_dir / 'fungal_guilds_python_baseline.summary.txt'
    with open(summary_file, 'w') as f:
        f.write("PYTHON BASELINE SUMMARY\n")
        f.write("="*80 + "\n\n")
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"CSV file: {csv_file}\n")
        f.write(f"File size: {csv_file.stat().st_size / 1024 / 1024:.2f} MB\n\n")

        f.write(f"Total plants: {stats['total_plants']:,}\n\n")

        f.write("Plants with fungi by guild:\n")
        f.write(f"  - Pathogenic: {stats['plants_with_pathogens']:,} ({stats['plants_with_pathogens']/stats['total_plants']*100:.1f}%)\n")
        f.write(f"  - Mycorrhizal: {stats['plants_with_mycorrhizae']:,} ({stats['plants_with_mycorrhizae']/stats['total_plants']*100:.1f}%)\n")
        f.write(f"  - Biocontrol: {stats['plants_with_biocontrol']:,} ({stats['plants_with_biocontrol']/stats['total_plants']*100:.1f}%)\n")
        f.write(f"  - Endophytic: {stats['plants_with_endophytic']:,} ({stats['plants_with_endophytic']/stats['total_plants']*100:.1f}%)\n")
        f.write(f"  - Saprotrophic: {stats['plants_with_saprotrophic']:,} ({stats['plants_with_saprotrophic']/stats['total_plants']*100:.1f}%)\n\n")

        f.write("Data source breakdown:\n")
        f.write(f"  - FungalTraits genera: {stats['total_ft_genera']:,}\n")
        f.write(f"  - FunGuild genera (fallback): {stats['total_fg_genera']:,}\n")
        f.write(f"  - FunGuild contribution: {stats['total_fg_genera']/(stats['total_ft_genera']+stats['total_fg_genera'])*100:.1f}%\n\n")

        f.write("Checksums:\n")
        f.write(f"  MD5:    {md5_hash}\n")
        f.write(f"  SHA256: {sha256_hash}\n")

    print(f"  ✓ Summary saved to {summary_file}")
    print()

    print("="*80)
    print(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Output: {csv_file}")
    print(f"Checksums: {checksum_file}")
    print(f"Summary: {summary_file}")
    print("="*80)

if __name__ == '__main__':
    generate_baseline_csv()

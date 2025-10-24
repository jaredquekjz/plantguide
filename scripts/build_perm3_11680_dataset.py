#!/usr/bin/env python3
"""
Build Perm3-style dataset for 11,680 species.
Manually replicates the exact column structure from the 1,084-species Perm3 dataset.
"""

import duckdb
import sys
from pathlib import Path

# Input files
ROSTER = "data/stage1/stage1_shortlist_with_gbif_ge30.csv"
TRAITS = "model_data/inputs/traits_model_ready_20251022_shortlist.csv"
CATEGORICAL = "data/stage1/stage1_union_canonical.parquet"
PHYLO = "model_data/outputs/p_phylo_proxy_shortlist_20251023.parquet"
ENV = "model_data/inputs/env_features_shortlist_20251022_means.csv"

# Output
OUTPUT_DIR = Path("model_data/inputs/mixgb_perm3_11680")
OUTPUT_PREFIX = "mixgb_input_perm3_shortlist_11680_20251024"

# Exact column order from Perm3 (182 columns)
PERM3_COLUMNS = [
    # IDs (2)
    "wfo_taxon_id", "wfo_scientific_name",
    # Target traits (6)
    "leaf_area_mm2", "nmass_mg_g", "ldmc_frac", "lma_g_m2", "plant_height_m", "seed_mass_mg",
    # Provenance (6)
    "leaf_area_source", "nmass_source", "ldmc_source", "lma_source", "height_source", "seed_mass_source",
    # TRY categorical (4)
    "try_woodiness", "try_growth_form", "try_habitat_adaptation", "try_leaf_type",
    # Environmental q50 - WorldClim bio (19)
    "wc2_1_30s_bio_1_q50", "wc2_1_30s_bio_10_q50", "wc2_1_30s_bio_11_q50", "wc2_1_30s_bio_12_q50",
    "wc2_1_30s_bio_13_q50", "wc2_1_30s_bio_14_q50", "wc2_1_30s_bio_15_q50", "wc2_1_30s_bio_16_q50",
    "wc2_1_30s_bio_18_q50", "wc2_1_30s_bio_19_q50", "wc2_1_30s_bio_2_q50", "wc2_1_30s_bio_3_q50",
    "wc2_1_30s_bio_4_q50", "wc2_1_30s_bio_5_q50", "wc2_1_30s_bio_6_q50", "wc2_1_30s_bio_7_q50",
    "wc2_1_30s_bio_8_q50", "wc2_1_30s_bio_9_q50",
    # Environmental q50 - WorldClim elev + srad + vapr (25)
    "wc2_1_30s_elev_q50",
    "wc2_1_30s_srad_01_q50", "wc2_1_30s_srad_02_q50", "wc2_1_30s_srad_03_q50", "wc2_1_30s_srad_04_q50",
    "wc2_1_30s_srad_05_q50", "wc2_1_30s_srad_06_q50", "wc2_1_30s_srad_07_q50", "wc2_1_30s_srad_08_q50",
    "wc2_1_30s_srad_09_q50", "wc2_1_30s_srad_10_q50", "wc2_1_30s_srad_11_q50", "wc2_1_30s_srad_12_q50",
    "wc2_1_30s_vapr_01_q50", "wc2_1_30s_vapr_02_q50", "wc2_1_30s_vapr_03_q50", "wc2_1_30s_vapr_04_q50",
    "wc2_1_30s_vapr_05_q50", "wc2_1_30s_vapr_06_q50", "wc2_1_30s_vapr_07_q50", "wc2_1_30s_vapr_08_q50",
    "wc2_1_30s_vapr_09_q50", "wc2_1_30s_vapr_10_q50", "wc2_1_30s_vapr_11_q50", "wc2_1_30s_vapr_12_q50",
    # Environmental q50 - SoilGrids (42)
    "phh2o_0_5cm_q50", "phh2o_5_15cm_q50", "phh2o_15_30cm_q50", "phh2o_30_60cm_q50",
    "phh2o_60_100cm_q50", "phh2o_100_200cm_q50",
    "soc_0_5cm_q50", "soc_5_15cm_q50", "soc_15_30cm_q50", "soc_30_60cm_q50",
    "soc_60_100cm_q50", "soc_100_200cm_q50",
    "clay_0_5cm_q50", "clay_5_15cm_q50", "clay_15_30cm_q50", "clay_30_60cm_q50",
    "clay_60_100cm_q50", "clay_100_200cm_q50",
    "sand_0_5cm_q50", "sand_5_15cm_q50", "sand_15_30cm_q50", "sand_30_60cm_q50",
    "sand_60_100cm_q50", "sand_100_200cm_q50",
    "cec_0_5cm_q50", "cec_5_15cm_q50", "cec_15_30cm_q50", "cec_30_60cm_q50",
    "cec_60_100cm_q50", "cec_100_200cm_q50",
    "nitrogen_0_5cm_q50", "nitrogen_5_15cm_q50", "nitrogen_15_30cm_q50", "nitrogen_30_60cm_q50",
    "nitrogen_60_100cm_q50", "nitrogen_100_200cm_q50",
    "bdod_0_5cm_q50", "bdod_5_15cm_q50", "bdod_15_30cm_q50", "bdod_30_60cm_q50",
    "bdod_60_100cm_q50", "bdod_100_200cm_q50",
    # Environmental q50 - AgroClim (51)
    "BEDD_q50", "BEDD_1_q50", "CDD_q50", "CDD_1_q50", "CFD_q50", "CFD_1_q50",
    "CSDI_q50", "CSDI_1_q50", "CSU_q50", "CSU_1_q50", "CWD_q50", "CWD_1_q50",
    "DTR_q50", "DTR_1_q50", "FD_q50", "FD_1_q50", "GSL_q50", "GSL_1_q50", "ID_1_q50",
    "R10mm_q50", "R10mm_1_q50", "R20mm_q50", "R20mm_1_q50",
    "RR_q50", "RR_1_q50", "RR1_q50", "RR1_1_q50", "SDII_q50", "SDII_1_q50",
    "SU_q50", "SU_1_q50", "TG_q50", "TG_1_q50", "TN_q50", "TN_1_q50",
    "TNn_q50", "TNn_1_q50", "TNx_q50", "TNx_1_q50", "TR_q50", "TR_1_q50",
    "TX_q50", "TX_1_q50", "TXn_q50", "TXn_1_q50", "TXx_q50", "TXx_1_q50",
    "WSDI_q50", "WSDI_1_q50", "WW_q50", "WW_1_q50",
    # Alternate traits and metadata (15)
    "leaf_area_n", "try_logNmass", "try_ldmc", "aust_ldmc", "try_lma", "aust_lma",
    "try_sla", "aust_sla", "sla_mm2_mg", "sla_source",
    "try_seed_mass", "aust_seed_mass", "try_height", "aust_height", "try_logLA",
    # Log transforms (6) - ESSENTIAL!
    "logLDMC", "logSLA", "logSM", "logH", "logLA", "logNmass",
    # Text taxonomy (2)
    "genus", "family",
    # Phylo (5)
    "phylo_depth", "phylo_terminal", "genus_code", "family_code", "phylo_proxy_fallback"
]

def main():
    print(f"Building Perm3-style dataset for 11,680 species...")
    print(f"Target: {len(PERM3_COLUMNS)} columns (exact match to Perm3)")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    con = duckdb.connect()

    try:
        # Load roster
        print(f"[1/5] Loading roster: {ROSTER}")
        con.execute(f"""
            CREATE TEMP TABLE roster AS
            SELECT wfo_taxon_id
            FROM read_csv('{ROSTER}')
        """)
        roster_count = con.execute("SELECT COUNT(*) FROM roster").fetchone()[0]
        print(f"  ✓ {roster_count} species")

        # Load traits (rename try_nmass -> nmass_mg_g to match Perm3)
        print(f"[2/5] Loading traits: {TRAITS}")
        con.execute(f"""
            CREATE TEMP TABLE traits AS
            SELECT
                * EXCLUDE (try_nmass),
                try_nmass AS nmass_mg_g
            FROM read_csv('{TRAITS}')
        """)
        traits_count = con.execute("SELECT COUNT(*) FROM traits").fetchone()[0]
        print(f"  ✓ {traits_count} species")

        # Load categorical (rename wfo_id -> wfo_taxon_id)
        print(f"[3/5] Loading categorical: {CATEGORICAL}")
        con.execute(f"""
            CREATE TEMP TABLE categorical AS
            SELECT
                wfo_id AS wfo_taxon_id,
                try_woodiness,
                try_growth_form,
                try_habitat_adaptation,
                try_leaf_type
            FROM read_parquet('{CATEGORICAL}')
        """)
        cat_count = con.execute("SELECT COUNT(*) FROM categorical").fetchone()[0]
        print(f"  ✓ {cat_count} species")

        # Load phylo
        print(f"[4/5] Loading phylo: {PHYLO}")
        con.execute(f"""
            CREATE TEMP TABLE phylo AS
            SELECT
                wfo_taxon_id,
                genus,
                family,
                phylo_depth,
                phylo_terminal,
                genus_code,
                family_code,
                phylo_proxy_fallback
            FROM read_parquet('{PHYLO}')
        """)
        phylo_count = con.execute("SELECT COUNT(*) FROM phylo").fetchone()[0]
        print(f"  ✓ {phylo_count} species")

        # Load environmental (drop metadata columns)
        print(f"[5/5] Loading environmental: {ENV}")
        con.execute(f"""
            CREATE TEMP TABLE env AS
            SELECT * EXCLUDE (species, wfo_accepted_name, Genus, Family)
            FROM read_csv('{ENV}')
        """)
        env_count = con.execute("SELECT COUNT(*) FROM env").fetchone()[0]
        print(f"  ✓ {env_count} species")

        # Join all tables
        print("\nJoining datasets...")
        con.execute("""
            CREATE TEMP TABLE merged AS
            SELECT
                r.wfo_taxon_id,
                t.*,
                c.try_woodiness,
                c.try_growth_form,
                c.try_habitat_adaptation,
                c.try_leaf_type,
                e.* EXCLUDE (wfo_taxon_id),
                p.genus,
                p.family,
                p.phylo_depth,
                p.phylo_terminal,
                p.genus_code,
                p.family_code,
                p.phylo_proxy_fallback
            FROM roster r
            LEFT JOIN traits t ON r.wfo_taxon_id = t.wfo_taxon_id
            LEFT JOIN categorical c ON r.wfo_taxon_id = c.wfo_taxon_id
            LEFT JOIN env e ON r.wfo_taxon_id = e.wfo_taxon_id
            LEFT JOIN phylo p ON r.wfo_taxon_id = p.wfo_taxon_id
        """)
        merged_count = con.execute("SELECT COUNT(*) FROM merged").fetchone()[0]
        print(f"  ✓ {merged_count} species merged")

        # Verify all Perm3 columns exist
        print("\nVerifying column structure...")
        merged_cols = [row[0] for row in con.execute("DESCRIBE merged").fetchall()]
        missing = [col for col in PERM3_COLUMNS if col not in merged_cols]

        if missing:
            print(f"  ✗ ERROR: Missing columns: {missing}")
            sys.exit(1)

        # Select columns in exact Perm3 order
        col_list = ", ".join([f'"{col}"' for col in PERM3_COLUMNS])

        output_csv = OUTPUT_DIR / f"{OUTPUT_PREFIX}.csv"
        output_parquet = OUTPUT_DIR / f"{OUTPUT_PREFIX}.parquet"

        print(f"\nWriting outputs...")
        print(f"  CSV: {output_csv}")
        con.execute(f"""
            COPY (
                SELECT {col_list}
                FROM merged
                ORDER BY wfo_taxon_id
            ) TO '{output_csv}' (HEADER, DELIMITER ',')
        """)

        print(f"  Parquet: {output_parquet}")
        con.execute(f"""
            COPY (
                SELECT {col_list}
                FROM merged
                ORDER BY wfo_taxon_id
            ) TO '{output_parquet}' (FORMAT PARQUET, COMPRESSION ZSTD)
        """)

        # Verification
        final_rows = con.execute(f"SELECT COUNT(*) FROM read_csv('{output_csv}')").fetchone()[0]
        final_cols = len(con.execute(f"SELECT * FROM read_csv('{output_csv}', AUTO_DETECT=TRUE) LIMIT 0").description)

        print(f"\n{'='*60}")
        print(f"✓ SUCCESS!")
        print(f"{'='*60}")
        print(f"Dataset: {final_rows} species × {final_cols} columns")
        print(f"Expected: 11,680 species × 182 columns")
        print(f"Match: {'✓' if final_rows == 11680 and final_cols == 182 else '✗ MISMATCH!'}")
        print(f"\nOutputs:")
        print(f"  - {output_csv}")
        print(f"  - {output_parquet}")

        if final_cols == 182:
            print(f"\n✓ Column count matches Perm3 exactly!")
            print(f"✓ Ready for XGBoost imputation with eta=0.05, nrounds=2000")
        else:
            print(f"\n✗ WARNING: Column count mismatch (got {final_cols}, expected 182)")

    finally:
        con.close()

if __name__ == "__main__":
    main()

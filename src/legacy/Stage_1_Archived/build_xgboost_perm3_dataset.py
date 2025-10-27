#!/usr/bin/env python3
"""
Build XGBoost Perm3 CANONICAL dataset for 11,680 species.

CANONICAL = Training-ready only, no metadata/provenance

Key features:
- COMPLETE environmental features: 156 q50 (WorldClim 63 + SoilGrids 42 + Agroclim 51)
- EIVE features EXCLUDED (Perm3 design - better performance)
- Canonical SLA (not LMA) as target trait
- Log transforms included as explicit predictors (essential for 3x performance)
- 7 TRY categorical features (woodiness, growth_form, habitat, leaf_type, phenology, photosynthesis, mycorrhiza)
- NO provenance columns (dropped for canonical dataset)
- NO alternate trait metadata (dropped for canonical dataset)
- NO text taxonomy (dropped for canonical dataset)

Result: 182 columns (clean training-ready)
  - 2 IDs
  - 6 target traits
  - 7 TRY categorical
  - 156 environmental q50
  - 6 log transforms
  - 5 phylogenetic codes
"""

import duckdb
import sys
from pathlib import Path

# Input files
ROSTER = "data/stage1/stage1_shortlist_with_gbif_ge30.csv"
TRAITS = "model_data/inputs/traits_model_ready_20251022_shortlist.csv"
CATEGORICAL = "data/stage1/stage1_union_canonical.parquet"
PHYLO = "model_data/outputs/p_phylo_proxy_shortlist_20251023.parquet"
ENV = "model_data/inputs/env_features_shortlist_20251025_complete_q50_xgb.csv"

# Output
OUTPUT_DIR = Path("model_data/inputs/mixgb_perm3_11680")
OUTPUT_PREFIX = "mixgb_input_perm3_shortlist_11680_20251025_sla_canonical"

# Fixed columns for CANONICAL training-ready dataset
FIXED_COLUMNS = [
    # IDs (2)
    "wfo_taxon_id", "wfo_scientific_name",
    # Target traits (6) - CANONICAL SLA not LMA
    "leaf_area_mm2", "nmass_mg_g", "ldmc_frac", "sla_mm2_mg", "plant_height_m", "seed_mass_mg",
    # TRY categorical (7)
    "try_woodiness", "try_growth_form", "try_habitat_adaptation", "try_leaf_type",
    "try_leaf_phenology", "try_photosynthesis_pathway", "try_mycorrhiza_type",
]

# Environmental q50 columns will be dynamically detected from env file (156 features)

# Training features (log transforms + phylo codes)
TRAINING_COLUMNS = [
    # Log transforms (6) - ESSENTIAL for 3x performance!
    "logLDMC", "logSLA", "logSM", "logH", "logLA", "logNmass",
    # Phylogenetic codes (5)
    "phylo_depth", "phylo_terminal", "genus_code", "family_code", "phylo_proxy_fallback"
]

def main():
    print(f"Building XGBoost Perm3 dataset for 11,680 species...")
    print(f"Target: COMPLETE environmental features (156 q50)")
    print(f"EIVE features: EXCLUDED (Perm3 design)")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    con = duckdb.connect()

    try:
        # Load roster
        print(f"\n[1/5] Loading roster: {ROSTER}")
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
                try_leaf_type,
                try_leaf_phenology,
                try_photosynthesis_pathway,
                try_mycorrhiza_type
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

        # Load environmental - dynamically detect all q50 columns
        print(f"[5/5] Loading environmental: {ENV}")
        con.execute(f"""
            CREATE TEMP TABLE env AS
            SELECT *
            FROM read_csv('{ENV}')
        """)
        env_count = con.execute("SELECT COUNT(*) FROM env").fetchone()[0]

        # Get all q50 column names from env table
        env_cols = [row[0] for row in con.execute("DESCRIBE env").fetchall()]
        env_q50_cols = sorted([c for c in env_cols if c.endswith('_q50')])

        print(f"  ✓ {env_count} species")
        print(f"  ✓ {len(env_q50_cols)} q50 environmental features detected")

        # Breakdown by source
        wc_bio = len([c for c in env_q50_cols if 'bio_' in c])
        wc_other = len([c for c in env_q50_cols if c.startswith('wc2_') and 'bio_' not in c])
        soil = len([c for c in env_q50_cols if any(x in c for x in ['phh2o', 'soc', 'clay', 'sand', 'cec', 'nitrogen', 'bdod'])])
        agro = len(env_q50_cols) - wc_bio - wc_other - soil

        print(f"    WorldClim bio:  {wc_bio}")
        print(f"    WorldClim other: {wc_other} (elev/srad/vapr)")
        print(f"    SoilGrids:      {soil}")
        print(f"    Agroclim:       {agro}")

        # Join all tables
        print("\n[6/6] Joining datasets...")
        con.execute("""
            CREATE TEMP TABLE merged AS
            SELECT
                r.wfo_taxon_id,
                t.*,
                c.try_woodiness,
                c.try_growth_form,
                c.try_habitat_adaptation,
                c.try_leaf_type,
                c.try_leaf_phenology,
                c.try_photosynthesis_pathway,
                c.try_mycorrhiza_type,
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

        # Build final column list: fixed + env_q50 + training (CANONICAL)
        final_columns = FIXED_COLUMNS + env_q50_cols + TRAINING_COLUMNS

        print(f"\n[7/7] Verifying column structure...")
        merged_cols = [row[0] for row in con.execute("DESCRIBE merged").fetchall()]
        missing = [col for col in final_columns if col not in merged_cols]

        if missing:
            print(f"  ✗ ERROR: Missing columns: {missing[:10]}")
            print(f"  Total missing: {len(missing)}")
            sys.exit(1)

        print(f"  ✓ All {len(final_columns)} columns present (CANONICAL)")
        print(f"    IDs + Traits + Categorical: {len(FIXED_COLUMNS)}")
        print(f"    Environmental q50:          {len(env_q50_cols)}")
        print(f"    Training features (log+phylo): {len(TRAINING_COLUMNS)}")

        # Select columns in final order
        col_list = ", ".join([f'"{col}"' for col in final_columns])

        output_csv = OUTPUT_DIR / f"{OUTPUT_PREFIX}.csv"
        output_parquet = OUTPUT_DIR / f"{OUTPUT_PREFIX}.parquet"

        print(f"\n[8/8] Writing outputs...")
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

        # Count actual env features in output
        output_cols = [row[0] for row in con.execute(f"DESCRIBE SELECT * FROM read_csv('{output_csv}') LIMIT 0").fetchall()]
        output_env_q50 = [c for c in output_cols if c.endswith('_q50')]

        print(f"\n{'='*70}")
        print(f"✓ SUCCESS!")
        print(f"{'='*70}")
        print(f"Dataset: {final_rows:,} species × {final_cols} columns")
        print(f"Expected: 11,680 species × {len(final_columns)} columns")
        print(f"Match: {'✓' if final_rows == 11680 and final_cols == len(final_columns) else '✗'}")
        print(f"\nEnvironmental features:")
        print(f"  q50 columns: {len(output_env_q50)} (expected: 156)")
        print(f"  Match: {'✓ COMPLETE' if len(output_env_q50) == 156 else '✗ INCOMPLETE'}")
        print(f"\nOutputs:")
        print(f"  - {output_csv}")
        print(f"  - {output_parquet}")

        if len(output_env_q50) == 156:
            print(f"\n✓ Complete environmental features (156 q50)!")
            print(f"✓ WorldClim (63) + SoilGrids (42) + Agroclim (51)")
            print(f"✓ Ready for XGBoost imputation")
        else:
            print(f"\n✗ WARNING: Environmental features incomplete")
            print(f"  Got {len(output_env_q50)}, expected 156")

    finally:
        con.close()

if __name__ == "__main__":
    main()

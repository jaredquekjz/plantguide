#!/usr/bin/env python3
"""
Phase 1: Data Preparation for Stage 3 Integration
==================================================

Adds pre-calculated climate sensitivity ratings to the existing dataset:
- drought_sensitivity (High/Medium/Low) from CDD_q95
- frost_sensitivity (High/Medium/Low) from CFD_q95
- heat_sensitivity (High/Medium/Low) from WSDI_q95

These are computed once and stored for fast guild-level vulnerability analysis.

Input:  model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet
Output: model_data/outputs/perm2_production/perm2_11680_with_climate_sensitivity_20251102.parquet

Usage:
    python src/Stage_4/06_prepare_stage3_integration.py
"""

import duckdb
from pathlib import Path
from datetime import datetime

def main():
    print("="*80)
    print("Phase 1: Data Preparation for Stage 3 Integration")
    print("="*80)
    print()

    # Paths
    input_file = Path('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')
    output_file = Path('model_data/outputs/perm2_production/perm2_11680_with_climate_sensitivity_20251102.parquet')

    print(f"Input:  {input_file}")
    print(f"Output: {output_file}")
    print()

    # Check input exists
    if not input_file.exists():
        print(f"ERROR: Input file not found: {input_file}")
        return

    # Connect to DuckDB
    con = duckdb.connect()

    print("Checking input dataset...")
    row_count = con.execute(f"""
        SELECT COUNT(*) as count FROM read_parquet('{input_file}')
    """).fetchone()[0]

    print(f"  Rows: {row_count:,}")
    print()

    print("Adding climate sensitivity ratings using pure DuckDB SQL...")
    print()

    # Create new parquet with added columns using pure SQL
    output_file.parent.mkdir(parents=True, exist_ok=True)

    con.execute(f"""
        COPY (
            SELECT
                *,
                -- DROUGHT SENSITIVITY (from CDD_q95)
                -- Logic: LOW q95 = only survived MILD droughts = SENSITIVE
                CASE
                    WHEN CDD_q95 IS NULL THEN NULL
                    WHEN CDD_q95 < 30 THEN 'High'     -- Needs reliable moisture
                    WHEN CDD_q95 < 60 THEN 'Medium'   -- Moderate tolerance
                    ELSE 'Low'                        -- Drought-tolerant
                END AS drought_sensitivity,

                -- FROST SENSITIVITY (from CFD_q95)
                -- Logic: LOW q95 = only survived BRIEF frosts = SENSITIVE
                CASE
                    WHEN CFD_q95 IS NULL THEN NULL
                    WHEN CFD_q95 < 10 THEN 'High'     -- Frost-tender
                    WHEN CFD_q95 < 30 THEN 'Medium'   -- Some frost tolerance
                    ELSE 'Low'                        -- Frost-tolerant
                END AS frost_sensitivity,

                -- HEAT SENSITIVITY (from WSDI_q95)
                -- Logic: LOW q95 = only survived SHORT heat spells = SENSITIVE
                CASE
                    WHEN WSDI_q95 IS NULL THEN NULL
                    WHEN WSDI_q95 < 20 THEN 'High'    -- Prefers cool climates
                    WHEN WSDI_q95 < 50 THEN 'Medium'  -- Moderate heat tolerance
                    ELSE 'Low'                        -- Heat-tolerant
                END AS heat_sensitivity

            FROM read_parquet('{input_file}')
        )
        TO '{output_file}'
        (FORMAT PARQUET, COMPRESSION ZSTD)
    """)

    file_size_mb = output_file.stat().st_size / (1024 * 1024)
    print(f"  Created parquet file: {file_size_mb:.1f} MB")
    print()

    # Calculate statistics using DuckDB
    print("DROUGHT SENSITIVITY (from CDD_q95 - consecutive dry days):")
    print("  High:   Survived <30 days max drought (needs reliable moisture)")
    print("  Medium: Survived 30-60 days")
    print("  Low:    Survived >60 days (drought-tolerant)")
    print()

    drought_stats = con.execute(f"""
        SELECT
            drought_sensitivity,
            COUNT(*) as count,
            ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as percentage
        FROM read_parquet('{output_file}')
        GROUP BY drought_sensitivity
        ORDER BY
            CASE drought_sensitivity
                WHEN 'High' THEN 1
                WHEN 'Medium' THEN 2
                WHEN 'Low' THEN 3
                ELSE 4
            END
    """).fetchall()

    for level, count, pct in drought_stats:
        level_str = str(level) if level is not None else 'NULL'
        print(f"  {level_str:8s}: {count:5,} ({pct:5.1f}%)")
    print()

    print("FROST SENSITIVITY (from CFD_q95 - consecutive frost days):")
    print("  High:   Survived <10 days frost (frost-tender)")
    print("  Medium: Survived 10-30 days")
    print("  Low:    Survived >30 days (frost-tolerant)")
    print()

    frost_stats = con.execute(f"""
        SELECT
            frost_sensitivity,
            COUNT(*) as count,
            ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as percentage
        FROM read_parquet('{output_file}')
        GROUP BY frost_sensitivity
        ORDER BY
            CASE frost_sensitivity
                WHEN 'High' THEN 1
                WHEN 'Medium' THEN 2
                WHEN 'Low' THEN 3
                ELSE 4
            END
    """).fetchall()

    for level, count, pct in frost_stats:
        level_str = str(level) if level is not None else 'NULL'
        print(f"  {level_str:8s}: {count:5,} ({pct:5.1f}%)")
    print()

    print("HEAT SENSITIVITY (from WSDI_q95 - warm spell days):")
    print("  High:   Survived <20 days heat (prefers cool climates)")
    print("  Medium: Survived 20-50 days")
    print("  Low:    Survived >50 days (heat-tolerant)")
    print()

    heat_stats = con.execute(f"""
        SELECT
            heat_sensitivity,
            COUNT(*) as count,
            ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as percentage
        FROM read_parquet('{output_file}')
        GROUP BY heat_sensitivity
        ORDER BY
            CASE heat_sensitivity
                WHEN 'High' THEN 1
                WHEN 'Medium' THEN 2
                WHEN 'Low' THEN 3
                ELSE 4
            END
    """).fetchall()

    for level, count, pct in heat_stats:
        level_str = str(level) if level is not None else 'NULL'
        print(f"  {level_str:8s}: {count:5,} ({pct:5.1f}%)")
    print()

    print("="*80)
    print("SUCCESS: Phase 1 data preparation complete")
    print("="*80)
    print()
    print(f"Output: {output_file}")
    print(f"Columns added: drought_sensitivity, frost_sensitivity, heat_sensitivity")
    print()

    con.close()


if __name__ == '__main__':
    main()

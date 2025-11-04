#!/usr/bin/env python3
"""
Calibrate global CSR percentiles for N4 conflict detection.

Unlike guild metrics (tier-stratified), CSR thresholds use GLOBAL percentiles
because conflicts are within-guild comparisons, not cross-guild comparisons.
"""

import duckdb
import numpy as np
import json
from pathlib import Path

def calibrate_csr_percentiles():
    """
    Compute global percentiles for C, S, R across all 11,680 plants.

    Returns tier-independent percentile thresholds for consistent
    interpretation of "High C", "High S", "High R".
    """
    con = duckdb.connect()

    # Load all plants with CSR scores
    plants = con.execute("""
        SELECT
            C as csr_c,
            S as csr_s,
            R as csr_r
        FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet')
        WHERE C IS NOT NULL AND S IS NOT NULL AND R IS NOT NULL
    """).fetchdf()

    print(f"Loaded {len(plants)} plants with CSR scores")

    # Compute percentiles for each strategy
    percentiles = [1, 5, 10, 20, 30, 40, 50, 60, 70, 75, 80, 85, 90, 95, 99]

    calibration = {}

    for strategy in ['C', 'S', 'R']:
        col = f'csr_{strategy.lower()}'
        values = plants[col].values

        # Compute percentile thresholds
        pct_values = np.percentile(values, percentiles)

        strategy_cal = {'method': 'percentile', 'n_samples': len(values)}
        for p, val in zip(percentiles, pct_values):
            strategy_cal[f'p{p}'] = float(val)

        calibration[strategy.lower()] = strategy_cal

        # Print for verification
        print(f"\n{strategy} Strategy Percentiles:")
        print(f"  p50 (median): {strategy_cal['p50']:.1f}")
        print(f"  p75 (top quartile): {strategy_cal['p75']:.1f}")
        print(f"  p90 (top decile): {strategy_cal['p90']:.1f}")

    # Save calibration
    output_dir = Path('data/stage4')
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / 'csr_percentile_calibration_global.json'

    with open(output_path, 'w') as f:
        json.dump(calibration, f, indent=2)

    print(f"\nSaved calibration to {output_path}")

    # Print comparison with fixed thresholds
    print("\n" + "="*80)
    print("COMPARISON: Fixed Thresholds (60, 60, 50) vs Percentiles")
    print("="*80)

    for strategy, fixed_thresh in [('C', 60), ('S', 60), ('R', 50)]:
        col = f'csr_{strategy.lower()}'
        actual_percentile = (plants[col] < fixed_thresh).mean() * 100

        print(f"\n{strategy} ≥ {fixed_thresh}:")
        print(f"  Actual percentile: {actual_percentile:.1f}th")
        print(f"  Interpretation: Top {100-actual_percentile:.1f}% of plants")

        # What value gives p75 (consistent "High")?
        p75_val = calibration[strategy.lower()]['p75']
        print(f"  P75 threshold: {p75_val:.1f} (top quartile)")

    return calibration


if __name__ == '__main__':
    calibration = calibrate_csr_percentiles()

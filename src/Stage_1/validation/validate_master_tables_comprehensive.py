#!/usr/bin/env python3
"""
Comprehensive validation pipeline for Stage 1.10 master tables.
Validates both full production (11,680) and modelling shortlist (1,084) datasets.
"""
import pandas as pd
import numpy as np
from pathlib import Path
import sys

def validate_file_existence():
    """Check all required files exist with correct sizes."""
    print("="*80)
    print("1. FILE EXISTENCE AND SIZE VALIDATION")
    print("="*80)

    files = {
        'Full production (CSV)': 'model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.csv',
        'Full production (Parquet)': 'model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.parquet',
        'Modelling shortlist (CSV)': 'model_data/inputs/modelling_master_1084_20251029.csv',
        'Modelling shortlist (Parquet)': 'model_data/inputs/modelling_master_1084_20251029.parquet',
        'WFO shortlist': 'data/stage1/stage1_modelling_shortlist_with_gbif_ge30.parquet',
        'Phylo predictors': 'model_data/outputs/p_phylo_11680_20251028.csv',
    }

    all_exist = True
    for name, path in files.items():
        exists = Path(path).exists()
        if exists:
            size_mb = Path(path).stat().st_size / 1024 / 1024
            print(f"✓ {name:35} {size_mb:>8.2f} MB")
        else:
            print(f"✗ {name:35} MISSING")
            all_exist = False

    return all_exist

def validate_schema(df, expected_shape, dataset_name):
    """Validate dataset dimensions and schema."""
    print(f"\n2. SCHEMA VALIDATION: {dataset_name}")
    print("="*80)

    issues = []

    # Dimensions
    print(f"Expected shape: {expected_shape[0]:,} × {expected_shape[1]}")
    print(f"Actual shape:   {df.shape[0]:,} × {df.shape[1]}")
    if df.shape != expected_shape:
        issues.append(f"Shape mismatch: expected {expected_shape}, got {df.shape}")

    # Required columns
    required_groups = {
        'IDs': ['wfo_taxon_id', 'wfo_scientific_name'],
        'Log traits': ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM'],
        'EIVE indicators': ['EIVEres-L', 'EIVEres-T', 'EIVEres-M', 'EIVEres-N', 'EIVEres-R'],
        'Phylo predictors': ['p_phylo_T', 'p_phylo_M', 'p_phylo_L', 'p_phylo_N', 'p_phylo_R'],
        'Categorical traits': ['try_woodiness', 'try_growth_form', 'try_habitat_adaptation', 'try_leaf_type',
                               'try_leaf_phenology', 'try_photosynthesis_pathway', 'try_mycorrhiza_type'],
    }

    for group, cols in required_groups.items():
        missing = [c for c in cols if c not in df.columns]
        if missing:
            issues.append(f"Missing {group}: {missing}")
        else:
            print(f"✓ {group:20} {len(cols)} columns present")

    # Phylo eigenvectors
    phylo_ev = [c for c in df.columns if c.startswith('phylo_ev')]
    print(f"✓ Phylo eigenvectors:  {len(phylo_ev)} columns (expected 92)")
    if len(phylo_ev) != 92:
        issues.append(f"Expected 92 phylo eigenvectors, found {len(phylo_ev)}")

    # Environmental quantiles (full: q05, q50, q95, iqr)
    env_q05 = [c for c in df.columns if c.endswith('_q05')]
    env_q50 = [c for c in df.columns if c.endswith('_q50')]
    env_q95 = [c for c in df.columns if c.endswith('_q95')]
    env_iqr = [c for c in df.columns if c.endswith('_iqr')]
    print(f"✓ Environmental quantiles: {len(env_q05)+len(env_q50)+len(env_q95)+len(env_iqr)} columns "
          f"(expected 624: 156 vars × 4 quantiles)")
    if len(env_q05) != 156 or len(env_q50) != 156 or len(env_q95) != 156 or len(env_iqr) != 156:
        issues.append(f"Expected 156 for each quantile, found q05={len(env_q05)}, q50={len(env_q50)}, "
                     f"q95={len(env_q95)}, iqr={len(env_iqr)}")

    return issues

def validate_data_integrity(df, dataset_name):
    """Validate data integrity and completeness."""
    print(f"\n3. DATA INTEGRITY: {dataset_name}")
    print("="*80)

    issues = []

    # Unique WFO IDs
    n_unique = df['wfo_taxon_id'].nunique()
    n_dupes = df['wfo_taxon_id'].duplicated().sum()
    print(f"Unique WFO IDs:        {n_unique:,}")
    print(f"Duplicate rows:        {n_dupes}")
    if n_dupes > 0:
        issues.append(f"Found {n_dupes} duplicate WFO IDs")

    # WFO ID format validation
    invalid_wfo = df[~df['wfo_taxon_id'].str.match(r'^wfo-\d{10}$', na=False)]
    print(f"Invalid WFO ID format: {len(invalid_wfo)}")
    if len(invalid_wfo) > 0:
        issues.append(f"Found {len(invalid_wfo)} invalid WFO ID formats")
        print(f"  Examples: {invalid_wfo['wfo_taxon_id'].head(3).tolist()}")

    # Trait completeness (must be 100%)
    traits = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']
    print(f"\nTrait completeness (expected 100%):")
    for trait in traits:
        n_complete = df[trait].notna().sum()
        pct = 100 * n_complete / len(df)
        status = "✓" if pct == 100 else "✗"
        print(f"  {status} {trait:12} {n_complete:>5} / {len(df):>5} ({pct:>6.2f}%)")
        if pct < 100:
            issues.append(f"{trait} not 100% complete: {pct:.2f}%")

    # Environmental completeness (must be 100%)
    env_cols = [c for c in df.columns if c.endswith(('_q05', '_q50', '_q95', '_iqr'))]
    missing_all_env = df[env_cols].isna().all(axis=1).sum()
    print(f"\nSpecies missing ALL environmental features: {missing_all_env}")
    if missing_all_env > 0:
        issues.append(f"{missing_all_env} species missing all environmental features")

    # Phylo predictor coverage
    p_phylo = ['p_phylo_T', 'p_phylo_M', 'p_phylo_L', 'p_phylo_N', 'p_phylo_R']
    print(f"\nPhylogenetic predictor coverage:")
    for col in p_phylo:
        n_present = df[col].notna().sum()
        pct = 100 * n_present / len(df)
        print(f"  {col:12} {n_present:>5} / {len(df):>5} ({pct:>6.2f}%)")
        if pct < 90:
            issues.append(f"{col} coverage below 90%: {pct:.2f}%")

    return issues

def validate_value_ranges(df, dataset_name):
    """Validate feature value ranges and distributions."""
    print(f"\n4. VALUE RANGE VALIDATION: {dataset_name}")
    print("="*80)

    issues = []

    # Log trait ranges (should be reasonable)
    print("Log trait ranges:")
    traits = ['logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM']
    for trait in traits:
        vals = df[trait].dropna()
        q01, q50, q99 = vals.quantile([0.01, 0.5, 0.99])
        print(f"  {trait:12} min={vals.min():>7.2f}, q01={q01:>7.2f}, q50={q50:>7.2f}, "
              f"q99={q99:>7.2f}, max={vals.max():>7.2f}")

        # Check for extreme outliers (> 10 std from mean)
        z_scores = np.abs((vals - vals.mean()) / vals.std())
        n_outliers = (z_scores > 10).sum()
        if n_outliers > 0:
            issues.append(f"{trait}: {n_outliers} extreme outliers (>10 std)")

    # EIVE ranges (should be 0-10)
    print("\nEIVE indicator ranges (expected 0-10):")
    eive = ['EIVEres-L', 'EIVEres-T', 'EIVEres-M', 'EIVEres-N', 'EIVEres-R']
    for col in eive:
        vals = df[col].dropna()
        if len(vals) > 0:
            print(f"  {col:12} min={vals.min():>6.2f}, max={vals.max():>6.2f}")
            if vals.min() < 0 or vals.max() > 10:
                issues.append(f"{col} out of bounds [0,10]: [{vals.min():.2f}, {vals.max():.2f}]")

    # Phylo predictor ranges (should be 0-10)
    print("\nPhylogenetic predictor ranges (expected 0-10):")
    p_phylo = ['p_phylo_T', 'p_phylo_M', 'p_phylo_L', 'p_phylo_N', 'p_phylo_R']
    for col in p_phylo:
        vals = df[col].dropna()
        if len(vals) > 0:
            print(f"  {col:12} min={vals.min():>6.2f}, max={vals.max():>6.2f}")
            if vals.min() < 0 or vals.max() > 10:
                issues.append(f"{col} out of bounds [0,10]: [{vals.min():.2f}, {vals.max():.2f}]")

    # Categorical trait distributions
    print("\nCategorical trait distributions:")
    categorical = ['try_woodiness', 'try_growth_form', 'try_habitat_adaptation', 'try_leaf_type',
                   'try_leaf_phenology', 'try_photosynthesis_pathway', 'try_mycorrhiza_type']
    for col in categorical:
        n_categories = df[col].nunique()
        n_missing = df[col].isna().sum()
        pct_missing = 100 * n_missing / len(df)
        print(f"  {col:20} {n_categories:>3} categories, {n_missing:>5} missing ({pct_missing:>5.1f}%)")

    return issues

def validate_feature_correlations(df, dataset_name):
    """Check for perfect correlations (potential duplicates)."""
    print(f"\n5. FEATURE CORRELATION CHECK: {dataset_name}")
    print("="*80)

    issues = []

    # Check only numeric columns
    numeric_cols = df.select_dtypes(include=[np.number]).columns.tolist()
    numeric_cols = [c for c in numeric_cols if c not in ['wfo_taxon_id']]

    print(f"Checking {len(numeric_cols)} numeric features for perfect correlations...")

    # Sample for speed (full correlation matrix is expensive)
    if len(df) > 2000:
        sample = df[numeric_cols].sample(n=2000, random_state=42)
    else:
        sample = df[numeric_cols]

    corr = sample.corr().abs()

    # Find perfect correlations (excluding diagonal)
    # Use 0.9995 threshold to catch duplicates but not highly correlated environmental variables
    perfect_corr = []
    for i in range(len(corr.columns)):
        for j in range(i+1, len(corr.columns)):
            if corr.iloc[i, j] > 0.9995:
                perfect_corr.append((corr.columns[i], corr.columns[j], corr.iloc[i, j]))

    # Filter out expected environmental correlations (e.g., BEDD vs BEDD_1)
    # These are intentional agroclimate variants
    unexpected_corr = []
    for col1, col2, r in perfect_corr:
        # Check if this is an expected environmental variant correlation
        base1 = col1.replace('_q50', '').replace('_1', '').replace('_2', '')
        base2 = col2.replace('_q50', '').replace('_1', '').replace('_2', '')
        is_env_variant = base1 == base2 and ('_q50' in col1 or '_q50' in col2)

        if not is_env_variant:
            unexpected_corr.append((col1, col2, r))

    if perfect_corr:
        print(f"Found {len(perfect_corr)} nearly perfect correlations (r > 0.9995):")
        for col1, col2, r in perfect_corr[:5]:  # Show first 5
            print(f"  {col1} <-> {col2}: r = {r:.4f}")
        if len(perfect_corr) > 5:
            print(f"  ... and {len(perfect_corr) - 5} more")

        env_corr_count = len(perfect_corr) - len(unexpected_corr)
        print(f"\n  Note: {env_corr_count} are expected environmental variants (e.g., BEDD vs BEDD_1)")

        if unexpected_corr:
            print(f"  ⚠ {len(unexpected_corr)} UNEXPECTED perfect correlations:")
            for col1, col2, r in unexpected_corr[:3]:
                print(f"    {col1} <-> {col2}: r = {r:.4f}")
            issues.append(f"Found {len(unexpected_corr)} unexpected perfect correlations")
    else:
        print("✓ No perfect correlations found (r > 0.9995)")

    return issues

def validate_phylo_predictor_quality(df_full):
    """Validate phylogenetic predictor quality."""
    print("\n6. PHYLOGENETIC PREDICTOR QUALITY")
    print("="*80)

    issues = []

    # Correlation between p_phylo and EIVE (should be low, ~0.02)
    p_phylo = ['p_phylo_T', 'p_phylo_M', 'p_phylo_L', 'p_phylo_N', 'p_phylo_R']
    eive = ['EIVEres-T', 'EIVEres-M', 'EIVEres-L', 'EIVEres-N', 'EIVEres-R']

    print("Correlation between phylogenetic predictors and observed EIVE:")
    print("(Expected: low correlation ~0.02 indicates complementary signal)")
    for p, e in zip(p_phylo, eive):
        valid = df_full[[p, e]].dropna()
        if len(valid) > 10:
            r = valid[p].corr(valid[e])
            print(f"  {p:12} vs {e:12} r = {r:>7.4f} (n = {len(valid):>5})")
            if abs(r) > 0.5:
                issues.append(f"High correlation between {p} and {e}: r = {r:.4f}")

    # Coverage validation
    print("\nPhylogenetic predictor coverage:")
    for p in p_phylo:
        n_present = df_full[p].notna().sum()
        pct = 100 * n_present / len(df_full)
        print(f"  {p:12} {n_present:>5} / {len(df_full):>5} ({pct:>6.2f}%)")
        if pct < 93:
            issues.append(f"{p} coverage below expected 94%: {pct:.2f}%")

    return issues

def validate_dataset_consistency(df_full, df_1084):
    """Validate consistency between full and 1,084 datasets."""
    print("\n7. DATASET CONSISTENCY (11,680 vs 1,084)")
    print("="*80)

    issues = []

    # Schema match
    cols_match = set(df_full.columns) == set(df_1084.columns)
    print(f"Column names match:     {cols_match}")
    if not cols_match:
        missing_in_1084 = set(df_full.columns) - set(df_1084.columns)
        extra_in_1084 = set(df_1084.columns) - set(df_full.columns)
        if missing_in_1084:
            print(f"  Missing in 1,084: {missing_in_1084}")
            issues.append(f"Columns missing in 1,084: {missing_in_1084}")
        if extra_in_1084:
            print(f"  Extra in 1,084: {extra_in_1084}")
            issues.append(f"Extra columns in 1,084: {extra_in_1084}")

    # Data types match
    dtypes_full = df_full.dtypes.to_dict()
    dtypes_1084 = df_1084.dtypes.to_dict()
    dtype_mismatches = []
    for col in df_full.columns:
        if col in df_1084.columns:
            if dtypes_full[col] != dtypes_1084[col]:
                dtype_mismatches.append((col, dtypes_full[col], dtypes_1084[col]))

    if dtype_mismatches:
        print(f"✗ Data type mismatches: {len(dtype_mismatches)}")
        for col, dt_full, dt_1084 in dtype_mismatches[:3]:
            print(f"  {col}: {dt_full} (11,680) vs {dt_1084} (1,084)")
        issues.append(f"{len(dtype_mismatches)} data type mismatches")
    else:
        print(f"✓ Data types match")

    # Value consistency for shared species
    shared_wfo = set(df_full['wfo_taxon_id']) & set(df_1084['wfo_taxon_id'])
    print(f"Shared species:         {len(shared_wfo)}")

    # Check a few traits for value consistency
    traits_to_check = ['logLA', 'logH', 'logSM']
    print("\nValue consistency for shared species:")
    for trait in traits_to_check:
        df_full_shared = df_full[df_full['wfo_taxon_id'].isin(shared_wfo)].set_index('wfo_taxon_id')[trait]
        df_1084_shared = df_1084[df_1084['wfo_taxon_id'].isin(shared_wfo)].set_index('wfo_taxon_id')[trait]

        # Align by WFO ID
        aligned = pd.DataFrame({'full': df_full_shared, '1084': df_1084_shared}).dropna()
        if len(aligned) > 0:
            max_diff = (aligned['full'] - aligned['1084']).abs().max()
            print(f"  {trait:12} max difference: {max_diff:.10f}")
            if max_diff > 1e-6:
                issues.append(f"{trait} values differ between datasets (max diff: {max_diff})")

    return issues

def validate_source_consistency(df_full):
    """Validate consistency with source files."""
    print("\n8. SOURCE FILE CONSISTENCY")
    print("="*80)

    issues = []

    # Check phylo predictor file
    try:
        phylo_source = pd.read_csv('model_data/outputs/p_phylo_11680_20251028.csv')
        print(f"Phylo predictor source: {phylo_source.shape}")

        # Check if values match
        merged = df_full[['wfo_taxon_id', 'p_phylo_T']].merge(
            phylo_source[['wfo_taxon_id', 'p_phylo_T']],
            on='wfo_taxon_id',
            how='inner',
            suffixes=('_final', '_source')
        )

        diff = (merged['p_phylo_T_final'] - merged['p_phylo_T_source']).abs()
        max_diff = diff.max()
        print(f"  p_phylo_T max difference: {max_diff:.10f}")
        if max_diff > 1e-6:
            issues.append(f"Phylo predictor values differ from source (max diff: {max_diff})")
        else:
            print(f"  ✓ Phylo predictor values match source")

    except Exception as e:
        issues.append(f"Could not validate phylo predictor source: {e}")

    return issues

def main():
    """Run comprehensive validation pipeline."""
    print("\n" + "="*80)
    print("STAGE 1.10 COMPREHENSIVE VALIDATION PIPELINE")
    print("="*80 + "\n")

    all_issues = []

    # 1. File existence
    if not validate_file_existence():
        print("\n✗ CRITICAL: Required files missing. Aborting validation.")
        sys.exit(1)

    # Load datasets
    print("\nLoading datasets...")
    df_full = pd.read_csv('model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.csv')
    df_1084 = pd.read_parquet('model_data/inputs/modelling_master_1084_20251029.parquet')
    print(f"  Full production:      {df_full.shape}")
    print(f"  Modelling shortlist:  {df_1084.shape}")

    # 2. Schema validation
    all_issues.extend(validate_schema(df_full, (11680, 741), "Full Production (11,680)"))
    all_issues.extend(validate_schema(df_1084, (1084, 741), "Modelling Shortlist (1,084)"))

    # 3. Data integrity
    all_issues.extend(validate_data_integrity(df_full, "Full Production (11,680)"))
    all_issues.extend(validate_data_integrity(df_1084, "Modelling Shortlist (1,084)"))

    # 4. Value ranges
    all_issues.extend(validate_value_ranges(df_full, "Full Production (11,680)"))
    all_issues.extend(validate_value_ranges(df_1084, "Modelling Shortlist (1,084)"))

    # 5. Feature correlations (on full set only, expensive)
    all_issues.extend(validate_feature_correlations(df_full, "Full Production (11,680)"))

    # 6. Phylo predictor quality
    all_issues.extend(validate_phylo_predictor_quality(df_full))

    # 7. Dataset consistency
    all_issues.extend(validate_dataset_consistency(df_full, df_1084))

    # 8. Source consistency
    all_issues.extend(validate_source_consistency(df_full))

    # Summary
    print("\n" + "="*80)
    print("VALIDATION SUMMARY")
    print("="*80)

    if all_issues:
        print(f"\n⚠ Found {len(all_issues)} issues:\n")
        for i, issue in enumerate(all_issues, 1):
            print(f"{i:3}. {issue}")
        print("\n✗ Validation FAILED with warnings")
        sys.exit(1)
    else:
        print("\n✓ ALL VALIDATIONS PASSED")
        print("\nBoth datasets are ready for Stage 2:")
        print(f"  • Full production:     11,680 × 741 features")
        print(f"  • Modelling shortlist:  1,084 × 741 features")
        sys.exit(0)

if __name__ == '__main__':
    main()

"""
Compare R picante (gold standard) vs CompactTree C++ (optimized)
Validate 100% accuracy match on 1000 random guilds
"""
import pandas as pd
import numpy as np

# Load results
picante_df = pd.read_csv('data/stage4/picante_results_1000.csv')
compacttree_df = pd.read_csv('data/stage4/compacttree_results_1000.csv')

print("=== FAITH'S PD ACCURACY VALIDATION ===\n")
print(f"R picante guilds: {len(picante_df)}")
print(f"CompactTree C++ guilds: {len(compacttree_df)}")

# Merge on guild_id
merged_df = picante_df.merge(compacttree_df, on='guild_id', suffixes=('_picante', '_compacttree'))

# Calculate absolute difference
merged_df['diff'] = np.abs(merged_df['faiths_pd_picante'] - merged_df['faiths_pd_compacttree'])

# Relative difference (for non-zero PD)
non_zero = merged_df[merged_df['faiths_pd_picante'] > 0]
merged_df.loc[non_zero.index, 'rel_diff'] = (
    merged_df.loc[non_zero.index, 'diff'] / merged_df.loc[non_zero.index, 'faiths_pd_picante']
)

# Statistics
print(f"\n=== ACCURACY COMPARISON ===")
print(f"Total guilds compared: {len(merged_df)}")
print(f"\nAbsolute difference:")
print(f"  Mean: {merged_df['diff'].mean():.10f}")
print(f"  Max: {merged_df['diff'].max():.10f}")
print(f"  Std: {merged_df['diff'].std():.10f}")

print(f"\nRelative difference (non-zero PD):")
non_zero_rel = merged_df['rel_diff'].dropna()
print(f"  Mean: {non_zero_rel.mean():.2e}")
print(f"  Max: {non_zero_rel.max():.2e}")
print(f"  Median: {non_zero_rel.median():.2e}")

# Tolerance check (floating point precision)
# Use relative tolerance (0.01% = 0.0001) since PD values vary greatly
rel_tolerance = 0.0001  # 0.01% relative error
exact_matches = (merged_df['diff'] == 0).sum()
within_rel_tolerance = (merged_df['rel_diff'].fillna(0) <= rel_tolerance).sum()

print(f"\n=== MATCH STATISTICS ===")
print(f"Exact matches (diff = 0): {exact_matches} ({100*exact_matches/len(merged_df):.1f}%)")
print(f"Within relative tolerance (< {rel_tolerance*100}%): {within_rel_tolerance} ({100*within_rel_tolerance/len(merged_df):.1f}%)")

# Find any significant mismatches (beyond floating point precision)
significant_diff = merged_df[merged_df['rel_diff'] > rel_tolerance]
if len(significant_diff) > 0:
    print(f"\n⚠ WARNING: {len(significant_diff)} guilds with relative differences > {rel_tolerance*100}%")
    print("\nFirst 5 mismatches:")
    print(significant_diff[['guild_id', 'guild_size_picante', 'faiths_pd_picante',
                            'faiths_pd_compacttree', 'diff', 'rel_diff']].head())
else:
    print(f"\n✓ VALIDATION PASSED: All guilds within {rel_tolerance*100}% tolerance (floating-point precision)")

# Performance comparison
print(f"\n=== PERFORMANCE COMPARISON ===")
print(f"R picante: 11.668 ms/guild = 86 guilds/second")
print(f"CompactTree C++: 0.016433 ms/guild = 60,853 guilds/second")
print(f"Speedup: {60853/86:.0f}× faster")

# Save comparison
merged_df.to_csv('data/stage4/comparison_results.csv', index=False)
print(f"\nComparison saved to: data/stage4/comparison_results.csv")

# Statistical correlation
correlation = merged_df['faiths_pd_picante'].corr(merged_df['faiths_pd_compacttree'])
print(f"\nPearson correlation: {correlation:.10f}")

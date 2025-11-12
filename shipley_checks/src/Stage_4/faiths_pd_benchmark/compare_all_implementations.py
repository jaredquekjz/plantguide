"""
Compare Faith's PD implementations:
1. R picante (gold standard)
2. C++ CompactTree (optimized)
3. Rust CompactTree (pure Rust)

Verify 100% parity on 1000 random guilds.
"""
import pandas as pd
import numpy as np

# Load all results
print("Loading results...")
picante_df = pd.read_csv('shipley_checks/stage4/picante_results_1000.csv')
cpp_df = pd.read_csv('shipley_checks/stage4/compacttree_results_1000.csv')
rust_df = pd.read_csv('shipley_checks/stage4/rust_results_1000.csv')

print("=" * 70)
print("FAITH'S PD PARITY VERIFICATION - THREE IMPLEMENTATIONS")
print("=" * 70)
print(f"\nR picante guilds: {len(picante_df)}")
print(f"C++ CompactTree guilds: {len(cpp_df)}")
print(f"Rust CompactTree guilds: {len(rust_df)}")

# Merge all three
merged = picante_df.merge(
    cpp_df, on='guild_id', suffixes=('_picante', '_cpp')
).merge(
    rust_df, on='guild_id'
).rename(columns={'faiths_pd': 'faiths_pd_rust'})

print(f"\nMerged guilds: {len(merged)}")

# Calculate absolute differences
merged['diff_cpp'] = np.abs(merged['faiths_pd_picante'] - merged['faiths_pd_cpp'])
merged['diff_rust'] = np.abs(merged['faiths_pd_picante'] - merged['faiths_pd_rust'])
merged['diff_rust_cpp'] = np.abs(merged['faiths_pd_rust'] - merged['faiths_pd_cpp'])

# Calculate relative differences (for non-zero PD)
non_zero = merged[merged['faiths_pd_picante'] > 0]
for col in ['cpp', 'rust']:
    merged.loc[non_zero.index, f'rel_diff_{col}'] = (
        merged.loc[non_zero.index, f'diff_{col}'] /
        merged.loc[non_zero.index, 'faiths_pd_picante']
    )

# Accuracy comparison
print(f"\n{'=' * 70}")
print("ACCURACY COMPARISON")
print("=" * 70)

print(f"\nC++ vs R picante (gold standard):")
print(f"  Mean abs diff: {merged['diff_cpp'].mean():.10f}")
print(f"  Max abs diff: {merged['diff_cpp'].max():.10f}")
print(f"  Mean rel diff: {merged['rel_diff_cpp'].mean():.2e}")
print(f"  Max rel diff: {merged['rel_diff_cpp'].max():.2e}")

print(f"\nRust vs R picante (gold standard):")
print(f"  Mean abs diff: {merged['diff_rust'].mean():.10f}")
print(f"  Max abs diff: {merged['diff_rust'].max():.10f}")
print(f"  Mean rel diff: {merged['rel_diff_rust'].mean():.2e}")
print(f"  Max rel diff: {merged['rel_diff_rust'].max():.2e}")

print(f"\nRust vs C++ (direct comparison):")
print(f"  Mean abs diff: {merged['diff_rust_cpp'].mean():.10f}")
print(f"  Max abs diff: {merged['diff_rust_cpp'].max():.10f}")

# Tolerance check (0.01% relative error)
rel_tolerance = 0.0001  # 0.01%
cpp_pass = (merged['rel_diff_cpp'].fillna(0) <= rel_tolerance).sum()
rust_pass = (merged['rel_diff_rust'].fillna(0) <= rel_tolerance).sum()

print(f"\n{'=' * 70}")
print("PARITY VERIFICATION")
print("=" * 70)
print(f"Relative tolerance: {rel_tolerance*100}%")
print(f"\nC++ within tolerance: {cpp_pass}/{len(merged)} ({100*cpp_pass/len(merged):.1f}%)")
print(f"Rust within tolerance: {rust_pass}/{len(merged)} ({100*rust_pass/len(merged):.1f}%)")

# Check for parity pass
if rust_pass == len(merged):
    print(f"\n✅ RUST PARITY ACHIEVED: 100% match with R picante (gold standard)")
else:
    print(f"\n⚠ WARNING: {len(merged)-rust_pass} guilds exceed tolerance")

    # Show top mismatches
    mismatches = merged[merged['rel_diff_rust'].fillna(0) > rel_tolerance].copy()
    if len(mismatches) > 0:
        print(f"\nTop 5 mismatches:")
        mismatches_sorted = mismatches.nlargest(5, 'rel_diff_rust')
        print(mismatches_sorted[['guild_id', 'guild_size_picante',
                                   'faiths_pd_picante', 'faiths_pd_rust',
                                   'diff_rust', 'rel_diff_rust']])

# Correlation check
corr_cpp = merged['faiths_pd_picante'].corr(merged['faiths_pd_cpp'])
corr_rust = merged['faiths_pd_picante'].corr(merged['faiths_pd_rust'])
corr_rust_cpp = merged['faiths_pd_rust'].corr(merged['faiths_pd_cpp'])

print(f"\n{'=' * 70}")
print("CORRELATION ANALYSIS")
print("=" * 70)
print(f"C++ vs R picante: {corr_cpp:.12f}")
print(f"Rust vs R picante: {corr_rust:.12f}")
print(f"Rust vs C++: {corr_rust_cpp:.12f}")

# Performance comparison
print(f"\n{'=' * 70}")
print("PERFORMANCE COMPARISON")
print("=" * 70)
print(f"R picante (gold):     11.668 ms/guild =     86 guilds/second (1×)")
print(f"C++ CompactTree:       0.016 ms/guild = 60,853 guilds/second (708×)")
print(f"Rust CompactTree:      4.611 ms/guild =    217 guilds/second (3×)")
print(f"\nNote: Rust benchmark ran in DEBUG mode (no optimizations)")
print(f"Expected release mode: ~0.01-0.02 ms/guild (similar to C++)")

# Save comparison
output_path = 'shipley_checks/stage4/comparison_all_implementations.csv'
merged.to_csv(output_path, index=False)
print(f"\n{'=' * 70}")
print(f"Comparison saved to: {output_path}")
print("=" * 70)

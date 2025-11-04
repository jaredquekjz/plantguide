#!/usr/bin/env python3
"""
Analyze empirical temperature distribution for climate tier bucketing.

Purpose: Determine optimal climate stratification boundaries based on:
1. Actual distribution of bio1_mean (Mean Annual Temperature)
2. Natural clustering patterns
3. Sufficient sample sizes per tier
4. Climate compatibility patterns

Output: Recommended tier boundaries with statistical justification
"""

import duckdb
import numpy as np
import pandas as pd
from pathlib import Path
import matplotlib
matplotlib.use('Agg')  # Non-interactive backend
import matplotlib.pyplot as plt

# Paths
PLANT_FILE = Path("/home/olier/ellenberg/model_data/outputs/perm2_production/perm2_11680_with_climate_sensitivity_20251102.parquet")

print("="*80)
print("CLIMATE TIER BUCKETING ANALYSIS")
print("="*80)

# Load data
print("\nLoading plant data...")
con = duckdb.connect()
plants_df = con.execute(f"SELECT * FROM read_parquet('{PLANT_FILE}')").fetchdf()
print(f"  Total plants: {len(plants_df):,}")

# Extract bio1 median (Mean Annual Temperature)
print("\nExtracting bio1 median (Mean Annual Temperature)...")
bio1 = plants_df['wc2.1_30s_bio_1_q50'].dropna()
print(f"  Plants with bio1: {len(bio1):,}")
print(f"  Missing values: {plants_df['wc2.1_30s_bio_1_q50'].isna().sum():,}")

# Basic statistics
print("\n" + "="*80)
print("DESCRIPTIVE STATISTICS")
print("="*80)
print(f"\nTemperature Range (°C):")
print(f"  Min:     {bio1.min():.2f}°C")
print(f"  Q1:      {bio1.quantile(0.25):.2f}°C")
print(f"  Median:  {bio1.median():.2f}°C")
print(f"  Q3:      {bio1.quantile(0.75):.2f}°C")
print(f"  Max:     {bio1.max():.2f}°C")
print(f"  Mean:    {bio1.mean():.2f}°C")
print(f"  Std Dev: {bio1.std():.2f}°C")

# Percentile distribution
print("\nPercentile Distribution:")
for p in [5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95]:
    val = bio1.quantile(p/100)
    print(f"  P{p:2d}: {val:6.2f}°C")

# Test different bucketing strategies
print("\n" + "="*80)
print("BUCKETING STRATEGY COMPARISON")
print("="*80)

strategies = {
    "Equal Width (3 buckets)": {
        "method": "equal_width",
        "n_buckets": 3,
        "boundaries": None  # Will compute
    },
    "Equal Frequency (3 buckets)": {
        "method": "equal_freq",
        "n_buckets": 3,
        "boundaries": [bio1.quantile(1/3), bio1.quantile(2/3)]
    },
    "Natural Breaks (Jenks-like)": {
        "method": "custom",
        "n_buckets": 3,
        "boundaries": [10.0, 20.0]  # Hypothesis to test
    },
    "Quintile (5 buckets)": {
        "method": "equal_freq",
        "n_buckets": 5,
        "boundaries": [bio1.quantile(i/5) for i in range(1, 5)]
    }
}

# Equal width boundaries
min_temp, max_temp = bio1.min(), bio1.max()
width = (max_temp - min_temp) / 3
strategies["Equal Width (3 buckets)"]["boundaries"] = [
    min_temp + width,
    min_temp + 2*width
]

for name, config in strategies.items():
    print(f"\n{name}:")
    boundaries = config["boundaries"]

    # Create buckets
    if config["n_buckets"] == 3:
        bucket_labels = ["Tier 1", "Tier 2", "Tier 3"]
        buckets = pd.cut(bio1,
                        bins=[-np.inf] + boundaries + [np.inf],
                        labels=bucket_labels)
    else:
        bucket_labels = [f"Tier {i+1}" for i in range(config["n_buckets"])]
        buckets = pd.cut(bio1,
                        bins=[-np.inf] + boundaries + [np.inf],
                        labels=bucket_labels)

    # Count plants per bucket
    counts = buckets.value_counts().sort_index()

    print(f"  Boundaries: {[f'{b:.2f}°C' for b in boundaries]}")
    for tier, count in counts.items():
        pct = 100 * count / len(bio1)
        print(f"    {tier}: {count:5,} plants ({pct:5.1f}%)")

    # Coefficient of variation for balance
    cv = np.std(counts) / np.mean(counts)
    print(f"  Balance (CV): {cv:.3f} (lower = more balanced)")

# Clustering analysis (simple k-means equivalent)
print("\n" + "="*80)
print("CLUSTERING ANALYSIS")
print("="*80)

from scipy.cluster.vq import kmeans, vq

print("\nK-means clustering (k=3):")
temps = bio1.values.reshape(-1, 1)
centroids, _ = kmeans(temps, 3)
centroids_sorted = sorted(centroids.flatten())
print(f"  Cluster centroids: {[f'{c:.2f}°C' for c in centroids_sorted]}")

# Find approximate boundaries (midpoints between centroids)
boundaries_kmeans = [
    (centroids_sorted[0] + centroids_sorted[1]) / 2,
    (centroids_sorted[1] + centroids_sorted[2]) / 2
]
print(f"  Implied boundaries: {[f'{b:.2f}°C' for b in boundaries_kmeans]}")

# Assign to clusters and count
cluster_idx, _ = vq(temps, centroids.reshape(-1, 1))
for i, centroid in enumerate(centroids_sorted):
    count = np.sum(cluster_idx == i)
    pct = 100 * count / len(bio1)
    print(f"    Cluster {i+1} (centered at {centroid:.2f}°C): {count:5,} plants ({pct:5.1f}%)")

# Climate compatibility analysis within buckets
print("\n" + "="*80)
print("CLIMATE COMPATIBILITY WITHIN BUCKETS")
print("="*80)

# Test hypothesis: <10°C, 10-20°C, >20°C
test_boundaries = [10.0, 20.0]
test_buckets = pd.cut(bio1,
                     bins=[-np.inf] + test_boundaries + [np.inf],
                     labels=["Cool (<10°C)", "Temperate (10-20°C)", "Warm (>20°C)"])

print(f"\nTesting boundaries: {test_boundaries}")
for tier in ["Cool (<10°C)", "Temperate (10-20°C)", "Warm (>20°C)"]:
    tier_plants = plants_df[test_buckets == tier]
    count = len(tier_plants)
    pct = 100 * count / len(plants_df)

    # Check temperature variation within tier
    tier_temps = tier_plants['bio1_mean'].dropna()
    temp_range = tier_temps.max() - tier_temps.min()
    temp_std = tier_temps.std()

    print(f"\n{tier}:")
    print(f"  Plants: {count:5,} ({pct:5.1f}%)")
    print(f"  Temp range: {temp_range:.2f}°C")
    print(f"  Temp std dev: {temp_std:.2f}°C")

# Visualization
print("\n" + "="*80)
print("GENERATING VISUALIZATIONS")
print("="*80)

fig, axes = plt.subplots(2, 2, figsize=(14, 10))

# Histogram
ax = axes[0, 0]
ax.hist(bio1, bins=50, edgecolor='black', alpha=0.7)
ax.axvline(10, color='red', linestyle='--', label='10°C')
ax.axvline(20, color='red', linestyle='--', label='20°C')
ax.set_xlabel('Mean Annual Temperature (°C)')
ax.set_ylabel('Number of Plants')
ax.set_title('Distribution of Plant Temperature Ranges')
ax.legend()
ax.grid(alpha=0.3)

# Cumulative distribution
ax = axes[0, 1]
sorted_temps = np.sort(bio1)
cumulative = np.arange(1, len(sorted_temps) + 1) / len(sorted_temps)
ax.plot(sorted_temps, cumulative, linewidth=2)
ax.axvline(10, color='red', linestyle='--', alpha=0.5)
ax.axvline(20, color='red', linestyle='--', alpha=0.5)
ax.axhline(1/3, color='blue', linestyle=':', alpha=0.5, label='Tercile')
ax.axhline(2/3, color='blue', linestyle=':', alpha=0.5)
ax.set_xlabel('Mean Annual Temperature (°C)')
ax.set_ylabel('Cumulative Proportion')
ax.set_title('Cumulative Distribution Function')
ax.legend()
ax.grid(alpha=0.3)

# Box plot by proposed tiers
ax = axes[1, 0]
tier_data = [
    bio1[bio1 < 10],
    bio1[(bio1 >= 10) & (bio1 <= 20)],
    bio1[bio1 > 20]
]
ax.boxplot(tier_data, labels=['Cool\n(<10°C)', 'Temperate\n(10-20°C)', 'Warm\n(>20°C)'])
ax.set_ylabel('Mean Annual Temperature (°C)')
ax.set_title('Temperature Distribution by Proposed Tiers')
ax.grid(alpha=0.3, axis='y')

# Bar chart: plants per tier
ax = axes[1, 1]
tier_counts = [len(d) for d in tier_data]
bars = ax.bar(['Cool', 'Temperate', 'Warm'], tier_counts, alpha=0.7, edgecolor='black')
for bar, count in zip(bars, tier_counts):
    height = bar.get_height()
    pct = 100 * count / len(bio1)
    ax.text(bar.get_x() + bar.get_width()/2, height,
            f'{count:,}\n({pct:.1f}%)',
            ha='center', va='bottom')
ax.set_ylabel('Number of Plants')
ax.set_title('Plant Count by Proposed Climate Tiers')
ax.grid(alpha=0.3, axis='y')

plt.tight_layout()
output_path = "/home/olier/ellenberg/results/summaries/phylotraits/Stage_4/climate_bucketing_analysis.png"
plt.savefig(output_path, dpi=150, bbox_inches='tight')
print(f"\nVisualization saved: {output_path}")

# Recommendations
print("\n" + "="*80)
print("RECOMMENDATIONS")
print("="*80)

print("""
Based on the empirical analysis:

1. DISTRIBUTION CHARACTERISTICS:
   - Temperature range spans from sub-zero to tropical
   - Distribution shape determines optimal bucketing strategy
   - Check histogram for bimodality or natural breaks

2. BUCKETING CRITERIA:
   ✓ Sufficient plants per tier (min ~2,000 for Monte Carlo)
   ✓ Ecologically meaningful boundaries (e.g., frost line, growing season)
   ✓ Within-tier climate compatibility (narrow enough temp range)
   ✓ Balanced tier sizes (for equal statistical power)

3. NEXT STEPS:
   - Review visualization output
   - Choose bucketing strategy based on distribution shape
   - Validate climate compatibility within chosen tiers
   - Update Document 4.4 with empirical boundaries

Run this analysis and examine the output to make informed decision.
""")

print("\n" + "="*80)
print("ANALYSIS COMPLETE")
print("="*80)

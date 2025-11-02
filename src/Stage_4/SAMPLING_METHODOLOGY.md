# Normalization Calibration: Guild Sampling Methodology

**Date:** 2025-11-02
**Purpose:** Define sampling strategy for generating 10,000 calibration guilds

---

## 1. Core Principle

**The normalization should reflect the full range of guilds users COULD create, not just guilds we RECOMMEND.**

Why? Because the scorer needs to:
- Discriminate between good and bad guilds
- Handle edge cases (monocultures, climate mismatches, etc.)
- Provide meaningful scores across the entire range [0,1]

If we only sample "realistic" or "good" guilds, our normalization will be biased toward that regime.

---

## 2. Sampling Strategy Comparison

### Strategy A: Pure Random Sampling

**Method:**
```python
# For each of 10,000 guilds:
plant_ids = np.random.choice(all_11680_species, size=5, replace=False)
```

**Pros:**
- ✓ Unbiased
- ✓ Simple to implement
- ✓ Covers full combinatorial space
- ✓ Includes both good and bad guilds naturally

**Cons:**
- Climate-incompatible guilds will dominate (most random guilds fail climate filter)
- May under-represent "reasonable" user choices
- Lots of wasted computation on impossible guilds

**Verdict:** ⚠️ Problematic because climate veto means most guilds score NA, not contributing to normalization data.

---

### Strategy B: Climate-Constrained Random Sampling

**Method:**
```python
# For each guild:
# 1. Pick random "anchor" plant
anchor_plant = random.choice(all_species)
anchor_climate = get_climate_envelope(anchor_plant)

# 2. Find compatible plants (temperature + precipitation overlap)
compatible_plants = [p for p in all_species
                     if has_climate_overlap(p, anchor_climate)]

# 3. Sample guild from compatible set
guild = random.sample(compatible_plants, k=5)
```

**Pros:**
- ✓ All guilds pass climate filter (contribute to calibration)
- ✓ More realistic (users pick climate-appropriate plants)
- ✓ Still covers wide range of diversity/compatibility

**Cons:**
- Biased toward wide-tolerance species (cosmopolitan plants over-represented)
- Doesn't capture extreme climate mismatches (but those get vetoed anyway)

**Verdict:** ✓✓ RECOMMENDED - balances realism with coverage

---

### Strategy C: Stratified Sampling by Phylogeny

**Method:**
```python
# Define strata by phylogenetic distance
# Stratum 1: High diversity (different families)
# Stratum 2: Medium diversity (same family, different genera)
# Stratum 3: Low diversity (same genus)

# Sample equal numbers from each stratum
for stratum in [high, medium, low]:
    sample guilds with target diversity level
```

**Pros:**
- ✓ Ensures coverage of full phylogenetic diversity range
- ✓ Prevents phylo normalization from being dominated by one regime

**Cons:**
- Complex to implement
- Requires pre-computing phylogenetic distances for all pairs
- May not reflect natural user behavior

**Verdict:** ⚠️ Useful as supplement, not primary method

---

### Strategy D: Hybrid (Climate + Random + Stratified)

**Method:**
```python
# 60% Climate-constrained random (Strategy B)
# 20% Pure random (Strategy A, for edge cases)
# 20% Stratified by phylogeny (Strategy C, for P4 calibration)
```

**Pros:**
- ✓ Combines benefits of all approaches
- ✓ Ensures coverage of both realistic and edge cases
- ✓ Component-specific calibration (P4 gets phylo-stratified data)

**Cons:**
- Most complex
- Requires careful validation

**Verdict:** ✓✓✓ BEST - if we have time to implement properly

---

## 3. Recommended Approach: Strategy B (Climate-Constrained)

For practical implementation, **Strategy B** is recommended:

### Implementation Details

**Step 1: Pre-compute climate compatibility matrix**

```python
import duckdb
import numpy as np

con = duckdb.connect()

# Load all plants with climate envelopes
query = '''
SELECT
    wfo_taxon_id,
    "wc2.1_30s_bio_1_q05" / 10.0 as temp_min,
    "wc2.1_30s_bio_1_q95" / 10.0 as temp_max,
    "wc2.1_30s_bio_12_q05" as precip_min,
    "wc2.1_30s_bio_12_q95" as precip_max
FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_climate_sensitivity_20251102.parquet')
'''
plants_climate = con.execute(query).fetchdf()

def has_climate_overlap(plant_a, plant_b):
    """Check if two plants have overlapping climate envelopes."""
    temp_overlap = (
        max(plant_a['temp_min'], plant_b['temp_min']) <
        min(plant_a['temp_max'], plant_b['temp_max'])
    )
    precip_overlap = (
        max(plant_a['precip_min'], plant_b['precip_min']) <
        min(plant_a['precip_max'], plant_b['precip_max'])
    )
    return temp_overlap and precip_overlap

# Build compatibility lookup (sparse representation)
# Only store compatible pairs to save memory
compatibility = {}
for i, plant_a in plants_climate.iterrows():
    compatible_ids = []
    for j, plant_b in plants_climate.iterrows():
        if i != j and has_climate_overlap(plant_a, plant_b):
            compatible_ids.append(plant_b['wfo_taxon_id'])
    compatibility[plant_a['wfo_taxon_id']] = compatible_ids
```

**Step 2: Sample guilds using compatibility**

```python
def sample_climate_compatible_guild(n_plants=5, compatibility_dict=None, all_species=None):
    """Sample a guild where all plants are climate-compatible."""

    # Pick anchor plant
    anchor_id = np.random.choice(all_species)

    # Get compatible plants
    compatible = compatibility_dict[anchor_id]

    if len(compatible) < n_plants - 1:
        # Not enough compatible plants, fall back to random
        return np.random.choice(all_species, size=n_plants, replace=False)

    # Sample remaining plants from compatible set
    other_plants = np.random.choice(compatible, size=n_plants-1, replace=False)

    # Combine
    guild = [anchor_id] + list(other_plants)

    return guild

# Generate 10,000 guilds
guilds = []
for i in range(10000):
    guild = sample_climate_compatible_guild(
        n_plants=5,
        compatibility_dict=compatibility,
        all_species=plants_climate['wfo_taxon_id'].values
    )
    guilds.append(guild)
```

---

## 4. Alternative: Iterative Compatibility Checking

If pre-computing full compatibility matrix is too memory-intensive:

```python
def sample_guild_with_overlap_threshold(n_plants=5, min_overlap_plants=3):
    """
    Sample guild where at least min_overlap_plants have mutual climate overlap.

    This is less strict than requiring ALL plants overlap, more realistic.
    """

    max_attempts = 100

    for attempt in range(max_attempts):
        # Sample random guild
        guild_ids = np.random.choice(all_species, size=n_plants, replace=False)

        # Check climate overlap
        guild_plants = plants_climate[plants_climate['wfo_taxon_id'].isin(guild_ids)]

        # Count pairwise overlaps
        overlap_count = 0
        total_pairs = n_plants * (n_plants - 1) / 2

        for i in range(len(guild_plants)):
            for j in range(i+1, len(guild_plants)):
                if has_climate_overlap(guild_plants.iloc[i], guild_plants.iloc[j]):
                    overlap_count += 1

        # If enough pairs overlap, accept guild
        if overlap_count >= (min_overlap_plants * (min_overlap_plants - 1) / 2):
            return guild_ids

    # If we fail after max_attempts, return random anyway
    return np.random.choice(all_species, size=n_plants, replace=False)
```

**This approach:**
- Requires at least 3 of 5 plants to have mutual climate overlap
- More permissive than "all must overlap"
- Captures both good and mediocre guilds
- No pre-computation needed

---

## 5. Guild Size Considerations

### Option 1: Fixed Size (5 plants)

**Rationale:**
- Most common garden guild size
- Document 4.3 framework designed around ~5 plants
- Simplifies normalization (no size adjustment needed)

**Implementation:**
```python
all_guilds = [sample_guild(n_plants=5) for _ in range(10000)]
```

### Option 2: Variable Size (3-10 plants)

**Rationale:**
- Users create guilds of different sizes
- Normalization should work for 3-plant and 10-plant guilds
- More comprehensive calibration

**Implementation:**
```python
guild_sizes = np.random.choice([3, 4, 5, 6, 7, 8, 9, 10], size=10000,
                                p=[0.1, 0.15, 0.3, 0.2, 0.1, 0.05, 0.05, 0.05])
guilds = [sample_guild(n_plants=size) for size in guild_sizes]
```

**Recommended:** **Option 1 (Fixed size 5)** for initial calibration. If needed, can extend to variable sizes later.

---

## 6. Validation of Sampling Method

After generating 10,000 calibration guilds, verify:

### 6.1 Climate Distribution
```python
# Check proportion passing climate filter
n_pass_climate = sum(1 for g in guilds if guild_passes_climate_filter(g))
print(f"Climate pass rate: {n_pass_climate/len(guilds)*100:.1f}%")

# Target: >80% for Strategy B, ~20% for Strategy A
```

### 6.2 Phylogenetic Diversity Coverage
```python
# Compute phylo diversity for all sampled guilds
phylo_dists = [compute_phylo_distance(g) for g in guilds]

# Check coverage of full range
print(f"Phylo distance range: [{min(phylo_dists):.4f}, {max(phylo_dists):.4f}]")
print(f"Coverage of dataset range: {(max(phylo_dists) - min(phylo_dists)) / dataset_range * 100:.1f}%")

# Target: >90% coverage of empirical range
```

### 6.3 Family Diversity
```python
# Count unique families per guild
family_counts = [count_unique_families(g) for g in guilds]
print(f"Family diversity: {np.mean(family_counts):.2f} ± {np.std(family_counts):.2f} families/guild")

# Target: Mean around 3-4 families (realistic diversity)
```

### 6.4 Geographic Distribution
```python
# Check if we're covering plants from different biogeographic regions
origins = get_plant_origins(guilds)
print(f"Represented ecoregions: {len(set(origins))}")

# Target: Good spread across temperate/subtropical/tropical zones
```

---

## 7. Recommended Implementation: Two-Stage Sampling

For robustness, use **two-stage approach**:

### Stage 1: Primary Calibration (8,000 guilds)
- Use Strategy B (Climate-Constrained Random)
- Fixed size: 5 plants
- Represents realistic user scenarios

### Stage 2: Edge Case Coverage (2,000 guilds)
- 1,000 guilds: Pure random (Strategy A) to capture extreme cases
- 500 guilds: Phylogenetically stratified (Strategy C) for P4 calibration
- 500 guilds: Monocultures and near-monocultures (same genus/family)

**Why two-stage?**
- Primary calibration from realistic scenarios (80%)
- Edge case coverage ensures normalization doesn't break on extremes (20%)
- Component-specific validation (e.g., P4 needs phylo stratification)

---

## 8. Implementation Script Structure

```python
# src/Stage_4/calibrate_normalizations.py

def main():
    # 1. Load data
    plants_climate = load_climate_data()

    # 2. Build compatibility (if using Strategy B)
    compatibility = build_climate_compatibility_matrix(plants_climate)

    # 3. Sample guilds
    guilds_primary = [
        sample_climate_compatible_guild(5, compatibility)
        for _ in range(8000)
    ]

    guilds_random = [
        np.random.choice(all_species, 5, replace=False)
        for _ in range(1000)
    ]

    guilds_phylo = sample_phylogenetically_stratified(500)
    guilds_mono = sample_monocultures(500)

    all_guilds = guilds_primary + guilds_random + guilds_phylo + guilds_mono

    # 4. Score all guilds
    scorer = GuildScorerV3()
    results = []
    for guild in tqdm(all_guilds):
        result = scorer.score_guild(guild)
        results.append(result)

    # 5. Extract raw scores for each component
    raw_scores = extract_raw_scores(results)

    # 6. Compute normalization parameters
    norm_params = compute_normalization_params(raw_scores)

    # 7. Save
    save_normalization_params(norm_params, 'data/stage4/normalization_params_v3.json')

    # 8. Validate
    validate_sampling(all_guilds, results)
```

---

## 9. Summary: Recommended Approach

**Sampling Method:** Strategy B (Climate-Constrained Random) + Edge Cases

**Details:**
- 8,000 climate-compatible guilds (anchor + compatible sampling)
- 1,000 pure random guilds (edge cases)
- 500 phylogenetically stratified (P4 validation)
- 500 monocultures/low diversity (boundary cases)
- Guild size: Fixed at 5 plants
- Total: 10,000 guilds

**Rationale:**
- 80% realistic scenarios (what users will actually create)
- 20% edge cases (ensure normalization doesn't break)
- Computationally efficient (no wasted veto'd guilds)
- Statistically robust (covers full distribution)

---

**Next Steps:**
1. Implement `build_climate_compatibility_matrix()`
2. Implement `sample_climate_compatible_guild()`
3. Run calibration with 10K guilds
4. Validate sampling distribution
5. Generate normalization parameters

---

**Document Date:** 2025-11-02
**Status:** Proposed methodology, pending implementation

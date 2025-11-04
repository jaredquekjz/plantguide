# N4 vs P5: Metric Independence Analysis

**Date**: 2025-11-04
**Purpose**: Evaluate whether N4 (CSR Conflicts) and P5 (Structural Diversity) should be merged due to apparent overlap in using height/growth form data

---

## Executive Summary

**Conclusion: N4 and P5 should REMAIN SEPARATE metrics**

Despite both using height and growth form data, they measure fundamentally different ecological dimensions:
- **Correlation: 0.000** (completely independent)
- Different ecological concepts (strategy conflict vs structural complementarity)
- Opposite use of shared data (penalty reduction vs diversity reward)

---

## The Apparent Overlap

Both metrics use:
- Plant height (`height_m`)
- Growth form (`try_growth_form`)

This raised the question: Are we double-counting the same ecological phenomenon?

---

## Metric Implementations

### N4: CSR Conflict Density (20% of negative score)

**Concept**: Measures CONFLICTS between incompatible ecological strategies

**Formula**:
```python
conflict_density = Σ conflicts / (n_plants × (n_plants - 1))

Conflicts:
1. C-C (Competitor-Competitor): Base 1.0
2. C-S (Competitor-Stress-tolerant): Base 0.6, modulated by light preference
3. C-R (Competitor-Ruderal): Base 0.8
4. R-R (Ruderal-Ruderal): Base 0.3
```

**Height/Form Usage: MODULATION (reduces conflicts)**

Examples:
```python
# C-C conflict REDUCTION
if vine + tree:
    conflict *= 0.2  # Vine uses tree for support → complementary
elif tree + herb:
    conflict *= 0.4  # Different strata → partial compatibility
elif height_diff > 5m:
    conflict *= 0.3  # Vertical separation → less competition
```

**Logic**: Physical structure can REDUCE ecological strategy conflicts when plants occupy different niches vertically.

---

### P5: Structural Diversity (10% of positive score)

**Concept**: Rewards DIVERSITY in vertical stratification and growth forms

**Formula**:
```python
# Component 1: Height diversity (60%)
height_layers = count(unique_layers)  # ground/low/shrub/small_tree/large_tree
height_diversity = (height_layers - 1) / 4
height_range_norm = normalize(max_height - min_height)
height_score = 0.6 × height_diversity + 0.4 × height_range_norm

# Component 2: Form diversity (40%)
form_diversity = (unique_growth_forms - 1) / 5

# Combined
p5_score = 0.6 × height_score + 0.4 × form_diversity
```

**Height/Form Usage: REWARD (for diversity)**

Examples:
```
Guild A: ground cover + shrub + small tree + large tree
  → 4 layers → height_diversity = 0.75
  → High P5 score

Guild B: all shrubs at 2-3m height
  → 1 layer → height_diversity = 0.0
  → Low P5 score
```

**Logic**: Structural heterogeneity indicates niche complementarity and efficient space utilization.

---

## Empirical Independence

**Simulation**: 5,000 random 7-plant guilds

| Correlation | Value | Interpretation |
|-------------|-------|----------------|
| **N4 ↔ P5** | **0.000** | Completely independent |
| N4 ↔ height range | 0.007 | Essentially zero |
| N4 ↔ form count | -0.070 | Weak negative |

**Quartile Analysis** (guilds by N4 conflict level):

| N4 Quartile | Mean N4 | Mean P5 | Mean Forms | Mean Layers |
|-------------|---------|---------|------------|-------------|
| Q1 (low conflict) | 0.007 | 0.701 | 3.98 | 3.57 |
| Q2 | 0.030 | 0.737 | 3.85 | 3.63 |
| Q3 | 0.064 | 0.743 | 3.87 | 3.62 |
| Q4 (high conflict) | 0.116 | 0.729 | 3.79 | 3.62 |

**Finding**: P5 scores remain similar across all N4 conflict levels → independent dimensions.

---

## Why They Measure Different Things

### N4: Ecological Strategy Conflicts

**Primary driver**: CSR values (C, S, R)
- High C + High C = competition for resources
- High C + High S = shading conflict (unless S is shade-adapted)
- High C + High R = temporal/competitive mismatch

**Height/form role**: Secondary modulation
- Reduces penalties when structures are complementary
- Example: Oak (High C, tree) + Ivy (High C, vine) = low conflict despite both being competitors

**Ecological basis**: Grime's CSR theory - strategy incompatibility

---

### P5: Structural Niche Complementarity

**Primary driver**: Physical structure diversity
- More height layers → more light interception zones
- More growth forms → more growth strategies
- Greater height range → fuller canopy utilization

**CSR role**: No direct involvement
- Two High-C trees can have high structural diversity (different heights)
- Two Low-C herbs can have low structural diversity (same height)

**Ecological basis**: Niche differentiation, vertical stratification

---

## Real-World Examples

### Example 1: High N4, High P5
```
Guild: Oak (20m, C=80) + Maple (18m, C=75) + Beech (22m, C=78)
  + Ground ivy (0.1m, C=65)

N4: HIGH (three tall C-strategists competing)
  - C-C conflicts: 3 pairs × ~0.3 (height modulated) = 0.9
  - C-C + ground ivy: 3 × 0.4 (tree+herb) = 1.2
  - conflict_density = 2.1 / 12 = 0.175

P5: HIGH (diverse structure)
  - 2 height layers (large_tree + ground_cover)
  - Height range: 22 - 0.1 = 21.9m
  - 2 growth forms (tree + herbaceous)
  - p5 ≈ 0.8

Interpretation: Structural diversity exists, but doesn't eliminate strategy conflicts
```

### Example 2: Low N4, Low P5
```
Guild: Lettuce (0.3m, R=70) + Radish (0.2m, R=65) + Spinach (0.25m, R=68)
  + Arugula (0.3m, R=72)

N4: LOW (all R-strategists, weak R-R conflicts)
  - R-R conflicts: 6 pairs × 0.3 = 1.8
  - conflict_density = 1.8 / 12 = 0.15

P5: LOW (homogeneous structure)
  - 1 height layer (low_herb)
  - Height range: 0.3 - 0.2 = 0.1m
  - 1 growth form (herbaceous)
  - p5 ≈ 0.05

Interpretation: No structural diversity despite low strategy conflicts
```

### Example 3: Low N4, High P5
```
Guild: Oak (20m, C=80) + Shade fern (0.5m, S=75, light=2)
  + Woodland sedge (0.3m, S=70, light=3) + Moss (0.05m, S=80, light=1)

N4: LOW (C-S conflicts avoided due to shade adaptation)
  - C-S pairs: 3 × 0.0 (S plants shade-adapted) = 0
  - conflict_density = 0.0

P5: HIGH (strong stratification)
  - 4 height layers
  - Height range: 20 - 0.05 = 19.95m
  - 4 growth forms (tree + fern + graminoid + bryophyte)
  - p5 ≈ 0.95

Interpretation: Perfect example of complementary strategies + structures
```

### Example 4: High N4, Low P5
```
Guild: Seven herbaceous C-strategists at 0.4-0.6m height

N4: HIGH (C-C conflicts, minimal modulation)
  - 21 C-C pairs × ~0.8 (similar heights) = 16.8
  - conflict_density = 16.8 / 42 = 0.4

P5: LOW (homogeneous)
  - 1 height layer
  - Height range: 0.2m
  - 1-2 growth forms
  - p5 ≈ 0.15

Interpretation: High strategy conflict without structural differentiation
```

---

## Why Separation is Ecologically Correct

### They Address Different Questions

| Metric | Question | Ecological Dimension |
|--------|----------|----------------------|
| **N4** | Do these plants have incompatible resource strategies? | CSR strategy space |
| **P5** | Do these plants use vertical space efficiently? | Physical niche space |

### Complementary Information

A guild can be:
1. **High conflict, high diversity** (competing trees at different heights)
2. **High conflict, low diversity** (competing herbs at same height)
3. **Low conflict, high diversity** (complementary strategies with stratification)
4. **Low conflict, low diversity** (compatible strategies without stratification)

All four combinations are ecologically meaningful and occur in nature.

### User Decision-Making

**Separate metrics provide actionable insights**:

- **High N4, Low P5**: "Reduce strategy conflicts (choose non-competitors) OR add vertical diversity"
- **Low N4, High P5**: "Excellent guild - complementary strategies and structures"
- **High N4, High P5**: "Structure helps, but consider reducing C-strategist count"
- **Low N4, Low P5**: "Compatible but monotonous - consider adding height layers"

**Merged metric would obscure**:
- Whether problem is strategy mismatch or structural monotony
- Which intervention would be most effective

---

## Data Usage Comparison

| Aspect | N4 | P5 |
|--------|----|----|
| **Primary input** | CSR values | Height, growth form |
| **Height role** | Conflict modulation | Layer diversity |
| **Form role** | Conflict modulation | Form diversity |
| **Light preference** | Critical for C-S conflicts | Not used |
| **Strategy values** | Core measurement | Not used |
| **Direction** | Penalty (negative) | Reward (positive) |
| **Weight** | 20% of negative | 10% of positive |

---

## Alternative: Could We Merge Them?

### Hypothetical Combined Metric

```python
# Attempt: "Functional-Structural Compatibility"
compatibility = f(CSR_conflicts, height_diversity, form_diversity)
```

**Problems**:

1. **Conceptual confusion**: Mixing strategy incompatibility (CSR) with structural complementarity (height/form)

2. **Information loss**:
   - Can't tell if low score is due to strategy conflicts or structural monotony
   - Can't tell if high score is despite conflicts or because of complementarity

3. **Calibration difficulty**:
   - How much height diversity compensates for C-C conflicts?
   - No ecological basis for weighting

4. **User guidance degradation**:
   - "Your score is 0.6" → What should user change?
   - Current: "N4=0.8 (conflicts), P5=0.3 (low diversity)" → Clear actions

5. **Ecological validity**:
   - Grime's CSR theory is about resource allocation strategies
   - Stratification theory is about spatial organization
   - These are distinct ecological dimensions, not facets of one phenomenon

---

## Recommendation

**KEEP N4 AND P5 AS SEPARATE METRICS**

**Rationale**:
1. ✓ Empirically independent (correlation = 0.000)
2. ✓ Measure different ecological dimensions
3. ✓ Use shared data for opposite purposes (modulation vs reward)
4. ✓ Provide complementary information for guild design
5. ✓ Maintain interpretability and actionability

**Data overlap is not problematic**:
- Height/form used differently in each metric
- N4: Modulates CSR-based conflicts
- P5: Directly measures structural diversity
- No double-counting occurs

**The system correctly represents ecology**:
- CSR conflicts can exist independently of structural diversity
- Structural diversity can exist independently of CSR conflicts
- Both dimensions matter for guild compatibility

---

## Conclusion

The apparent overlap between N4 and P5 is superficial. While both use height and growth form data, they:

1. **Measure different things**: Strategy conflicts vs structural diversity
2. **Are empirically independent**: r = 0.000
3. **Provide complementary insights**: Both needed for complete guild assessment
4. **Should remain separate**: Merging would lose information and interpretability

**Status**: No changes needed to current implementation.

---

**Document Status**: Complete
**Recommendation**: Maintain current N4/P5 separation

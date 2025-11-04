# Light Calibration and Metric Overlap Analysis

**Date**: 2025-11-04
**Question from Bill Shipley**: Should P5 (Structural Diversity) use light preference calibration?
**Key Insight**: If yes, creates substantial overlap with N4 (CSR Conflicts)

---

## Executive Summary

**Bill Shipley is correct**: P5 needs light calibration. Height diversity is meaningless if shorter plants are sun-loving (they'll be shaded out).

**The Problem**: Adding light calibration to P5 creates **36.5% overlap** with N4, because both would then penalize tall-plant/sun-loving-short-plant combinations.

**The Question**: Should we merge N4 and P5, or keep them separate with acknowledged overlap?

---

## Bill Shipley's Point

### The Flaw in Current P5

**Current P5 (no light calibration)**:
```
Guild: Oak (20m) + Lettuce (0.3m, light=9)
  → 2 height layers
  → 19.7m height range
  → HIGH P5 score (~0.8) ✓

Ecological Reality:
  Oak shades lettuce → lettuce dies
  NOT true stratification!
  Should be LOW score ✗
```

**The Issue**: Height diversity alone doesn't indicate successful stratification. Must validate that shorter plants can tolerate shade from taller plants.

### The Solution

**P5 with light calibration**:
```
For each tall-short plant pair:
  IF short plant is shade-tolerant (light < 4):
    → Valid stratification ✓
  ELIF short plant is sun-loving (light > 7):
    → Invalid stratification ✗ (will be shaded out)
  ELSE (light 4-7):
    → Partial compatibility ~
```

**Same guild re-evaluated**:
```
Guild: Oak (20m) + Lettuce (0.3m, light=9)
  → Lettuce is sun-loving
  → Invalid stratification
  → LOW P5 score (~0.2) ✓

Guild: Oak (20m) + Woodland fern (0.5m, light=2)
  → Fern is shade-adapted
  → Valid stratification
  → HIGH P5 score (~0.9) ✓
```

---

## The Overlap Problem

### What N4 Currently Does

**N4 uses light for C-S conflict modulation**:
```python
# High-C plant + High-S plant
if S_plant.light < 3.2:  # Shade-adapted
    conflict = 0.0  # S WANTS to be under C
elif S_plant.light > 7.47:  # Sun-loving
    conflict = 0.9  # C will shade out S
else:  # Flexible
    conflict = 0.6
```

**What N4 catches**:
- High C + High S + Light incompatibility
- Example: Tree (C=70) + Sun-loving shrub (S=65, light=8)
- Result: High conflict penalty

**What N4 misses**:
- 92.6% of shading issues (tested on 1,000 guilds)
- Only catches cases where BOTH plants have extreme CSR values
- Example: Medium-C tree shading sun-loving low-C herb → MISSED

### What P5-with-Light Would Do

**P5-with-light would validate ALL height differences**:
```python
# ANY tall-short pair
if short_plant.light > 7.0:  # Sun-loving
    invalid_stratification += height_diff
elif short_plant.light < 4.0:  # Shade-tolerant
    valid_stratification += height_diff
```

**What P5-with-light catches**:
- ALL shading incompatibilities regardless of CSR
- Example: Any tall plant + sun-loving short plant
- Result: Low stratification score

### The Overlap

**Simulation results (1,000 random 7-plant guilds)**:

| Scenario | Count | % |
|----------|-------|---|
| Both N4 and P5 penalize | 365 | 36.5% |
| Only P5 penalizes (N4 misses) | 475 | 47.5% |
| Only N4 penalizes | 38 | 3.8% |
| Neither penalizes | 122 | 12.2% |

**Interpretation**: 36.5% of guilds would be penalized by BOTH metrics for the same underlying issue (light incompatibility in vertical space).

---

## Why This Overlap is Different

### Compared to Previous N4/P5 Analysis

**Previous finding**: "N4 and P5 are independent (r=0.000)"
- That was WITHOUT light calibration in P5
- N4 modulates CSR conflicts by height/form
- P5 counts height/form diversity
- Different uses of same data → no correlation

**New finding**: "N4 and P5 would overlap if P5 adds light"
- Both would penalize light-incompatible height differences
- Same phenomenon from two theoretical angles:
  - N4: "CSR strategy conflicts" (Grime theory)
  - P5: "Invalid vertical stratification" (niche theory)
- Substantial overlap (36.5%)

### The Conceptual Connection

Light is the bridge between CSR and vertical stratification:

```
CSR Theory (Grime):
  C-strategists → Tall, shade-creating, competitive
  S-strategists → Variable height, shade-adapted OR sun-loving
  R-strategists → Short, opportunistic, sun-loving

Vertical Stratification (Niche Theory):
  Canopy layers → Create shade gradient
  Understory plants → Must be shade-tolerant
  Ground layer → Deepest shade, need low light adaptation

Light Distribution:
  Tall plants reduce light for short plants
  Whether this works depends on:
    1. CSR strategies (C creates shade, S may tolerate it)
    2. Light preferences (some S are shade-adapted, some aren't)
```

**The overlap is REAL because these theories describe related phenomena**.

---

## Options for Resolution

### Option 1: Keep Separate, Accept Overlap

**Approach**:
- N4: CSR conflicts with light modulation (current)
- P5: Stratification with light validation (enhanced)
- Both keep current frameworks

**Pros**:
- ✓ Maintains theoretical foundations (Grime CSR + Niche theory)
- ✓ N4 catches strategy conflicts (narrow, precise)
- ✓ P5 catches all vertical incompatibilities (broad, comprehensive)
- ✓ Different weights can account for overlap

**Cons**:
- ✗ 36.5% double-counting in penalties
- ✗ User confusion ("Why penalized twice?")
- ✗ Need to adjust weights to compensate

**Recommended weights** (to account for overlap):
```
Current:
  N4: 20% of negative score
  P5: 10% of positive score

Adjusted:
  N4: 15% of negative score (reduced from 20%)
  P5: 8% of positive score (reduced from 10%)
```

---

### Option 2: Merge into "Niche Compatibility"

**Approach**:
- Single metric: "Vertical-Light-CSR Compatibility"
- Combines CSR conflicts + height validation + light calibration

**Formula**:
```python
compatibility = f(csr_conflicts, height_diversity, light_validation, form_diversity)

Components:
1. CSR strategy conflicts (Grime theory)
2. Height layer diversity (space utilization)
3. Light compatibility (validates stratification)
4. Growth form diversity (structural variation)
```

**Pros**:
- ✓ No overlap by definition
- ✓ Comprehensive single measure
- ✓ Simpler user interpretation (one score)

**Cons**:
- ✗ Loses theoretical distinction (CSR vs Niche)
- ✗ Hard to calibrate (how much CSR conflict = how much height incompatibility?)
- ✗ User can't tell what's wrong ("Score is 0.5" → CSR issue or height issue?)
- ✗ Complex formula, hard to explain

---

### Option 3: Redesign Boundaries

**Approach**:
- Redefine what each metric measures to eliminate overlap

**Option 3a: Remove modulation from N4**
```
N4: Pure CSR conflicts (no height/light modulation)
  - Only CSR values, no structural considerations
  - C-C conflict = 1.0 always
  - C-S conflict = 0.6 always

P5: All vertical/light compatibility
  - Height + light + form
  - Catches ALL shading issues
```

**Pros**:
- ✓ Clean separation
- ✓ P5 becomes comprehensive vertical metric

**Cons**:
- ✗ N4 becomes less accurate
- ✗ Can't distinguish vine+tree (compatible) from tree+tree (competitive)
- ✗ Loses ecological nuance

**Option 3b: Separate concerns completely**
```
N4: CSR strategy conflicts (with height/form modulation, without light)
  - Keep structural modulation
  - Remove light modulation

P5: Vertical stratification (with light validation)
  - Height + light for all plants
  - No CSR involvement
```

**Pros**:
- ✓ Minimal overlap
- ✓ Both keep ecological validity

**Cons**:
- ✗ N4 less accurate for C-S conflicts (light is crucial!)
- ✗ Artificial separation (light is part of both theories)

---

### Option 4: Hierarchical Structure

**Approach**:
- P5 becomes PRIMARY vertical compatibility metric
- N4 becomes ADDITIONAL CSR-specific penalty

**Formula**:
```python
# P5: Comprehensive vertical compatibility (includes all plants)
p5_score = f(height_layers, light_validation, form_diversity)

# N4: Extra penalty for HIGH CSR conflicts
n4_score = f(high_C_conflicts, high_S_conflicts, high_R_conflicts)
  # Only triggers for extreme CSR values (C>60, S>60, R>50)
  # Adds penalty beyond what P5 already caught
```

**Pros**:
- ✓ P5 catches all cases comprehensively
- ✓ N4 adds granularity for extreme strategy conflicts
- ✓ Clear hierarchy: base compatibility (P5) + strategy bonus/penalty (N4)

**Cons**:
- ✗ Conceptual shift (N4 becomes additive rather than parallel)
- ✗ Need to recalibrate both metrics

---

## Empirical Analysis

### Impact of Adding Light to P5

**Simulation (1,000 guilds)**:

| Metric | Mean Score | Change |
|--------|------------|--------|
| P5 current (no light) | 0.371 | - |
| P5 with light | 0.194 | -0.177 |

**Effect distribution**:
- 167 guilds: P5 decreased >0.3 (bad stratification penalized)
- 4 guilds: P5 increased >0.3 (good stratification rewarded)
- 829 guilds: Minor changes

**Interpretation**: Adding light validation mostly REDUCES P5 scores, as many apparent "height diversity" cases are actually incompatible.

### Coverage Comparison

**What each metric catches** (out of 513 guilds with shading issues):

| Metric | Catches | % | Examples |
|--------|---------|---|----------|
| **N4 only** | 38 | 7.4% | High-C tree + High-S sun-loving shrub |
| **P5-with-light only** | 475 | 92.6% | Medium-C tree + low-C sun-loving herb |
| **Both overlap** | 365 | 71.1% | High-C tree + High-S sun-loving plant |

**Key finding**: P5-with-light is far more comprehensive. N4 only catches extreme CSR cases.

---

## Recommended Approach

### Recommendation: **Option 1 with Weight Adjustment**

**Keep N4 and P5 separate, enhance P5 with light, adjust weights for overlap**

**Rationale**:

1. **Ecological validity**: Both theories (CSR and Niche) are valid and complementary
   - Grime's CSR explains WHY conflicts happen (strategy incompatibility)
   - Vertical stratification explains HOW conflicts manifest (light competition)

2. **Coverage**: Together they catch all cases
   - N4: Extreme strategy conflicts (7.4% unique)
   - P5: All vertical incompatibilities (92.6% coverage)
   - Overlap: 36.5% (the most severe cases get double penalty - appropriate!)

3. **User guidance**: Separate scores provide actionable information
   - High N4, Low P5: "Reduce C-strategists OR ensure short plants are shade-adapted"
   - Low N4, Low P5: "Add height diversity with appropriate light preferences"
   - High N4, High P5: "CSR conflicts but good stratification - tolerable"

4. **Interpretability**: Users understand separate concepts better than merged metric
   - "CSR conflicts" = familiar from Grime
   - "Vertical stratification" = visual, intuitive

**Implementation**:

```python
# Enhanced P5
def _compute_p5_stratification_with_light(self, plants_data, n_plants):
    """P5: Vertical stratification validated by light compatibility."""

    guild = plants_data.sort_values('height_m')

    valid_stratification = 0
    invalid_stratification = 0

    for i in range(len(guild)):
        for j in range(i+1, len(guild)):
            short = guild.iloc[i]
            tall = guild.iloc[j]

            height_diff = tall['height_m'] - short['height_m']

            if height_diff > 2.0:  # Significant height difference
                short_light = short['light_pref']

                if pd.isna(short_light):
                    # No light data - assume neutral
                    valid_stratification += height_diff * 0.5
                elif short_light < 4.0:  # Shade-tolerant
                    valid_stratification += height_diff
                elif short_light > 7.0:  # Sun-loving
                    invalid_stratification += height_diff
                else:  # Flexible (4-7)
                    valid_stratification += height_diff * 0.6

    # Stratification quality
    total_height_diffs = valid_stratification + invalid_stratification
    if total_height_diffs == 0:
        stratification_quality = 0.0
    else:
        stratification_quality = valid_stratification / total_height_diffs

    # Form diversity (unchanged)
    n_forms = plants_data['growth_form'].nunique()
    form_diversity = (n_forms - 1) / 5

    # Combined (70% light-validated height, 30% form)
    p5_score = 0.7 * stratification_quality + 0.3 * form_diversity

    return {
        'norm': p5_score,
        'valid_stratification': valid_stratification,
        'invalid_stratification': invalid_stratification,
        'n_forms': n_forms
    }

# N4 stays the same (already has light modulation for C-S conflicts)
```

**Weight adjustment**:
```python
# OLD weights
negative_score = (
    0.35 * n1 +  # Pathogens
    0.35 * n2 +  # Herbivores
    0.20 * n4 +  # CSR conflicts
    0.05 * n5 +  # N-fixation
    0.05 * n6    # pH
)

positive_score = (
    0.25 * p1 +  # Biocontrol
    0.20 * p2 +  # Pathogen control
    0.15 * p3 +  # Beneficial fungi
    0.20 * p4 +  # Phylo diversity
    0.10 * p5 +  # Stratification
    0.10 * p6    # Pollinators
)

# NEW weights (accounting for 36.5% N4/P5 overlap)
negative_score = (
    0.35 * n1 +  # Pathogens (unchanged)
    0.35 * n2 +  # Herbivores (unchanged)
    0.15 * n4 +  # CSR conflicts (reduced from 0.20)
    0.08 * n5 +  # N-fixation (slightly increased)
    0.07 * n6    # pH (slightly increased)
)

positive_score = (
    0.25 * p1 +  # Biocontrol (unchanged)
    0.20 * p2 +  # Pathogen control (unchanged)
    0.15 * p3 +  # Beneficial fungi (unchanged)
    0.20 * p4 +  # Phylo diversity (unchanged)
    0.12 * p5 +  # Stratification (INCREASED from 0.10 - now more important!)
    0.08 * p6    # Pollinators (reduced from 0.10)
)
```

**Rationale for weight changes**:
- N4: Reduced 20% → 15% (accounts for 36.5% overlap, but keep meaningful weight)
- P5: Increased 10% → 12% (now more comprehensive with light validation)
- N5/N6: Slightly increased to maintain 100% total
- P6: Slightly reduced to maintain 100% total

---

## Alternative: If User Prefers Merger

**If you prefer Option 2** (single merged metric), here's the formula:

```python
def _compute_niche_compatibility(self, plants_data, n_plants):
    """Unified metric: CSR conflicts + vertical stratification."""

    compatibility_score = 0

    # COMPONENT 1: CSR conflicts (40%)
    csr_conflicts = self._compute_csr_conflicts_pure(plants_data, n_plants)

    # COMPONENT 2: Vertical-light compatibility (40%)
    vertical_compat = self._compute_vertical_light_compatibility(plants_data, n_plants)

    # COMPONENT 3: Form diversity (20%)
    form_diversity = (plants_data['growth_form'].nunique() - 1) / 5

    # Combined (inverted so higher = better)
    compatibility = 0.4 * (1 - csr_conflicts) + 0.4 * vertical_compat + 0.2 * form_diversity

    return compatibility
```

But I **do not recommend this approach** due to loss of interpretability.

---

## Conclusion

**Bill Shipley is correct**: P5 needs light calibration to be ecologically valid.

**The overlap is real**: 36.5% of guilds penalized by both metrics.

**Recommendation**: Keep separate with adjusted weights
- Maintains theoretical foundations
- Provides comprehensive coverage
- Offers actionable user guidance
- Weight adjustment accounts for overlap

**Next steps**:
1. Implement light validation in P5
2. Recalibrate P5 percentiles with light-validated scores
3. Adjust N4/P5 weights as recommended
4. Document overlap in 4.4

---

**Document Status**: Complete - Awaiting user decision on approach

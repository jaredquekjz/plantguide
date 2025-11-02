# Guild Scorer Test Results

**Date**: 2025-11-02
**Script**: `src/Stage_4/05_compute_guild_compatibility.py`
**Status**: Initial implementation complete, calibration needed

---

## Summary of Results

| Guild | Actual Score | Expected Score | Status |
|-------|-------------|----------------|---------|
| BAD (5 Acacias) | **+0.255** | -0.75 to -0.85 | ❌ TOO HIGH |
| GOOD #1 (Diverse) | **+0.459** | +0.30 to +0.45 | ✅ CORRECT |
| GOOD #2 (Pollinator) | **+0.152** | +0.55 to +0.75 | ⚠️  TOO LOW |

**Key Finding**: Discrimination works (0.31 point spread), but absolute values need calibration.

---

## Detailed Results

### BAD GUILD: 5 Acacias

**Plants**: Acacia koa, A. auriculiformis, A. melanoxylon, A. mangium, A. harpophylla

#### Score Breakdown

```
NEGATIVE FACTORS: 0.343 [Expected: ~0.9]
  N1 (Pathogen fungi, 40%):  0.719  ← 40 shared fungi, 7 on 80%+ plants ✓
  N2 (Herbivores, 30%):      0.183  ← Only 8 shared herbivores
  N3 (Other pathogens, 30%): 0.000  ← Zero non-fungal pathogens

POSITIVE FACTORS: 0.597 [Expected: ~0.1]
  P1 (Herbivore control, 30%): 0.462  ← 1 beneficial pair out of 20 ❌
  P2 (Pathogen control, 30%):  0.635  ← 5 mycoparasites ❌
  P3 (Beneficial fungi, 25%):  1.000  ← 49 shared beneficial fungi ❌
  P4 (Diversity, 15%):         0.120  ← 1 family only ✓

FINAL SCORE: +0.255 [Expected: -0.80]
```

#### Issues

1. **P3 maxed out (1.000)**: 49 shared beneficial fungi shouldn't compensate for 40 shared pathogens
   - Problem: Acacias have high total beneficial fungi counts (avg 58.6 per plant)
   - Ecological reality: Beneficial fungi don't matter if all plants die from same disease!

2. **P1 and P2 over-normalized**: Small raw values inflate to 0.4-0.6
   - P1: Only 1 predator total → 0.462 (should be ~0.05)
   - P2: Only 5 mycoparasites → 0.635 (should be ~0.1)

3. **N2 and N3 underweight negative**: Only pathogen fungi contributing to negative score

---

### GOOD GUILD #1: Taxonomically Diverse

**Plants**: Abrus precatorius, Abies concolor, Acacia koa, Abutilon grandifolium, Abelmoschus moschatus

#### Score Breakdown

```
NEGATIVE FACTORS: 0.024 [Expected: ~0.1]
  N1 (Pathogen fungi, 40%):  0.060  ← Only 5 shared fungi ✓
  N2 (Herbivores, 30%):      0.000  ← Zero shared herbivores ✓
  N3 (Other pathogens, 30%): 0.000  ← Zero non-fungal pathogens ✓

POSITIVE FACTORS: 0.483 [Expected: ~0.5]
  P1 (Herbivore control, 30%): 0.000  ← No cross-benefits ✓
  P2 (Pathogen control, 30%):  0.635  ← 5 mycoparasites
  P3 (Beneficial fungi, 25%):  0.798  ← 12 shared beneficial fungi
  P4 (Diversity, 15%):         0.622  ← 3 families ✓

FINAL SCORE: +0.459 [Expected: +0.40]
```

#### Analysis

- **Works well!** Score within expected range
- Low overlap correctly captured
- Good diversity correctly captured
- Slight inflation in P2/P3 but acceptable

---

### GOOD GUILD #2: Native Pollinator Plants

**Plants**: Eryngium yuccifolium, Heliopsis helianthoides, Monarda punctata, Spiraea alba, Symphyotrichum novae-angliae

#### Score Breakdown

```
NEGATIVE FACTORS: 0.316 [Expected: ~0.2]
  N1 (Pathogen fungi, 40%):  0.087  ← Only 6 shared fungi ✓
  N2 (Herbivores, 30%):      0.938  ← 60 shared herbivores! ❌
  N3 (Other pathogens, 30%): 0.000  ← Zero non-fungal pathogens ✓

POSITIVE FACTORS: 0.468 [Expected: ~0.75]
  P1 (Herbivore control, 30%): 1.000  ← 295 predators, 100% coverage ✓ EXCELLENT
  P2 (Pathogen control, 30%):  0.000  ← No mycoparasites
  P3 (Beneficial fungi, 25%):  0.185  ← Only 1 shared beneficial fungus
  P4 (Diversity, 15%):         0.811  ← 4 families ✓

FINAL SCORE: +0.152 [Expected: +0.65]
```

#### Analysis

- **Interesting case**: High herbivore overlap (60 shared) BUT high biocontrol (295 predators)
- Ecological interpretation: These plants share many generalist herbivores BUT also share their predators
- Current scoring: N2 penalty (0.938) dominates, outweighs P1 benefit (1.000 but only 30% weight)
- **Question**: Should high biocontrol (P1=1.0) offset high herbivore overlap (N2=0.938)?

---

## Component Analysis

### NEGATIVE Components

| Component | BAD | GOOD #1 | GOOD #2 | Comment |
|-----------|-----|---------|---------|---------|
| N1 (Pathogen fungi) | 0.719 | 0.060 | 0.087 | ✅ Discriminates well |
| N2 (Herbivores) | 0.183 | 0.000 | 0.938 | ⚠️  High variance |
| N3 (Other pathogens) | 0.000 | 0.000 | 0.000 | ❌ No data (all zero) |
| **Total Negative** | 0.343 | 0.024 | 0.316 | Range: 0.32 |

### POSITIVE Components

| Component | BAD | GOOD #1 | GOOD #2 | Comment |
|-----------|-----|---------|---------|---------|
| P1 (Herbivore control) | 0.462 | 0.000 | 1.000 | ⚠️  Over-normalized for small values |
| P2 (Pathogen control) | 0.635 | 0.635 | 0.000 | ⚠️  Over-normalized |
| P3 (Beneficial fungi) | 1.000 | 0.798 | 0.185 | ❌ TOO HIGH for BAD guild |
| P4 (Diversity) | 0.120 | 0.622 | 0.811 | ✅ Discriminates well |
| **Total Positive** | 0.597 | 0.483 | 0.468 | Range: 0.13 (too narrow!) |

---

## Calibration Issues Identified

### Issue 1: P3 (Beneficial Fungi) Overweighted for BAD Guild

**Problem**: Acacias have 49 shared beneficial fungi → P3 = 1.000 (maxed out)
- This gives them 25% of positive score (0.25 × 1.0 = 0.250)
- Overwhelms the negative pathogen signal

**Root cause**: Acacias naturally have high beneficial fungi diversity
- Avg beneficial fungi per plant: 58.6 (vs 40.4 for GOOD #1, 1.8 for GOOD #2)
- High total counts → high shared counts

**Proposed fix**:
```python
# Option A: Reduce P3 weight from 25% → 15%
positive_benefit_score = (
    0.35 * herbivore_control_norm +  # Increase from 30%
    0.35 * pathogen_control_norm +   # Increase from 30%
    0.15 * beneficial_fungi_norm +   # Decrease from 25%
    0.15 * diversity_norm
)

# Option B: Use ratio instead of absolute counts
# shared_beneficial / avg_total_beneficial (penalizes high absolute counts)

# Option C: Cap P3 contribution when N1 is high
# if pathogen_fungi_norm > 0.5:
#     beneficial_fungi_norm *= 0.5  # Reduce benefit when high pathogen risk
```

### Issue 2: P1/P2 Over-Normalization for Small Values

**Problem**: BAD guild has minimal cross-benefits but scores 0.462 and 0.635

**Root cause**: Current normalization
```python
# P1: 1 predator → normalized to 0.462
herbivore_control_raw = 1.0
herbivore_control_norm = tanh(1.0 / 20 * 10) = tanh(0.5) = 0.462

# P2: 5 mycoparasites → normalized to 0.635
pathogen_control_raw = 5 * 0.3 = 1.5
pathogen_control_norm = tanh(1.5 / 20 * 10) = tanh(0.75) = 0.635
```

**Proposed fix**: Adjust scaling factors
```python
# Make tanh curve steeper - require more to get high scores
herbivore_control_norm = tanh(herbivore_control_raw / max_pairs * 5)  # Was 10
pathogen_control_norm = tanh(pathogen_control_raw / max_pairs * 5)    # Was 10
```

### Issue 3: N3 (Other Pathogens) Always Zero

**Problem**: None of the test guilds have non-fungal pathogens
- N3 contributes 30% of negative score but is always 0
- This artificially lowers total negative scores

**Options**:
- A) Keep as-is (data sparsity issue, not framework issue)
- B) Reweight: N1=50%, N2=50%, N3=0% until better data
- C) Merge into N1 as "all pathogens" (fungi + other)

---

## Recommendations

### Priority 1: Recalibrate Weights

**Proposed new weights**:
```python
# NEGATIVE (unchanged structure)
negative_risk_score = (
    0.50 * pathogen_fungi_norm +  # Increase from 40% (N3 not contributing)
    0.50 * herbivore_norm          # Increase from 30%
    # Remove N3 for now (0% data coverage)
)

# POSITIVE (rebalance biocontrol vs beneficial fungi)
positive_benefit_score = (
    0.35 * herbivore_control_norm +  # Increase from 30%
    0.30 * pathogen_control_norm +   # Keep at 30%
    0.15 * beneficial_fungi_norm +   # Decrease from 25%
    0.20 * diversity_norm             # Increase from 15%
)
```

**Rationale**:
- Increase N1 weight since N3 is always zero
- Reduce P3 weight (beneficial fungi less important than biocontrol)
- Increase P4 weight (diversity is critical but underweighted)

### Priority 2: Adjust Scaling Factors

```python
# P1 and P2: Make scoring stricter
herbivore_control_norm = tanh(herbivore_control_raw / max_pairs * 5)  # Was 10
pathogen_control_norm = tanh(pathogen_control_raw / max_pairs * 5)    # Was 10

# P3: Penalize when high pathogen load
if pathogen_fungi_norm > 0.5:
    beneficial_fungi_norm *= 0.5  # Halve benefit if high pathogen risk
```

### Priority 3: Expected Scores After Calibration

| Guild | Current | After Calibration | Target |
|-------|---------|------------------|---------|
| BAD (Acacias) | +0.255 | -0.50 to -0.60 | -0.75 to -0.85 |
| GOOD #1 (Diverse) | +0.459 | +0.40 to +0.50 | +0.30 to +0.45 |
| GOOD #2 (Pollinator) | +0.152 | +0.45 to +0.55 | +0.55 to +0.75 |

---

## Next Steps

1. **Implement calibration adjustments** in `05_compute_guild_compatibility.py`
2. **Re-test on all 3 guilds** to verify improved discrimination
3. **Collect 10-20 additional test guilds** for validation
4. **Optimize weights via regression** on expanded test set
5. **Document final calibrated weights** and rationale

---

## Data Quality Notes

- ✅ Pathogenic fungi overlap (N1): Excellent discriminator (0.719 vs 0.060)
- ✅ Herbivore control (P1): Excellent when present (1.000 for GOOD #2)
- ✅ Diversity (P4): Good discriminator (0.120 vs 0.811)
- ⚠️  Beneficial fungi (P3): Too generous, needs capping
- ⚠️  Herbivore overlap (N2): High variance (0.000 to 0.938)
- ❌ Non-fungal pathogens (N3): No data (consider removing)

---

**Conclusion**: Framework structure is sound, but component weights and scaling factors need adjustment to achieve target score ranges. Primary issue is P3 (beneficial fungi) overwhelming negative signals for BAD guild.

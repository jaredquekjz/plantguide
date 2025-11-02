# Guild Scorer V3: Statistical Normalization Methodology

**Date:** 2025-11-02
**Purpose:** Document empirically-calibrated normalization approaches for guild compatibility scoring

---

## 1. The Problem with Arbitrary Scaling

### Current approach (V3 initial)
```python
# Arbitrary scaling factors chosen without empirical basis
pathogen_norm = tanh(raw_score / 8.0)   # Why 8?
phylo_norm = tanh(raw_score / 3.0)      # Why 3?
height_norm = tanh(raw_score / 10.0)    # Why 10?
```

**Issues:**
- No connection to actual data distributions
- P4 (phylogenetic diversity): Median guild gets 0.041 normalized score (4% of potential)
- P5 (height stratification): 95th percentile saturates at 0.999 (no discrimination)
- Sensitive to component design changes (if we change raw score formula, scaling breaks)

---

## 2. Proposed Statistical Normalization Methods

### Method 1: Empirical Percentile Mapping (RECOMMENDED)

**Concept:** Map raw scores to [0,1] using empirical percentile ranks from representative sample.

**Algorithm:**
1. Sample N guilds (N=1000-10000) from dataset
2. Compute raw scores for target component
3. Calculate empirical percentiles: p5, p25, p50, p75, p95
4. Define piecewise linear mapping:
   ```
   norm(x) = {
     0.0                           if x ≤ p5
     0.2 + 0.3*(x-p25)/(p50-p25)   if p25 < x ≤ p50
     0.5 + 0.3*(x-p50)/(p75-p50)   if p50 < x ≤ p75
     0.8 + 0.2*(x-p75)/(p95-p75)   if p75 < x ≤ p95
     1.0                           if x > p95
   }
   ```

**Advantages:**
- ✓ Directly calibrated to actual data distribution
- ✓ Handles arbitrary distribution shapes (skewed, zero-inflated, heavy-tailed)
- ✓ Interpretable: "This guild is at the 75th percentile for phylo diversity"
- ✓ Preserves ordinal relationships
- ✓ No saturation issues

**Disadvantages:**
- Requires pre-computed percentile table (one-time cost)
- Slightly more complex than tanh()

**Implementation:**
```python
class PercentileNormalizer:
    def __init__(self, p5, p25, p50, p75, p95):
        self.percentiles = {5: p5, 25: p25, 50: p50, 75: p75, 95: p95}

    def normalize(self, x):
        if x <= self.percentiles[5]:
            return 0.0
        elif x <= self.percentiles[25]:
            return 0.2 * (x - self.percentiles[5]) / (self.percentiles[25] - self.percentiles[5])
        elif x <= self.percentiles[50]:
            return 0.2 + 0.3 * (x - self.percentiles[25]) / (self.percentiles[50] - self.percentiles[25])
        elif x <= self.percentiles[75]:
            return 0.5 + 0.3 * (x - self.percentiles[50]) / (self.percentiles[75] - self.percentiles[50])
        elif x <= self.percentiles[95]:
            return 0.8 + 0.2 * (x - self.percentiles[75]) / (self.percentiles[95] - self.percentiles[75])
        else:
            return 1.0
```

---

### Method 2: Empirical CDF (Continuous Percentile)

**Concept:** Use empirical cumulative distribution function directly.

**Algorithm:**
1. Sample N guilds, compute raw scores
2. Sort scores: x₁ ≤ x₂ ≤ ... ≤ xₙ
3. For new score x, find rank k where xₖ ≤ x < xₖ₊₁
4. Normalize: norm(x) = k/N (with linear interpolation)

**Implementation:**
```python
from scipy.interpolate import interp1d

class ECDFNormalizer:
    def __init__(self, sample_scores):
        sorted_scores = np.sort(sample_scores)
        ecdf_values = np.linspace(0, 1, len(sorted_scores))
        self.interpolator = interp1d(sorted_scores, ecdf_values,
                                     bounds_error=False,
                                     fill_value=(0, 1))

    def normalize(self, x):
        return float(self.interpolator(x))
```

**Advantages:**
- ✓ Smooth, continuous mapping
- ✓ Direct percentile interpretation
- ✓ Handles any distribution shape
- ✓ Simple implementation (scipy)

**Disadvantages:**
- Sensitive to outliers (unless truncated)
- Requires storing entire sample or interpolation object

---

### Method 3: Quantile Normalization (Theoretical Distribution)

**Concept:** Fit theoretical distribution, map via CDF.

**Algorithm:**
1. Sample N guilds, compute raw scores
2. Fit distribution (e.g., Beta, Gamma, LogNormal) using MLE
3. Normalize: norm(x) = CDF(x | fitted_params)

**Example for Beta distribution:**
```python
from scipy.stats import beta

class BetaNormalizer:
    def __init__(self, sample_scores):
        # Fit beta distribution to [0,1]-scaled data
        data_scaled = (sample_scores - sample_scores.min()) / (sample_scores.max() - sample_scores.min())
        self.alpha, self.beta_param, self.loc, self.scale = beta.fit(data_scaled)
        self.data_min = sample_scores.min()
        self.data_max = sample_scores.max()

    def normalize(self, x):
        x_scaled = (x - self.data_min) / (self.data_max - self.data_min)
        return beta.cdf(x_scaled, self.alpha, self.beta_param, self.loc, self.scale)
```

**Advantages:**
- ✓ Compact representation (4-5 parameters)
- ✓ Smooth mapping
- ✓ Can extrapolate beyond sample range

**Disadvantages:**
- Requires correct distribution family choice
- Poor fit → biased normalization
- Doesn't handle zero-inflation well

---

### Method 4: Robust Scaling + Sigmoid (Hybrid)

**Concept:** Combine robust statistics with smooth sigmoid.

**Algorithm:**
1. Sample N guilds, compute raw scores
2. Calculate robust statistics:
   - Center: median (m)
   - Scale: IQR/1.35 (robust std estimate)
3. Normalize: norm(x) = tanh((x - m) / scale)
4. Map [-1,1] → [0,1]

**Implementation:**
```python
class RobustTanhNormalizer:
    def __init__(self, sample_scores):
        self.median = np.median(sample_scores)
        self.scale = (np.percentile(sample_scores, 75) -
                      np.percentile(sample_scores, 25)) / 1.35

    def normalize(self, x):
        z = (x - self.median) / self.scale if self.scale > 0 else 0
        return (np.tanh(z) + 1) / 2  # Map [-1,1] to [0,1]
```

**Advantages:**
- ✓ Robust to outliers (uses median/IQR)
- ✓ Smooth, differentiable
- ✓ Simple (only 2 parameters)

**Disadvantages:**
- Assumes symmetric-ish distribution
- Poor for zero-inflated data

---

### Method 5: Zero-Inflated Specialized (Two-Part Model)

**Concept:** Handle zero-inflation explicitly with two-part model.

**Algorithm:**
1. Part 1: P(zero) = proportion of zeros in sample
2. Part 2: For non-zeros, use Method 1 or 2
3. Combined: norm(x) = 0 if x=0, else (1 - P(zero)) × norm_nonzero(x)

**Implementation:**
```python
class ZeroInflatedNormalizer:
    def __init__(self, sample_scores):
        self.p_zero = (sample_scores == 0).mean()
        nonzero_scores = sample_scores[sample_scores > 0]
        # Use ECDF for non-zero part
        self.nonzero_normalizer = ECDFNormalizer(nonzero_scores)

    def normalize(self, x):
        if x == 0:
            return 0.0
        else:
            # Map non-zeros to [1-p_zero, 1.0] range
            return (1 - self.p_zero) + self.p_zero * self.nonzero_normalizer.normalize(x)
```

**Advantages:**
- ✓ Explicitly handles zero-inflation
- ✓ Preserves "no problem = 0 score" semantics
- ✓ Good for N1, N2, N4 (negative components)

**Disadvantages:**
- More complex
- Requires separate handling for zeros

---

## 3. Recommended Method by Component Type

Based on empirical analysis of 1000 random guilds:

### **Negative Components (Zero-Inflated)**

| Component | Distribution | Method | Rationale |
|-----------|--------------|--------|-----------|
| **N1: Pathogen Fungi** | Zero-inflated (50% zeros) | Method 5 or current tanh | Most guilds have no shared pathogens; zero is meaningful |
| **N2: Herbivores** | Highly zero-inflated (95% zeros) | Method 5 or keep simple | True herbivores very rare; binary-ish behavior |
| **N4: CSR Conflicts** | Zero-inflated (50% zeros) | Method 1 (Percentile) | Non-zeros span wide range; need good discrimination |

**For N1, N2, N4:** Current tanh scaling may be acceptable IF we accept that most guilds score near zero (biologically correct). The issue is NOT the scaling, but that these components are genuinely sparse.

**Alternative:** Use **Method 5 (Zero-Inflated)** to properly discriminate among non-zero cases.

---

### **Positive Components (Skewed/Normal)**

| Component | Distribution | Method | Rationale |
|-----------|--------------|--------|-----------|
| **P3: Beneficial Fungi** | Right-skewed | **Method 1 (Percentile)** ✓ | Handles skewness; clear interpretation |
| **P4: Phylogenetic Diversity** | Approximately normal | **Method 2 (ECDF)** ✓ | Smooth, continuous; good fit for normal-ish data |
| **P5: Height Stratification** | Heavy-tailed (outliers) | **Method 1 (Percentile)** ✓ | Prevents saturation from outliers |
| **P6: Shared Pollinators** | Extremely heavy-tailed | **Method 1 (Percentile)** ✓ | Handles long tail without saturation |

---

## 4. Implementation Strategy

### Phase 1: Generate Normalization Tables (One-Time)

**Script:** `src/Stage_4/calibrate_normalizations.py`

```python
"""
Sample 10,000 random 5-plant guilds to compute normalization parameters.
Save to: data/stage4/normalization_params_v3.json
"""

import json
import numpy as np
from guild_scorer_v3 import GuildScorerV3

# Sample guilds
scorer = GuildScorerV3()
n_samples = 10000
results = {
    'n1_raw': [], 'n2_raw': [], 'n4_raw': [],
    'p3_raw': [], 'p4_raw': [], 'p5_raw': [], 'p6_raw': []
}

# ... sampling code ...

# Compute percentiles for each component
params = {}
for component in ['n1', 'n2', 'n4', 'p3', 'p4', 'p5', 'p6']:
    data = np.array(results[f'{component}_raw'])
    params[component] = {
        'method': 'percentile',
        'p5': float(np.percentile(data, 5)),
        'p25': float(np.percentile(data, 25)),
        'p50': float(np.percentile(data, 50)),
        'p75': float(np.percentile(data, 75)),
        'p95': float(np.percentile(data, 95)),
        'n_samples': n_samples
    }

# Save
with open('data/stage4/normalization_params_v3.json', 'w') as f:
    json.dump(params, f, indent=2)
```

**Verification:** Compare normalized score distributions to ensure:
- Median guild → ~0.4-0.6 normalized score
- 95th percentile → ~0.8-0.95 (not saturated)
- 5th percentile → ~0.0-0.2

---

### Phase 2: Update Guild Scorer to Use Calibrated Parameters

**Modification to `guild_scorer_v3.py`:**

```python
import json
from pathlib import Path

class GuildScorerV3:
    def __init__(self, data_dir='data/stage4'):
        # ... existing init ...

        # Load normalization parameters
        norm_params_path = Path(data_dir) / 'normalization_params_v3.json'
        if norm_params_path.exists():
            with open(norm_params_path) as f:
                self.norm_params = json.load(f)
            self.use_calibrated_norms = True
        else:
            print("WARNING: No calibrated normalization params found, using defaults")
            self.use_calibrated_norms = False

    def _normalize(self, component: str, raw_value: float) -> float:
        """Apply calibrated normalization."""
        if not self.use_calibrated_norms:
            # Fallback to tanh with default scales
            return self._normalize_default(component, raw_value)

        params = self.norm_params[component]

        if params['method'] == 'percentile':
            # Piecewise linear percentile mapping
            if raw_value <= params['p5']:
                return 0.0
            elif raw_value <= params['p25']:
                return 0.2 * (raw_value - params['p5']) / (params['p25'] - params['p5'])
            elif raw_value <= params['p50']:
                return 0.2 + 0.3 * (raw_value - params['p25']) / (params['p50'] - params['p25'])
            elif raw_value <= params['p75']:
                return 0.5 + 0.3 * (raw_value - params['p50']) / (params['p75'] - params['p50'])
            elif raw_value <= params['p95']:
                return 0.8 + 0.2 * (raw_value - params['p75']) / (params['p95'] - params['p75'])
            else:
                return 1.0

        # ... other methods ...
```

---

## 5. Comparison: Current vs. Proposed

Using empirical data from 1000-guild sample:

### P4: Phylogenetic Diversity (Example)

**Current (tanh with scale=3.0):**
```
Median raw (0.1235) → 0.041 normalized → 0.008 contribution (20% weight)
75th %ile (0.1381) → 0.046 normalized → 0.009 contribution
```

**Proposed (Percentile mapping):**
```
Median raw (0.1235) → 0.50 normalized → 0.100 contribution (20% weight)
75th %ile (0.1381) → 0.80 normalized → 0.160 contribution
```

**Improvement:** 12× better sensitivity at median, preserves full dynamic range.

---

## 6. Alternative: Keep Tanh, Calibrate Scale Factor

If we want to keep tanh for smoothness, we can empirically calibrate the scale factor:

**Target:** Median raw score → tanh(0.5) = 0.46

**Formula:** `scale = median_raw / 0.5`

**Results:**
| Component | Median Raw | Current Scale | Calibrated Scale | Improvement |
|-----------|------------|---------------|------------------|-------------|
| P3 | 0.240 | 3.0 | **0.48** | 6.25× |
| P4 | 0.1235 | 3.0 | **0.247** | 12.1× |
| P5 | 11.84 | 10.0 | **23.7** | 2.37× |
| P6 | 0.160 | 5.0 | **0.32** | 15.6× |

**Pros:** Minimal code change, smooth differentiable function
**Cons:** Still arbitrary sigmoid shape, doesn't handle zero-inflation or heavy tails well

---

## 7. Recommended Action Plan

### Immediate (Quick Fix)
✓ **Option A:** Update tanh scale factors using empirical calibration (Section 6)
- Minimal code change
- Immediate 6-15× sensitivity improvement
- Takes 5 minutes

### Robust (Proper Solution)
✓ **Option B:** Implement Method 1 (Percentile Mapping) for all components
1. Run `calibrate_normalizations.py` to generate percentile table (30 min)
2. Update `guild_scorer_v3.py` to use percentile normalization (1 hour)
3. Re-test all guilds (10 min)
4. Document normalization parameters in version control

**Recommendation:** Start with **Option A** (quick empirical tanh calibration) now, implement **Option B** (percentile mapping) as next iteration.

---

## 8. Validation Criteria

After implementing new normalization:

1. **Sensitivity check:**
   - Median guild should score 0.4-0.6 (not 0.04!)
   - 25th-75th percentile range should span ≥0.3 (discriminatory power)

2. **Saturation check:**
   - 95th percentile should score <0.95 (no saturation)
   - Top 5% of guilds should have distinguishable scores

3. **Biological validity:**
   - Zero-problem guilds score near 0 for negative components
   - Extreme cases (monocultures, very diverse) produce expected scores

4. **Stability:**
   - Re-sampling 10,000 guilds should give similar percentile values (±5%)

---

## 9. References

**Statistical Methods:**
- Robust scaling: Huber (1981) "Robust Statistics"
- Percentile normalization: Bolstad et al. (2003) "A comparison of normalization methods for high density oligonucleotide array data"
- Zero-inflated models: Lambert (1992) "Zero-inflated Poisson regression"

**Phylogenetic Methods:**
- Eigenvector approach: Moura et al. (2024) "Rapid and predictable trait evolution in sticklebacks" PLoS Biology
- V.PhyloMaker2: Jin & Qian (2022) Molecular Ecology Resources

---

**Document Date:** 2025-11-02
**Empirical Sample:** 1000 random 5-plant guilds from 11,680-species dataset
**Next Update:** After implementing chosen normalization method

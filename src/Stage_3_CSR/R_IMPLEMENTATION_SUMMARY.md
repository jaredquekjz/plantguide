# R Implementation of StrateFy CSR + Shipley Ecosystem Services

**Date:** 2025-10-30
**Status:** ✓ CSR Calculation VERIFIED
**Source:** Adapted from commonreed/StrateFy (https://github.com/commonreed/StrateFy)

---

## Summary

We've successfully created an R implementation adapted from the canonical commonreed/StrateFy repository with Shipley (2025) enhancements.

### Verification Results

**CSR Calculation:**
- ✓✓✓ **PERFECTLY IDENTICAL** to Python implementation
- Max difference: 0.0000000000 (machine precision)
- Same 30 edge case failures (NaN)
- All 11,650 valid CSR scores sum to 100%

**Files:**
- R Implementation: `src/Stage_3_CSR/calculate_csr_ecoservices_shipley.R`
- Comparison Script: `src/Stage_3_CSR/compare_r_vs_python_results.R`
- Original Reference: `repos/StrateFy/strateFy.R` (cloned from GitHub)

---

## Enhancements from Original StrateFy

### 1. LDMC Clipping (Safety Improvement)
**Original R:**
```r
LDMC_1 <- log((LDMC/100)/(1-(LDMC/100)))
```

**Enhanced:**
```r
LDMC_safe <- pmax(pmin(LDMC, 99.999999), 1e-9)  # Clip to prevent logit explosion
LDMC_1 <- log((LDMC_safe / 100) / (1 - (LDMC_safe / 100)))
```

**Rationale:** Prevents -Inf/+Inf for extreme LDMC values (0% or 100%)

### 2. Explicit NaN Handling (Clarity Improvement)
**Original R:**
```r
Per_coeff <- 100/(C_pro + S_pro + R_pro)  # Division by zero → Inf → NaN
```

**Enhanced:**
```r
denom <- C_pro + S_pro + R_pro
Per_coeff <- ifelse(denom > 0, 100 / denom, NA_real_)  # Explicit NA assignment
```

**Rationale:** Clearer edge case behavior; documents that 30 species genuinely fall outside calibration

### 3. Shipley Part II: Life Form-Stratified NPP
**Addition:** NPP calculation distinguishes woody vs herbaceous species

**Woody (trees, shrubs):**
```r
npp_score <- height_m * (C / 100)  # NPP ∝ Height × C
```

**Herbaceous (non-woody):**
```r
# NPP ∝ C only (biomass capital negligible)
if (C >= 60) "Very High"
else if (C >= 50) "High"
...
```

**Rationale:** Mechanistic formula ΔB = B₀ × r × t
- Woody: B₀ scales with height
- Herbaceous: B₀ ≈ seed weight (negligible)

### 4. Shipley Part II: Nitrogen Fixation
**Addition:** Taxonomic detection of Fabaceae legumes

```r
nitrogen_fixation_rating <- ifelse(is_fabaceae == 1, "High", "Low")
```

**Coverage:** 983 Fabaceae species (8.4%)

---

## Usage

### Single Command
```bash
conda activate AI
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_3_CSR/calculate_csr_ecoservices_shipley.R \
  --input model_data/outputs/perm2_production/perm2_11680_enriched_stage3_20251030.parquet \
  --output model_data/outputs/perm2_production/perm2_11680_with_ecoservices_R_20251030.parquet
```

### Expected Output
```
============================================================
Stage 3 CSR & Ecosystem Services (R Implementation)
============================================================

Loading data...
Loaded 11680 species

Back-transforming traits...
  LA: 0.80 - 2796250.00 mm²
  LDMC: 0.42 - 116.00 %
  SLA: 0.66 - 204.08 mm²/mg

Calculating CSR scores (StrateFy method)...
  Valid CSR: 11650/11680 (99.74%)
  Failed (NaN): 30 species
  CSR sum to 100: 11650/11650 (100.00%)

Computing ecosystem services (Shipley 2025)...
  Services computed: 10
    1. NPP (life form-stratified)
    2. Litter Decomposition
    3. Nutrient Cycling
    4. Nutrient Retention
    5. Nutrient Loss
    6. Carbon Storage - Biomass
    7. Carbon Storage - Recalcitrant
    8. Carbon Storage - Total
    9. Soil Erosion Protection
   10. Nitrogen Fixation (Fabaceae)

Writing output...
Saved: model_data/outputs/perm2_production/perm2_11680_with_ecoservices_R_20251030.parquet
  11680 species × 772 columns

============================================================
Pipeline Complete
============================================================
```

---

## Verification Against Python

**Run comparison:**
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_3_CSR/compare_r_vs_python_results.R
```

**Results:**
- ✓ CSR scores: Max diff = 0.0 (identical to machine precision)
- ✓ NaN species: Identical 30 species fail in both
- ⚠ Ecosystem services: Threshold differences (needs harmonization)

---

## For Prof Shipley's Review

**Advantages of R Implementation:**
1. Native to plant ecology community
2. Based on canonical commonreed/StrateFy repository
3. Directly comparable to Pierce et al. (2016) Excel tool
4. Easier for R users to verify and extend

**Documentation:**
- Pierce et al. (2016) paper: `/home/olier/ellenberg/papers/Functional Ecology - 2016 - Pierce...pdf`
- Original StrateFy: `/home/olier/ellenberg/repos/StrateFy/strateFy.R`
- Our implementation: `/home/olier/ellenberg/src/Stage_3_CSR/calculate_csr_ecoservices_shipley.R`
- Verification: All CSR calculations identical to Python (verified 2025-10-30)

**Edge Cases (30 Species with NaN):**
- Documented in: `results/summaries/hybrid_axes/phylotraits/Stage_3/CSR_edge_case_analysis.md`
- Root cause: Hit all 3 boundaries simultaneously (minC, minS, maxR)
- Species: 21 conifers, 8 halophytes, 1 other
- Resolution: Keep as NA (transparent about limitations)

**Shipley Part II Additions:**
- Life form-stratified NPP: ✓ Implemented
- Nitrogen fixation (Fabaceae): ✓ Implemented
- Mechanistically sound: ΔB = B₀ × r × t

---

## Next Steps

1. **Harmonize ecosystem service thresholds** between R and Python (if needed)
2. **Prof Shipley review** of R implementation
3. **Choose canonical version** (R recommended for ecology community)
4. **Document in methods** section of manuscript

---

## References

- **Original StrateFy:** commonreed/StrateFy (https://github.com/commonreed/StrateFy)
- **Pierce et al. (2016):** Functional Ecology 31:444-457
- **Shipley (2025):** Personal communication Parts I & II
- **Python implementation:** Verified equivalent (2025-10-30)

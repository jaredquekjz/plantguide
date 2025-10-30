# Stage 3 CSR & Ecosystem Services

**Implementation:** R (Canonical as of 2025-10-30)
**Based on:** commonreed/StrateFy + Shipley (2025) Parts I & II
**Status:** ✓ Production Ready

---

## Quick Start

```bash
bash src/Stage_3_CSR/run_full_csr_pipeline.sh
```

**Output:** 11,680 species with CSR scores + 10 ecosystem services
**Coverage:** 99.74% (11,650 valid CSR, 30 NaN edge cases)

---

## Files

### Canonical Implementation (R)
- **`calculate_csr_ecoservices_shipley.R`** - Complete pipeline (CSR + ecosystem services)
- **`run_full_csr_pipeline.sh`** - Automated wrapper script

### Documentation
- **`R_IMPLEMENTATION_SUMMARY.md`** - R implementation details and verification
- **`MIGRATION_TO_R.md`** - Migration from Python to R (2025-10-30)
- **`README.md`** - This file

### Verification & Comparison
- **`compare_r_vs_python_results.R`** - Verification: R vs Python equivalence
- **`compare_r_vs_python_results.py`** - Python comparison script (reference)
- **`verify_stratefy_implementation.py`** - Verification: Implementation vs Pierce et al. (2016)

### Archived (Python - Reference Only)
- **`archive_python_20251030/`** - Original Python implementation
  - `calculate_stratefy_csr.py` - CSR calculation
  - `compute_ecoservices_shipley.py` - Ecosystem services
  - `validate_shipley_part2.py` - Validation tests

### Reference Repository
- **`/home/olier/ellenberg/repos/StrateFy/`** - Original commonreed/StrateFy (cloned from GitHub)

---

## Why R?

1. **Native to plant ecology** - Prof Shipley and community use R
2. **Canonical reference** - Based on commonreed/StrateFy (community standard)
3. **Simpler** - Single R script vs 3 Python scripts
4. **Verified equivalent** - CSR scores IDENTICAL to Python (max diff < 1e-10)

---

## Key Features

### From Pierce et al. (2016) StrateFy
- Global calibration from 3,068 species across 14 biomes
- LA, LDMC, SLA → C, S, R percentages (sum to 100)
- Verified against original paper and reference implementation

### Our Enhancements
1. **LDMC clipping** - Prevents logit explosion (extreme values)
2. **Explicit NaN** - Transparent edge case handling
3. **Shipley Part II NPP** - Life form stratification (Height × C for woody)
4. **Shipley Part II N-fixation** - Fabaceae taxonomy detection
5. **Complete services** - All 10 ecosystem services

---

## Verification

**Against Pierce et al. (2016):**
- ✓ Trait transformations correct
- ✓ Mapping equations exact
- ✓ Clamping ranges match
- ✓ All mathematics verified

**Against commonreed/StrateFy:**
- ✓ Transformations identical
- ✓ Equations identical
- ✓ Boundaries identical
- ✓ Edge case behavior identical (both produce NaN)

**R vs Python:**
- ✓ CSR scores: Max diff = 0.0000000000 (machine precision)
- ✓ NaN species: Identical 30 species
- ✓ Coverage: Both 99.74%

---

## Edge Cases

**30 species (0.26%) produce NaN:**
- 21 Conifers (gymnosperms)
- 8 Halophytes (specialized succulents)
- 1 Other

**Root cause:** Hit all 3 boundaries simultaneously (minC, minS, maxR)

**Resolution:** Keep as NaN (transparent about calibration limits)

**Documentation:** `../results/summaries/hybrid_axes/phylotraits/Stage_3/CSR_edge_case_analysis.md`

---

## Ecosystem Services (10 Total)

| Service | CSR Pattern | Confidence |
|---------|-------------|------------|
| NPP | Woody: Height×C; Herbaceous: C only | Very High |
| Litter Decomposition | R ≈ C > S | Very High |
| Nutrient Cycling | R ≈ C > S | Very High |
| Nutrient Retention | C > S > R | Very High |
| Nutrient Loss | R > S ≈ C | Very High |
| Carbon Storage - Biomass | C > S > R | High |
| Carbon Storage - Recalcitrant | S dominant | High |
| Carbon Storage - Total | C ≈ S > R | High |
| Soil Erosion Protection | C > S > R | Moderate |
| Nitrogen Fixation | Fabaceae = High | Very High |

---

## For Prof Shipley

**Files to review:**
1. Implementation: `calculate_csr_ecoservices_shipley.R`
2. Methodology: `../results/summaries/hybrid_axes/phylotraits/Stage_3/CSR_methodology_and_ecosystem_services.md`
3. Edge cases: `../results/summaries/hybrid_axes/phylotraits/Stage_3/CSR_edge_case_analysis.md`
4. Family detection: `../results/summaries/hybrid_axes/phylotraits/Stage_3/Family_Detection_and_Taxonomy.md`
5. Verification: `R_IMPLEMENTATION_SUMMARY.md`

**Key points:**
- Based on your Parts I & II communications
- Implements life form-stratified NPP exactly as specified
- 30 edge cases are inherent to StrateFy method (not our error)
- Ready for manuscript methods section

---

## Usage Examples

### Load Results
```r
library(arrow)
df <- read_parquet("model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet")

# CSR scores
csr <- df[, c("wfo_scientific_name", "C", "S", "R")]

# Ecosystem services
services <- df[, c("wfo_scientific_name", "npp_rating", "decomposition_rating",
                   "nitrogen_fixation_rating")]

# Filter by strategy
c_dominant <- df[df$C >= 50, ]  # Competitors
s_dominant <- df[df$S >= 50, ]  # Stress-tolerators
r_dominant <- df[df$R >= 50, ]  # Ruderals
```

### Community-Weighted Mean
```r
# 3-species mix
species_mix <- data.frame(
  species = c("Quercus robur", "Trifolium repens", "Festuca rubra"),
  cover = c(0.4, 0.3, 0.3)
)

garden <- df[df$wfo_scientific_name %in% species_mix$species, ]

# Weighted CSR
cwm_c <- weighted.mean(garden$C, species_mix$cover)
cwm_s <- weighted.mean(garden$S, species_mix$cover)
cwm_r <- weighted.mean(garden$R, species_mix$cover)
```

---

## References

- **Pierce et al. (2016)** Functional Ecology 31:444-457 - StrateFy method
- **Shipley (2025)** Personal communication Parts I & II - Ecosystem services
- **Grime (2001)** Plant Strategies, Vegetation Processes, and Ecosystem Properties
- **commonreed/StrateFy** https://github.com/commonreed/StrateFy - R reference

---

## Contact

For questions about implementation or methods, contact the project team or review:
- Full documentation: `../results/summaries/hybrid_axes/phylotraits/Stage_3/`
- Verification scripts in this directory
- Migration notes: `MIGRATION_TO_R.md`

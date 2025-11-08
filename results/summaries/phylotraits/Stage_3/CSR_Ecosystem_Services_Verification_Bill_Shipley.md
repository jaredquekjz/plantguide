# Stage 3 CSR & Ecosystem Services — R Verification (Bill Shipley)

**Purpose**: Independent R-based verification of CSR strategy and ecosystem services calculation
**Date**: 2025-11-08
**Dataset**: 11,711 species with 100% complete traits and EIVE
**Environment**: R (system R at `/usr/bin/Rscript`)

---

## Bill's Verification Role

Bill should independently assess:

1. **CSR calculation correctness**: StrateFy (Pierce et al. 2016) implementation, LDMC clipping, edge case handling
2. **Ecosystem services logic**: Shipley (2025) framework, life form stratification (Part II), service-CSR relationships
3. **Code review**: Trait back-transformation, life form simplification, NPP formula (height × C for woody plants)

---

## Scripts Overview

All scripts located in: `src/Stage_3/bill_verification/`

### Processing Scripts (2)

**Enrichment:**
- `enrich_bill_with_taxonomy.R` - Add family, genus, height_m, life_form_simple

**CSR & Services:**
- `calculate_csr_bill.R` - StrateFy CSR + 10 ecosystem services (Shipley 2025)

### Verification Scripts (4)

**CSR Verification:**
- `verify_csr_calculation_bill.R` - **CRITICAL**: CSR completeness ≥99.5%, sum to 100, distributions
- `verify_ecoservices_bill.R` - Verify 10 service patterns (NPP, decomposition, nutrient cycling, etc.)
- `verify_lifeform_stratification_bill.R` - Verify Shipley Part II (woody height × C boost)

**Master Verification:**
- `verify_stage3_complete_bill.R` - Orchestrate all Stage 3 verification checks

**Total: 6 scripts** (2 processing, 4 verification)

---

## Workflow Overview

**Stage 3 (CSR & Services)**: Complete traits + EIVE → CSR scores → 10 ecosystem service ratings

**Pipeline steps**:
1. **Enrichment**: Add taxonomy, back-transform height, simplify life form
2. **CSR calculation**: Apply StrateFy (Pierce et al. 2016) to LA, LDMC, SLA
3. **Services calculation**: Apply Shipley (2025) rules with life form stratification
4. **Verification**: Validate CSR patterns, service distributions, NPP stratification

**Key enhancement**: Life form-stratified NPP (Shipley Part II)
- **Woody plants**: NPP ∝ height_m × C/100 (biomass accumulation effect)
- **Herbaceous plants**: NPP ∝ C only (negligible initial biomass)

---

## Prerequisites

### Required Data (from Stage 2)

**Complete EIVE dataset** (after Stage 2 imputation):
- File: `data/shipley_checks/stage2_predictions/bill_complete_with_eive_20251107.csv`
- Dimensions: 11,711 species with 100% complete traits and EIVE
- Required columns:
  - `wfo_taxon_id`, `wfo_scientific_name`
  - `logLA`, `logLDMC`, `logSLA`, `logH` (100% complete from Stage 1)
  - `try_woodiness` (~79% complete)
  - `EIVEres-L`, `EIVEres-T`, `EIVEres-M`, `EIVEres-N`, `EIVEres-R` (100% complete from Stage 2)

**WorldFlora taxonomy** (from Phase 0):
- Files: `data/shipley_checks/wfo_verification/*_worldflora_enriched.parquet`
- Provides: family, genus for ≥99% species

### R Environment Setup

```bash
# Use system R (not conda)
R_LIBS_USER="/home/olier/ellenberg/.Rlib"

# Required packages: readr, dplyr, arrow, optparse
```

**Note**: Stage 3 is pure R, no Python dependencies.

---

## Stage 3: CSR & Ecosystem Services

### Step 0: Enrich with Taxonomy and Life Form

**Purpose**: Add family, genus, height_m, life_form_simple to Stage 2 output

**Script**: `src/Stage_3/bill_verification/enrich_bill_with_taxonomy.R`

**Run**:
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_3/bill_verification/enrich_bill_with_taxonomy.R \
    --input data/shipley_checks/stage2_predictions/bill_complete_with_eive_20251107.csv \
    --output data/shipley_checks/stage3/bill_enriched_stage3_11711.csv
```

**What it does**:
1. Load Stage 2 complete dataset (11,711 × complete traits + EIVE)
2. Load taxonomy from WorldFlora parquets (family, genus)
3. Merge taxonomy by wfo_taxon_id
4. Back-transform height: `height_m = exp(logH)`
5. Simplify life form from try_woodiness:
   - "woody" → woody
   - "non-woody" → non-woody
   - "semi-woody" → semi-woody
   - Mixed/unknown → NA
6. Save enriched dataset

**Output**: `data/shipley_checks/stage3/bill_enriched_stage3_11711.csv`

**Expected internal verification**:
```
[Pending - to be filled when run]

[1] Taxonomy coverage:
    ✓ family: [__]% ([____]/11711)
    ✓ genus: [__]% ([____]/11711)

[2] Enrichment completeness:
    ✓ height_m: 100% (11711/11711)
    ✓ life_form_simple: [__]% ([____]/11711)

[3] Dimensions:
    ✓ 11711 species × [___] columns
```

---

### Step 1: Calculate CSR and Ecosystem Services

**Purpose**: Apply StrateFy CSR + Shipley (2025) ecosystem services

**Script**: `src/Stage_3/bill_verification/calculate_csr_bill.R`

**Run**:
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_3/bill_verification/calculate_csr_bill.R \
    --input data/shipley_checks/stage3/bill_enriched_stage3_11711.csv \
    --output data/shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv
```

**What it does**:

**Part 1: CSR Calculation (StrateFy)**
1. Back-transform traits to raw units:
   - `LA = exp(logLA)` (mm²)
   - `LDMC = exp(logLDMC) × 100` (%)
   - `SLA = exp(logSLA)` (mm²/mg)
2. Apply StrateFy transformations with LDMC clipping (prevents logit explosion)
3. Calculate C, S, R percentages (sum to 100)
4. Handle edge cases (species at boundaries → NaN)

**Part 2: Ecosystem Services (Shipley 2025)**
5. Compute 10 service ratings based on CSR scores:
   - **NPP** (life form-stratified): Woody = height × C, Herbaceous = C only
   - **Litter Decomposition**: R ≈ C > S
   - **Nutrient Cycling**: R ≈ C > S
   - **Nutrient Retention**: C > S > R
   - **Nutrient Loss**: R > S ≈ C
   - **Carbon Storage - Biomass**: C > S > R
   - **Carbon Storage - Recalcitrant**: S dominant
   - **Carbon Storage - Total**: C ≈ S > R
   - **Soil Erosion Protection**: C > S > R
   - **Nitrogen Fixation**: Fallback "Low" (no TRY data)
6. Assign confidence levels (Very High, High, Moderate, Low)
7. Mark species without valid CSR as "Unable to Classify"

**Output**: `data/shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv`

**Expected internal verification**:
```
[Pending - to be filled when run]

[1] Trait back-transformation:
    ✓ LA: [____] - [____] mm²
    ✓ LDMC: [____] - [____] %
    ✓ SLA: [____] - [____] mm²/mg

[2] CSR calculation:
    ✓ Valid CSR: [____]/11711 ([__]%)
    ✓ Failed (NaN): [__] species ([__]%)
    ✓ CSR sum to 100: [____]/[____] ([__]%)

[3] CSR distribution:
    Mean C: [__]% (expected ~31%)
    Mean S: [__]% (expected ~39%)
    Mean R: [__]% (expected ~30%)

[4] Ecosystem services:
    ✓ 10 services computed
    ✓ Confidence levels assigned
```

---

### Step 2: Verify CSR Calculation

**Purpose**: Verify CSR scores match expected StrateFy patterns

**Script**: `src/Stage_3/bill_verification/verify_csr_calculation_bill.R`

**Run**:
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_3/bill_verification/verify_csr_calculation_bill.R \
    --input data/shipley_checks/stage3/bill_with_csr_ecoservices_11711.csv
```

**Checks**:

**[1] CSR Completeness**:
- ✓ Valid CSR ≥ 99.5% ([expected: ~99.7%])
- ✓ Edge cases ≤ 60 species ([expected: ~30 species, 0.26%])

**[2] CSR Sum to 100**:
- ✓ C + S + R = 100 (±0.01) for ≥99.9% of valid species
- Show example bad sums if any failures

**[3] CSR Value Ranges**:
- ✓ C, S, R all in [0, 100]
- ✓ Mean C ≈ 31% (allow 20-45%)
- ✓ Mean S ≈ 39% (allow 30-50%)
- ✓ Mean R ≈ 30% (allow 20-40%)

**[4] Dominant Strategies**:
- Count species where one strategy >40%
- Expected: balanced distribution across C/S/R dominant groups

**Expected**:
```
[Pending - to be filled when run]

✓ VERIFICATION PASSED
✓ CSR completeness: [____]/11711 ([__]%) valid
✓ Edge cases: [__] species with NaN CSR
✓ CSR sum check: [__]% sum to 100 (±0.01)
✓ Mean CSR: C=[__]%, S=[__]%, R=[__]%
```

---

### Step 3: Verify Ecosystem Services

**Purpose**: Verify ecosystem service patterns match Shipley framework

**Script**: `src/Stage_3/bill_verification/verify_ecoservices_bill.R` *(to be created)*

**Checks**:

**[1] Service Completeness**:
- ✓ All 10 services: 100% coverage (inherit from CSR or fallback)
- ✓ All 10 confidence levels assigned

**[2] NPP Patterns** (Shipley Part I + II):
- ✓ C-dominant species: majority Very High/High
- ✓ S-dominant species: majority Low
- ✓ R-dominant species: very few Very High
- ✓ **Woody NPP** (Part II): ~36% Very High (height × C effect)
- ✓ **Herbaceous NPP**: ~10% Very High (C only)

**[3] Decomposition Patterns**:
- ✓ R-dominant: ~54% Very High
- ✓ C-dominant: ~52% Very High
- ✓ S-dominant: ~68% Low

**[4] Nutrient Loss Patterns**:
- ✓ R-dominant: ~54% Very High
- ✓ C-dominant: ~52% Very Low

**[5] Nitrogen Fixation**:
- ✓ All species: "Low" (fallback, no TRY data)
- ✓ Confidence: "Low" for all

**Expected**:
```
[Pending - to be filled when run]

✓ VERIFICATION PASSED
✓ All 10 services: 100% coverage
✓ NPP patterns match Shipley framework
✓ Decomposition patterns: R ≈ C > S
✓ Nutrient loss patterns: R > C
```

---

### Step 4: Verify Life Form Stratification

**Purpose**: Verify Shipley Part II NPP formula implementation

**Script**: `src/Stage_3/bill_verification/verify_lifeform_stratification_bill.R` *(to be created)*

**Checks**:

**[1] Formula Correctness**:
- ✓ Woody: NPP ∝ height_m × (C/100)
- ✓ Herbaceous: NPP ∝ C only
- ✓ Semi-woody: treated as woody
- ✓ Unknown: fallback to C only

**[2] Test Cases**:
- ✓ Tall tree (22m, C=37.8) → NPP Very High (height boost)
- ✓ Short herb (0.5m, C=63.5) → NPP Very High (C pathway)
- ✓ Tall tree with low C → moderate NPP (demonstrates stratification)

**[3] Distribution Validation**:
- ✓ Woody: ~36% Very High NPP
- ✓ Herbaceous: ~10% Very High NPP
- ✓ Ratio: ~3.6× difference demonstrates life form effect

**Expected**:
```
[Pending - to be filled when run]

✓ VERIFICATION PASSED
✓ NPP formula correct for woody/herbaceous
✓ Woody NPP: [__]% Very High (expected ~36%)
✓ Herbaceous NPP: [__]% Very High (expected ~10%)
✓ Life form stratification working correctly
```

---

### Step 5: Master Verification (All Checks)

**Purpose**: Run all Stage 3 verification checks in sequence

**Script**: `src/Stage_3/bill_verification/verify_stage3_complete_bill.R` *(to be created)*

**Run**:
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_3/bill_verification/verify_stage3_complete_bill.R
```

**Orchestrates**:
1. CSR calculation verification
2. Ecosystem services verification
3. Life form stratification verification

**Expected**:
```
[Pending - to be filled when run]

========================================================================
STAGE 3 VERIFICATION COMPLETE
========================================================================

✓ CSR calculation: PASSED
✓ Ecosystem services: PASSED
✓ Life form stratification: PASSED

All verification checks passed.
```

---

## Expected Outputs

### Data Files

```
data/shipley_checks/stage3/
├── bill_enriched_stage3_11711.csv              # Step 0 output
└── bill_with_csr_ecoservices_11711.csv         # Step 1 output (FINAL)
```

**Final dataset structure**:
- 11,711 species × ~[770] columns
- Original features + enrichment (family, genus, height_m, life_form_simple)
- CSR scores (C, S, R) - 3 columns
- 10 ecosystem service ratings - 10 columns
- 10 ecosystem service confidence levels - 10 columns

**New columns added**:
| Column Group | Count | Description |
|--------------|-------|-------------|
| Taxonomy | 2 | family, genus |
| Back-transformed | 1 | height_m = exp(logH) |
| Life form | 1 | life_form_simple (woody/non-woody/semi-woody) |
| CSR scores | 3 | C, S, R (sum to 100) |
| Service ratings | 10 | NPP, decomposition, nutrient cycling, retention, loss, carbon (3 types), erosion, N-fixation |
| Service confidence | 10 | Very High, High, Moderate, Low, Not Applicable |
| **Total added** | **27** | |

---

## Success Criteria

### CSR Calculation
- [ ] Valid CSR ≥ 99.5% (expected ~99.7%)
- [ ] Edge cases ≤ 60 species (expected ~30)
- [ ] All valid CSR: C + S + R = 100 (±0.01)
- [ ] Mean CSR: C ≈ 31%, S ≈ 39%, R ≈ 30% (±10%)

### Ecosystem Services
- [ ] All 10 services: 100% coverage
- [ ] NPP: C-dominant majority Very High/High, S-dominant majority Low
- [ ] Decomposition: R ≈ C > S pattern confirmed
- [ ] Nutrient loss: R > C pattern confirmed
- [ ] Nitrogen fixation: All "Low" with "Low" confidence (fallback)

### Life Form Stratification
- [ ] Woody NPP: ~36% Very High (height × C boost working)
- [ ] Herbaceous NPP: ~10% Very High (C only pathway)
- [ ] Ratio ≈ 3.6× demonstrates stratification effect
- [ ] Formula correctness: test cases pass

### Data Integrity
- [ ] No missing ecosystem service ratings (100% coverage)
- [ ] All confidence levels assigned correctly
- [ ] Family/genus coverage ≥ 99%
- [ ] height_m coverage = 100% (complete from Stage 1 logH)

---

## System Requirements

**R Environment**:
```bash
R_LIBS_USER="/home/olier/ellenberg/.Rlib"
/usr/bin/Rscript  # System R (not conda)
```

**Required packages**:
- `readr` - CSV I/O
- `dplyr` - Data manipulation
- `arrow` - Parquet reading (for WorldFlora sources)
- `optparse` - Command-line argument parsing

**Runtime**:
- Enrichment: ~30 seconds
- CSR calculation: ~1-2 minutes
- Verification suite: ~30 seconds
- **Total: ~3 minutes**

---

## File Locations

**Scripts**: `src/Stage_3/bill_verification/`
- `enrich_bill_with_taxonomy.R`
- `calculate_csr_bill.R`
- `verify_csr_calculation_bill.R`
- `verify_ecoservices_bill.R` *(to be created)*
- `verify_lifeform_stratification_bill.R` *(to be created)*
- `verify_stage3_complete_bill.R` *(to be created)*

**Data**: `data/shipley_checks/stage3/`
- Input: `../stage2_predictions/bill_complete_with_eive_20251107.csv`
- Enriched: `bill_enriched_stage3_11711.csv`
- Final: `bill_with_csr_ecoservices_11711.csv`

**Verification reports**: Console output + exit codes (0 = pass, 1 = fail)

---

## Notes

**Canonical pipeline already pure R**:
- Original: `src/Stage_3_CSR/calculate_csr_ecoservices_shipley.R`
- Bill's version: Minimal changes (CSV I/O, shipley_checks paths)
- Logic identical: StrateFy CSR + Shipley services

**Key enhancements from canonical Python**:
1. LDMC clipping (prevents logit explosion for extreme values)
2. Explicit NaN handling (clearer edge case behavior)
3. Life form-stratified NPP (Shipley Part II: height × C for woody plants)
4. Nitrogen fixation fallback (no TRY data, all "Low")

**Edge cases** (~30 species, 0.26%):
- Species at CSR boundary extremes → denominator = 0 → NaN
- Expected behavior: Marked as "Unable to Classify" for all services
- Typically: Extreme halophytes, conifers with unusual trait combinations

**Nitrogen fixation**:
- Bill's version uses "Low" fallback for all species
- Canonical version uses TRY TraitID 8 weighted evidence (not available for Bill's verification)
- All confidence levels = "Low" (assumption-based, not empirical)

---

## Quick Reference Commands

**Full Stage 3 pipeline** (run sequentially):

```bash
# Step 0: Enrichment
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_3/bill_verification/enrich_bill_with_taxonomy.R

# Step 1: CSR + Ecosystem Services
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_3/bill_verification/calculate_csr_bill.R

# Step 2-4: Verification Suite (when scripts created)
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_3/bill_verification/verify_csr_calculation_bill.R

env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_3/bill_verification/verify_ecoservices_bill.R

env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_3/bill_verification/verify_lifeform_stratification_bill.R

# Master verification (orchestrates all checks)
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript src/Stage_3/bill_verification/verify_stage3_complete_bill.R
```

**Monitor progress**: All scripts provide detailed console output with ✓/✗ status indicators.

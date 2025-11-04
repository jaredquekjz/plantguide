# Stage 4 Framework Audit

**Date**: 2025-11-04
**Purpose**: Verify all scripts align with updated framework (4.4) after P5 light validation implementation

---

## Executive Summary

**Status**: Framework is solid with minor path inconsistencies that need fixing.

**Key Findings**:
1. ✓ Core scorer (guild_scorer_v3.py) fully aligned with 4.4 framework
2. ✓ Light boundaries (3.2, 7.47) consistent across N4 and P5
3. ✓ All 11 metrics (N1, N2, N4-N6, P1-P6) implemented correctly
4. ✗ Dataset path inconsistencies across scripts (3 different files used)
5. ⚠ Explanation engine missing coverage for P1, P2, P5 (non-critical)

---

## Detailed Findings

### 1. guild_scorer_v3.py (Core Scorer)

**Status**: ✓ FULLY ALIGNED

**Verification**:
- Implements all 11 metrics as documented in 4.4 (N1, N2, N4, N5, N6, P1-P6)
- Light boundaries consistent: `< 3.2` (shade), `> 7.47` (sun)
- P5 uses light-validated stratification formula (updated 2025-11-04)
- Data paths current: `perm2_11680_with_koppen_tiers_20251103.parquet`

**Formula verification**:
```python
# N4: CSR conflicts with light modulation (lines 614, 618)
if s_light < 3.2:    # Shade-adapted
    conflict = 0.0
elif s_light > 7.47: # Sun-loving
    conflict = 0.9

# P5: Stratification with light validation (lines 1018, 1021)
if short_light < 3.2:    # Shade-tolerant
    valid_stratification += height_diff
elif short_light > 7.47: # Sun-loving
    invalid_stratification += height_diff
else:                    # Flexible (3.2-7.47)
    valid_stratification += height_diff * 0.6
```

**Dependencies**:
- Plants: `model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet` ✓
- Organisms: `data/stage4/plant_organism_profiles.parquet` ✓
- Fungi: `data/stage4/plant_fungal_guilds_hybrid.parquet` ✓
- Relationships: `herbivore_predators.parquet`, `insect_fungal_parasites.parquet`, `pathogen_antagonists.parquet` ✓
- Normalization: `data/stage4/normalization_params_7plant.json` (needs recalibration after P5 update)

---

### 2. Data Path Inconsistencies

**Issue**: Three different plant datasets used across scripts

| Script | Dataset Used | Date | Status |
|--------|--------------|------|--------|
| guild_scorer_v3.py | koppen_tiers_20251103 | Nov 3 | ✓ Current |
| 01_extract_organism_profiles.py | ecoservices_20251030 | Oct 30 | ✗ Outdated |
| calibrate_normalizations_simple.py | climate_sensitivity_20251102 | Nov 2 | ⚠ Works but inconsistent |

**Dataset comparison**:
```
ecoservices (Oct 30):       775 cols, no Köppen zones
climate_sensitivity (Nov 2): 778 cols, no Köppen zones
koppen_tiers (Nov 3):       795 cols, WITH Köppen zones ← MOST COMPLETE
```

**All datasets contain required columns** (C, S, R, EIVEres-L, height_m, etc.), but **koppen_tiers is most recent and complete**.

**Action required**: Update all scripts to use `perm2_11680_with_koppen_tiers_20251103.parquet`

---

### 3. Organism Extraction (01_extract_organism_profiles.py)

**Status**: ✓ LOGIC CORRECT, ✗ PATH OUTDATED

**Alignment with 4.4**:
- ✓ Filters "no name" placeholder (implemented 2025-11-04)
- ✓ Extracts pollinators, herbivores, pathogens, flower visitors
- ✓ Excludes pollinators from herbivore list (correct logic)
- ✗ Uses `perm2_11680_with_ecoservices_20251030.parquet` (lines 38, 45)

**Fix needed**:
```python
# CHANGE FROM:
FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')

# CHANGE TO:
FROM read_parquet('model_data/outputs/perm2_production/perm2_11680_with_koppen_tiers_20251103.parquet')
```

**Output**: `data/stage4/plant_organism_profiles.parquet` (generated Oct 30, needs regeneration)

---

### 4. Calibration (calibrate_normalizations_simple.py)

**Status**: ✓ WORKS, ⚠ PATH INCONSISTENT

**Alignment with 4.4**:
- ✓ Generates percentile normalization parameters
- ✓ Uses correct metric implementations (N1-N6, P1-P6)
- ✗ Uses `perm2_11680_with_climate_sensitivity_20251102.parquet` (line 45)
- ⚠ P5 calibration parameters now OUTDATED (P5 formula changed with light validation)

**Fix needed**:
1. Update data path to koppen_tiers
2. Re-run calibration to capture new P5 distribution

**Output**: `data/stage4/normalization_params_7plant.json` (needs regeneration)

---

### 5. Fungal Guild Extraction (01_extract_fungal_guilds_hybrid.py)

**Status**: ✓ ALIGNED

**Verification**:
- Uses FungalTraits + FunGuild hybrid approach (documented in 4.1b)
- Extracts pathogenic, AMF, EMF, endophytic, saprotrophic, mycoparasite, entomopathogenic fungi
- Mycoparasite classification matches 4.1b documentation
- Output current: `data/stage4/plant_fungal_guilds_hybrid.parquet` (Nov 1)

---

### 6. Explanation Engine (explanation_engine.py)

**Status**: ✓ COMPATIBLE, ⚠ INCOMPLETE COVERAGE

**What it explains**:
- ✓ Climate veto reasons
- ✓ N1 (pathogen fungi overlap)
- ✓ N2 (herbivore overlap)
- ✓ N4 (CSR conflicts)
- ✓ P3 (beneficial fungi networks)
- ✓ P4 (phylogenetic diversity)
- ✓ P6 (shared pollinators)

**What it doesn't explain** (non-critical):
- ✗ P1 (cross-plant biocontrol) - score computed but no user-facing explanation
- ✗ P2 (pathogen antagonists) - score computed but no user-facing explanation
- ✗ P5 (vertical stratification) - score computed but no user-facing explanation

**Impact**: Low. Core scoring works correctly. Explanation engine provides generic positive score interpretation. Can be enhanced later for better user guidance.

---

### 7. Pipeline Scripts (03, 04)

**Status**: ✓ ALIGNED (Different Use Cases)

**03_compute_cross_plant_benefits.py**:
- Computes P1 biocontrol relationships
- Uses correct data files (organism profiles, herbivore predators)
- Pure DuckDB implementation (performant)

**04_compute_compatibility_matrix.py**:
- For Plant Doctor (2-plant pairwise compatibility)
- Different use case from guild builder (7-plant guilds)
- Still functional for its purpose

---

## Required Actions

### CRITICAL (Blocking calibration)

1. **Update organism extraction data path**
   - File: `src/Stage_4/01_extract_organism_profiles.py`
   - Change: Lines 38, 45 → use `koppen_tiers_20251103.parquet`
   - Reason: Consistency with scorer, ensures same plant set
   - Re-run: Generate new `plant_organism_profiles.parquet`

2. **Update calibration data path**
   - File: `src/Stage_4/calibrate_normalizations_simple.py`
   - Change: Line 45 → use `koppen_tiers_20251103.parquet`
   - Reason: Consistency across framework

3. **Recalibrate P5 percentiles**
   - Run: `calibrate_normalizations_simple.py`
   - Reason: P5 formula changed (light validation added), raw score distribution different
   - Output: New `normalization_params_7plant.json`

### RECOMMENDED (Non-blocking)

4. **Enhance explanation engine**
   - Add explanations for P1, P2, P5
   - Provide actionable guidance on stratification quality
   - Explain biocontrol mechanisms to users
   - Priority: Medium (after calibration)

5. **Audit other scripts using perm2 datasets**
   - Check Köppen zone scripts for consistency
   - Verify test scripts use correct data
   - Priority: Low

---

## Framework Validation Summary

| Component | 4.4 Alignment | Action Needed |
|-----------|---------------|---------------|
| **Metrics** | ✓ All 11 correct | None |
| **Light boundaries** | ✓ Consistent (3.2, 7.47) | None |
| **P5 implementation** | ✓ Light validation added | Recalibrate |
| **Data paths** | ✗ Inconsistent | Standardize to koppen_tiers |
| **Dependencies** | ✓ All files exist | Regenerate organism profiles |
| **Explanations** | ⚠ Partial coverage | Enhance engine (optional) |

---

## Next Steps (Ordered by Priority)

### Phase 1: Path Standardization (30 minutes)
1. Update `01_extract_organism_profiles.py` data path
2. Update `calibrate_normalizations_simple.py` data path
3. Re-run organism extraction (generates new profiles with koppen_tiers plant set)

### Phase 2: Recalibration (1-2 hours)
4. Run `calibrate_normalizations_simple.py` to generate new percentiles
5. Verify P5 distribution changed (lower scores expected due to light validation)
6. Test guild_scorer_v3.py with new normalization params

### Phase 3: Validation (30 minutes)
7. Test guild scorer on known guilds (valid vs invalid stratification)
8. Verify light validation working correctly
9. Check score distributions look reasonable

### Phase 4: Enhancement (Optional, 2-3 hours)
10. Add P1/P2/P5 explanations to explanation_engine.py
11. Create user-friendly stratification messages
12. Document biocontrol mechanisms for frontend

---

## Technical Notes

### Why Köppen Tiers is the Canonical Dataset

The `perm2_11680_with_koppen_tiers_20251103.parquet` file is the most recent (Nov 3) and includes:
- All 11,680 plants with WFO taxonomy
- EIVE predictions (L, T, M, N, R)
- CSR strategies (C, S, R)
- Functional traits (height, growth form, nitrogen fixation)
- Climate data (WorldClim bio variables)
- **Köppen climate zones** (n_koppen_zones column)
- Phylogenetic eigenvectors (92 dimensions)

**795 columns total**, most comprehensive version.

### Light Boundary Rationale

The boundaries `< 3.2` (shade) and `> 7.47` (sun) are derived from EIVE-L calibration:
- EIVE-L scale: 1-9
- Empirically calibrated to European flora
- Used consistently in N4 (CSR modulation) and P5 (stratification validation)
- Flexible range (3.2-7.47) receives 0.6 weight (partial compatibility)

### P5 Formula Change Impact

**Old P5**: Height diversity + form diversity (no light validation)
**New P5**: Light-validated stratification quality + form diversity

**Expected distribution shift**:
- Many "high diversity" guilds will score lower (invalid stratification exposed)
- Ecologically valid guilds maintain high scores
- Average P5 raw score expected to drop ~40% (based on overlap analysis)

**Calibration essential** to map new raw scores to [0, 1] percentile range.

---

**Document Status**: Complete
**Audit Result**: Framework solid, ready for recalibration after path fixes

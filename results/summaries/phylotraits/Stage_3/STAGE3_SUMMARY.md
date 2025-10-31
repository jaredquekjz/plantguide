# Stage 3 CSR: Complete Summary

**Date:** 2025-10-30
**Status:** PRODUCTION READY

---

## Quick Reference

### What This Stage Does
Calculates CSR (Competitor/Stress-tolerator/Ruderal) strategies for 11,680 plant species and predicts 10 ecosystem services using Shipley (2025) framework with life form stratification.

### Single Command Execution
```bash
bash src/Stage_3_CSR/run_full_csr_pipeline.sh
```
**Note:** Uses R implementation (canonical as of 2025-10-30)

### Final Output
`model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet`
- 11,680 species
- C, S, R scores (percentages summing to 100)
- 10 ecosystem service ratings (ordinal: Very Low/Low/Moderate/High/Very High)
- 10 confidence levels (Very High/High/Moderate)

---

## Methodological Foundation

### CSR Calculation: Pierce et al. (2016) StrateFy Method
**Inputs:** LA (mm²), LDMC (%), SLA (mm²/mg)
**Outputs:** C, S, R percentages summing to 100
**Method:** Globally calibrated equations from 3,068 species across 14 biomes
**Coverage:** 99.7% (11,650/11,680 species)

### Ecosystem Services: Shipley (2025) Parts I & II

**Part I (Base CSR Relationships):**
1. Decomposition (R ≈ C > S)
2. Nutrient Cycling (R ≈ C > S)
3. Nutrient Retention (C > S > R)
4. Nutrient Loss (R > S ≈ C)
5. Carbon Storage - Biomass (C > S > R)
6. Carbon Storage - Recalcitrant (S dominant)
7. Carbon Storage - Total (C ≈ S > R)
8. Erosion Protection (C > S > R)

**Part II Enhancements (NEW):**
9. **NPP with life form stratification:**
   - Herbaceous: NPP ∝ C-score only
   - Woody: NPP ∝ Height × C-score (accounts for biomass capital)
   - Formula: ΔB = B₀ × r × t (exponential growth model)
10. **Nitrogen Fixation:**
    - Fabaceae taxonomy (983 species flagged)
    - High rating for legumes, Low for non-legumes

---

## Data Flow

```
Stage 2 Output (11,680 species)
    ↓ [enrich_master_with_taxonomy.py]
Enriched with: family (99.3%), height (100%), life_form (78.8%), Fabaceae flag
    ↓ [Back-transform traits: LA, LDMC, SLA]
Traits ready for CSR calculation
    ↓ [calculate_stratefy_csr.py - StrateFy method]
CSR scores: C, S, R (99.7% coverage)
    ↓ [Merge back into master table]
Master + CSR (11,680 species × 749 columns)
    ↓ [compute_ecoservices_shipley.py - Shipley framework]
FINAL: Master + CSR + 10 Ecosystem Services (11,680 × 759 columns)
    ↓ [validate_shipley_part2.py]
Validation: ✓ All tests pass
```

---

## Key Validation Results

### NPP Life Form Stratification
- **Tall tree** (Cassia fistula, 22m, C=37.8) → NPP score = 8.31 → Very High ✓
- **Short herb** (Tephroseris helenitis, 0.5m, C=63.5) → NPP score = 0.64 → Very High ✓
- Woody species: 36.0% Very High vs Herbaceous: 10.0% Very High ✓

### Nitrogen Fixation
- 983/983 Fabaceae = High (100%) ✓
- 10,697/10,697 non-Fabaceae = Low (100%) ✓

### CSR Patterns
- NPP: C-dominant 56.9% Very High > R 0.9% > S 8.3% ✓
- Decomposition: R 54.2% Very High ≈ C 52.4% > S 68.5% Low ✓
- Nutrient Loss: R 54.2% Very High > C 52.4% Very Low ✓

### Data Quality
- CSR sum to 100: 11,650/11,680 (99.7%) ✓
- All services 100% complete (11,680/11,680) ✓
- Height coverage: 100% ✓
- Family coverage: 99.3% ✓

---

## File Locations

### Scripts
| Script | Purpose |
|--------|---------|
| `src/Stage_3/enrich_master_with_taxonomy.py` | Add family, height, life form, Fabaceae |
| `src/Stage_3_CSR/calculate_stratefy_csr.py` | Calculate CSR scores (StrateFy) |
| `src/Stage_3_CSR/compute_ecoservices_shipley.py` | Compute 10 ecosystem services |
| `src/Stage_3_CSR/validate_shipley_part2.py` | Validation tests |
| `src/Stage_3_CSR/run_full_csr_pipeline.sh` | **Master pipeline (use this)** |

### Documentation
| Document | Content |
|----------|---------|
| `Stage_3/CSR_methodology_and_ecosystem_services.md` | Complete methodology, formulas, references |
| `Stage_3/VERIFICATION_AND_REPRODUCTION.md` | Step-by-step verification, all tests documented |
| `Stage_3/Family_Detection_and_Taxonomy.md` | Taxonomic family detection for nitrogen fixation |
| `Stage_3/STAGE3_SUMMARY.md` | **This file** - quick reference |

### Data Outputs
| File | Description |
|------|-------------|
| `perm2_11680_enriched_stage3_20251030.parquet` | Master + taxonomy/height/life form |
| `perm2_11680_with_csr_20251030.parquet` | Master + CSR scores |
| `perm2_11680_with_ecoservices_20251030.parquet` | **FINAL OUTPUT** |

---

## Usage Examples

### Load Final Data
```python
import pandas as pd

df = pd.read_parquet('model_data/outputs/perm2_production/perm2_11680_with_ecoservices_20251030.parquet')

# Access CSR scores
csr = df[['wfo_scientific_name', 'C', 'S', 'R']]

# Access ecosystem services
services = df[['wfo_scientific_name',
               'npp_rating', 'decomposition_rating',
               'nutrient_cycling_rating', 'nutrient_retention_rating',
               'nutrient_loss_rating', 'carbon_total_rating',
               'erosion_protection_rating', 'nitrogen_fixation_rating']]

# Filter by dominant strategy
c_dominant = df[df['C'] >= 50]  # Competitor species
s_dominant = df[df['S'] >= 50]  # Stress-tolerator species
r_dominant = df[df['R'] >= 50]  # Ruderal species

# Filter by ecosystem service
high_npp = df[df['npp_rating'].isin(['High', 'Very High'])]  # Productive species
n_fixers = df[df['nitrogen_fixation_rating'] == 'High']      # Legumes
```

### Community-Weighted Ecosystem Services
```python
# Example: 3-species garden
species_mix = {
    'Quercus robur': 0.4,      # Oak (40% cover)
    'Trifolium repens': 0.3,   # Clover (30% cover)
    'Festuca rubra': 0.3       # Fescue (30% cover)
}

# Get species data
garden = df[df['wfo_scientific_name'].isin(species_mix.keys())]

# Calculate community-weighted NPP (numeric conversion for calculation)
rating_to_value = {'Very Low': 1, 'Low': 2, 'Moderate': 3, 'High': 4, 'Very High': 5}
garden['npp_value'] = garden['npp_rating'].map(rating_to_value)

# Weighted average
cwm_npp = sum(garden.set_index('wfo_scientific_name')['npp_value'][sp] * prop
              for sp, prop in species_mix.items())
print(f"Community-weighted NPP: {cwm_npp:.2f}")
```

---

## Confidence Levels Interpretation

| Level | Meaning | Services |
|-------|---------|----------|
| **Very High** | Extensive empirical evidence, mechanistic basis well-established | NPP, Decomposition, Nutrient Cycling, Nutrient Retention/Loss, Nitrogen Fixation |
| **High** | Good evidence but some uncertainty in mechanisms | Carbon Storage (Biomass, Recalcitrant, Total) |
| **Moderate** | Limited research, Shipley explicitly flags uncertainty | Erosion Protection |

---

## Limitations

### StrateFy Method (Pierce et al. 2016)

**Edge Case Failures: 30 species (0.26%) produce NaN CSR**
- **Cause:** Extreme trait combinations hit all three boundaries simultaneously (minC, minS, maxR)
- **Affected groups:** 21 Conifers (gymnosperms), 8 Halophytes, 1 Other
- **Examples:** Thuja occidentalis, Juniperus pseudosabina, Suaeda vera
- **Trait pattern:** Very low LDMC (6.94-16.52%) + low SLA (3-9) + small LA (1-24 mm²)
- **Root cause:** Fall outside angiosperm-based calibration space (3,068 species, Pierce et al. 2016)
- **Resolution:** Documented as known limitation; CSR = NaN retained (no arbitrary assignments)
- **Coverage:** 11,650/11,680 species (99.74%) with valid CSR scores
- **See:** `CSR_edge_case_analysis.md` for detailed investigation

### Shipley Framework (Ecosystem Services)

1. **Growing season constant:** t assumed same for all species (site-specific data needed for quantitative predictions)
2. **Height as biomass proxy:** Approximate; actual woody biomass requires allometric equations
3. **Thresholds empirical:** Calibrated from contrasting species examples, not validated against measured NPP
4. **Qualitative only:** Ratings for comparative purposes, not absolute quantitative predictions
5. **Site-specificity:** Trait effects modulated by environment; requires site-level data for quantitative models

---

## References

**Core Methods:**
- Pierce et al. (2016) *Functional Ecology* 31:444-457 - Global CSR method (StrateFy)
- Grime (2001) *Plant Strategies, Vegetation Processes, and Ecosystem Properties*

**Ecosystem Services:**
- Shipley (2025) Personal communication Part I - CSR and ecosystem services (qualitative)
- Shipley (2025) Personal communication Part II - Life form adjustments, nitrogen fixation
- Garnier & Navas (2013) *Diversité fonctionnelle des plantes*
- Vile et al. (2006) *Ecology Letters* 9:1061-1067 - NPP from RGR_max

---

## Troubleshooting

**Issue:** Pipeline fails with missing conda environment
**Solution:** `conda activate AI` before running

**Issue:** Input file not found
**Solution:** Ensure Stage 2 output exists: `perm2_11680_complete_final_20251028.parquet`

**Issue:** CSR scores missing (NaN)
**Solution:** Check LA/LDMC/SLA are all positive, non-zero values

**Issue:** Validation tests fail
**Solution:** Check intermediate outputs exist and have expected row counts

**Issue:** Need to rerun single step
**Solution:** Use manual commands from VERIFICATION_AND_REPRODUCTION.md

---

## Status: Production Ready ✓

- [x] Methodology finalized and documented
- [x] Scripts canonical and tested
- [x] Pipeline automated and validated
- [x] All 10 ecosystem services implemented
- [x] Shipley Part I & II fully integrated
- [x] Validation tests passing
- [x] Data quality verified
- [x] Documentation complete

**Ready for:**
- Downstream analyses
- Integration with gardening recommendations
- Multi-species community predictions
- Ecosystem service trade-off analyses

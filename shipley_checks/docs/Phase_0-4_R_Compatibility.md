# Phase 0-4 R Pipeline Compatibility

**Date:** 2025-11-17
**Status:** ✓ VERIFIED - R arrow can consume all Phase 0-4 DuckDB parquets

## Summary

The Phase 0-4 pipeline outputs (DuckDB `COPY TO` parquets) are **fully compatible** with R's arrow package. All required data is present and list columns work directly without conversion.

## Phase 0-4 Outputs Tested

### Phase 4 Final Dataset
**File:** `shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet`
- **Size:** 11,713 plants × 861 columns
- **CSR Scores:** C, S, R columns (0-100 range, 99.86% complete)
- **Köppen Tiers:** 6 boolean columns (tier_1_tropical through tier_6_arid)
- **Ecosystem Services:** 10 services with ratings + confidence levels
- **Vernaculars:** 61 languages
- **Heights:** height_m column (100% complete, 0.001-90m range)

**Köppen Tier Coverage:**
- tier_1_tropical: 1,659 plants
- tier_2_mediterranean: 4,086 plants
- tier_3_humid_temperate: 8,835 plants
- tier_4_continental: 4,404 plants
- tier_5_boreal_polar: 964 plants
- tier_6_arid: 2,413 plants

### Phase 0 Organism Data
**File:** `shipley_checks/validation/organism_profiles_pure_rust.parquet`
- **Size:** 11,711 plants × 17 columns
- **List columns:** pollinators, herbivores, flower_visitors, predators (3 types), fungivores_eats
- **Fungivore data:** 1,333 plants (11.38%) have fungivores - CRITICAL for M4 parity

### Phase 0 Fungal Data
**File:** `shipley_checks/validation/fungal_guilds_pure_rust.parquet`
- **Size:** 11,711 plants × 26 columns
- **List columns:** 8 fungal guild types (pathogenic, AMF, EMF, mycoparasite, etc.)
- **All mechanisms covered:** Pathogens, mycoparasites, biocontrol fungi

## Key Findings

### 1. Arrow List Columns Work Directly

DuckDB stores list columns as native Arrow list types, not pipe-separated strings.

**Current R CSV approach:**
```r
# CSV files with pipe-separated strings
organisms_df <- read_csv('organism_profiles_pure_r.csv') %>%
  csv_to_lists(c('pollinators', 'herbivores', ...))
```

**New R parquet approach:**
```r
# Parquet files with native lists - NO conversion needed
organisms_df <- read_parquet('organism_profiles_pure_rust.parquet')
# Lists already present and work with R operations
```

**Verified operations:**
- `length(df$pollinators[[1]])` ✓ Works
- `intersect(list_a, list_b)` ✓ Works
- Iteration in loops ✓ Works
- All M4 code patterns ✓ Compatible

### 2. Data Schema Matches Requirements

**Plants dataset (Phase 4):**
- ✓ CSR scores: C, S, R (not c_score, s_score, r_score)
- ✓ Köppen tiers: tier_1_tropical through tier_6_arid
- ✓ Heights: height_m column
- ✓ Ecosystem services: All 10 services present
- ✓ Nitrogen fixation: nitrogen_fixation_rating column

**Organism dataset (Phase 0):**
- ✓ All predator types (hasHost, interactsWith, adjacentTo)
- ✓ Pollinators and flower visitors
- ✓ **Fungivores** (NEW - critical for M4 parity)

**Fungal dataset (Phase 0):**
- ✓ Pathogenic fungi (general + host-specific)
- ✓ Mycoparasites
- ✓ Mycorrhizae (AMF + EMF)
- ✓ Biocontrol fungi (entomopathogenic)

### 3. Fungivore Data Available

**Critical for R-Rust M4 parity:**
- Fungivore column: `fungivores_eats` (Arrow list type)
- Coverage: 1,333 plants (11.38%)
- Example: "Mycodiplosis erysiphes" (fungus gnat eating fungi)
- Required for Mechanism 3 in M4 (fungivores eating pathogens)

## Required Changes to R Pipeline

### guild_scorer_v3_shipley.R

**Current data loading (lines 90-127):**
```r
# Plants from parquet
self$plants_df <- read_parquet('shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet')

# Organisms from CSV
self$organisms_df <- read_csv('shipley_checks/validation/organism_profiles_pure_r.csv') %>%
  csv_to_lists(c('herbivores', 'flower_visitors', 'pollinators', ...))

# Fungi from CSV
self$fungi_df <- read_csv('shipley_checks/validation/fungal_guilds_pure_r.csv') %>%
  csv_to_lists(c('pathogenic_fungi', 'amf_fungi', ...))
```

**Updated for Phase 0-4 (parquet only):**
```r
# Plants from Phase 4 output
self$plants_df <- read_parquet('shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet')

# Organisms from Phase 0 output - lists already present
self$organisms_df <- read_parquet('shipley_checks/validation/organism_profiles_pure_rust.parquet')

# Fungi from Phase 0 output - lists already present
self$fungi_df <- read_parquet('shipley_checks/validation/fungal_guilds_pure_rust.parquet')

# NO csv_to_lists() needed - Arrow lists work directly!
```

**Additional changes needed:**
1. Remove `csv_to_lists()` helper function (no longer needed)
2. Update M4 to include fungivore mechanism (R-Rust parity)
3. Verify column name changes: `C`, `S`, `R` (not c_score, s_score, r_score)
4. Verify Köppen tier columns: `tier_1_tropical` through `tier_6_arid` (not single `koppen_tier`)

## Verification Test

**Test script:** `/home/olier/ellenberg/test_r_parquet_compatibility.R`

**Results:**
- ✓ All Phase 0-4 parquets readable by R arrow
- ✓ Arrow list operations work identically to R lists
- ✓ M4 code patterns verified (pathogen-mycoparasite + fungivore logic)
- ✓ All required columns present
- ✓ No data loss or corruption

**Run test:**
```bash
env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
  /usr/bin/Rscript test_r_parquet_compatibility.R
```

## Next Steps (R-Rust M4 Parity)

Before proceeding with Rust calibration, R must reach parity with Rust M4:

1. **Update R data loading** (30 min)
   - Switch to Phase 0-4 parquets
   - Remove csv_to_lists() calls
   - Update column names (C/S/R, Köppen tiers)

2. **Add M4 Mechanism 3** (1 hour)
   - Implement fungivore-pathogen logic in R M4
   - Weight: 0.2 per fungivore (matches Rust)
   - Location: `compute_metric_m4_disease_control()` function

3. **Verify local parity** (30 min)
   - Test 3 guilds with both R and Rust
   - Compare M4 scores and mechanisms
   - Ensure exact match before calibration

## Conclusion

**Phase 0-4 DuckDB parquets are R-friendly.** No compatibility issues found. Arrow list types work seamlessly with R operations.

**Action:** Update R pipeline to use Phase 0-4 parquets, then proceed with M4 parity verification.

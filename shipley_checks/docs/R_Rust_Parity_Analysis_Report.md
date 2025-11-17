# R-Rust Guild Scorer Parity Analysis Report

**Date**: 2025-11-17
**Analyst**: Claude Code
**Status**: INCOMPLETE - Critical discrepancies remain

---

## Executive Summary

Systematic comparison of R (`guild_scorer_v3_shipley.R`) and Rust metric implementations revealed:

- ✅ **5 metrics have PERFECT PARITY**: M1, M2, M4, M5, M6
- ❌ **2 metrics have LOGIC DISCREPANCIES**: M3, M7
- ⚠️  **Fixes attempted but failed** - Root cause not yet identified

### Current Test Results

| Guild | Expected (R) | Rust | Difference | Status |
|-------|--------------|------|------------|--------|
| Forest Garden | 90.467710 | 89.744125 | 0.723585 | ❌ FAIL |
| Competitive Clash | 53.011553 | 53.011554 | 0.000001 | ✅ PERFECT |
| Stress-Tolerant | 42.380873 | 42.380900 | 0.000027 | ✅ PERFECT |

**Guild 1 (Forest Garden) Raw Score Discrepancies:**

| Metric | R Value | Rust Value | Match? |
|--------|---------|------------|--------|
| M1 | 0.4296931 | 0.429693 | ✅ YES |
| M2 | 0.0 | 0.0 | ✅ YES |
| M3 | **6.0** | **5.238095** | ❌ NO (Rust 12.7% lower) |
| M4 | 10.85714 | 10.857143 | ✅ YES |
| M5 | 5.085714 | 5.085714 | ✅ YES |
| M6 | 0.88 | 0.880000 | ✅ YES |
| M7 | **0.4081633** | **0.163265** | ❌ NO (Rust 60% lower) |

---

## Detailed Metric Analysis

### M1: Pest & Pathogen Independence ✅

**Status**: PERFECT PARITY

| Component | R | Rust | Match |
|-----------|---|------|-------|
| Faith's PD calculation | `phylo_calculator$calculate_pd()` | `phylo_calculator.calculate_pd()` | ✅ |
| Decay constant | `k <- 0.001` | `const K: f64 = 0.001` | ✅ |
| Formula | `exp(-k * faiths_pd)` | `(-K * faiths_pd).exp()` | ✅ |
| Normalization | percentile_normalize(..., 'm1') | percentile_normalize(..., "m1") | ✅ |

**Conclusion**: No issues found

---

### M2: Growth Compatibility (CSR Conflicts) ✅

**Status**: PERFECT PARITY

All conflict calculations, light modulation thresholds, and height modulation factors match exactly between R and Rust.

**Conclusion**: No issues found

---

### M3: Beneficial Insect Networks (Biocontrol) ❌

**Status**: CRITICAL DISCREPANCY - Rust scores 12.7% lower than R

#### Identified Issue

**R Implementation** (lines 536-551):
Aggregates predators from 4 columns:
- `flower_visitors`
- `predators_hasHost`
- `predators_interactsWith`
- `predators_adjacentTo`

**Rust Implementation** (lines 398-403 in extract_predator_data):
Currently uses 4 columns (after fix attempt):
- `flower_visitors`
- `predators_hasHost`
- `predators_interactsWith`
- `predators_adjacentTo`

**Fix Attempted**: Added `flower_visitors` to `extract_predator_data()` but scores still don't match.

**Current Hypothesis**: There may be additional logic differences in:
1. How predators are aggregated/deduplicated
2. How predator matches are counted
3. Mechanism weighting or normalization

**Files Affected**:
- `/home/olier/ellenberg/shipley_checks/src/Stage_4/guild_scorer_rust/src/metrics/m3_insect_control.rs`

**R Reference**:
- `/home/olier/ellenberg/shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R` lines 502-626

---

### M4: Disease Suppression ✅

**Status**: PERFECT PARITY (after fix)

**Fix Applied**: Changed Mechanism 3 (fungivores) from specific matching (weight 1.0) to general matching (weight 0.2) to match R implementation.

**Conclusion**: No further issues

---

### M5: Beneficial Fungi Networks ✅

**Status**: PERFECT PARITY (after earlier fix for list columns)

**Conclusion**: No issues found

---

### M6: Structural Diversity ✅

**Status**: PERFECT PARITY (after column fix)

**Fix Applied**: Changed R to use `EIVEres-L_complete` instead of `EIVEres-L` for consistent use of imputed values.

**Conclusion**: No issues found

---

### M7: Pollinator Support ❌

**Status**: CRITICAL DISCREPANCY - Rust scores 60% lower than R

#### Identified Issue

**R Implementation** (lines 904-907):
```r
shared_pollinators <- self$count_shared_organisms(
  self$organisms_df, plant_ids,
  'pollinators', 'flower_visitors'  # Uses 2 columns
)
```

**Rust Implementation** (lines 85-89):
```rust
let shared_pollinators = count_shared_organisms(
    &guild_organisms,
    &guild_plant_ids,
    &["pollinators", "flower_visitors"],  // Updated to use 2 columns
)?;
```

**Fix Attempted**: Changed Rust from 1 column to 2 columns, but scores still don't match.

**Current Hypothesis**: There may be differences in:
1. How `count_shared_organisms` aggregates data from multiple columns
2. Data format differences between R and Rust parquets
3. Deduplication logic

**Files Affected**:
- `/home/olier/ellenberg/shipley_checks/src/Stage_4/guild_scorer_rust/src/metrics/m7_pollinator_support.rs`
- `/home/olier/ellenberg/shipley_checks/src/Stage_4/guild_scorer_rust/src/utils/organism_counter.rs`

**R Reference**:
- `/home/olier/ellenberg/shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R` lines 898-929

---

## Data Consistency Issues

### Parquet File Usage

**R loads**:
- Plants: `shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711_polars.parquet`
- Organisms: `shipley_checks/validation/organism_profiles_pure_rust.parquet`
- Fungi: `shipley_checks/validation/fungal_guilds_pure_rust.parquet`

**Rust loads**:
- Plants: `shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711_polars.parquet`
- Organisms: `shipley_checks/validation/organism_profiles_pure_rust.parquet`
- Fungi: `shipley_checks/validation/fungal_guilds_pure_rust.parquet`

**Status**: ✅ Both use same files (after fix)

### Column Usage

**Light Preference**:
- ✅ Both now use `EIVEres-L_complete` (imputed values)

**Organism Columns**:
- ⚠️ Potential differences in how list columns are parsed/aggregated

---

## Fixes Applied

### Successful Fixes

1. ✅ **M4 Mechanism 3**: Changed from specific fungivore matching (weight 1.0) to general (weight 0.2)
2. ✅ **M5 Coverage Ratio**: Fixed list column parsing in `count_plants_with_beneficial_fungi()`
3. ✅ **M6 Light Preference**: Changed R to use `EIVEres-L_complete` column
4. ✅ **Data Files**: Updated R to use same parquet files as Rust

### Failed Fixes

1. ❌ **M3 Predator Columns**: Added `flower_visitors` to `extract_predator_data()` but scores still differ
2. ❌ **M7 Pollinator Columns**: Changed to use 2 columns but scores still differ

---

## Recommended Next Steps

### Immediate Actions

1. **Debug M3 Guild 1 in Detail**:
   - Add debug logging to both R and Rust M3 calculations for Guild 1
   - Compare intermediate values:
     - Number of herbivores per plant
     - Number of predators per plant
     - Number of biocontrol matches
     - Biocontrol raw score before normalization

2. **Debug M7 Guild 1 in Detail**:
   - Add debug logging to `count_shared_organisms()` in both R and Rust
   - Compare:
     - Number of pollinators from each column
     - Total unique pollinators after merging
     - Overlap ratios
     - Quadratic scores

3. **Verify Data Integrity**:
   - Confirm that parquet files contain identical data
   - Check for differences in how Arrow list columns are parsed
   - Verify deduplication logic produces same results

### Investigation Commands

```bash
# Test individual metrics for Guild 1
cd /home/olier/ellenberg/shipley_checks/src/Stage_4/guild_scorer_rust
cargo run --bin test_single_guild

# Run R version with debug output
cd /home/olier/ellenberg/shipley_checks/src/Stage_4
Rscript test_guild_debug.R
```

---

## Appendix: Comparison Methodology

### Tools Used
- Task tool with Explore agent for systematic code comparison
- Manual line-by-line verification of critical components
- Test-driven validation with 3-guild test suite

### Metrics Analyzed
All 7 metrics (M1-M7) were systematically compared for:
1. Calculation formulas
2. Weighting factors
3. Normalization factors
4. Mechanism counts
5. Data filtering logic
6. Column usage

### Known Limitations
- Some discrepancies may exist in subtle implementation details not captured by static code analysis
- Data parsing differences may only be visible through runtime debugging
- Edge cases may behave differently between R and Rust

---

## Conclusion

While significant progress was made in achieving R-Rust parity (5 of 7 metrics now match perfectly), two critical discrepancies remain in M3 and M7. These require deeper investigation through runtime debugging to identify the root causes.

The fixes applied successfully resolved issues in M4, M5, M6, and data consistency, but the remaining M3/M7 discrepancies suggest subtle logic differences that are not apparent from static code analysis alone.

**Next session should focus on**: Runtime debugging of M3 and M7 for Guild 1 with detailed intermediate value logging.

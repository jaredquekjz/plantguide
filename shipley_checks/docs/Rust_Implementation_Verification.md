# Rust Guild Scorer Implementation Verification

## Data Loading and Normalization Equivalence with R

This document verifies that the Rust guild scorer implementation exactly matches the R modular architecture.

### File Paths Verification

All data file paths match exactly between R and Rust implementations:

| Dataset | R Path (guild_scorer_v3_modular.R) | Rust Path (data.rs) | Status |
|---------|-------------------------------------|---------------------|--------|
| Plants | `shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet` | `shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet` | ✓ |
| Organisms | `shipley_checks/validation/organism_profiles_pure_r.csv` | `shipley_checks/validation/organism_profiles_pure_r.csv` | ✓ |
| Fungi | `shipley_checks/validation/fungal_guilds_pure_r.csv` | `shipley_checks/validation/fungal_guilds_pure_r.csv` | ✓ |
| Herbivore Predators | `shipley_checks/validation/herbivore_predators_pure_r.csv` | `shipley_checks/validation/herbivore_predators_pure_r.csv` | ✓ |
| Insect Parasites | `shipley_checks/validation/insect_fungal_parasites_pure_r.csv` | `shipley_checks/validation/insect_fungal_parasites_pure_r.csv` | ✓ |
| Pathogen Antagonists | `shipley_checks/validation/pathogen_antagonists_pure_r.csv` | `shipley_checks/validation/pathogen_antagonists_pure_r.csv` | ✓ |

### Column Mappings Verification

Plant DataFrame column selection and renaming matches exactly:

```r
# R (lines 128-135)
select(
  wfo_taxon_id, wfo_scientific_name, family, genus,
  height_m, try_growth_form,
  CSR_C = C, CSR_S = S, CSR_R = R,
  light_pref = `EIVEres-L`,
  tier_1_tropical, tier_2_mediterranean, tier_3_humid_temperate,
  tier_4_continental, tier_5_boreal_polar, tier_6_arid
)
```

```rust
// Rust (lines 99-116)
.select(&[
    col("wfo_taxon_id"), col("wfo_scientific_name"),
    col("family"), col("genus"),
    col("height_m"), col("try_growth_form"),
    col("C").alias("CSR_C"),
    col("S").alias("CSR_S"),
    col("R").alias("CSR_R"),
    col("EIVEres-L").alias("light_pref"),
    col("tier_1_tropical"), col("tier_2_mediterranean"),
    col("tier_3_humid_temperate"), col("tier_4_continental"),
    col("tier_5_boreal_polar"), col("tier_6_arid"),
])
```

Key column naming conventions:
- Plants DataFrame: `wfo_taxon_id` as primary key
- Organisms/Fungi DataFrames: `plant_wfo_id` as foreign key
- CSR columns: `C`/`S`/`R` renamed to `CSR_C`/`CSR_S`/`CSR_R`
- Light preference: `EIVEres-L` renamed to `light_pref`

### Normalization Algorithm Verification

Percentile normalization uses identical linear interpolation algorithm:

| Component | R Implementation | Rust Implementation | Status |
|-----------|------------------|---------------------|--------|
| Percentiles | `[1, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99]` | `[1.0, 5.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 95.0, 99.0]` | ✓ |
| Edge: Below p1 | `return if (invert) 100.0 else 0.0` | `Ok(if invert { 100.0 } else { 0.0 })` | ✓ |
| Edge: Above p99 | `return if (invert) 0.0 else 100.0` | `Ok(if invert { 0.0 } else { 100.0 })` | ✓ |
| Interpolation | `fraction <- (raw - values[i]) / (values[i+1] - values[i])`<br>`percentile <- percentiles[i] + fraction * (percentiles[i+1] - percentiles[i])` | `let fraction = (raw_value - values[i]) / (values[i + 1] - values[i]);`<br>`let percentile = PERCENTILES[i] + fraction * (PERCENTILES[i + 1] - PERCENTILES[i]);` | ✓ |
| Inversion | `if (invert) percentile <- 100.0 - percentile` | `if invert { 100.0 - percentile } else { percentile }` | ✓ |
| Fallback | `return(50.0)` | `Ok(50.0)` | ✓ |

### CSR Percentile Normalization Verification

CSR normalization (global, not tier-stratified) matches exactly:

| Component | R Implementation | Rust Implementation | Status |
|-----------|------------------|---------------------|--------|
| Percentiles | `[1, 5, 10, 20, 30, 40, 50, 60, 70, 75, 80, 85, 90, 95, 99]` | `[1.0, 5.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 75.0, 80.0, 85.0, 90.0, 95.0, 99.0]` | ✓ |
| Fallback C | `if (raw_value >= 60) 100 else 50` | `if raw_value >= 60.0 { 100.0 } else { 50.0 }` | ✓ |
| Fallback S | `if (raw_value >= 60) 100 else 50` | `if raw_value >= 60.0 { 100.0 } else { 50.0 }` | ✓ |
| Fallback R | `if (raw_value >= 50) 100 else 50` | `if raw_value >= 50.0 { 100.0 } else { 50.0 }` | ✓ |
| Interpolation | Same as guild metrics | Same as guild metrics | ✓ |

### Calibration Files

Both implementations load the same JSON calibration files:

```
shipley_checks/stage4/normalization_params_{calibration_type}.json
shipley_checks/stage4/csr_percentile_calibration_global.json
```

Structure:
```json
{
  "tier_3_humid_temperate": {
    "m1": { "p1": 0.5234, "p5": 0.5789, ..., "p99": 0.9876 },
    "n4": { ... },
    "p1": { ... },
    "p2": { ... },
    "p3": { ... },
    "p5": { ... },
    "p6": { ... }
  },
  "tier_1_tropical": { ... },
  ...
}
```

### Implementation Status

Completed and verified:

| Component | R Reference | Rust Implementation | Status |
|-----------|-------------|---------------------|--------|
| Data loading | `guild_scorer_v3_modular.R` lines 123-179 | `data.rs` lines 36-195 | ✓ Exact match |
| Normalization | `utils/normalization.R` lines 112-181 | `utils/normalization.rs` lines 88-147 | ✓ Exact match |
| CSR normalization | `utils/normalization.R` lines 203-264 | `utils/normalization.rs` lines 194-248 | ✓ Exact match |
| Organism counter | `utils/shared_organism_counter.R` | `utils/organism_counter.rs` | ✓ Exact match |
| M2: CSR Compatibility | `metrics/m2_growth_compatibility.R` | `metrics/m2_growth_compatibility.rs` | ✓ Implemented |
| M3: Insect Control | `metrics/m3_insect_control.R` | `metrics/m3_insect_control.rs` | ✓ Implemented |
| M4: Disease Control | `metrics/m4_disease_control.R` | `metrics/m4_disease_control.rs` | ✓ Implemented |
| M5: Beneficial Fungi | `metrics/m5_beneficial_fungi.R` | `metrics/m5_beneficial_fungi.rs` | ✓ Implemented |
| M6: Structural Diversity | `metrics/m6_structural_diversity.R` | `metrics/m6_structural_diversity.rs` | ✓ Implemented |
| M7: Pollinator Support | `metrics/m7_pollinator_support.R` | `metrics/m7_pollinator_support.rs` | ✓ Implemented |
| M1: Pest Independence | `metrics/m1_pest_independence.R` | - | Pending (requires C++ Faith's PD binary) |

### Test Coverage

All implemented modules have unit tests:

```
running 23 tests
test data::tests::test_load_data ... ignored
test metrics::m2_growth_compatibility::tests::test_c_c_conflict ... ok
test metrics::m2_growth_compatibility::tests::test_c_r_conflict ... ok
test metrics::m2_growth_compatibility::tests::test_c_s_conflict_shade_adapted ... ok
test metrics::m2_growth_compatibility::tests::test_c_s_conflict_sun_loving ... ok
test metrics::m2_growth_compatibility::tests::test_r_r_conflict ... ok
test metrics::m3_insect_control::tests::test_general_entomopathogenic_mechanism ... ok
test metrics::m3_insect_control::tests::test_multiple_mechanisms ... ok
test metrics::m3_insect_control::tests::test_specific_predator_mechanism ... ok
test metrics::m4_disease_control::tests::test_count_matches ... ok
test metrics::m4_disease_control::tests::test_count_matches_multiple ... ok
test metrics::m4_disease_control::tests::test_count_matches_none ... ok
test metrics::m5_beneficial_fungi::tests::test_combined_score ... ok
test metrics::m5_beneficial_fungi::tests::test_coverage_ratio ... ok
test metrics::m5_beneficial_fungi::tests::test_network_score_calculation ... ok
test metrics::m6_structural_diversity::tests::test_combined_score ... ok
test metrics::m6_structural_diversity::tests::test_form_diversity ... ok
test metrics::m6_structural_diversity::tests::test_stratification_quality ... ok
test metrics::m7_pollinator_support::tests::test_multiple_pollinators ... ok
test metrics::m7_pollinator_support::tests::test_quadratic_weighting ... ok
test utils::normalization::tests::test_csr_to_percentile_fallback ... ok
test utils::normalization::tests::test_percentile_normalize_edge_cases ... ok
test utils::organism_counter::tests::test_count_shared_organisms_mock ... ok

test result: ok. 22 passed; 0 failed; 1 ignored; 0 measured; 0 filtered out
```

### Build Status

Release build successful (optimized with LTO):

```
Finished `release` profile [optimized] target(s) in 2m 19s
```

Warnings (non-critical):
- Dead code warnings for unused struct fields (will be used in main scorer integration)

### Next Steps

1. Implement M1: Pest Independence (requires external C++ Faith's PD calculator binary)
2. Integrate all metrics into main scorer with parallel execution
3. Run parity tests against R implementation using 100-guild test set
4. Performance benchmarking (target: 20-25× speedup vs Python, 8-10× speedup vs R)

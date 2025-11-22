# Script Path Update Plan

## Principle
- **Source data** stays in `data/` (don't move)
- **BILL_VERIFIED CSV** stays in `shipley_checks/stage3/`
- **Phase outputs** organized in `shipley_checks/stage4/phaseX_output/`
- **All intermediate files** will be regenerated (don't keep old ones)

## Path Mappings

### Phase 0 Outputs (GloBI Extraction)
```
OLD: shipley_checks/phase0_output/*.parquet
NEW: shipley_checks/stage4/phase0_output/*.parquet
```

### Phase 1 Outputs (Vernaculars)
```
OLD: data/taxonomy/plants_vernacular_normalized.parquet
NEW: shipley_checks/stage4/phase1_output/plants_vernacular_normalized.parquet
```

### Phase 2 Output (Kimi - kept, not regenerated)
```
KEEP: data/taxonomy/animal_genera_with_vernaculars.parquet
NEW: shipley_checks/stage4/phase2_output/animal_genera_with_vernaculars.parquet (symlink)
```

### Phase 3 Outputs (Köppen)
```
OLD: data/taxonomy/bill_with_koppen_only_11711.parquet
OLD: data/stage4/plant_koppen_distributions_11711.parquet
NEW: shipley_checks/stage4/phase3_output/bill_with_koppen_only_11711.parquet
NEW: shipley_checks/stage4/phase3_output/plant_koppen_distributions_11711.parquet
```

### Phase 4 Output (Merged)
```
OLD: shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet
NEW: shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet
```

### Phase 5 Outputs (Calibration)
```
OLD: shipley_checks/stage4/csr_percentile_calibration_global.json
OLD: shipley_checks/stage4/normalization_params_*.json
NEW: shipley_checks/stage4/phase5_output/csr_percentile_calibration_global.json
NEW: shipley_checks/stage4/phase5_output/normalization_params_*.json
```

## Files to Update

### 1. Rust Guild Scorer (guild_scorer_rust/src/data.rs)

**Current paths:**
```rust
let plants_path = "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet";
let organisms_path = "shipley_checks/phase0_output/organism_profiles_11711.parquet";
let fungi_path = "shipley_checks/phase0_output/fungal_guilds_hybrid_11711.parquet";
"shipley_checks/phase0_output/herbivore_predators_11711.parquet"
"shipley_checks/phase0_output/insect_fungal_parasites_11711.parquet"
"shipley_checks/phase0_output/pathogen_antagonists_11711.parquet"
```

**New paths:**
```rust
let plants_path = "shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet";
let organisms_path = "shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet";
let fungi_path = "shipley_checks/stage4/phase0_output/fungal_guilds_hybrid_11711.parquet";
"shipley_checks/stage4/phase0_output/herbivore_predators_11711.parquet"
"shipley_checks/stage4/phase0_output/insect_fungal_parasites_11711.parquet"
"shipley_checks/stage4/phase0_output/pathogen_antagonists_11711.parquet"
```

### 2. Rust Calibration (guild_scorer_rust/src/scorer.rs)

**Current:**
```rust
"shipley_checks/stage4/normalization_params_{}.json"
```

**New:**
```rust
"shipley_checks/stage4/phase5_output/normalization_params_{}.json"
```

### 3. R Guild Scorer (guild_scorer_v3_shipley.R)

**Current paths (lines 58, 67, 96, 107, 110, 116, 125, 134):**
```r
cal_file <- glue("shipley_checks/stage4/normalization_params_{calibration_type}.json")
csr_cal_file <- "shipley_checks/stage4/csr_percentile_calibration_global.json"
self$plants_df <- read_parquet('shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet')
self$organisms_df <- read_parquet('shipley_checks/phase0_output/organism_profiles_11711.parquet')
self$fungi_df <- read_parquet('shipley_checks/phase0_output/fungal_guilds_hybrid_11711.parquet')
pred_df <- read_parquet('shipley_checks/phase0_output/herbivore_predators_11711.parquet')
para_df <- read_parquet('shipley_checks/phase0_output/insect_fungal_parasites_11711.parquet')
antag_df <- read_parquet('shipley_checks/phase0_output/pathogen_antagonists_11711.parquet')
```

**New paths:**
```r
cal_file <- glue("shipley_checks/stage4/phase5_output/normalization_params_{calibration_type}.json")
csr_cal_file <- "shipley_checks/stage4/phase5_output/csr_percentile_calibration_global.json"
self$plants_df <- read_parquet('shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet')
self$organisms_df <- read_parquet('shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet')
self$fungi_df <- read_parquet('shipley_checks/stage4/phase0_output/fungal_guilds_hybrid_11711.parquet')
pred_df <- read_parquet('shipley_checks/stage4/phase0_output/herbivore_predators_11711.parquet')
para_df <- read_parquet('shipley_checks/stage4/phase0_output/insect_fungal_parasites_11711.parquet')
antag_df <- read_parquet('shipley_checks/stage4/phase0_output/pathogen_antagonists_11711.parquet')
```

### 4. Phase 0 Scripts (Phase_0_extraction/*.R)

**Output paths:**
```r
# All writes should go to:
"shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet"
"shipley_checks/stage4/phase0_output/fungal_guilds_hybrid_11711.parquet"
etc.
```

### 5. Phase 1 Scripts (Phase_1_multilingual/assign_vernacular_names.R)

**Output path:**
```r
OUTPUT_FILE <- "shipley_checks/stage4/phase1_output/plants_vernacular_normalized.parquet"
```

### 6. Phase 3 Scripts (Phase_3_koppen/*.py)

**Current:**
```python
KOPPEN_FILE = PROJECT_ROOT / "data/stage4/plant_koppen_distributions_11711.parquet"
OUTPUT_FILE = PROJECT_ROOT / "data/taxonomy/bill_with_koppen_only_11711.parquet"
```

**New:**
```python
KOPPEN_FILE = PROJECT_ROOT / "shipley_checks/stage4/phase3_output/plant_koppen_distributions_11711.parquet"
OUTPUT_FILE = PROJECT_ROOT / "shipley_checks/stage4/phase3_output/bill_with_koppen_only_11711.parquet"
```

### 7. Phase 4 Script (Phase_4_merge/merge_taxonomy_koppen.py)

**Current:**
```python
VERNACULAR_FILE = PROJECT_ROOT / "data/taxonomy/plants_vernacular_normalized.parquet"
KOPPEN_FILE = PROJECT_ROOT / "data/taxonomy/bill_with_koppen_only_11711.parquet"
OUTPUT_FILE = PROJECT_ROOT / "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet"
```

**New:**
```python
VERNACULAR_FILE = PROJECT_ROOT / "shipley_checks/stage4/phase1_output/plants_vernacular_normalized.parquet"
KOPPEN_FILE = PROJECT_ROOT / "shipley_checks/stage4/phase3_output/bill_with_koppen_only_11711.parquet"
OUTPUT_FILE = PROJECT_ROOT / "shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet"
```

### 8. Phase 5 Calibration Scripts

**R calibration (calibration/generate_csr_percentile_calibration.R):**
```r
INPUT_PARQUET <- "shipley_checks/stage4/phase4_output/bill_with_csr_ecoservices_koppen_vernaculars_11711.parquet"
OUTPUT_FILE <- "shipley_checks/stage4/phase5_output/csr_percentile_calibration_global.json"
```

**Rust calibration (guild_scorer_rust/src/bin/calibrate_koppen_stratified.rs):**
```rust
// Outputs to:
let output_path_2plant = "shipley_checks/stage4/phase5_output/normalization_params_2plant.json";
let output_path_7plant = "shipley_checks/stage4/phase5_output/normalization_params_7plant.json";
```

### 9. Master Pipeline (run_complete_pipeline_phase0_to_4.sh)

**Log outputs:**
```bash
# Redirect all logs to shipley_checks/stage4/logs/
> shipley_checks/stage4/logs/phase0_extraction.log 2>&1
> shipley_checks/stage4/logs/phase1_vernaculars.log 2>&1
> shipley_checks/stage4/logs/phase3_koppen.log 2>&1
> shipley_checks/stage4/logs/phase4_merge.log 2>&1
> shipley_checks/stage4/logs/phase5_calibration.log 2>&1
```

## Execution Steps

1. Create new directory structure (empty phase folders)
2. Update ALL script paths (this document)
3. Delete old intermediate files
4. Keep only: BILL_VERIFIED CSV, Kimi labels
5. Rerun full pipeline Phase 0 → 6
6. Verify outputs in correct locations

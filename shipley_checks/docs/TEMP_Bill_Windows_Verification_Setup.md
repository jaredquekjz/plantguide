# Bill Shipley Windows Verification Setup Plan

**Purpose**: Enable Bill Shipley to independently verify Phases 0-3 and Stage 3 on Windows
**Date**: 2025-11-14
**Status**: DRAFT Implementation Plan

---

## Problem Statement

Bill Shipley needs to:
1. Run verification scripts on Windows (not Linux)
2. Verify data pipeline from raw inputs through CSR calculation
3. Compare his reproduced dataset against canonical output
4. **CANNOT** run XGBoost-based imputation (Stage 1-2) due to C++ compilation requirements

Current blockers:
- Path confusion (Linux paths vs Windows paths)
- File naming inconsistencies (`duke_wfo.csv` vs `duke_wfo_worldflora.csv`)
- Hard-coded relative paths that fail on Windows
- Unclear where to place input data

---

## Solution Overview

### Two-Package Approach

**Package 1**: `bill_foundational_data.zip` (14.5 GB)
- 12 raw input files for Phases 0-3

**Package 2**: `bill_intermediate_data.zip` (500 MB)
- Pre-computed Stage 1-2 outputs (XGBoost results)
- Enables Bill to run Stage 3 (CSR + ecosystem services)

### Windows Directory Structure

Bill's working directory:
```
C:/Users/shij1401/OneDrive - USherbrooke/
```

Required folder structure:
```
C:/Users/shij1401/OneDrive - USherbrooke/
├── shipley_verification_input/          # Extract bill_foundational_data.zip here
│   ├── duke_original.parquet
│   ├── eive_original.parquet
│   ├── mabberly_original.parquet
│   ├── tryenhanced_species_original.parquet
│   ├── austraits_taxa.parquet
│   ├── try_selected_traits.parquet
│   ├── gbif_occurrence_plantae.parquet
│   ├── globi_interactions_plants.parquet
│   ├── worldclim_occ_samples.parquet
│   ├── soilgrids_occ_samples.parquet
│   ├── agroclime_occ_samples.parquet
│   └── classification.csv
│
├── shipley_verification_intermediate/   # Extract bill_intermediate_data.zip here
│   ├── bill_complete_with_eive_20251107.csv
│   ├── duke_worldflora_enriched.parquet
│   ├── eive_worldflora_enriched.parquet
│   ├── mabberly_worldflora_enriched.parquet
│   ├── tryenhanced_worldflora_enriched.parquet
│   ├── austraits_traits_worldflora_enriched.parquet
│   └── try_nitrogen_fixation_bill.csv
│
├── shipley_verification_output/         # Scripts write here (auto-created)
│   ├── wfo_verification/
│   ├── stage1_shortlists/
│   ├── stage2_summaries/
│   └── stage3/                          # Final CSR output here
│
├── shipley_verification_scripts/        # All R scripts (from shipley-review branch)
│   ├── Phase_0/
│   ├── Phase_1/
│   ├── Phase_2/
│   ├── Phase_3/
│   ├── Stage_3/
│   └── run_all_bill.R
│
└── bill_with_csr_ecoservices_11711.csv  # Reference dataset (already provided)
```

---

## Data Package Contents

### Package 1: bill_foundational_data.zip (14.5 GB)

**Source files from main branch**:
```bash
data/stage1/duke_original.parquet
data/stage1/eive_original.parquet
data/stage1/mabberly_original.parquet
data/stage1/tryenhanced_species_original.parquet
data/stage1/austraits/taxa.parquet
data/stage1/try_selected_traits.parquet
data/gbif/occurrence_plantae.parquet
data/stage1/globi_interactions_plants.parquet
data/stage1/worldclim_occ_samples.parquet
data/stage1/soilgrids_occ_samples.parquet
data/stage1/agroclime_occ_samples.parquet
data/classification.csv
```

**Required transforms**:
- Copy `austraits/taxa.parquet` → `austraits_taxa.parquet` (flatten directory)
- Copy `gbif/occurrence_plantae.parquet` → `gbif_occurrence_plantae.parquet` (flatten directory)

### Package 2: bill_intermediate_data.zip (500 MB)

**Source files from main branch**:
```bash
shipley_checks/stage2_predictions/bill_complete_with_eive_20251107.csv
shipley_checks/wfo_verification/duke_worldflora_enriched.parquet
shipley_checks/wfo_verification/eive_worldflora_enriched.parquet
shipley_checks/wfo_verification/mabberly_worldflora_enriched.parquet
shipley_checks/wfo_verification/tryenhanced_worldflora_enriched.parquet
shipley_checks/wfo_verification/austraits_traits_worldflora_enriched.parquet
shipley_checks/stage3/try_nitrogen_fixation_bill.csv
```

**Purpose**:
- Stage 2 output → Stage 3 input (bill_complete_with_eive_20251107.csv)
- WFO-enriched parquets for taxonomy enrichment
- Nitrogen fixation data from TRY database

---

## Script Modifications Required

### Standard Path Template

All scripts modified to use:
```r
# ========================================================================
# BILL SHIPLEY WINDOWS PATHS
# USER ACTION: Replace USERNAME with your Windows username
# ========================================================================
BASE_DIR <- "C:/Users/USERNAME/OneDrive - USherbrooke"
INPUT_DIR <- file.path(BASE_DIR, "shipley_verification_input")
INTERMEDIATE_DIR <- file.path(BASE_DIR, "shipley_verification_intermediate")
OUTPUT_DIR <- file.path(BASE_DIR, "shipley_verification_output")

# Create output directories if needed
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
```

### Scripts Requiring Modification (35 scripts)

#### Phase 0: WFO Normalization (15 scripts)

**Extraction scripts (4)**:
1. `extract_all_names_bill.R`
   - **Current**: `data/stage1/duke_original.parquet`
   - **Change to**: `file.path(INPUT_DIR, "duke_original.parquet")`
   - Output: `file.path(OUTPUT_DIR, "wfo_verification/duke_names_for_r.csv")`

2. `extract_gbif_names_bill.R`
   - Input: `file.path(INPUT_DIR, "gbif_occurrence_plantae.parquet")`
   - Output: `file.path(OUTPUT_DIR, "wfo_verification/gbif_names_for_r.csv")`

3. `extract_globi_names_bill.R`
   - Input: `file.path(INPUT_DIR, "globi_interactions_plants.parquet")`
   - Output: `file.path(OUTPUT_DIR, "wfo_verification/globi_names_for_r.csv")`

4. `extract_try_traits_names_bill.R`
   - Input: `file.path(INPUT_DIR, "try_selected_traits.parquet")`
   - Output: `file.path(OUTPUT_DIR, "wfo_verification/try_traits_names_for_r.csv")`

**WorldFlora matching scripts (8)**:
5-12. `worldflora_{duke,eive,mabberly,tryenhanced,austraits,gbif,globi,try_traits}_match_bill.R`
   - Input names: `file.path(OUTPUT_DIR, "wfo_verification/{dataset}_names_for_r.csv")`
   - Input WFO: `file.path(INPUT_DIR, "classification.csv")`
   - Output: `file.path(OUTPUT_DIR, "wfo_verification/{dataset}_wfo_worldflora.csv")`

**Verification script (1)**:
13. `verify_wfo_matching_bill.R`
   - **CRITICAL FIX**: Change expected filename from `duke_wfo.csv` → `duke_wfo_worldflora.csv`
   - Input: `file.path(OUTPUT_DIR, "wfo_verification/{dataset}_wfo_worldflora.csv")`

**Additional extraction scripts (2)**:
14. `extract_try_traits_names_bill.R`
15. `extract_globi_names_bill.R`

#### Phase 1: Core Integration (6 scripts)

16. `build_bill_enriched_parquets.R`
   - Input WFO: `file.path(OUTPUT_DIR, "wfo_verification/{dataset}_wfo_worldflora.csv")`
   - Input original: `file.path(INPUT_DIR, "{dataset}_original.parquet")`
   - Output: `file.path(OUTPUT_DIR, "wfo_verification/{dataset}_worldflora_enriched.parquet")`

17. `verify_enriched_parquets_bill.R`
   - Input: `file.path(OUTPUT_DIR, "wfo_verification/{dataset}_worldflora_enriched.parquet")`

18. `verify_stage1_integrity_bill.R`
   - Input: Enriched parquets from OUTPUT_DIR
   - Output: `file.path(OUTPUT_DIR, "master_taxa_union_bill.parquet")`
   - Output: `file.path(OUTPUT_DIR, "stage1_shortlist_candidates_R.parquet")`

19. `verify_master_shortlist_bill.R`
   - Input: Shortlists from OUTPUT_DIR

20. `add_gbif_counts_bill.R`
   - Input shortlist: `file.path(OUTPUT_DIR, "stage1_shortlist_candidates_R.parquet")`
   - Input GBIF: `file.path(INPUT_DIR, "gbif_occurrence_plantae.parquet")`
   - Output: `file.path(OUTPUT_DIR, "stage1_shortlist_with_gbif_ge30_R.parquet")`

21. `verify_gbif_integration_bill.R`
   - Input: `file.path(OUTPUT_DIR, "stage1_shortlist_with_gbif_ge30_R.parquet")`

#### Phase 2: Environmental Aggregation (3 scripts)

22. `aggregate_env_summaries_bill.R`
   - Input shortlist: `file.path(OUTPUT_DIR, "stage1_shortlist_with_gbif_ge30_R.parquet")`
   - Input env: `file.path(INPUT_DIR, "{worldclim,soilgrids,agroclime}_occ_samples.parquet")`
   - Output: `file.path(OUTPUT_DIR, "{dataset}_species_summary_R.parquet")`

23. `aggregate_env_quantiles_bill.R`
   - Same input/output pattern as above for quantiles

24. `verify_env_aggregation_bill.R`
   - Input: Environmental summaries/quantiles from OUTPUT_DIR

#### Phase 3: Imputation Dataset Assembly (4 scripts - Skip tree building)

25. `extract_phylo_eigenvectors_bill.R`
   - **Use pre-computed tree**: `file.path(INPUT_DIR, "mixgb_tree_11711_species_20251107.nwk")`
   - **Use pre-computed mapping**: `file.path(INPUT_DIR, "mixgb_wfo_to_tree_mapping_11711.csv")`
   - Output: `file.path(OUTPUT_DIR, "phylo_eigenvectors_11711_bill.csv")`

26. `verify_phylo_eigenvectors_bill.R`
   - Input: `file.path(OUTPUT_DIR, "phylo_eigenvectors_11711_bill.csv")`

27. `assemble_canonical_imputation_input_bill.R`
   - Input shortlist: `file.path(OUTPUT_DIR, "stage1_shortlist_with_gbif_ge30_R.parquet")`
   - Input phylo: `file.path(OUTPUT_DIR, "phylo_eigenvectors_11711_bill.csv")`
   - Input env: `file.path(OUTPUT_DIR, "{dataset}_species_quantiles_R.parquet")`
   - Output: `file.path(OUTPUT_DIR, "canonical_imputation_input_11711_bill.csv")`

28. `verify_canonical_assembly_bill.R`
   - Input: `file.path(OUTPUT_DIR, "canonical_imputation_input_11711_bill.csv")`

#### Stage 3: CSR + Ecosystem Services (7 scripts)

29. `extract_try_nitrogen_fixation_bill.R`
   - **Skip**: Use pre-computed from INTERMEDIATE_DIR
   - (Optional: Bill can re-run if he has access to TRY raw data)

30. `enrich_bill_with_taxonomy.R`
   - **Input Stage 2**: `file.path(INTERMEDIATE_DIR, "bill_complete_with_eive_20251107.csv")`
   - Input enriched: `file.path(INTERMEDIATE_DIR, "{dataset}_worldflora_enriched.parquet")`
   - Input nitrogen: `file.path(INTERMEDIATE_DIR, "try_nitrogen_fixation_bill.csv")`
   - Output: `file.path(OUTPUT_DIR, "stage3/bill_enriched_stage3_11711.csv")`

31. `calculate_csr_bill.R`
   - Input: `file.path(OUTPUT_DIR, "stage3/bill_enriched_stage3_11711.csv")`
   - **Output**: `file.path(OUTPUT_DIR, "stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv")`
   - **CRITICAL**: Different filename to avoid overwriting reference dataset

32. `verify_csr_calculation_bill.R`
   - Input: `file.path(OUTPUT_DIR, "stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv")`

33. `verify_ecoservices_bill.R`
   - Input: `file.path(OUTPUT_DIR, "stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv")`

34. `verify_lifeform_stratification_bill.R`
   - Input: `file.path(OUTPUT_DIR, "stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv")`

35. `verify_stage3_complete_bill.R`
   - Orchestrates all Stage 3 verifications

---

## Additional Files for Package 1

Bill needs pre-computed phylogenetic tree files:

**Add to bill_foundational_data.zip**:
```
mixgb_tree_11711_species_20251107.nwk           # Phylogenetic tree (11,010 tips)
mixgb_wfo_to_tree_mapping_11711.csv             # WFO → tree tip mapping
```

**Source**: `data/stage1/phlogeny/` directory

---

## Master Run Script: run_all_bill.R

Create orchestrator script for Bill:

```r
#!/usr/bin/env Rscript
# run_all_bill.R - Master verification script for Bill Shipley
# Runs Phases 0-3 and Stage 3 (skips XGBoost Stages 1-2)

cat("========================================================================\n")
cat("BILL SHIPLEY VERIFICATION PIPELINE\n")
cat("Windows Edition - Phases 0-3 + Stage 3\n")
cat("========================================================================\n\n")

# USER ACTION: Update USERNAME
BASE_DIR <- "C:/Users/USERNAME/OneDrive - USherbrooke"
SCRIPT_DIR <- file.path(BASE_DIR, "shipley_verification_scripts")

# Set working directory
setwd(BASE_DIR)

# Helper function
run_script <- function(script_path, phase_name) {
  cat(sprintf("\n[%s] Running %s...\n", phase_name, basename(script_path)))
  result <- tryCatch({
    source(script_path)
    cat(sprintf("[%s] ✓ PASSED\n", phase_name))
    TRUE
  }, error = function(e) {
    cat(sprintf("[%s] ✗ FAILED: %s\n", phase_name, e$message))
    FALSE
  })
  return(result)
}

# PHASE 0: WFO Normalization
cat("\n\n========== PHASE 0: WFO NORMALIZATION ==========\n")
run_script(file.path(SCRIPT_DIR, "Phase_0/extract_all_names_bill.R"), "PHASE 0")
run_script(file.path(SCRIPT_DIR, "Phase_0/extract_gbif_names_bill.R"), "PHASE 0")
run_script(file.path(SCRIPT_DIR, "Phase_0/extract_globi_names_bill.R"), "PHASE 0")
run_script(file.path(SCRIPT_DIR, "Phase_0/extract_try_traits_names_bill.R"), "PHASE 0")

for (ds in c("duke", "eive", "mabberly", "tryenhanced", "austraits", "gbif", "globi", "try_traits")) {
  run_script(file.path(SCRIPT_DIR, sprintf("Phase_0/worldflora_%s_match_bill.R", ds)), "PHASE 0")
}

run_script(file.path(SCRIPT_DIR, "Phase_0/verify_wfo_matching_bill.R"), "PHASE 0 VERIFY")

# PHASE 1: Core Integration
cat("\n\n========== PHASE 1: CORE INTEGRATION ==========\n")
run_script(file.path(SCRIPT_DIR, "Phase_1/build_bill_enriched_parquets.R"), "PHASE 1")
run_script(file.path(SCRIPT_DIR, "Phase_1/verify_enriched_parquets_bill.R"), "PHASE 1 VERIFY")
run_script(file.path(SCRIPT_DIR, "Phase_1/verify_stage1_integrity_bill.R"), "PHASE 1")
run_script(file.path(SCRIPT_DIR, "Phase_1/verify_master_shortlist_bill.R"), "PHASE 1 VERIFY")
run_script(file.path(SCRIPT_DIR, "Phase_1/add_gbif_counts_bill.R"), "PHASE 1")
run_script(file.path(SCRIPT_DIR, "Phase_1/verify_gbif_integration_bill.R"), "PHASE 1 VERIFY")

# PHASE 2: Environmental Aggregation
cat("\n\n========== PHASE 2: ENVIRONMENTAL AGGREGATION ==========\n")
run_script(file.path(SCRIPT_DIR, "Phase_2/aggregate_env_summaries_bill.R"), "PHASE 2")
run_script(file.path(SCRIPT_DIR, "Phase_2/aggregate_env_quantiles_bill.R"), "PHASE 2")
run_script(file.path(SCRIPT_DIR, "Phase_2/verify_env_aggregation_bill.R"), "PHASE 2 VERIFY")

# PHASE 3: Imputation Dataset Assembly
cat("\n\n========== PHASE 3: IMPUTATION DATASET ASSEMBLY ==========\n")
run_script(file.path(SCRIPT_DIR, "Phase_3/extract_phylo_eigenvectors_bill.R"), "PHASE 3")
run_script(file.path(SCRIPT_DIR, "Phase_3/verify_phylo_eigenvectors_bill.R"), "PHASE 3 VERIFY")
run_script(file.path(SCRIPT_DIR, "Phase_3/assemble_canonical_imputation_input_bill.R"), "PHASE 3")
run_script(file.path(SCRIPT_DIR, "Phase_3/verify_canonical_assembly_bill.R"), "PHASE 3 VERIFY")

# STAGE 1-2: SKIPPED (XGBoost pre-computed)
cat("\n\n========== STAGE 1-2: USING PRE-COMPUTED XGBOOST RESULTS ==========\n")
cat("Stage 1 (Trait Imputation): Skipped - using pre-computed mixgb results\n")
cat("Stage 2 (EIVE Prediction): Skipped - using pre-computed XGBoost models\n")
cat("Input file: shipley_verification_intermediate/bill_complete_with_eive_20251107.csv\n")

# STAGE 3: CSR + Ecosystem Services
cat("\n\n========== STAGE 3: CSR + ECOSYSTEM SERVICES ==========\n")
run_script(file.path(SCRIPT_DIR, "Stage_3/enrich_bill_with_taxonomy.R"), "STAGE 3")
run_script(file.path(SCRIPT_DIR, "Stage_3/calculate_csr_bill.R"), "STAGE 3")
run_script(file.path(SCRIPT_DIR, "Stage_3/verify_stage3_complete_bill.R"), "STAGE 3 VERIFY")

cat("\n\n========================================================================\n")
cat("✓ VERIFICATION PIPELINE COMPLETE\n")
cat("========================================================================\n")
cat("\nFinal output:\n")
cat("  shipley_verification_output/stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv\n\n")
cat("Compare with reference dataset:\n")
cat("  bill_with_csr_ecoservices_11711.csv\n\n")
```

---

## What Bill Can/Cannot Run

### Bill CAN Run (with modified scripts):

✓ **Phase 0**: WFO Normalization (15 scripts)
- Extract taxonomic names from 8 datasets
- Match to WorldFlora taxonomy
- Verify match rates

✓ **Phase 1**: Core Integration (6 scripts)
- Build WFO-enriched parquets
- Create master taxa union (86,592 species)
- Filter to ≥3 traits (24,511 species)
- Add GBIF occurrence counts
- Filter to ≥30 occurrences (11,711 species)

✓ **Phase 2**: Environmental Aggregation (3 scripts)
- Aggregate WorldClim/SoilGrids/AgroClime summaries
- Calculate species-level quantiles (q05, q50, q95)
- Verify completeness

✓ **Phase 3**: Imputation Dataset Assembly (4 scripts)
- Extract phylogenetic eigenvectors (using pre-computed tree)
- Assemble canonical imputation input (11,711 × 736 columns)
- Verify anti-leakage and completeness

✓ **Stage 3**: CSR + Ecosystem Services (7 scripts)
- Enrich with taxonomy and nitrogen fixation
- Calculate CSR percentages
- Calculate 10 ecosystem service ratings
- Verify NPP/decomposition patterns
- **Output**: bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv

### Bill CANNOT Run (use pre-computed):

✗ **Stage 1**: Trait Imputation
- Requires mixgb R package (XGBoost wrapper with PMM)
- Requires C++ compiler for mice/Rfast dependencies
- 10-fold CV + 10 production runs (~16 hours runtime)
- **Solution**: Provide pre-computed `bill_complete_11711_20251107.csv`

✗ **Stage 2**: EIVE Prediction
- Requires Python XGBoost models
- Requires scikit-learn for preprocessing
- 5 axis-specific models with SHAP analysis
- **Solution**: Provide pre-computed `bill_complete_with_eive_20251107.csv`

---

## Estimated Runtime for Bill

**With standard laptop (no GPU)**:

- Phase 0: ~2 hours (taxonomy matching)
- Phase 1: ~1.5 hours (parquet joins, GBIF aggregation)
- Phase 2: ~4 hours (environmental aggregation on 31.5M rows × 3 datasets)
- Phase 3: ~30 minutes (phylogenetic eigenvectors, assembly)
- Stage 3: ~10 seconds (CSR calculation)

**Total**: ~8 hours

**Recommendation**: Run overnight or in background

---

## File Naming Fixes

### Critical Fix: verify_wfo_matching_bill.R

**Current (line 26)**:
```r
file_path <- sprintf("%s/%s_wfo.csv", WFO_DIR, ds)
```

**Change to**:
```r
file_path <- sprintf("%s/%s_wfo_worldflora.csv", WFO_DIR, ds)
```

**Reason**: WorldFlora matching scripts output `{dataset}_wfo_worldflora.csv`, not `{dataset}_wfo.csv`

---

## Validation Strategy

Bill compares his output against reference:

```r
# Bill's reproduced dataset
bill_verified <- read_csv("shipley_verification_output/stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv")

# Reference dataset (provided by Jared)
reference <- read_csv("bill_with_csr_ecoservices_11711.csv")

# Compare
library(dplyr)
library(waldo)

# Check dimensions
cat(sprintf("Bill: %d × %d\n", nrow(bill_verified), ncol(bill_verified)))
cat(sprintf("Reference: %d × %d\n", nrow(reference), ncol(reference)))

# Check CSR columns
compare(bill_verified %>% select(wfo_taxon_id, C, S, R),
        reference %>% select(wfo_taxon_id, C, S, R),
        tolerance = 1e-6)

# Check ecosystem services
compare(bill_verified %>% select(starts_with("ecoserv_")),
        reference %>% select(starts_with("ecoserv_")),
        tolerance = 1e-6)
```

**Expected outcome**: Identical CSR and ecosystem service values (numerical tolerance ≤1e-6)

---

## Implementation Checklist

### Data Preparation

- [ ] Zip bill_foundational_data/ (14.5 GB)
  - [ ] Include 12 parquet files
  - [ ] Include classification.csv
  - [ ] Include phylogenetic tree files (2)

- [ ] Zip bill_intermediate_data/ (500 MB)
  - [ ] Include Stage 2 output CSV
  - [ ] Include 5 enriched parquets
  - [ ] Include nitrogen fixation CSV

### Script Modifications (shipley-review branch)

- [ ] Update all 35 scripts with Windows path template
- [ ] Fix verify_wfo_matching_bill.R filename issue
- [ ] Update calculate_csr_bill.R output filename
- [ ] Create run_all_bill.R master script
- [ ] Organize scripts into Phase_0/, Phase_1/, Phase_2/, Phase_3/, Stage_3/ folders

### Documentation for Bill

- [ ] Create README_BILL.txt with:
  - [ ] Folder structure instructions
  - [ ] Where to extract ZIP files
  - [ ] How to update USERNAME in run_all_bill.R
  - [ ] How to run master script
  - [ ] Expected runtime
  - [ ] How to compare final output

### Testing Before Sending

- [ ] Test extraction scripts on sample data
- [ ] Verify path substitutions work
- [ ] Test run_all_bill.R on subset
- [ ] Confirm output filenames match expected paths

---

## Next Steps

1. **Create shipley-review branch** (if not exists)
2. **Modify 35 scripts** with Windows path template
3. **Create master run script** (run_all_bill.R)
4. **Package data** (2 ZIP files)
5. **Write README_BILL.txt** with setup instructions
6. **Test on Windows VM** (if available)
7. **Send to Bill** via email/OneDrive

---

**Last Updated**: 2025-11-14
**Status**: DRAFT - Awaiting implementation
**Target User**: Bill Shipley (Windows environment)

# Bill Shipley Script Modification Checklist

**Purpose**: Track all 35 scripts requiring Windows path standardization
**Date**: 2025-11-14
**Branch**: shipley-review

---

## Path Template (Add to ALL scripts)

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
dir.create(file.path(OUTPUT_DIR, "wfo_verification"), showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(OUTPUT_DIR, "stage3"), showWarnings = FALSE, recursive = TRUE)
```

---

## Phase 0: WFO Normalization (15 scripts)

### Extraction Scripts (4)

- [ ] **extract_all_names_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Search for: `data/stage1/duke_original.parquet`
  - Replace with: `file.path(INPUT_DIR, "duke_original.parquet")`
  - Output pattern: `file.path(OUTPUT_DIR, "wfo_verification/{dataset}_names_for_r.csv")`

- [ ] **extract_gbif_names_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Search for: `data/gbif/occurrence_plantae.parquet`
  - Replace with: `file.path(INPUT_DIR, "gbif_occurrence_plantae.parquet")`
  - Output: `file.path(OUTPUT_DIR, "wfo_verification/gbif_names_for_r.csv")`

- [ ] **extract_globi_names_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Search for: `data/stage1/globi_interactions_plants.parquet`
  - Replace with: `file.path(INPUT_DIR, "globi_interactions_plants.parquet")`
  - Output: `file.path(OUTPUT_DIR, "wfo_verification/globi_names_for_r.csv")`

- [ ] **extract_try_traits_names_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Search for: `data/stage1/try_selected_traits.parquet`
  - Replace with: `file.path(INPUT_DIR, "try_selected_traits.parquet")`
  - Output: `file.path(OUTPUT_DIR, "wfo_verification/try_traits_names_for_r.csv")`

### WorldFlora Matching Scripts (8)

- [ ] **worldflora_duke_match_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Input names: `file.path(OUTPUT_DIR, "wfo_verification/duke_names_for_r.csv")`
  - Input WFO: `file.path(INPUT_DIR, "classification.csv")`
  - Output: `file.path(OUTPUT_DIR, "wfo_verification/duke_wfo_worldflora.csv")`

- [ ] **worldflora_eive_match_bill.R**
  - Same pattern as duke

- [ ] **worldflora_mabberly_match_bill.R**
  - Same pattern as duke

- [ ] **worldflora_tryenhanced_match_bill.R**
  - Same pattern as duke

- [ ] **worldflora_austraits_match_bill.R**
  - Same pattern as duke

- [ ] **worldflora_gbif_match_bill.R**
  - Same pattern as duke

- [ ] **worldflora_globi_match_bill.R**
  - Same pattern as duke

- [ ] **worldflora_try_traits_match_bill.R**
  - Same pattern as duke

### Verification Scripts (3)

- [ ] **verify_wfo_matching_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - **CRITICAL FIX Line 17**: `WFO_DIR <- "data/shipley_checks/wfo_verification"`
    → `WFO_DIR <- file.path(OUTPUT_DIR, "wfo_verification")`
  - **CRITICAL FIX Line 26**: `file_path <- sprintf("%s/%s_wfo.csv", WFO_DIR, ds)`
    → `file_path <- file.path(WFO_DIR, sprintf("%s_wfo_worldflora.csv", ds))`

---

## Phase 1: Core Integration (6 scripts)

- [ ] **build_bill_enriched_parquets.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Input WFO CSVs: `file.path(OUTPUT_DIR, "wfo_verification/{dataset}_wfo_worldflora.csv")`
  - Input original parquets: `file.path(INPUT_DIR, "{dataset}_original.parquet")`
  - Output: `file.path(OUTPUT_DIR, "wfo_verification/{dataset}_worldflora_enriched.parquet")`

- [ ] **verify_enriched_parquets_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Input: `file.path(OUTPUT_DIR, "wfo_verification/{dataset}_worldflora_enriched.parquet")`

- [ ] **verify_stage1_integrity_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Input: Enriched parquets from OUTPUT_DIR
  - Output master union: `file.path(OUTPUT_DIR, "master_taxa_union_bill.parquet")`
  - Output shortlist: `file.path(OUTPUT_DIR, "stage1_shortlist_candidates_R.parquet")`

- [ ] **verify_master_shortlist_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Input: `file.path(OUTPUT_DIR, "master_taxa_union_bill.parquet")`
  - Input: `file.path(OUTPUT_DIR, "stage1_shortlist_candidates_R.parquet")`

- [ ] **add_gbif_counts_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Input shortlist: `file.path(OUTPUT_DIR, "stage1_shortlist_candidates_R.parquet")`
  - Input GBIF: `file.path(INPUT_DIR, "gbif_occurrence_plantae.parquet")`
  - Output with counts: `file.path(OUTPUT_DIR, "gbif_occurrence_counts_by_wfo_R.parquet")`
  - Output merged: `file.path(OUTPUT_DIR, "stage1_shortlist_with_gbif_R.parquet")`
  - Output filtered: `file.path(OUTPUT_DIR, "stage1_shortlist_with_gbif_ge30_R.parquet")`

- [ ] **verify_gbif_integration_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Input: `file.path(OUTPUT_DIR, "stage1_shortlist_with_gbif_ge30_R.parquet")`

---

## Phase 2: Environmental Aggregation (3 scripts)

- [ ] **aggregate_env_summaries_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Input shortlist: `file.path(OUTPUT_DIR, "stage1_shortlist_with_gbif_ge30_R.parquet")`
  - Input WorldClim: `file.path(INPUT_DIR, "worldclim_occ_samples.parquet")`
  - Input SoilGrids: `file.path(INPUT_DIR, "soilgrids_occ_samples.parquet")`
  - Input AgroClime: `file.path(INPUT_DIR, "agroclime_occ_samples.parquet")`
  - Output: `file.path(OUTPUT_DIR, "{dataset}_species_summary_R.parquet")` (3 files)

- [ ] **aggregate_env_quantiles_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Same inputs as above
  - Output: `file.path(OUTPUT_DIR, "{dataset}_species_quantiles_R.parquet")` (3 files)

- [ ] **verify_env_aggregation_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Input summaries: `file.path(OUTPUT_DIR, "{dataset}_species_summary_R.parquet")`
  - Input quantiles: `file.path(OUTPUT_DIR, "{dataset}_species_quantiles_R.parquet")`

---

## Phase 3: Imputation Dataset Assembly (4 scripts)

- [ ] **extract_phylo_eigenvectors_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Input tree: `file.path(INPUT_DIR, "mixgb_tree_11711_species_20251107.nwk")`
  - Input mapping: `file.path(INPUT_DIR, "mixgb_wfo_to_tree_mapping_11711.csv")`
  - Output: `file.path(OUTPUT_DIR, "phylo_eigenvectors_11711_bill.csv")`

- [ ] **verify_phylo_eigenvectors_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Input: `file.path(OUTPUT_DIR, "phylo_eigenvectors_11711_bill.csv")`

- [ ] **assemble_canonical_imputation_input_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Input shortlist: `file.path(OUTPUT_DIR, "stage1_shortlist_with_gbif_ge30_R.parquet")`
  - Input phylo: `file.path(OUTPUT_DIR, "phylo_eigenvectors_11711_bill.csv")`
  - Input env quantiles: `file.path(OUTPUT_DIR, "{dataset}_species_quantiles_R.parquet")` (3 files)
  - Input enriched parquets: `file.path(OUTPUT_DIR, "wfo_verification/{dataset}_worldflora_enriched.parquet")`
  - Output: `file.path(OUTPUT_DIR, "canonical_imputation_input_11711_bill.csv")`

- [ ] **verify_canonical_assembly_bill.R**
  - Location: `shipley_checks/src/Stage_1/bill_verification/`
  - Input: `file.path(OUTPUT_DIR, "canonical_imputation_input_11711_bill.csv")`

---

## Stage 3: CSR + Ecosystem Services (7 scripts)

- [ ] **enrich_bill_with_taxonomy.R**
  - Location: `shipley_checks/src/Stage_3/bill_verification/`
  - **Input Stage 2 output**: `file.path(INTERMEDIATE_DIR, "bill_complete_with_eive_20251107.csv")`
  - Input enriched duke: `file.path(INTERMEDIATE_DIR, "duke_worldflora_enriched.parquet")`
  - Input enriched eive: `file.path(INTERMEDIATE_DIR, "eive_worldflora_enriched.parquet")`
  - Input enriched mabberly: `file.path(INTERMEDIATE_DIR, "mabberly_worldflora_enriched.parquet")`
  - Input nitrogen fixation: `file.path(INTERMEDIATE_DIR, "try_nitrogen_fixation_bill.csv")`
  - Output: `file.path(OUTPUT_DIR, "stage3/bill_enriched_stage3_11711.csv")`

- [ ] **calculate_csr_bill.R**
  - Location: `shipley_checks/src/Stage_3/bill_verification/`
  - Input: `file.path(OUTPUT_DIR, "stage3/bill_enriched_stage3_11711.csv")`
  - **CRITICAL**: Change output filename
  - Old: `file.path(OUTPUT_DIR, "stage3/bill_with_csr_ecoservices_11711.csv")`
  - New: `file.path(OUTPUT_DIR, "stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv")`

- [ ] **verify_csr_calculation_bill.R**
  - Location: `shipley_checks/src/Stage_3/bill_verification/`
  - Input: `file.path(OUTPUT_DIR, "stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv")`

- [ ] **verify_ecoservices_bill.R**
  - Location: `shipley_checks/src/Stage_3/bill_verification/`
  - Input: `file.path(OUTPUT_DIR, "stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv")`

- [ ] **verify_lifeform_stratification_bill.R**
  - Location: `shipley_checks/src/Stage_3/bill_verification/`
  - Input: `file.path(OUTPUT_DIR, "stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv")`

- [ ] **verify_stage3_complete_bill.R**
  - Location: `shipley_checks/src/Stage_3/bill_verification/`
  - Orchestrates all Stage 3 verifications
  - Update all internal script calls to use correct input path

- [ ] **extract_try_nitrogen_fixation_bill.R** (OPTIONAL - Bill likely can't run)
  - Location: `shipley_checks/src/Stage_3/bill_verification/`
  - Note: Requires TRY raw data access
  - Bill will use pre-computed from INTERMEDIATE_DIR

---

## Master Script

- [ ] **run_all_bill.R** (NEW)
  - Location: `shipley_checks/src/`
  - Orchestrates all 35 scripts in sequence
  - Skips Stage 1-2 (XGBoost)
  - Uses pre-computed intermediate data

---

## Summary

**Total Scripts**: 35 + 1 master = 36 scripts
- Phase 0: 15 scripts
- Phase 1: 6 scripts
- Phase 2: 3 scripts
- Phase 3: 4 scripts
- Stage 3: 7 scripts
- Master: 1 script

**Critical Fixes**:
1. verify_wfo_matching_bill.R: Filename from `_wfo.csv` → `_wfo_worldflora.csv`
2. calculate_csr_bill.R: Output filename add `_BILL_VERIFIED` suffix
3. All scripts: Add Windows path template at top

**Next Action**: Begin systematic modification on shipley-review branch

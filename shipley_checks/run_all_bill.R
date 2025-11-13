#!/usr/bin/env Rscript
################################################################################
# Master Verification Script for Bill Shipley
# Cross-platform - Phases 0-3 + Stage 3
#
# This script orchestrates the complete verification pipeline that Bill can run,
# skipping XGBoost-based Stages 1-2 (which use pre-computed results)
#
# Prerequisites:
#   1. Run: Rscript setup_bill.R (extracts intermediate data)
#   2. Extract bill_foundational_data.zip to shipley_checks/input/
#   3. Install required R packages (arrow, data.table, dplyr, readr, WorldFlora, ape, phangorn)
#
# Estimated runtime: ~8 hours on standard laptop
################################################################################

# ========================================================================
# AUTO-DETECTING PATHS (works on Windows/Linux/Mac, any location)
# ========================================================================
get_repo_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- sub("^--file=", "", file_arg[1])
    # This script is in shipley_checks/
    repo_root <- normalizePath(file.path(dirname(script_path), ".."))
  } else {
    # Fallback: assume current directory is repo root
    repo_root <- normalizePath(getwd())
  }
  return(repo_root)
}

repo_root <- get_repo_root()
shipley_dir <- file.path(repo_root, "shipley_checks")
INPUT_DIR <- file.path(shipley_dir, "input")
INTERMEDIATE_DIR <- file.path(shipley_dir, "intermediate")
OUTPUT_DIR <- file.path(shipley_dir, "output")
SCRIPT_DIR <- file.path(shipley_dir, "src")

cat("========================================================================\n")
cat("BILL SHIPLEY VERIFICATION PIPELINE\n")
cat("Cross-Platform Edition - Phases 0-3 + Stage 3\n")
cat("========================================================================\n\n")

cat("Detected paths:\n")
cat("  Repo root:    ", repo_root, "\n")
cat("  Input:        ", INPUT_DIR, "\n")
cat("  Intermediate: ", INTERMEDIATE_DIR, "\n")
cat("  Output:       ", OUTPUT_DIR, "\n")
cat("  Scripts:      ", SCRIPT_DIR, "\n\n")

# Verify directories exist
if (!dir.exists(INPUT_DIR)) {
  stop("ERROR: Input directory not found. Please extract bill_foundational_data.zip to: ", INPUT_DIR)
}
if (!dir.exists(INTERMEDIATE_DIR)) {
  stop("ERROR: Intermediate directory not found. Please run: Rscript setup_bill.R")
}
if (!dir.exists(SCRIPT_DIR)) {
  stop("ERROR: Scripts directory not found at: ", SCRIPT_DIR)
}

# Create output directory
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

################################################################################
# Helper Functions
################################################################################

run_script <- function(script_rel_path, phase_name, required = TRUE) {
  script_path <- file.path(SCRIPT_DIR, script_rel_path)
  cat(sprintf("\n[%s] Running %s...\n", phase_name, basename(script_path)))

  if (!file.exists(script_path)) {
    msg <- sprintf("[%s] ✗ SCRIPT NOT FOUND: %s\n", phase_name, script_path)
    if (required) {
      stop(msg)
    } else {
      cat(msg)
      return(FALSE)
    }
  }

  start_time <- Sys.time()

  result <- tryCatch({
    # Source the script in isolated environment
    suppressMessages(source(script_path, local = new.env()))
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    cat(sprintf("[%s] ✓ PASSED (%.1f seconds)\n", phase_name, elapsed))
    TRUE
  }, error = function(e) {
    cat(sprintf("[%s] ✗ FAILED: %s\n", phase_name, e$message))
    if (required) {
      stop(sprintf("Required script failed: %s", script_path))
    }
    FALSE
  })

  return(result)
}

pipeline_start_time <- Sys.time()

################################################################################
# PHASE 0: WFO NORMALIZATION
################################################################################

cat("\n\n")
cat("========================================================================\n")
cat("PHASE 0: WFO NORMALIZATION (Taxonomic Standardization)\n")
cat("========================================================================\n")
cat("Extracts names from 8 datasets and matches to WorldFlora taxonomy\n")
cat("Expected runtime: ~2 hours\n\n")

# Step 0.1: Extract names from all datasets
cat("--- Step 0.1: Extract Names ---\n")
run_script("Stage_1/bill_verification/extract_all_names_bill.R", "PHASE 0.1")

# Step 0.2: WorldFlora matching for all datasets
cat("\n--- Step 0.2: WorldFlora Matching ---\n")
datasets <- c("duke", "eive", "mabberly", "tryenhanced", "austraits", "gbif", "globi", "try_traits")
for (ds in datasets) {
  run_script(sprintf("Stage_1/bill_verification/worldflora_%s_match_bill.R", ds), "PHASE 0.2")
}

# Step 0.3: Verify WFO matching
cat("\n--- Step 0.3: Verification ---\n")
run_script("Stage_1/bill_verification/verify_wfo_matching_bill.R", "PHASE 0.3")

################################################################################
# PHASE 1: CORE INTEGRATION
################################################################################

cat("\n\n")
cat("========================================================================\n")
cat("PHASE 1: CORE INTEGRATION (Trait Assembly)\n")
cat("========================================================================\n")
cat("Builds WFO-enriched datasets and filters to high-quality species\n")
cat("Expected runtime: ~1.5 hours\n\n")

# Step 1.1: Build enriched parquets
cat("--- Step 1.1: Build Enriched Parquets ---\n")
run_script("Stage_1/bill_verification/build_bill_enriched_parquets.R", "PHASE 1.1")

# Step 1.2: Verify enriched parquets
cat("\n--- Step 1.2: Verify Enriched Parquets ---\n")
run_script("Stage_1/bill_verification/verify_enriched_parquets_bill.R", "PHASE 1.2")

# Step 1.3: Build master union and shortlist
cat("\n--- Step 1.3: Build Master Union ---\n")
run_script("Stage_1/bill_verification/verify_stage1_integrity_bill.R", "PHASE 1.3")

# Step 1.4: Verify master shortlist
cat("\n--- Step 1.4: Verify Master Shortlist ---\n")
run_script("Stage_1/bill_verification/verify_master_shortlist_bill.R", "PHASE 1.4")

# Step 1.5: Add GBIF counts and filter
cat("\n--- Step 1.5: Add GBIF Counts ---\n")
run_script("Stage_1/bill_verification/add_gbif_counts_bill.R", "PHASE 1.5")

# Step 1.6: Verify GBIF integration
cat("\n--- Step 1.6: Verify GBIF Integration ---\n")
run_script("Stage_1/bill_verification/verify_gbif_integration_bill.R", "PHASE 1.6")

################################################################################
# PHASE 2: ENVIRONMENTAL AGGREGATION
################################################################################

cat("\n\n")
cat("========================================================================\n")
cat("PHASE 2: ENVIRONMENTAL AGGREGATION\n")
cat("========================================================================\n")
cat("Aggregates climate and soil data for each species\n")
cat("Expected runtime: ~4 hours\n\n")

# Step 2.1: Aggregate summaries
cat("--- Step 2.1: Aggregate Environmental Summaries ---\n")
run_script("Stage_1/bill_verification/aggregate_env_summaries_bill.R", "PHASE 2.1")

# Step 2.2: Aggregate quantiles
cat("\n--- Step 2.2: Aggregate Environmental Quantiles ---\n")
run_script("Stage_1/bill_verification/aggregate_env_quantiles_bill.R", "PHASE 2.2")

# Step 2.3: Verify aggregation
cat("\n--- Step 2.3: Verify Environmental Aggregation ---\n")
run_script("Stage_1/bill_verification/verify_env_aggregation_bill.R", "PHASE 2.3")

################################################################################
# PHASE 3: IMPUTATION DATASET ASSEMBLY
################################################################################

cat("\n\n")
cat("========================================================================\n")
cat("PHASE 3: IMPUTATION DATASET ASSEMBLY\n")
cat("========================================================================\n")
cat("Prepares features for trait imputation (phylogeny + environment)\n")
cat("Expected runtime: ~30 minutes\n\n")

# Step 3.1: Extract phylogenetic eigenvectors (using pre-computed tree)
cat("--- Step 3.1: Extract Phylogenetic Eigenvectors ---\n")
run_script("Stage_1/bill_verification/extract_phylo_eigenvectors_bill.R", "PHASE 3.1")

# Step 3.2: Verify phylogenetic eigenvectors
cat("\n--- Step 3.2: Verify Phylogenetic Eigenvectors ---\n")
run_script("Stage_1/bill_verification/verify_phylo_eigenvectors_bill.R", "PHASE 3.2")

# Step 3.3: Assemble canonical imputation input
cat("\n--- Step 3.3: Assemble Canonical Imputation Input ---\n")
run_script("Stage_1/bill_verification/assemble_canonical_imputation_input_bill.R", "PHASE 3.3")

# Step 3.4: Verify canonical assembly
cat("\n--- Step 3.4: Verify Canonical Assembly ---\n")
run_script("Stage_1/bill_verification/verify_canonical_assembly_bill.R", "PHASE 3.4")

################################################################################
# STAGE 1-2: XGBOOST (SKIPPED - PRE-COMPUTED)
################################################################################

cat("\n\n")
cat("========================================================================\n")
cat("STAGE 1-2: XGBOOST IMPUTATION (SKIPPED - USING PRE-COMPUTED)\n")
cat("========================================================================\n")
cat("Stage 1 (Trait Imputation): Skipped - using pre-computed mixgb results\n")
cat("Stage 2 (EIVE Prediction): Skipped - using pre-computed XGBoost models\n\n")
cat("Pre-computed input file for Stage 3:\n")
cat("  ", file.path(INTERMEDIATE_DIR, "bill_complete_with_eive_20251107.csv"), "\n\n")

# Verify intermediate file exists
intermediate_file <- file.path(INTERMEDIATE_DIR, "bill_complete_with_eive_20251107.csv")
if (!file.exists(intermediate_file)) {
  stop("ERROR: Pre-computed Stage 2 output not found. Please run: Rscript setup_bill.R")
}
cat("✓ Pre-computed Stage 2 output verified\n")

################################################################################
# STAGE 3: CSR + ECOSYSTEM SERVICES
################################################################################

cat("\n\n")
cat("========================================================================\n")
cat("STAGE 3: CSR + ECOSYSTEM SERVICES\n")
cat("========================================================================\n")
cat("Calculates CSR strategy percentages and ecosystem service ratings\n")
cat("Expected runtime: ~10 seconds\n\n")

# Step 3.1: Enrich with taxonomy and nitrogen fixation
cat("--- Step 3.1: Enrich with Taxonomy ---\n")
run_script("Stage_3/bill_verification/enrich_bill_with_taxonomy.R", "STAGE 3.1")

# Step 3.2: Calculate CSR and ecosystem services
cat("\n--- Step 3.2: Calculate CSR & Ecosystem Services ---\n")
run_script("Stage_3/bill_verification/calculate_csr_bill.R", "STAGE 3.2")

# Step 3.3: Verify complete Stage 3 pipeline
cat("\n--- Step 3.3: Verify Complete Stage 3 Pipeline ---\n")
run_script("Stage_3/bill_verification/verify_stage3_complete_bill.R", "STAGE 3.3")

################################################################################
# PIPELINE COMPLETE
################################################################################

cat("\n\n")
cat("========================================================================\n")
cat("✓ VERIFICATION PIPELINE COMPLETE\n")
cat("========================================================================\n\n")

cat("Final output location:\n")
cat("  ", file.path(OUTPUT_DIR, "stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv"), "\n\n")

cat("Compare with reference dataset:\n")
cat("  ", file.path(shipley_dir, "bill_with_csr_ecoservices_11711.csv"), "\n\n")

cat("Next steps:\n")
cat("  1. Compare your output with the reference dataset\n")
cat("  2. Check for numerical differences (should be < 1e-6)\n")
cat("  3. Report any discrepancies to Jared\n\n")

elapsed <- format(Sys.time() - pipeline_start_time, digits = 2)
cat("Total runtime: ", elapsed, "\n\n")

#!/usr/bin/env Rscript
################################################################################
# Bill Shipley Verification Setup Script
#
# This script prepares your environment for running the verification pipeline:
#   1. Extracts intermediate data (pre-computed XGBoost results)
#   2. Creates necessary directory structure
#   3. Verifies all prerequisites
#
# RUN THIS FIRST before running run_all_bill.R
#
# Usage:
#   Rscript setup_bill.R
################################################################################

cat("========================================================================\n")
cat("BILL SHIPLEY VERIFICATION SETUP\n")
cat("========================================================================\n\n")

# Detect repo root
get_repo_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- sub("^--file=", "", file_arg[1])
    # This script is at repo root
    repo_root <- normalizePath(dirname(script_path))
  } else {
    # Fallback: assume current directory is repo root
    repo_root <- normalizePath(getwd())
  }
  return(repo_root)
}

repo_root <- get_repo_root()

cat("Detected repository root: ", repo_root, "\n\n")

################################################################################
# Step 1: Extract Intermediate Data
################################################################################

cat("Step 1: Extracting intermediate data...\n")
zip_path <- file.path(repo_root, "bill_intermediate_data.zip")

if (!file.exists(zip_path)) {
  stop("ERROR: bill_intermediate_data.zip not found at: ", zip_path)
}

cat("  Found ZIP: ", zip_path, "\n")
cat("  Size: ", round(file.size(zip_path) / 1024^2, 1), " MB\n")

# Extract to shipley_checks/ (creates intermediate/ folder)
cat("  Extracting...\n")
unzip(zip_path, exdir = repo_root, overwrite = TRUE)

# Verify extraction
intermediate_dir <- file.path(repo_root, "intermediate")
if (!dir.exists(intermediate_dir)) {
  stop("ERROR: Extraction failed - intermediate/ directory not created")
}

# Verify all expected files
expected_files <- c(
  "bill_complete_with_eive_20251107.csv",
  "duke_worldflora_enriched.parquet",
  "eive_worldflora_enriched.parquet",
  "mabberly_worldflora_enriched.parquet",
  "tryenhanced_worldflora_enriched.parquet",
  "austraits_traits_worldflora_enriched.parquet",
  "try_nitrogen_fixation_bill.csv"
)

missing <- c()
for (fname in expected_files) {
  fpath <- file.path(intermediate_dir, fname)
  if (!file.exists(fpath)) {
    missing <- c(missing, fname)
  }
}

if (length(missing) > 0) {
  stop("ERROR: Missing intermediate files: ", paste(missing, collapse = ", "))
}

cat("  ✓ Extracted ", length(expected_files), " intermediate files\n\n")

################################################################################
# Step 2: Create Directory Structure
################################################################################

cat("Step 2: Creating directory structure...\n")

# Create input directory
input_dir <- file.path(repo_root, "input")
dir.create(input_dir, recursive = TRUE, showWarnings = FALSE)
cat("  Created: ", input_dir, "\n")

# Create output directory tree
output_dir <- file.path(repo_root, "output")
dir.create(file.path(output_dir, "wfo_verification"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(output_dir, "stage3"), recursive = TRUE, showWarnings = FALSE)
cat("  Created: ", output_dir, "\n")
cat("  Created: ", file.path(output_dir, "wfo_verification"), "\n")
cat("  Created: ", file.path(output_dir, "stage3"), "\n\n")

################################################################################
# Step 3: Verify Prerequisites
################################################################################

cat("Step 3: Checking prerequisites...\n\n")

# Check for input data
cat("  [INPUT DATA]\n")
input_files_needed <- c(
  "duke_original.parquet",
  "eive_original.parquet",
  "mabberly_original.parquet",
  "tryenhanced_species_original.parquet",
  "austraits_traits.parquet",   # CORRECTED: traits file (1.8M rows), not taxa
  "try_selected_traits.parquet",
  "gbif_occurrence_plantae.parquet",
  "globi_interactions_plants.parquet",
  "worldclim_occ_samples.parquet",
  "soilgrids_occ_samples.parquet",
  "agroclime_occ_samples.parquet",
  "classification.csv",
  "mixgb_tree_11711_species_20251107.nwk",
  "mixgb_wfo_to_tree_mapping_11711.csv"
)

missing_input <- c()
for (fname in input_files_needed) {
  fpath <- file.path(input_dir, fname)
  if (file.exists(fpath)) {
    cat("    ✓ ", fname, "\n")
  } else {
    cat("    ✗ ", fname, " (MISSING)\n")
    missing_input <- c(missing_input, fname)
  }
}

if (length(missing_input) > 0) {
  cat("\n  WARNING: ", length(missing_input), " input files missing\n")
  cat("  Please extract bill_foundational_data.zip to:\n")
  cat("    ", input_dir, "\n\n")
} else {
  cat("\n  ✓ All input files present\n\n")
}

# Check R packages
cat("  [R PACKAGES]\n")
required_packages <- c(
  "arrow",        # For parquet files
  "data.table",   # For fast data manipulation
  "dplyr",        # For data wrangling
  "readr",        # For CSV I/O
  "tibble",       # For tibble data structures (dplyr dependency)
  "purrr",        # For functional programming (dplyr dependency)
  "stringr",      # For Arrow-compatible string functions
  "duckdb",       # For out-of-core GBIF processing (WARNING: 20-30 min compile time)
  "WorldFlora",   # For taxonomic matching
  "ape",          # For phylogenetic trees
  "phangorn"      # For phylogenetic analysis
)

missing_packages <- c()
for (pkg in required_packages) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    cat("    ✓ ", pkg, "\n")
  } else {
    cat("    ✗ ", pkg, " (NOT INSTALLED)\n")
    missing_packages <- c(missing_packages, pkg)
  }
}

if (length(missing_packages) > 0) {
  cat("\n  WARNING: ", length(missing_packages), " packages missing\n")
  cat("  Install with:\n")
  cat("    install.packages(c('", paste(missing_packages, collapse = "', '"), "'), dependencies = TRUE)\n\n")
  cat("  Note: 'dependencies = TRUE' ensures all sub-packages are also installed\n\n")
} else {
  cat("\n  ✓ All required packages installed\n\n")
}

################################################################################
# Setup Complete
################################################################################

cat("========================================================================\n")
cat("SETUP COMPLETE\n")
cat("========================================================================\n\n")

cat("Directory structure:\n")
cat("  ", repo_root, "/\n")
cat("    ├── input/           # Place bill_foundational_data.zip contents here\n")
cat("    ├── intermediate/    # ✓ Pre-computed XGBoost results (extracted)\n")
cat("    ├── output/          # ✓ Pipeline outputs go here\n")
cat("    └── src/             # Verification scripts\n\n")

if (length(missing_input) > 0) {
  cat("NEXT STEPS:\n")
  cat("  1. Extract bill_foundational_data.zip to: ", input_dir, "\n")
  cat("  2. Run: Rscript ", file.path(repo_root, "run_all_bill.R"), "\n\n")
} else if (length(missing_packages) > 0) {
  cat("NEXT STEPS:\n")
  cat("  1. Install missing R packages (see above)\n")
  cat("  2. Run: Rscript ", file.path(repo_root, "run_all_bill.R"), "\n\n")
} else {
  cat("✓ All prerequisites met!\n\n")
  cat("NEXT STEP:\n")
  cat("  Run: Rscript ", file.path(repo_root, "run_all_bill.R"), "\n\n")
}

cat("Estimated runtime: ~8 hours on standard laptop\n\n")

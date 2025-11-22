#!/usr/bin/env Rscript
# verify_phylo_eigenvectors_bill.R - Verify phylogenetic eigenvector extraction
# ========================================================================
# AUTO-DETECTING PATHS (works on Windows/Linux/Mac, any location)
# ========================================================================
get_repo_root <- function() {
  # First check if environment variable is set (from run_all_bill.R)
  env_root <- Sys.getenv("BILL_REPO_ROOT", unset = NA)
  if (!is.na(env_root) && env_root != "") {
    return(normalizePath(env_root))
  }

  # Otherwise detect from script path
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- sub("^--file=", "", file_arg[1])
    # Navigate up from script to repo root
    # Scripts are in src/Stage_X/bill_verification/
    repo_root <- normalizePath(file.path(dirname(script_path), "..", "..", ".."))
  } else {
    # Fallback: assume current directory is repo root
    repo_root <- normalizePath(getwd())
  }
  return(repo_root)
}

repo_root <- get_repo_root()
INPUT_DIR <- file.path(repo_root, "input")
INTERMEDIATE_DIR <- file.path(repo_root, "intermediate")
OUTPUT_DIR <- file.path(repo_root, "output")

# Create output directories
dir.create(file.path(OUTPUT_DIR, "wfo_verification"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUTPUT_DIR, "stage3"), recursive = TRUE, showWarnings = FALSE)



suppressPackageStartupMessages({library(dplyr); library(readr); library(ape)})

# Helper function: Check conditions and print formatted pass/fail status
# Returns TRUE if condition passes, FALSE otherwise
# Used to accumulate verification results across multiple checks
check_pass <- function(cond, msg) { stat <- if (cond) "✓" else "✗"; cat(sprintf("  %s %s\n", stat, msg)); return(cond) }

cat("========================================================================\n")
cat("VERIFICATION: Phylogenetic Eigenvectors\n")
cat("========================================================================\n\n")

# Define input files to verify
# Tree file: phylogenetic tree used for eigenvector extraction (11,010 tips)
TREE_FILE <- file.path(INPUT_DIR, "mixgb_tree_11711_species_20251107.nwk")
# Eigenvector file: output from extract_phylo_eigenvectors_bill.R
# Use auto-detected OUTPUT_DIR for cross-platform compatibility
EV_FILE <- file.path(OUTPUT_DIR, "modelling", "phylo_eigenvectors_11711_bill.csv")
# Track verification status across all checks
all_pass <- TRUE

# ========================================================================
# CHECK 1: FILE EXISTENCE
# ========================================================================
# Verify both input tree and output eigenvector files exist
# Tree file is required to verify tip count matches eigenvector rows
# Eigenvector file is the primary output to validate
all_pass <- check_pass(file.exists(TREE_FILE), "Tree file exists") && all_pass
all_pass <- check_pass(file.exists(EV_FILE), "Eigenvector file exists") && all_pass

# ========================================================================
# CHECK 2: TREE STRUCTURE
# ========================================================================
# Verify tree has expected number of tips (~11,010 species)
# Tree tips represent species with phylogenetic placement in tree
# Expected: 11,010 tips (slightly less than 11,711 total WFO species)
# ~700 species lack tree placement (infraspecific taxa or missing data)
if (file.exists(TREE_FILE)) {
  tree <- read.tree(TREE_FILE)
  # Allow tolerance of ±20 tips for minor variations in tree construction
  all_pass <- check_pass(abs(length(tree$tip.label) - 11010) <= 20, sprintf("Tree tips: %d [expected ~11,010]", length(tree$tip.label))) && all_pass
}

# ========================================================================
# CHECK 3: EIGENVECTOR OUTPUT STRUCTURE
# ========================================================================
# Verify extracted eigenvectors have correct dimensions and coverage
# Expected output structure:
#   - 11,711 rows: all WFO species (including those without tree tips)
#   - 93 columns: wfo_taxon_id + 92 phylo eigenvectors (selected by broken stick)
#   - ~94% coverage: 11,010 species with eigenvectors, ~700 with NA (no tree tip)
if (file.exists(EV_FILE)) {
  df <- read_csv(EV_FILE, show_col_types = FALSE)

  # Row count: should include all 11,711 WFO species
  # Species without tree tips will have NA eigenvector values
  all_pass <- check_pass(nrow(df) == 11711, sprintf("Eigenvectors: %d rows", nrow(df))) && all_pass

  # Column count: wfo_taxon_id (1) + phylo_ev1...phylo_ev92 (92) = 93 total
  all_pass <- check_pass(ncol(df) == 93, sprintf("Columns: %d (wfo_taxon_id + 92 EVs)", ncol(df))) && all_pass

  # Count phylo eigenvector columns using naming pattern
  # Broken stick rule typically selects 92 eigenvectors from 11,010 dimensions
  phylo_cols <- grep("^phylo_ev[0-9]+$", names(df), value=TRUE)
  all_pass <- check_pass(length(phylo_cols) == 92, sprintf("Phylo eigenvectors: %d", length(phylo_cols))) && all_pass

  # Coverage check: >99.6% species should have eigenvectors
  # 11,010 with tips / 11,711 total = 94.0% coverage
  # Sample first 10 eigenvectors to compute mean coverage (faster than checking all 92)
  coverage <- mean(sapply(phylo_cols[1:10], function(col) sum(!is.na(df[[col]])) / nrow(df)))
  all_pass <- check_pass(coverage > 0.996, sprintf("Mean coverage: %.1f%% [expected >99.6%%]", coverage * 100)) && all_pass
}

# ========================================================================
# FINAL VERIFICATION STATUS
# ========================================================================
# Report overall verification result and exit with appropriate status code
# Status 0: all checks passed, pipeline can continue
# Status 1: at least one check failed, pipeline should halt
cat("\n========================================================================\n")
if (all_pass) {
  cat("✓ VERIFICATION PASSED\n========================================================================\n\n")
  invisible(TRUE)  # Return success without exiting R session
} else {
  cat("✗ VERIFICATION FAILED\n========================================================================\n\n")
  stop("Verification failed")  # Throw error instead of quitting
}

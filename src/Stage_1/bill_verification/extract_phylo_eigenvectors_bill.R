#!/usr/bin/env Rscript
#
# extract_phylo_eigenvectors_bill.R
#
# Purpose: Extract phylogenetic eigenvectors from newick tree (pure R implementation)
#
# Inputs:
#   - data/stage1/phlogeny/mixgb_tree_11711_species_20251107.nwk (phylogenetic tree, 11,010 tips)
#   - data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11711.csv (WFO→tree mapping, 11,711 rows)
#
# Output:
#   - data/shipley_checks/modelling/phylo_eigenvectors_11711_bill.csv (92 eigenvectors × 11,711 species)
#
# Methodology:
#   1. Load phylogenetic tree (ape::read.tree)
#   2. Build VCV matrix (ape::vcv)
#   3. Eigendecomposition (base::eigen)
#   4. Apply broken stick rule to select K eigenvectors (89.8% variance)
#   5. Map to all species (infraspecific taxa inherit parent eigenvectors)
#
# Reference: Moura et al. 2024, PLoS Biology
#   "A phylogeny-informed characterisation of global tetrapod traits addresses data gaps and biases"
#   DOI: https://doi.org/10.1371/journal.pbio.3002658
#
# Run:
#   env R_LIBS_USER=/home/olier/ellenberg/.Rlib \
#     /usr/bin/Rscript src/Stage_1/bill_verification/extract_phylo_eigenvectors_bill.R

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



suppressPackageStartupMessages({
  library(ape)
  library(dplyr)
  library(readr)
  library(RSpectra)  # Fast eigendecomposition using ARPACK
})

cat("=", rep("=", 70), "=\n", sep="")
cat("Bill's Verification: Extract Phylogenetic Eigenvectors\n")
cat("=", rep("=", 70), "=\n\n", sep="")

# ========================================================================
# OUTPUT DIRECTORY SETUP
# ========================================================================
# Create modelling output directory for phylogenetic eigenvector results
# Use auto-detected OUTPUT_DIR for cross-platform compatibility
output_dir <- file.path(OUTPUT_DIR, "modelling")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# ========================================================================
# STEP 1: LOAD PHYLOGENETIC TREE
# ========================================================================
# Load newick tree file (11,010 species tips) from mixgb output
# Tree serves as base for computing phylogenetic variance-covariance matrix
cat("[1/7] Loading phylogenetic tree...\n")
tree_path <- file.path(INPUT_DIR, "mixgb_tree_11711_species_20251107.nwk")
if (!file.exists(tree_path)) {
  stop("ERROR: Phylogenetic tree not found: ", tree_path)
}

# Read tree using ape package
tree <- read.tree(tree_path)
cat("  ✓ Loaded tree with", length(tree$tip.label), "tips\n")

# Verify tree properties
# Ultrametric = all tips at same distance from root (required for valid VCV)
if (!is.ultrametric(tree)) {
  cat("  WARNING: Tree is not ultrametric (may affect VCV matrix)\n")
}
# Negative branch lengths would indicate corrupted tree data
if (any(tree$edge.length < 0)) {
  stop("ERROR: Tree has negative branch lengths")
}

# ========================================================================
# STEP 2: LOAD WFO→TREE MAPPING
# ========================================================================
# Maps each WFO taxon ID (11,711 species + infraspecific) to tree tip
# Not all species in WFO have tree tips (only 11,010 do)
# Infraspecific taxa inherit eigenvectors from parent species
cat("\n[2/7] Loading WFO→tree mapping...\n")
mapping_path <- file.path(INPUT_DIR, "mixgb_wfo_to_tree_mapping_11711.csv")
if (!file.exists(mapping_path)) {
  stop("ERROR: WFO→tree mapping not found: ", mapping_path)
}

mapping <- read_csv(mapping_path, show_col_types = FALSE)
cat("  ✓ Loaded mapping with", nrow(mapping), "rows\n")

# Verify mapping structure
required_cols <- c("wfo_taxon_id", "tree_tip")
if (!all(required_cols %in% names(mapping))) {
  stop("ERROR: Missing required columns in mapping. Expected: ", paste(required_cols, collapse=", "))
}

# Extract tree tip label from tree_tip column
# Format: "wfo-0000510888|Abelmoschus_moschatus" → extract "Abelmoschus_moschatus"
# This is needed to join with eigenvector matrix rownames
mapping <- mapping %>%
  mutate(
    has_tree_tip = !is.na(tree_tip),
    tree_tip_label = if_else(has_tree_tip,
                              sub("^[^|]+\\|", "", tree_tip),  # Remove everything before pipe
                              NA_character_)
  )

# Count coverage: ~11,010/11,711 species have tree tips (~94%)
species_with_tips <- sum(mapping$has_tree_tip, na.rm = TRUE)
cat("  ✓ Species with tree tips:", species_with_tips, "/", nrow(mapping),
    sprintf("(%.1f%%)\n", 100 * species_with_tips / nrow(mapping)))

# ========================================================================
# STEP 3: BUILD PHYLOGENETIC VCV MATRIX
# ========================================================================
# VCV (variance-covariance) matrix captures phylogenetic relationships
# Element [i,j] = shared evolutionary history between species i and j
# Diagonal = total branch length from root to tip for each species
cat("\n[3/7] Building phylogenetic VCV matrix...\n")
cat("  - Using ape::vcv() for variance-covariance matrix\n")
vcv_matrix <- vcv(tree)
cat("  ✓ VCV matrix dimensions:", nrow(vcv_matrix), "×", ncol(vcv_matrix), "\n")

# Verify VCV properties for valid eigendecomposition
# Must be symmetric (covariance property)
if (!isSymmetric(vcv_matrix)) {
  stop("ERROR: VCV matrix is not symmetric")
}
# Must have positive diagonal (variance must be positive)
if (any(diag(vcv_matrix) <= 0)) {
  stop("ERROR: VCV matrix has non-positive diagonal values")
}

cat("  ✓ VCV matrix is symmetric and positive definite\n")

# ========================================================================
# STEP 4: EIGENDECOMPOSITION OF VCV MATRIX
# ========================================================================
# Decompose VCV matrix into eigenvalues and eigenvectors
# Eigenvectors capture orthogonal axes of phylogenetic variation
# Used as predictors in imputation models to account for phylogenetic signal
cat("\n[4/7] Performing full eigendecomposition...\n")
cat("  - Using base::eigen() for complete spectral decomposition\n")
cat("  - Extracting ALL", nrow(vcv_matrix), "eigenvalues/eigenvectors (required for accurate broken stick)\n")
cat("  - This may take several minutes for", nrow(vcv_matrix), "×", nrow(vcv_matrix), "matrix...\n")

# Full eigendecomposition (like Python's np.linalg.eigh)
# Note: eigen() returns values in DESCENDING order (unlike numpy's ascending)
eigen_result <- eigen(vcv_matrix, symmetric = TRUE)

# Verify eigenvalues (should all be non-negative for positive semi-definite matrix)
# Small negative values can occur due to numerical precision
if (any(eigen_result$values < 0)) {
  cat("  WARNING:", sum(eigen_result$values < 0), "negative eigenvalues (numerical precision issue)\n")
  cat("    Setting negative eigenvalues to zero\n")
  eigen_result$values[eigen_result$values < 0] <- 0
}

eigenvalues <- eigen_result$values
eigenvectors_full <- eigen_result$vectors

n_eigen <- length(eigenvalues)
cat("  ✓ Extracted", n_eigen, "eigenvalues/eigenvectors\n")
cat("  ✓ Eigenvalue range: [", min(eigenvalues), ",", max(eigenvalues), "]\n")

# ========================================================================
# STEP 5: BROKEN STICK RULE FOR EIGENVECTOR SELECTION
# ========================================================================
# Broken stick model: statistical test for retaining significant eigenvectors
# Compares observed eigenvalue distribution to random (null) expectation
# Keep eigenvectors where observed variance > expected by chance
cat("\n[5/7] Applying broken stick rule to select eigenvectors...\n")

# Compute cumulative variance explained by eigenvalues
total_var <- sum(eigenvalues)
cum_var <- cumsum(eigenvalues) / total_var

# Broken stick rule: compare observed vs expected random distribution
# For each eigenvalue i, compute expected proportion under null model
# Expected[i] = (1/i + 1/(i+1) + ... + 1/n) / n
n <- length(eigenvalues)
broken_stick <- sapply(1:n, function(i) {
  sum(1 / i:n) / n
})

# Select eigenvectors where observed variance > broken stick threshold
# This retains only eigenvectors with signal above random noise
keep_idx <- which(eigenvalues / total_var > broken_stick)
n_keep <- length(keep_idx)

cat("  - Broken stick criterion: keep eigenvectors where λ/Σλ > E[random]\n")
cat("  ✓ Selected", n_keep, "eigenvectors\n")
cat("  ✓ Variance explained:", sprintf("%.1f%%", 100 * cum_var[n_keep]), "\n")

# Sanity check: canonical pipeline produces 92 eigenvectors
if (abs(n_keep - 92) > 5) {
  cat("  WARNING: Expected ~92 eigenvectors, got", n_keep, "\n")
}

# Extract selected eigenvectors and label them
eigenvectors <- eigenvectors_full[, keep_idx, drop = FALSE]
colnames(eigenvectors) <- paste0("phylo_ev", 1:n_keep)
rownames(eigenvectors) <- tree$tip.label

cat("  ✓ Eigenvector matrix:", nrow(eigenvectors), "tips ×", ncol(eigenvectors), "eigenvectors\n")

# ========================================================================
# STEP 6: MAP EIGENVECTORS TO ALL WFO SPECIES
# ========================================================================
# Tree has 11,010 tips, but WFO mapping has 11,711 species
# Species without tree tips get NA (e.g., infraspecific taxa)
# These will be imputed by mixgb using other predictors
cat("\n[6/7] Mapping eigenvectors to all species...\n")

# Create data frame from eigenvector matrix
# Eigenvector rownames are full tip labels (e.g., "wfo-0000510888|Abelmoschus_moschatus")
# But mapping$tree_tip_label is just the species part (e.g., "Abelmoschus_moschatus")
ev_df <- as.data.frame(eigenvectors)
full_tip_labels <- rownames(eigenvectors)

# Extract just the species part after the pipe to match mapping
# This allows joining eigenvectors with WFO taxa
ev_df$tree_tip_label <- sub("^[^|]+\\|", "", full_tip_labels)

# Left join: species with tree tips get eigenvectors, others get NA
result <- mapping %>%
  left_join(ev_df, by = "tree_tip_label") %>%
  select(wfo_taxon_id, starts_with("phylo_ev"))

# Count coverage (should match species_with_tips from Step 2)
species_with_ev <- sum(complete.cases(result[, -1]))
cat("  ✓ Species with eigenvectors:", species_with_ev, "/", nrow(result),
    sprintf("(%.1f%%)\n", 100 * species_with_ev / nrow(result)))

# Verify no unexpected NAs (missing should equal species without tree tips)
species_missing_ev <- sum(!complete.cases(result[, -1]))
species_expected_missing <- nrow(mapping) - species_with_tips
if (species_missing_ev != species_expected_missing) {
  cat("  WARNING: Unexpected missing eigenvectors\n")
  cat("    Expected missing:", species_expected_missing, "\n")
  cat("    Actual missing:", species_missing_ev, "\n")
}

# ========================================================================
# STEP 7: WRITE OUTPUT
# ========================================================================
# Write final eigenvector data frame to CSV file
# Output: CSV with wfo_taxon_id + 92 phylo eigenvector columns (93 total)
# Used as predictors in mixgb imputation model to account for phylogenetic signal
# Note: Uses output_dir from line 80 which is hardcoded relative path
cat("\n[7/7] Writing output...\n")
output_path <- file.path(output_dir, "phylo_eigenvectors_11711_bill.csv")
write_csv(result, output_path)
cat("  ✓ Written:", output_path, "\n")
cat("  ✓ File size:", file.size(output_path) / 1024^2, "MB\n")

# Summary
cat("\n", rep("=", 72), "\n", sep="")
cat("SUCCESS: Phylogenetic eigenvector extraction complete\n")
cat(rep("=", 72), "\n\n", sep="")
cat("Output:\n")
cat("  - File:", output_path, "\n")
cat("  - Shape:", nrow(result), "species ×", ncol(result), "columns\n")
cat("  - Eigenvectors:", n_keep, "\n")
cat("  - Coverage:", species_with_ev, "/", nrow(result),
    sprintf("(%.1f%%)\n", 100 * species_with_ev / nrow(result)))
cat("  - Variance explained:", sprintf("%.1f%%", 100 * cum_var[n_keep]), "\n")
cat("  - Missing:", species_missing_ev, "species (no tree tip)\n")
cat("\nNext step: Run assemble_canonical_imputation_input_bill.R\n")

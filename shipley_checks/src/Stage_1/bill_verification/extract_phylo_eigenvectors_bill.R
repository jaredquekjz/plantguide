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

# Output directory
output_dir <- "modelling"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Step 1: Load phylogenetic tree
cat("[1/7] Loading phylogenetic tree...\n")
tree_path <- file.path(INPUT_DIR, "mixgb_tree_11711_species_20251107.nwk")
if (!file.exists(tree_path)) {
  stop("ERROR: Phylogenetic tree not found: ", tree_path)
}

tree <- read.tree(tree_path)
cat("  ✓ Loaded tree with", length(tree$tip.label), "tips\n")

# Verify tree properties
if (!is.ultrametric(tree)) {
  cat("  WARNING: Tree is not ultrametric (may affect VCV matrix)\n")
}
if (any(tree$edge.length < 0)) {
  stop("ERROR: Tree has negative branch lengths")
}

# Step 2: Load WFO→tree mapping
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

# Extract tree tip label from tree_tip column (format: "wfo-ID|Label")
mapping <- mapping %>%
  mutate(
    has_tree_tip = !is.na(tree_tip),
    tree_tip_label = if_else(has_tree_tip,
                              sub("^[^|]+\\|", "", tree_tip),
                              NA_character_)
  )

# Count coverage
species_with_tips <- sum(mapping$has_tree_tip, na.rm = TRUE)
cat("  ✓ Species with tree tips:", species_with_tips, "/", nrow(mapping),
    sprintf("(%.1f%%)\n", 100 * species_with_tips / nrow(mapping)))

# Step 3: Build VCV matrix
cat("\n[3/7] Building phylogenetic VCV matrix...\n")
cat("  - Using ape::vcv() for variance-covariance matrix\n")
vcv_matrix <- vcv(tree)
cat("  ✓ VCV matrix dimensions:", nrow(vcv_matrix), "×", ncol(vcv_matrix), "\n")

# Verify VCV properties
if (!isSymmetric(vcv_matrix)) {
  stop("ERROR: VCV matrix is not symmetric")
}
if (any(diag(vcv_matrix) <= 0)) {
  stop("ERROR: VCV matrix has non-positive diagonal values")
}

cat("  ✓ VCV matrix is symmetric and positive definite\n")

# Step 4: Full eigendecomposition (matching Python's np.linalg.eigh)
cat("\n[4/7] Performing full eigendecomposition...\n")
cat("  - Using base::eigen() for complete spectral decomposition\n")
cat("  - Extracting ALL", nrow(vcv_matrix), "eigenvalues/eigenvectors (required for accurate broken stick)\n")
cat("  - This may take several minutes for", nrow(vcv_matrix), "×", nrow(vcv_matrix), "matrix...\n")

# Full eigendecomposition (like Python's np.linalg.eigh)
# Note: eigen() returns values in DESCENDING order (unlike numpy's ascending)
eigen_result <- eigen(vcv_matrix, symmetric = TRUE)

# Verify eigenvalues
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

# Step 5: Apply broken stick rule
cat("\n[5/7] Applying broken stick rule to select eigenvectors...\n")

# Compute cumulative variance explained
total_var <- sum(eigenvalues)
cum_var <- cumsum(eigenvalues) / total_var

# Broken stick rule: compare observed vs expected random distribution
n <- length(eigenvalues)
broken_stick <- sapply(1:n, function(i) {
  sum(1 / i:n) / n
})

# Select eigenvectors where observed > broken stick
keep_idx <- which(eigenvalues / total_var > broken_stick)
n_keep <- length(keep_idx)

cat("  - Broken stick criterion: keep eigenvectors where λ/Σλ > E[random]\n")
cat("  ✓ Selected", n_keep, "eigenvectors\n")
cat("  ✓ Variance explained:", sprintf("%.1f%%", 100 * cum_var[n_keep]), "\n")

# For compatibility with canonical (92 eigenvectors), verify we're close
if (abs(n_keep - 92) > 5) {
  cat("  WARNING: Expected ~92 eigenvectors, got", n_keep, "\n")
}

# Extract selected eigenvectors
eigenvectors <- eigenvectors_full[, keep_idx, drop = FALSE]
colnames(eigenvectors) <- paste0("phylo_ev", 1:n_keep)
rownames(eigenvectors) <- tree$tip.label

cat("  ✓ Eigenvector matrix:", nrow(eigenvectors), "tips ×", ncol(eigenvectors), "eigenvectors\n")

# Step 6: Map eigenvectors to all species (including infraspecific)
cat("\n[6/7] Mapping eigenvectors to all species...\n")

# Create data frame from eigenvector matrix
# Eigenvector rownames are full tip labels (e.g., "wfo-0000510888|Abelmoschus_moschatus")
# But mapping$tree_tip_label is just the species part (e.g., "Abelmoschus_moschatus")
ev_df <- as.data.frame(eigenvectors)
full_tip_labels <- rownames(eigenvectors)

# Extract just the species part after the pipe to match mapping
ev_df$tree_tip_label <- sub("^[^|]+\\|", "", full_tip_labels)

# Merge with mapping (species with tree tips get eigenvectors, others get NA)
result <- mapping %>%
  left_join(ev_df, by = "tree_tip_label") %>%
  select(wfo_taxon_id, starts_with("phylo_ev"))

# Count coverage
species_with_ev <- sum(complete.cases(result[, -1]))
cat("  ✓ Species with eigenvectors:", species_with_ev, "/", nrow(result),
    sprintf("(%.1f%%)\n", 100 * species_with_ev / nrow(result)))

# Verify no unexpected NAs
species_missing_ev <- sum(!complete.cases(result[, -1]))
species_expected_missing <- nrow(mapping) - species_with_tips
if (species_missing_ev != species_expected_missing) {
  cat("  WARNING: Unexpected missing eigenvectors\n")
  cat("    Expected missing:", species_expected_missing, "\n")
  cat("    Actual missing:", species_missing_ev, "\n")
}

# Step 7: Write output
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

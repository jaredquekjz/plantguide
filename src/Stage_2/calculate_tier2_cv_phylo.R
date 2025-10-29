#!/usr/bin/env Rscript
# Calculate context-matched p_phylo for Tier 2 CV sets
# Date: 2025-10-29
# Issue: Original p_phylo calculated on 10,977-species tree, but CV trains on ~6,200 per axis

suppressPackageStartupMessages({
  library(ape)
  library(dplyr)
  library(readr)
  library(arrow)
})

cat("======================================================================\n")
cat("TIER 2 CV PHYLO PREDICTOR CALCULATOR\n")
cat("======================================================================\n")
cat("Calculating context-matched p_phylo for each axis's CV set\n\n")

# Load full tree
tree_path <- "data/phylogeny/mixgb_tree_11676_species_20251027.nwk"
if (!file.exists(tree_path)) {
  stop("Tree file not found: ", tree_path)
}

cat("[tree] Loading full tree:", tree_path, "\n")
phy <- read.tree(tree_path)
cat("[tree] Loaded", length(phy$tip.label), "tips\n\n")

# Parse tip labels (format: wfo-ID|Species_name)
parse_tip_label <- function(label) {
  parts <- strsplit(label, "\\|")[[1]]
  if (length(parts) == 2) {
    return(parts[1])  # Return WFO ID
  }
  return(label)
}

phy$tip.label <- sapply(phy$tip.label, parse_tip_label)
cat("[tree] Parsed tip labels to WFO IDs\n\n")

# Shipley phylo predictor formula
compute_p_phylo <- function(cop, values, x_exp = 2, k_trunc = 0) {
  # cop: cophenetic distance matrix
  # values: named vector of EIVE values (names = species IDs)
  # x_exp: exponent for distance weighting (default 2)
  # k_trunc: threshold distance (0 = no truncation)

  n <- nrow(cop)
  W <- matrix(0, nrow = n, ncol = n)
  rownames(W) <- rownames(cop)
  colnames(W) <- colnames(cop)

  # Calculate weights: w_ij = 1 / d_ij^x
  mask <- !diag(n)
  Dmat <- cop

  if (k_trunc > 0) {
    mask <- mask & (Dmat <= k_trunc)
  }

  W[mask] <- 1 / (Dmat[mask]^x_exp)

  # Compute weighted average
  p_vals <- rep(NA_real_, n)
  names(p_vals) <- rownames(cop)

  for (i in seq_len(n)) {
    weights <- W[i, ]
    sum_weights <- sum(weights, na.rm = TRUE)

    if (sum_weights > 0) {
      # Match EIVE values to neighbors
      neighbor_eive <- values[colnames(W)]
      neighbor_eive[is.na(neighbor_eive)] <- 0  # Missing neighbors contribute 0

      p_vals[i] <- sum(weights * neighbor_eive, na.rm = TRUE) / sum_weights
    } else {
      # No neighbors: use mean
      p_vals[i] <- mean(values, na.rm = TRUE)
    }
  }

  return(p_vals)
}

# Load production master to get EIVE values
production_path <- "model_data/outputs/perm2_production/perm2_11680_complete_final_20251028.parquet"
if (!file.exists(production_path)) {
  stop("Production master not found: ", production_path)
}

cat("[data] Loading production master for EIVE values\n")
production <- read_parquet(production_path)
cat("[data] Loaded", nrow(production), "species\n\n")

# Process each axis
axes <- c("L", "T", "M", "N", "R")
results <- list()

for (axis in axes) {
  cat("======================================================================\n")
  cat("Processing", axis, "axis\n")
  cat("======================================================================\n")

  # Load axis feature table to get species list
  features_path <- paste0("model_data/inputs/stage2_features/", axis, "_features_11680_20251029.csv")
  if (!file.exists(features_path)) {
    cat("[error] Feature file not found:", features_path, "\n")
    next
  }

  features <- read_csv(features_path, show_col_types = FALSE)
  axis_species <- features$wfo_taxon_id
  n_species <- length(axis_species)

  cat("[", axis, "] Feature table has", n_species, "species\n")

  # Get EIVE values for this axis
  eive_col <- paste0("EIVEres-", axis)
  eive_data <- production %>%
    filter(wfo_taxon_id %in% axis_species) %>%
    select(wfo_taxon_id, !!sym(eive_col))

  if (nrow(eive_data) != n_species) {
    cat("[warn] EIVE coverage mismatch: expected", n_species, "got", nrow(eive_data), "\n")
  }

  # Convert to named vector
  eive_values <- setNames(eive_data[[eive_col]], eive_data$wfo_taxon_id)
  n_with_eive <- sum(!is.na(eive_values))
  cat("[", axis, "] EIVE coverage:", n_with_eive, "/", n_species, "\n")

  # Prune tree to axis species
  tips_to_keep <- intersect(axis_species, phy$tip.label)
  n_matched <- length(tips_to_keep)
  cat("[", axis, "] Species matched to tree:", n_matched, "/", n_species, "\n")

  if (n_matched < 100) {
    cat("[error] Too few species matched to tree\n")
    next
  }

  phy_pruned <- keep.tip(phy, tips_to_keep)
  cat("[", axis, "] Pruned tree to", length(phy_pruned$tip.label), "tips\n")

  # Calculate cophenetic distances
  cop <- cophenetic.phylo(phy_pruned)
  cat("[", axis, "] Calculated cophenetic distances\n")

  # Calculate p_phylo
  p_phylo <- compute_p_phylo(cop, eive_values, x_exp = 2, k_trunc = 0)
  cat("[", axis, "] Calculated p_phylo (x_exp=2, k_trunc=0)\n")

  # Check coverage
  n_p_phylo <- sum(!is.na(p_phylo))
  pct_coverage <- 100 * n_p_phylo / length(p_phylo)
  cat("[", axis, "] p_phylo coverage:", n_p_phylo, "/", length(p_phylo),
      sprintf("(%.1f%%)\n", pct_coverage))

  # Create output data frame
  p_phylo_df <- data.frame(
    wfo_taxon_id = names(p_phylo),
    p_phylo = as.numeric(p_phylo),
    stringsAsFactors = FALSE
  )

  # Save
  output_path <- paste0("model_data/outputs/p_phylo_tier2_cv/p_phylo_", axis,
                       "_tier2_cv_20251029.csv")
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  write_csv(p_phylo_df, output_path)

  cat("[", axis, "] Saved:", output_path, "\n")
  cat("[", axis, "] Summary: mean=", round(mean(p_phylo, na.rm=TRUE), 3),
      ", sd=", round(sd(p_phylo, na.rm=TRUE), 3), "\n\n")

  results[[axis]] <- list(
    n_species = n_species,
    n_matched = n_matched,
    n_p_phylo = n_p_phylo,
    output_path = output_path
  )
}

cat("======================================================================\n")
cat("SUMMARY\n")
cat("======================================================================\n")

for (axis in names(results)) {
  r <- results[[axis]]
  cat(sprintf("%-6s: %d species, %d matched tree, %d p_phylo calculated\n",
              paste0(axis, "-axis"), r$n_species, r$n_matched, r$n_p_phylo))
}

cat("\nContext-matched p_phylo files saved to:\n")
cat("  model_data/outputs/p_phylo_tier2_cv/p_phylo_{L,T,M,N,R}_tier2_cv_20251029.csv\n")
cat("\nNext step: Update feature tables with corrected p_phylo\n")
cat("  python src/Stage_2/update_tier2_features_with_cv_phylo.py\n\n")

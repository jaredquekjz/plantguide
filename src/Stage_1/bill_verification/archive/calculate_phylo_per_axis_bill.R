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
cat("BILL'S VERIFICATION: PER-AXIS PHYLO PREDICTOR CALCULATOR\n")
cat("======================================================================\n")
cat("Calculating context-matched p_phylo for each axis from Bill's pipeline\n\n")

# Load full tree (Bill's tree with 11,711 species)
tree_path <- "data/stage1/phlogeny/mixgb_tree_11711_species_20251107.nwk"
if (!file.exists(tree_path)) {
  stop("Tree file not found: ", tree_path)
}

cat("[tree] Loading full tree:", tree_path, "\n")
phy <- read.tree(tree_path)
cat("[tree] Loaded", length(phy$tip.label), "tips\n\n")

# Load mapping to convert WFO IDs to tree tips
mapping_path <- "data/stage1/phlogeny/mixgb_wfo_to_tree_mapping_11711.csv"
if (!file.exists(mapping_path)) {
  stop("Mapping file not found: ", mapping_path)
}

cat("[tree] Loading WFO-to-tree mapping\n")
mapping <- read_csv(mapping_path, show_col_types = FALSE)
cat("[tree] Loaded mapping for", nrow(mapping), "species\n\n")

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

# Load Bill's canonical input to get EIVE values
bill_input_path <- "data/shipley_checks/modelling/canonical_imputation_input_11711_bill.csv"
if (!file.exists(bill_input_path)) {
  stop("Bill's input not found: ", bill_input_path)
}

cat("[data] Loading Bill's canonical input for EIVE values\n")
bill_data <- read_csv(bill_input_path, show_col_types = FALSE)
cat("[data] Loaded", nrow(bill_data), "species\n\n")

# Map WFO IDs to tree tips
bill_data <- bill_data %>%
  left_join(mapping %>% select(wfo_taxon_id, tree_tip), by = "wfo_taxon_id")

# Process each axis
axes <- c("L", "T", "M", "N", "R")
results <- list()

for (axis in axes) {
  cat("======================================================================\n")
  cat("Processing", axis, "axis\n")
  cat("======================================================================\n")

  # Get EIVE column (readr::read_csv preserves hyphens)
  eive_col <- paste0("EIVEres-", axis)

  # Filter to species with non-NA EIVE for this axis
  axis_data <- bill_data %>%
    filter(!is.na(!!sym(eive_col)), !is.na(tree_tip))

  n_species <- nrow(axis_data)
  cat("[", axis, "] Species with observed EIVE:", n_species, "\n")

  # Get EIVE values indexed by tree tips (not WFO IDs)
  eive_values <- setNames(axis_data[[eive_col]], axis_data$tree_tip)
  n_with_eive <- sum(!is.na(eive_values))
  cat("[", axis, "] EIVE values ready:", n_with_eive, "\n")

  # Prune tree to species with this axis's EIVE
  tips_to_keep <- axis_data$tree_tip
  n_matched <- length(tips_to_keep)
  cat("[", axis, "] Tips to keep in tree:", n_matched, "\n")

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

  # Create output data frame - map tree tips back to WFO IDs
  tree_to_wfo <- setNames(axis_data$wfo_taxon_id, axis_data$tree_tip)
  wfo_ids <- tree_to_wfo[names(p_phylo)]

  p_phylo_df <- data.frame(
    wfo_taxon_id = wfo_ids,
    p_phylo = as.numeric(p_phylo),
    stringsAsFactors = FALSE
  )

  # Save to Bill's verification directory
  output_path <- paste0("data/shipley_checks/imputation/p_phylo_", axis, "_bill.csv")
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
cat("BILL'S VERIFICATION SUMMARY\n")
cat("======================================================================\n")

for (axis in names(results)) {
  r <- results[[axis]]
  cat(sprintf("%-6s: %d species, %d matched tree, %d p_phylo calculated\n",
              paste0(axis, "-axis"), r$n_species, r$n_matched, r$n_p_phylo))
}

cat("\nContext-matched p_phylo files saved to:\n")
cat("  data/shipley_checks/imputation/p_phylo_{L,T,M,N,R}_bill.csv\n")
cat("\nNext step: Merge p_phylo files and add to complete imputed dataset\n\n")

#!/usr/bin/env Rscript
# verify_phylo_eigenvectors_bill.R - Verify phylogenetic eigenvector extraction
suppressPackageStartupMessages({library(dplyr); library(readr); library(ape)})
check_pass <- function(cond, msg) { stat <- if (cond) "✓" else "✗"; cat(sprintf("  %s %s\n", stat, msg)); return(cond) }

cat("========================================================================\n")
cat("VERIFICATION: Phylogenetic Eigenvectors\n")
cat("========================================================================\n\n")

TREE_FILE <- "data/stage1/phlogeny/mixgb_tree_11711_species_20251107.nwk"
EV_FILE <- "data/shipley_checks/modelling/phylo_eigenvectors_11711_bill.csv"
all_pass <- TRUE

all_pass <- check_pass(file.exists(TREE_FILE), "Tree file exists") && all_pass
all_pass <- check_pass(file.exists(EV_FILE), "Eigenvector file exists") && all_pass

if (file.exists(TREE_FILE)) {
  tree <- read.tree(TREE_FILE)
  all_pass <- check_pass(abs(length(tree$tip.label) - 11010) <= 20, sprintf("Tree tips: %d [expected ~11,010]", length(tree$tip.label))) && all_pass
}

if (file.exists(EV_FILE)) {
  df <- read_csv(EV_FILE, show_col_types = FALSE)
  all_pass <- check_pass(nrow(df) == 11711, sprintf("Eigenvectors: %d rows", nrow(df))) && all_pass
  all_pass <- check_pass(ncol(df) == 93, sprintf("Columns: %d (wfo_taxon_id + 92 EVs)", ncol(df))) && all_pass
  
  phylo_cols <- grep("^phylo_ev[0-9]+$", names(df), value=TRUE)
  all_pass <- check_pass(length(phylo_cols) == 92, sprintf("Phylo eigenvectors: %d", length(phylo_cols))) && all_pass
  
  coverage <- mean(sapply(phylo_cols[1:10], function(col) sum(!is.na(df[[col]])) / nrow(df)))
  all_pass <- check_pass(coverage > 0.996, sprintf("Mean coverage: %.1f%% [expected >99.6%%]", coverage * 100)) && all_pass
}

cat("\n========================================================================\n")
if (all_pass) { cat("✓ VERIFICATION PASSED\n========================================================================\n\n"); quit(status = 0)
} else { cat("✗ VERIFICATION FAILED\n========================================================================\n\n"); quit(status = 1) }

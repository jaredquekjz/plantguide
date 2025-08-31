#!/usr/bin/env Rscript

# Blend out-of-fold SEM pwSEM predictions with a phylogenetic neighbor predictor
# using the exact folds produced by run_sem_pwsem.R. This guarantees the SEM-only
# baseline (alpha=0) matches the Stage 4 CV metrics, and computes the lift.

suppressPackageStartupMessages({
  library(ape)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a) && a != "") a else b

parse_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  kv <- list()
  for (i in seq_along(args)) {
    if (grepl("^--", args[[i]])) {
      key <- sub("^--", "", args[[i]])
      val <- if (i < length(args) && !grepl("^--", args[[i+1]])) args[[i+1]] else ""
      kv[[key]] <- val
    }
  }
  kv
}

args <- parse_args()
pwsem_dir <- args[["pwsem_dir"]] %||% "artifacts/stage4_sem_pwsem_blend_repro"
input_csv <- args[["input_csv"]] %||% "artifacts/model_data_complete_case_with_myco.csv"
species_col <- args[["species_col"]] %||% "wfo_accepted_name"
phylo_newick <- args[["phylogeny_newick"]] %||% "data/phylogeny/eive_try_tree.nwk"
xexp <- as.numeric(args[["x"]] %||% 2)
alpha_grid <- as.numeric(strsplit(args[["alpha_grid"]] %||% "0,0.25,0.5,0.75,1", ",")[[1]])
out_csv <- args[["output_csv"]] %||% "artifacts/pwsem_blend_cv_results.csv"

stopifnot(file.exists(pwsem_dir), file.exists(input_csv), file.exists(phylo_newick))
df <- read.csv(input_csv, stringsAsFactors = FALSE, check.names = FALSE)
stopifnot(species_col %in% names(df))

axes <- c("L","T","M","R","N")
axis_to_col <- setNames(paste0("EIVEres-", axes), axes)

tree <- ape::read.tree(phylo_newick)
tips <- tree$tip.label

blend_axis <- function(axis) {
  preds_path <- file.path(pwsem_dir, paste0("sem_pwsem_", axis, "_preds.csv"))
  stopifnot(file.exists(preds_path))
  pr <- read.csv(preds_path, stringsAsFactors = FALSE)
  # Sanity
  stopifnot(all(c("rep","fold","id","y_true","y_pred") %in% names(pr)))
  # Prepare E vector for donors (reference truth)
  # Map ids to input_csv
  ref_idx <- match(pr$id, df[[species_col]])
  # Some ids may not resolve because pwsem may filter missing target rows; drop later if needed
  E_col <- axis_to_col[[axis]]
  # Build distance matrix D for all species found in preds that exist in tree
  ids <- unique(pr$id)
  ids_tips <- gsub(" ", "_", ids, fixed = TRUE)
  have_tip <- ids_tips %in% tips
  ids_keep <- ids[have_tip]
  ids_tips_keep <- ids_tips[have_tip]
  tree2 <- ape::keep.tip(tree, ids_tips_keep)
  cop <- ape::cophenetic.phylo(tree2)
  # positions
  pos <- match(gsub(" ", "_", pr$id, fixed = TRUE), rownames(cop))
  # If some rows are not in the tree, we will handle via fallback to train mean
  # Pre-compute donor EIVE per species (from input_csv)
  eive_map <- setNames(df[[E_col]][match(rownames(cop), gsub(" ", "_", df[[species_col]], fixed=TRUE))], rownames(cop))

  alpha_grid2 <- sort(unique(pmin(pmax(alpha_grid, 0), 1)))
  res_axis <- list()
  for (a in alpha_grid2) {
    # Accumulate per rep-fold R2 and MAE
    groups <- unique(pr[, c("rep","fold")])
    r2s <- c(); maes <- c()
    for (i in seq_len(nrow(groups))) {
      r <- groups$rep[i]; k <- groups$fold[i]
      idx <- which(pr$rep == r & pr$fold == k)
      test_ids <- pr$id[idx]
      test_pos <- pos[idx]
      all_ids <- rownames(cop)
      test_mask <- all_ids %in% gsub(" ", "_", test_ids, fixed = TRUE)
      # donors = all_ids[!test_mask]
      # Build weights W for this test set using donors only
      Dsub <- cop[test_pos, , drop = FALSE]
      W <- matrix(0, nrow(Dsub), ncol(Dsub))
      ok <- is.finite(Dsub) & (Dsub > 0)
      W[ok] <- 1 / (Dsub[ok]^xexp)
      # zero out self and test donors columns
      # Remove any rows where test_pos is NA (species not in tree)
      na_rows <- which(is.na(test_pos))
      if (length(na_rows)) {
        W[na_rows, ] <- 0
      }
      # zero weights for donor columns that are test species
      if (length(test_pos)) {
        W[, test_pos[is.finite(test_pos)]] <- 0
      }
      # Compute p_k using donors' EIVE
      Ek <- as.numeric(eive_map[colnames(Dsub)])
      num <- W %*% matrix(Ek, ncol=1)
      den <- rowSums(W)
      # fallback to training mean if denom is 0 or NA
      mu_tr <- mean(Ek[colSums(W)>0], na.rm = TRUE)
      p_te <- as.numeric(ifelse(den > .Machine$double.eps, num/den, mu_tr))
      # Blend
      y_sem <- pr$y_pred[idx]
      y_true <- pr$y_true[idx]
      yhat <- (1 - a) * y_sem + a * p_te
      # Metrics with test-set mean
      sse <- sum((y_true - yhat)^2)
      sst <- sum((y_true - mean(y_true))^2)
      r2s <- c(r2s, 1 - sse / (ifelse(sst > 0, sst, .Machine$double.eps)))
      maes <- c(maes, mean(abs(y_true - yhat)))
    }
    res_axis[[length(res_axis)+1]] <- data.frame(
      axis = paste0("EIVEres-", axis),
      alpha = a,
      r2_mean = mean(r2s),
      mae_mean = mean(maes),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, res_axis)
}

all_res <- do.call(rbind, lapply(axes, blend_axis))
all_res <- all_res[order(all_res$axis, all_res$alpha), ]
dir.create(dirname(out_csv), recursive = TRUE, showWarnings = FALSE)
write.csv(all_res, out_csv, row.names = FALSE)
cat(sprintf("Wrote blended results using pwSEM CV folds: %s (rows %d)\n", out_csv, nrow(all_res)))


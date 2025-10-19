#!/usr/bin/env Rscript

# Evaluate a phylogenetic neighbor predictor for EIVE axes via small CV
#
# Intuition: For each species j, predict its EIVE_k as a weighted average of
# other species' EIVE_k, with weights decaying by phylogenetic distance:
#   p_ik(j) = sum_i w_ij * E_k(i) / sum_i w_ij,   w_ij = 1 / d_ij^x, i != j
#
# Implementation details:
# - Fold-safe CV: weights are computed using only training species (rows of W
#   for held-out species are zeroed), so there is no leakage of test EIVE into
#   predictions.
# - Species alignment: matches dataset species to Newick tip labels; handles
#   spaces vs underscores.
# - Stability: guards against zero denominators; can optionally truncate to
#   k-nearest neighbors among training species for speed/robustness.
#
# CLI
#   Rscript src/Stage_5_Apply_Mean_Structure/eval_phylo_neighbor_cv.R \
#     --input_csv artifacts/model_data_complete_case.csv \
#     --species_col wfo_accepted_name \
#     --eive_cols EIVEres-L,EIVEres-T,EIVEres-M,EIVEres-R,EIVEres-N \
#     --phylogeny_newick data/phylogeny/eive_try_tree.nwk \
#     --x_grid 0.5,1,1.5,2 \
#     --k_trunc 0 \
#     --repeats 2 --folds 5 --seed 42 \
#     --output_csv artifacts/phylo_neighbor_cv_results.csv
#
# Output CSV columns:
#   axis, x, k_trunc, repeats, folds, n_used, r2_mean, r2_sd, mae_mean, mae_sd

suppressPackageStartupMessages({
  library(ape)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a) && a != "") a else b

parse_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  keyvals <- list()
  for (i in seq_along(args)) {
    if (grepl("^--", args[[i]])) {
      key <- sub("^--", "", args[[i]])
      val <- if (i < length(args) && !grepl("^--", args[[i+1]])) args[[i+1]] else ""
      keyvals[[key]] <- val
    }
  }
  keyvals
}

args <- parse_args()
input_csv <- args[["input_csv"]] %||% "artifacts/model_data_complete_case.csv"
species_col <- args[["species_col"]] %||% "wfo_accepted_name"
eive_cols <- strsplit(args[["eive_cols"]] %||% "EIVEres-L,EIVEres-T,EIVEres-M,EIVEres-R,EIVEres-N", ",")[[1]]
phylo_newick <- args[["phylogeny_newick"]] %||% "data/phylogeny/eive_try_tree.nwk"
x_grid <- as.numeric(strsplit(args[["x_grid"]] %||% "0.5,1,1.5,2", ",")[[1]])
k_trunc <- as.integer(args[["k_trunc"]] %||% 0)
repeats <- as.integer(args[["repeats"]] %||% 2)
folds <- as.integer(args[["folds"]] %||% 5)
seed <- as.integer(args[["seed"]] %||% 42)
out_csv <- args[["output_csv"]] %||% "artifacts/phylo_neighbor_cv_results.csv"

cat(sprintf("Effective parameters:\n  input_csv=%s\n  species_col=%s\n  eive_cols=%s\n  phylogeny_newick=%s\n  x_grid=%s\n  k_trunc=%d\n  repeats=%d\n  folds=%d\n  seed=%d\n  output_csv=%s\n",
            input_csv, species_col, paste(eive_cols, collapse=","), phylo_newick,
            paste(x_grid, collapse=","), k_trunc, repeats, folds, seed, out_csv))

stopifnot(file.exists(input_csv))
stopifnot(file.exists(phylo_newick))

dt <- read.csv(input_csv, stringsAsFactors = FALSE, check.names = FALSE)
stopifnot(species_col %in% names(dt))
missing_cols <- setdiff(eive_cols, names(dt))
if (length(missing_cols) > 0) {
  stop(sprintf("Missing EIVE columns in input: %s", paste(missing_cols, collapse=",")))
}

# Keep only rows with all requested EIVE present (complete cases for targets)
dt_sub <- dt[complete.cases(dt[, eive_cols, drop = FALSE]), , drop = FALSE]
cat(sprintf("Rows with complete EIVE targets: %d (of %d)\n", nrow(dt_sub), nrow(dt)))

# Read tree and compute cophenetic distances
tree <- read.tree(phylo_newick)
tip_labels <- tree$tip.label

# Normalize species names (spaces vs underscores)
species_raw <- dt_sub[[species_col]]
species_norm_space <- gsub("_", " ", tip_labels, fixed = TRUE)
species_norm_underscore <- gsub(" ", "_", species_raw, fixed = TRUE)

# Try matching by exact species names to tip labels (underscore form)
common_idx <- match(species_norm_underscore, tip_labels)
has_match <- !is.na(common_idx)

if (!any(has_match)) {
  # Fallback: try matching tip labels with spaces
  common_idx2 <- match(species_raw, species_norm_space)
  has_match <- !is.na(common_idx2)
  if (!any(has_match)) {
    stop("No species in input matched the tree tip labels after normalization.")
  }
  # Map to tip indices
  tip_idx <- common_idx2[has_match]
} else {
  tip_idx <- common_idx[has_match]
}

dt_match <- dt_sub[has_match, , drop = FALSE]
cat(sprintf("Matched species to tree: %d\n", nrow(dt_match)))

# Prune tree to matched tips to keep cophenetic matrix small and aligned
tips_keep <- tip_labels[unique(tip_idx)]
tree2 <- keep.tip(tree, tips_keep)
cop <- cophenetic.phylo(tree2)  # matrix with dim = number of kept tips

# Rebuild a distance matrix D aligned to dt_match order
tip_pos <- match(ifelse(!is.na(match(species_norm_underscore[has_match], colnames(cop))),
                          species_norm_underscore[has_match],
                          colnames(cop)[match(dt_match[[species_col]], gsub("_", " ", colnames(cop), fixed = TRUE))]),
                 colnames(cop))

if (any(is.na(tip_pos))) {
  # Drop rows that still failed to map
  keep_rows <- which(!is.na(tip_pos))
  dt_match <- dt_match[keep_rows, , drop = FALSE]
  tip_pos <- tip_pos[keep_rows]
  cat(sprintf("Dropped unmatched after pruning: now %d rows\n", nrow(dt_match)))
}

D <- cop[tip_pos, tip_pos, drop = FALSE]
diag(D) <- 0  # ensure exact zeros on diagonal
n <- nrow(D)

if (n < 50) {
  warning(sprintf("Only %d species matched the tree and EIVE columns; results may be unstable.", n))
}

# Helper: compute p_ik for vector E using weight decay exponent x and optional k-NN truncation.
# Fold-safety: zero out rows of W for indices not in train_idx.
pvalue_cv <- function(D, E, train_idx, x = 1, k_trunc = 0L) {
  n <- length(E)
  W <- matrix(0, n, n)
  pos <- which(D > 0)
  W[pos] <- 1 / (D[pos]^x)
  # zero-out self just in case
  diag(W) <- 0
  # keep only training species as contributors (rows)
  keep_row <- logical(n); keep_row[train_idx] <- TRUE
  W[!keep_row, ] <- 0
  if (k_trunc > 0L) {
    for (j in seq_len(n)) {
      # order ascending distance among training species only
      dcol <- D[, j]
      ord <- order(dcol, na.last = NA)
      ord <- ord[ord %in% train_idx & dcol[ord] > 0]
      if (length(ord) > k_trunc) {
        drop_rows <- setdiff(train_idx, ord[seq_len(k_trunc)])
        if (length(drop_rows) > 0) W[drop_rows, j] <- 0
      }
    }
  }
  top <- as.numeric(crossprod(E, W))
  bot <- colSums(W)
  # Guard small denominators; fallback to training mean
  mu <- mean(E[train_idx])
  pred <- ifelse(bot > .Machine$double.eps, top / bot, mu)
  pred
}

# CV splits
set.seed(seed)
idx_all <- seq_len(n)
cv_results <- list()
for (axis in eive_cols) {
  y <- dt_match[[axis]]
  # store per-x metrics over all repeats/folds
  for (xexp in x_grid) {
    r2s <- c(); maes <- c(); n_used <- 0L
    for (rep in seq_len(repeats)) {
      fold_ids <- sample(rep(seq_len(folds), length.out = n))
      for (fold in seq_len(folds)) {
        test_idx <- which(fold_ids == fold)
        train_idx <- setdiff(idx_all, test_idx)
        y_tr <- y[train_idx]
        y_te <- y[test_idx]
        # predictions for test using training-only weights
        yhat <- pvalue_cv(D, y, train_idx, x = xexp, k_trunc = k_trunc)[test_idx]
        # R2 with train-mean baseline on test
        sse <- sum((y_te - yhat)^2)
        sst <- sum((y_te - mean(y_tr))^2)
        r2 <- 1 - sse / (ifelse(sst > 0, sst, .Machine$double.eps))
        mae <- mean(abs(y_te - yhat))
        r2s <- c(r2s, r2)
        maes <- c(maes, mae)
        n_used <- n_used + length(test_idx)
      }
    }
    cv_results[[length(cv_results) + 1L]] <- data.frame(
      axis = axis,
      x = xexp,
      k_trunc = k_trunc,
      repeats = repeats,
      folds = folds,
      n_used = n_used,
      r2_mean = mean(r2s),
      r2_sd = sd(r2s),
      mae_mean = mean(maes),
      mae_sd = sd(maes),
      stringsAsFactors = FALSE
    )
  }
}

res <- do.call(rbind, cv_results)
res <- res[order(res$axis, res$x), ]

dir.create(dirname(out_csv), showWarnings = FALSE, recursive = TRUE)
write.csv(res, out_csv, row.names = FALSE)
cat(sprintf("Wrote CV results: %s (rows %d)\n", out_csv, nrow(res)))

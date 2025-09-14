#!/usr/bin/env Rscript

# Prefer project-local R library first
.libPaths(c("/home/olier/ellenberg/.Rlib", .libPaths()))

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(ranger)
  library(jsonlite)
})

`%||%` <- function(a,b) if (!is.null(a) && length(a)>0 && !is.na(a) && nzchar(a)) a else b

args <- commandArgs(trailingOnly = TRUE)
parse_args <- function(args) {
  out <- list()
  for (a in args) {
    if (!grepl("^--[A-Za-z0-9_]+=", a)) next
    kv <- sub("^--", "", a)
    k <- sub("=.*$", "", kv)
    v <- sub("^[^=]*=", "", kv)
    out[[k]] <- v
  }
  out
}

opts <- parse_args(args)
features_csv <- opts[["features_csv"]] %||% stop("--features_csv is required")
axis <- toupper(opts[["axis"]] %||% "M")
out_dir <- opts[["out_dir"]] %||% "artifacts/stage3rf_hybrid_interpret"
vars_csv <- opts[["vars"]] %||% "mat_mean,mat_q05,mat_q95,temp_seasonality,tmin_q05,precip_mean,precip_seasonality,drought_min,aridity_mean,ai_month_min,ai_roll3_min,ai_dry_frac_t020,ai_dry_frac_t050,ai_amp,ai_cv_month,SIZE,LES_core,size_temp,les_seasonality,lma_precip,wood_cold,size_precip,les_drought,p_phylo"
pairs_csv <- opts[["pairs"]] %||% "SIZE:mat_mean,LES_core:temp_seasonality,LMA:precip_mean,SIZE:precip_mean,LES_core:drought_min"
num_trees <- suppressWarnings(as.integer(opts[["num_trees"]] %||% "1000")); if (is.na(num_trees)) num_trees <- 1000
set.seed(suppressWarnings(as.integer(opts[["seed"]] %||% "123")))

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
stopifnot(file.exists(features_csv))
dat <- read_csv(features_csv, show_col_types = FALSE)

# Expect columns: y (target), predictors incl. climate/traits/composites; drop ID/factor cols
drop_cols <- intersect(c("wfo_accepted_name","species_normalized","Family"), names(dat))
num_mask <- sapply(dat, is.numeric)
num_cols <- names(dat)[num_mask]
num_cols <- setdiff(num_cols, c("y"))
X <- dat[, num_cols, drop = FALSE]
y <- dat$y
row_good <- is.finite(y)
X <- X[row_good, , drop = FALSE]
y <- y[row_good]

# Fit RF for interpretability (full data)
rf <- ranger(
  x = X,
  y = y,
  num.trees = num_trees,
  mtry = ceiling(sqrt(ncol(X))),
  min.node.size = 5,
  importance = "permutation",
  seed = 42
)

write_csv(data.frame(feature = names(rf$variable.importance), importance = rf$variable.importance),
          file.path(out_dir, sprintf("rf_%s_importance.csv", axis)))

to_grid <- function(x, n=50) {
  xr <- x[is.finite(x)]
  qs <- quantile(xr, probs = c(0.05, 0.95), na.rm = TRUE, type=7)
  seq(qs[1], qs[2], length.out = n)
}

# PDP 1D
vars <- trimws(unlist(strsplit(vars_csv, ",")))
vars <- intersect(vars, colnames(X))
for (v in vars) {
  g <- to_grid(X[[v]], 50)
  preds <- numeric(length(g))
  for (i in seq_along(g)) {
    Xg <- X
    Xg[[v]] <- g[i]
    preds[i] <- mean(predict(rf, data = Xg)$predictions)
  }
  out <- data.frame(feature=v, value=g, yhat=preds)
  write_csv(out, file.path(out_dir, sprintf("rf_%s_pdp_%s.csv", axis, gsub("[^A-Za-z0-9]+","_", v))))
}

# PDP 2D + H^2
pairs <- trimws(unlist(strsplit(pairs_csv, ",")))
pairs <- pairs[nzchar(pairs)]
for (p in pairs) {
  ab <- trimws(unlist(strsplit(p, ":")))
  if (length(ab) != 2) next
  a <- ab[1]; b <- ab[2]
  if (!(a %in% colnames(X) && b %in% colnames(X))) next
  g1 <- to_grid(X[[a]], 25); g2 <- to_grid(X[[b]], 25)
  mat <- matrix(NA_real_, nrow=length(g1), ncol=length(g2))
  for (i in seq_along(g1)) {
    for (j in seq_along(g2)) {
      Xg <- X
      Xg[[a]] <- g1[i]
      Xg[[b]] <- g2[j]
      mat[i, j] <- mean(predict(rf, data = Xg)$predictions)
    }
  }
  # H^2 approx
  pd1 <- numeric(length(g1)); for (i in seq_along(g1)) { Xg <- X; Xg[[a]] <- g1[i]; pd1[i] <- mean(predict(rf, data=Xg)$predictions) }
  pd2 <- numeric(length(g2)); for (j in seq_along(g2)) { Xg <- X; Xg[[b]] <- g2[j]; pd2[j] <- mean(predict(rf, data=Xg)$predictions) }
  f12 <- as.vector(mat); f1 <- rep(pd1, times=length(g2)); f2 <- rep(pd2, each=length(g2))
  num <- stats::var(f12 - f1 - f2); den <- stats::var(f12)
  H2 <- if (is.finite(num) && is.finite(den) && den > 0) max(0, min(1, num/den)) else NA_real_
  # Write artifacts
  surf <- expand.grid(v1=g1, v2=g2, KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  surf$yhat <- as.vector(mat)
  write_csv(surf, file.path(out_dir, sprintf("rf_%s_pdp2_%s__%s.csv", axis, gsub("[^A-Za-z0-9]+","_", a), gsub("[^A-Za-z0-9]+","_", b))))
  write_csv(data.frame(var1=a, var2=b, H2=H2), file.path(out_dir, sprintf("rf_%s_interaction_%s__%s.csv", axis, gsub("[^A-Za-z0-9]+","_", a), gsub("[^A-Za-z0-9]+","_", b))))
}

meta <- list(axis=axis, n=nrow(X), p=ncol(X), features_csv=features_csv, out_dir=out_dir)
writeLines(jsonlite::toJSON(meta, pretty = TRUE, auto_unbox = TRUE), con = file.path(out_dir, sprintf("rf_%s_interpret_meta.json", axis)))

cat(sprintf("[ok] RF hybrid interpretability artifacts written to: %s\n", normalizePath(out_dir)))

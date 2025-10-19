#!/usr/bin/env Rscript

# Analyze a trained Random Forest (ranger) model for interpretability
# - Fits a single RF on the full data (with the same transforms as training)
# - Writes PDP (1D), ICE (subset), and pairwise PDP (2D) CSVs for nominated features
# - No external deps beyond ranger + readr/jsonlite (optional)

suppressWarnings({
  # Allow project-local library first (works with conda 'plants' env)
  extra_libs <- Sys.getenv("R_EXTRA_LIBS")
  paths <- character()
  if (nzchar(extra_libs)) paths <- c(paths, unlist(strsplit(extra_libs, "[,:;]", perl = TRUE)))
  if (dir.exists(".Rlib")) paths <- c(normalizePath(".Rlib"), paths)
  paths <- unique(paths[nzchar(paths)])
  if (length(paths)) .libPaths(c(paths, .libPaths()))
  suppressMessages({
    have_readr    <- requireNamespace("readr",    quietly = TRUE)
    have_jsonlite <- requireNamespace("jsonlite", quietly = TRUE)
    have_ranger   <- requireNamespace("ranger",   quietly = TRUE)
  })
})

fail <- function(msg) { cat(sprintf("[error] %s\n", msg)); quit(status = 1) }
if (!have_ranger) fail("Package 'ranger' not installed.")

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
`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b

opts <- parse_args(args)

in_csv         <- opts[["input_csv"]] %||% "artifacts/model_data_complete_case.csv"
target_letter  <- toupper(opts[["target"]] %||% "L")
out_dir        <- opts[["out_dir"]]   %||% "artifacts/stage3rf_ranger_interpret"
features_csv   <- opts[["features"]]  %||% "LMA (g/m2),Leaf area (mm2),Plant height (m),SSD used (mg/mm3),Nmass (mg/g),Diaspore mass (mg)"
pairs_csv      <- opts[["pairs"]]     %||% "LMA (g/m2):Leaf area (mm2),Plant height (m):SSD used (mg/mm3),Nmass (mg/g):Leaf area (mm2)"
ngrid1         <- suppressWarnings(as.integer(opts[["ngrid1"]] %||% "50")); if (is.na(ngrid1) || ngrid1 < 10) ngrid1 <- 50
ngrid2         <- suppressWarnings(as.integer(opts[["ngrid2"]] %||% "25")); if (is.na(ngrid2) || ngrid2 < 10) ngrid2 <- 25
nice_n_ice     <- suppressWarnings(as.integer(opts[["n_ice"]]   %||% "100")); if (is.na(nice_n_ice) || nice_n_ice < 10) nice_n_ice <- 100
seed_opt       <- suppressWarnings(as.integer(opts[["seed"]]    %||% "42")); if (is.na(seed_opt)) seed_opt <- 42
verbose        <- tolower(opts[["verbose"]] %||% "true") %in% c("1","true","yes","y")

# Ranger params (default match Stage 3 unless overridden)
num_trees_opt  <- suppressWarnings(as.integer(opts[["num_trees"]] %||% "1000")); if (is.na(num_trees_opt)) num_trees_opt <- 1000
mtry_opt       <- suppressWarnings(as.integer(opts[["mtry"]]      %||% "3")); if (is.na(mtry_opt)) mtry_opt <- 3
min_node_opt   <- suppressWarnings(as.integer(opts[["min_node_size"]] %||% "5")); if (is.na(min_node_opt)) min_node_opt <- 5
sample_frac    <- suppressWarnings(as.numeric(opts[["sample_fraction"]] %||% "0.632")); if (is.na(sample_frac)) sample_frac <- 0.632
max_depth_opt  <- suppressWarnings(as.integer(opts[["max_depth"]] %||% "0")); if (is.na(max_depth_opt)) max_depth_opt <- 0
standardize    <- tolower(opts[["standardize"]] %||% "true") %in% c("1","true","yes","y")
winsorize_opt  <- tolower(opts[["winsorize"]]  %||% "false") %in% c("1","true","yes","y")
winsor_p_opt   <- suppressWarnings(as.numeric(opts[["winsor_p"]]  %||% "0.005")); if (is.na(winsor_p_opt)) winsor_p_opt <- 0.005

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
if (!file.exists(in_csv)) fail(sprintf("Input CSV not found: '%s'", in_csv))

target_name  <- paste0("EIVEres-", target_letter)
feature_cols <- c("Leaf area (mm2)", "Nmass (mg/g)", "LMA (g/m2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")

df <- if (have_readr) readr::read_csv(in_csv, show_col_types = FALSE, progress = FALSE) else utils::read.csv(in_csv, check.names = FALSE)
miss <- setdiff(c(target_name, feature_cols), names(df))
if (length(miss)) fail(sprintf("Missing columns: %s", paste(miss, collapse=", ")))

dat <- df[, c(target_name, feature_cols, "wfo_accepted_name"), drop = FALSE]
dat <- dat[stats::complete.cases(dat[, c(target_name, feature_cols)]), , drop = FALSE]

logf <- function(fmt, ...) { if (verbose) { cat(sprintf("[%s] ", format(Sys.time(), "%H:%M:%S"))); cat(sprintf(fmt, ...), "\n"); flush.console() } }

log_vars <- c("Leaf area (mm2)", "Diaspore mass (mg)", "Plant height (m)", "SSD used (mg/mm3)")
compute_offset <- function(x) { x <- as.numeric(x); x <- x[is.finite(x) & !is.na(x) & x > 0]; if (!length(x)) return(1e-6); max(1e-6, 1e-3 * stats::median(x)) }
winsorize <- function(x, p=0.005, lo=NULL, hi=NULL) { x <- as.numeric(x); qs <- stats::quantile(x[is.finite(x)], probs=c(p,1-p), na.rm=TRUE, names=FALSE, type=7); if (is.null(lo)) lo <- qs[1]; if (is.null(hi)) hi <- qs[2]; x[x<lo] <- lo; x[x>hi] <- hi; list(x=x, lo=lo, hi=hi) }
zscore <- function(x, mean_=NULL, sd_=NULL) { x <- as.numeric(x); if (is.null(mean_)) mean_ <- mean(x, na.rm=TRUE); if (is.null(sd_))   sd_   <- stats::sd(x, na.rm=TRUE); if (!is.finite(sd_) || sd_==0) sd_ <- 1; list(x=(x-mean_)/sd_, mean=mean_, sd=sd_) }

offsets <- sapply(intersect(names(dat), log_vars), function(v) compute_offset(dat[[v]]))

# Prepare design matrix X (apply log, winsorize, standardize)
prep_X <- function(df_in) {
  X <- df_in[, feature_cols, drop = FALSE]
  # log transform
  for (v in feature_cols) if (v %in% names(offsets)) { off <- offsets[[v]]; X[[v]] <- log10(X[[v]] + off) }
  # winsorize
  if (winsorize_opt) {
    for (v in feature_cols) {
      wtr <- winsorize(X[[v]], p=winsor_p_opt)
      X[[v]] <- wtr$x
    }
  }
  # standardize
  means <- list(); sds <- list()
  if (standardize) {
    for (v in feature_cols) { zs <- zscore(X[[v]]); X[[v]] <- zs$x; means[[v]] <- zs$mean; sds[[v]] <- zs$sd }
  } else {
    for (v in feature_cols) { means[[v]] <- 0; sds[[v]] <- 1 }
  }
  list(X=X, means=means, sds=sds)
}

# Transform a single column to the model scale
to_model_scale <- function(vname, raw_values, means, sds) {
  x <- raw_values
  if (vname %in% names(offsets)) x <- log10(x + offsets[[vname]])
  if (standardize) x <- (x - means[[vname]])/sds[[vname]]
  x
}

set.seed(seed_opt)
Xprep <- prep_X(dat)
X <- Xprep$X
y <- dat[[target_name]]

logf("Training ranger RF for %s on n=%d (trees=%d, mtry=%d, min_node=%d)", target_name, nrow(X), num_trees_opt, mtry_opt, min_node_opt)
ts <- Sys.time()
rf <- ranger::ranger(
  dependent.variable.name = NULL,
  y = y,
  x = X,
  num.trees = num_trees_opt,
  mtry = mtry_opt,
  min.node.size = min_node_opt,
  sample.fraction = sample_frac,
  max.depth = if (max_depth_opt > 0) max_depth_opt else NULL,
  write.forest = TRUE,
  importance = "permutation",
  seed = seed_opt,
  num.threads = 0
)
te <- Sys.time()
oob <- tryCatch(rf$prediction.error, error = function(e) NA_real_)
logf("RF trained in %.1f sec; OOB MSE=%.4f", as.numeric(difftime(te, ts, units = "secs")), as.numeric(oob))

# Save a minimal metadata file
meta <- list(
  target = target_name,
  n = nrow(X),
  params = list(num_trees=num_trees_opt, mtry=mtry_opt, min_node_size=min_node_opt, sample_fraction=sample_frac, max_depth=max_depth_opt),
  offsets = as.list(offsets),
  standardize = standardize,
  means = Xprep$means,
  sds = Xprep$sds
)
if (have_jsonlite) cat(jsonlite::toJSON(meta, pretty = TRUE, auto_unbox = TRUE), file = file.path(out_dir, paste0("rf_", target_letter, "_interpret_meta.json")))

# Helper to write CSV
write_csv <- function(df, path) {
  if (have_readr) readr::write_csv(df, path) else utils::write.csv(df, path, row.names=FALSE)
}

# PDP for single variables
feat_list <- trimws(unlist(strsplit(features_csv, ",")))
feat_list <- feat_list[nchar(feat_list) > 0]
for (v in intersect(feat_list, feature_cols)) {
  logf("PDP: %s (%d grid points)", v, ngrid1)
  # grid on raw scale between 5th and 95th percentiles
  xr <- dat[[v]]
  qs <- stats::quantile(xr, probs = c(0.05, 0.95), na.rm = TRUE, type = 7)
  grid_raw <- seq(qs[1], qs[2], length.out = ngrid1)
  grid_mod <- to_model_scale(v, grid_raw, Xprep$means, Xprep$sds)
  preds <- numeric(length(grid_mod))
  pb <- utils::txtProgressBar(min = 0, max = length(grid_mod), style = 3)
  for (i in seq_along(grid_mod)) {
    Xg <- X
    Xg[[v]] <- grid_mod[i]
    preds[i] <- mean(stats::predict(rf, data = Xg)$predictions)
    if (verbose) utils::setTxtProgressBar(pb, i)
  }
  if (verbose) close(pb)
  out <- data.frame(feature=v, value_raw=grid_raw, value_model=grid_mod, yhat=preds)
  write_csv(out, file.path(out_dir, paste0("rf_", target_letter, "_pdp_", gsub("[^A-Za-z0-9]+","_", v), ".csv")))

  # ICE for a subset of instances
  n_take <- min(nice_n_ice, nrow(X))
  idx <- sample.int(nrow(X), n_take)
  logf("ICE: %s on %d instances", v, n_take)
  pb_ice <- utils::txtProgressBar(min = 0, max = length(idx), style = 3)
  ice_rows <- lapply(seq_along(idx), function(j){
    ii <- idx[j]
    Xrow <- X[ii, , drop=FALSE]
    vals <- numeric(length(grid_mod))
    for (i in seq_along(grid_mod)) {
      Xrow[[v]] <- grid_mod[i]
      vals[i] <- stats::predict(rf, data = Xrow)$predictions
    }
    if (verbose) utils::setTxtProgressBar(pb_ice, j)
    data.frame(id = dat$wfo_accepted_name[ii], feature=v, value_raw=grid_raw, value_model=grid_mod, yhat=vals)
  })
  if (verbose) close(pb_ice)
  ice_df <- do.call(rbind, ice_rows)
  write_csv(ice_df, file.path(out_dir, paste0("rf_", target_letter, "_ice_", gsub("[^A-Za-z0-9]+","_", v), ".csv")))
}

# Pairwise PDP surfaces and simple H^2 interaction index
pair_list <- trimws(unlist(strsplit(pairs_csv, ",")))
pair_list <- pair_list[nchar(pair_list) > 0]
for (p in pair_list) {
  vars <- trimws(unlist(strsplit(p, ":")))
  if (length(vars) != 2) next
  v1 <- vars[1]; v2 <- vars[2]
  if (!(v1 %in% feature_cols && v2 %in% feature_cols)) next
  logf("Pairwise PDP: %s × %s (%dx%d)", v1, v2, ngrid2, ngrid2)
  xr1 <- dat[[v1]]; xr2 <- dat[[v2]]
  q1 <- stats::quantile(xr1, probs = c(0.05, 0.95), na.rm = TRUE, type = 7)
  q2 <- stats::quantile(xr2, probs = c(0.05, 0.95), na.rm = TRUE, type = 7)
  g1_raw <- seq(q1[1], q1[2], length.out = ngrid2)
  g2_raw <- seq(q2[1], q2[2], length.out = ngrid2)
  g1_mod <- to_model_scale(v1, g1_raw, Xprep$means, Xprep$sds)
  g2_mod <- to_model_scale(v2, g2_raw, Xprep$means, Xprep$sds)
  # pairwise PDP grid
  mat <- matrix(NA_real_, nrow = ngrid2, ncol = ngrid2)
  pb2 <- utils::txtProgressBar(min = 0, max = length(g1_mod), style = 3)
  for (i in seq_along(g1_mod)) {
    for (j in seq_along(g2_mod)) {
      Xg <- X
      Xg[[v1]] <- g1_mod[i]
      Xg[[v2]] <- g2_mod[j]
      mat[i, j] <- mean(stats::predict(rf, data = Xg)$predictions)
    }
    if (verbose) utils::setTxtProgressBar(pb2, i)
  }
  if (verbose) close(pb2)
  # marginal PDPs for H^2 approx
  pd1 <- numeric(length(g1_mod))
  for (i in seq_along(g1_mod)) { Xg <- X; Xg[[v1]] <- g1_mod[i]; pd1[i] <- mean(stats::predict(rf, data = Xg)$predictions) }
  pd2 <- numeric(length(g2_mod))
  for (j in seq_along(g2_mod)) { Xg <- X; Xg[[v2]] <- g2_mod[j]; pd2[j] <- mean(stats::predict(rf, data = Xg)$predictions) }
  # H^2 (Friedman): fraction of variance unexplained by additivity
  # Approximate integrals by uniform averages on the grid
  f12 <- as.vector(mat)
  f1  <- rep(pd1, times = ngrid2)
  f2  <- rep(pd2, each  = ngrid2)
  num <- stats::var(f12 - f1 - f2)
  den <- stats::var(f12)
  H2  <- if (is.finite(num) && is.finite(den) && den > 0) max(0, min(1, num/den)) else NA_real_
  # Write surface and H^2
  surf <- expand.grid(v1_raw = g1_raw, v2_raw = g2_raw, KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  surf$yhat <- as.vector(mat)
  names(surf) <- c(paste0(v1, "_raw"), paste0(v2, "_raw"), "yhat")
  write_csv(surf, file.path(out_dir, paste0("rf_", target_letter, "_pdp2_", gsub("[^A-Za-z0-9]+","_", v1), "__", gsub("[^A-Za-z0-9]+","_", v2), ".csv")))
  write_csv(data.frame(var1=v1, var2=v2, H2=H2), file.path(out_dir, paste0("rf_", target_letter, "_interaction_", gsub("[^A-Za-z0-9]+","_", v1), "__", gsub("[^A-Za-z0-9]+","_", v2), ".csv")))
}

logf("All artifacts written to: %s", normalizePath(out_dir))

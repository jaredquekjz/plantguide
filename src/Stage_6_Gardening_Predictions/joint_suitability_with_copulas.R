#!/usr/bin/env Rscript

# Stage 6 — Joint Suitability via Copulas (Gaussian, Monte Carlo)
# - Reads per-axis predictions and Run 8 copula metadata
# - Uses RMSE from Stage 4 Run 7 as residual scale per axis
# - Builds a 5D Gaussian residual with pairwise correlations from mag_copulas.json
# - Estimates P(requirement) for each species by Monte Carlo

suppressWarnings({
  suppressMessages({
    have_readr    <- requireNamespace("readr",    quietly = TRUE)
    have_jsonlite <- requireNamespace("jsonlite", quietly = TRUE)
    have_dplyr    <- requireNamespace("dplyr",    quietly = TRUE)
  })
})

`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b

args <- commandArgs(trailingOnly = TRUE)
opts <- list()
for (i in seq(1, length(args), by = 2)) {
  k <- gsub("^--", "", args[[i]])
  v <- if (i+1 <= length(args)) args[[i+1]] else ""
  opts[[k]] <- v
}

pred_csv <- opts[["predictions_csv"]]
if (is.null(pred_csv)) stop("Missing --predictions_csv <path>")
cop_json <- opts[["copulas_json"]] %||% "results/MAG_Run8/mag_copulas.json"
metrics_dir <- opts[["metrics_dir"]] %||% "artifacts/stage4_sem_piecewise_run7"
bins_spec <- opts[["bins"]] %||% "0:3.5,3.5:6.5,6.5:10"
req_spec  <- opts[["joint_requirement"]]
presets_csv <- opts[["presets_csv"]] %||% ""
default_threshold <- suppressWarnings(as.numeric(opts[["default_threshold"]] %||% "0.6")); if (!is.finite(default_threshold)) default_threshold <- 0.6
nsim <- suppressWarnings(as.integer(opts[["nsim"]] %||% "10000")); if (is.na(nsim) || nsim < 1000) nsim <- 10000
out_csv <- opts[["output_csv"]] %||% "results/gardening/garden_joint_suitability.csv"
summary_csv <- opts[["summary_csv"]] %||% "results/gardening/garden_joint_summary.csv"

ensure_dir <- function(path) dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
ensure_dir(out_csv)

parse_bins <- function(spec) {
  parts <- strsplit(spec, ",", fixed = TRUE)[[1]]
  rng <- lapply(parts, function(p) as.numeric(strsplit(trimws(p), ":", fixed = TRUE)[[1]]))
  if (length(rng) != 3) stop("Expect exactly 3 bins: low,med,high")
  list(low = rng[[1]], med = rng[[2]], high = rng[[3]])
}

parse_req <- function(s) {
  bits <- strsplit(s, ",", fixed = TRUE)[[1]]
  out <- list()
  for (b in bits) {
    kv <- strsplit(trimws(b), "=", fixed = TRUE)[[1]]
    if (length(kv) != 2) next
    ax <- toupper(trimws(kv[1]))
    lv <- tolower(trimws(kv[2]))
    stopifnot(ax %in% c("L","T","M","R","N"))
    stopifnot(lv %in% c("low","med","high"))
    out[[ax]] <- lv
  }
  out
}

# Load presets: CSV must have columns label, requirement, joint_min_prob (optional)
load_presets <- function(path) {
  if (nzchar(path) && file.exists(path)) {
    if (have_readr) {
      df <- readr::read_csv(path, show_col_types = FALSE)
    } else {
      df <- utils::read.csv(path, stringsAsFactors = FALSE)
    }
    if (!"label" %in% names(df) || !"requirement" %in% names(df)) stop("presets_csv must have columns: label, requirement [, joint_min_prob]")
    if (!"joint_min_prob" %in% names(df)) df$joint_min_prob <- default_threshold
    return(df)
  }
  # Built-in defaults (5 scenarios)
  data.frame(
    label = c(
      "SunnyNeutral",
      "ShadeWetAcidic",
      "PartialSunAverage",
      "WarmNeutralFertile",
      "DryPoorSun"
    ),
    requirement = c(
      "L=high,M=med,R=med",
      "L=low,M=high,R=low",
      "L=med,M=med,R=med",
      "T=high,R=med,N=high",
      "L=high,M=low,N=low"
    ),
    joint_min_prob = rep(default_threshold, 5),
    stringsAsFactors = FALSE
  )
}

bins <- parse_bins(bins_spec)
req  <- if (!is.null(req_spec) && nzchar(req_spec)) parse_req(req_spec) else NULL

read_sigma <- function(dir, letter) {
  p <- file.path(dir, sprintf("sem_piecewise_%s_metrics.json", letter))
  if (!file.exists(p)) stop(sprintf("Metrics JSON not found: %s", p))
  jj <- if (have_jsonlite) jsonlite::fromJSON(p) else dget(p)
  # aggregate is an array of length 1 with RMSE_mean
  ag <- jj$metrics$aggregate
  if (is.data.frame(ag)) {
    rmse <- as.numeric(ag$RMSE_mean[1])
  } else if (is.list(ag) && length(ag) >= 1) {
    rmse <- as.numeric(ag[[1]]$RMSE_mean)
  } else rmse <- NA_real_
  if (!is.finite(rmse)) stop(sprintf("Could not read RMSE_mean from %s", p))
  rmse
}

sigmas <- c(
  L = read_sigma(metrics_dir, "L"),
  T = read_sigma(metrics_dir, "T"),
  M = read_sigma(metrics_dir, "M"),
  R = read_sigma(metrics_dir, "R"),
  N = read_sigma(metrics_dir, "N")
)

cop <- if (have_jsonlite) jsonlite::fromJSON(cop_json) else dget(cop_json)

# Build 5x5 correlation matrix from districts (default 0 elsewhere)
axes <- c("L","T","M","R","N")
Corr <- diag(5)
if (is.data.frame(cop$districts)) {
  for (i in seq_len(nrow(cop$districts))) {
    mem <- toupper(unlist(cop$districts$members[[i]]))
    rho <- as.numeric(cop$districts$params$rho[i])
    a <- match(mem[1], axes); b <- match(mem[2], axes)
    Corr[a,b] <- Corr[b,a] <- rho
  }
} else if (is.list(cop$districts)) {
  for (d in cop$districts) {
    mem <- toupper(unlist(d$members)); rho <- as.numeric(d$params$rho)
    a <- match(mem[1], axes); b <- match(mem[2], axes)
    Corr[a,b] <- Corr[b,a] <- rho
  }
}

# Covariance = D * Corr * D
D <- diag(as.numeric(sigmas[axes]))
Sigma <- D %*% Corr %*% D

# Cholesky (upper triangular R s.t. t(R) %*% R = Sigma)
Rchol <- chol(Sigma)

# Load predictions
preds <- if (have_readr) readr::read_csv(pred_csv, show_col_types = FALSE) else utils::read.csv(pred_csv, check.names = FALSE)

id_col <- NULL
for (cand in c("species", "species_id", "Species", "wfo_accepted_name")) if (cand %in% names(preds)) { id_col <- cand; break }
if (is.null(id_col)) { preds$row_id <- seq_len(nrow(preds)); id_col <- "row_id" }

mu_mat <- as.matrix(preds[, paste0(axes, "_pred")])
if (ncol(mu_mat) != 5) stop("Predictions CSV must contain L_pred,T_pred,M_pred,R_pred,N_pred")

# Precompute residual draws shared across species
Z <- matrix(stats::rnorm(nsim*5), ncol=5)
E <- Z %*% Rchol  # nsim x 5 residual draws

# Helper to compute probability inside a rectangular bin constraint
inside_rect <- function(mu, lo, hi) {
  Y <- sweep(E, 2, mu, "+")
  ok <- rep(TRUE, nrow(Y))
  for (j in 1:5) {
    if (is.finite(lo[j])) ok <- ok & (Y[,j] >= lo[j])
    if (is.finite(hi[j])) ok <- ok & (Y[,j] <= hi[j])
  }
  mean(ok)
}

if (!is.null(req)) {
  # Single requirement path (backward compatible)
  lo <- rep(-Inf, 5); hi <- rep(Inf, 5)
  for (k in seq_along(axes)) {
    ax <- axes[k]
    if (!is.null(req[[ax]])) { b <- bins[[ req[[ax]] ]]; lo[k] <- b[1]; hi[k] <- b[2] }
  }
  probs <- apply(mu_mat, 1, function(mu) inside_rect(mu, lo, hi))
  out <- data.frame(tmp_id = preds[[id_col]], stringsAsFactors = FALSE)
  names(out)[1] <- id_col
  out$joint_requirement <- req_spec
  out$joint_prob <- probs
  if (have_readr) readr::write_csv(out, out_csv) else utils::write.csv(out, out_csv, row.names = FALSE)
  cat(sprintf("Wrote %s (n=%d)\n", out_csv, nrow(out)))
} else {
  # Presets path (batch)
  presets <- load_presets(presets_csv)
  rows <- list()
  for (i in seq_len(nrow(presets))) {
    lab <- as.character(presets$label[i])
    reqs <- as.character(presets$requirement[i])
    thr <- suppressWarnings(as.numeric(presets$joint_min_prob[i])); if (!is.finite(thr)) thr <- default_threshold
    rparsed <- parse_req(reqs)
    lo_i <- rep(-Inf, 5); hi_i <- rep(Inf, 5)
    for (k in seq_along(axes)) {
      ax <- axes[k]
      if (!is.null(rparsed[[ax]])) { b <- bins[[ rparsed[[ax]] ]]; lo_i[k] <- b[1]; hi_i[k] <- b[2] }
    }
    probs <- apply(mu_mat, 1, function(mu) inside_rect(mu, lo_i, hi_i))
    df <- data.frame(tmp_id = preds[[id_col]], stringsAsFactors = FALSE)
    names(df)[1] <- id_col
    df$label <- lab
    df$requirement <- reqs
    df$joint_prob <- probs
    df$threshold <- thr
    df$pass <- probs >= thr
    rows[[length(rows)+1]] <- df
  }
  all <- do.call(rbind, rows)
  if (have_readr) readr::write_csv(all, summary_csv) else utils::write.csv(all, summary_csv, row.names = FALSE)
  cat(sprintf("Wrote %s (rows=%d)\n", summary_csv, nrow(all)))
}

#!/usr/bin/env Rscript

# Stage 6 — Joint Suitability via Copulas (Gaussian, Monte Carlo)
# - Reads per-axis predictions and Run 8 copula metadata
# - Uses RMSE from Stage 4 Run 7 as residual scale per axis
# - Optional: group-aware residual scales (σ per group, per axis) when a grouping is supplied
#   via --group_col, computed from Run 7 CV predictions joined to a reference CSV.
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
group_col <- opts[["group_col"]] %||% ""              # optional: name of group column present in predictions or to be joined from reference
# Optional: reference CSV (id -> group) to compute per-group sigmas from Run 7 preds
group_ref_csv <- opts[["group_ref_csv"]] %||% "artifacts/model_data_complete_case_with_myco.csv"
group_ref_id_col <- opts[["group_ref_id_col"]] %||% "wfo_accepted_name"
group_ref_group_col <- opts[["group_ref_group_col"]] %||% group_col
sigma_mode <- tolower(opts[["sigma_mode"]] %||% if (nzchar(group_col)) "by_group" else "global")  # global|by_group
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
  if (!file.exists(p)) {
    # try pwSEM naming
    p2 <- file.path(dir, sprintf("sem_pwsem_%s_metrics.json", letter))
    if (file.exists(p2)) p <- p2 else stop(sprintf("Metrics JSON not found: %s or %s", p, p2))
  }
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

# Build correlation matrices
axes <- c("L","T","M","R","N")
build_corr <- function(districts) {
  C <- diag(5)
  if (is.data.frame(districts)) {
    for (i in seq_len(nrow(districts))) {
      mem <- toupper(unlist(districts$members[[i]]))
      rho <- as.numeric(districts$params$rho[i])
      a <- match(mem[1], axes); b <- match(mem[2], axes)
      C[a,b] <- C[b,a] <- rho
    }
  } else if (is.list(districts)) {
    for (d in districts) {
      mem <- toupper(unlist(d$members)); rho <- as.numeric(d$params$rho)
      a <- match(mem[1], axes); b <- match(mem[2], axes)
      C[a,b] <- C[b,a] <- rho
    }
  }
  C
}
Corr_global <- build_corr(cop$districts)
by_group_corr <- list()
if (!is.null(cop$by_group) && is.list(cop$by_group)) {
  for (nm in names(cop$by_group)) {
    if (is.null(cop$by_group[[nm]]$districts)) next
    by_group_corr[[nm]] <- build_corr(cop$by_group[[nm]]$districts)
  }
}
Corr_for_group <- function(glab) {
  if (!is.null(by_group_corr) && length(by_group_corr) && !is.null(glab) && nzchar(glab) && (glab %in% names(by_group_corr))) return(by_group_corr[[glab]])
  Corr_global
}

# Note: covariance matrices are constructed on-demand (global or per-group)

# Load predictions
preds <- if (have_readr) readr::read_csv(pred_csv, show_col_types = FALSE) else utils::read.csv(pred_csv, check.names = FALSE)

id_col <- NULL
for (cand in c("species", "species_id", "Species", "wfo_accepted_name")) if (cand %in% names(preds)) { id_col <- cand; break }
if (is.null(id_col)) { preds$row_id <- seq_len(nrow(preds)); id_col <- "row_id" }

mu_mat <- as.matrix(preds[, paste0(axes, "_pred")])
if (ncol(mu_mat) != 5) stop("Predictions CSV must contain L_pred,T_pred,M_pred,R_pred,N_pred")

# Helper: build per-axis sigma vector (global)
read_sigma <- function(dir, letter) {
  p <- file.path(dir, sprintf("sem_piecewise_%s_metrics.json", letter))
  if (!file.exists(p)) {
    p2 <- file.path(dir, sprintf("sem_pwsem_%s_metrics.json", letter))
    if (file.exists(p2)) p <- p2 else stop(sprintf("Metrics JSON not found: %s or %s", p, p2))
  }
  jj <- if (have_jsonlite) jsonlite::fromJSON(p) else dget(p)
  ag <- jj$metrics$aggregate
  if (is.data.frame(ag)) {
    rmse <- as.numeric(ag$RMSE_mean[1])
  } else if (is.list(ag) && length(ag) >= 1) {
    rmse <- as.numeric(ag[[1]]$RMSE_mean)
  } else rmse <- NA_real_
  if (!is.finite(rmse)) stop(sprintf("Could not read RMSE_mean from %s", p))
  rmse
}

sigmas_global <- c(
  L = read_sigma(metrics_dir, "L"),
  T = read_sigma(metrics_dir, "T"),
  M = read_sigma(metrics_dir, "M"),
  R = read_sigma(metrics_dir, "R"),
  N = read_sigma(metrics_dir, "N")
)

# Optional: per-group sigma computation from Run 7 preds + reference mapping
sigmas_by_group <- NULL
group_values <- NULL
if (sigma_mode == "by_group" && nzchar(group_ref_group_col)) {
  # Derive grouping for current predictions
  if (nzchar(group_col) && !(group_col %in% names(preds))) {
    # try to join from reference CSV
    if (!file.exists(group_ref_csv)) {
      warning(sprintf("group_ref_csv not found: %s; falling back to global sigmas", group_ref_csv))
    } else {
      ref <- tryCatch({ if (have_readr) readr::read_csv(group_ref_csv, show_col_types = FALSE) else utils::read.csv(group_ref_csv, check.names = FALSE) }, error = function(e) NULL)
      if (is.null(ref) || !(group_ref_id_col %in% names(ref)) || !(group_ref_group_col %in% names(ref))) {
        warning("group_ref_csv missing required columns; falling back to global sigmas")
      } else {
        preds <- merge(preds, ref[, c(group_ref_id_col, group_ref_group_col)], by.x = id_col, by.y = group_ref_id_col, all.x = TRUE, sort = FALSE)
        names(preds)[names(preds) == group_ref_group_col] <- group_col
      }
    }
  }
  if (nzchar(group_col) && (group_col %in% names(preds))) {
    group_values <- as.character(preds[[group_col]])
    # Build per-group RMSE using Run 7 prediction files
    per_axis <- list()
    for (ax in axes) {
      ppath <- file.path(metrics_dir, sprintf("sem_piecewise_%s_preds.csv", ax))
      if (!file.exists(ppath)) {
        p2 <- file.path(metrics_dir, sprintf("sem_pwsem_%s_preds.csv", ax))
        if (file.exists(p2)) ppath <- p2 else { per_axis[[ax]] <- NULL; next }
      }
      dfp <- tryCatch({ if (have_readr) readr::read_csv(ppath, show_col_types = FALSE) else utils::read.csv(ppath, check.names = FALSE) }, error = function(e) NULL)
      if (is.null(dfp) || !("id" %in% names(dfp))) { per_axis[[ax]] <- NULL; next }
      # join group from reference
      if (!file.exists(group_ref_csv)) { per_axis[[ax]] <- NULL; next }
      ref <- tryCatch({ if (have_readr) readr::read_csv(group_ref_csv, show_col_types = FALSE) else utils::read.csv(group_ref_csv, check.names = FALSE) }, error = function(e) NULL)
      if (is.null(ref) || !(group_ref_id_col %in% names(ref)) || !(group_ref_group_col %in% names(ref))) { per_axis[[ax]] <- NULL; next }
      tmp <- merge(dfp, ref[, c(group_ref_id_col, group_ref_group_col)], by.x = "id", by.y = group_ref_id_col, all.x = TRUE, sort = FALSE)
      if (!(group_ref_group_col %in% names(tmp)) || !("y_true" %in% names(tmp)) || !("y_pred" %in% names(tmp))) { per_axis[[ax]] <- NULL; next }
      tmp$err <- as.numeric(tmp$y_true) - as.numeric(tmp$y_pred)
      ok <- is.finite(tmp$err)
      tmp <- tmp[ok & !is.na(tmp[[group_ref_group_col]]), , drop = FALSE]
      if (nrow(tmp) == 0) { per_axis[[ax]] <- NULL; next }
      agg <- stats::aggregate(err ~ tmp[[group_ref_group_col]], data = tmp, FUN = function(s) sqrt(mean(s^2, na.rm = TRUE)))
      groups_lab <- as.character(agg[[1]])
      vals <- as.numeric(agg[[2]])
      names(vals) <- groups_lab
      per_axis[[ax]] <- vals
    }
    sigmas_by_group <- per_axis
  }
}

# Helper: given a group label, return sigma vector (L..N), defaulting to global
sigma_for_group <- function(glab) {
  s <- sigmas_global
  if (!is.null(sigmas_by_group) && length(sigmas_by_group)) {
    for (k in seq_along(axes)) {
      ax <- axes[[k]]
      vec <- sigmas_by_group[[ax]]
      if (!is.null(vec) && !is.na(glab) && nzchar(glab) && (glab %in% names(vec))) {
        s[[ax]] <- as.numeric(vec[[glab]])
      }
    }
  }
  s
}

# Precompute standard normal draws
Z <- matrix(stats::rnorm(nsim*5), ncol=5)

# Helper to compute probability inside a rectangular bin constraint
inside_rect_E <- function(Euse, mu, lo, hi) {
  Y <- sweep(Euse, 2, mu, "+")
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
  # Compute probs by grouping to reuse Cholesky per group
  if (!is.null(group_values)) {
    probs <- numeric(nrow(mu_mat))
    glabs <- unique(group_values)
    for (g in glabs) {
      idx <- which(group_values == g)
      svec <- sigma_for_group(g)
      Cg <- Corr_for_group(g)
      Dg <- diag(as.numeric(svec[axes])); Sigmag <- Dg %*% Cg %*% Dg; Rg <- chol(Sigmag)
      Eg <- Z %*% Rg
      pg <- apply(mu_mat[idx, , drop = FALSE], 1, function(mu) inside_rect_E(Eg, mu, lo, hi))
      probs[idx] <- pg
    }
  } else {
    # global path
    D <- diag(as.numeric(sigmas_global[axes])); Sigma <- D %*% Corr_global %*% D; Rchol <- chol(Sigma)
    E <- Z %*% Rchol
    probs <- apply(mu_mat, 1, function(mu) inside_rect_E(E, mu, lo, hi))
  }
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
    if (!is.null(group_values)) {
      probs <- numeric(nrow(mu_mat))
      glabs <- unique(group_values)
      for (g in glabs) {
        idx <- which(group_values == g)
        svec <- sigma_for_group(g)
        Cg <- Corr_for_group(g)
        Dg <- diag(as.numeric(svec[axes])); Sigmag <- Dg %*% Cg %*% Dg; Rg <- chol(Sigmag)
        Eg <- Z %*% Rg
        pg <- apply(mu_mat[idx, , drop = FALSE], 1, function(mu) inside_rect_E(Eg, mu, lo_i, hi_i))
        probs[idx] <- pg
      }
    } else {
      D <- diag(as.numeric(sigmas_global[axes])); Sigma <- D %*% Corr_global %*% D; Rchol <- chol(Sigma)
      E <- Z %*% Rchol
      probs <- apply(mu_mat, 1, function(mu) inside_rect_E(E, mu, lo_i, hi_i))
    }
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

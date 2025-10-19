#!/usr/bin/env Rscript

# Stage 3 — Multiple Regression Baseline
# Fits linear models for EIVE indicators (L,T,M,R,N) using six TRY-curated traits.
# - Log-transform heavy-tailed traits (Leaf area, Diaspore mass, Plant height, SSD used)
# - Standardize predictors
# - 5x5 repeated CV (optional stratification by target deciles)
# - Outputs per-target coefficients, VIFs, CV metrics JSON, and out-of-fold predictions CSV

suppressWarnings({
  suppressMessages({
    have_readr    <- requireNamespace("readr",    quietly = TRUE)
    have_dplyr    <- requireNamespace("dplyr",    quietly = TRUE)
    have_tibble   <- requireNamespace("tibble",   quietly = TRUE)
    have_jsonlite <- requireNamespace("jsonlite", quietly = TRUE)
    have_sandwich <- requireNamespace("sandwich", quietly = TRUE)
    have_lmtest   <- requireNamespace("lmtest",   quietly = TRUE)
  })
})

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

`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b

# Inputs / outputs
in_csv         <- opts[["input_csv"]]   %||% "artifacts/model_data_complete_case.csv"
targets_opt    <- opts[["targets"]]     %||% "all"  # "all" or comma list like L,T,M
seed_opt       <- suppressWarnings(as.integer(opts[["seed"]] %||% "123")); if (is.na(seed_opt)) seed_opt <- 123
repeats_opt    <- suppressWarnings(as.integer(opts[["repeats"]] %||% "5"));  if (is.na(repeats_opt)) repeats_opt <- 5
folds_opt      <- suppressWarnings(as.integer(opts[["folds"]]   %||% "5"));  if (is.na(folds_opt))   folds_opt   <- 5
stratify_opt   <- tolower(opts[["stratify"]] %||% "false") %in% c("1","true","yes","y")
winsorize_opt  <- tolower(opts[["winsorize"]] %||% "false") %in% c("1","true","yes","y")
winsor_p_opt   <- suppressWarnings(as.numeric(opts[["winsor_p"]] %||% "0.005")); if (is.na(winsor_p_opt)) winsor_p_opt <- 0.005
standardize    <- tolower(opts[["standardize"]] %||% "true") %in% c("1","true","yes","y")
weights_mode   <- opts[["weights"]] %||% "none"  # none|min|log1p_min
min_records_th <- suppressWarnings(as.numeric(opts[["min_records_threshold"]] %||% "0")); if (is.na(min_records_th)) min_records_th <- 0
out_dir        <- opts[["out_dir"]]   %||% "artifacts/stage3_multi_regression"

ensure_dir <- function(path) dir.create(path, recursive = TRUE, showWarnings = FALSE)
ensure_dir(out_dir)

fail <- function(msg) { cat(sprintf("[error] %s\n", msg)); quit(status = 1) }

if (!file.exists(in_csv)) fail(sprintf("Input CSV not found: '%s'", in_csv))

# Load data
df <- if (have_readr) readr::read_csv(in_csv, show_col_types = FALSE, progress = FALSE) else utils::read.csv(in_csv, check.names = FALSE)

# Validate essential columns
target_cols <- c("EIVEres-L", "EIVEres-T", "EIVEres-M", "EIVEres-R", "EIVEres-N")
feature_cols <- c("Leaf area (mm2)", "Nmass (mg/g)", "LMA (g/m2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")

miss_t <- setdiff(target_cols, names(df)); if (length(miss_t)) fail(sprintf("Missing target columns: %s", paste(miss_t, collapse=", ")))
miss_f <- setdiff(feature_cols, names(df)); if (length(miss_f)) fail(sprintf("Missing feature columns: %s", paste(miss_f, collapse=", ")))

# Optional filtering by evidence threshold
if (min_records_th > 0) {
  if (!("min_records_6traits" %in% names(df))) fail("'min_records_6traits' not present; cannot filter by evidence threshold.")
  df <- df[is.na(df$min_records_6traits) | df$min_records_6traits >= min_records_th, , drop = FALSE]
}

# Determine targets to run
targets_to_run <- if (identical(tolower(targets_opt), "all")) c("L","T","M","R","N") else unlist(strsplit(gsub("\\s+","",targets_opt), ","))
targets_to_run <- intersect(targets_to_run, c("L","T","M","R","N"))
if (!length(targets_to_run)) fail("No valid targets to run. Use --targets=all or comma list from L,T,M,R,N")

set.seed(seed_opt)

log_vars <- c("Leaf area (mm2)", "Diaspore mass (mg)", "Plant height (m)", "SSD used (mg/mm3)")

compute_offset <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x) & !is.na(x) & x > 0]
  if (!length(x)) return(1e-6)
  max(1e-6, 1e-3 * stats::median(x))
}

winsorize <- function(x, p=0.005, lo=NULL, hi=NULL) {
  x <- as.numeric(x)
  if (is.null(lo) || is.null(hi)) {
    qs <- stats::quantile(x[is.finite(x)], probs=c(p, 1-p), na.rm=TRUE, names=FALSE, type=7)
    lo <- qs[1]; hi <- qs[2]
  }
  x[x < lo] <- lo
  x[x > hi] <- hi
  list(x=x, lo=lo, hi=hi)
}

zscore <- function(x, mean_=NULL, sd_=NULL) {
  x <- as.numeric(x)
  if (is.null(mean_)) mean_ <- mean(x, na.rm=TRUE)
  if (is.null(sd_))   sd_   <- stats::sd(x, na.rm=TRUE)
  if (!is.finite(sd_) || sd_ == 0) sd_ <- 1
  list(x=(x-mean_)/sd_, mean=mean_, sd=sd_)
}

vif_manual <- function(X) {
  # X is a data.frame of predictors
  vifs <- sapply(names(X), function(j) {
    others <- setdiff(names(X), j)
    if (!length(others)) return(1)
    lhs <- sprintf("`%s`", j)
    rhs <- paste(sprintf("`%s`", others), collapse=" + ")
    f <- stats::as.formula(paste(lhs, "~", rhs))
    m <- stats::lm(f, data=X)
    r2 <- max(0, min(1, summary(m)$r.squared))
    1/(1 - r2)
  })
  vifs
}

fit_one_target <- function(target_letter) {
  target_name <- paste0("EIVEres-", target_letter)
  dat <- df[, c(target_name, feature_cols, "wfo_accepted_name"), drop = FALSE]
  dat <- dat[stats::complete.cases(dat[, c(target_name, feature_cols)]), , drop = FALSE]
  n <- nrow(dat)
  if (n < folds_opt) fail(sprintf("Not enough rows (%d) for %d-fold CV", n, folds_opt))

  # Precompute per-variable offsets from full data to keep reproducible, but apply within folds separately
  offsets <- sapply(log_vars, function(v) compute_offset(dat[[v]]))

  # CV fold assigner
  make_folds <- function(y, K, stratify) {
    idx <- seq_along(y)
    if (stratify) {
      # stratify by deciles
      br <- stats::quantile(y, probs = seq(0,1,length.out=11), na.rm=TRUE, type=7)
      br[1] <- -Inf; br[length(br)] <- Inf
      g <- cut(y, breaks=unique(br), include.lowest=TRUE, labels=FALSE)
      split(idx, as.integer(g))
    } else {
      list(idx)
    }
  }

  # storage
  metrics <- data.frame(rep=integer(), fold=integer(), R2=double(), RMSE=double(), MAE=double(), stringsAsFactors = FALSE)
  preds <- data.frame(stringsAsFactors = FALSE)

  # repeated K-fold CV
  for (r in seq_len(repeats_opt)) {
    set.seed(seed_opt + r)
    groups <- make_folds(dat[[target_name]], folds_opt, stratify_opt)
    # initialize fold assignments
    fold_assign <- integer(n)
    if (length(groups) == 1) {
      # random assignment
      fold_assign <- sample(rep(1:folds_opt, length.out=n))
    } else {
      # balance within groups
      fold_assign <- unlist(lapply(groups, function(idxg) {
        sample(rep(1:folds_opt, length.out=length(idxg)))
      }))
      # reorder to original index order
      ord <- unlist(groups)
      fold_tmp <- integer(n); fold_tmp[ord] <- fold_assign; fold_assign <- fold_tmp
    }

    for (k in seq_len(folds_opt)) {
      test_idx <- which(fold_assign == k)
      train_idx <- setdiff(seq_len(n), test_idx)
      train <- dat[train_idx, , drop = FALSE]
      test  <- dat[test_idx,  , drop = FALSE]

      # optional weights
      w <- NULL
      if (weights_mode != "none" && ("min_records_6traits" %in% names(df))) {
        wraw <- df$min_records_6traits[match(train$wfo_accepted_name, df$wfo_accepted_name)]
        if (weights_mode == "min") w <- wraw
        if (weights_mode == "log1p_min") w <- log1p(wraw)
        if (!is.null(w)) w[!is.finite(w)] <- NA
      }

      # transform + winsorize + scale using TRAIN parameters only
      Xtr <- train[, feature_cols, drop = FALSE]
      Xte <- test[,  feature_cols, drop = FALSE]

      # log transforms
      logs <- list()
      for (v in feature_cols) {
        if (v %in% log_vars) {
          off <- offsets[[v]]
          Xtr[[v]] <- log10(Xtr[[v]] + off)
          Xte[[v]] <- log10(Xte[[v]] + off)
          logs[[v]] <- off
        }
      }

      # winsorize
      wins <- list()
      if (winsorize_opt) {
        for (v in feature_cols) {
          wtr <- winsorize(Xtr[[v]], p = winsor_p_opt)
          Xtr[[v]] <- wtr$x
          # apply same clip to test
          Xte[[v]][Xte[[v]] < wtr$lo] <- wtr$lo
          Xte[[v]][Xte[[v]] > wtr$hi] <- wtr$hi
          wins[[v]] <- c(lo=wtr$lo, hi=wtr$hi)
        }
      }

      # standardize
      scales <- list()
      if (standardize) {
        for (v in feature_cols) {
          zs <- zscore(Xtr[[v]])
          Xtr[[v]] <- zs$x
          Xte[[v]] <- (Xte[[v]] - zs$mean)/zs$sd
          scales[[v]] <- c(mean=zs$mean, sd=zs$sd)
        }
      }

      dtr <- data.frame(y = train[[target_name]], Xtr, stringsAsFactors = FALSE, check.names = FALSE)
      dte <- data.frame(y = test[[target_name]],  Xte, stringsAsFactors = FALSE, check.names = FALSE)

      # fit
      terms_bt <- paste(sprintf("`%s`", feature_cols), collapse = " + ")
      f <- stats::as.formula(paste("y ~", terms_bt))
      if (!is.null(w)) {
        m <- stats::lm(f, data = dtr, weights = w)
      } else {
        m <- stats::lm(f, data = dtr)
      }

      ph <- stats::predict(m, newdata = dte)
      err <- dte$y - ph
      R2 <- 1 - sum(err^2)/sum( (dte$y - mean(dte$y))^2 )
      RMSE <- sqrt(mean(err^2))
      MAE <- mean(abs(err))

      metrics <- rbind(metrics, data.frame(rep=r, fold=k, R2=R2, RMSE=RMSE, MAE=MAE))
      preds <- rbind(preds, data.frame(target=target_name, rep=r, fold=k, wfo_accepted_name=test$wfo_accepted_name, y_true=dte$y, y_pred=ph, stringsAsFactors = FALSE))
    }
  }

  # Fit full model for coefficients and VIFs
  Xfull <- dat[, feature_cols, drop = FALSE]
  for (v in feature_cols) {
    if (v %in% log_vars) {
      off <- offsets[[v]]
      Xfull[[v]] <- log10(Xfull[[v]] + off)
    }
  }
  if (winsorize_opt) {
    for (v in feature_cols) {
      Xfull[[v]] <- winsorize(Xfull[[v]], p = winsor_p_opt)$x
    }
  }
  if (standardize) {
    for (v in feature_cols) {
      Xfull[[v]] <- zscore(Xfull[[v]])$x
    }
  }
  dfull <- data.frame(y = dat[[target_name]], Xfull, stringsAsFactors = FALSE, check.names = FALSE)
  terms_bt_full <- paste(sprintf("`%s`", feature_cols), collapse = " + ")
  mfull <- stats::lm(stats::as.formula(paste("y ~", terms_bt_full)), data = dfull)

  # Coefficients and SEs (robust if available)
  coef_tab <- summary(mfull)$coefficients
  if (have_sandwich && have_lmtest) {
    rob <- sandwich::vcovHC(mfull, type = "HC3")
    ct <- lmtest::coeftest(mfull, vcov. = rob)
    coef_tab <- as.matrix(ct)
  }
  rownames(coef_tab) <- gsub("^`|`$", "", rownames(coef_tab))
  colnames(coef_tab)[1:2] <- c("Estimate","Std.Error")
  coefs <- data.frame(term = rownames(coef_tab), Estimate = coef_tab[,"Estimate"], Std.Error = coef_tab[,"Std.Error"], stringsAsFactors = FALSE)

  # VIFs
  vifs <- vif_manual(Xfull)

  # Aggregate metrics
  agg <- data.frame(
    R2_mean = mean(metrics$R2, na.rm=TRUE), R2_sd = stats::sd(metrics$R2, na.rm=TRUE),
    RMSE_mean = mean(metrics$RMSE, na.rm=TRUE), RMSE_sd = stats::sd(metrics$RMSE, na.rm=TRUE),
    MAE_mean = mean(metrics$MAE, na.rm=TRUE), MAE_sd = stats::sd(metrics$MAE, na.rm=TRUE)
  )

  # Write outputs
  base <- file.path(out_dir, paste0("eive_lm_", target_letter))
  preds_path <- paste0(base, "_preds.csv")
  coefs_path <- paste0(base, "_coefficients.csv")
  vif_path   <- paste0(base, "_vif.csv")
  metrics_json <- paste0(base, "_metrics.json")

  if (have_readr) {
    readr::write_csv(preds, preds_path)
    readr::write_csv(coefs, coefs_path)
    readr::write_csv(data.frame(term=names(vifs), VIF=as.numeric(vifs)), vif_path)
  } else {
    utils::write.csv(preds, preds_path, row.names = FALSE)
    utils::write.csv(coefs, coefs_path, row.names = FALSE)
    utils::write.csv(data.frame(term=names(vifs), VIF=as.numeric(vifs)), vif_path, row.names = FALSE)
  }

  metrics_out <- list(
    target = target_name,
    n = nrow(dfull),
    repeats = repeats_opt,
    folds = folds_opt,
    stratify = stratify_opt,
    standardize = standardize,
    winsorize = winsorize_opt,
    winsor_p = winsor_p_opt,
    weights = weights_mode,
    min_records_threshold = min_records_th,
    seed = seed_opt,
    offsets = as.list(offsets),
    metrics = list(per_fold = metrics, aggregate = agg)
  )

  if (have_jsonlite) {
    json <- jsonlite::toJSON(metrics_out, pretty = TRUE, dataframe = "rows", na = "null")
    cat(json, file = metrics_json)
  } else {
    # Fallback: write aggregate metrics as CSV and parameters as txt
    agg_path <- paste0(base, "_metrics_aggregate.csv")
    if (have_readr) readr::write_csv(agg, agg_path) else utils::write.csv(agg, agg_path, row.names = FALSE)
    cat("jsonlite not available; wrote CSV aggregate metrics instead.\n", file = paste0(base, "_note.txt"))
  }

  list(
    base = base,
    preds = preds_path,
    coefs = coefs_path,
    vif = vif_path,
    metrics_json = metrics_json,
    n = nrow(dfull),
    agg = agg
  )
}

results <- lapply(targets_to_run, fit_one_target)

# Print brief summary for CLI
for (res in results) {
  cat(sprintf("Target %s: n=%d, R2=%.3f±%.3f, RMSE=%.3f±%.3f, MAE=%.3f±%.3f\n",
              sub("^.*_", "", res$base), res$n,
              res$agg$R2_mean, res$agg$R2_sd, res$agg$RMSE_mean, res$agg$RMSE_sd, res$agg$MAE_mean, res$agg$MAE_sd))
  cat(sprintf("  Wrote: %s_{preds.csv, coefficients.csv, vif.csv, metrics.json}\n", res$base))
}

invisible(NULL)

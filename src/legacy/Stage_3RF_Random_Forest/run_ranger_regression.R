#!/usr/bin/env Rscript

# Stage 3RF — Random Forest (ranger) baseline for EIVE axes
# Mirrors Stage 3 CV scaffolding with per-fold transforms.
# Outputs per-axis: out-of-fold predictions, per-fold metrics, aggregate metrics,
# and feature importance. Artifacts mirror Stage 3 naming for easy comparison.

suppressWarnings({
  .libPaths(c(normalizePath(".Rlib"), .libPaths()))
  suppressMessages({
    have_readr    <- requireNamespace("readr",    quietly = TRUE)
    have_jsonlite <- requireNamespace("jsonlite", quietly = TRUE)
    have_ranger   <- requireNamespace("ranger",   quietly = TRUE)
  })
})

fail <- function(msg) { cat(sprintf("[error] %s\n", msg)); quit(status = 1) }
if (!have_ranger) fail("Package 'ranger' not installed. Run install.packages('ranger').")

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

in_csv         <- opts[["input_csv"]]   %||% "artifacts/model_data_complete_case.csv"
targets_opt    <- opts[["targets"]]     %||% "all"
seed_opt       <- suppressWarnings(as.integer(opts[["seed"]] %||% "42")); if (is.na(seed_opt)) seed_opt <- 42
repeats_opt    <- suppressWarnings(as.integer(opts[["repeats"]] %||% "10")); if (is.na(repeats_opt)) repeats_opt <- 10
folds_opt      <- suppressWarnings(as.integer(opts[["folds"]]   %||% "5"));  if (is.na(folds_opt))   folds_opt   <- 5
stratify_opt   <- tolower(opts[["stratify"]] %||% "true") %in% c("1","true","yes","y")
winsorize_opt  <- tolower(opts[["winsorize"]] %||% "false") %in% c("1","true","yes","y")
winsor_p_opt   <- suppressWarnings(as.numeric(opts[["winsor_p"]] %||% "0.005")); if (is.na(winsor_p_opt)) winsor_p_opt <- 0.005
standardize    <- tolower(opts[["standardize"]] %||% "true") %in% c("1","true","yes","y")
weights_mode   <- opts[["weights"]] %||% "none"  # none|min|log1p_min
min_records_th <- suppressWarnings(as.numeric(opts[["min_records_threshold"]] %||% "0")); if (is.na(min_records_th)) min_records_th <- 0
out_dir        <- opts[["out_dir"]]   %||% "artifacts/stage3rf_ranger"

# ranger params
num_trees_opt  <- suppressWarnings(as.integer(opts[["num_trees"]] %||% "1000")); if (is.na(num_trees_opt)) num_trees_opt <- 1000
mtry_opt       <- suppressWarnings(as.integer(opts[["mtry"]]      %||% "3"));    if (is.na(mtry_opt)) mtry_opt <- 3
min_node_opt   <- suppressWarnings(as.integer(opts[["min_node_size"]] %||% "5")); if (is.na(min_node_opt)) min_node_opt <- 5
sample_frac    <- suppressWarnings(as.numeric(opts[["sample_fraction"]] %||% "0.632")); if (is.na(sample_frac)) sample_frac <- 0.632
max_depth_opt  <- suppressWarnings(as.integer(opts[["max_depth"]] %||% "0")); if (is.na(max_depth_opt)) max_depth_opt <- 0 # 0 = unlimited

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
if (!file.exists(in_csv)) fail(sprintf("Input CSV not found: '%s'", in_csv))

df <- if (have_readr) readr::read_csv(in_csv, show_col_types = FALSE, progress = FALSE) else utils::read.csv(in_csv, check.names = FALSE)

target_cols <- c("EIVEres-L", "EIVEres-T", "EIVEres-M", "EIVEres-R", "EIVEres-N")
feature_cols <- c("Leaf area (mm2)", "Nmass (mg/g)", "LMA (g/m2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")

miss_t <- setdiff(target_cols, names(df)); if (length(miss_t)) fail(sprintf("Missing target columns: %s", paste(miss_t, collapse=", ")))
miss_f <- setdiff(feature_cols, names(df)); if (length(miss_f)) fail(sprintf("Missing feature columns: %s", paste(miss_f, collapse=", ")))

targets_to_run <- if (identical(tolower(targets_opt), "all")) c("L","T","M","R","N") else intersect(strsplit(gsub("\\s+","",targets_opt), ",")[[1]], c("L","T","M","R","N"))
if (!length(targets_to_run)) fail("No valid targets to run. Use --targets=all or subset of L,T,M,R,N")

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
    qs <- stats::quantile(x[is.finite(x)], probs=c(p, 1-p), na.rm=TRUE, type=7)
    lo <- qs[1]; hi <- qs[2]
  }
  x[x < lo] <- lo; x[x > hi] <- hi
  list(x=x, lo=lo, hi=hi)
}

zscore <- function(x, mean_=NULL, sd_=NULL) {
  x <- as.numeric(x)
  if (is.null(mean_)) mean_ <- mean(x, na.rm=TRUE)
  if (is.null(sd_))   sd_   <- stats::sd(x, na.rm=TRUE)
  if (!is.finite(sd_) || sd_ == 0) sd_ <- 1
  list(x=(x-mean_)/sd_, mean=mean_, sd=sd_)
}

make_groups <- function(y, K, stratify=TRUE) {
  if (!stratify) return(list(seq_along(y)))
  br <- stats::quantile(y, probs = seq(0,1,length.out=11), na.rm=TRUE, type=7)
  br[1] <- -Inf; br[length(br)] <- Inf
  g <- cut(y, breaks=unique(br), include.lowest=TRUE, labels=FALSE)
  split(seq_along(y), as.integer(g))
}

fit_one <- function(target_letter) {
  target_name <- paste0("EIVEres-", target_letter)
  dat <- df[, c(target_name, feature_cols, "wfo_accepted_name"), drop = FALSE]
  dat <- dat[stats::complete.cases(dat[, c(target_name, feature_cols)]), , drop = FALSE]
  if (min_records_th > 0) {
    if (!("min_records_6traits" %in% names(df))) fail("'min_records_6traits' not present; cannot filter by evidence threshold.")
    keep <- is.na(df$min_records_6traits) | df$min_records_6traits >= min_records_th
    # align
    keep_aligned <- keep[match(dat$wfo_accepted_name, df$wfo_accepted_name)]
    dat <- dat[isTRUE(keep_aligned) | is.na(keep_aligned), , drop=FALSE]
  }

  n <- nrow(dat)
  if (n < folds_opt) fail(sprintf("Not enough rows (%d) for %d-fold CV", n, folds_opt))

  offsets <- sapply(intersect(names(dat), log_vars), function(v) compute_offset(dat[[v]]))

  metrics <- data.frame(rep=integer(), fold=integer(), R2=double(), RMSE=double(), MAE=double())
  preds   <- data.frame(stringsAsFactors = FALSE)
  imp_sum <- setNames(rep(0, length(feature_cols)), feature_cols)
  imp_cnt <- 0L

  y_all <- dat[[target_name]]

  for (r in seq_len(repeats_opt)) {
    set.seed(seed_opt + r)
    groups <- make_groups(y_all, folds_opt, stratify_opt)
    fold_assign <- integer(n)
    if (length(groups) == 1) {
      fold_assign <- sample(rep(1:folds_opt, length.out=n))
    } else {
      fold_assign <- unlist(lapply(groups, function(idxg) sample(rep(1:folds_opt, length.out=length(idxg)))))
      ord <- unlist(groups)
      tmp <- integer(n); tmp[ord] <- fold_assign; fold_assign <- tmp
    }

    for (k in seq_len(folds_opt)) {
      test_idx <- which(fold_assign == k)
      train_idx <- setdiff(seq_len(n), test_idx)
      train <- dat[train_idx, , drop = FALSE]
      test  <- dat[test_idx,  , drop = FALSE]

      Xtr <- train[, feature_cols, drop = FALSE]
      Xte <- test[,  feature_cols, drop = FALSE]

      # log transforms using stable offsets
      for (v in feature_cols) {
        if (v %in% names(offsets)) {
          off <- offsets[[v]]
          Xtr[[v]] <- log10(Xtr[[v]] + off)
          Xte[[v]] <- log10(Xte[[v]] + off)
        }
      }

      # winsorize
      if (winsorize_opt) {
        for (v in feature_cols) {
          wtr <- winsorize(Xtr[[v]], p = winsor_p_opt)
          Xtr[[v]] <- wtr$x
          Xte[[v]][Xte[[v]] < wtr$lo] <- wtr$lo
          Xte[[v]][Xte[[v]] > wtr$hi] <- wtr$hi
        }
      }

      # standardize (optional)
      if (standardize) {
        for (v in feature_cols) {
          zs <- zscore(Xtr[[v]])
          Xtr[[v]] <- zs$x
          Xte[[v]] <- (Xte[[v]] - zs$mean)/zs$sd
        }
      }

      ytr <- train[[target_name]]
      yte <- test[[target_name]]

      # weights
      w <- NULL
      if (weights_mode != "none" && ("min_records_6traits" %in% names(df))) {
        wraw <- df$min_records_6traits[match(train$wfo_accepted_name, df$wfo_accepted_name)]
        if (weights_mode == "min") w <- wraw
        if (weights_mode == "log1p_min") w <- log1p(wraw)
        if (!is.null(w)) w[!is.finite(w)] <- NA
      }

      dtr <- data.frame(y=ytr, Xtr, check.names = FALSE)
      dte <- data.frame(y=yte, Xte, check.names = FALSE)

      rf <- ranger::ranger(
        dependent.variable.name = "y",
        data = dtr,
        num.trees = num_trees_opt,
        mtry = mtry_opt,
        min.node.size = min_node_opt,
        sample.fraction = sample_frac,
        max.depth = if (max_depth_opt > 0) max_depth_opt else NULL,
        write.forest = TRUE,
        importance = "impurity",
        case.weights = w,
        seed = seed_opt + r*100 + k,
        num.threads = 0
      )

      ph <- stats::predict(rf, data = dte)$predictions
      err <- yte - ph
      R2 <- 1 - sum(err^2)/sum( (yte - mean(yte))^2 )
      RMSE <- sqrt(mean(err^2))
      MAE <- mean(abs(err))

      metrics <- rbind(metrics, data.frame(rep=r, fold=k, R2=R2, RMSE=RMSE, MAE=MAE))
      preds <- rbind(preds, data.frame(target=target_name, rep=r, fold=k, wfo_accepted_name=test$wfo_accepted_name, y_true=yte, y_pred=ph))

      vi <- ranger::importance(rf)
      # Ensure all features present
      vi_full <- setNames(rep(0, length(feature_cols)), feature_cols)
      vi_full[names(vi)] <- as.numeric(vi)
      imp_sum <- imp_sum + vi_full
      imp_cnt <- imp_cnt + 1L
    }
  }

  agg <- data.frame(
    R2_mean = mean(metrics$R2, na.rm=TRUE), R2_sd = stats::sd(metrics$R2, na.rm=TRUE),
    RMSE_mean = mean(metrics$RMSE, na.rm=TRUE), RMSE_sd = stats::sd(metrics$RMSE, na.rm=TRUE),
    MAE_mean = mean(metrics$MAE, na.rm=TRUE), MAE_sd = stats::sd(metrics$MAE, na.rm=TRUE)
  )

  base <- file.path(out_dir, paste0("eive_rf_", target_letter))
  preds_path <- paste0(base, "_preds.csv")
  metrics_json <- paste0(base, "_metrics.json")
  import_path <- paste0(base, "_feature_importance.csv")

  if (have_readr) readr::write_csv(preds, preds_path) else utils::write.csv(preds, preds_path, row.names = FALSE)

  imp_out <- data.frame(feature=names(imp_sum), importance=as.numeric(imp_sum)/max(imp_cnt,1))
  if (have_readr) readr::write_csv(imp_out, import_path) else utils::write.csv(imp_out, import_path, row.names = FALSE)

  meta <- list(
    target = target_name,
    n = nrow(dat),
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
    ranger_params = list(num_trees=num_trees_opt, mtry=mtry_opt, min_node_size=min_node_opt, sample_fraction=sample_frac, max_depth=max_depth_opt),
    metrics = list(per_fold = metrics, aggregate = agg)
  )
  if (have_jsonlite) {
    json <- jsonlite::toJSON(meta, pretty = TRUE, dataframe = "rows", na = "null")
    cat(json, file = metrics_json)
  } else {
    if (have_readr) readr::write_csv(agg, paste0(base, "_metrics_aggregate.csv")) else utils::write.csv(agg, paste0(base, "_metrics_aggregate.csv"), row.names = FALSE)
  }

  list(base=base, preds=preds_path, metrics_json=metrics_json, importances=import_path, n=nrow(dat), agg=agg)
}

results <- lapply(targets_to_run, fit_one)
for (res in results) {
  cat(sprintf("Target %s: n=%d, R2=%.3f±%.3f, RMSE=%.3f±%.3f, MAE=%.3f±%.3f\n",
              sub("^.*_", "", res$base), res$n,
              res$agg$R2_mean, res$agg$R2_sd, res$agg$RMSE_mean, res$agg$RMSE_sd, res$agg$MAE_mean, res$agg$MAE_sd))
  cat(sprintf("  Wrote: %s_{preds.csv, feature_importance.csv, metrics.json}\n", res$base))
}

invisible(NULL)

#!/usr/bin/env Rscript

# Ordinal comparator: fit proportional-odds (ordinal) models by discretizing
# EIVE (0–10) into 10 ordered ranks (1–10). Uses ordinal::clm if available,
# otherwise MASS::polr. Mirrors Stage 3 preprocessing and CV.

suppressWarnings({
  suppressMessages({
    have_readr    <- requireNamespace("readr",    quietly = TRUE)
    have_dplyr    <- requireNamespace("dplyr",    quietly = TRUE)
    have_tibble   <- requireNamespace("tibble",   quietly = TRUE)
    have_jsonlite <- requireNamespace("jsonlite", quietly = TRUE)
    have_ordinal  <- requireNamespace("ordinal",  quietly = TRUE)
    have_MASS     <- requireNamespace("MASS",     quietly = TRUE)
  })
})

args <- commandArgs(trailingOnly = TRUE)
parse_args <- function(args) { out <- list(); for (a in args) { if (!grepl("^--[A-Za-z0-9_]+=", a)) next; kv <- sub("^--","",a); k <- sub("=.*$","",kv); v <- sub("^[^=]*=","",kv); out[[k]] <- v }; out }
opts <- parse_args(args)
`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b

in_csv       <- opts[["input_csv"]] %||% "artifacts/model_data_complete_case.csv"
targets_opt  <- opts[["targets"]]   %||% "L,T,M"   # focus on L,T,M to mirror 2017; allow others
levels_opt   <- suppressWarnings(as.integer(opts[["levels"]] %||% "10")); if (is.na(levels_opt) || levels_opt < 3) levels_opt <- 10
seed_opt     <- suppressWarnings(as.integer(opts[["seed"]] %||% "123")); if (is.na(seed_opt)) seed_opt <- 123
repeats_opt  <- suppressWarnings(as.integer(opts[["repeats"]] %||% "5"));  if (is.na(repeats_opt)) repeats_opt <- 5
folds_opt    <- suppressWarnings(as.integer(opts[["folds"]]   %||% "5"));  if (is.na(folds_opt))   folds_opt   <- 5
stratify_opt <- tolower(opts[["stratify"]] %||% "true") %in% c("1","true","yes","y")
standardize  <- tolower(opts[["standardize"]] %||% "true") %in% c("1","true","yes","y")
winsorize_on <- tolower(opts[["winsorize"]] %||% "false") %in% c("1","true","yes","y")
winsor_p_opt <- suppressWarnings(as.numeric(opts[["winsor_p"]] %||% "0.005")); if (is.na(winsor_p_opt)) winsor_p_opt <- 0.005
out_dir      <- opts[["out_dir"]]   %||% "artifacts/stage3_multi_regression"

ensure_dir <- function(path) dir.create(path, recursive = TRUE, showWarnings = FALSE)
ensure_dir(out_dir)
fail <- function(msg) { cat(sprintf("[error] %s\n", msg)); quit(status = 1) }
if (!file.exists(in_csv)) fail(sprintf("Input CSV not found: '%s'", in_csv))

df <- if (have_readr) readr::read_csv(in_csv, show_col_types = FALSE, progress = FALSE) else utils::read.csv(in_csv, check.names = FALSE)

target_cols <- c("EIVEres-L", "EIVEres-T", "EIVEres-M")
feature_cols <- c("Leaf area (mm2)", "Nmass (mg/g)", "LMA (g/m2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")
miss_t <- setdiff(target_cols[target_cols %in% names(df)], names(df)); # harmless
miss_f <- setdiff(feature_cols, names(df)); if (length(miss_f)) fail(sprintf("Missing feature columns: %s", paste(miss_f, collapse=", ")))

targets_to_run <- unlist(strsplit(gsub("\\s+","",targets_opt),","))
targets_to_run <- intersect(targets_to_run, c("L","T","M","R","N"))
if (!length(targets_to_run)) fail("No valid targets to run. Use --targets=L,T,M or include from L,T,M,R,N")

log_vars <- c("Leaf area (mm2)", "Diaspore mass (mg)", "Plant height (m)", "SSD used (mg/mm3)")
compute_offset <- function(x) { x <- as.numeric(x); x <- x[is.finite(x) & !is.na(x) & x > 0]; if (!length(x)) return(1e-6); max(1e-6, 1e-3 * stats::median(x)) }
winsorize <- function(x, p=0.005, lo=NULL, hi=NULL) { x <- as.numeric(x); if (is.null(lo) || is.null(hi)) { qs <- stats::quantile(x[is.finite(x)], probs=c(p,1-p), na.rm=TRUE, names=FALSE, type=7); lo <- qs[1]; hi <- qs[2] }; x[x < lo] <- lo; x[x > hi] <- hi; list(x=x, lo=lo, hi=hi) }
zscore <- function(x, mean_=NULL, sd_=NULL) { x <- as.numeric(x); if (is.null(mean_)) mean_ <- mean(x, na.rm=TRUE); if (is.null(sd_)) sd_ <- stats::sd(x, na.rm=TRUE); if (!is.finite(sd_) || sd_==0) sd_ <- 1; list(x=(x-mean_)/sd_, mean=mean_, sd=sd_) }

to_rankN <- function(y, N=10) { # map [0,10] -> ordered factor 1..N
  r <- floor(as.numeric(y) * (N/10)) + 1
  r[!is.finite(r)] <- NA
  r[r < 1] <- 1
  r[r > N] <- N
  factor(r, levels = seq_len(N), ordered = TRUE)
}

fit_one <- function(letter) {
  target_name <- paste0("EIVEres-", letter)
  if (!(target_name %in% names(df))) fail(sprintf("Missing target column: %s", target_name))
  dat <- df[, c(target_name, feature_cols, "wfo_accepted_name"), drop = FALSE]
  dat <- dat[stats::complete.cases(dat[, c(target_name, feature_cols)]), , drop = FALSE]
  n <- nrow(dat)
  if (n < folds_opt) fail(sprintf("Not enough rows (%d) for %d-fold CV", n, folds_opt))

  y_ord <- to_rankN(dat[[target_name]], N = levels_opt)
  dat$.__y_ord <- y_ord
  y_num <- as.numeric(y_ord)

  # Precompute offsets on full data (per variable) for determinism
  offsets <- sapply(log_vars, function(v) compute_offset(dat[[v]]))

  # fold assignment, stratified by y_ord
  set.seed(seed_opt)
  idx <- seq_len(n)
  make_folds <- function(g, K) {
    if (!stratify_opt) return(sample(rep(1:K, length.out=n)))
    groups <- split(idx, y_ord)
    fold_assign <- integer()
    fold_idx <- integer(n)
    for (lev in names(groups)) {
      ids <- groups[[lev]]
      if (!length(ids)) next
      fa <- sample(rep(1:K, length.out=length(ids)))
      fold_idx[ids] <- fa
    }
    fold_idx
  }

  metrics <- data.frame(rep=integer(), fold=integer(), RMSE=double(), MAE=double(), Hit1=double(), Hit2=double(), stringsAsFactors = FALSE)
  preds <- data.frame(stringsAsFactors = FALSE)

  for (r in seq_len(repeats_opt)) {
    set.seed(seed_opt + r)
    fold_assign <- make_folds(y_ord, folds_opt)
    for (k in 1:folds_opt) {
      te <- which(fold_assign == k)
      tr <- setdiff(idx, te)
      train <- dat[tr, , drop = FALSE]
      test  <- dat[te, , drop = FALSE]

      # transforms on train
      Xtr <- train[, feature_cols, drop = FALSE]
      Xte <- test[,  feature_cols, drop = FALSE]
      # log10
      for (v in feature_cols) if (v %in% log_vars) { off <- offsets[[v]]; Xtr[[v]] <- log10(Xtr[[v]] + off); Xte[[v]] <- log10(Xte[[v]] + off) }
      # winsorize
      if (winsorize_on) { for (v in feature_cols) { wtr <- winsorize(Xtr[[v]], p=winsor_p_opt); Xtr[[v]] <- wtr$x; Xte[[v]][Xte[[v]] < wtr$lo] <- wtr$lo; Xte[[v]][Xte[[v]] > wtr$hi] <- wtr$hi } }
      # standardize
      if (standardize) { for (v in feature_cols) { zs <- zscore(Xtr[[v]]); Xtr[[v]] <- zs$x; Xte[[v]] <- (Xte[[v]] - zs$mean)/zs$sd } }

      dtr <- data.frame(y = to_rankN(train[[target_name]], N = levels_opt), Xtr, stringsAsFactors = FALSE, check.names = FALSE)
      dte <- data.frame(y = to_rankN(test[[target_name]],  N = levels_opt), Xte, stringsAsFactors = FALSE, check.names = FALSE)

      # fit ordinal model
      form <- stats::as.formula(paste("y ~", paste(sprintf("`%s`", feature_cols), collapse = " + ")))
      mdl <- NULL
      if (have_ordinal) {
        mdl <- ordinal::clm(form, data = dtr, link = "logit", Hess = TRUE)
        pr <- predict(mdl, newdata = dte, type = "prob")$fit
      } else if (have_MASS) {
        mdl <- MASS::polr(form, data = dtr, Hess = TRUE, method = "logistic")
        pr <- stats::predict(mdl, newdata = dte, type = "probs")
      } else {
        fail("Need either 'ordinal' or 'MASS' package available.")
      }

      # expected rank and hit-rates
      mat <- as.matrix(pr) # rows x N
      ranks <- 1:ncol(mat)
      yhat <- as.numeric(mat %*% ranks)
      ytrue <- as.numeric(dte$y)
      err <- yhat - ytrue
      RMSE <- sqrt(mean((err)^2))
      MAE  <- mean(abs(err))
      Hit1 <- mean(abs(err) <= 1)
      Hit2 <- mean(abs(err) <= 2)

      metrics <- rbind(metrics, data.frame(rep=r, fold=k, RMSE=RMSE, MAE=MAE, Hit1=Hit1, Hit2=Hit2))
      preds <- rbind(preds, data.frame(target=target_name, rep=r, fold=k, wfo_accepted_name=test$wfo_accepted_name, y_true=ytrue, y_pred=yhat, stringsAsFactors = FALSE))
    }
  }

  agg <- data.frame(
    RMSE_mean = mean(metrics$RMSE), RMSE_sd = stats::sd(metrics$RMSE),
    MAE_mean  = mean(metrics$MAE),  MAE_sd  = stats::sd(metrics$MAE),
    Hit1_mean = mean(metrics$Hit1), Hit1_sd = stats::sd(metrics$Hit1),
    Hit2_mean = mean(metrics$Hit2), Hit2_sd = stats::sd(metrics$Hit2)
  )

  # write
  base <- if (levels_opt == 10) file.path(out_dir, paste0("eive_clm_", letter)) else file.path(out_dir, paste0("eive_clm", levels_opt, "_", letter))
  preds_path <- paste0(base, "_preds.csv")
  metrics_json <- paste0(base, "_metrics.json")
  if (have_readr) readr::write_csv(preds, preds_path) else utils::write.csv(preds, preds_path, row.names = FALSE)
  out <- list(target = target_name, repeats = repeats_opt, folds = folds_opt, stratify = stratify_opt, standardize = standardize, winsorize = winsorize_on, winsor_p = winsor_p_opt, offsets = as.list(offsets), metrics = list(per_fold = metrics, aggregate = agg))
  if (have_jsonlite) cat(jsonlite::toJSON(out, pretty = TRUE, dataframe = "rows", na = "null"), file = metrics_json) else { if (have_readr) readr::write_csv(agg, paste0(base, "_metrics_aggregate.csv")) else utils::write.csv(agg, paste0(base, "_metrics_aggregate.csv"), row.names = FALSE) }

  list(base=base, n=n, agg=agg)
}

res <- lapply(targets_to_run, fit_one)
for (r in res) {
  cat(sprintf("Ordinal%s %s: n=%d, RMSE=%.3f±%.3f, MAE=%.3f±%.3f, Hit1=%.1f%%, Hit2=%.1f%%\n",
              if (levels_opt==10) "" else paste0("(", levels_opt, ")"),
              sub("^.*_", "", r$base), r$n,
              r$agg$RMSE_mean, r$agg$RMSE_sd, r$agg$MAE_mean, r$agg$MAE_sd,
              100*r$agg$Hit1_mean, 100*r$agg$Hit2_mean))
  cat(sprintf("  Wrote: %s_{preds.csv, metrics.json}\n", r$base))
}

invisible(NULL)

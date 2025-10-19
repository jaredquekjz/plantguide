#!/usr/bin/env Rscript

# Stage 4 — SEM (lavaan) runner with CV predictions
# - Preprocess features: log10 transforms with small offsets (Leaf area, Plant height,
#   Diaspore mass, SSD used), optional winsorization, optional standardization.
# - CV predictions use composite proxies (PC1 scores) for LES and SIZE to avoid leakage and
#   dependency on lavaan scoring across folds. This mirrors piecewise usage and provides
#   reproducible OOS metrics even if lavaan is unavailable.
# - If lavaan is available, fit the full latent model on all data to export path coefficients
#   and fit indices. This supports inference while keeping CV predictive hygiene.

suppressWarnings({
  suppressMessages({
    have_readr    <- requireNamespace("readr",    quietly = TRUE)
    have_dplyr    <- requireNamespace("dplyr",    quietly = TRUE)
    have_tibble   <- requireNamespace("tibble",   quietly = TRUE)
    have_jsonlite <- requireNamespace("jsonlite", quietly = TRUE)
    have_lavaan   <- requireNamespace("lavaan",   quietly = TRUE)
  })
})

args <- commandArgs(trailingOnly = TRUE)

# Robust CLI parser: accepts "--k=v" and "--k v" and boolean flags ("--flag")
parse_args <- function(args) {
  out <- list()
  i <- 1
  while (i <= length(args)) {
    a <- args[[i]]
    if (grepl("^--[A-Za-z0-9_]+=", a)) {
      kv <- sub("^--", "", a)
      k <- sub("=.*$", "", kv)
      v <- sub("^[^=]*=", "", kv)
      out[[k]] <- v
      i <- i + 1
    } else if (grepl("^--[A-Za-z0-9_]+$", a)) {
      k <- sub("^--", "", a)
      v <- if (i < length(args)) args[[i+1]] else ""
      if (nzchar(v) && !startsWith(v, "--")) {
        out[[k]] <- v
        i <- i + 2
      } else {
        out[[k]] <- "true"
        i <- i + 1
      }
    } else {
      i <- i + 1
    }
  }
  out
}

opts <- parse_args(args)

if (!is.null(opts$help) && tolower(opts$help) %in% c("true","1","yes","y","help")) {
  cat("\nStage 4 — lavaan SEM runner (CV via composites + full-data lavaan)\n")
  cat("Usage:\n")
  cat("  Rscript src/Stage_4_SEM_Analysis/run_sem_lavaan.R \\\n+    --input_csv artifacts/model_data_complete_case_with_myco.csv \\\n+    --target L --transform logit --repeats 5 --folds 10 --stratify true \\\n+    --standardize true --winsorize false --group Woodiness --cluster Family \\\n+    --deconstruct_size true --les_core true --logLA_as_predictor true \\\n+    --add_direct_ssd_targets M,N --allow_les_size_cov true \\\n+    --out_dir artifacts/stage4_sem_lavaan_run7\n\n")
  cat("Flags (accept --k=v or --k v):\n")
  cat("  --input_csv PATH           Input CSV with columns: wfo_accepted_name, EIVEres-{L,T,M,R,N},\n")
  cat("                             Leaf area (mm2), Nmass (mg/g), LMA (g/m2), Plant height (m),\n")
  cat("                             Diaspore mass (mg), SSD used (mg/mm3)\n")
  cat("  --target L|T|M|R|N         Axis to model (default L)\n")
  cat("  --transform logit|identity Response transform for CV proxies (default logit)\n")
  cat("  --repeats INT --folds INT  Repeated stratified CV (defaults 5×5)\n")
  cat("  --stratify true|false      Stratify CV by y deciles (default true)\n")
  cat("  --standardize true|false   Z-score predictors within folds (default true)\n")
  cat("  --winsorize true|false     Winsorize predictors in train (default false)\n")
  cat("  --group NAME               Group variable for lavaan multi-group (e.g., Woodiness)\n")
  cat("  --cluster NAME             Cluster variable for robust SEs (e.g., Family)\n")
  cat("  --deconstruct_size true|false Use logH+logSM directly in y (M/N style)\n")
  cat("  --coadapt_les true|false   Replace LES ~ SIZE+logSSD with LES ~~ SIZE and LES ~~ logSSD\n")
  cat("  --les_core true|false      Use LES =~ negLMA + Nmass (Run 7 core)\n")
  cat("  --les_core_indicators CSV  If overriding, CSV of indicators (default negLMA,Nmass)\n")
  cat("  --logLA_as_predictor true|false  Include logLA -> y\n")
  cat("  --add_direct_ssd_targets CSV     Targets with direct logSSD -> y (e.g., M,N)\n")
  cat("  --allow_les_size_cov true|false  Keep LES ~~ SIZE residual covariance\n")
  cat("  --resid_cov STR            Extra residual covs (e.g., 'logH ~~ logSM; Nmass ~~ logLA')\n")
  cat("  --bootstrap true|false     lavaan bootstrap SEs (default false); --n_boot N; --bootstrap_ci_type perc|bca|norm\n")
  cat("  --out_dir PATH             Output directory\n\n")
  cat("Examples: see README Section ‘Structural Equation Modeling’.\n")
  quit(status = 0)
}

`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b

# Inputs / flags
in_csv        <- opts[["input_csv"]]   %||% "artifacts/model_data_complete_case.csv"
target_letter <- toupper(opts[["target"]] %||% "L")
transform_y   <- tolower(opts[["transform"]] %||% "logit")  # logit|identity
seed_opt      <- suppressWarnings(as.integer(opts[["seed"]] %||% "123")); if (is.na(seed_opt)) seed_opt <- 123
repeats_opt   <- suppressWarnings(as.integer(opts[["repeats"]] %||% "5"));  if (is.na(repeats_opt)) repeats_opt <- 5
folds_opt     <- suppressWarnings(as.integer(opts[["folds"]]   %||% "5"));  if (is.na(folds_opt))   folds_opt   <- 5
stratify_opt  <- tolower(opts[["stratify"]] %||% "true") %in% c("1","true","yes","y")
winsorize_opt <- tolower(opts[["winsorize"]] %||% "false") %in% c("1","true","yes","y")
winsor_p_opt  <- suppressWarnings(as.numeric(opts[["winsor_p"]] %||% "0.005")); if (is.na(winsor_p_opt)) winsor_p_opt <- 0.005
standardize   <- tolower(opts[["standardize"]] %||% "true") %in% c("1","true","yes","y")
weights_mode  <- opts[["weights"]] %||% "none"  # none|min|log1p_min
cluster_var   <- opts[["cluster"]] %||% "Family"  # used only for metadata/future; not needed for CV regression here
group_var     <- opts[["group"]]   %||% "Woodiness"  # used in lavaan full-fit if present
if (!nzchar(cluster_var) || tolower(cluster_var) %in% c("__none__","none","na")) cluster_var <- NA_character_
if (!nzchar(group_var)   || tolower(group_var)   %in% c("__none__","none","na")) group_var   <- NA_character_
out_dir       <- opts[["out_dir"]]  %||% "artifacts/stage4_sem_lavaan"

# lavaan model tuning (full-data fit only)
add_direct_ssd_targets <- toupper(opts[["add_direct_ssd_targets"]] %||% "M,N")
allow_les_size_cov     <- tolower(opts[["allow_les_size_cov"]]     %||% "true") %in% c("1","true","yes","y")
resid_cov_raw          <- opts[["resid_cov"]] %||% "logH ~~ logSM; Nmass ~~ logLA"
resid_cov_terms        <- trimws(unlist(strsplit(resid_cov_raw, ";")))
group_ssd_to_y_for     <- opts[["group_ssd_to_y_for"]] %||% ""  # comma-separated list of group labels where SSD->y is included
deconstruct_size       <- tolower(opts[["deconstruct_size"]] %||% if (target_letter %in% c("M","N")) "true" else "false") %in% c("1","true","yes","y")
coadapt_les            <- tolower(opts[["coadapt_les"]] %||% "false") %in% c("1","true","yes","y")  # if true, replace 'LES ~ SIZE + logSSD' with 'LES ~~ SIZE' and 'LES ~~ logSSD'
# Run 7 — refined LES measurement and logLA as predictor
les_core               <- tolower(opts[["les_core"]] %||% "true") %in% c("1","true","yes","y")
les_core_inds_raw      <- opts[["les_core_indicators"]] %||% "negLMA,Nmass"
les_core_inds          <- trimws(unlist(strsplit(les_core_inds_raw, ",")))
logLA_as_predictor     <- tolower(opts[["logLA_as_predictor"]] %||% "true") %in% c("1","true","yes","y")
min_group_n            <- suppressWarnings(as.integer(opts[["min_group_n"]] %||% "0")); if (is.na(min_group_n)) min_group_n <- 0

# Bootstrap options (full-data lavaan inference only)
do_bootstrap_lav       <- tolower(opts[["bootstrap"]] %||% "false") %in% c("1","true","yes","y")
n_boot_lav             <- suppressWarnings(as.integer(opts[["n_boot"]] %||% "200")); if (is.na(n_boot_lav)) n_boot_lav <- 200
boot_ci_type           <- tolower(opts[["bootstrap_ci_type"]] %||% "perc")  # perc|bca|norm
if (boot_ci_type %in% c("bca.simple","bca")) boot_ci_type <- "bca.simple"

ensure_dir <- function(path) dir.create(path, recursive = TRUE, showWarnings = FALSE)
ensure_dir(out_dir)

fail <- function(msg) { cat(sprintf("[error] %s\n", msg)); quit(status = 1) }

if (!file.exists(in_csv)) fail(sprintf("Input CSV not found: '%s'", in_csv))

# Load data
df <- if (have_readr) readr::read_csv(in_csv, show_col_types = FALSE, progress = FALSE) else utils::read.csv(in_csv, check.names = FALSE)

# Validate columns
target_name <- paste0("EIVEres-", target_letter)
feature_cols <- c("Leaf area (mm2)", "Nmass (mg/g)", "LMA (g/m2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")
id_col <- "wfo_accepted_name"
miss <- setdiff(c(target_name, feature_cols, id_col), names(df))
if (length(miss)) fail(sprintf("Missing required columns: %s", paste(miss, collapse=", ")))

# Keep complete cases for selected variables
df <- df[stats::complete.cases(df[, c(target_name, feature_cols, id_col)]), , drop = FALSE]
if (nrow(df) < folds_opt) fail(sprintf("Not enough rows (%d) for %d-fold CV", nrow(df), folds_opt))

# Helpers
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

# Transform setup
log_vars <- c("Leaf area (mm2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")
offsets <- sapply(log_vars, function(v) compute_offset(df[[v]]))

# CV fold maker
make_folds <- function(y, K, stratify) {
  idx <- seq_along(y)
  if (stratify) {
    br <- stats::quantile(y, probs = seq(0,1,length.out=11), na.rm=TRUE, type=7)
    br[1] <- -Inf; br[length(br)] <- Inf
    g <- cut(y, breaks=unique(br), include.lowest=TRUE, labels=FALSE)
    split(idx, as.integer(g))
  } else {
    list(idx)
  }
}

# Transform EIVE to logit or identity
to_logit <- function(y) {
  p <- (y + 0.5)/10.999
  p <- pmax(pmin(p, 1-1e-6), 1e-6)
  stats::qlogis(p)
}
from_logit <- function(eta) {
  p <- stats::plogis(eta)
  y <- p*10.999 - 0.5
  pmin(pmax(y, 0), 10)
}

# Composite builder using training-only PCA
build_composites <- function(train, test) {
  # Inputs must contain: LMA, Nmass, logLA, logH, logSM
  # LES: PC1 of either [-LMA, Nmass, logLA] or Run 7 core [-LMA, Nmass]
  if (les_core) {
    M_LES_tr <- scale(cbind(negLMA = -train$LMA, Nmass = train$Nmass), center = TRUE, scale = TRUE)
    M_LES_te <- scale(cbind(negLMA = -test$LMA,  Nmass = test$Nmass),  center = attr(M_LES_tr, "scaled:center"), scale = attr(M_LES_tr, "scaled:scale"))
  } else {
    M_LES_tr <- scale(cbind(negLMA = -train$LMA, Nmass = train$Nmass, logLA = train$logLA), center = TRUE, scale = TRUE)
    M_LES_te <- scale(cbind(negLMA = -test$LMA,  Nmass = test$Nmass,  logLA = test$logLA),  center = attr(M_LES_tr, "scaled:center"), scale = attr(M_LES_tr, "scaled:scale"))
  }
  p_les <- stats::prcomp(M_LES_tr, center = FALSE, scale. = FALSE)
  rot_les <- p_les$rotation[,1]
  # orient to positive Nmass loading
  if (rot_les["Nmass"] < 0) rot_les <- -rot_les
  scores_LES_tr <- as.numeric(M_LES_tr %*% rot_les)
  scores_LES_te <- as.numeric(M_LES_te %*% rot_les)

  # SIZE: PC1 of [logH, logSM] oriented to positive logH loading
  M_SIZE_tr <- scale(cbind(logH = train$logH, logSM = train$logSM), center = TRUE, scale = TRUE)
  p_size <- stats::prcomp(M_SIZE_tr, center = FALSE, scale. = FALSE)
  rot_size <- p_size$rotation[,1]
  if (rot_size["logH"] < 0) rot_size <- -rot_size
  scores_SIZE_tr <- as.numeric(M_SIZE_tr %*% rot_size)
  M_SIZE_te <- scale(cbind(logH = test$logH, logSM = test$logSM), center = attr(M_SIZE_tr, "scaled:center"), scale = attr(M_SIZE_tr, "scaled:scale"))
  scores_SIZE_te <- as.numeric(M_SIZE_te %*% rot_size)

  list(
    LES_train = scores_LES_tr,
    LES_test  = scores_LES_te,
    SIZE_train = scores_SIZE_tr,
    SIZE_test  = scores_SIZE_te
  )
}

set.seed(seed_opt)

# Prepare working frame with derived columns
base_cols <- c(id_col, target_name, feature_cols)
if (!is.na(cluster_var) && (cluster_var %in% names(df))) base_cols <- c(base_cols, cluster_var)
if (!is.na(group_var)   && (group_var   %in% names(df))) base_cols <- c(base_cols, group_var)
work <- df[, base_cols, drop = FALSE]
names(work)[names(work) == id_col] <- "id"
if (!is.na(cluster_var) && !(cluster_var %in% names(work))) work[[cluster_var]] <- NA
if (!is.na(group_var)   && !(group_var   %in% names(work))) work[[group_var]]   <- NA

# Apply log transforms using global offsets; winsorize and standardize within folds
work$logLA <- log10(work[["Leaf area (mm2)"]] + offsets[["Leaf area (mm2)"]])
work$logH  <- log10(work[["Plant height (m)"]] + offsets[["Plant height (m)"]])
work$logSM <- log10(work[["Diaspore mass (mg)"]] + offsets[["Diaspore mass (mg)"]])
work$logSSD<- log10(work[["SSD used (mg/mm3)"]] + offsets[["SSD used (mg/mm3)"]])
work$LMA   <- as.numeric(work[["LMA (g/m2)"]])
work$Nmass <- as.numeric(work[["Nmass (mg/g)"]])
work$y_raw <- as.numeric(work[[target_name]])

# Response transform
if (transform_y == "logit") {
  work$y <- to_logit(work$y_raw)
} else {
  work$y <- work$y_raw
}

# CV loop with composite proxies
groups <- make_folds(work$y_raw, folds_opt, stratify_opt)

metrics <- data.frame(rep=integer(), fold=integer(), R2=double(), RMSE=double(), MAE=double(), stringsAsFactors = FALSE)
preds <- data.frame(stringsAsFactors = FALSE)

for (r in seq_len(repeats_opt)) {
  set.seed(seed_opt + r)
  # assign folds
  fold_assign <- integer(nrow(work))
  if (length(groups) == 1) {
    fold_assign <- sample(rep(1:folds_opt, length.out=nrow(work)))
  } else {
    fold_assign <- unlist(lapply(groups, function(idxg) sample(rep(1:folds_opt, length.out=length(idxg)))))
    ord <- unlist(groups)
    tmp <- integer(nrow(work)); tmp[ord] <- fold_assign; fold_assign <- tmp
  }

  for (k in seq_len(folds_opt)) {
    test_idx <- which(fold_assign == k)
    train_idx <- setdiff(seq_len(nrow(work)), test_idx)
    tr <- work[train_idx, , drop = FALSE]
    te <- work[test_idx,  , drop = FALSE]

    # Optional winsorization on training predictors (apply same bounds to test)
    if (winsorize_opt) {
      for (v in c("logLA","logH","logSM","logSSD","LMA","Nmass")) {
        wtr <- winsorize(tr[[v]], p = winsor_p_opt)
        tr[[v]] <- wtr$x
        te[[v]][te[[v]] < wtr$lo] <- wtr$lo
        te[[v]][te[[v]] > wtr$hi] <- wtr$hi
      }
    }

    # Standardize predictors if requested
    if (standardize) {
      for (v in c("logLA","logH","logSM","logSSD","LMA","Nmass")) {
        zs <- zscore(tr[[v]])
        tr[[v]] <- zs$x
        te[[v]] <- (te[[v]] - zs$mean)/zs$sd
      }
    }

    # Build composites on training only
    comps <- build_composites(train = tr, test = te)
    tr$LES  <- comps$LES_train; te$LES  <- comps$LES_test
    tr$SIZE <- comps$SIZE_train; te$SIZE <- comps$SIZE_test

    # weights
    w <- NULL
    if (weights_mode != "none" && ("min_records_6traits" %in% names(df))) {
      wraw <- df$min_records_6traits[match(tr$id, df$wfo_accepted_name)]
      if (weights_mode == "min") w <- wraw
      if (weights_mode == "log1p_min") w <- log1p(wraw)
      if (!is.null(w)) w[!is.finite(w)] <- NA
    }

    # Train regression on composites + logSSD
    dtr <- data.frame(y = tr$y, LES = tr$LES, SIZE = tr$SIZE, logSSD = tr$logSSD, logLA = tr$logLA, stringsAsFactors = FALSE)
    dte <- data.frame(y = te$y, LES = te$LES, SIZE = te$SIZE, logSSD = te$logSSD, logLA = te$logLA, stringsAsFactors = FALSE)
    if (logLA_as_predictor) {
      form <- y ~ LES + SIZE + logSSD + logLA
    } else {
      form <- y ~ LES + SIZE + logSSD
    }
    m <- if (!is.null(w)) stats::lm(form, data = dtr, weights = w) else stats::lm(form, data = dtr)

    eta <- as.numeric(stats::predict(m, newdata = dte))
    yhat <- if (transform_y == "logit") from_logit(eta) else eta
    ytrue <- te$y_raw

    err <- ytrue - yhat
    R2 <- 1 - sum(err^2)/sum((ytrue - mean(ytrue))^2)
    RMSE <- sqrt(mean(err^2))
    MAE <- mean(abs(err))

    metrics <- rbind(metrics, data.frame(rep=r, fold=k, R2=R2, RMSE=RMSE, MAE=MAE))
    preds <- rbind(preds, data.frame(target=target_name, rep=r, fold=k, id=te$id, y_true=ytrue, y_pred=yhat, method="composite_proxy", stringsAsFactors = FALSE))
  }
}

# Aggregate metrics
agg <- data.frame(
  R2_mean = mean(metrics$R2, na.rm=TRUE), R2_sd = stats::sd(metrics$R2, na.rm=TRUE),
  RMSE_mean = mean(metrics$RMSE, na.rm=TRUE), RMSE_sd = stats::sd(metrics$RMSE, na.rm=TRUE),
  MAE_mean = mean(metrics$MAE, na.rm=TRUE), MAE_sd = stats::sd(metrics$MAE, na.rm=TRUE)
)

# Write CV outputs
base <- file.path(out_dir, paste0("sem_lavaan_", target_letter))
preds_path <- paste0(base, "_preds.csv")
metrics_json <- paste0(base, "_metrics.json")

if (have_readr) readr::write_csv(preds, preds_path) else utils::write.csv(preds, preds_path, row.names = FALSE)

metrics_out <- list(
  target = target_name,
  n = nrow(work),
  repeats = repeats_opt,
  folds = folds_opt,
  stratify = stratify_opt,
  standardize = standardize,
  winsorize = winsorize_opt,
  winsor_p = winsor_p_opt,
  weights = weights_mode,
  seed = seed_opt,
  transform = transform_y,
  offsets = as.list(offsets),
  cv_method = "composite_proxy",
  metrics = list(per_fold = metrics, aggregate = agg)
)
if (have_jsonlite) {
  json <- jsonlite::toJSON(metrics_out, pretty = TRUE, dataframe = "rows", na = "null")
  cat(json, file = metrics_json)
} else {
  # fallback minimal
  agg_path <- paste0(base, "_metrics_aggregate.csv")
  if (have_readr) readr::write_csv(agg, agg_path) else utils::write.csv(agg, agg_path, row.names = FALSE)
}

# Full-data lavaan fit for inference (optional)
if (have_lavaan) {
  safe_fit_measures <- function(fit, measures) {
    vals <- list(); keys <- character(0)
    for (m in measures) {
      v <- try(lavaan::fitMeasures(fit, m), silent = TRUE)
      if (!inherits(v, "try-error") && is.finite(as.numeric(v[1]))) {
        keys <- c(keys, m)
        vals[[length(vals)+1]] <- as.numeric(v[1])
      }
    }
    if (!length(keys)) return(NULL)
    data.frame(measure = keys, value = unlist(vals), stringsAsFactors = FALSE)
  }
  lav_cols <- c("y","logLA","LMA","Nmass","logH","logSM","logSSD")
  if (!is.na(group_var)   && (group_var   %in% names(work))) lav_cols <- c(lav_cols, group_var)
  if (!is.na(cluster_var) && (cluster_var %in% names(work))) lav_cols <- c(lav_cols, cluster_var)
  dat_lav <- work[, lav_cols, drop = FALSE]
  # Create negLMA observed variable to fix sign of loading in measurement model
  dat_lav$negLMA <- -dat_lav$LMA
  # Measurement + structural model; Y refers to y (transformed). Use simple names.
  # Helper to build model string with or without direct SSD -> y
  build_model <- function(include_ssd_y) {
    rc <- resid_cov_terms[resid_cov_terms != ""]
    if (!deconstruct_size) {
      # Original latent SIZE
      y_rhs <- "b1*LES + b2*SIZE"
      if (include_ssd_y) y_rhs <- paste(y_rhs, "+ b3*logSSD")
      if (logLA_as_predictor) y_rhs <- paste(y_rhs, "+ b4*logLA")
      lines <- c(
        if (les_core) "LES =~ negLMA + Nmass" else "LES =~ negLMA + Nmass + logLA",
        "SIZE =~ logH + logSM",
        sprintf("y ~ %s", y_rhs)
      )
      if (coadapt_les) {
        # Replace directed influences with co-adaptation (residual covariances)
        # Always include LES ~~ SIZE when co-adapting
        lines <- c(lines, "LES ~~ SIZE", "LES ~~ logSSD")
      } else {
        # Keep directed influences on LES from SIZE and logSSD
        lines <- c(lines, "LES ~ c1*SIZE + c2*logSSD")
        if (allow_les_size_cov) lines <- c(lines, "LES ~~ SIZE")
      }
      if (length(rc)) lines <- c(lines, rc)
      return(paste(lines, collapse = "\n"))
    } else {
      # Deconstruct SIZE: use logH and logSM directly in y; regress LES on logH + logSM + logSSD
      y_rhs <- "b1*LES + b2*logH + b3*logSM"
      if (include_ssd_y) y_rhs <- paste(y_rhs, "+ b4*logSSD")
      if (logLA_as_predictor) y_rhs <- paste(y_rhs, "+ b5*logLA")
      lines <- c(
        if (les_core) "LES =~ negLMA + Nmass" else "LES =~ negLMA + Nmass + logLA",
        sprintf("y ~ %s", y_rhs),
        "LES ~ c1*logH + c2*logSM + c3*logSSD"
      )
      # Keep residual covariance between logH and logSM if requested
      if (allow_les_size_cov) lines <- c(lines, "logH ~~ logSM")
      if (length(rc)) lines <- c(lines, rc)
      return(paste(lines, collapse = "\n"))
    }
  }

  # Determine if we should do group-specific inclusion of SSD -> y
  do_group_specific <- nzchar(group_ssd_to_y_for) && !is.na(group_var) && (group_var %in% names(dat_lav)) && length(unique(na.omit(dat_lav[[group_var]]))) > 1
  if (do_group_specific) {
    # Fit per group with group-specific include_ssd_y, then write by-group fit indices
    glist <- unique(as.character(na.omit(dat_lav[[group_var]])))
    include_groups <- trimws(tolower(unlist(strsplit(group_ssd_to_y_for, ","))))
    rows <- list()
    for (g in glist) {
      sub <- dat_lav[which(as.character(dat_lav[[group_var]]) == g), , drop = FALSE]
      if (nrow(sub) < max(10L, min_group_n)) next
      include_ssd <- (target_letter %in% unlist(strsplit(add_direct_ssd_targets, ","))) || (tolower(g) %in% include_groups)
      model_g <- build_model(include_ssd)
      fit_g <- try(lavaan::sem(model_g, data = sub, estimator = "MLR", missing = "fiml", std.lv = TRUE), silent = TRUE)
      if (inherits(fit_g, "try-error")) next
      fm <- try(lavaan::fitMeasures(fit_g, c("chisq","df","pvalue","cfi","tli","rmsea","srmr","bic","aic")), silent = TRUE)
      if (!inherits(fm, "try-error")) {
        fm_list <- as.list(fm)
        row <- as.data.frame(fm_list, check.names = FALSE, stringsAsFactors = FALSE)
        row$group <- g
        row <- row[, c("group", setdiff(names(row), "group")), drop = FALSE]
        rows[[length(rows)+1]] <- row
      }
    }
    if (length(rows)) {
      fit_by_group <- do.call(rbind, rows)
      fit_path2 <- paste0(base, "_fit_indices_by_group.csv")
      if (have_readr) readr::write_csv(fit_by_group, fit_path2) else utils::write.csv(fit_by_group, fit_path2, row.names = FALSE)
    }
  } else {
    # Single (possibly multi-group) fit with global add_ssd toggle
    add_ssd <- target_letter %in% unlist(strsplit(add_direct_ssd_targets, ","))
    model <- build_model(add_ssd)
    cat(sprintf("[lavaan] target=%s add_ssd=%s deconstruct_size=%s coadapt_les=%s allow_les_size_cov=%s resid_cov_terms=%s\n",
                target_letter, add_ssd, deconstruct_size, coadapt_les, allow_les_size_cov, paste(resid_cov_terms[resid_cov_terms != ""], collapse=' | ')))
    lavaan_args <- list(model = model, data = dat_lav, estimator = "MLR", missing = "fiml", std.lv = TRUE)
    # Enable bootstrap-based SEs and CIs if requested
    if (do_bootstrap_lav) {
      lavaan_args$se <- "bootstrap"
      lavaan_args$bootstrap <- n_boot_lav
      lavaan_args$bootstrap.ci.type <- boot_ci_type
    }
    if (!is.na(group_var) && (group_var %in% names(dat_lav)) && length(unique(na.omit(dat_lav[[group_var]]))) > 1) {
      lavaan_args$group <- group_var
    }
    if (!is.na(cluster_var) && (cluster_var %in% names(dat_lav)) && length(unique(na.omit(dat_lav[[cluster_var]]))) > 1) {
      lavaan_args$cluster <- cluster_var
    }
    fit <- try(do.call(lavaan::sem, lavaan_args), silent = TRUE)
    if (!inherits(fit, "try-error")) {
      # Include confidence intervals when available (analytic or bootstrap)
      std <- try(lavaan::standardizedSolution(fit, ci = TRUE), silent = TRUE)
      if (!inherits(std, "try-error")) {
        coefs_path <- paste0(base, "_path_coefficients.csv")
        if (have_readr) readr::write_csv(std, coefs_path) else utils::write.csv(std, coefs_path, row.names = FALSE)
      }
      desired <- c(
        "chisq","df","pvalue","cfi","tli","rmsea","srmr","bic","aic",
        "chisq.scaled","df.scaled","pvalue.scaled","cfi.scaled","tli.scaled",
        "rmsea.robust","rmsea.scaled","srmr_mplus"
      )
      fit_df <- safe_fit_measures(fit, desired)
      if (!is.null(fit_df)) {
        fit_path <- paste0(base, "_fit_indices.csv")
        if (have_readr) readr::write_csv(fit_df, fit_path) else utils::write.csv(fit_df, fit_path, row.names = FALSE)
      } else {
        cat("[lavaan] fitMeasures unavailable; wrote coefficients only.\n")
      }
    } else {
      cat("[lavaan] fit failed; skipping full-data coefficients and fit indices.\n")
    }
  }
}

cat(sprintf("Target %s: n=%d, R2=%.3f±%.3f, RMSE=%.3f±%.3f, MAE=%.3f±%.3f\n",
            target_letter, nrow(work),
            agg$R2_mean, agg$R2_sd, agg$RMSE_mean, agg$RMSE_sd, agg$MAE_mean, agg$MAE_sd))
cat(sprintf("  Wrote: %s_{preds.csv, metrics.json[, path_coefficients.csv, fit_indices.csv]}\n", base))

invisible(NULL)

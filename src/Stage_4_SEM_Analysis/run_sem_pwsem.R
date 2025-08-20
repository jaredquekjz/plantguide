#!/usr/bin/env Rscript

# Stage 4 — SEM (pwSEM) runner with CV predictions
# - Mirrors the behavior of run_sem_piecewise.R for data prep and CV.
# - Uses pwSEM for full-data d-separation tests and reporting.

suppressWarnings({
  # Allow injecting extra library paths via environment before loading packages
  extra_libs <- Sys.getenv("R_EXTRA_LIBS")
  paths <- character()
  if (nzchar(extra_libs)) paths <- c(paths, unlist(strsplit(extra_libs, "[,:;]", perl = TRUE)))
  if (dir.exists(".Rlib")) paths <- c(normalizePath(".Rlib"), paths)
  paths <- unique(paths[nzchar(paths)])
  if (length(paths)) .libPaths(c(paths, .libPaths()))
})

suppressWarnings({
  suppressMessages({
    have_readr       <- requireNamespace("readr",       quietly = TRUE)
    have_dplyr       <- requireNamespace("dplyr",       quietly = TRUE)
    have_tibble      <- requireNamespace("tibble",      quietly = TRUE)
    have_jsonlite    <- requireNamespace("jsonlite",    quietly = TRUE)
    have_lme4        <- requireNamespace("lme4",        quietly = TRUE)
    have_mgcv        <- requireNamespace("mgcv",        quietly = TRUE)
    have_gamm4       <- requireNamespace("gamm4",       quietly = TRUE)
    have_pwsem       <- requireNamespace("pwSEM",       quietly = TRUE)
    have_ape         <- requireNamespace("ape",         quietly = TRUE)
    have_nlme        <- requireNamespace("nlme",        quietly = TRUE)
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

# Inputs / flags (mirrors run_sem_piecewise where sensible)
in_csv        <- opts[["input_csv"]]   %||% "artifacts/model_data_complete_case.csv"
target_letter <- toupper(opts[["target"]] %||% "L")
seed_opt      <- suppressWarnings(as.integer(opts[["seed"]] %||% "123")); if (is.na(seed_opt)) seed_opt <- 123
repeats_opt   <- suppressWarnings(as.integer(opts[["repeats"]] %||% "5"));  if (is.na(repeats_opt)) repeats_opt <- 5
folds_opt     <- suppressWarnings(as.integer(opts[["folds"]]   %||% "5"));  if (is.na(folds_opt))   folds_opt   <- 5
stratify_opt  <- tolower(opts[["stratify"]] %||% "true") %in% c("1","true","yes","y")
winsorize_opt <- tolower(opts[["winsorize"]] %||% "false") %in% c("1","true","yes","y")
winsor_p_opt  <- suppressWarnings(as.numeric(opts[["winsor_p"]] %||% "0.005")); if (is.na(winsor_p_opt)) winsor_p_opt <- 0.005
standardize   <- tolower(opts[["standardize"]] %||% "true") %in% c("1","true","yes","y")
weights_mode  <- opts[["weights"]] %||% "none"  # none|min|log1p_min
cluster_var   <- opts[["cluster"]] %||% "Family"
group_var     <- opts[["group_var"]] %||% ""      # optional (not used directly in pwSEM)
nonlinear_opt <- tolower(opts[["nonlinear"]] %||% "false") %in% c("1","true","yes","y")
deconstruct_size <- tolower(opts[["deconstruct_size"]] %||% "false") %in% c("1","true","yes","y")
out_dir       <- opts[["out_dir"]]  %||% "artifacts/stage4_sem_pwsem"
force_lm      <- tolower(opts[["force_lm"]] %||% "false") %in% c("1","true","yes","y")
les_components_raw <- opts[["les_components"]] %||% "negLMA,Nmass,logLA"
les_components <- trimws(unlist(strsplit(les_components_raw, ",")))
add_predictor_raw <- opts[["add_predictor"]] %||% ""
add_predictors <- trimws(unlist(strsplit(add_predictor_raw, ",")))
want_logLA_pred <- any(tolower(add_predictors) == "logla")
phylo_newick <- opts[["phylogeny_newick"]] %||% ""  # not used here
phylo_corr   <- tolower(opts[["phylo_correlation"]] %||% "brownian")
add_interactions <- opts[["add_interaction"]] %||% ""
want_les_x_ssd <- grepl("(^|[, ])LES:logSSD([, ]|$)", add_interactions)

# pwSEM options
pw_perm       <- tolower(opts[["pw_permutations"]] %||% "false") %in% c("1","true","yes","y")
pw_nperms     <- suppressWarnings(as.integer(opts[["pw_nperms"]] %||% "5000")); if (is.na(pw_nperms)) pw_nperms <- 5000
pw_do_smooth  <- tolower(opts[["pw_do_smooth"]] %||% if (nonlinear_opt) "true" else "false") %in% c("1","true","yes","y")
latents_marg  <- opts[["marginalized_latents"]] %||% ""
latents_cond  <- opts[["conditioned_latents"]] %||% ""
psem_include_size_eq  <- tolower(opts[["psem_include_size_eq"]]  %||% "true") %in% c("1","true","yes","y")
## Parity with piecewise: option to drop direct logSSD -> y in the SEM (full-data only)
psem_drop_logSSD_y    <- tolower(opts[["psem_drop_logssd_y"]]    %||% "true") %in% c("1","true","yes","y")

# Bootstrap options (full-data coefficient stability; not used in CV)
do_bootstrap_pw       <- tolower(opts[["bootstrap"]] %||% "false") %in% c("1","true","yes","y")
n_boot_pw             <- suppressWarnings(as.integer(opts[["n_boot"]] %||% "200")); if (is.na(n_boot_pw)) n_boot_pw <- 200
boot_cluster_pw       <- tolower(opts[["bootstrap_cluster"]] %||% "true") %in% c("1","true","yes","y")

ensure_dir <- function(path) dir.create(path, recursive = TRUE, showWarnings = FALSE)
ensure_dir(out_dir)

fail <- function(msg) { cat(sprintf("[error] %s\n", msg)); quit(status = 1) }

if (!file.exists(in_csv)) fail(sprintf("Input CSV not found: '%s'", in_csv))
if (!have_pwsem) fail("pwSEM package is required. Run: Rscript scripts/install_pwsem.R --method=cran")
if (!have_mgcv)  fail("mgcv is required by pwSEM. Install it first: install.packages('mgcv')")

# Load data
df <- if (have_readr) readr::read_csv(in_csv, show_col_types = FALSE, progress = FALSE) else utils::read.csv(in_csv, check.names = FALSE)

# If requested, force-disable lme4 usage everywhere
if (force_lm) {
  have_lme4 <- FALSE
}

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

log_vars <- c("Leaf area (mm2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")
offsets <- sapply(log_vars, function(v) compute_offset(df[[v]]))

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

set.seed(seed_opt)

base_cols <- c(id_col, target_name, feature_cols, cluster_var)
if (nzchar(group_var) && (group_var %in% names(df))) base_cols <- unique(c(base_cols, group_var))
work <- df[, base_cols, drop = FALSE]
names(work)[names(work) == id_col] <- "id"
if (!(cluster_var %in% names(work))) work[[cluster_var]] <- NA

work$logLA <- log10(work[["Leaf area (mm2)"]] + offsets[["Leaf area (mm2)"]])
work$logH  <- log10(work[["Plant height (m)"]] + offsets[["Plant height (m)"]])
work$logSM <- log10(work[["Diaspore mass (mg)"]] + offsets[["Diaspore mass (mg)"]])
work$logSSD<- log10(work[["SSD used (mg/mm3)"]] + offsets[["SSD used (mg/mm3)"]])
work$LMA   <- as.numeric(work[["LMA (g/m2)"]])
work$Nmass <- as.numeric(work[["Nmass (mg/g)"]])
work$y     <- as.numeric(work[[target_name]])

groups <- make_folds(work$y, folds_opt, stratify_opt)

metrics <- data.frame(rep=integer(), fold=integer(), R2=double(), RMSE=double(), MAE=double(), stringsAsFactors = FALSE)
preds <- data.frame(stringsAsFactors = FALSE)

build_composites <- function(train, test) {
  # Dynamically build LES from requested components (e.g., negLMA,Nmass[,logLA])
  make_mat <- function(df) {
    cols <- list()
    for (nm in les_components) {
      key <- tolower(nm)
      if (key == "neglma") cols[["negLMA"]] <- -df$LMA else if (key == "nmass") cols[["Nmass"]] <- df$Nmass else if (key == "logla") cols[["logLA"]] <- df$logLA
    }
    as.data.frame(cols, check.names = FALSE)
  }
  Mtr_raw <- make_mat(train)
  Mte_raw <- make_mat(test)
  M_LES_tr <- scale(as.matrix(Mtr_raw), center = TRUE, scale = TRUE)
  p_les <- stats::prcomp(M_LES_tr, center = FALSE, scale. = FALSE)
  rot_les <- p_les$rotation[,1]
  if (rot_les["Nmass"] < 0) rot_les <- -rot_les
  scores_LES_tr <- as.numeric(M_LES_tr %*% rot_les)
  M_LES_te <- scale(as.matrix(Mte_raw), center = attr(M_LES_tr, "scaled:center"), scale = attr(M_LES_tr, "scaled:scale"))
  scores_LES_te <- as.numeric(M_LES_te %*% rot_les)

  M_SIZE_tr <- scale(cbind(logH = train$logH, logSM = train$logSM), center = TRUE, scale = TRUE)
  p_size <- stats::prcomp(M_SIZE_tr, center = FALSE, scale. = FALSE)
  rot_size <- p_size$rotation[,1]
  if (rot_size["logH"] < 0) rot_size <- -rot_size
  scores_SIZE_tr <- as.numeric(M_SIZE_tr %*% rot_size)
  M_SIZE_te <- scale(cbind(logH = test$logH, logSM = test$logSM), center = attr(M_SIZE_tr, "scaled:center"), scale = attr(M_SIZE_tr, "scaled:scale"))
  scores_SIZE_te <- as.numeric(M_SIZE_te %*% rot_size)

  list(LES_train = scores_LES_tr, LES_test = scores_LES_te, SIZE_train = scores_SIZE_tr, SIZE_test = scores_SIZE_te)
}

for (r in seq_len(repeats_opt)) {
  set.seed(seed_opt + r)
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

    # Optional winsorization and standardization on predictors
    if (winsorize_opt) {
      for (v in c("logLA","logH","logSM","logSSD","LMA","Nmass")) {
        wtr <- winsorize(tr[[v]], p = winsor_p_opt)
        tr[[v]] <- wtr$x
        te[[v]][te[[v]] < wtr$lo] <- wtr$lo
        te[[v]][te[[v]] > wtr$hi] <- wtr$hi
      }
    }
    if (standardize) {
      for (v in c("logLA","logH","logSM","logSSD","LMA","Nmass")) {
        zs <- zscore(tr[[v]])
        tr[[v]] <- zs$x
        te[[v]] <- (te[[v]] - zs$mean)/zs$sd
      }
    }

    comps <- build_composites(train = tr, test = te)
    tr$LES  <- comps$LES_train; te$LES  <- comps$LES_test
    tr$SIZE <- comps$SIZE_train; te$SIZE <- comps$SIZE_test

    # optional weights
    w <- NULL
    if (weights_mode != "none" && ("min_records_6traits" %in% names(df))) {
      wraw <- df$min_records_6traits[match(tr$id, df$wfo_accepted_name)]
      if (weights_mode == "min") w <- wraw
      if (weights_mode == "log1p_min") w <- log1p(wraw)
      if (!is.null(w)) w[!is.finite(w)] <- NA
    }

    # Fit component model (predictions); follow piecewise forms
    used_gam <- FALSE
    edf_s <- NA_real_
    aic_tr <- NA_real_
    model_form <- "linear_size"
    if (nonlinear_opt && have_mgcv && (target_letter %in% c("M","N","R"))) {
      # Nonlinear GAM forms
      if (target_letter %in% c("M","N")) {
        if (want_les_x_ssd) {
          f_gam <- mgcv::gam(y ~ LES + s(logH, k = 5) + logSM + logSSD + LES:logSSD, data = tr, method = "REML")
          model_form <- paste0(model_form, "+LES:logSSD")
        } else {
          f_gam <- mgcv::gam(y ~ LES + s(logH, k = 5) + logSM + logSSD, data = tr, method = "REML")
        }
      } else { # R
        if (want_les_x_ssd) {
          f_gam <- mgcv::gam(y ~ LES + s(logH, k = 5) + SIZE + logSSD + LES:logSSD, data = tr, method = "REML")
          model_form <- paste0(model_form, "+LES:logSSD")
        } else {
          f_gam <- mgcv::gam(y ~ LES + s(logH, k = 5) + SIZE + logSSD, data = tr, method = "REML")
        }
      }
      used_gam <- TRUE
      model_form <- "semi_nonlinear_slogH"
      gs <- try(summary(f_gam), silent = TRUE)
      if (!inherits(gs, "try-error") && length(gs$s.table) >= 1) edf_s <- suppressWarnings(as.numeric(gs$s.table[1, 1]))
      aic_tr <- tryCatch(AIC(f_gam), error = function(e) NA_real_)
      eta <- as.numeric(stats::predict(f_gam, newdata = te, type = "link"))
    } else if (deconstruct_size) {
      model_form <- "linear_deconstructed"
      if (have_lme4 && (cluster_var %in% names(tr)) && length(unique(na.omit(tr[[cluster_var]]))) > 1) {
        rhs <- "y ~ LES + logH + logSM + logSSD"
        if (want_logLA_pred) rhs <- paste(rhs, "+ logLA")
        if (want_les_x_ssd) rhs <- paste(rhs, "+ LES:logSSD")
        f <- stats::as.formula(sprintf("%s + (1|%s)", rhs, cluster_var))
        m <- try(lme4::lmer(f, data = tr, weights = w, REML = FALSE), silent = TRUE)
        if (inherits(m, "try-error")) {
          f2 <- stats::as.formula(rhs)
          m <- stats::lm(f2, data = tr, weights = w)
        }
        aic_tr <- tryCatch(AIC(m), error = function(e) NA_real_)
        eta <- as.numeric(stats::predict(m, newdata = te, allow.new.levels = TRUE))
      } else {
        rhs <- "y ~ LES + logH + logSM + logSSD"
        if (want_logLA_pred) rhs <- paste(rhs, "+ logLA")
        if (want_les_x_ssd) rhs <- paste(rhs, "+ LES:logSSD")
        m <- stats::lm(stats::as.formula(rhs), data = tr, weights = w)
        aic_tr <- tryCatch(AIC(m), error = function(e) NA_real_)
        eta <- as.numeric(stats::predict(m, newdata = te))
      }
    } else if (have_lme4 && (cluster_var %in% names(tr)) && length(unique(na.omit(tr[[cluster_var]]))) > 1) {
      rhs <- "y ~ LES + SIZE + logSSD"
      if (want_logLA_pred) rhs <- paste(rhs, "+ logLA")
      if (want_les_x_ssd) rhs <- paste(rhs, "+ LES:logSSD")
      f <- stats::as.formula(sprintf("%s + (1|%s)", rhs, cluster_var))
      m <- try(lme4::lmer(f, data = tr, weights = w, REML = FALSE), silent = TRUE)
      if (inherits(m, "try-error")) m <- stats::lm(stats::as.formula(rhs), data = tr, weights = w)
      aic_tr <- tryCatch(AIC(m), error = function(e) NA_real_)
      eta <- as.numeric(stats::predict(m, newdata = te, allow.new.levels = TRUE))
    } else {
      rhs <- "y ~ LES + SIZE + logSSD"
      if (want_logLA_pred) rhs <- paste(rhs, "+ logLA")
      if (want_les_x_ssd) rhs <- paste(rhs, "+ LES:logSSD")
      m <- stats::lm(stats::as.formula(rhs), data = tr, weights = w)
      aic_tr <- tryCatch(AIC(m), error = function(e) NA_real_)
      eta <- as.numeric(stats::predict(m, newdata = te))
    }

    # Optional mild nonlinearity on LES (legacy). Skip when GAM is used.
    if (nonlinear_opt && !used_gam) {
      res_tr <- tr$y - as.numeric(stats::predict(m, newdata = tr))
      adj <- try(stats::lm(res_tr ~ poly(LES, 2, raw = TRUE), data = tr), silent = TRUE)
      if (!inherits(adj, "try-error")) {
        res_adj <- predict(adj, newdata = data.frame(LES = te$LES))
        eta <- eta + as.numeric(res_adj)
      }
    }

    ytrue <- te$y
    yhat <- eta
    err <- ytrue - yhat
    R2 <- 1 - sum(err^2)/sum((ytrue - mean(ytrue))^2)
    RMSE <- sqrt(mean(err^2))
    MAE <- mean(abs(err))

    metrics <- rbind(metrics, data.frame(rep=r, fold=k, R2=R2, RMSE=RMSE, MAE=MAE, used_gam=used_gam, edf_s_logH=edf_s, AIC_train=aic_tr, model_form=model_form))
    preds <- rbind(preds, data.frame(target=target_name, rep=r, fold=k, id=te$id, y_true=ytrue, y_pred=yhat, method="pwsem", stringsAsFactors = FALSE))
  }
}

agg <- data.frame(
  R2_mean = mean(metrics$R2, na.rm=TRUE), R2_sd = stats::sd(metrics$R2, na.rm=TRUE),
  RMSE_mean = mean(metrics$RMSE, na.rm=TRUE), RMSE_sd = stats::sd(metrics$RMSE, na.rm=TRUE),
  MAE_mean = mean(metrics$MAE, na.rm=TRUE), MAE_sd = stats::sd(metrics$MAE, na.rm=TRUE)
)

base <- file.path(out_dir, paste0("sem_pwsem_", target_letter))
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
  group_var = if (nzchar(group_var)) group_var else NULL,
  transform = "identity",
  offsets = as.list(offsets),
  metrics = list(per_fold = metrics, aggregate = agg)
)
if (have_jsonlite) {
  json <- jsonlite::toJSON(metrics_out, pretty = TRUE, dataframe = "rows", na = "null")
  cat(json, file = metrics_json)
}

# Full-data pwSEM d-separation
tr <- work
comps <- build_composites(train = tr, test = tr)
tr$LES  <- comps$LES_train
tr$SIZE <- comps$SIZE_train

# Build sem.functions list (mgcv or gamm4 if random effects and available)
use_mixed <- have_gamm4 && (cluster_var %in% names(tr)) && length(unique(na.omit(tr[[cluster_var]]))) > 1

gam_or_gamm <- function(formula, data, weights = NULL) {
  if (use_mixed) {
    # gamm4 returns list with $gam and $mer
    # Try with weights; if not supported, fall back to no weights
    obj <- try(gamm4::gamm4(formula, random = stats::as.formula(sprintf("~(1|%s)", cluster_var)), data = data, family = gaussian(), weights = weights), silent = TRUE)
    if (inherits(obj, 'try-error')) obj <- gamm4::gamm4(formula, random = stats::as.formula(sprintf("~(1|%s)", cluster_var)), data = data, family = gaussian())
    return(obj)
  } else {
    if (!is.null(weights)) return(mgcv::gam(formula, data = data, family = gaussian(), weights = weights))
    return(mgcv::gam(formula, data = data, family = gaussian()))
  }
}

# Y equation mirrors CV form (with parity option to drop logSSD)
rhs_y <- if (deconstruct_size) "y ~ LES + logH + logSM" else "y ~ LES + SIZE"
add_logssd <- !psem_drop_logSSD_y
# For targets M and N, if user did not override the flag, include logSSD by default
if (target_letter %in% c("M","N") && is.null(opts[["psem_drop_logssd_y"]])) add_logssd <- TRUE
if (add_logssd) rhs_y <- paste(rhs_y, "+ logSSD")
if (want_logLA_pred) rhs_y <- paste(rhs_y, "+ logLA")
if (want_les_x_ssd)  rhs_y <- paste(rhs_y, "+ LES:logSSD")
if (nonlinear_opt) {
  # Add smooth on logH if available
  if (grepl("logH", rhs_y, fixed = TRUE)) rhs_y <- sub("logH", "s(logH, k=5)", rhs_y, fixed = TRUE)
}

# LES and SIZE equations
rhs_les  <- "LES ~ SIZE + logSSD"
rhs_size <- if (psem_include_size_eq) "SIZE ~ logSSD" else NULL

sem_list <- list()
# Exogenous variables need models (intercepts-only)
## Optional weights for full-data SEM
w_full <- NULL
if (weights_mode != "none" && ("min_records_6traits" %in% names(df))) {
  w_full_raw <- df$min_records_6traits[match(tr$id, df$wfo_accepted_name)]
  if (weights_mode == "min") w_full <- w_full_raw
  if (weights_mode == "log1p_min") w_full <- log1p(w_full_raw)
  if (!is.null(w_full)) w_full[!is.finite(w_full)] <- NA
}

sem_list[[length(sem_list)+1]] <- gam_or_gamm(stats::as.formula("logSSD ~ 1"), data = tr, weights = w_full)
if (!psem_include_size_eq) sem_list[[length(sem_list)+1]] <- gam_or_gamm(stats::as.formula("SIZE ~ 1"), data = tr, weights = w_full)
if (want_logLA_pred) sem_list[[length(sem_list)+1]] <- gam_or_gamm(stats::as.formula("logLA ~ 1"), data = tr, weights = w_full)

# Endogenous equations
sem_list[[length(sem_list)+1]] <- gam_or_gamm(stats::as.formula(rhs_les),  data = tr, weights = w_full)
if (!is.null(rhs_size)) sem_list[[length(sem_list)+1]] <- gam_or_gamm(stats::as.formula(rhs_size), data = tr, weights = w_full)
sem_list[[length(sem_list)+1]] <- gam_or_gamm(stats::as.formula(rhs_y),    data = tr, weights = w_full)

# Parse latents from CLI: expect syntax like X2~~X4;X3~~X5
parse_latents <- function(s) {
  s <- trimws(s)
  if (!nzchar(s)) return(NULL)
  parts <- unlist(strsplit(s, "[;,]", perl = TRUE))
  parts <- trimws(parts[nzchar(parts)])
  out <- list()
  for (p in parts) {
    if (grepl("~~", p, fixed = TRUE)) {
      vars <- trimws(unlist(strsplit(p, "~~", fixed = TRUE)))
      if (length(vars) == 2) out[[length(out)+1]] <- stats::as.formula(paste0(vars[1], "~~", vars[2]))
    }
  }
  if (!length(out)) return(NULL)
  out
}

lat_marg <- parse_latents(latents_marg)
lat_cond <- parse_latents(latents_cond)

pw <- NULL
fit_C <- NA_real_; fit_p <- NA_real_; fit_df <- NA_real_
basis_n <- NA_integer_
prob_vec <- NULL
try({
  pw <- pwSEM::pwSEM(
    sem.functions       = sem_list,
    marginalized.latents = lat_marg,
    conditioned.latents  = lat_cond,
    data = tr,
    use.permutations = pw_perm,
    n.perms = pw_nperms,
    do.smooth = pw_do_smooth,
    all.grouping.vars = if (use_mixed) c(cluster_var) else NULL
  )
  if (is.list(pw)) {
    if (!is.null(pw$C.statistic))      fit_C <- suppressWarnings(as.numeric(pw$C.statistic))
    if (!is.null(pw$prob.C.statistic)) fit_p <- suppressWarnings(as.numeric(pw$prob.C.statistic))
    if (!is.null(pw$dsep.probs)) {
      prob_vec <- pw$dsep.probs
      fit_df <- 2 * length(prob_vec)
    }
    if (!is.null(pw$basis.set)) basis_n <- suppressWarnings(tryCatch(nrow(as.data.frame(pw$basis.set)), error = function(e) NA_integer_))
  }
}, silent = TRUE)

# Write d-sep outputs
fit_df_df <- data.frame(C = fit_C, df = fit_df, P.Value = fit_p)
fit_path <- paste0(base, "_dsep_fit.csv")
if (have_readr) readr::write_csv(fit_df_df, fit_path) else utils::write.csv(fit_df_df, fit_path, row.names = FALSE)

if (!is.null(prob_vec)) {
  probs_path <- paste0(base, "_dsep_probs.csv")
  pv_df <- data.frame(p = as.numeric(prob_vec))
  if (have_readr) readr::write_csv(pv_df, probs_path) else utils::write.csv(pv_df, probs_path, row.names = FALSE)
}
if (!is.null(pw) && !is.null(pw$basis.set)) {
  bs <- try(as.data.frame(pw$basis.set), silent = TRUE)
  if (!inherits(bs, 'try-error')) {
    bs_path <- paste0(base, "_basis_set.csv")
    if (have_readr) readr::write_csv(bs, bs_path) else utils::write.csv(bs, bs_path, row.names = FALSE)
  }
}

# Alternative full-model AIC reporting via pwSEM
# - pw$AIC field (if present)
# - pwSEM::get.AIC(sem.model, MAG, data) which returns LL, K, AIC, AICc
ga_path <- paste0(base, "_full_model_getAIC.csv")
rows_ga <- list()
if (!is.null(pw) && is.list(pw)) {
  # Row from pw field AIC, if available
  aic_field <- suppressWarnings(as.numeric(pw$AIC))
  if (is.finite(aic_field)) {
    rows_ga[[length(rows_ga)+1]] <- data.frame(source = "pwSEM_field", LL = NA_real_, K = NA_real_, AIC = aic_field, AICc = NA_real_, stringsAsFactors = FALSE)
  }
  # Row from get.AIC, if available
  ga <- try(pwSEM::get.AIC(sem.model = pw$sem.functions, MAG = pw$causal.graph, data = tr), silent = TRUE)
  if (!inherits(ga, 'try-error')) {
    # Coerce to data.frame with expected columns
    gadf <- try(as.data.frame(ga), silent = TRUE)
    if (!inherits(gadf, 'try-error')) {
      # Normalize column names
      cn <- tolower(names(gadf))
      getv <- function(keys) { idx <- which(cn %in% keys)[1]; if (is.na(idx)) NA_real_ else suppressWarnings(as.numeric(gadf[[idx]][1])) }
      LL   <- getv(c('ll','loglik','log-likelihood','loglikelihood'))
      K    <- getv(c('k','params','npar','n.params'))
      AICv <- getv(c('aic'))
      AICc <- getv(c('aicc','aic.c','aicc.'))
      rows_ga[[length(rows_ga)+1]] <- data.frame(source = "get.AIC", LL = LL, K = K, AIC = AICv, AICc = AICc, stringsAsFactors = FALSE)
    }
  }
}
if (length(rows_ga)) {
  out_ga <- do.call(rbind, rows_ga)
  if (have_readr) readr::write_csv(out_ga, ga_path) else utils::write.csv(out_ga, ga_path, row.names = FALSE)
}

# Multigroup d-separation analysis (split by group, run pwSEM, aggregate C/df)
if (nzchar(group_var) && (group_var %in% names(tr))) {
  try({
    gv <- tr[[group_var]]
    levs <- unique(gv[!is.na(gv)])
    rows <- list()
    build_sem_list_for <- function(df_sub) {
      # Recompute composites for subset to avoid leakage
      comps_g <- build_composites(train = df_sub, test = df_sub)
      df_sub$LES  <- comps_g$LES_train
      df_sub$SIZE <- comps_g$SIZE_train
      # Decide mixed vs fixed for this subset
      use_mixed_g <- have_gamm4 && (cluster_var %in% names(df_sub)) && length(unique(na.omit(df_sub[[cluster_var]]))) > 1
      gam_or_gamm_g <- function(formula, data, weights = NULL) {
        if (use_mixed_g) {
          obj <- try(gamm4::gamm4(formula, random = stats::as.formula(sprintf("~(1|%s)", cluster_var)), data = data, family = gaussian(), weights = weights), silent = TRUE)
          if (inherits(obj, 'try-error')) obj <- gamm4::gamm4(formula, random = stats::as.formula(sprintf("~(1|%s)", cluster_var)), data = data, family = gaussian())
          return(obj)
        } else {
          if (!is.null(weights)) return(mgcv::gam(formula, data = data, family = gaussian(), weights = weights))
          return(mgcv::gam(formula, data = data, family = gaussian()))
        }
      }
      # weights
      w_sub <- NULL
      if (weights_mode != "none" && ("min_records_6traits" %in% names(df))) {
        w_full_raw <- df$min_records_6traits[match(df_sub$id, df$wfo_accepted_name)]
        if (weights_mode == "min") w_sub <- w_full_raw
        if (weights_mode == "log1p_min") w_sub <- log1p(w_full_raw)
        if (!is.null(w_sub)) w_sub[!is.finite(w_sub)] <- NA
      }
      # formulas
      rhs_y_g <- if (deconstruct_size) "y ~ LES + logH + logSM" else "y ~ LES + SIZE"
      if (add_logssd) rhs_y_g <- paste(rhs_y_g, "+ logSSD")
      if (want_logLA_pred) rhs_y_g <- paste(rhs_y_g, "+ logLA")
      if (want_les_x_ssd)  rhs_y_g <- paste(rhs_y_g, "+ LES:logSSD")
      if (nonlinear_opt) if (grepl("logH", rhs_y_g, fixed = TRUE)) rhs_y_g <- sub("logH", "s(logH, k=5)", rhs_y_g, fixed = TRUE)
      rhs_les_g  <- "LES ~ SIZE + logSSD"
      rhs_size_g <- if (psem_include_size_eq) "SIZE ~ logSSD" else NULL
      # build list
      L <- list()
      L[[length(L)+1]] <- gam_or_gamm_g(stats::as.formula("logSSD ~ 1"), data = df_sub, weights = w_sub)
      if (!psem_include_size_eq) L[[length(L)+1]] <- gam_or_gamm_g(stats::as.formula("SIZE ~ 1"), data = df_sub, weights = w_sub)
      if (want_logLA_pred) L[[length(L)+1]] <- gam_or_gamm_g(stats::as.formula("logLA ~ 1"), data = df_sub, weights = w_sub)
      L[[length(L)+1]] <- gam_or_gamm_g(stats::as.formula(rhs_les_g),  data = df_sub, weights = w_sub)
      if (!is.null(rhs_size_g)) L[[length(L)+1]] <- gam_or_gamm_g(stats::as.formula(rhs_size_g), data = df_sub, weights = w_sub)
      L[[length(L)+1]] <- gam_or_gamm_g(stats::as.formula(rhs_y_g),    data = df_sub, weights = w_sub)
      attr(L, "use_mixed_g") <- use_mixed_g
      L
    }
    for (lv in levs) {
      sub <- tr[which(gv == lv), , drop = FALSE]
      if (nrow(sub) < 10) next
      Lg <- build_sem_list_for(sub)
      use_mixed_g <- isTRUE(attr(Lg, "use_mixed_g"))
      outg <- try(pwSEM::pwSEM(sem.functions = Lg, marginalized.latents = lat_marg, conditioned.latents = lat_cond, data = sub, use.permutations = pw_perm, n.perms = pw_nperms, do.smooth = pw_do_smooth, all.grouping.vars = if (use_mixed_g) c(cluster_var) else NULL), silent = TRUE)
      if (inherits(outg, 'try-error') || !is.list(outg)) next
      Cg <- suppressWarnings(as.numeric(outg$C.statistic))
      df_g <- if (!is.null(outg$dsep.probs)) 2 * length(outg$dsep.probs) else NA_real_
      pg <- if (is.finite(Cg) && is.finite(df_g) && df_g > 0) stats::pchisq(Cg, df = df_g, lower.tail = FALSE) else NA_real_
      rows[[length(rows)+1]] <- data.frame(group = as.character(lv), n = nrow(sub), fisher_C = Cg, df = df_g, pvalue = pg, stringsAsFactors = FALSE)
    }
    if (length(rows)) {
      tab <- do.call(rbind, rows)
      total_C <- sum(tab$fisher_C, na.rm = TRUE)
      total_df<- sum(tab$df,       na.rm = TRUE)
      p_overall <- if (is.finite(total_C) && is.finite(total_df) && total_df > 0) stats::pchisq(total_C, df = total_df, lower.tail = FALSE) else NA_real_
      overall <- data.frame(group = "Overall", n = sum(tab$n), fisher_C = total_C, df = total_df, pvalue = p_overall, stringsAsFactors = FALSE)
      out_mg <- rbind(tab, overall)
      mg_path <- paste0(base, "_multigroup_dsep.csv")
      if (have_readr) readr::write_csv(out_mg, mg_path) else utils::write.csv(out_mg, mg_path, row.names = FALSE)
    }
  }, silent = TRUE)
}

# Phylogenetic GLS sensitivity (full-data; no CV)
if (nzchar(phylo_newick) && file.exists(phylo_newick) && have_ape && have_nlme) {
  tr2 <- tr
  rownames(tr2) <- gsub(" ", "_", as.character(tr2$id), fixed = TRUE)
  phy <- try(ape::read.tree(phylo_newick), silent = TRUE)
  if (!inherits(phy, "try-error")) {
    common <- intersect(phy$tip.label, rownames(tr2))
    if (length(common) >= 10) {
      phy2 <- ape::keep.tip(phy, common)
      tr3  <- tr2[common, , drop = FALSE]
      corStruct <- NULL
      if (phylo_corr %in% c("brownian","bm")) {
        corStruct <- ape::corBrownian(phy = phy2)
      } else if (phylo_corr %in% c("pagel","lambda")) {
        cs <- try(ape::corPagel(value = 0.5, phy = phy2, fixed = FALSE), silent = TRUE)
        if (!inherits(cs, "try-error")) corStruct <- cs
      }
      if (!is.null(corStruct)) {
        add_logssd_phy <- add_logssd
        rhs_fixed <- if (deconstruct_size) "y ~ LES + logH + logSM" else "y ~ LES + SIZE"
        if (add_logssd_phy) rhs_fixed <- paste(rhs_fixed, "+ logSSD")
        if (want_logLA_pred) rhs_fixed <- paste(rhs_fixed, "+ logLA")
        if (want_les_x_ssd) rhs_fixed <- paste(rhs_fixed, "+ LES:logSSD")
        rhs_lm <- stats::as.formula(rhs_fixed)
        m1g <- try(nlme::gls(rhs_lm, data = tr3, method = "ML", correlation = corStruct, na.action = stats::na.omit, control = nlme::glsControl(msMaxIter = 200)), silent = TRUE)
        m2g <- try(nlme::gls(LES ~ SIZE + logSSD, data = tr3, method = "ML", correlation = corStruct, na.action = stats::na.omit, control = nlme::glsControl(msMaxIter = 200)), silent = TRUE)
        m3g <- NULL
        if (psem_include_size_eq) m3g <- try(nlme::gls(SIZE ~ logSSD, data = tr3, method = "ML", correlation = corStruct, na.action = stats::na.omit, control = nlme::glsControl(msMaxIter = 200)), silent = TRUE)
        aics <- c(tryCatch(stats::AIC(m1g), error = function(e) NA_real_),
                  tryCatch(stats::AIC(m2g), error = function(e) NA_real_),
                  if (!is.null(m3g)) tryCatch(stats::AIC(m3g), error = function(e) NA_real_) else NULL)
        bics <- c(tryCatch(stats::BIC(m1g), error = function(e) NA_real_),
                  tryCatch(stats::BIC(m2g), error = function(e) NA_real_),
                  if (!is.null(m3g)) tryCatch(stats::BIC(m3g), error = function(e) NA_real_) else NULL)
        subm <- c("y|parents","LES|parents", if (!is.null(m3g)) "SIZE|parents" else NULL)
        fm_phy <- data.frame(submodel = subm, AIC = aics, BIC = bics, stringsAsFactors = FALSE)
        fm_phy$AIC_sum <- sum(fm_phy$AIC, na.rm = TRUE)
        fm_phy$BIC_sum <- sum(fm_phy$BIC, na.rm = TRUE)
        icp <- paste0(base, "_full_model_ic_phylo.csv")
        if (have_readr) readr::write_csv(fm_phy, icp) else utils::write.csv(fm_phy, icp, row.names = FALSE)
        co <- try(summary(m1g), silent = TRUE)
        if (!inherits(co, "try-error")) {
          coefs <- as.data.frame(co$tTable)
          coefs$term <- rownames(coefs)
          coefs_path <- paste0(base, "_phylo_coefs_y.csv")
          if (have_readr) readr::write_csv(coefs, coefs_path) else utils::write.csv(coefs, coefs_path, row.names = FALSE)
        }
      }
    }
  }
}

# Optional: nonparametric bootstrap for coefficient stability (OLS; full data)
if (do_bootstrap_pw) {
  # Ensure composites exist in 'tr' from earlier block
  if (!("LES" %in% names(tr) && "SIZE" %in% names(tr))) {
    comps <- build_composites(train = tr, test = tr)
    tr$LES  <- comps$LES_train
    tr$SIZE <- comps$SIZE_train
  }
  # Determine terms in the selected y-equation (on linear scale for OLS)
  rhs_lm_txt <- if (deconstruct_size) "y ~ LES + logH + logSM" else "y ~ LES + SIZE"
  if (add_logssd) rhs_lm_txt <- paste(rhs_lm_txt, "+ logSSD")
  if (want_logLA_pred) rhs_lm_txt <- paste(rhs_lm_txt, "+ logLA")
  if (want_les_x_ssd)  rhs_lm_txt <- paste(rhs_lm_txt, "+ LES:logSSD")
  rhs_lm <- stats::as.formula(rhs_lm_txt)
  lm_full <- try(stats::lm(rhs_lm, data = tr), silent = TRUE)
  coef_names <- NULL
  if (!inherits(lm_full, "try-error")) {
    coef_names <- setdiff(names(coef(lm_full)), "(Intercept)")
  } else {
    rhs_txt <- gsub("^y ~ ", "", deparse(rhs_lm))
    coef_names <- trimws(unlist(strsplit(rhs_txt, "+", fixed = TRUE)))
  }
  coef_names <- unique(coef_names)
  # Helper: cluster-aware resample
  boot_once <- function() {
    df_b <- NULL
    if (boot_cluster_pw && (cluster_var %in% names(tr))) {
      cl <- as.character(tr[[cluster_var]])
      cl <- cl[!is.na(cl) & nzchar(cl)]
      uniq <- unique(cl)
      if (length(uniq) >= 2) {
        take <- sample(uniq, size = length(uniq), replace = TRUE)
        idx <- which(as.character(tr[[cluster_var]]) %in% take)
        df_b <- tr[idx, , drop = FALSE]
      }
    }
    if (is.null(df_b)) {
      idx <- sample(seq_len(nrow(tr)), size = nrow(tr), replace = TRUE)
      df_b <- tr[idx, , drop = FALSE]
    }
    df_b
  }
  # Collect bootstrap coefficients
  B <- as.integer(n_boot_pw)
  mat <- matrix(NA_real_, nrow = B, ncol = length(coef_names))
  colnames(mat) <- coef_names
  kept <- 0L
  for (b in seq_len(B)) {
    df_b <- boot_once()
    fit_b <- try(stats::lm(rhs_lm, data = df_b), silent = TRUE)
    if (!inherits(fit_b, "try-error")) {
      cb <- coef(fit_b)
      for (nm in coef_names) {
        if (nm %in% names(cb)) mat[b, nm] <- as.numeric(cb[[nm]])
      }
      kept <- kept + 1L
    }
  }
  # Summarize percentiles
  summ_rows <- list()
  full_est <- tryCatch(as.numeric(coef(lm_full)[coef_names]), error = function(e) rep(NA_real_, length(coef_names)))
  names(full_est) <- coef_names
  for (nm in coef_names) {
    v <- mat[, nm]
    v <- v[is.finite(v)]
    if (length(v) >= max(10, floor(0.2 * B))) {
      qs <- stats::quantile(v, probs = c(0.025, 0.975), na.rm = TRUE, names = FALSE, type = 7)
      summ_rows[[length(summ_rows)+1]] <- data.frame(
        term = nm,
        est_full = if (!is.na(full_est[[nm]])) full_est[[nm]] else NA_real_,
        p2.5 = qs[1],
        p97.5 = qs[2],
        stringsAsFactors = FALSE
      )
    }
  }
  boot_path <- paste0(base, "_bootstrap_coefs.csv")
  out_boot <- if (length(summ_rows)) do.call(rbind, summ_rows) else data.frame(term=character(), est_full=double(), p2.5=double(), p97.5=double(), stringsAsFactors = FALSE)
  if (have_readr) readr::write_csv(out_boot, boot_path) else utils::write.csv(out_boot, boot_path, row.names = FALSE)
}

# Equality test for logSSD slope across groups (pooled vs by-group)
if (nzchar(group_var) && (group_var %in% names(tr))) {
  try({
    df_eq <- tr[!is.na(tr[[group_var]]), , drop = FALSE]
    if (nrow(df_eq) > 20) {
      df_eq$.grp <- factor(df_eq[[group_var]])
      # Pooled model allows group effects and interactions for LES/SIZE, but common logSSD slope
      mdl_pooled <- stats::lm(y ~ LES + SIZE + logSSD + .grp + LES:.grp + SIZE:.grp, data = df_eq)
      AIC_pooled <- tryCatch(stats::AIC(mdl_pooled), error = function(e) NA_real_)
      levs2 <- levels(df_eq$.grp)
      AIC_groups <- 0
      pvals_groups <- data.frame(group = character(0), p_logSSD = double(0), stringsAsFactors = FALSE)
      for (lv in levs2) {
        sub <- df_eq[df_eq$.grp == lv, , drop = FALSE]
        if (nrow(sub) < 10) next
        mg <- stats::lm(y ~ LES + SIZE + logSSD, data = sub)
        AIC_groups <- AIC_groups + tryCatch(stats::AIC(mg), error = function(e) 0)
        co <- summary(mg)$coefficients
        pss <- if ("logSSD" %in% rownames(co)) co["logSSD", 4] else NA_real_
        pvals_groups <- rbind(pvals_groups, data.frame(group = lv, p_logSSD = pss, stringsAsFactors = FALSE))
      }
      use_groups <- is.finite(AIC_groups) && is.finite(AIC_pooled) && (AIC_groups + 2) < AIC_pooled
      out_eq <- NULL
      if (use_groups && nrow(pvals_groups) > 0) {
        pvec <- pvals_groups$p_logSSD
        k <- sum(is.finite(pvec))
        C <- if (k > 0) -2 * sum(log(pvec[is.finite(pvec)])) else NA_real_
        dfc <- 2 * k
        pover <- if (is.finite(C) && dfc > 0) stats::pchisq(C, df = dfc, lower.tail = FALSE) else NA_real_
        out_eq <- data.frame(model = "by_group", AIC_pooled = AIC_pooled, AIC_by_group = AIC_groups, Fisher_C = C, df = dfc, p_overall = pover, stringsAsFactors = FALSE)
        eq_path <- paste0(base, "_claim_logSSD_eqtest.csv")
        if (have_readr) readr::write_csv(pvals_groups, gsub("_eqtest.csv$", "_pergroup_pvals.csv", eq_path)) else utils::write.csv(pvals_groups, gsub("_eqtest.csv$", "_pergroup_pvals.csv", eq_path), row.names = FALSE)
      } else {
        co <- summary(mdl_pooled)$coefficients
        p_pool <- if ("logSSD" %in% rownames(co)) co["logSSD", 4] else NA_real_
        k <- if (is.finite(p_pool)) 1L else 0L
        C <- if (k == 1L) -2 * log(p_pool) else NA_real_
        dfc <- 2 * k
        pover <- if (is.finite(C) && dfc > 0) stats::pchisq(C, df = dfc, lower.tail = FALSE) else NA_real_
        out_eq <- data.frame(model = "pooled", AIC_pooled = AIC_pooled, AIC_by_group = AIC_groups, Fisher_C = C, df = dfc, p_overall = pover, stringsAsFactors = FALSE)
        eq_path <- paste0(base, "_claim_logSSD_eqtest.csv")
      }
      eq_path <- paste0(base, "_claim_logSSD_eqtest.csv")
      if (!is.null(out_eq)) {
        if (have_readr) readr::write_csv(out_eq, eq_path) else utils::write.csv(out_eq, eq_path, row.names = FALSE)
      }
    }
  }, silent = TRUE)
}

cat(sprintf("Target %s: n=%d, R2=%.3f±%.3f, RMSE=%.3f±%.3f, MAE=%.3f±%.3f\n",
            target_letter, nrow(work),
            agg$R2_mean, agg$R2_sd, agg$RMSE_mean, agg$RMSE_sd, agg$MAE_mean, agg$MAE_sd))
cat(sprintf("  Wrote: %s_{preds.csv, metrics.json[, dsep_fit.csv, dsep_probs.csv, basis_set.csv, full_model_getAIC.csv, multigroup_dsep.csv, full_model_ic_phylo.csv, phylo_coefs_y.csv, bootstrap_coefs.csv]}\n", base))

invisible(NULL)

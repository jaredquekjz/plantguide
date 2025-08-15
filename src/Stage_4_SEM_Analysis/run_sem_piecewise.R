#!/usr/bin/env Rscript

# Stage 4 — SEM (piecewise) runner with CV predictions
# - Builds LES and SIZE composite proxies via training-only PCA.
# - Fits component model for target: y ~ LES + SIZE + logSSD with optional random intercept (Family).
# - Repeated K-fold CV with no leakage in transforms. Optional winsorization and standardization.
# - If piecewiseSEM and lme4 are available, fits a psem on full data for d-sep (Fisher's C).

suppressWarnings({
  # Allow injecting extra library paths via environment before loading packages
  extra_libs <- Sys.getenv("R_EXTRA_LIBS")
  if (nzchar(extra_libs)) {
    paths <- unlist(strsplit(extra_libs, "[,:;]", perl = TRUE))
    paths <- paths[nzchar(paths)]
    if (length(paths)) .libPaths(c(paths, .libPaths()))
  }
})

suppressWarnings({
  suppressMessages({
    have_readr       <- requireNamespace("readr",       quietly = TRUE)
    have_dplyr       <- requireNamespace("dplyr",       quietly = TRUE)
    have_tibble      <- requireNamespace("tibble",      quietly = TRUE)
    have_jsonlite    <- requireNamespace("jsonlite",    quietly = TRUE)
    have_lme4        <- requireNamespace("lme4",        quietly = TRUE)
    have_piecewise   <- requireNamespace("piecewiseSEM", quietly = TRUE)
    have_mgcv        <- requireNamespace("mgcv",        quietly = TRUE)
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

# Inputs / flags
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
group_var     <- opts[["group_var"]] %||% ""      # optional: enable multigroup d-sep if provided
nonlinear_opt <- tolower(opts[["nonlinear"]] %||% "false") %in% c("1","true","yes","y")
deconstruct_size <- tolower(opts[["deconstruct_size"]] %||% "false") %in% c("1","true","yes","y")
out_dir       <- opts[["out_dir"]]  %||% "artifacts/stage4_sem_piecewise"
# Run 7 — refined LES and added predictors
les_components_raw <- opts[["les_components"]] %||% "negLMA,Nmass,logLA"
les_components <- trimws(unlist(strsplit(les_components_raw, ",")))
add_predictor_raw <- opts[["add_predictor"]] %||% ""
add_predictors <- trimws(unlist(strsplit(add_predictor_raw, ",")))
want_logLA_pred <- any(tolower(add_predictors) == "logla")
# Phylogeny options (full-data GLS sensitivity)
phylo_newick <- opts[["phylogeny_newick"]] %||% ""
phylo_corr   <- tolower(opts[["phylo_correlation"]] %||% "brownian")  # brownian|pagel
# Interaction terms (comma-separated), e.g., "LES:logSSD"; supports LES:logSSD specifically for Run 5
add_interactions <- opts[["add_interaction"]] %||% ""
want_les_x_ssd <- grepl("(^|[, ])LES:logSSD([, ]|$)", add_interactions)
# psem configuration (affects full-data d-sep only; not CV predictions)
psem_drop_logSSD_y    <- tolower(opts[["psem_drop_logssd_y"]]    %||% "true") %in% c("1","true","yes","y")
psem_include_size_eq  <- tolower(opts[["psem_include_size_eq"]]  %||% "true") %in% c("1","true","yes","y")
group_ssd_to_y_for    <- opts[["group_ssd_to_y_for"]] %||% ""  # comma-separated group labels to force logSSD -> y in multigroup d-sep

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

# NOTE: Phylogenetic GLS sensitivity block moved below after data prep so 'work' exists.
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

    # Fit component model
    # Nonlinear option: for targets M/N/R and mgcv available, fit GAM with s(logH) instead of SIZE
    used_gam <- FALSE
    edf_s <- NA_real_
    aic_tr <- NA_real_
    model_form <- "linear_size"
    if (nonlinear_opt && have_mgcv && (target_letter %in% c("M","N","R"))) {
      # Build GAM formula: y ~ LES + s(logH) + logSM + logSSD [+ LES:logSSD]
      # Deconstruct SIZE: include logSM linearly; keep LES and logSSD
      if (want_les_x_ssd) {
        f_gam <- mgcv::gam(y ~ LES + s(logH, k = 5) + logSM + logSSD + LES:logSSD, data = tr, method = "REML")
        model_form <- paste0(model_form, "+LES:logSSD")
      } else {
        f_gam <- mgcv::gam(y ~ LES + s(logH, k = 5) + logSM + logSSD, data = tr, method = "REML")
      }
      used_gam <- TRUE
      model_form <- "semi_nonlinear_slogH"
      # edf of logH smooth
      gs <- try(summary(f_gam), silent = TRUE)
      if (!inherits(gs, "try-error") && length(gs$s.table) >= 1) {
        # s.table has columns: edf, Ref.df, F, p-value; take first row edf
        edf_s <- suppressWarnings(as.numeric(gs$s.table[1, 1]))
      }
      aic_tr <- tryCatch(AIC(f_gam), error = function(e) NA_real_)
      eta <- as.numeric(stats::predict(f_gam, newdata = te, type = "link"))
    } else if (deconstruct_size) {
      # Linear deconstructed: y ~ LES + logH + logSM + logSSD [+ LES:logSSD]
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
      # Mixed model with random intercept: y ~ LES + SIZE + logSSD [+ LES:logSSD]
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
    preds <- rbind(preds, data.frame(target=target_name, rep=r, fold=k, id=te$id, y_true=ytrue, y_pred=yhat, method="piecewise", stringsAsFactors = FALSE))
  }
}

agg <- data.frame(
  R2_mean = mean(metrics$R2, na.rm=TRUE), R2_sd = stats::sd(metrics$R2, na.rm=TRUE),
  RMSE_mean = mean(metrics$RMSE, na.rm=TRUE), RMSE_sd = stats::sd(metrics$RMSE, na.rm=TRUE),
  MAE_mean = mean(metrics$MAE, na.rm=TRUE), MAE_sd = stats::sd(metrics$MAE, na.rm=TRUE)
)

base <- file.path(out_dir, paste0("sem_piecewise_", target_letter))
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

# Optional: phylogenetic GLS sensitivity (full-data; no CV)
if (nzchar(phylo_newick) && file.exists(phylo_newick) && have_ape && have_nlme) {
  tr <- work
  # Prepare composites on full data
  comps <- build_composites(train = tr, test = tr)
  tr$LES  <- comps$LES_train
  tr$SIZE <- comps$SIZE_train
  # Keep only rows with species id and set rownames to id for matching tips
  tr <- tr[!is.na(tr$id) & nzchar(as.character(tr$id)), , drop = FALSE]
  # Match Newick tip labels that commonly use underscores instead of spaces
  rownames(tr) <- gsub(" ", "_", as.character(tr$id), fixed = TRUE)
  phy <- try(ape::read.tree(phylo_newick), silent = TRUE)
  if (!inherits(phy, "try-error")) {
    common <- intersect(phy$tip.label, rownames(tr))
    if (length(common) >= 10) {
      phy2 <- ape::keep.tip(phy, common)
      tr2  <- tr[common, , drop = FALSE]
      # Choose correlation structure
      corStruct <- NULL
      if (phylo_corr %in% c("brownian","bm")) {
        corStruct <- ape::corBrownian(phy = phy2)
      } else if (phylo_corr %in% c("pagel","lambda")) {
        cs <- try(ape::corPagel(value = 0.5, phy = phy2, fixed = FALSE), silent = TRUE)
        if (!inherits(cs, "try-error")) corStruct <- cs
      }
      if (!is.null(corStruct)) {
        add_logssd <- !psem_drop_logSSD_y
        if (target_letter %in% c("M","N") && is.null(opts[["psem_drop_logssd_y"]])) add_logssd <- TRUE
        rhs_fixed <- if (deconstruct_size) "y ~ LES + logH + logSM" else "y ~ LES + SIZE"
        if (add_logssd) rhs_fixed <- paste(rhs_fixed, "+ logSSD")
        if (want_logLA_pred) rhs_fixed <- paste(rhs_fixed, "+ logLA")
        if (!deconstruct_size && target_letter == "M") rhs_fixed <- paste(rhs_fixed, "+ SIZE:logSSD")
        if (want_les_x_ssd) rhs_fixed <- paste(rhs_fixed, "+ LES:logSSD")
        rhs_lm <- stats::as.formula(rhs_fixed)
        # Fit GLS models (ML)
        m1g <- try(nlme::gls(rhs_lm, data = tr2, method = "ML", correlation = corStruct, na.action = stats::na.omit, control = nlme::glsControl(msMaxIter = 200)), silent = TRUE)
        m2g <- try(nlme::gls(LES ~ SIZE + logSSD, data = tr2, method = "ML", correlation = corStruct, na.action = stats::na.omit, control = nlme::glsControl(msMaxIter = 200)), silent = TRUE)
        m3g <- NULL
        if (psem_include_size_eq) m3g <- try(nlme::gls(SIZE ~ logSSD, data = tr2, method = "ML", correlation = corStruct, na.action = stats::na.omit, control = nlme::glsControl(msMaxIter = 200)), silent = TRUE)
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

# Optional: psem on full data + full-model IC (Douma & Shipley 2020)
if (have_piecewise && have_lme4) {
  tr <- work
  # Prepare composites on full data (for structural paths and d-sep)
  comps <- build_composites(train = tr, test = tr)
  tr$LES  <- comps$LES_train
  tr$SIZE <- comps$SIZE_train

  # Use the safe surrogate response 'y' to avoid hyphenated names in formulas
  # Configure direct SSD -> y by target and optional interaction for Moisture (M)
  # If psem_drop_logSSD_y is TRUE, we remove logSSD from y-equation; otherwise include it
  add_logssd <- !psem_drop_logSSD_y
  # For targets M and N, keep direct SSD -> y regardless of default flag if user didn't override explicitly
  if (target_letter %in% c("M","N") && is.null(opts[["psem_drop_logssd_y"]])) add_logssd <- TRUE
  # Build fixed-effects part for y-equation
  # Honor deconstructed SIZE choice for full-data PSEM so coefficients align with CV forms
  if (deconstruct_size) {
    rhs_fixed <- "y ~ LES + logH + logSM"
  } else {
    rhs_fixed <- "y ~ LES + SIZE"
  }
  if (want_logLA_pred) rhs_fixed <- paste(rhs_fixed, "+ logLA")
  if (add_logssd)      rhs_fixed <- paste(rhs_fixed, "+ logSSD")
  # Optional interactions
  # Do not auto-include SIZE:logSSD for Moisture; keep only explicit LES:logSSD when requested
  if (want_les_x_ssd) rhs_fixed <- paste(rhs_fixed, "+ LES:logSSD")
  # Final formulas
  rhs_lm  <- stats::as.formula(rhs_fixed)
  rhs_lme <- stats::as.formula(sprintf("%s + (1|%s)", rhs_fixed, cluster_var))

  m1 <- try(lme4::lmer(rhs_lme, data = tr), silent = TRUE)
  if (inherits(m1, "try-error")) m1 <- stats::lm(rhs_lm, data = tr)

  m2 <- try(lme4::lmer(stats::as.formula(sprintf("LES ~ SIZE + logSSD + (1|%s)", cluster_var)), data = tr), silent = TRUE)
  if (inherits(m2, "try-error")) m2 <- stats::lm(LES ~ SIZE + logSSD, data = tr)

  if (psem_include_size_eq) {
    m3 <- try(lme4::lmer(stats::as.formula(sprintf("SIZE ~ logSSD + (1|%s)", cluster_var)), data = tr), silent = TRUE)
    if (inherits(m3, "try-error")) m3 <- stats::lm(SIZE ~ logSSD, data = tr)
    P <- try(piecewiseSEM::psem(m1, m2, m3), silent = TRUE)
  } else {
    P <- try(piecewiseSEM::psem(m1, m2), silent = TRUE)
  }
  if (!inherits(P, "try-error")) {
    summ <- try(summary(P), silent = TRUE)
    if (!inherits(summ, "try-error")) {
      dsep <- try(piecewiseSEM::coefs(P), silent = TRUE)
      if (!inherits(dsep, "try-error")) {
        dsep_path <- paste0(base, "_piecewise_coefs.csv")
        if (have_readr) readr::write_csv(dsep, dsep_path) else utils::write.csv(dsep, dsep_path, row.names = FALSE)
      }
      fitinfo <- try(piecewiseSEM::fisherC(P), silent = TRUE)
      if (!inherits(fitinfo, "try-error")) {
        fit_df <- as.data.frame(fitinfo)
        fit_path <- paste0(base, "_dsep_fit.csv")
        if (have_readr) readr::write_csv(fit_df, fit_path) else utils::write.csv(fit_df, fit_path, row.names = FALSE)
      }

      # Full-model information criteria: sum AIC/BIC across submodels (Douma & Shipley 2020)
      aic_list <- c(tryCatch(stats::AIC(m1), error = function(e) NA_real_),
                    tryCatch(stats::AIC(m2), error = function(e) NA_real_))
      bic_list <- c(tryCatch(stats::BIC(m1), error = function(e) NA_real_),
                    tryCatch(stats::BIC(m2), error = function(e) NA_real_))
      if (exists("m3")) {
        aic_list <- c(aic_list, tryCatch(stats::AIC(m3), error = function(e) NA_real_))
        bic_list <- c(bic_list, tryCatch(stats::BIC(m3), error = function(e) NA_real_))
      }
      fm_ic <- data.frame(
        submodel = c("y|parents", "LES|parents", if (exists("m3")) "SIZE|parents" else NULL),
        AIC = aic_list,
        BIC = bic_list,
        stringsAsFactors = FALSE
      )
      fm_ic$AIC_sum <- sum(fm_ic$AIC, na.rm = TRUE)
      fm_ic$BIC_sum <- sum(fm_ic$BIC, na.rm = TRUE)
      ic_path <- paste0(base, "_full_model_ic.csv")
      if (have_readr) readr::write_csv(fm_ic, ic_path) else utils::write.csv(fm_ic, ic_path, row.names = FALSE)
    }
  }

  # Optional: multigroup d-sep aggregation (Douma & Shipley 2021)
  if (nzchar(group_var) && (group_var %in% names(work))) {
    # Helper to compute Fisher's C for a subset
    fisher_for_subset <- function(df_sub, force_add_logssd = FALSE) {
      # Rebuild composites within subset
      comps_g <- build_composites(train = df_sub, test = df_sub)
      df_sub$LES  <- comps_g$LES_train
      df_sub$SIZE <- comps_g$SIZE_train
      # Build equations as above
      add_logssd_g <- if (force_add_logssd) TRUE else add_logssd
      rhs_fixed_g <- "y ~ LES + SIZE"
      if (add_logssd_g) rhs_fixed_g <- paste(rhs_fixed_g, "+ logSSD")
      if (target_letter == "M") rhs_fixed_g <- paste(rhs_fixed_g, "+ SIZE:logSSD")
      rhs_lm_g  <- stats::as.formula(rhs_fixed_g)
      rhs_lme_g <- stats::as.formula(sprintf("%s + (1|%s)", rhs_fixed_g, cluster_var))
      m1_g <- try(lme4::lmer(rhs_lme_g, data = df_sub), silent = TRUE)
      if (inherits(m1_g, "try-error")) m1_g <- stats::lm(rhs_lm_g, data = df_sub)
      m2_g <- try(lme4::lmer(stats::as.formula(sprintf("LES ~ SIZE + logSSD + (1|%s)", cluster_var)), data = df_sub), silent = TRUE)
      if (inherits(m2_g, "try-error")) m2_g <- stats::lm(LES ~ SIZE + logSSD, data = df_sub)
      if (psem_include_size_eq) {
        m3_g <- try(lme4::lmer(stats::as.formula(sprintf("SIZE ~ logSSD + (1|%s)", cluster_var)), data = df_sub), silent = TRUE)
        if (inherits(m3_g, "try-error")) m3_g <- stats::lm(SIZE ~ logSSD, data = df_sub)
        Pg <- try(piecewiseSEM::psem(m1_g, m2_g, m3_g), silent = TRUE)
      } else {
        Pg <- try(piecewiseSEM::psem(m1_g, m2_g), silent = TRUE)
      }
      if (inherits(Pg, "try-error")) return(NULL)
      fitg <- try(piecewiseSEM::fisherC(Pg), silent = TRUE)
      if (inherits(fitg, "try-error")) return(NULL)
      as.data.frame(fitg)
    }

    gv <- work[[group_var]]
    levs <- unique(gv[!is.na(gv)])
    rows <- list()
    # Parse override list for forcing SSD->y in selected groups
    override_groups <- character(0)
    if (nzchar(group_ssd_to_y_for)) {
      tmp <- unlist(strsplit(group_ssd_to_y_for, ",", fixed = TRUE))
      tmp <- trimws(tolower(tmp))
      override_groups <- tmp[nzchar(tmp)]
    }
    for (lv in levs) {
      sub <- tr[which(gv == lv), , drop = FALSE]
      if (nrow(sub) < 10) { next }
      force_ssd <- tolower(as.character(lv)) %in% override_groups
      fitg <- fisher_for_subset(sub, force_add_logssd = force_ssd)
      if (is.null(fitg)) next
      # Try to locate C and df columns robustly
      cn <- names(fitg); cnl <- tolower(cn)
      cidx <- which(cnl %in% c('c','c.stat','fisher.c','fisherc'))[1]
      dfidx<- which(cnl %in% c('df','d.f.','dof'))[1]
      pidx <- which(cnl %in% c('p','p.value','pvalue'))[1]
      Cres <- if (!is.na(cidx)) as.numeric(fitg[[cn[cidx]]][1]) else NA_real_
      dfr  <- if (!is.na(dfidx)) as.numeric(fitg[[cn[dfidx]]][1]) else NA_real_
      pval <- if (!is.na(pidx)) as.numeric(fitg[[cn[pidx]]][1]) else NA_real_
      rows[[length(rows)+1]] <- data.frame(group = as.character(lv), n = nrow(sub), fisher_C = Cres, df = dfr, pvalue = pval, stringsAsFactors = FALSE)
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

    # Per-claim equality test (AIC) for independence y ⟂ logSSD | {LES, SIZE}
    # Pooled vs per-group slopes for logSSD
    try({
      # Build composites on full data 'tr' already done above
      df_eq <- tr[!is.na(gv), , drop = FALSE]
      if (nrow(df_eq) > 20) {
        # Create a factor for group
        df_eq$.grp <- factor(df_eq[[group_var]])
        # Fit pooled with group as factor and interactions for LES/SIZE only (keep logSSD common)
        mdl_pooled <- stats::lm(y ~ LES + SIZE + logSSD + .grp + LES:.grp + SIZE:.grp, data = df_eq)
        AIC_pooled <- tryCatch(stats::AIC(mdl_pooled), error = function(e) NA_real_)
        # Per-group fits summed AIC
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
        # Decision
        use_groups <- is.finite(AIC_groups) && is.finite(AIC_pooled) && (AIC_groups + 2) < AIC_pooled  # small penalty for splitting
        out_eq <- NULL
        if (use_groups && nrow(pvals_groups) > 0) {
          # Fisher's C across groups
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
}

cat(sprintf("Target %s: n=%d, R2=%.3f±%.3f, RMSE=%.3f±%.3f, MAE=%.3f±%.3f\n",
            target_letter, nrow(work),
            agg$R2_mean, agg$R2_sd, agg$RMSE_mean, agg$RMSE_sd, agg$MAE_mean, agg$MAE_sd))
cat(sprintf("  Wrote: %s_{preds.csv, metrics.json[, piecewise_coefs.csv, dsep_fit.csv]}\n", base))

invisible(NULL)

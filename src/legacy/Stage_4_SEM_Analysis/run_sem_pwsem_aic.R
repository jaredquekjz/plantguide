#!/usr/bin/env Rscript

# Stage 4 — SEM (pwSEM) with AIC-based feature selection
# Implements Bill Shipley's methodology: RF importance → correlation clustering → AIC selection
# Based on run_sem_pwsem.R but with data-driven feature selection

suppressWarnings({
  extra_libs <- Sys.getenv("R_EXTRA_LIBS")
  paths <- character()
  if (nzchar(extra_libs)) paths <- c(paths, unlist(strsplit(extra_libs, "[,:;]", perl = TRUE)))
  if (dir.exists(".Rlib")) paths <- c(normalizePath(".Rlib"), paths)
  paths <- unique(paths[nzchar(paths)])
  if (length(paths)) .libPaths(c(paths, .libPaths()))
})

suppressWarnings({
  suppressMessages({
    have_readr    <- requireNamespace("readr",    quietly = TRUE)
    have_dplyr    <- requireNamespace("dplyr",    quietly = TRUE)
    have_ranger   <- requireNamespace("ranger",   quietly = TRUE)
    have_xgboost  <- requireNamespace("xgboost",  quietly = TRUE)
    have_lme4     <- requireNamespace("lme4",     quietly = TRUE)
    have_mgcv     <- requireNamespace("mgcv",     quietly = TRUE)
    have_MuMIn    <- requireNamespace("MuMIn",    quietly = TRUE)
    have_car      <- requireNamespace("car",      quietly = TRUE)
  })
})

# Source helper functions
source("src/Stage_4_SEM_Analysis/utils_aic_selection.R")

args <- commandArgs(trailingOnly = TRUE)

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
  cat("\nStage 4 — pwSEM with AIC-based feature selection\n")
  cat("Implements Bill Shipley's methodology for data-driven feature selection\n\n")
  cat("Usage:\n")
  cat("  Rscript src/Stage_4_SEM_Analysis/run_sem_pwsem_aic.R \\\n")
  cat("    --input_csv artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv \\\n")
  cat("    --target T --repeats 5 --folds 10 \\\n")
  cat("    --rf_trees 1000 --cor_threshold 0.8 --offer_all false \\\n")
  cat("    --out_dir artifacts/stage4_sem_pwsem_aic\n\n")
  cat("Flags:\n")
  cat("  --input_csv PATH        Input CSV with traits and bioclim features\n")
  cat("  --target L|T|M|R|N      Axis to model (default T)\n")
  cat("  --repeats INT --folds INT  Repeated CV (defaults 5×10)\n")
  cat("  --rf_trees INT          Number of RF trees for importance (default 1000)\n")
  cat("  --cor_threshold FLOAT   Correlation threshold for clustering (default 0.8)\n")
  cat("  --offer_all true|false  Skip clustering, offer all variables (default false)\n")
  cat("  --stratify true|false   Stratify CV by y deciles (default true)\n")
  cat("  --standardize true|false  Z-score predictors within folds (default true)\n")
  cat("  --out_dir PATH          Output directory\n")
  quit(status = 0)
}

`%||%` <- function(a,b) if (!is.null(a) && nzchar(a)) a else b

# Parse options
in_csv        <- opts[["input_csv"]] %||% "artifacts/model_data_bioclim_subset_sem_ready_20250920_stage2.csv"
target_letter <- toupper(opts[["target"]] %||% "T")
seed_opt      <- suppressWarnings(as.integer(opts[["seed"]] %||% "123"))
repeats_opt   <- suppressWarnings(as.integer(opts[["repeats"]] %||% "5"))
folds_opt     <- suppressWarnings(as.integer(opts[["folds"]]   %||% "10"))
stratify_opt  <- tolower(opts[["stratify"]] %||% "true") %in% c("1","true","yes","y")
standardize   <- tolower(opts[["standardize"]] %||% "true") %in% c("1","true","yes","y")
rf_trees      <- suppressWarnings(as.integer(opts[["rf_trees"]] %||% "1000"))
cor_threshold <- suppressWarnings(as.numeric(opts[["cor_threshold"]] %||% "0.8"))
offer_all     <- tolower(opts[["offer_all"]] %||% "false") %in% c("1","true","yes","y")
out_dir       <- opts[["out_dir"]] %||% "artifacts/stage4_sem_pwsem_aic"

# Ensure output directory exists
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

fail <- function(msg) { cat(sprintf("[error] %s\n", msg)); quit(status = 1) }

if (!file.exists(in_csv)) fail(sprintf("Input CSV not found: '%s'", in_csv))
if (!have_ranger) fail("ranger package required for RF importance")
# XGBoost will be called via conda/Python, so R package not strictly required
if (!have_MuMIn) fail("MuMIn package required for AIC selection")

# Load data
message(sprintf("\n[Data] Loading from %s", in_csv))
df <- if (have_readr) readr::read_csv(in_csv, show_col_types = FALSE) else read.csv(in_csv, check.names = FALSE)
df <- as.data.frame(df)

# Target column
target_name <- paste0("EIVEres.", target_letter)
if (!(target_name %in% names(df))) {
  target_name <- paste0("EIVEres-", target_letter)
}
if (!(target_name %in% names(df))) fail(sprintf("Target column not found: %s", target_name))

message(sprintf("[Data] Target: %s, n = %d species", target_name, nrow(df)))

# ==============================================================================
# PHASE 1: Black-box Feature Importance (RF + XGBoost)
# ==============================================================================
message("\n=== Phase 1: Black-box Feature Importance (RF + XGBoost) ===")

# Rename target for consistency
names(df)[names(df) == target_name] <- "y"

# Run RF to get feature importance
rf_results <- compute_rf_importance(df, "y", n_trees = rf_trees, seed = seed_opt)

# Run XGBoost to get feature importance
xgb_results <- compute_xgb_importance(df, "y", n_rounds = rf_trees / 2, seed = seed_opt)

# Combine importances from both methods
combined_importance <- combine_importances(
  rf_importance = rf_results$importance,
  xgb_importance = xgb_results$importance,
  method = "average_normalized"  # Can also use "average_rank" or "max"
)

# Display top features by combined importance
message("\nTop 20 features by combined RF+XGBoost importance:")
top_features <- head(combined_importance, 20)
for (i in 1:nrow(top_features)) {
  message(sprintf("  %2d. %-30s Comb:%.4f (RF:%.4f, XGB:%.4f)",
                 i,
                 top_features$feature[i],
                 top_features$combined_importance[i],
                 top_features$rf_importance[i],
                 top_features$xgb_importance[i]))
}

# ==============================================================================
# PHASE 2: Correlation Clustering for Climate Variables
# ==============================================================================
message("\n=== Phase 2: Correlation Clustering ===")

# Define climate variables
climate_vars <- get_axis_climate_vars(target_letter)
message(sprintf("[Clustering] Checking %d potential climate variables", length(climate_vars)))

# Select climate representatives using combined importance
selected_climate <- select_climate_representatives(
  data = df,
  climate_vars = climate_vars,
  importance_df = combined_importance,  # Use combined RF+XGBoost importance
  cor_threshold = cor_threshold,
  offer_all = offer_all
)

message(sprintf("[Clustering] Selected %d climate representatives", length(selected_climate)))

# ==============================================================================
# PHASE 3: Define Core Features and Interactions
# ==============================================================================
message("\n=== Phase 3: Feature Set Construction ===")

# Core trait variables (always retained per SEM theory)
core_traits <- c("Leaf area (mm2)", "Plant height (m)", "Diaspore mass (mg)",
                "SSD used (mg/mm3)", "LMA (g/m2)", "Nmass (mg/g)")

# Check which are available
available_traits <- intersect(core_traits, names(df))
message(sprintf("[Features] Core traits available: %d/%d", length(available_traits), length(core_traits)))

# Get axis-specific interactions
interaction_vars <- get_axis_interactions(target_letter)
available_interactions <- intersect(interaction_vars, names(df))
message(sprintf("[Features] Interactions available: %d/%d",
               length(available_interactions), length(interaction_vars)))

# Check for phylogenetic predictor
phylo_col <- paste0("p_phylo_", target_letter)
has_phylo <- phylo_col %in% names(df)
message(sprintf("[Features] Phylogenetic predictor: %s", ifelse(has_phylo, "available", "not found")))

# ==============================================================================
# PHASE 4: Cross-Validation with AIC Selection
# ==============================================================================
message("\n=== Phase 4: Cross-Validation with AIC Selection ===")

# Helper functions for data preparation
compute_offset <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x) & !is.na(x) & x > 0]
  if (!length(x)) return(1e-6)
  max(1e-6, 1e-3 * stats::median(x))
}

zscore <- function(x) {
  x <- as.numeric(x)
  mean_ <- mean(x, na.rm=TRUE)
  sd_ <- stats::sd(x, na.rm=TRUE)
  if (!is.finite(sd_) || sd_ == 0) sd_ <- 1
  list(x=(x-mean_)/sd_, mean=mean_, sd=sd_)
}

build_composites <- function(train, test) {
  # Build LES composite (negative LMA + Nmass)
  M_LES_tr <- scale(cbind(negLMA = -train$LMA, Nmass = train$Nmass))
  p_les <- stats::prcomp(M_LES_tr, center = FALSE, scale. = FALSE)
  rot_les <- p_les$rotation[,1]
  if (rot_les["Nmass"] < 0) rot_les <- -rot_les
  scores_LES_tr <- as.numeric(M_LES_tr %*% rot_les)

  M_LES_te <- scale(cbind(negLMA = -test$LMA, Nmass = test$Nmass),
                   center = attr(M_LES_tr, "scaled:center"),
                   scale = attr(M_LES_tr, "scaled:scale"))
  scores_LES_te <- as.numeric(M_LES_te %*% rot_les)

  # Build SIZE composite (logH + logSM)
  M_SIZE_tr <- scale(cbind(logH = train$logH, logSM = train$logSM))
  p_size <- stats::prcomp(M_SIZE_tr, center = FALSE, scale. = FALSE)
  rot_size <- p_size$rotation[,1]
  if (rot_size["logH"] < 0) rot_size <- -rot_size
  scores_SIZE_tr <- as.numeric(M_SIZE_tr %*% rot_size)

  M_SIZE_te <- scale(cbind(logH = test$logH, logSM = test$logSM),
                    center = attr(M_SIZE_tr, "scaled:center"),
                    scale = attr(M_SIZE_tr, "scaled:scale"))
  scores_SIZE_te <- as.numeric(M_SIZE_te %*% rot_size)

  list(LES_train = scores_LES_tr, LES_test = scores_LES_te,
       SIZE_train = scores_SIZE_tr, SIZE_test = scores_SIZE_te)
}

# Prepare for CV
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

# Prepare work data
work <- df[, c("wfo_accepted_name", "y", available_traits, selected_climate,
              available_interactions, if(has_phylo) phylo_col else NULL)]

# Log-transform traits
log_vars <- c("Leaf area (mm2)", "Plant height (m)", "Diaspore mass (mg)", "SSD used (mg/mm3)")
offsets <- sapply(log_vars, function(v) if(v %in% names(work)) compute_offset(work[[v]]) else 1e-6)

for (v in names(offsets)) {
  if (v %in% names(work)) {
    work[[paste0("log_", gsub("[^A-Za-z]", "", v))]] <- log10(work[[v]] + offsets[[v]])
  }
}

# Create simplified column names
work$logLA <- log10(work[["Leaf area (mm2)"]] + offsets[["Leaf area (mm2)"]])
work$logH  <- log10(work[["Plant height (m)"]] + offsets[["Plant height (m)"]])
work$logSM <- log10(work[["Diaspore mass (mg)"]] + offsets[["Diaspore mass (mg)"]])
work$logSSD<- log10(work[["SSD used (mg/mm3)"]] + offsets[["SSD used (mg/mm3)"]])
work$LMA   <- as.numeric(work[["LMA (g/m2)"]])
work$Nmass <- as.numeric(work[["Nmass (mg/g)"]])

# CV storage
cv_results <- data.frame()
model_selection <- data.frame()

set.seed(seed_opt)
groups <- make_folds(work$y, folds_opt, stratify_opt)

# Run CV
for (r in seq_len(repeats_opt)) {
  message(sprintf("\n[CV] Repeat %d/%d", r, repeats_opt))
  set.seed(seed_opt + r)

  fold_assign <- integer(nrow(work))
  if (length(groups) == 1) {
    fold_assign <- sample(rep(1:folds_opt, length.out=nrow(work)))
  } else {
    fold_assign <- unlist(lapply(groups, function(idxg)
      sample(rep(1:folds_opt, length.out=length(idxg)))))
    ord <- unlist(groups)
    tmp <- integer(nrow(work))
    tmp[ord] <- fold_assign
    fold_assign <- tmp
  }

  for (k in seq_len(folds_opt)) {
    test_idx <- which(fold_assign == k)
    train_idx <- setdiff(seq_len(nrow(work)), test_idx)

    tr <- work[train_idx, , drop = FALSE]
    te <- work[test_idx,  , drop = FALSE]

    # Standardize features
    if (standardize) {
      for (v in c("logLA","logH","logSM","logSSD","LMA","Nmass",
                 selected_climate, available_interactions)) {
        if (v %in% names(tr)) {
          zs <- zscore(tr[[v]])
          tr[[v]] <- zs$x
          if (v %in% names(te)) te[[v]] <- (te[[v]] - zs$mean)/zs$sd
        }
      }
    }

    # Build composites
    comps <- build_composites(train = tr, test = te)
    tr$LES  <- comps$LES_train; te$LES  <- comps$LES_test
    tr$SIZE <- comps$SIZE_train; te$SIZE <- comps$SIZE_test

    # Define available features for this fold
    fold_traits <- c("LES", "SIZE", "logSSD", "logLA", "Nmass")
    fold_climate <- intersect(selected_climate, names(tr))
    fold_interactions <- intersect(available_interactions, names(tr))
    fold_phylo <- if(has_phylo && phylo_col %in% names(tr)) phylo_col else NULL

    # Build candidate formulas
    formulas <- build_candidate_formulas(
      target_letter = target_letter,
      trait_vars = fold_traits,
      climate_vars = fold_climate,
      interaction_vars = fold_interactions,
      phylo_var = fold_phylo
    )

    # Fit models and select best by AIC
    aic_results <- fit_and_compare_models(tr, formulas, use_gam = have_mgcv)

    # Use best model for prediction
    best_model <- aic_results$best_model
    best_name <- aic_results$best_name

    # Predict
    if (inherits(best_model, "gam")) {
      yhat <- as.numeric(predict(best_model, newdata = te))
    } else {
      yhat <- as.numeric(predict(best_model, newdata = te))
    }

    ytrue <- te$y
    err <- ytrue - yhat
    r2 <- 1 - sum(err^2)/sum((ytrue - mean(ytrue))^2)
    rmse <- sqrt(mean(err^2))
    mae <- mean(abs(err))

    # Store results
    cv_results <- rbind(cv_results, data.frame(
      rep = r, fold = k,
      r2 = r2, rmse = rmse, mae = mae,
      selected_model = best_name,
      stringsAsFactors = FALSE
    ))

    # Store model selection details
    for (i in 1:nrow(aic_results$comparison)) {
      model_selection <- rbind(model_selection, data.frame(
        rep = r, fold = k,
        model = aic_results$comparison$model[i],
        aic = aic_results$comparison$aic[i],
        weight = aic_results$comparison$weight[i],
        selected = (aic_results$comparison$model[i] == best_name),
        stringsAsFactors = FALSE
      ))
    }
  }
}

# ==============================================================================
# PHASE 5: Summary and Output
# ==============================================================================
message("\n=== Phase 5: Results Summary ===")

# Overall CV performance
overall_summary <- cv_results %>%
  dplyr::summarise(
    r2_mean = mean(r2, na.rm=TRUE),
    r2_sd = sd(r2, na.rm=TRUE),
    rmse_mean = mean(rmse, na.rm=TRUE),
    rmse_sd = sd(rmse, na.rm=TRUE),
    mae_mean = mean(mae, na.rm=TRUE),
    mae_sd = sd(mae, na.rm=TRUE)
  )

message(sprintf("\nCV Performance (AIC selection):"))
message(sprintf("  R² = %.3f ± %.3f", overall_summary$r2_mean, overall_summary$r2_sd))
message(sprintf("  RMSE = %.3f ± %.3f", overall_summary$rmse_mean, overall_summary$rmse_sd))
message(sprintf("  MAE = %.3f ± %.3f", overall_summary$mae_mean, overall_summary$mae_sd))

# Model selection frequency
selection_freq <- cv_results %>%
  dplyr::count(selected_model) %>%
  dplyr::mutate(prop = n / nrow(cv_results)) %>%
  dplyr::arrange(dplyr::desc(n))

message("\nModel selection frequency:")
for (i in 1:nrow(selection_freq)) {
  message(sprintf("  %s: %.1f%% (%d/%d folds)",
                 selection_freq$selected_model[i],
                 100 * selection_freq$prop[i],
                 selection_freq$n[i],
                 nrow(cv_results)))
}

# Average AIC weights
avg_weights <- model_selection %>%
  dplyr::group_by(model) %>%
  dplyr::summarise(
    avg_weight = mean(weight, na.rm=TRUE),
    times_selected = sum(selected)
  ) %>%
  dplyr::arrange(dplyr::desc(avg_weight))

message("\nAverage AIC weights:")
for (i in 1:nrow(avg_weights)) {
  message(sprintf("  %s: weight = %.3f, selected %d times",
                 avg_weights$model[i],
                 avg_weights$avg_weight[i],
                 avg_weights$times_selected[i]))
}

# Save results
results <- list(
  target = target_letter,
  cv_summary = overall_summary,
  cv_details = cv_results,
  model_selection = model_selection,
  selection_frequency = selection_freq,
  avg_weights = avg_weights,
  rf_importance_top20 = head(rf_results$importance, 20),
  xgb_importance_top20 = head(xgb_results$importance, 20),
  combined_importance_top20 = head(combined_importance, 20),
  selected_climate = selected_climate,
  config = list(
    repeats = repeats_opt,
    folds = folds_opt,
    rf_trees = rf_trees,
    cor_threshold = cor_threshold,
    offer_all = offer_all,
    seed = seed_opt
  )
)

# Write JSON output
if (have_dplyr) {  # jsonlite typically comes with dplyr
  jsonlite::write_json(
    results,
    file.path(out_dir, sprintf("pwsem_aic_%s_results.json", target_letter)),
    pretty = TRUE,
    auto_unbox = TRUE
  )
}

# Write CSV outputs
write.csv(cv_results,
         file.path(out_dir, sprintf("pwsem_aic_%s_cv.csv", target_letter)),
         row.names = FALSE)
write.csv(selection_freq,
         file.path(out_dir, sprintf("pwsem_aic_%s_selection.csv", target_letter)),
         row.names = FALSE)

message(sprintf("\n[Complete] Results saved to %s", out_dir))
message(sprintf("Target %s: n=%d, R²=%.3f±%.3f, RMSE=%.3f±%.3f",
               target_letter, nrow(work),
               overall_summary$r2_mean, overall_summary$r2_sd,
               overall_summary$rmse_mean, overall_summary$rmse_sd))
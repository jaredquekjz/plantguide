#!/usr/bin/env Rscript
#
# XGBoost Training Driver (Bill's Verification)
#
# Purpose: Train XGBoost models with k-fold CV for Stage 1 (imputation) or Stage 2 (EIVE)
# - Fits XGBRegressor, reports k-fold CV metrics
# - Exports model, scaler params, and SHAP feature importance
# - Supports both observed trait data (Stage 1) and complete feature tables (Stage 2)
#

suppressPackageStartupMessages({
  library(xgboost)
  library(readr)
  library(dplyr)
  library(jsonlite)
})

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

parse_args <- function(args) {
  out <- list(
    mode = 'stage2',  # 'stage1' or 'stage2'
    axis = 'L',       # For stage2: L/T/M/N/R; For stage1: trait name (logLA, logNmass, etc.)
    features_csv = NA,
    out_dir = NA,
    target_column = 'y',
    species_column = 'wfo_taxon_id',
    gpu = FALSE,
    seed = 42,
    n_estimators = 600,
    learning_rate = 0.05,
    max_depth = 6,
    subsample = 0.8,
    colsample_bytree = 0.8,
    cv_folds = 10,
    compute_cv = TRUE
  )

  for (a in args) {
    if (!grepl('^--', a)) next
    kv <- sub('^--', '', a)
    key <- sub('=.*$', '', kv)
    val <- sub('^[^=]*=', '', kv)

    if (key == 'mode') out$mode <- tolower(val)
    else if (key == 'axis') out$axis <- val
    else if (key == 'trait') out$axis <- val  # Alias for stage1
    else if (key == 'features_csv') out$features_csv <- val
    else if (key == 'out_dir') out$out_dir <- val
    else if (key == 'target_column') out$target_column <- val
    else if (key == 'species_column') out$species_column <- val
    else if (key == 'gpu') out$gpu <- tolower(val) %in% c('true', 't', '1', 'yes')
    else if (key == 'seed') out$seed <- as.integer(val)
    else if (key == 'n_estimators') out$n_estimators <- as.integer(val)
    else if (key == 'learning_rate') out$learning_rate <- as.numeric(val)
    else if (key == 'max_depth') out$max_depth <- as.integer(val)
    else if (key == 'subsample') out$subsample <- as.numeric(val)
    else if (key == 'colsample_bytree') out$colsample_bytree <- as.numeric(val)
    else if (key == 'cv_folds') out$cv_folds <- as.integer(val)
    else if (key == 'compute_cv') out$compute_cv <- tolower(val) %in% c('true', 't', '1', 'yes')
  }

  # Validate required args
  if (is.na(out$features_csv)) stop('Missing required argument: --features_csv')
  if (is.na(out$out_dir)) stop('Missing required argument: --out_dir')

  out
}

args <- commandArgs(trailingOnly = TRUE)
opts <- parse_args(args)

# ============================================================================
# HEADER
# ============================================================================

cat(strrep('=', 80), '\n')
if (opts$mode == 'stage1') {
  cat(sprintf('XGBOOST TRAINING: Stage 1 Imputation - %s (Bill Verification)\n', opts$axis))
} else {
  cat(sprintf('XGBOOST TRAINING: Stage 2 EIVE - %s-axis (Bill Verification)\n', opts$axis))
}
cat(strrep('=', 80), '\n\n')

cat('Configuration:\n')
cat(sprintf('  Mode: %s\n', opts$mode))
cat(sprintf('  Features CSV: %s\n', opts$features_csv))
cat(sprintf('  Output dir: %s\n', opts$out_dir))
cat(sprintf('  Target: %s\n', ifelse(opts$mode == 'stage1', opts$axis, opts$target_column)))
cat(sprintf('  GPU: %s\n', ifelse(opts$gpu, 'TRUE', 'FALSE')))
cat(sprintf('  Seed: %d\n', opts$seed))
cat(sprintf('  n_estimators: %d\n', opts$n_estimators))
cat(sprintf('  learning_rate: %.3f\n', opts$learning_rate))
cat(sprintf('  max_depth: %d\n', opts$max_depth))
cat(sprintf('  subsample: %.2f\n', opts$subsample))
cat(sprintf('  colsample_bytree: %.2f\n', opts$colsample_bytree))
cat(sprintf('  CV folds: %d\n\n', opts$cv_folds))

# ============================================================================
# LOAD DATA
# ============================================================================

cat('[1/5] Loading feature table...\n')
cat(strrep('-', 80), '\n')

if (!file.exists(opts$features_csv)) {
  stop('Features file not found: ', opts$features_csv)
}

df <- read_csv(opts$features_csv, show_col_types = FALSE)
cat(sprintf('✓ Loaded %d species × %d columns\n', nrow(df), ncol(df)))

# Mode-specific data preparation
if (opts$mode == 'stage1') {
  # Stage 1: Imputation analysis
  # Target is a trait column (logLA, logNmass, etc.)
  target_trait <- opts$axis

  if (!target_trait %in% names(df)) {
    stop('Target trait not found: ', target_trait)
  }

  # Extract target
  y_full <- df[[target_trait]]
  n_total <- nrow(df)
  n_obs <- sum(!is.na(y_full))

  if (n_obs == 0) {
    stop('No observed values for trait: ', target_trait)
  }

  cat(sprintf('✓ Target trait: %s\n', target_trait))
  cat(sprintf('✓ Observed: %d/%d (%.1f%%)\n', n_obs, n_total, 100 * n_obs / n_total))

  # Filter to observed cases only
  obs_idx <- which(!is.na(y_full))
  df <- df[obs_idx, ]
  y <- y_full[obs_idx]

  cat(sprintf('✓ Filtered to %d observed cases\n', nrow(df)))

  # Exclude ALL target traits from features
  all_target_traits <- c('logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM')
  drop_cols <- c('leaf_area_source', 'nmass_source', 'ldmc_source', 'lma_source',
                 'height_source', 'seed_mass_source', 'sla_source',
                 'try_parasitism', 'try_carnivory', 'try_succulence',
                 'accepted_name', 'accepted_norm', 'accepted_wfo_id',
                 'duke_files', 'duke_original_names', 'duke_matched_names', 'duke_scientific_names',
                 'eive_taxon_concepts', 'try_source_species',
                 'genus', 'family', 'try_genus', 'try_family')

  id_cols <- c('wfo_taxon_id', 'wfo_scientific_name', opts$species_column)
  exclude_cols <- c(id_cols, all_target_traits, drop_cols)
  feature_cols <- setdiff(names(df), exclude_cols)

} else {
  # Stage 2: EIVE prediction
  # Target is 'y' column, features are already prepared
  if (!opts$target_column %in% names(df)) {
    stop('Target column not found: ', opts$target_column)
  }

  y <- df[[opts$target_column]]
  n_obs <- sum(!is.na(y))

  if (n_obs == 0) {
    stop('No observed values for target: ', opts$target_column)
  }

  cat(sprintf('✓ Target (%s): %d observed (%.1f%%)\n',
              opts$target_column, n_obs, 100 * n_obs / nrow(df)))

  # Remove non-feature columns
  id_cols <- c('wfo_taxon_id', 'wfo_scientific_name', opts$species_column, opts$target_column)
  feature_cols <- setdiff(names(df), id_cols)
}

# Prepare feature matrix
X_df <- df %>% select(all_of(feature_cols))

# Handle categorical features for Stage 1
if (opts$mode == 'stage1') {
  # Convert categorical traits to factors
  keep_cats <- c('try_woodiness', 'try_growth_form', 'try_habitat_adaptation',
                 'try_leaf_type', 'try_leaf_phenology', 'try_photosynthesis_pathway',
                 'try_mycorrhiza_type')

  for (col in intersect(keep_cats, names(X_df))) {
    if (!is.factor(X_df[[col]])) {
      X_df[[col]] <- as.factor(X_df[[col]])
    }
  }

  # Convert any remaining character columns to factors
  char_cols <- sapply(X_df, is.character)
  if (any(char_cols)) {
    X_df[char_cols] <- lapply(X_df[char_cols], factor)
  }

  # Remove high-cardinality categoricals (>50 levels)
  high_card <- names(X_df)[sapply(X_df, function(col) {
    if (is.factor(col)) nlevels(col) > 50 else FALSE
  })]
  if (length(high_card) > 0) {
    cat(sprintf('  Removing %d high-cardinality features: %s\n',
                length(high_card), paste(high_card, collapse=', ')))
    X_df <- X_df[, !names(X_df) %in% high_card, drop = FALSE]
  }

  # One-hot encode categorical features
  cat('  One-hot encoding categorical features...\n')
  X_encoded <- model.matrix(~ . - 1, data = X_df, na.action = na.pass)
  X <- X_encoded
  feature_cols <- colnames(X)

  cat(sprintf('✓ Features after encoding: %d columns\n', ncol(X)))
} else {
  # Stage 2: Features should already be numeric
  non_numeric <- names(X_df)[!sapply(X_df, is.numeric)]
  if (length(non_numeric) > 0) {
    warning(sprintf('Non-numeric columns found: %s', paste(non_numeric, collapse=', ')))
    X_df <- X_df %>% select(where(is.numeric))
    feature_cols <- names(X_df)
  }

  X <- as.matrix(X_df)
  cat(sprintf('✓ Features: %d columns\n', ncol(X)))
}

cat(sprintf('✓ Data shape: %d × %d\n\n', nrow(X), ncol(X)))

# ============================================================================
# K-FOLD CROSS-VALIDATION
# ============================================================================

if (opts$compute_cv) {
  cat('[2/5] Running k-fold cross-validation...\n')
  cat(strrep('-', 80), '\n')

  set.seed(opts$seed)
  fold_indices <- sample(rep(1:opts$cv_folds, length.out = n_obs))

  r2s <- numeric(opts$cv_folds)
  rmses <- numeric(opts$cv_folds)
  maes <- numeric(opts$cv_folds)
  acc_rank1 <- numeric(opts$cv_folds)
  acc_rank2 <- numeric(opts$cv_folds)

  # Store per-fold predictions
  cv_predictions <- list()

  for (fold in 1:opts$cv_folds) {
    cat(sprintf('  Fold %d/%d... ', fold, opts$cv_folds))

    # Split data
    test_idx <- which(fold_indices == fold)
    train_idx <- setdiff(1:n_obs, test_idx)

    X_train_raw <- X[train_idx, , drop = FALSE]
    X_test_raw <- X[test_idx, , drop = FALSE]
    y_train <- y[train_idx]
    y_test <- y[test_idx]

    # Standardize features (z-score on training set)
    means <- colMeans(X_train_raw, na.rm = TRUE)
    means[is.na(means)] <- 0

    sds <- apply(X_train_raw, 2, sd, na.rm = TRUE)
    sds[sds == 0 | is.na(sds)] <- 1

    X_train <- scale(X_train_raw, center = means, scale = sds)
    X_test <- scale(X_test_raw, center = means, scale = sds)

    # Convert to xgb.DMatrix
    dtrain <- xgb.DMatrix(data = X_train, label = y_train)
    dtest <- xgb.DMatrix(data = X_test, label = y_test)

    # XGBoost parameters
    params <- list(
      objective = 'reg:squarederror',
      eval_metric = 'rmse',
      eta = opts$learning_rate,
      max_depth = opts$max_depth,
      subsample = opts$subsample,
      colsample_bytree = opts$colsample_bytree,
      lambda = 1.0,
      min_child_weight = 1.0,
      seed = opts$seed + fold  # Different seed per fold
    )

    if (opts$gpu) {
      params$device <- 'cuda'
      params$tree_method <- 'hist'
    } else {
      params$device <- 'cpu'
      params$tree_method <- 'hist'
    }

    # Train model
    model <- xgb.train(
      params = params,
      data = dtrain,
      nrounds = opts$n_estimators,
      verbose = 0
    )

    # Predict
    y_pred <- predict(model, dtest)

    # Metrics
    r2 <- 1 - sum((y_test - y_pred)^2) / sum((y_test - mean(y_test))^2)
    rmse <- sqrt(mean((y_test - y_pred)^2))
    mae <- mean(abs(y_test - y_pred))

    # Rank-based accuracy (matching Python implementation)
    y_rank_true <- round(y_test)
    y_rank_pred <- round(y_pred)
    rank_diff <- abs(y_rank_true - y_rank_pred)
    acc_r1 <- mean(rank_diff <= 1)
    acc_r2 <- mean(rank_diff <= 2)

    r2s[fold] <- r2
    rmses[fold] <- rmse
    maes[fold] <- mae
    acc_rank1[fold] <- acc_r1
    acc_rank2[fold] <- acc_r2

    # Store predictions
    if (opts$species_column %in% names(df)) {
      species_ids <- df[[opts$species_column]][test_idx]
    } else {
      species_ids <- test_idx
    }

    cv_predictions[[fold]] <- data.frame(
      fold = fold,
      row = test_idx,
      species = species_ids,
      y_true = y_test,
      y_pred = y_pred,
      residual = y_test - y_pred,
      stringsAsFactors = FALSE
    )

    cat(sprintf('R²=%.4f, RMSE=%.4f, MAE=%.4f, Acc±1=%.3f\n',
                r2, rmse, mae, acc_r1))
  }

  # Combine all fold predictions
  cv_preds_df <- bind_rows(cv_predictions)

  cat('\n')
  cat('Cross-validation summary:\n')
  cat(sprintf('  R²:   %.4f ± %.4f\n', mean(r2s), sd(r2s)))
  cat(sprintf('  RMSE: %.4f ± %.4f\n', mean(rmses), sd(rmses)))
  cat(sprintf('  MAE:  %.4f ± %.4f\n', mean(maes), sd(maes)))
  cat(sprintf('  Acc±1: %.3f ± %.3f\n', mean(acc_rank1), sd(acc_rank1)))
  cat(sprintf('  Acc±2: %.3f ± %.3f\n\n', mean(acc_rank2), sd(acc_rank2)))

} else {
  cat('[2/5] Skipping cross-validation (compute_cv=FALSE)\n\n')
}

# ============================================================================
# TRAIN PRODUCTION MODEL (ALL DATA)
# ============================================================================

cat('[3/5] Training production model on all observed data...\n')
cat(strrep('-', 80), '\n')

# Standardize on full dataset
means <- colMeans(X, na.rm = TRUE)
means[is.na(means)] <- 0

sds <- apply(X, 2, sd, na.rm = TRUE)
sds[sds == 0 | is.na(sds)] <- 1

X_scaled <- scale(X, center = means, scale = sds)

# Convert to xgb.DMatrix
dtrain_full <- xgb.DMatrix(data = X_scaled, label = y)

# XGBoost parameters
params <- list(
  objective = 'reg:squarederror',
  eval_metric = 'rmse',
  eta = opts$learning_rate,
  max_depth = opts$max_depth,
  subsample = opts$subsample,
  colsample_bytree = opts$colsample_bytree,
  lambda = 1.0,
  min_child_weight = 1.0,
  seed = opts$seed
)

if (opts$gpu) {
  params$device <- 'cuda'
  params$tree_method <- 'hist'
} else {
  params$device <- 'cpu'
  params$tree_method <- 'hist'
}

cat(sprintf('Training with %d estimators...\n', opts$n_estimators))
model_final <- xgb.train(
  params = params,
  data = dtrain_full,
  nrounds = opts$n_estimators,
  verbose = 0
)

cat('✓ Model training complete\n\n')

# ============================================================================
# COMPUTE FEATURE IMPORTANCE (SHAP)
# ============================================================================

cat('[4/5] Computing feature importance (SHAP)...\n')
cat(strrep('-', 80), '\n')

# Get SHAP contributions
shap_contrib <- predict(model_final, dtrain_full, predcontrib = TRUE)

# Mean absolute SHAP values (global importance)
# Last column is bias, exclude it
shap_abs_mean <- colMeans(abs(shap_contrib[, -ncol(shap_contrib), drop = FALSE]))

importance_df <- data.frame(
  feature = feature_cols,
  importance = shap_abs_mean,
  stringsAsFactors = FALSE
) %>%
  arrange(desc(importance))

cat(sprintf('✓ Computed importance for %d features\n', nrow(importance_df)))
cat('\nTop 10 features:\n')
print(head(importance_df, 10), row.names = FALSE)
cat('\n')

# ============================================================================
# SAVE OUTPUTS
# ============================================================================

cat('[5/5] Saving outputs...\n')
cat(strrep('-', 80), '\n')

dir.create(opts$out_dir, recursive = TRUE, showWarnings = FALSE)

# Save model (JSON format)
model_path <- file.path(opts$out_dir, sprintf('xgb_%s_model.json', opts$axis))
xgb.save(model_final, model_path)
cat(sprintf('✓ Saved model: %s\n', model_path))

# Save scaler parameters (JSON)
scaler_params <- list(
  features = feature_cols,
  mean = as.numeric(means),
  scale = as.numeric(sds)
)

scaler_path <- file.path(opts$out_dir, sprintf('xgb_%s_scaler.json', opts$axis))
write_json(scaler_params, scaler_path, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf('✓ Saved scaler: %s\n', scaler_path))

# Save feature importance
importance_path <- file.path(opts$out_dir, sprintf('xgb_%s_importance.csv', opts$axis))
write_csv(importance_df, importance_path)
cat(sprintf('✓ Saved importance: %s\n', importance_path))

# Save CV metrics and predictions if computed
if (opts$compute_cv) {
  cv_metrics <- list(
    axis = opts$axis,
    n_folds = opts$cv_folds,
    n_obs = n_obs,
    r2_mean = mean(r2s),
    r2_sd = sd(r2s),
    rmse_mean = mean(rmses),
    rmse_sd = sd(rmses),
    mae_mean = mean(maes),
    mae_sd = sd(maes),
    accuracy_rank1_mean = mean(acc_rank1),
    accuracy_rank1_sd = sd(acc_rank1),
    accuracy_rank2_mean = mean(acc_rank2),
    accuracy_rank2_sd = sd(acc_rank2)
  )

  metrics_path <- file.path(opts$out_dir, sprintf('xgb_%s_cv_metrics.json', opts$axis))
  write_json(cv_metrics, metrics_path, auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf('✓ Saved CV metrics: %s\n', metrics_path))

  # Save per-fold predictions
  cv_preds_path <- file.path(opts$out_dir, sprintf('xgb_%s_cv_predictions.csv', opts$axis))
  write_csv(cv_preds_df, cv_preds_path)
  cat(sprintf('✓ Saved CV predictions: %s\n', cv_preds_path))
}

# ============================================================================
# SUMMARY
# ============================================================================

cat('\n')
cat(strrep('=', 80), '\n')
cat('TRAINING COMPLETE\n')
cat(strrep('=', 80), '\n\n')

cat(sprintf('Axis: %s\n', opts$axis))
cat(sprintf('Training samples: %d\n', n_obs))
cat(sprintf('Features: %d\n', length(feature_cols)))

if (opts$compute_cv) {
  cat(sprintf('CV R²: %.4f ± %.4f\n', mean(r2s), sd(r2s)))
  cat(sprintf('CV RMSE: %.4f ± %.4f\n', mean(rmses), sd(rmses)))
  cat(sprintf('CV Acc±1: %.3f ± %.3f\n', mean(acc_rank1), sd(acc_rank1)))
  cat(sprintf('CV Acc±2: %.3f ± %.3f\n', mean(acc_rank2), sd(acc_rank2)))
}

cat(sprintf('\nModel saved: %s\n', model_path))
cat('\nNext step: Run imputation for missing EIVE values\n')
cat('  Rscript src/Stage_2/bill_verification/impute_eive_no_eive_bill.R\n\n')

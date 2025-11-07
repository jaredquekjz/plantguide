#!/usr/bin/env Rscript
#
# Stage 2 XGBoost Training Driver (Bill's Verification)
#
# Purpose: Train XGBoost models with k-fold CV for EIVE prediction
# - Fits XGBRegressor, reports k-fold CV metrics
# - Exports model, scaler params, and feature importance
# - NO phylo predictors (using eigenvectors only)
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
    axis = 'L',
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

    if (key == 'axis') out$axis <- val
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
cat(sprintf('XGBOOST TRAINING: %s-axis (Bill Verification)\n', opts$axis))
cat(strrep('=', 80), '\n\n')

cat('Configuration:\n')
cat(sprintf('  Features CSV: %s\n', opts$features_csv))
cat(sprintf('  Output dir: %s\n', opts$out_dir))
cat(sprintf('  Target: %s\n', opts$target_column))
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

# Verify target column exists
if (!opts$target_column %in% names(df)) {
  stop('Target column not found: ', opts$target_column)
}

# Extract target
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

X_df <- df %>% select(all_of(feature_cols))
X <- as.matrix(X_df)

cat(sprintf('✓ Features: %d columns\n', ncol(X)))
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
      seed = opts$seed
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

    r2s[fold] <- r2
    rmses[fold] <- rmse
    maes[fold] <- mae

    cat(sprintf('R²=%.4f, RMSE=%.4f, MAE=%.4f\n', r2, rmse, mae))
  }

  cat('\n')
  cat('Cross-validation summary:\n')
  cat(sprintf('  R²:   %.4f ± %.4f\n', mean(r2s), sd(r2s)))
  cat(sprintf('  RMSE: %.4f ± %.4f\n', mean(rmses), sd(rmses)))
  cat(sprintf('  MAE:  %.4f ± %.4f\n\n', mean(maes), sd(maes)))

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

# Save CV metrics if computed
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
    mae_sd = sd(maes)
  )

  metrics_path <- file.path(opts$out_dir, sprintf('xgb_%s_cv_metrics.json', opts$axis))
  write_json(cv_metrics, metrics_path, auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf('✓ Saved CV metrics: %s\n', metrics_path))
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
}

cat(sprintf('\nModel saved: %s\n', model_path))
cat('\nNext step: Run imputation for missing EIVE values\n')
cat('  Rscript src/Stage_2/bill_verification/impute_eive_no_eive_bill.R\n\n')

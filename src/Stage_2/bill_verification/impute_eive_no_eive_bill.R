#!/usr/bin/env Rscript
#
# EIVE Imputation - NO-EIVE Models Only (Bill's Verification)
#
# Uses NO-EIVE models (excluding 5 EIVE features) for ALL species
# needing imputation (5,756 species: 337 partial + 5,419 zero EIVE).
#
# XGBoost handles missing values natively via learned default directions.
#

suppressPackageStartupMessages({
  library(xgboost)
  library(readr)
  library(dplyr)
  library(jsonlite)
})

# ============================================================================
# CONFIGURATION
# ============================================================================

AXES <- c('L', 'T', 'M', 'N', 'R')
MASTER_PATH <- 'data/shipley_checks/imputation/bill_complete_11711_20251107.csv'
MODEL_DIR <- 'data/shipley_checks/stage2_models'
OUTPUT_DIR <- 'data/shipley_checks/stage2_predictions'

# ============================================================================
# HEADER
# ============================================================================

cat(strrep('=', 80), '\n')
cat('EIVE IMPUTATION - NO-EIVE Models Only (Bill Verification)\n')
cat(strrep('=', 80), '\n')
cat('XGBoost models trained WITHOUT EIVE-related features (5 features excluded)\n')
cat('Missing environmental features handled via XGBoost default directions\n\n')

# ============================================================================
# LOAD MASTER TABLE
# ============================================================================

cat('[1/6] Loading master table...\n')
cat(strrep('-', 80), '\n')

if (!file.exists(MASTER_PATH)) {
  stop('Master table not found: ', MASTER_PATH)
}

df_master <- read_csv(MASTER_PATH, show_col_types = FALSE)
cat(sprintf('✓ Loaded %d species\n', nrow(df_master)))
cat(sprintf('✓ Features: %d columns\n\n', ncol(df_master)))

# ============================================================================
# ANALYZE EIVE MISSINGNESS PATTERNS
# ============================================================================

cat('[2/6] Analyzing EIVE missingness patterns...\n')
cat(strrep('-', 80), '\n')

eive_cols_all <- paste0('EIVEres-', AXES)
eive_count <- rowSums(!is.na(df_master[, eive_cols_all]))

complete <- sum(eive_count == 5)
none <- sum(eive_count == 0)
partial <- nrow(df_master) - complete - none

cat(sprintf('  Complete (5/5 axes): %d (%.1f%%)\n',
            complete, 100 * complete / nrow(df_master)))
cat(sprintf('  None (0/5 axes):     %d (%.1f%%)\n',
            none, 100 * none / nrow(df_master)))
cat(sprintf('  Partial (1-4 axes):  %d (%.1f%%)\n',
            partial, 100 * partial / nrow(df_master)))
cat(sprintf('  → Total to impute:   %d species\n\n', partial + none))

# ============================================================================
# LOAD MODELS AND SCALERS
# ============================================================================

cat('[3/6] Loading NO-EIVE models and scalers...\n')
cat(strrep('-', 80), '\n')

no_eive_models <- list()
no_eive_scalers <- list()

for (axis in AXES) {
  model_path <- file.path(MODEL_DIR, sprintf('xgb_%s_model.json', axis))
  scaler_path <- file.path(MODEL_DIR, sprintf('xgb_%s_scaler.json', axis))

  if (!file.exists(model_path)) {
    stop('Model not found: ', model_path)
  }
  if (!file.exists(scaler_path)) {
    stop('Scaler not found: ', scaler_path)
  }

  # Load model
  model <- xgb.load(model_path)
  no_eive_models[[axis]] <- model

  # Load scaler
  scaler <- read_json(scaler_path)
  scaler$features <- unlist(scaler$features)  # Convert list to character vector
  no_eive_scalers[[axis]] <- scaler

  cat(sprintf('  ✓ %s-axis: model + scaler loaded\n', axis))
}

cat(sprintf('\n✓ All %d models loaded\n\n', length(AXES)))

# ============================================================================
# PREPARE FEATURE MATRIX
# ============================================================================

cat('[4/6] Preparing feature matrix...\n')
cat(strrep('-', 80), '\n')

# Get feature names from first scaler (all should be the same)
feature_names <- no_eive_scalers[[AXES[1]]]$features

# Remove EIVE columns from master table
eive_related <- eive_cols_all
available_cols <- setdiff(names(df_master), eive_related)

cat(sprintf('  Models expect: %d features\n', length(feature_names)))
cat(sprintf('  Available non-EIVE: %d columns\n\n', length(available_cols)))

# ============================================================================
# IMPUTE AXIS BY AXIS
# ============================================================================

cat('[5/6] Running batch imputation...\n')
cat(strrep('-', 80), '\n\n')

imputed_results <- list()
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

for (i in seq_along(AXES)) {
  axis <- AXES[i]
  cat(sprintf('[%d/5] %s-axis:\n', i, axis))
  cat(strrep('-', 60), '\n')

  start_time <- Sys.time()

  # Identify species needing imputation
  target_col <- paste0('EIVEres-', axis)
  observed <- !is.na(df_master[[target_col]])
  missing_species <- df_master[!observed, ]

  n_observed <- sum(observed)
  n_missing <- nrow(missing_species)

  cat(sprintf('  Observed: %d | Missing: %d\n', n_observed, n_missing))

  if (n_missing == 0) {
    cat('  ✓ No missing values - skipping\n\n')
    next
  }

  # Build feature matrix
  X_full <- missing_species[, available_cols, drop = FALSE]

  # Select features that the model expects
  X_model <- X_full[, intersect(feature_names, names(X_full)), drop = FALSE]

  # Report missing value statistics
  na_per_row <- rowSums(is.na(X_model))
  cat(sprintf('  Avg NA: %.0f/%d (%.1f%%) | Max NA: %d\n',
              mean(na_per_row), length(feature_names),
              100 * mean(na_per_row) / length(feature_names),
              max(na_per_row)))

  # Apply scaling
  cat('  Scaling features... ')
  scaler <- no_eive_scalers[[axis]]
  X_scaled <- X_model

  for (j in seq_along(scaler$features)) {
    col_name <- scaler$features[j]
    if (col_name %in% names(X_scaled) && scaler$scale[j] > 0) {
      X_scaled[[col_name]] <- (X_scaled[[col_name]] - scaler$mean[j]) / scaler$scale[j]
    }
  }

  cat('✓\n')

  # Predict
  cat(sprintf('  Predicting %d species... ', n_missing))
  dmatrix <- xgb.DMatrix(data = as.matrix(X_scaled))
  predictions <- predict(no_eive_models[[axis]], dmatrix)

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = 'secs'))
  cat(sprintf('✓ (%.1fs)\n', elapsed))

  # Store results
  result_df <- missing_species %>%
    select(wfo_taxon_id, wfo_scientific_name) %>%
    mutate(
      axis = axis,
      !!paste0(target_col, '_imputed') := predictions,
      source = 'no_eive_imputed'
    )

  imputed_results[[axis]] <- result_df

  # Report statistics
  cat(sprintf('  Prediction range: [%.3f, %.3f]\n',
              min(predictions), max(predictions)))
  cat(sprintf('  Prediction mean: %.3f ± %.3f\n\n',
              mean(predictions), sd(predictions)))
}

# ============================================================================
# SAVE RESULTS
# ============================================================================

cat('[6/6] Saving imputation results...\n')
cat(strrep('-', 80), '\n')

# Combine all axes
all_predictions <- bind_rows(imputed_results)

# Save per-axis predictions
for (axis in AXES) {
  if (!is.null(imputed_results[[axis]])) {
    output_path <- file.path(OUTPUT_DIR,
                            sprintf('%s_predictions_bill_20251107.csv', axis))
    write_csv(imputed_results[[axis]], output_path)
    cat(sprintf('  ✓ %s-axis: %s\n', axis, output_path))
  }
}

# Save combined predictions
combined_path <- file.path(OUTPUT_DIR, 'all_predictions_bill_20251107.csv')
write_csv(all_predictions, combined_path)
cat(sprintf('  ✓ Combined: %s\n', combined_path))

# ============================================================================
# MERGE WITH MASTER TABLE
# ============================================================================

cat('\nMerging predictions with master table...\n')

# Pivot predictions to wide format (one row per species)
predictions_wide <- all_predictions %>%
  select(wfo_taxon_id, axis, matches('_imputed$')) %>%
  tidyr::pivot_wider(
    names_from = axis,
    values_from = matches('_imputed$')
  )

# Merge with master
df_complete <- df_master %>%
  left_join(predictions_wide, by = 'wfo_taxon_id')

# For each axis, coalesce observed and imputed
for (axis in AXES) {
  target_col <- paste0('EIVEres-', axis)
  imputed_col <- paste0(target_col, '_imputed')

  if (imputed_col %in% names(df_complete)) {
    df_complete <- df_complete %>%
      mutate(
        !!paste0(target_col, '_complete') := coalesce(.data[[target_col]], .data[[imputed_col]]),
        !!paste0(target_col, '_source') := ifelse(
          is.na(.data[[target_col]]), 'imputed', 'observed'
        )
      )
  }
}

# Save complete dataset
complete_path <- file.path(OUTPUT_DIR, 'bill_complete_with_eive_20251107.csv')
write_csv(df_complete, complete_path)
cat(sprintf('✓ Complete dataset: %s\n', complete_path))

# ============================================================================
# SUMMARY
# ============================================================================

cat('\n')
cat(strrep('=', 80), '\n')
cat('IMPUTATION COMPLETE\n')
cat(strrep('=', 80), '\n\n')

cat('Statistics:\n')
cat(sprintf('  Total species: %d\n', nrow(df_master)))
cat(sprintf('  Species with complete observed EIVE: %d (%.1f%%)\n',
            complete, 100 * complete / nrow(df_master)))
cat(sprintf('  Species needing imputation: %d (%.1f%%)\n',
            partial + none, 100 * (partial + none) / nrow(df_master)))

cat('\nOutputs:\n')
cat(sprintf('  Per-axis predictions: %s/{L,T,M,N,R}_predictions_bill_20251107.csv\n', OUTPUT_DIR))
cat(sprintf('  Combined predictions: %s\n', combined_path))
cat(sprintf('  Complete dataset: %s\n', complete_path))

cat('\nNext step: Analyze SHAP values for model interpretation\n')
cat('  Rscript src/Stage_2/bill_verification/analyze_shap_bill.R --axis L\n\n')

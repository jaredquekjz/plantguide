suppressPackageStartupMessages({
  library(mixgb)
  library(dplyr)
  library(purrr)
  library(readr)
})

# Parse command-line arguments
args <- commandArgs(trailingOnly = TRUE)
parse_args <- function(args) {
  out <- list()
  for (a in args) {
    if (!grepl('^--[A-Za-z0-9_]+=', a)) next
    kv <- sub('^--', '', a)
    k <- sub('=.*$', '', kv)
    v <- sub('^[^=]*=', '', kv)
    out[[k]] <- v
  }
  out
}

opts <- parse_args(args)
get_opt <- function(name, default) {
  if (!is.null(opts[[name]]) && nzchar(opts[[name]])) {
    opts[[name]]
  } else {
    default
  }
}

input_path <- get_opt('input_csv', 'model_data/inputs/mixgb/mixgb_input_clean_1084_20251023.csv')
output_path <- get_opt('output_csv', 'model_data/inputs/mixgb/mixgb_cv_rmse_clean.csv')
nrounds_val <- as.integer(get_opt('nrounds', '300'))
device_val <- get_opt('device', 'cuda')
eta_val <- as.numeric(get_opt('eta', '0.3'))
folds_val <- as.integer(get_opt('folds', '5'))
traits_val <- get_opt('traits', 'all')

# Production imputation parameters
run_production <- tolower(get_opt('run_production', 'false')) %in% c('true', 't', '1', 'yes')
imputation_m <- as.integer(get_opt('m', '10'))
imputation_seed <- as.integer(get_opt('seed', '20251027'))
output_dir <- get_opt('output_dir', 'model_data/imputed')
output_prefix <- get_opt('output_prefix', 'xgboost_imputed')

# Clean flag - purge previous outputs
clean_previous <- tolower(get_opt('clean', 'false')) %in% c('true', 't', '1', 'yes')

# Perform cleanup if requested
if (clean_previous) {
  message('\n========================================')
  message('CLEAN MODE: Purging previous outputs')
  message('========================================')

  # Clean CV outputs
  cv_files <- c(output_path, sub('\\.csv$', '_predictions.csv', output_path))
  for (f in cv_files) {
    if (file.exists(f)) {
      file.remove(f)
      message('Removed: ', f)
    }
  }

  # Clean production outputs
  if (run_production && dir.exists(output_dir)) {
    output_base <- file.path(output_dir, output_prefix)
    prod_files <- c(
      sprintf('%s_m%d.csv', output_base, 1:imputation_m),
      paste0(output_base, '_mean.csv')
    )
    for (f in prod_files) {
      if (file.exists(f)) {
        file.remove(f)
        message('Removed: ', f)
      }
    }
  }

  message('Cleanup complete\n')
}

message('CV Parameters:')
message('  Input: ', input_path)
message('  Output: ', output_path)
message('  nrounds: ', nrounds_val)
message('  eta: ', eta_val)
message('  device: ', device_val)
message('  folds: ', folds_val)
message('  traits: ', traits_val)
if (run_production) {
  message('\nProduction Imputation: ENABLED')
  message('  m: ', imputation_m)
  message('  seed: ', imputation_seed)
  message('  output_dir: ', output_dir)
  message('  output_prefix: ', output_prefix)
}

mix_data <- readr::read_csv(input_path, show_col_types = FALSE)
message('Loaded input with ', nrow(mix_data), ' rows and ', ncol(mix_data), ' columns')

id_cols <- c('wfo_taxon_id', 'wfo_scientific_name')
drop_predictors <- c('leaf_area_source', 'nmass_source', 'ldmc_source', 'lma_source',
                     'height_source', 'seed_mass_source', 'sla_source',
                     'try_parasitism', 'try_carnivory', 'try_succulence',
                     'accepted_name', 'accepted_norm', 'accepted_wfo_id',
                     'duke_files', 'duke_original_names', 'duke_matched_names', 'duke_scientific_names',
                     'eive_taxon_concepts', 'try_source_species',
                     'genus', 'family', 'try_genus', 'try_family')

keep_cats <- c('try_woodiness', 'try_growth_form', 'try_habitat_adaptation', 'try_leaf_type')
for (col in intersect(keep_cats, names(mix_data))) {
  mix_data[[col]] <- as.factor(mix_data[[col]])
}

feature_cols_base <- setdiff(names(mix_data), c(id_cols, drop_predictors))

prepare_features <- function(df) {
  feat <- df[, feature_cols_base, drop = FALSE]

  # Drop all-NA and constant columns
  all_na_cols <- names(feat)[colSums(!is.na(feat)) == 0]
  if (length(all_na_cols) > 0) {
    feat <- feat[, !names(feat) %in% all_na_cols, drop = FALSE]
  }

  const_cols <- names(feat)[sapply(feat, function(col) {
    vals <- unique(col[!is.na(col)])
    length(vals) <= 1
  })]
  if (length(const_cols) > 0) {
    feat <- feat[, !names(feat) %in% const_cols, drop = FALSE]
  }

  # Convert remaining characters to factors
  char_cols <- map_lgl(feat, is.character)
  if (any(char_cols)) {
    feat[char_cols] <- lapply(feat[char_cols], factor)
  }

  # Drop high-cardinality categoricals
  high_card <- names(feat)[sapply(feat, function(col) {
    if (is.factor(col)) {
      nlevels(col) > 50
    } else {
      FALSE
    }
  })]
  if (length(high_card) > 0) {
    feat <- feat[, !names(feat) %in% high_card, drop = FALSE]
  }

  feat
}

# IMPUTE LOG TRAITS DIRECTLY: More statistically sound for XGBoost learning
# Log traits are already normalized and more normally distributed
# Other log traits are included as predictors (leverages trait correlations)
trait_info_all <- tibble::tibble(
  trait = c('logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM'),
  transform = c('none', 'none', 'none', 'none', 'none', 'none')
)

# Filter traits if specified
if (traits_val != 'all') {
  requested_traits <- strsplit(traits_val, ',')[[1]]
  trait_info <- trait_info_all[trait_info_all$trait %in% requested_traits, ]
  if (nrow(trait_info) == 0) {
    stop('No valid traits found. Requested: ', traits_val)
  }
  message('Evaluating ', nrow(trait_info), ' trait(s): ', paste(trait_info$trait, collapse=', '))
} else {
  trait_info <- trait_info_all
}

logit <- function(x, eps = 1e-06) {
  x <- pmin(pmax(x, eps), 1 - eps)
  log(x / (1 - x))
}

apply_transform <- function(x, type) {
  if (type == 'log') {
    if (any(x <= 0, na.rm = TRUE)) warning('Non-positive values encountered in log transform; coercing to NA.')
    return(log(x))
  }
  if (type == 'logit') {
    return(logit(x))
  }
  x
}

set.seed(20251022)
K <- folds_val
results <- list()
all_predictions <- list()
cv_start <- Sys.time()

# Progress tracking with forced output
n_traits <- nrow(trait_info)
total_folds <- n_traits * K
cat(sprintf("\n========================================\n"))
cat(sprintf("Starting XGBoost %d-Fold CV\n", K))
cat(sprintf("Traits: %d | Total folds: %d\n", n_traits, total_folds))
cat(sprintf("Started: %s\n", format(cv_start, "%Y-%m-%d %H:%M:%S")))
cat(sprintf("========================================\n\n"))
flush.console()

fold_counter <- 0

for (i in seq_len(nrow(trait_info))) {
  trait <- trait_info$trait[i]
  transform_type <- trait_info$transform[i]

  cat(sprintf("[%d/%d] Trait: %s | ", i, n_traits, trait))
  flush.console()

  observed_idx <- which(!is.na(mix_data[[trait]]))
  if (length(observed_idx) < K) {
    warning('Trait ', trait, ' has fewer than ', K, ' observed values; skipping.')
    next
  }
  fold_ids <- sample(rep(seq_len(K), length.out = length(observed_idx)))
  errors <- c()

  cat(sprintf("%d obs | ", length(observed_idx)))
  flush.console()

  for (fold in seq_len(K)) {
    fold_counter <- fold_counter + 1
    fold_start <- Sys.time()

    test_local_idx <- observed_idx[fold_ids == fold]
    train_local_idx <- setdiff(observed_idx, test_local_idx)

    df_fold <- mix_data
    df_fold[[trait]][test_local_idx] <- NA_real_

    feature_data <- prepare_features(df_fold)

    fit <- mixgb(feature_data,
                 m = 1,
                 nrounds = nrounds_val,
                 pmm.type = 2,
                 pmm.k = 4,
                 xgb.params = list(device = device_val, tree_method = 'hist', eta = eta_val),
                 verbose = 1)

    imputed <- fit[[1]]
    preds <- imputed[[trait]][test_local_idx]
    actual <- mix_data[[trait]][test_local_idx]

    valid <- is.finite(preds) & is.finite(actual)
    preds <- preds[valid]
    actual <- actual[valid]

    if (length(preds) == 0) next

    preds_t <- apply_transform(preds, transform_type)
    actual_t <- apply_transform(actual, transform_type)
    err <- preds_t - actual_t
    rmse_fold <- sqrt(mean(err^2, na.rm = TRUE))
    errors <- c(errors, rmse_fold)

    # Store predictions for R² calculation
    for (j in seq_along(test_local_idx)) {
      all_predictions[[length(all_predictions) + 1]] <- list(
        trait = trait,
        fold = fold,
        y_obs = actual[j],
        y_pred = preds[j],
        y_obs_transformed = actual_t[j],
        y_pred_transformed = preds_t[j]
      )
    }

    fold_elapsed <- as.numeric(difftime(Sys.time(), fold_start, units = 'secs'))
    overall_elapsed <- as.numeric(difftime(Sys.time(), cv_start, units = 'mins'))

    cat(sprintf("F%d:%.3f[%.0fs] ", fold, rmse_fold, fold_elapsed))
    flush.console()
  }

  cat(sprintf("✓ Mean RMSE: %.4f (±%.4f)\n", mean(errors), sd(errors)))
  flush.console()

  results[[trait]] <- data.frame(trait = trait,
                                rmse_mean = mean(errors),
                                rmse_median = median(errors),
                                rmse_sd = stats::sd(errors),
                                folds = length(errors))
}

cv_elapsed <- as.numeric(difftime(Sys.time(), cv_start, units = 'mins'))
result_df <- dplyr::bind_rows(results)
result_df$nrounds <- nrounds_val
result_df$eta <- eta_val

# Calculate R² for each trait from stored predictions
predictions_df <- do.call(rbind, lapply(all_predictions, as.data.frame))

# Calculate R² on transformed scale (log/logit - same scale as RMSE)
r2_results <- predictions_df %>%
  group_by(trait) %>%
  summarise(
    # R² on transformed scale (matches RMSE scale)
    r2_transformed = 1 - sum((y_obs_transformed - y_pred_transformed)^2) /
                         sum((y_obs_transformed - mean(y_obs_transformed))^2),
    # R² on original scale (for interpretability)
    r2_original = 1 - sum((y_obs - y_pred)^2) /
                      sum((y_obs - mean(y_obs))^2),
    n_obs = n(),
    .groups = 'drop'
  )

# Merge R² into results
result_df <- result_df %>%
  left_join(r2_results, by = 'trait')

# Reorder columns for clarity
result_df <- result_df %>%
  select(trait, rmse_mean, rmse_median, rmse_sd, r2_transformed, r2_original,
         folds, n_obs, nrounds, eta)

print(result_df)
readr::write_csv(result_df, output_path)
message('Saved CV RMSE + R² summary to ', output_path)
message('Total CV time: ', signif(cv_elapsed, 3), ' minutes')

# Save predictions for additional analysis
predictions_path <- sub('\\.csv$', '_predictions.csv', output_path)
readr::write_csv(predictions_df, predictions_path)
message('Saved CV predictions to ', predictions_path)

# ============================================================================
# PRODUCTION IMPUTATION (Optional)
# ============================================================================
if (run_production) {
  message('\n========================================')
  message('Starting Production Imputation')
  message('========================================')

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    message('Created output directory: ', output_dir)
  }

  output_base <- file.path(output_dir, output_prefix)

  # Get log trait columns present in dataset
  log_traits <- c('logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM')
  present_log_traits <- intersect(log_traits, names(mix_data))

  if (length(present_log_traits) == 0) {
    message('WARNING: No log traits found in dataset. Skipping production imputation.')
  } else {
    message('Log traits to impute: ', paste(present_log_traits, collapse=', '))

    # Report missingness for each trait
    for (trait in present_log_traits) {
      n_obs <- sum(!is.na(mix_data[[trait]]))
      n_missing <- sum(is.na(mix_data[[trait]]))
      pct_obs <- 100 * n_obs / nrow(mix_data)
      message(sprintf('  %s: %d obs (%.1f%%), %d missing (%.1f%%)',
                     trait, n_obs, pct_obs, n_missing, 100 - pct_obs))
    }

    # Prepare features for production imputation
    feature_data <- prepare_features(mix_data)
    id_data <- mix_data %>% select(all_of(id_cols))

    # Run M imputations
    imputed_list <- vector('list', imputation_m)
    production_start <- Sys.time()

    for (i in seq_len(imputation_m)) {
      run_seed <- imputation_seed + i - 1L
      message('')
      message(sprintf('[%d/%d] Running imputation (seed=%d)', i, imputation_m, run_seed))
      run_start <- Sys.time()
      set.seed(run_seed)

      fit <- mixgb(feature_data,
                   m = 1,
                   nrounds = nrounds_val,
                   pmm.type = 2,
                   pmm.k = 4,
                   xgb.params = list(device = device_val, tree_method = 'hist', eta = eta_val),
                   verbose = 1)

      fit_df <- as.data.frame(fit[[1]])
      imputed_list[[i]] <- fit_df
      elapsed_min <- as.numeric(difftime(Sys.time(), run_start, units = 'mins'))
      message(sprintf('[%d/%d] Completed in %.2f min', i, imputation_m, elapsed_min))

      # Save individual imputation
      imp_df <- cbind(id_data, fit_df)
      imp_path <- sprintf('%s_m%d.csv', output_base, i)
      readr::write_csv(imp_df, imp_path)
      message(sprintf('[%d/%d] Saved to %s', i, imputation_m, basename(imp_path)))
    }

    # Compute and save mean of all imputations (for log traits only)
    summary_df <- Reduce(`+`, lapply(imputed_list, function(df) df[, present_log_traits, drop = FALSE])) / imputation_m
    summary_df <- cbind(id_data, summary_df)
    mean_path <- paste0(output_base, '_mean.csv')
    readr::write_csv(summary_df, mean_path)
    message('Saved mean imputation to ', basename(mean_path))

    production_elapsed <- as.numeric(difftime(Sys.time(), production_start, units = 'mins'))
    message(sprintf('Production imputation completed in %.2f min', production_elapsed))
    message('All outputs written to: ', output_dir)
  }
}

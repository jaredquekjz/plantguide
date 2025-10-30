#!/usr/bin/env Rscript
suppressPackageStartupMessages({
  library(mixgb)
  library(dplyr)
  library(purrr)
  library(readr)
  library(arrow)
})

options(stringsAsFactors = FALSE)
options(warn = 1)

log_info <- function(fmt, ...) {
  msg <- sprintf(fmt, ...)
  cat(msg, "\n", sep = "", file = stdout())
  flush.console()
}

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

# Configuration (with defaults)
input_path <- get_opt('input_csv', 'model_data/inputs/mixgb_experimental_11targets/mixgb_input_11targets_11680_20251029.csv')
cv_output_dir <- get_opt('cv_output_dir', 'results/experiments/experimental_11targets_20251029')
prod_output_dir <- get_opt('prod_output_dir', 'model_data/outputs/experimental_11targets_20251029')
prod_output_prefix <- get_opt('prod_output_prefix', 'experimental_11targets')
clean_previous <- tolower(get_opt('clean', 'false')) %in% c('true', 't', '1', 'yes')

# Hyperparameters
nrounds_value <- as.integer(get_opt('nrounds', '3000'))
eta_value <- as.numeric(get_opt('eta', '0.025'))
pmm_type_value <- as.integer(get_opt('pmm_type', '2'))
pmm_k_value <- as.integer(get_opt('pmm_k', '4'))
device_value <- get_opt('device', 'cuda')
cv_folds <- as.integer(get_opt('folds', '10'))
prod_imputations <- as.integer(get_opt('m', '10'))
seed_base <- as.integer(get_opt('seed', '20251029'))

# Clean previous outputs if requested
if (clean_previous) {
  log_info('Cleaning previous outputs...')
  if (dir.exists(cv_output_dir)) {
    unlink(cv_output_dir, recursive = TRUE)
    log_info('  ✓ Removed: %s', cv_output_dir)
  }
  if (dir.exists(prod_output_dir)) {
    unlink(prod_output_dir, recursive = TRUE)
    log_info('  ✓ Removed: %s', prod_output_dir)
  }
  log_info('')
}

# Create output directories
dir.create(cv_output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(prod_output_dir, recursive = TRUE, showWarnings = FALSE)

log_info('================================================================================')
log_info('EXPERIMENTAL 11-TARGET JOINT IMPUTATION')
log_info('================================================================================')
log_info('Joint imputation: 6 log traits + 5 EIVE axes')
log_info('')
log_info('Configuration:')
log_info('  Input: %s', input_path)
log_info('  nrounds: %d', nrounds_value)
log_info('  eta: %g', eta_value)
log_info('  device: %s', device_value)
log_info('  CV folds: %d', cv_folds)
log_info('  Production imputations: %d', prod_imputations)
log_info('')

# Load data
log_info('[1/3] Loading dataset...')
mix_data <- readr::read_csv(input_path, show_col_types = FALSE)
log_info('   Loaded: %d rows × %d columns', nrow(mix_data), ncol(mix_data))
log_info('')

# Define columns
id_cols <- c('wfo_taxon_id', 'wfo_scientific_name')

# CRITICAL: 11 targets (6 log traits + 5 EIVE axes)
target_vars <- c('logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM',
                 'EIVEres-L', 'EIVEres-T', 'EIVEres-M', 'EIVEres-N', 'EIVEres-R')

drop_predictors <- c('leaf_area_source', 'nmass_source', 'ldmc_source', 'lma_source',
                     'height_source', 'seed_mass_source', 'sla_source',
                     'try_parasitism', 'try_carnivory', 'try_succulence',
                     'accepted_name', 'accepted_norm', 'accepted_wfo_id',
                     'duke_files', 'duke_original_names', 'duke_matched_names', 'duke_scientific_names',
                     'eive_taxon_concepts', 'try_source_species',
                     'genus', 'family', 'try_genus', 'try_family')

keep_cats <- c('try_woodiness', 'try_growth_form', 'try_habitat_adaptation', 'try_leaf_type',
               'try_leaf_phenology', 'try_photosynthesis_pathway', 'try_mycorrhiza_type')

for (col in intersect(keep_cats, names(mix_data))) {
  mix_data[[col]] <- as.factor(mix_data[[col]])
}

feature_cols <- setdiff(names(mix_data), c(id_cols, drop_predictors))
id_data <- mix_data %>% select(all_of(id_cols))

log_info('Feature preparation:')
log_info('  Total columns: %d', ncol(mix_data))
log_info('  ID columns: %d', length(id_cols))
log_info('  Target traits: %d', length(target_vars))
log_info('  Feature columns: %d', length(feature_cols))
log_info('')

# Check target missingness
log_info('Target missingness:')
present_targets <- intersect(target_vars, names(mix_data))
for (trait in present_targets) {
  n_obs <- sum(!is.na(mix_data[[trait]]))
  pct <- 100 * n_obs / nrow(mix_data)
  log_info('  %s: %d obs (%.1f%%)', trait, n_obs, pct)
}
log_info('')

prepare_features <- function(df) {
  feat <- df[, feature_cols, drop = FALSE]

  # Drop all-NA columns
  all_na_cols <- names(feat)[colSums(!is.na(feat)) == 0]
  if (length(all_na_cols) > 0) {
    feat <- feat[, !names(feat) %in% all_na_cols, drop = FALSE]
  }

  # Drop constant columns
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

################################################################################
# PHASE 1: CROSS-VALIDATION (10-FOLD)
################################################################################

log_info('[2/3] Running 10-fold cross-validation...')
log_info('')

set.seed(seed_base)
K <- cv_folds
results <- list()
all_predictions <- list()
cv_start <- Sys.time()

n_traits <- length(present_targets)
total_folds <- n_traits * K
cat(sprintf("========================================\n"))
cat(sprintf("Starting %d-Fold CV on %d targets\n", K, n_traits))
cat(sprintf("Total folds: %d | Started: %s\n", total_folds, format(cv_start, "%Y-%m-%d %H:%M:%S")))
cat(sprintf("========================================\n\n"))
flush.console()

fold_counter <- 0

for (i in seq_len(n_traits)) {
  trait <- present_targets[i]

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
                 nrounds = nrounds_value,
                 pmm.type = pmm_type_value,
                 pmm.k = pmm_k_value,
                 xgb.params = list(device = device_value, tree_method = 'hist', eta = eta_value),
                 verbose = 1)

    imputed <- fit[[1]]
    preds <- imputed[[trait]][test_local_idx]
    actual <- mix_data[[trait]][test_local_idx]

    valid <- is.finite(preds) & is.finite(actual)
    preds <- preds[valid]
    actual <- actual[valid]

    if (length(preds) == 0) next

    err <- preds - actual
    rmse_fold <- sqrt(mean(err^2, na.rm = TRUE))
    errors <- c(errors, rmse_fold)

    # Store predictions for R² calculation
    for (j in seq_along(test_local_idx)) {
      all_predictions[[length(all_predictions) + 1]] <- list(
        trait = trait,
        fold = fold,
        y_obs = actual[j],
        y_pred = preds[j]
      )
    }

    fold_elapsed <- as.numeric(difftime(Sys.time(), fold_start, units = 'secs'))

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
result_df$nrounds <- nrounds_value
result_df$eta <- eta_value

# Calculate R² for each trait
predictions_df <- do.call(rbind, lapply(all_predictions, as.data.frame))

r2_results <- predictions_df %>%
  group_by(trait) %>%
  summarise(
    r2 = 1 - sum((y_obs - y_pred)^2) / sum((y_obs - mean(y_obs))^2),
    n_obs = n(),
    .groups = 'drop'
  )

result_df <- result_df %>%
  left_join(r2_results, by = 'trait') %>%
  select(trait, rmse_mean, rmse_median, rmse_sd, r2, folds, n_obs, nrounds, eta)

print(result_df)

# Save CV outputs
cv_results_path <- file.path(cv_output_dir, 'cv_10fold_11targets_20251029.csv')
readr::write_csv(result_df, cv_results_path)
log_info('✓ Saved CV results: %s', cv_results_path)

predictions_path <- file.path(cv_output_dir, 'cv_10fold_11targets_20251029_predictions.csv')
readr::write_csv(predictions_df, predictions_path)
log_info('✓ Saved CV predictions: %s', predictions_path)

# Save summary
summary_path <- file.path(cv_output_dir, 'cv_10fold_11targets_20251029_summary.txt')
sink(summary_path)
cat("Experimental 11-Target CV Summary\n")
cat("==================================\n\n")
cat(sprintf("Date: %s\n", Sys.Date()))
cat(sprintf("Dataset: %s\n", input_path))
cat(sprintf("Species: %d\n", nrow(mix_data)))
cat(sprintf("Targets: %d (6 traits + 5 EIVE)\n", length(present_targets)))
cat(sprintf("CV folds: %d\n", cv_folds))
cat(sprintf("nrounds: %d\n", nrounds_value))
cat(sprintf("eta: %g\n", eta_value))
cat(sprintf("Runtime: %.1f minutes\n\n", cv_elapsed))
cat("Results:\n")
print(result_df)
sink()
log_info('✓ Saved CV summary: %s', summary_path)

log_info('CV Phase Complete: %.1f minutes', cv_elapsed)
log_info('')

################################################################################
# PHASE 2: PRODUCTION IMPUTATION (10 RUNS)
################################################################################

log_info('[3/3] Running production imputation (%d runs)...', prod_imputations)
log_info('')

output_base <- file.path(prod_output_dir, prod_output_prefix)

feature_data_prod <- prepare_features(mix_data)
imputed_list <- vector('list', prod_imputations)
prod_start <- Sys.time()

for (i in seq_len(prod_imputations)) {
  run_seed <- seed_base + i - 1L
  log_info('')
  log_info(strrep('=', 70))
  log_info('[PRODUCTION] Imputation %d/%d (seed=%d)', i, prod_imputations, run_seed)
  log_info(strrep('=', 70))
  run_start <- Sys.time()
  set.seed(run_seed)

  fit <- mixgb(feature_data_prod,
               m = 1,
               nrounds = nrounds_value,
               pmm.type = pmm_type_value,
               pmm.k = pmm_k_value,
               xgb.params = list(device = device_value, tree_method = 'hist', eta = eta_value),
               verbose = 1)

  fit_df <- as.data.frame(fit[[1]])
  imputed_list[[i]] <- fit_df
  elapsed_min <- as.numeric(difftime(Sys.time(), run_start, units = 'mins'))
  log_info('[PRODUCTION] (%d/%d) completed in %.2f min', i, prod_imputations, elapsed_min)

  imp_df <- cbind(id_data, fit_df)
  imp_path_csv <- sprintf('%s_m%d.csv', output_base, i)
  imp_path_parquet <- sprintf('%s_m%d.parquet', output_base, i)
  readr::write_csv(imp_df, imp_path_csv)
  arrow::write_parquet(imp_df, imp_path_parquet)
  log_info('[PRODUCTION] (%d/%d) saved: %s_m%d.{csv,parquet}', i, prod_imputations, prod_output_prefix, i)
}

# Create mean imputation
summary_df <- Reduce(`+`, lapply(imputed_list, function(df) df[, target_vars, drop = FALSE])) / prod_imputations
summary_df <- cbind(id_data, summary_df)
readr::write_csv(summary_df, paste0(output_base, '_mean.csv'))
arrow::write_parquet(summary_df, paste0(output_base, '_mean.parquet'))
log_info('[PRODUCTION] Wrote mean imputation')

prod_elapsed <- as.numeric(difftime(Sys.time(), prod_start, units = 'mins'))
total_elapsed <- as.numeric(difftime(Sys.time(), cv_start, units = 'mins'))

log_info('')
log_info('================================================================================')
log_info('EXPERIMENTAL 11-TARGET IMPUTATION COMPLETE')
log_info('================================================================================')
log_info('')
log_info('Runtime:')
log_info('  CV (%d-fold): %.1f minutes', cv_folds, cv_elapsed)
log_info('  Production (%d runs): %.1f minutes', prod_imputations, prod_elapsed)
log_info('  Total: %.1f minutes (%.1f hours)', total_elapsed, total_elapsed / 60)
log_info('')
log_info('Outputs:')
log_info('  CV results: %s', cv_output_dir)
log_info('  Production: %s', prod_output_dir)
log_info('  PRODUCTION OUTPUT: %s_mean.csv', output_base)
log_info('')

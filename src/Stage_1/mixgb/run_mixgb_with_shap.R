suppressPackageStartupMessages({
  library(mixgb)
  library(dplyr)
  library(purrr)
  library(readr)
  library(xgboost)
  if (!requireNamespace('arrow', quietly = TRUE)) {
    install.packages('arrow', repos = 'https://cran.rstudio.com')
  }
  library(arrow)
})

options(stringsAsFactors = FALSE)
options(warn = 1)

log_info <- function(fmt, ...) {
  msg <- sprintf(fmt, ...)
  cat(msg, "\n", sep = "", file = stdout())
  flush.console()
}

parse_args <- function(args) {
  out <- list()
  for (a in args) {
    if (!grepl('^--[A-Za-z0-9_]+=', a)) next
    kv <- sub('^--', '', a)
    key <- sub('=.*$', '', kv)
    val <- sub('^[^=]*=', '', kv)
    out[[key]] <- val
  }
  out
}

args <- commandArgs(trailingOnly = TRUE)
opts <- parse_args(args)
get_opt <- function(name, default) {
  if (!is.null(opts[[name]]) && nzchar(opts[[name]])) {
    opts[[name]]
  } else {
    default
  }
}

log_info('Loaded packages')
input_path <- get_opt('input_csv', 'model_data/inputs/mixgb/mixgb_input_20251022.csv')
output_dir <- get_opt('output_dir', 'model_data/inputs/mixgb')
output_prefix <- get_opt('output_prefix', 'mixgb_imputed_20251022')
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
output_base <- file.path(output_dir, output_prefix)

seed_value <- as.integer(get_opt('seed', '20251022'))
imputation_runs <- as.integer(get_opt('m', '10'))
nrounds_value <- as.integer(get_opt('nrounds', '300'))
pmm_type_value <- as.integer(get_opt('pmm_type', '2'))
pmm_k_value <- as.integer(get_opt('pmm_k', '4'))
device_value <- tolower(get_opt('device', 'cuda'))
eta_value <- as.numeric(get_opt('eta', '0.3'))

# SHAP computation parameters
compute_shap <- tolower(get_opt('compute_shap', 'true')) %in% c('true', 't', '1', 'yes')
shap_output_dir <- get_opt('shap_output_dir', file.path(output_dir, 'shap'))
if (compute_shap && !dir.exists(shap_output_dir)) {
  dir.create(shap_output_dir, recursive = TRUE)
  log_info('Created SHAP output directory: %s', shap_output_dir)
}

# Model saving parameters (required for SHAP)
save_models_folder <- get_opt('save_models_folder', 'model_data/models/mixgb_saved')
if (!dir.exists(save_models_folder)) {
  dir.create(save_models_folder, recursive = TRUE)
  log_info('Created model saving directory: %s', save_models_folder)
}

mix_data <- readr::read_csv(input_path, show_col_types = FALSE)
log_info('Input rows: %d, columns: %d', nrow(mix_data), ncol(mix_data))

# CANONICAL SLA: Use sla_mm2_mg (not lma_g_m2) to match BHPMF and Stage 2
target_vars <- c('leaf_area_mm2', 'nmass_mg_g', 'ldmc_frac', 'sla_mm2_mg', 'plant_height_m', 'seed_mass_mg')

id_cols <- c('wfo_taxon_id', 'wfo_scientific_name')

drop_predictors <- c('leaf_area_source', 'nmass_source', 'ldmc_source', 'lma_source',
                     'height_source', 'seed_mass_source', 'sla_source',
                     'try_parasitism', 'try_carnivory', 'try_succulence',
                     'accepted_name', 'accepted_norm', 'accepted_wfo_id',
                     'duke_files', 'duke_original_names', 'duke_matched_names', 'duke_scientific_names',
                     'eive_taxon_concepts', 'try_source_species',
                     'genus', 'family', 'try_genus', 'try_family')

# Updated: 7 categorical features (added phenology, photosynthesis, mycorrhiza)
keep_cats <- c('try_woodiness', 'try_growth_form', 'try_habitat_adaptation',
               'try_leaf_type', 'try_leaf_phenology', 'try_photosynthesis_pathway',
               'try_mycorrhiza_type')

for (col in intersect(keep_cats, names(mix_data))) {
  mix_data[[col]] <- as.factor(mix_data[[col]])
}

feature_cols <- setdiff(names(mix_data), c(id_cols, drop_predictors))
feature_data <- mix_data %>% select(all_of(feature_cols))
id_data <- mix_data %>% select(all_of(id_cols))

log_info('Feature preparation:')
log_info('  Total columns: %d', ncol(mix_data))
log_info('  ID columns: %d', length(id_cols))
log_info('  Dropped columns: %d', length(intersect(drop_predictors, names(mix_data))))
log_info('  Feature columns: %d', length(feature_cols))

# Check target traits present
missing_targets <- setdiff(target_vars, names(feature_data))
if (length(missing_targets) > 0) {
  log_info('WARNING: Missing target traits: %s', paste(missing_targets, collapse=', '))
}
present_targets <- intersect(target_vars, names(feature_data))
log_info('Target traits present: %d/%d', length(present_targets), length(target_vars))
for (trait in present_targets) {
  n_obs <- sum(!is.na(feature_data[[trait]]))
  pct <- 100 * n_obs / nrow(feature_data)
  log_info('  %s: %d obs (%.1f%%)', trait, n_obs, pct)
}

# Check categorical features
cat_present <- intersect(keep_cats, names(feature_data))
log_info('Categorical features present: %d/%d', length(cat_present), length(keep_cats))
for (cat_col in cat_present) {
  n_obs <- sum(!is.na(feature_data[[cat_col]]))
  n_levels <- nlevels(feature_data[[cat_col]])
  pct <- 100 * n_obs / nrow(feature_data)
  log_info('  %s: %d obs (%.1f%%), %d levels', cat_col, n_obs, pct, n_levels)
}

# Check environmental features
env_cols <- grep('_q50$', names(feature_data), value = TRUE)
log_info('Environmental q50 features: %d', length(env_cols))

all_na_cols <- names(feature_data)[colSums(!is.na(feature_data)) == 0]
if (length(all_na_cols) > 0) {
  log_info('Dropping %d all-NA feature(s): %s', length(all_na_cols), paste(all_na_cols, collapse = ', '))
  feature_data <- feature_data %>% select(-all_of(all_na_cols))
}

char_cols <- purrr::map_lgl(feature_data, is.character)
if (any(char_cols)) {
  feature_data[char_cols] <- lapply(feature_data[char_cols], factor)
}

# Store original feature data BEFORE dropping constants (needed for SHAP)
original_feature_data_with_constants <- feature_data

const_cols <- names(feature_data)[sapply(feature_data, function(col) {
  vals <- unique(col[!is.na(col)])
  length(vals) <= 1L
})]
if (length(const_cols) > 0) {
  log_info('Dropping %d constant feature(s): %s', length(const_cols), paste(const_cols, collapse = ', '))
  feature_data <- feature_data %>% select(-all_of(const_cols))
}

high_card_cols <- names(feature_data)[sapply(feature_data, function(col) {
  if (is.factor(col)) {
    nlevels(col) > 50
  } else {
    FALSE
  }
})]
if (length(high_card_cols) > 0) {
  log_info('Dropping %d high-cardinality categorical feature(s): %s', length(high_card_cols), paste(high_card_cols, collapse = ', '))
  feature_data <- feature_data %>% select(-all_of(high_card_cols))
}

M <- imputation_runs
imputed_list <- vector('list', M)
warning_lines <- character()
overall_start <- Sys.time()

log_info('[mixgb] Starting %d imputations (device=%s, compute_shap=%s)', M, device_value, compute_shap)

for (i in seq_len(M)) {
  run_seed <- seed_value + i - 1L
  log_info('')
  log_info(strrep('=', 70))
  log_info('[mixgb] IMPUTATION %d/%d (seed=%d)', i, M, run_seed)
  log_info(strrep('=', 70))
  run_start <- Sys.time()
  set.seed(run_seed)
  run_warnings <- character()

  # Build xgb.params
  xgb_params <- list(device = device_value, tree_method = 'hist', eta = eta_value)

  # Build mixgb call arguments with model saving enabled
  mixgb_args <- list(
    data = feature_data,
    m = 1,
    nrounds = nrounds_value,
    pmm.type = pmm_type_value,
    pmm.k = pmm_k_value,
    xgb.params = xgb_params,
    save.models = TRUE,
    save.models.folder = save_models_folder,
    verbose = 1
  )

  fit <- withCallingHandlers(
    do.call(mixgb, mixgb_args),
    warning = function(w) {
      run_warnings <<- c(run_warnings, conditionMessage(w))
      invokeRestart('muffleWarning')
    }
  )

  if (length(run_warnings) > 0) {
    tag <- sprintf('[imputation %d]', i)
    warning_lines <- c(warning_lines, paste(tag, unique(run_warnings)))
  }

  fit_df <- as.data.frame(fit[[1]])
  imputed_list[[i]] <- fit_df
  elapsed_min <- as.numeric(difftime(Sys.time(), run_start, units = 'mins'))
  log_info('[mixgb] (%d/%d) completed in %.2f min', i, M, elapsed_min)

  # Save imputed data
  imp_df <- cbind(id_data, fit_df)
  imp_path_csv <- sprintf('%s_m%d.csv', output_base, i)
  imp_path_parquet <- sprintf('%s_m%d.parquet', output_base, i)
  readr::write_csv(imp_df, imp_path_csv)
  arrow::write_parquet(imp_df, imp_path_parquet)
  log_info('[mixgb] (%d/%d) wrote %s_m%d.csv/parquet', i, M, output_prefix, i)

  # Compute and save SHAP values
  if (compute_shap) {
    log_info('[SHAP] Computing SHAP values for imputation %d', i)
    shap_start <- Sys.time()

    # mixgb saves models with pattern: xgb.model.<variable_name><imputation_number>.json
    # e.g., xgb.model.leaf_area_mm21.json for imputation 1
    # Find all target trait models for this imputation
    target_pattern <- sprintf('xgb\\.model\\.(%s)%d\\.json',
                              paste(target_vars, collapse='|'), i)
    model_files <- list.files(save_models_folder, pattern = target_pattern, full.names = TRUE)

    if (length(model_files) > 0) {
      log_info('[SHAP] Found %d target trait models for imputation %d', length(model_files), i)

      # For each target trait model, compute SHAP values
      for (model_file in model_files) {
        # Extract trait name from filename (e.g., "xgb.model.leaf_area_mm21.json" -> "leaf_area_mm2")
        basename_file <- basename(model_file)
        trait_name <- sub(sprintf('^xgb\\.model\\.(.*)%d\\.json$', i), '\\1', basename_file)

        if (trait_name %in% target_vars) {
          log_info('[SHAP] Computing SHAP for %s (imputation %d)', trait_name, i)

          tryCatch({
            # Load the model
            model <- xgb.load(model_file)

            # Use ORIGINAL data WITH CONSTANTS (before dropping them) for SHAP computation
            # This ensures feature dimensions match exactly what model was trained on
            # Remove the target trait being predicted (it was the response variable)
            pred_data <- original_feature_data_with_constants %>% select(-all_of(trait_name))

            # Convert factors to numeric codes (xgboost's internal encoding)
            pred_data_numeric <- pred_data
            for (col_name in names(pred_data_numeric)) {
              if (is.factor(pred_data_numeric[[col_name]])) {
                pred_data_numeric[[col_name]] <- as.numeric(pred_data_numeric[[col_name]]) - 1  # 0-indexed
              }
            }

            # Create DMatrix
            pred_dmatrix <- xgb.DMatrix(data = as.matrix(pred_data_numeric))

            # Compute SHAP values using predcontrib
            shap_values <- predict(model, pred_dmatrix, predcontrib = TRUE)

            # Convert to data frame
            shap_df <- as.data.frame(shap_values)
            # Assign column names manually to avoid issues
            if (ncol(shap_df) == ncol(pred_data) + 1) {
              # Last column is BIAS
              colnames(shap_df) <- c(names(pred_data), "BIAS")
            }
            shap_df <- cbind(id_data, trait = trait_name, shap_df)

            # Save SHAP values
            shap_path <- file.path(shap_output_dir, sprintf('%s_shap_m%d_%s.parquet', output_prefix, i, trait_name))
            arrow::write_parquet(shap_df, shap_path)
            log_info('[SHAP] Saved SHAP values for %s: %d rows, %d columns', trait_name, nrow(shap_df), ncol(shap_df))
          }, error = function(e) {
            log_info('[SHAP] ERROR computing SHAP for %s: %s', trait_name, e$message)
          })
        }
      }

      shap_elapsed <- as.numeric(difftime(Sys.time(), shap_start, units = 'mins'))
      log_info('[SHAP] (%d/%d) SHAP computation completed in %.2f min', i, M, shap_elapsed)
    } else {
      log_info('[SHAP] WARNING: No target trait models found for imputation %d in %s', i, save_models_folder)
      log_info('[SHAP] Pattern searched: %s', target_pattern)
    }
  }
}

summary_df <- Reduce(`+`, lapply(imputed_list, function(df) df[, target_vars, drop = FALSE])) / M
summary_df <- cbind(id_data, summary_df)
readr::write_csv(summary_df, paste0(output_base, '_mean.csv'))
arrow::write_parquet(summary_df, paste0(output_base, '_mean.parquet'))
log_info('[mixgb] Wrote mean summary tables')

if (length(warning_lines) > 0) {
  warn_path <- file.path(output_dir, paste0(output_prefix, '_warnings.txt'))
  writeLines(warning_lines, warn_path)
  log_info('[mixgb] Warning log written to %s', warn_path)
}

total_min <- as.numeric(difftime(Sys.time(), overall_start, units = 'mins'))
log_info('[mixgb] All imputations completed in %.2f min', total_min)
log_info('Outputs written to %s', output_dir)
if (compute_shap) {
  log_info('SHAP values written to %s', shap_output_dir)
}

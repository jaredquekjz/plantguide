# ========================================================================
# AUTO-DETECTING PATHS (works on Windows/Linux/Mac, any location)
# ========================================================================
get_repo_root <- function() {
  # First check if environment variable is set (from run_all_bill.R)
  env_root <- Sys.getenv("BILL_REPO_ROOT", unset = NA)
  if (!is.na(env_root) && env_root != "") {
    return(normalizePath(env_root))
  }

  # Otherwise detect from script path
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- sub("^--file=", "", file_arg[1])
    # Navigate up from script to repo root
    # Scripts are in shipley_checks/src/Stage_X/bill_verification/
    repo_root <- normalizePath(file.path(dirname(script_path), "..", "..", ".."))
  } else {
    # Fallback: assume current directory is repo root
    repo_root <- normalizePath(getwd())
  }
  return(repo_root)
}

repo_root <- get_repo_root()
INPUT_DIR <- file.path(repo_root, "shipley_checks/input")
INTERMEDIATE_DIR <- file.path(repo_root, "shipley_checks/intermediate")
OUTPUT_DIR <- file.path(repo_root, "shipley_checks/output")

# Create output directories
dir.create(file.path(OUTPUT_DIR, "wfo_verification"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(OUTPUT_DIR, "stage3"), recursive = TRUE, showWarnings = FALSE)



suppressPackageStartupMessages({
  library(mixgb)
  library(dplyr)
  library(purrr)
  library(readr)
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
# Bill's verification paths
input_path <- get_opt('input_csv', 'data/shipley_checks/modelling/canonical_imputation_input_11711_bill.csv')
output_dir <- get_opt('output_dir', 'data/shipley_checks/imputation')
output_prefix <- get_opt('output_prefix', 'mixgb_imputed_bill')
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
output_base <- file.path(output_dir, output_prefix)

seed_value <- as.integer(get_opt('seed', '20251022'))
imputation_runs <- as.integer(get_opt('m', '10'))
nrounds_value <- as.integer(get_opt('nrounds', '300'))
pmm_type_value <- as.integer(get_opt('pmm_type', '2'))
pmm_k_value <- as.integer(get_opt('pmm_k', '4'))
device_value <- tolower(get_opt('device', 'cuda'))
eta_value <- as.numeric(get_opt('eta', '0.3'))

# Model saving parameters
save_models <- tolower(get_opt('save_models', 'false')) %in% c('true', 't', '1', 'yes')
save_models_folder <- get_opt('save_models_folder', 'data/shipley_checks/models/mixgb_saved')
if (save_models && !dir.exists(save_models_folder)) {
  dir.create(save_models_folder, recursive = TRUE)
  log_info('Created model saving directory: %s', save_models_folder)
}

mix_data <- readr::read_csv(input_path, show_col_types = FALSE)
log_info('Input rows: %d, columns: %d', nrow(mix_data), ncol(mix_data))

# CANONICAL SLA: Use sla_mm2_mg (not lma_g_m2) to match BHPMF and Stage 2
log_target_vars <- c('logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM')
raw_target_vars <- c('leaf_area_mm2', 'nmass_mg_g', 'ldmc_frac', 'sla_mm2_mg',
                     'plant_height_m', 'seed_mass_mg')

id_cols <- c('wfo_taxon_id', 'wfo_scientific_name')

drop_predictors <- c('leaf_area_source', 'nmass_source', 'ldmc_source', 'lma_source',
                     'height_source', 'seed_mass_source', 'sla_source',
                     'try_parasitism', 'try_carnivory', 'try_succulence',
                     'accepted_name', 'accepted_norm', 'accepted_wfo_id',
                     'duke_files', 'duke_original_names', 'duke_matched_names', 'duke_scientific_names',
                     'eive_taxon_concepts', 'try_source_species',
                     'genus', 'family', 'try_genus', 'try_family')

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

# Determine target traits (log-transformed expected; raw supported for legacy datasets)
if (all(log_target_vars %in% names(feature_data))) {
  target_vars <- log_target_vars
  log_info('Using log-transformed trait targets: %s', paste(target_vars, collapse = ', '))
} else if (all(raw_target_vars %in% names(feature_data))) {
  target_vars <- raw_target_vars
  log_info('Using raw trait targets: %s', paste(target_vars, collapse = ', '))
} else {
  found <- intersect(c(log_target_vars, raw_target_vars), names(feature_data))
  stop(sprintf(
    'None of the expected trait targets were found. Present targets: %s',
    paste(found, collapse = ', ')
  ))
}

for (trait in target_vars) {
  n_obs <- sum(!is.na(feature_data[[trait]]))
  pct <- 100 * n_obs / nrow(feature_data)
  log_info('  %s: %d obs (%.1f%%)', trait, n_obs, pct)
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

log_info('[mixgb] Starting %d imputations (device=%s)', M, device_value)

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

  # Build mixgb call arguments
  mixgb_args <- list(
    data = feature_data,
    m = 1,
    nrounds = nrounds_value,
    pmm.type = pmm_type_value,
    pmm.k = pmm_k_value,
    xgb.params = xgb_params,
    verbose = 1
  )

  # Add model saving parameters if enabled
  if (save_models) {
    mixgb_args$save.models <- TRUE
    mixgb_args$save.models.folder <- save_models_folder
  }

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

  imp_df <- cbind(id_data, fit_df)
  imp_path_csv <- sprintf('%s_m%d.csv', output_base, i)
  imp_path_parquet <- sprintf('%s_m%d.parquet', output_base, i)
  readr::write_csv(imp_df, imp_path_csv)
  arrow::write_parquet(imp_df, imp_path_parquet)
  log_info('[mixgb] (%d/%d) wrote %s_{m%d}.csv/parquet', i, M, output_prefix, i)
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

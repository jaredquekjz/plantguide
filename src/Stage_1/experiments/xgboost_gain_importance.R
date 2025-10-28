#!/usr/bin/env Rscript
# Extract GAIN feature importance from XGBoost models trained on 6 log traits.
#
# Based on scripts/train_target_trait_models.R with adaptations for log trait targets.

suppressPackageStartupMessages({
  library(xgboost)
  library(dplyr)
  library(readr)
  library(data.table)
})

# Parse command-line arguments
args <- commandArgs(trailingOnly = TRUE)
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
opts <- parse_args(args)
get_opt <- function(name, default) {
  if (!is.null(opts[[name]]) && nzchar(opts[[name]])) opts[[name]] else default
}

# Parameters
input_csv <- get_opt('input_csv', 'model_data/inputs/mixgb_perm123_1084/mixgb_input_perm1_1084_20251027.csv')
output_dir <- get_opt('output_dir', 'results/experiments/perm1_antileakage_1084/feature_importance')
nrounds <- as.integer(get_opt('nrounds', '1000'))
eta <- as.numeric(get_opt('eta', '0.1'))
device <- tolower(get_opt('device', 'cuda'))
top_n <- as.integer(get_opt('top_n', '20'))

# Create output directory
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cat(sprintf("================================================================================\n"))
cat(sprintf("XGBOOST GAIN FEATURE IMPORTANCE EXTRACTION\n"))
cat(sprintf("================================================================================\n\n"))
cat(sprintf("Input: %s\n", input_csv))
cat(sprintf("Output: %s\n", output_dir))
cat(sprintf("XGBoost params: nrounds=%d, eta=%.3f, device=%s\n\n", nrounds, eta, device))

# Load dataset
imputed_data <- read_csv(input_csv, show_col_types = FALSE)
cat(sprintf("Loaded %d rows, %d columns\n\n", nrow(imputed_data), ncol(imputed_data)))

# Define target traits (log scale)
target_traits <- c('logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM')

# ID columns to exclude
id_cols <- c('wfo_taxon_id', 'wfo_scientific_name')

# Feature columns = all except IDs and target traits
feature_cols <- setdiff(names(imputed_data), c(id_cols, target_traits))

cat(sprintf("Feature columns: %d\n", length(feature_cols)))
cat(sprintf("Target traits: %d\n\n", length(target_traits)))

# Storage for all importance results
all_importance <- list()

# Train model for each target trait
for (trait in target_traits) {
  cat(sprintf("================================================================================\n"))
  cat(sprintf("[%s] Processing trait: %s\n", Sys.time(), trait))
  cat(sprintf("================================================================================\n\n"))

  # Prepare data: complete cases for this trait
  trait_data <- imputed_data %>%
    select(all_of(c(trait, feature_cols))) %>%
    filter(!is.na(.data[[trait]]))

  n_complete <- nrow(trait_data)
  cat(sprintf("  Complete cases: %d/%d\n", n_complete, nrow(imputed_data)))

  if (n_complete < 10) {
    cat(sprintf("  [SKIP] Insufficient data for trait %s\n\n", trait))
    next
  }

  # Separate target and features
  y <- trait_data[[trait]]
  X <- trait_data %>% select(all_of(feature_cols))

  # Handle categorical features
  is_char <- sapply(X, is.character)
  cat_cols <- names(X)[is_char]
  if (length(cat_cols) > 0) {
    cat(sprintf("  Converting %d character columns to factors\n", length(cat_cols)))
    for (col in cat_cols) {
      X[[col]] <- factor(X[[col]])
    }
  }

  # One-hot encode categorical features
  # NOTE: model.matrix will drop rows with NA in categorical columns
  # and preserve original row indices as rownames
  X_encoded <- model.matrix(~ . - 1, data = X)

  # Match y to X_encoded rows using rownames
  # (model.matrix drops rows with NA in categorical features)
  row_indices <- as.integer(rownames(X_encoded))
  y <- y[row_indices]

  cat(sprintf("  Final dimensions: X=%d×%d, y=%d\n", nrow(X_encoded), ncol(X_encoded), length(y)))

  # Verify dimensions match
  if (nrow(X_encoded) != length(y)) {
    cat(sprintf("  [ERROR] Dimension mismatch: X=%d, y=%d\n\n", nrow(X_encoded), length(y)))
    next
  }

  # Create DMatrix
  dtrain <- xgb.DMatrix(data = X_encoded, label = y)

  # Train XGBoost model
  cat(sprintf("  Training XGBoost model...\n"))
  start_time <- Sys.time()

  xgb_params <- list(
    device = device,
    tree_method = 'hist',
    eta = eta,
    objective = 'reg:squarederror',
    eval_metric = 'rmse'
  )

  model <- xgb.train(
    params = xgb_params,
    data = dtrain,
    nrounds = nrounds,
    verbose = 0
  )

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = 'secs'))
  cat(sprintf("  Training completed in %.1f seconds\n", elapsed))

  # Extract feature importance
  cat(sprintf("  Extracting feature importance...\n"))
  importance <- xgb.importance(
    feature_names = colnames(X_encoded),
    model = model
  )

  # Add trait column
  importance$trait <- trait

  # Store
  all_importance[[trait]] <- importance

  # Save individual trait importance
  trait_output <- file.path(output_dir, sprintf("%s_importance.csv", trait))
  fwrite(importance, trait_output)

  cat(sprintf("  [DONE] Extracted %d features\n", nrow(importance)))
  cat(sprintf("  Top 5 features by GAIN:\n"))
  top5 <- importance %>% arrange(desc(Gain)) %>% head(5)
  for (i in 1:nrow(top5)) {
    cat(sprintf("    %d. %s (%.4f)\n", i, top5$Feature[i], top5$Gain[i]))
  }
  cat(sprintf("  Saved: %s\n\n", trait_output))
}

# Combine all importance tables
cat(sprintf("================================================================================\n"))
cat(sprintf("COMBINING RESULTS\n"))
cat(sprintf("================================================================================\n\n"))

all_importance_df <- rbindlist(all_importance)
combined_output <- file.path(output_dir, "all_traits_importance.csv")
fwrite(all_importance_df, combined_output)

cat(sprintf("Combined importance saved: %s\n", combined_output))
cat(sprintf("Total features across all traits: %d\n", nrow(all_importance_df)))
cat(sprintf("\n[COMPLETED] Feature importance extraction\n\n"))

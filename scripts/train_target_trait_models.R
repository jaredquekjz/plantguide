#!/usr/bin/env Rscript
# Train XGBoost models for 6 target traits and extract feature importance.
#
# This script loads the mean imputed dataset from mixgb, then trains separate
# XGBoost models for each of the 6 target traits to enable feature importance
# extraction and cluster analysis (phylo, EIVE, climate, soil contributions).

suppressPackageStartupMessages({
  library(xgboost)
  library(dplyr)
  library(readr)
  library(data.table)
})

options(stringsAsFactors = FALSE)

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
input_csv <- get_opt('input_csv', 'model_data/inputs/mixgb/mixgb_FINAL_eta005_2000trees_WITH_MODELS_20251023_m1.csv')
output_dir <- get_opt('output_dir', 'results/feature_importance')
models_dir <- get_opt('models_dir', 'model_data/models/target_traits')
nrounds <- as.integer(get_opt('nrounds', '2000'))
eta <- as.numeric(get_opt('eta', '0.05'))
device <- tolower(get_opt('device', 'cuda'))
top_n <- as.integer(get_opt('top_n', '20'))

# Create output directories
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(models_dir, recursive = TRUE, showWarnings = FALSE)

cat(sprintf("[info] Loading imputed dataset: %s\n", input_csv))
imputed_data <- read_csv(input_csv, show_col_types = FALSE)

# Define target traits (in log scale)
target_traits <- c('leaf_area_mm2', 'nmass_mg_g', 'ldmc_frac',
                   'lma_g_m2', 'plant_height_m', 'seed_mass_mg')

# ID columns to exclude from features
id_cols <- c('wfo_taxon_id', 'wfo_scientific_name')

# Feature columns = all columns except IDs and target traits
feature_cols <- setdiff(names(imputed_data), c(id_cols, target_traits))

cat(sprintf("[info] Training models for %d traits using %d features\n",
            length(target_traits), length(feature_cols)))
cat(sprintf("[info] XGBoost params: nrounds=%d, eta=%.3f, device=%s\n",
            nrounds, eta, device))

# Storage for all importance tables
all_importance <- list()

# Train model for each target trait
for (trait in target_traits) {
  cat(sprintf("\n[trait] %s\n", trait))

  # Prepare data: complete cases only (no missing target)
  trait_data <- imputed_data %>%
    select(all_of(c(trait, feature_cols))) %>%
    filter(!is.na(.data[[trait]]))

  n_complete <- nrow(trait_data)
  cat(sprintf("  - Complete cases: %d/%d\n", n_complete, nrow(imputed_data)))

  # Separate target and features
  y <- trait_data[[trait]]
  X <- trait_data %>% select(all_of(feature_cols))

  # Handle categorical features
  is_char <- sapply(X, is.character)
  cat_cols <- names(X)[is_char]
  if (length(cat_cols) > 0) {
    for (col in cat_cols) {
      X[[col]] <- factor(X[[col]])
    }
  }

  # Convert to matrix (xgboost expects numeric matrix)
  # One-hot encode categorical features
  X_encoded <- model.matrix(~ . - 1, data = X)

  # Create DMatrix
  dtrain <- xgb.DMatrix(data = X_encoded, label = y)

  # Train XGBoost model
  cat(sprintf("  - Training XGBoost model...\n"))
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
  cat(sprintf("  - Training completed in %.1f seconds\n", elapsed))

  # Save model
  model_path <- file.path(models_dir, sprintf('%s_model.json', trait))
  xgb.save(model, model_path)
  cat(sprintf("  - Model saved: %s\n", model_path))

  # Extract feature importance
  cat(sprintf("  - Extracting feature importance...\n"))
  importance <- xgb.importance(
    feature_names = colnames(X_encoded),
    model = model
  )

  # Add trait column for tracking
  importance$trait <- trait

  # Save trait-specific importance
  trait_importance_path <- file.path(output_dir, sprintf('importance_%s.csv', trait))
  fwrite(importance, trait_importance_path)
  cat(sprintf("  - Importance saved: %s (top feature: %s, Gain=%.4f)\n",
              trait_importance_path, importance$Feature[1], importance$Gain[1]))

  # Store in list
  all_importance[[trait]] <- importance
}

cat("\n[summary] Aggregating importance across all traits\n")

# Combine all importance tables
combined_importance <- rbindlist(all_importance)

# Aggregate by feature: mean Gain across traits
global_importance <- combined_importance %>%
  group_by(Feature) %>%
  summarise(
    mean_Gain = mean(Gain, na.rm = TRUE),
    mean_Cover = mean(Cover, na.rm = TRUE),
    mean_Frequency = mean(Frequency, na.rm = TRUE),
    n_traits = n()
  ) %>%
  arrange(desc(mean_Gain)) %>%
  as.data.table()

# Save global importance
global_path <- file.path(output_dir, sprintf('importance_global_top%d.csv', top_n))
fwrite(head(global_importance, top_n), global_path)
cat(sprintf("[ok] Global importance (top %d): %s\n", top_n, global_path))

# Cluster analysis: categorize features by source
cat("\n[cluster] Categorizing features by source\n")

# Define feature patterns
phylo_pattern <- "^(genus_code|family_code|phylo_)"
eive_pattern <- "^EIVEres_"
worldclim_pattern <- "_(q50|q05|q95)$"  # Environmental features with quantiles
categorical_pattern <- "^try_"

global_importance_annotated <- global_importance %>%
  mutate(
    cluster = case_when(
      grepl(phylo_pattern, Feature) ~ 'Phylogenetic',
      grepl(eive_pattern, Feature) ~ 'EIVE Ecological',
      grepl(categorical_pattern, Feature) ~ 'TRY Categorical',
      grepl(worldclim_pattern, Feature) ~ 'Environmental',
      TRUE ~ 'Other'
    )
  )

# Cluster summary
cluster_summary <- global_importance_annotated %>%
  group_by(cluster) %>%
  summarise(
    n_features = n(),
    total_Gain = sum(mean_Gain, na.rm = TRUE),
    mean_Gain = mean(mean_Gain, na.rm = TRUE)
  ) %>%
  arrange(desc(total_Gain)) %>%
  as.data.table()

cluster_summary_path <- file.path(output_dir, 'cluster_summary.csv')
fwrite(cluster_summary, cluster_summary_path)
cat(sprintf("[ok] Cluster summary: %s\n", cluster_summary_path))

# Print cluster summary
cat("\n[results] Feature cluster contributions:\n")
print(cluster_summary, row.names = FALSE)

# Top features by cluster
cat("\n[results] Top 5 features per cluster:\n")
for (clust in unique(global_importance_annotated$cluster)) {
  cat(sprintf("\n%s:\n", clust))
  top_cluster <- global_importance_annotated %>%
    filter(cluster == clust) %>%
    arrange(desc(mean_Gain)) %>%
    head(5)
  for (i in 1:nrow(top_cluster)) {
    cat(sprintf("  %d. %s (Gain=%.4f)\n",
                i, top_cluster$Feature[i], top_cluster$mean_Gain[i]))
  }
}

# Save annotated global importance
annotated_path <- file.path(output_dir, sprintf('importance_global_top%d_annotated.csv', top_n))
fwrite(head(global_importance_annotated, top_n), annotated_path)
cat(sprintf("\n[ok] Annotated importance: %s\n", annotated_path))

cat("\n[complete] Feature importance extraction finished\n")
cat(sprintf("[complete] Output directory: %s\n", output_dir))

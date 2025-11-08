#!/usr/bin/env Rscript
#
# SHAP Analysis for EIVE Models (Bill's Verification)
#
# Purpose: Analyze SHAP values to understand feature contributions
# - Global feature importance (mean absolute SHAP)
# - Per-category analysis for categorical features
# - Feature value vs SHAP contribution plots
#

suppressPackageStartupMessages({
  library(xgboost)
  library(readr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(jsonlite)
})

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

parse_args <- function(args) {
  out <- list(
    axis = 'L',
    features_csv = NA,
    model_dir = 'data/shipley_checks/stage2_models',
    out_dir = 'data/shipley_checks/stage2_shap',
    top_n = 20
  )

  for (a in args) {
    if (!grepl('^--', a)) next
    kv <- sub('^--', '', a)
    key <- sub('=.*$', '', kv)
    val <- sub('^[^=]*=', '', kv)

    if (key == 'axis') out$axis <- val
    else if (key == 'features_csv') out$features_csv <- val
    else if (key == 'model_dir') out$model_dir <- val
    else if (key == 'out_dir') out$out_dir <- val
    else if (key == 'top_n') out$top_n <- as.integer(val)
  }

  out
}

args <- commandArgs(trailingOnly = TRUE)
opts <- parse_args(args)

# Auto-detect features CSV if not provided
if (is.na(opts$features_csv)) {
  opts$features_csv <- file.path(
    'data/shipley_checks/stage2_features',
    sprintf('%s_features_11711_bill_20251107.csv', opts$axis)
  )
}

# ============================================================================
# HEADER
# ============================================================================

cat(strrep('=', 80), '\n')
cat(sprintf('SHAP ANALYSIS: %s-axis (Bill Verification)\n', opts$axis))
cat(strrep('=', 80), '\n\n')

cat('Configuration:\n')
cat(sprintf('  Features CSV: %s\n', opts$features_csv))
cat(sprintf('  Model dir: %s\n', opts$model_dir))
cat(sprintf('  Output dir: %s\n', opts$out_dir))
cat(sprintf('  Top N features: %d\n\n', opts$top_n))

# ============================================================================
# LOAD DATA AND MODEL
# ============================================================================

cat('[1/5] Loading data and model...\n')
cat(strrep('-', 80), '\n')

if (!file.exists(opts$features_csv)) {
  stop('Features file not found: ', opts$features_csv)
}

df <- read_csv(opts$features_csv, show_col_types = FALSE)
cat(sprintf('✓ Loaded %d species × %d columns\n', nrow(df), ncol(df)))

# Load model
model_path <- file.path(opts$model_dir, sprintf('xgb_%s_model.json', opts$axis))
if (!file.exists(model_path)) {
  stop('Model not found: ', model_path)
}

model <- xgb.load(model_path)
cat(sprintf('✓ Loaded model: %s\n', model_path))

# Load scaler
scaler_path <- file.path(opts$model_dir, sprintf('xgb_%s_scaler.json', opts$axis))
if (!file.exists(scaler_path)) {
  stop('Scaler not found: ', scaler_path)
}

scaler <- read_json(scaler_path)
cat(sprintf('✓ Loaded scaler: %s\n\n', scaler_path))

# ============================================================================
# PREPARE FEATURES
# ============================================================================

cat('[2/5] Preparing features...\n')
cat(strrep('-', 80), '\n')

# Extract target and features
y <- df$y
feature_cols <- scaler$features

# Build feature matrix
X_df <- df %>% select(all_of(feature_cols))
X <- as.matrix(X_df)

cat(sprintf('✓ Features: %d columns\n', ncol(X)))
cat(sprintf('✓ Samples: %d\n', nrow(X)))

# Apply scaling
X_scaled <- X
for (j in seq_along(scaler$features)) {
  if (scaler$scale[j] > 0) {
    X_scaled[, j] <- (X[, j] - scaler$mean[j]) / scaler$scale[j]
  }
}

cat('✓ Scaling applied\n\n')

# ============================================================================
# COMPUTE SHAP VALUES
# ============================================================================

cat('[3/5] Computing SHAP values...\n')
cat(strrep('-', 80), '\n')

dmatrix <- xgb.DMatrix(data = X_scaled)
shap_contrib <- predict(model, dmatrix, predcontrib = TRUE)

# Last column is bias (intercept), exclude it
shap_values <- shap_contrib[, -ncol(shap_contrib), drop = FALSE]
colnames(shap_values) <- feature_cols

cat(sprintf('✓ SHAP values computed: %d samples × %d features\n', nrow(shap_values), ncol(shap_values)))

# Global importance (mean absolute SHAP)
importance <- colMeans(abs(shap_values))
importance_df <- data.frame(
  feature = names(importance),
  importance = as.numeric(importance),
  stringsAsFactors = FALSE
) %>%
  arrange(desc(importance))

cat('\nTop 10 features by mean |SHAP|:\n')
print(head(importance_df, 10), row.names = FALSE)
cat('\n')

# ============================================================================
# ANALYZE BY CATEGORY
# ============================================================================

cat('[4/5] Analyzing SHAP by feature category...\n')
cat(strrep('-', 80), '\n')

# Categorize features (matching Python implementation)
categorize_feature <- function(feature) {
  feature_lower <- tolower(feature)

  # Log traits (6 features)
  log_traits <- c('logla', 'logsla', 'logh', 'lognmass', 'logldmc', 'logsm')
  if (feature_lower %in% log_traits) return('Log traits')

  # Cross-axis EIVE (excluded in NO-EIVE models, but check anyway)
  if (grepl('^EIVEres-', feature)) return('Cross-axis EIVE')

  # Cross-axis phylo (excluded in NO-EIVE models, but check anyway)
  if (grepl('^p_phylo_', feature)) return('Cross-axis phylo')

  # Phylo eigenvectors
  if (grepl('^phylo_ev', feature)) return('Phylo eigenvectors')

  # Climate variables (WorldClim + Agroclim)
  climate_prefixes <- c('wc2.1_', 'bio_', 'bedd', 'tx', 'tn', 'csu', 'csdi',
                       'dtr', 'fd', 'gdd', 'gsl', 'id', 'su', 'tr')
  if (any(sapply(climate_prefixes, function(p) grepl(paste0('^', p), feature_lower)))) {
    return('Climate')
  }

  # Soil variables (SoilGrids + derived)
  soil_keywords <- c('clay', 'sand', 'silt', 'nitrogen', 'soc', 'phh2o',
                     'bdod', 'cec', 'cfvo', 'ocd', 'ocs')
  if (any(sapply(soil_keywords, function(k) grepl(k, feature_lower)))) {
    return('Soil')
  }

  # Categorical traits
  if (grepl('^try_', feature)) return('Categorical traits')

  # Unknown
  return('Other')
}

importance_df <- importance_df %>%
  mutate(category = sapply(feature, categorize_feature))

# Summary by category (matching Python implementation)
category_summary <- importance_df %>%
  group_by(category) %>%
  summarise(
    n_features = n(),
    total_shap = sum(importance),
    avg_shap = mean(importance),
    .groups = 'drop'
  ) %>%
  arrange(desc(total_shap)) %>%
  mutate(
    pct_importance = 100 * total_shap / sum(total_shap)
  )

cat('SHAP importance by feature category:\n')
cat(sprintf('%-25s %10s %10s %10s %10s\n',
            'Category', 'Total SHAP', '% Import', '# Feats', 'Avg SHAP'))
cat(strrep('-', 80), '\n')
for (i in 1:nrow(category_summary)) {
  row <- category_summary[i, ]
  cat(sprintf('%-25s %10.4f %9.1f%% %10d %10.5f\n',
              row$category, row$total_shap, row$pct_importance,
              row$n_features, row$avg_shap))
}
cat('\n')

# Show top features per category (top 3 categories)
cat('Top 5 features per category (top 3 categories):\n')
cat(strrep('-', 80), '\n')
for (i in 1:min(3, nrow(category_summary))) {
  cat_name <- category_summary$category[i]
  cat_pct <- category_summary$pct_importance[i]
  cat(sprintf('\n%s (%.1f%% of total importance):\n', cat_name, cat_pct))

  top_features <- importance_df %>%
    filter(category == cat_name) %>%
    arrange(desc(importance)) %>%
    head(5)

  for (j in 1:nrow(top_features)) {
    cat(sprintf('  %d. %s: %.4f\n', j, top_features$feature[j], top_features$importance[j]))
  }
}
cat('\n')

# ============================================================================
# SAVE OUTPUTS
# ============================================================================

cat('[5/5] Saving outputs...\n')
cat(strrep('-', 80), '\n')

dir.create(opts$out_dir, recursive = TRUE, showWarnings = FALSE)

# Save full importance table
importance_path <- file.path(opts$out_dir, sprintf('%s_shap_importance.csv', opts$axis))
write_csv(importance_df, importance_path)
cat(sprintf('✓ Importance table: %s\n', importance_path))

# Save category summary
category_path <- file.path(opts$out_dir, sprintf('%s_shap_by_category.csv', opts$axis))
write_csv(category_summary, category_path)
cat(sprintf('✓ Category summary: %s\n', category_path))

# Save raw SHAP values for top N features
top_features <- head(importance_df$feature, opts$top_n)
shap_top <- as.data.frame(shap_values[, top_features])
shap_top$wfo_taxon_id <- df$wfo_taxon_id
shap_top$y_true <- y

shap_values_path <- file.path(opts$out_dir, sprintf('%s_shap_values_top%d.csv', opts$axis, opts$top_n))
write_csv(shap_top, shap_values_path)
cat(sprintf('✓ SHAP values (top %d): %s\n', opts$top_n, shap_values_path))

# ============================================================================
# PLOTS
# ============================================================================

cat('\nGenerating plots...\n')

# Plot 1: Feature importance bar plot
p1 <- ggplot(head(importance_df, opts$top_n), aes(x = reorder(feature, importance), y = importance)) +
  geom_col(fill = 'steelblue') +
  coord_flip() +
  labs(
    title = sprintf('Top %d Features by SHAP Importance (%s-axis)', opts$top_n, opts$axis),
    x = 'Feature',
    y = 'Mean |SHAP|'
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 12, face = 'bold'),
    axis.text.y = element_text(size = 8)
  )

plot_path_1 <- file.path(opts$out_dir, sprintf('%s_shap_importance_top%d.png', opts$axis, opts$top_n))
ggsave(plot_path_1, p1, width = 10, height = 8, dpi = 300)
cat(sprintf('✓ Importance plot: %s\n', plot_path_1))

# Plot 2: Category bar chart (percentage)
p2 <- ggplot(category_summary, aes(x = reorder(category, pct_importance), y = pct_importance)) +
  geom_col(fill = 'steelblue') +
  coord_flip() +
  labs(
    title = sprintf('SHAP Importance by Category (%s-axis)', opts$axis),
    x = 'Category',
    y = '% of Total SHAP Importance'
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 12, face = 'bold'),
    axis.text.y = element_text(size = 9)
  )

plot_path_2 <- file.path(opts$out_dir, sprintf('%s_shap_by_category.png', opts$axis))
ggsave(plot_path_2, p2, width = 8, height = 6, dpi = 300)
cat(sprintf('✓ Category plot: %s\n', plot_path_2))

# ============================================================================
# SUMMARY
# ============================================================================

cat('\n')
cat(strrep('=', 80), '\n')
cat('SHAP ANALYSIS COMPLETE\n')
cat(strrep('=', 80), '\n\n')

cat(sprintf('Axis: %s\n', opts$axis))
cat(sprintf('Features analyzed: %d\n', ncol(shap_values)))
cat(sprintf('Samples: %d\n\n', nrow(shap_values)))

cat('Top 3 features:\n')
for (i in 1:min(3, nrow(importance_df))) {
  cat(sprintf('  %d. %s (%.4f)\n', i, importance_df$feature[i], importance_df$importance[i]))
}

cat('\nTop category:\n')
cat(sprintf('  %s: %.1f%% of total importance (%d features)\n',
            category_summary$category[1],
            category_summary$pct_importance[1],
            category_summary$n_features[1]))

cat(sprintf('\nOutputs saved to: %s\n\n', opts$out_dir))

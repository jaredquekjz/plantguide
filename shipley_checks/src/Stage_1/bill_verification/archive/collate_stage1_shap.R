#!/usr/bin/env Rscript
################################################################################
# Collate Stage 1 SHAP Results: Trait Imputation Feature Importance
#
# Purpose: Analyze SHAP importance by category for all 6 traits
################################################################################

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})

cat(strrep('=', 80), '\n')
cat('STAGE 1 TRAIT IMPUTATION - SHAP ANALYSIS\n')
cat(strrep('=', 80), '\n\n')

TRAITS <- c("logLA", "logNmass", "logLDMC", "logSLA", "logH", "logSM")
MODEL_DIR <- "data/shipley_checks/stage1_models"

categorize_feature <- function(feature_name) {
  # Stage 1 specific: includes other traits as features (not EIVE)
  if (grepl('^try_.*_', feature_name)) return('Categorical')
  else if (grepl('^phylo_ev', feature_name)) return('Phylogeny')
  else if (grepl('^log[A-Z]', feature_name)) return('Other_Traits')
  else if (grepl('^EIVEres-', feature_name)) return('EIVE')
  else if (grepl('^wc2\\.1_|^bio_', feature_name)) return('Climate')
  else if (grepl('^soc_|^nitrogen_|^phh2o_|^cec_|^bdod_|^clay_|^sand_|^silt_', feature_name)) return('Soil')
  else return('Other')
}

shap_by_trait <- list()
top_features_by_trait <- list()

for (trait in TRAITS) {
  importance_file <- file.path(MODEL_DIR, sprintf("xgb_%s_importance.csv", trait))

  if (!file.exists(importance_file)) {
    cat(sprintf('  ⚠ Missing: %s\n', basename(importance_file)))
    next
  }

  importance <- read_csv(importance_file, show_col_types = FALSE)

  # Categorize features
  importance <- importance %>%
    mutate(category = sapply(feature, categorize_feature))

  # Calculate total importance for normalization
  total_shap <- sum(importance$importance)

  # Aggregate by category (normalize to 100%)
  category_summary <- importance %>%
    group_by(category) %>%
    summarize(
      n_features = n(),
      total_importance = sum(importance),
      mean_importance = mean(importance),
      .groups = 'drop'
    ) %>%
    mutate(
      pct_contribution = 100 * total_importance / total_shap
    ) %>%
    arrange(desc(pct_contribution))

  category_summary$trait <- trait
  shap_by_trait[[trait]] <- category_summary

  # Get top 10 individual features
  top_features <- importance %>%
    arrange(desc(importance)) %>%
    head(10) %>%
    mutate(
      pct_contribution = 100 * importance / total_shap,
      trait = trait
    )

  top_features_by_trait[[trait]] <- top_features

  cat(sprintf('\n%s:\n', trait))
  cat('  Category contributions (% of total SHAP importance):\n')
  for (j in 1:nrow(category_summary)) {
    cat(sprintf('    %-14s: %5.1f%% (%d features)\n',
                category_summary$category[j],
                category_summary$pct_contribution[j],
                category_summary$n_features[j]))
  }

  cat('  Top 3 individual features:\n')
  for (j in 1:3) {
    cat(sprintf('    %d. %-40s: %5.1f%%\n',
                j,
                top_features$feature[j],
                top_features$pct_contribution[j]))
  }
}

cat('\n', strrep('=', 80), '\n')
cat('SUMMARY\n')
cat(strrep('=', 80), '\n\n')

# Overall patterns
cat('Key Patterns:\n\n')

cat('1. Categorical traits dominate for:\n')
for (trait in TRAITS) {
  cat_pct <- shap_by_trait[[trait]] %>%
    filter(category == 'Categorical') %>%
    pull(pct_contribution)
  if (length(cat_pct) > 0 && cat_pct > 30) {
    cat(sprintf('   - %s: %.1f%% (top predictor)\n', trait, cat_pct))
  }
}

cat('\n2. EIVE as cross-predictors:\n')
for (trait in TRAITS) {
  eive_pct <- shap_by_trait[[trait]] %>%
    filter(category == 'EIVE') %>%
    pull(pct_contribution)
  if (length(eive_pct) > 0) {
    cat(sprintf('   - %s: %.1f%%\n', trait, eive_pct))
  }
}

cat('\n3. Climate importance:\n')
for (trait in TRAITS) {
  clim_pct <- shap_by_trait[[trait]] %>%
    filter(category == 'Climate') %>%
    pull(pct_contribution)
  if (length(clim_pct) > 0 && clim_pct > 10) {
    cat(sprintf('   - %s: %.1f%%\n', trait, clim_pct))
  }
}

# Save results
cat('\n', strrep('=', 80), '\n')

shap_aggregated <- bind_rows(shap_by_trait)
shap_path <- file.path(MODEL_DIR, "stage1_shap_by_category.csv")
write_csv(shap_aggregated, shap_path)
cat(sprintf('Saved: %s\n', shap_path))

top_features_all <- bind_rows(top_features_by_trait)
top_features_path <- file.path(MODEL_DIR, "stage1_top_features.csv")
write_csv(top_features_all, top_features_path)
cat(sprintf('Saved: %s\n\n', top_features_path))

cat('Note: Percentages show each category\'s contribution to predictions.\n')
cat('All categories sum to 100% per trait. Higher % = more influential.\n\n')

#!/usr/bin/env Rscript
#
# Analyze sources of variation in ensemble imputation
#
# Investigates:
# 1. Relationship between missingness and RMSD
# 2. Relationship between CV R² and RMSD
# 3. Which species contribute most to variation
# 4. Stochastic elements in mixgb/XGBoost
#

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
})

LOG_TRAITS <- c('logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM')

cat(strrep('=', 80), '\n')
cat('ENSEMBLE VARIATION ANALYSIS\n')
cat(strrep('=', 80), '\n\n')

# Load canonical input (to get missingness rates)
cat('[1/5] Loading canonical input for missingness rates...\n')
canonical <- read_csv('data/shipley_checks/modelling/canonical_imputation_input_11711_bill.csv',
                      show_col_types = FALSE)

missingness <- data.frame(
  trait = LOG_TRAITS,
  n_missing = sapply(LOG_TRAITS, function(t) sum(is.na(canonical[[t]]))),
  pct_missing = sapply(LOG_TRAITS, function(t) 100 * sum(is.na(canonical[[t]])) / nrow(canonical))
)

cat('\nMissingness rates:\n')
print(missingness, row.names = FALSE)

# Load CV results (to get R² performance)
cat('\n[2/5] Loading CV results for predictability...\n')
cv_results <- read_csv('data/shipley_checks/imputation/mixgb_cv_rmse_bill_trial_7cats_eta03.csv',
                       show_col_types = FALSE)

if ('r2_original' %in% names(cv_results)) {
  r2_data <- cv_results %>%
    select(trait, r2 = r2_original)
} else if ('r2_transformed' %in% names(cv_results)) {
  r2_data <- cv_results %>%
    select(trait, r2 = r2_transformed)
} else {
  r2_data <- cv_results %>%
    select(trait, r2)
}

cat('\nCV R² by trait:\n')
print(r2_data, row.names = FALSE)

# Load all 10 runs and calculate species-level variation
cat('\n[3/5] Loading all 10 runs to calculate species-level variation...\n')

run_files <- paste0('data/shipley_checks/imputation/mixgb_imputed_bill_7cats_m', 1:10, '.csv')

# Load first run to get structure
run1 <- read_csv(run_files[1], show_col_types = FALSE)
cat(sprintf('  Loaded run 1: %d species\n', nrow(run1)))

# Initialize storage for all runs
all_runs <- vector('list', 10)
all_runs[[1]] <- run1

# Load remaining runs
for (i in 2:10) {
  all_runs[[i]] <- read_csv(run_files[i], show_col_types = FALSE)
  cat(sprintf('  Loaded run %d: %d species\n', i, nrow(all_runs[[i]])))
}

# Calculate species-level RMSD for each trait
cat('\n[4/5] Calculating species-level RMSD...\n')

species_rmsd <- data.frame(wfo_taxon_id = run1$wfo_taxon_id)

for (trait in LOG_TRAITS) {
  # Extract trait values across all 10 runs for each species
  trait_matrix <- sapply(all_runs, function(df) df[[trait]])

  # Calculate species-level SD and mean
  species_sd <- apply(trait_matrix, 1, sd, na.rm = TRUE)
  species_mean <- apply(trait_matrix, 1, mean, na.rm = TRUE)

  species_rmsd[[paste0(trait, '_sd')]] <- species_sd
  species_rmsd[[paste0(trait, '_mean')]] <- species_mean
}

# Calculate RMSD and identify high-variation species
cat('\n[5/5] Identifying high-variation species...\n\n')

for (trait in LOG_TRAITS) {
  sd_col <- paste0(trait, '_sd')
  mean_col <- paste0(trait, '_mean')

  # Overall RMSD
  overall_rmsd <- sqrt(mean(species_rmsd[[sd_col]]^2, na.rm = TRUE))

  # Find top 10 most variable species
  top_var <- species_rmsd %>%
    select(wfo_taxon_id, sd = !!sd_col, mean = !!mean_col) %>%
    arrange(desc(sd)) %>%
    head(10)

  # Check if these species were originally missing
  was_missing <- canonical %>%
    filter(wfo_taxon_id %in% top_var$wfo_taxon_id) %>%
    select(wfo_taxon_id, original_value = !!trait) %>%
    mutate(was_imputed = is.na(original_value))

  top_var <- top_var %>%
    left_join(was_missing, by = 'wfo_taxon_id')

  cat(sprintf('%s (RMSD=%.4f):\n', trait, overall_rmsd))
  cat('  Top 10 most variable species:\n')
  for (j in 1:nrow(top_var)) {
    status <- if (top_var$was_imputed[j]) 'IMPUTED' else 'OBSERVED'
    cat(sprintf('    %d. %s: SD=%.4f, mean=%.4f [%s]\n',
                j, top_var$wfo_taxon_id[j], top_var$sd[j],
                top_var$mean[j], status))
  }

  # Summary: what % of high-variation species were imputed vs observed?
  n_imputed <- sum(top_var$was_imputed, na.rm = TRUE)
  cat(sprintf('  High-variation species: %d/10 were imputed, %d/10 had observed values\n\n',
              n_imputed, 10 - n_imputed))
}

# Correlation analysis
cat(strrep('=', 80), '\n')
cat('CORRELATION ANALYSIS\n')
cat(strrep('=', 80), '\n\n')

# Calculate RMSD for each trait
rmsd_values <- sapply(LOG_TRAITS, function(trait) {
  sd_col <- paste0(trait, '_sd')
  sqrt(mean(species_rmsd[[sd_col]]^2, na.rm = TRUE))
})

summary_df <- data.frame(
  trait = LOG_TRAITS,
  pct_missing = missingness$pct_missing,
  cv_r2 = r2_data$r2[match(LOG_TRAITS, r2_data$trait)],
  rmsd = rmsd_values
)

cat('Summary table:\n')
print(summary_df, row.names = FALSE, digits = 4)

cat('\n\nCorrelations:\n')
cat(sprintf('  RMSD vs missingness: r=%.3f\n',
            cor(summary_df$rmsd, summary_df$pct_missing, use = 'complete.obs')))
cat(sprintf('  RMSD vs CV R²: r=%.3f\n',
            cor(summary_df$rmsd, summary_df$cv_r2, use = 'complete.obs')))
cat(sprintf('  CV R² vs missingness: r=%.3f\n',
            cor(summary_df$cv_r2, summary_df$pct_missing, use = 'complete.obs')))

cat('\n', strrep('=', 80), '\n')
cat('KEY FINDINGS\n')
cat(strrep('=', 80), '\n\n')

# Find traits with highest/lowest RMSD relative to R²
summary_df <- summary_df %>%
  mutate(rmsd_per_r2_loss = rmsd / (1 - cv_r2))

cat('Traits ranked by RMSD (variation between runs):\n')
summary_df_sorted <- summary_df %>% arrange(desc(rmsd))
for (i in 1:nrow(summary_df_sorted)) {
  cat(sprintf('  %d. %s: RMSD=%.4f (R²=%.3f, %.1f%% missing)\n',
              i, summary_df_sorted$trait[i], summary_df_sorted$rmsd[i],
              summary_df_sorted$cv_r2[i], summary_df_sorted$pct_missing[i]))
}

cat('\nTraits ranked by predictability (CV R²):\n')
summary_df_sorted <- summary_df %>% arrange(desc(cv_r2))
for (i in 1:nrow(summary_df_sorted)) {
  cat(sprintf('  %d. %s: R²=%.3f (RMSD=%.4f, %.1f%% missing)\n',
              i, summary_df_sorted$trait[i], summary_df_sorted$cv_r2[i],
              summary_df_sorted$rmsd[i], summary_df_sorted$pct_missing[i]))
}

cat('\n')

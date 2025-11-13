#!/usr/bin/env Rscript
#
# Analyze trait value scales to understand RMSD variation
#

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})

LOG_TRAITS <- c('logLA', 'logNmass', 'logLDMC', 'logSLA', 'logH', 'logSM')

cat(strrep('=', 80), '\n')
cat('TRAIT SCALE ANALYSIS\n')
cat(strrep('=', 80), '\n\n')

# Load mean imputation
mean_df <- read_csv('data/shipley_checks/imputation/mixgb_imputed_bill_7cats_mean.csv',
                    show_col_types = FALSE)

cat('Trait value distributions (log-scale):\n\n')

scale_summary <- data.frame(
  trait = character(),
  min = numeric(),
  q25 = numeric(),
  median = numeric(),
  mean = numeric(),
  q75 = numeric(),
  max = numeric(),
  sd = numeric(),
  range = numeric(),
  stringsAsFactors = FALSE
)

for (trait in LOG_TRAITS) {
  values <- mean_df[[trait]]

  scale_summary <- rbind(scale_summary, data.frame(
    trait = trait,
    min = min(values, na.rm = TRUE),
    q25 = quantile(values, 0.25, na.rm = TRUE),
    median = median(values, na.rm = TRUE),
    mean = mean(values, na.rm = TRUE),
    q75 = quantile(values, 0.75, na.rm = TRUE),
    max = max(values, na.rm = TRUE),
    sd = sd(values, na.rm = TRUE),
    range = max(values, na.rm = TRUE) - min(values, na.rm = TRUE),
    stringsAsFactors = FALSE
  ))

  cat(sprintf('%s:\n', trait))
  cat(sprintf('  Range: [%.2f, %.2f] (span=%.2f)\n',
              min(values, na.rm = TRUE), max(values, na.rm = TRUE),
              max(values, na.rm = TRUE) - min(values, na.rm = TRUE)))
  cat(sprintf('  Mean: %.2f, SD: %.2f\n', mean(values, na.rm = TRUE), sd(values, na.rm = TRUE)))
  cat(sprintf('  Median: %.2f, IQR: [%.2f, %.2f]\n\n',
              median(values, na.rm = TRUE),
              quantile(values, 0.25, na.rm = TRUE),
              quantile(values, 0.75, na.rm = TRUE)))
}

cat(strrep('=', 80), '\n')
cat('RELATIONSHIP: RMSD vs Trait Scale\n')
cat(strrep('=', 80), '\n\n')

# RMSD values from earlier analysis
rmsd_values <- c(
  logLA = 0.4855,
  logNmass = 0.1007,
  logLDMC = 0.0974,
  logSLA = 0.1640,
  logH = 0.2484,
  logSM = 0.4884
)

# Create comparison table
comparison <- scale_summary %>%
  mutate(
    rmsd = rmsd_values[trait],
    rmsd_pct_of_range = 100 * rmsd / range,
    rmsd_pct_of_sd = 100 * rmsd / sd,
    rmsd_relative = rmsd / range  # RMSD as fraction of total range
  ) %>%
  arrange(desc(rmsd))

cat('Traits ranked by RMSD:\n\n')
cat(sprintf('%-10s %6s %8s %8s %8s %12s %12s\n',
            'Trait', 'RMSD', 'Range', 'SD', 'Mean', 'RMSD/Range%', 'RMSD/SD%'))
cat(strrep('-', 80), '\n')
for (i in 1:nrow(comparison)) {
  cat(sprintf('%-10s %6.4f %8.2f %8.2f %8.2f %11.1f%% %11.1f%%\n',
              comparison$trait[i],
              comparison$rmsd[i],
              comparison$range[i],
              comparison$sd[i],
              comparison$mean[i],
              comparison$rmsd_pct_of_range[i],
              comparison$rmsd_pct_of_sd[i]))
}

cat('\n', strrep('=', 80), '\n')
cat('KEY INSIGHT: Relative vs Absolute Variation\n')
cat(strrep('=', 80), '\n\n')

cat('RMSD as % of trait range (smaller = more stable relative to scale):\n')
comparison_rel <- comparison %>% arrange(rmsd_pct_of_range)
for (i in 1:nrow(comparison_rel)) {
  cat(sprintf('  %d. %s: %.1f%% (RMSD=%.4f, range=%.2f)\n',
              i, comparison_rel$trait[i],
              comparison_rel$rmsd_pct_of_range[i],
              comparison_rel$rmsd[i],
              comparison_rel$range[i]))
}

cat('\nRMSD as % of trait SD (smaller = more stable relative to variability):\n')
comparison_sd <- comparison %>% arrange(rmsd_pct_of_sd)
for (i in 1:nrow(comparison_sd)) {
  cat(sprintf('  %d. %s: %.1f%% (RMSD=%.4f, SD=%.2f)\n',
              i, comparison_sd$trait[i],
              comparison_sd$rmsd_pct_of_sd[i],
              comparison_sd$rmsd[i],
              comparison_sd$sd[i]))
}

cat('\n')

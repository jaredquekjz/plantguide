#!/usr/bin/env Rscript
#
# Cross-Axis SHAP Category Comparison (Bill's Verification)
#
# Purpose: Compare SHAP category importance across all 5 EIVE axes
# - Loads per-axis category summaries
# - Creates cross-axis comparison table showing % importance
# - Identifies patterns and differences across axes
#

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
  library(readr)
  library(dplyr)
  library(tidyr)
})

# ============================================================================
# CONFIGURATION
# ============================================================================

AXES <- c('L', 'T', 'M', 'N', 'R')
AXIS_NAMES <- c(
  L = 'Light',
  T = 'Temperature',
  M = 'Moisture',
  N = 'Nitrogen',
  R = 'Reaction (pH)'
)

SHAP_DIR <- 'data/shipley_checks/stage2_shap'
OUTPUT_DIR <- 'data/shipley_checks/stage2_shap'

# ============================================================================
# HEADER
# ============================================================================

cat(strrep('=', 80), '\n')
cat('Cross-Axis SHAP Category Comparison (Bill Verification)\n')
cat(strrep('=', 80), '\n\n')

# ============================================================================
# LOAD PER-AXIS CATEGORY SUMMARIES
# ============================================================================

cat('[1/3] Loading per-axis category summaries...\n')
cat(strrep('-', 80), '\n')

all_summaries <- list()

for (axis in AXES) {
  cat_file <- file.path(SHAP_DIR, sprintf('%s_shap_by_category.csv', axis))

  if (!file.exists(cat_file)) {
    cat(sprintf('WARNING: %s not found - skipping\n', cat_file))
    next
  }

  cat_summary <- read_csv(cat_file, show_col_types = FALSE) %>%
    mutate(axis = axis, axis_name = AXIS_NAMES[axis])

  all_summaries[[axis]] <- cat_summary
  cat(sprintf('  ✓ %s-axis: %d categories\n', axis, nrow(cat_summary)))
}

cat(sprintf('\n✓ Loaded %d axes\n\n', length(all_summaries)))

# ============================================================================
# CREATE CROSS-AXIS COMPARISON TABLE
# ============================================================================

cat('[2/3] Creating cross-axis comparison...\n')
cat(strrep('-', 80), '\n')

# Combine all summaries
combined_df <- bind_rows(all_summaries)

# Save combined table
combined_path <- file.path(OUTPUT_DIR, 'shap_category_all_axes_bill.csv')
write_csv(combined_df, combined_path)
cat(sprintf('✓ Combined table: %s\n\n', combined_path))

# Create wide-format comparison (categories × axes)
# Get all unique categories
all_categories <- combined_df %>%
  group_by(category) %>%
  summarise(total_importance = sum(total_shap), .groups = 'drop') %>%
  arrange(desc(total_importance)) %>%
  pull(category)

# Build comparison table
comparison_data <- data.frame(Category = all_categories)

for (axis in AXES) {
  axis_data <- combined_df %>%
    filter(axis == !!axis) %>%
    select(category, pct_importance)

  comparison_data <- comparison_data %>%
    left_join(axis_data, by = c('Category' = 'category')) %>%
    rename(!!axis := pct_importance)

  # Fill NAs with 0
  comparison_data[[axis]][is.na(comparison_data[[axis]])] <- 0
}

# ============================================================================
# DISPLAY RESULTS
# ============================================================================

cat('Cross-Axis Category Comparison (% of Total SHAP Importance):\n')
cat(strrep('-', 80), '\n\n')

cat(sprintf('%-30s %8s %8s %8s %8s %8s\n',
            'Category', 'L', 'T', 'M', 'N', 'R'))
cat(strrep('-', 80), '\n')

for (i in 1:nrow(comparison_data)) {
  row <- comparison_data[i, ]
  cat(sprintf('%-30s %7.1f%% %7.1f%% %7.1f%% %7.1f%% %7.1f%%\n',
              row$Category,
              row$L, row$T, row$M, row$N, row$R))
}

cat('\n')

# ============================================================================
# SUMMARY INSIGHTS
# ============================================================================

cat('Key Insights:\n')
cat(strrep('-', 80), '\n\n')

# Identify dominant category per axis
cat('Dominant category per axis:\n')
for (axis in AXES) {
  axis_summary <- all_summaries[[axis]] %>%
    arrange(desc(pct_importance)) %>%
    head(1)

  cat(sprintf('  %s-axis (%s): %s (%.1f%%)\n',
              axis, AXIS_NAMES[axis],
              axis_summary$category[1], axis_summary$pct_importance[1]))
}

cat('\n')

# Average importance by category across all axes
cat('Average category importance across all 5 axes:\n')
avg_by_category <- combined_df %>%
  group_by(category) %>%
  summarise(
    avg_pct = mean(pct_importance),
    sd_pct = sd(pct_importance),
    n_axes = n(),
    .groups = 'drop'
  ) %>%
  arrange(desc(avg_pct))

for (i in 1:min(5, nrow(avg_by_category))) {
  row <- avg_by_category[i, ]
  cat(sprintf('  %d. %s: %.1f%% ± %.1f%% (present in %d axes)\n',
              i, row$category, row$avg_pct, row$sd_pct, row$n_axes))
}

cat('\n')

# ============================================================================
# SAVE OUTPUTS
# ============================================================================

cat('[3/3] Saving outputs...\n')
cat(strrep('-', 80), '\n')

# Save comparison table
comparison_path <- file.path(OUTPUT_DIR, 'shap_category_comparison_bill.csv')
write_csv(comparison_data, comparison_path)
cat(sprintf('✓ Comparison table: %s\n', comparison_path))

# Save average summary
avg_summary_path <- file.path(OUTPUT_DIR, 'shap_category_avg_across_axes_bill.csv')
write_csv(avg_by_category, avg_summary_path)
cat(sprintf('✓ Average summary: %s\n', avg_summary_path))

# ============================================================================
# SUMMARY
# ============================================================================

cat('\n')
cat(strrep('=', 80), '\n')
cat('CROSS-AXIS COMPARISON COMPLETE\n')
cat(strrep('=', 80), '\n\n')

cat(sprintf('Axes analyzed: %d\n', length(all_summaries)))
cat(sprintf('Categories found: %d\n', length(all_categories)))
cat(sprintf('\nOutputs saved to: %s\n', OUTPUT_DIR))
cat(sprintf('  - Combined table: shap_category_all_axes_bill.csv\n'))
cat(sprintf('  - Comparison table: shap_category_comparison_bill.csv\n'))
cat(sprintf('  - Average summary: shap_category_avg_across_axes_bill.csv\n\n'))

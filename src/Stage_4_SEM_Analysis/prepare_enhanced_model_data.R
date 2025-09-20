#!/usr/bin/env Rscript

# Prepare enhanced model data with climate features for Stage 2 pwSEM
# This script merges bioclim features with trait data following Stage 1 patterns

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

cat("========================================\n")
cat("Enhanced Model Data Preparation\n")
cat("========================================\n\n")

# Load base model data - use bioclim subset to match Stage 1
cat("Loading base model data (bioclim subset)...\n")
# Use the same dataset as Stage 1 for fair comparison
# Use check.names=FALSE to preserve column names with spaces/parentheses
model_data <- read.csv("artifacts/model_data_bioclim_subset_enhanced_imputed.csv",
                      stringsAsFactors = FALSE, check.names = FALSE)
cat(sprintf("  Loaded %d species with %d columns\n", nrow(model_data), ncol(model_data)))
cat("  Using bioclim subset for Stage 1/2 comparison\n")

# Load bioclim summary
cat("\nLoading bioclim summary with AI features...\n")
climate_summary <- read_csv("data/bioclim_extractions_cleaned/summary_stats/species_bioclim_summary_with_aimonth.csv",
                            show_col_types = FALSE)
cat(sprintf("  Loaded climate data for %d species\n", nrow(climate_summary)))

# Check if bio6_sd exists for tmin variability
has_bio6_sd <- "bio6_sd" %in% names(climate_summary)

# Create climate features (following Stage 1 pattern from hybrid_trait_bioclim_comprehensive.R)
cat("\nProcessing climate features...\n")
climate_features <- climate_summary %>%
  select(
    species,
    # Raw bioclim variables for reference
    bio1_mean, bio1_sd, bio4_mean, bio5_mean, bio6_mean, bio7_mean,
    bio12_mean, bio12_sd, bio14_mean, bio15_mean, bio17_mean, bio18_mean, bio19_mean,
    # Optional bio6_sd if available
    any_of(c("bio6_sd")),
    # Aridity metrics
    any_of(c("ai_month_min", "ai_amp", "ai_cv_month", "ai_roll3_min"))
  ) %>%
  mutate(
    # Temperature metrics (matching Stage 1)
    mat_mean = bio1_mean,
    mat_sd = bio1_sd,
    temp_seasonality = bio4_mean,
    temp_range = bio7_mean,
    tmax_mean = bio5_mean,
    tmin_mean = bio6_mean,

    # Precipitation metrics
    precip_mean = bio12_mean,
    precip_sd = bio12_sd,
    drought_min = bio14_mean,
    precip_seasonality = bio15_mean,
    precip_driest_q = bio17_mean,
    precip_warmest_q = bio18_mean,
    precip_coldest_q = bio19_mean,

    # Derived metrics
    precip_cv = bio12_sd / pmax(bio12_mean, 1),

    # Approximate quantiles (using normal approximation)
    mat_q05 = bio1_mean - 1.645 * bio1_sd,
    mat_q95 = bio1_mean + 1.645 * bio1_sd
  )

# Add tmin_q05 based on available data
if (has_bio6_sd) {
  climate_features <- climate_features %>%
    mutate(tmin_q05 = bio6_mean - 1.645 * bio6_sd)
} else {
  climate_features <- climate_features %>%
    mutate(tmin_q05 = bio6_mean - 1.645 * (bio1_sd * 0.5))  # Approximate from mat_sd
}

# Select final climate columns
climate_features <- climate_features %>%
  select(species,
         mat_mean, mat_sd, mat_q05, mat_q95, temp_seasonality, temp_range,
         tmax_mean, tmin_mean, tmin_q05,
         precip_mean, precip_sd, precip_cv, precip_seasonality,
         precip_driest_q, precip_warmest_q, precip_coldest_q,
         drought_min,
         any_of(c("ai_month_min", "ai_amp", "ai_cv_month", "ai_roll3_min")))

# Merge with model data
cat("\nMerging climate features with model data...\n")
enhanced_data <- model_data %>%
  left_join(climate_features, by = c("wfo_accepted_name" = "species"))

# Report merge statistics
n_matched <- sum(!is.na(enhanced_data$mat_mean))
n_missing <- sum(is.na(enhanced_data$mat_mean))
cat(sprintf("  Matched: %d species (%.1f%%)\n", n_matched, 100 * n_matched / nrow(enhanced_data)))
cat(sprintf("  Missing: %d species (%.1f%%)\n", n_missing, 100 * n_missing / nrow(enhanced_data)))

# Create interaction features (critical for performance)
cat("\nCreating interaction features...\n")

# Helper function for safe log transformation
safe_log10 <- function(x, offset = 0.001) {
  log10(pmax(x, 0) + offset)
}

# Extract columns with spaces for easier manipulation
if ("LMA (g/m2)" %in% names(enhanced_data)) {
  lma_col <- enhanced_data[["LMA (g/m2)"]]
} else {
  lma_col <- rep(NA, nrow(enhanced_data))
}

if ("Plant height (m)" %in% names(enhanced_data)) {
  height_col <- enhanced_data[["Plant height (m)"]]
} else {
  height_col <- rep(NA, nrow(enhanced_data))
}

if ("SSD used (mg/mm3)" %in% names(enhanced_data)) {
  ssd_col <- enhanced_data[["SSD used (mg/mm3)"]]
} else {
  ssd_col <- rep(NA, nrow(enhanced_data))
}

if ("Diaspore mass (mg)" %in% names(enhanced_data)) {
  diaspore_col <- enhanced_data[["Diaspore mass (mg)"]]
} else {
  diaspore_col <- rep(NA, nrow(enhanced_data))
}

precip_mean_col <- if ("precip_mean" %in% names(enhanced_data)) enhanced_data$precip_mean else rep(NA, nrow(enhanced_data))
mat_mean_col <- if ("mat_mean" %in% names(enhanced_data)) enhanced_data$mat_mean else rep(NA, nrow(enhanced_data))

# Create interactions
if (length(lma_col) > 0 && length(precip_mean_col) > 0) {
  enhanced_data$lma_precip <- ifelse(
    !is.na(lma_col) & !is.na(precip_mean_col),
    lma_col * precip_mean_col / 1000,
    NA
  )
} else {
  enhanced_data$lma_precip <- NA
}

if (length(height_col) > 0 && length(mat_mean_col) > 0) {
  enhanced_data$height_temp <- ifelse(
    !is.na(height_col) & !is.na(mat_mean_col),
    safe_log10(height_col) * mat_mean_col,
    NA
  )
} else {
  enhanced_data$height_temp <- NA
}

if (length(height_col) > 0 && length(ssd_col) > 0) {
  enhanced_data$height_ssd <- ifelse(
    !is.na(height_col) & !is.na(ssd_col),
    safe_log10(height_col) * safe_log10(ssd_col),
    NA
  )
} else {
  enhanced_data$height_ssd <- NA
}

if (length(height_col) > 0 && length(diaspore_col) > 0 && length(mat_mean_col) > 0) {
  enhanced_data$size_temp <- ifelse(
    !is.na(height_col) & !is.na(diaspore_col) & !is.na(mat_mean_col),
    safe_log10(sqrt(height_col * diaspore_col)) * mat_mean_col,
    NA
  )
} else {
  enhanced_data$size_temp <- NA
}

if (length(height_col) > 0 && length(diaspore_col) > 0 && length(precip_mean_col) > 0) {
  enhanced_data$size_precip <- ifelse(
    !is.na(height_col) & !is.na(diaspore_col) & !is.na(precip_mean_col),
    safe_log10(sqrt(height_col * diaspore_col)) * precip_mean_col / 1000,
    NA
  )
} else {
  enhanced_data$size_precip <- NA
}

# Placeholder for LES-based interactions (computed within pwSEM)
enhanced_data$les_seasonality <- NA
enhanced_data$les_drought <- NA
enhanced_data$les_ai <- NA

# Count created features
n_interactions <- sum(!is.na(enhanced_data$lma_precip))
cat(sprintf("  Created interaction features for %d species\n", n_interactions))

# Save enhanced dataset - preserve column names
output_path <- "artifacts/model_data_bioclim_subset_with_climate.csv"
cat(sprintf("\nSaving enhanced data to %s...\n", output_path))

# Write with quote=TRUE to preserve column names with spaces
write.csv(enhanced_data, output_path, row.names = FALSE, quote = TRUE)

# Report final statistics
cat("\n========================================\n")
cat("Feature Coverage Summary:\n")
cat("========================================\n")
cat(sprintf("Total species: %d\n", nrow(enhanced_data)))
cat(sprintf("Original features: %d\n", ncol(model_data)))
cat(sprintf("Enhanced features: %d\n", ncol(enhanced_data)))
cat(sprintf("New climate features: %d\n", ncol(enhanced_data) - ncol(model_data)))

# Check coverage for key features
key_features <- c("mat_mean", "mat_q05", "precip_seasonality", "lma_precip", "height_temp")
cat("\nKey feature coverage:\n")
for (feat in key_features) {
  if (feat %in% names(enhanced_data)) {
    coverage <- sum(!is.na(enhanced_data[[feat]])) / nrow(enhanced_data) * 100
    cat(sprintf("  %-20s: %.1f%%\n", feat, coverage))
  } else {
    cat(sprintf("  %-20s: MISSING\n", feat))
  }
}

# Check for T axis specific requirements
t_axis_critical <- c("mat_mean", "mat_q05", "mat_q95", "precip_seasonality",
                      "temp_seasonality", "lma_precip", "height_temp")
t_axis_available <- intersect(t_axis_critical, names(enhanced_data))
cat(sprintf("\nT axis critical features: %d/%d available\n",
            length(t_axis_available), length(t_axis_critical)))

if (length(t_axis_available) < length(t_axis_critical)) {
  missing_t <- setdiff(t_axis_critical, t_axis_available)
  cat("  Missing: ", paste(missing_t, collapse = ", "), "\n")
}

cat("\n✓ Enhanced model data preparation complete\n")
#!/usr/bin/env Rscript
#' Stratified Accuracy Check Across Similarity Ranges
#'
#' Extracts samples from different similarity bands to assess
#' how accuracy varies with similarity score.
#'
#' Input:
#'   - data/taxonomy/vector_classifications_bilingual.parquet
#'
#' Output:
#'   - reports/taxonomy/stratified_accuracy_check.csv
#'
#' Date: 2025-11-15

suppressPackageStartupMessages({
  library(duckdb)
  library(dplyr)
  library(arrow)
})

cat("=", rep("=", 78), "\n", sep = "")
cat("Stratified Accuracy Check - Multiple Similarity Bands\n")
cat("=", rep("=", 78), "\n\n", sep = "")

# ============================================================================
# Configuration
# ============================================================================

BILINGUAL_FILE <- "/home/olier/ellenberg/data/taxonomy/vector_classifications_bilingual.parquet"
OUTPUT_FILE <- "/home/olier/ellenberg/reports/taxonomy/stratified_accuracy_check.csv"

N_PER_BAND <- 15  # Samples per band per language

# Define similarity bands
bands <- list(
  list(name = "0.50-0.55", min = 0.50, max = 0.55),
  list(name = "0.55-0.60", min = 0.55, max = 0.60),
  list(name = "0.60-0.65", min = 0.60, max = 0.65),
  list(name = "0.65+", min = 0.65, max = 1.00)
)

# ============================================================================
# Load Data
# ============================================================================

cat("Loading bilingual classifications...\n")
bilingual <- read_parquet(BILINGUAL_FILE)
cat(sprintf("  Loaded %d genera\n\n", nrow(bilingual)))

# ============================================================================
# Extract Samples from Each Band
# ============================================================================

cat("Extracting samples from similarity bands...\n\n")

all_samples <- list()
review_id <- 1

for (band in bands) {
  cat(sprintf("Band: %s (%.2f - %.2f)\n", band$name, band$min, band$max))

  # English samples
  english_band <- bilingual %>%
    filter(!is.na(en_category),
           source == "english",
           en_similarity >= band$min,
           en_similarity < band$max) %>%
    sample_n(min(N_PER_BAND, n())) %>%
    mutate(
      review_id = review_id:(review_id + n() - 1),
      language = "English",
      band = band$name
    ) %>%
    select(
      review_id,
      band,
      language,
      genus,
      category = en_category,
      similarity = en_similarity,
      top3_categories = top3_categories_en,
      top3_scores
    )

  review_id <- review_id + nrow(english_band)

  cat(sprintf("  English: %d samples (mean: %.4f)\n",
              nrow(english_band),
              mean(english_band$similarity)))

  # Chinese samples
  chinese_band <- bilingual %>%
    filter(!is.na(zh_category),
           source == "chinese",
           zh_similarity >= band$min,
           zh_similarity < band$max) %>%
    sample_n(min(N_PER_BAND, n())) %>%
    mutate(
      review_id = review_id:(review_id + n() - 1),
      language = "Chinese",
      band = band$name
    ) %>%
    select(
      review_id,
      band,
      language,
      genus,
      category = zh_category,
      similarity = zh_similarity,
      top3_categories = top3_categories_zh,
      top3_scores
    )

  review_id <- review_id + nrow(chinese_band)

  cat(sprintf("  Chinese: %d samples (mean: %.4f)\n\n",
              nrow(chinese_band),
              mean(chinese_band$similarity)))

  all_samples[[length(all_samples) + 1]] <- english_band
  all_samples[[length(all_samples) + 1]] <- chinese_band
}

# ============================================================================
# Combine and Add Review Columns
# ============================================================================

stratified_check <- bind_rows(all_samples) %>%
  mutate(
    correct = NA_character_,
    notes = NA_character_
  )

# ============================================================================
# Write Output
# ============================================================================

cat("Writing output...\n")
cat(sprintf("  Output: %s\n", OUTPUT_FILE))

write.csv(stratified_check, OUTPUT_FILE, row.names = FALSE)

cat(sprintf("\n✓ Successfully wrote %d samples for manual review\n", nrow(stratified_check)))

# ============================================================================
# Summary
# ============================================================================

cat("\n", rep("=", 80), "\n", sep = "")
cat("Summary\n")
cat(rep("=", 80), "\n\n", sep = "")

summary_table <- stratified_check %>%
  group_by(band, language) %>%
  summarise(
    n = n(),
    min_sim = min(similarity),
    mean_sim = mean(similarity),
    max_sim = max(similarity),
    .groups = "drop"
  )

cat("Samples by band:\n")
for (i in 1:nrow(summary_table)) {
  cat(sprintf("  %s (%s): %d samples (%.4f - %.4f, mean: %.4f)\n",
              summary_table$band[i],
              summary_table$language[i],
              summary_table$n[i],
              summary_table$min_sim[i],
              summary_table$max_sim[i],
              summary_table$mean_sim[i]))
}

cat("\nNext steps:\n")
cat("  1. Open reports/taxonomy/stratified_accuracy_check.csv\n")
cat("  2. Review each match and mark 'correct' column (yes/no)\n")
cat("  3. Calculate accuracy % for each similarity band\n")

cat("\n", rep("=", 80), "\n", sep = "")
cat("Complete\n")
cat(rep("=", 80), "\n\n", sep = "")

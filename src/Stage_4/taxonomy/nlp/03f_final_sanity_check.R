#!/usr/bin/env Rscript
#' Final Sanity Check - Lowest 30 Matches per Language
#'
#' Extracts the 30 lowest-scoring matches from both English and Chinese
#' classifications at the standardized 0.45 threshold for manual review.
#'
#' Input:
#'   - data/taxonomy/vector_classifications_bilingual.parquet
#'
#' Output:
#'   - reports/taxonomy/final_sanity_check_0.45.csv
#'
#' Date: 2025-11-15

suppressPackageStartupMessages({
  library(duckdb)
  library(dplyr)
  library(arrow)
})

cat("=", rep("=", 78), "\n", sep = "")
cat("Final Sanity Check - Lowest Matches @ 0.45 Threshold\n")
cat("=", rep("=", 78), "\n\n", sep = "")

# ============================================================================
# Configuration
# ============================================================================

BILINGUAL_FILE <- "/home/olier/ellenberg/data/taxonomy/vector_classifications_bilingual.parquet"
OUTPUT_FILE <- "/home/olier/ellenberg/reports/taxonomy/final_sanity_check_0.45.csv"

N_SAMPLES <- 30  # Number of lowest-scoring examples per language

# ============================================================================
# Load Data
# ============================================================================

cat("Loading bilingual classifications...\n")
bilingual <- read_parquet(BILINGUAL_FILE)
cat(sprintf("  Loaded %d genera\n\n", nrow(bilingual)))

# ============================================================================
# Extract Lowest Matches per Source
# ============================================================================

cat("Extracting lowest-scoring matches...\n")

# English: Get bottom 30 by similarity
english_low <- bilingual %>%
  filter(!is.na(en_category), source == "english") %>%
  arrange(en_similarity) %>%
  head(N_SAMPLES) %>%
  mutate(
    review_id = 1:n(),
    language = "English"
  ) %>%
  select(
    review_id,
    language,
    genus,
    category = en_category,
    similarity = en_similarity,
    top3_categories = top3_categories_en,
    top3_scores
  )

cat(sprintf("  English: %d samples (min: %.4f, max: %.4f)\n",
            nrow(english_low),
            min(english_low$similarity),
            max(english_low$similarity)))

# Chinese: Get bottom 30 by similarity (from Chinese-only matches)
chinese_low <- bilingual %>%
  filter(!is.na(zh_category), source == "chinese") %>%
  arrange(zh_similarity) %>%
  head(N_SAMPLES) %>%
  mutate(
    review_id = (N_SAMPLES + 1):(N_SAMPLES + n()),
    language = "Chinese"
  ) %>%
  select(
    review_id,
    language,
    genus,
    category = zh_category,
    similarity = zh_similarity,
    top3_categories = top3_categories_zh,
    top3_scores
  )

cat(sprintf("  Chinese: %d samples (min: %.4f, max: %.4f)\n\n",
            nrow(chinese_low),
            min(chinese_low$similarity),
            max(chinese_low$similarity)))

# ============================================================================
# Combine and Add Review Columns
# ============================================================================

sanity_check <- bind_rows(english_low, chinese_low) %>%
  mutate(
    correct = NA_character_,
    notes = NA_character_
  )

# ============================================================================
# Write Output
# ============================================================================

cat("Writing output...\n")
cat(sprintf("  Output: %s\n", OUTPUT_FILE))

write.csv(sanity_check, OUTPUT_FILE, row.names = FALSE)

cat(sprintf("\n✓ Successfully wrote %d samples for manual review\n", nrow(sanity_check)))

# ============================================================================
# Summary
# ============================================================================

cat("\n", rep("=", 80), "\n", sep = "")
cat("Summary\n")
cat(rep("=", 80), "\n\n", sep = "")

cat("Samples extracted:\n")
cat(sprintf("  English (bottom 30): similarity range %.4f - %.4f\n",
            min(english_low$similarity),
            max(english_low$similarity)))
cat(sprintf("  Chinese (bottom 30): similarity range %.4f - %.4f\n",
            min(chinese_low$similarity),
            max(chinese_low$similarity)))

cat("\nNext steps:\n")
cat("  1. Open reports/taxonomy/final_sanity_check_0.45.csv\n")
cat("  2. Review each match and mark 'correct' column (yes/no)\n")
cat("  3. Add notes for borderline or interesting cases\n")

cat("\n", rep("=", 80), "\n", sep = "")
cat("Complete\n")
cat(rep("=", 80), "\n\n", sep = "")

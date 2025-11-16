#!/usr/bin/env Rscript
#' Sanity Check: Review Lowest-Scoring Categorizations
#'
#' Extracts the 30 lowest-scoring matches from both English and Chinese
#' classifications for manual quality review.
#'
#' Input:
#'   - data/taxonomy/vector_classifications_kalm.parquet
#'   - data/taxonomy/vector_classifications_kalm_chinese.parquet
#'
#' Output:
#'   - reports/sanity_check_low_scores.csv
#'
#' Date: 2025-11-15

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(readr)
})

cat("=", rep("=", 78), "\n", sep = "")
cat("Sanity Check: Low-Scoring Classifications\n")
cat("=", rep("=", 78), "\n\n", sep = "")

# ============================================================================
# Configuration
# ============================================================================

ENGLISH_FILE <- "/home/olier/ellenberg/data/taxonomy/vector_classifications_kalm.parquet"
CHINESE_FILE <- "/home/olier/ellenberg/data/taxonomy/vector_classifications_kalm_chinese.parquet"
OUTPUT_FILE <- "/home/olier/ellenberg/reports/sanity_check_low_scores.csv"

N_SAMPLES <- 30  # Number of lowest-scoring examples to review per language

# ============================================================================
# Load Data
# ============================================================================

cat("Loading classification results...\n")

# Load English results
english_df <- read_parquet(ENGLISH_FILE)
cat(sprintf("  English: %d genera\n", nrow(english_df)))

# Load Chinese results
chinese_df <- read_parquet(CHINESE_FILE)
cat(sprintf("  Chinese: %d genera\n", nrow(chinese_df)))

# ============================================================================
# Extract Lowest-Scoring Matches
# ============================================================================

cat("\nExtracting lowest-scoring matches for review...\n")

# English: Get bottom 30 by similarity (categorized only)
english_low <- english_df %>%
  filter(!is.na(vector_category)) %>%
  arrange(vector_similarity) %>%
  head(N_SAMPLES) %>%
  mutate(
    language = "English",
    genus_name = genus,
    category = vector_category,
    similarity = vector_similarity,
    top3_categories = vector_top3_categories,
    top3_scores = vector_top3_scores
  ) %>%
  select(language, genus_name, category, similarity, top3_categories, top3_scores)

cat(sprintf("  English: %d low-scoring matches (similarity %.3f - %.3f)\n",
            nrow(english_low),
            min(english_low$similarity),
            max(english_low$similarity)))

# Chinese: Get bottom 30 by similarity (categorized only)
chinese_low <- chinese_df %>%
  filter(!is.na(vector_category_zh)) %>%
  arrange(vector_similarity) %>%
  head(N_SAMPLES) %>%
  mutate(
    language = "Chinese",
    genus_name = genus,
    category = paste0(vector_category_zh, " (", vector_category_en, ")"),
    similarity = vector_similarity,
    top3_categories = paste0(vector_top3_categories_zh, " (", vector_top3_categories_en, ")"),
    top3_scores = vector_top3_scores
  ) %>%
  select(language, genus_name, category, similarity, top3_categories, top3_scores)

cat(sprintf("  Chinese: %d low-scoring matches (similarity %.3f - %.3f)\n",
            nrow(chinese_low),
            min(chinese_low$similarity),
            max(chinese_low$similarity)))

# ============================================================================
# Combine and Sort
# ============================================================================

cat("\nCombining results...\n")

review_df <- bind_rows(english_low, chinese_low) %>%
  arrange(language, similarity) %>%
  mutate(
    review_id = row_number(),
    correct = "",  # For manual review: Y/N/Uncertain
    notes = ""      # For manual notes
  ) %>%
  select(review_id, language, genus_name, category, similarity,
         top3_categories, top3_scores, correct, notes)

# ============================================================================
# Summary Statistics
# ============================================================================

cat("\n", rep("=", 80), "\n", sep = "")
cat("Summary\n")
cat(rep("=", 80), "\n", sep = "")

cat(sprintf("\nTotal samples for review: %d\n", nrow(review_df)))
cat(sprintf("  English: %d (similarity %.3f - %.3f)\n",
            sum(review_df$language == "English"),
            min(review_df$similarity[review_df$language == "English"]),
            max(review_df$similarity[review_df$language == "English"])))
cat(sprintf("  Chinese: %d (similarity %.3f - %.3f)\n",
            sum(review_df$language == "Chinese"),
            min(review_df$similarity[review_df$language == "Chinese"]),
            max(review_df$similarity[review_df$language == "Chinese"])))

cat("\nSimilarity ranges by language:\n")
cat(sprintf("  English threshold: 0.45 (lowest actual: %.3f)\n",
            min(review_df$similarity[review_df$language == "English"])))
cat(sprintf("  Chinese threshold: 0.42 (lowest actual: %.3f)\n",
            min(review_df$similarity[review_df$language == "Chinese"])))

# ============================================================================
# Write Output
# ============================================================================

cat("\nWriting output...\n")
cat(sprintf("  Output: %s\n", OUTPUT_FILE))

write_csv(review_df, OUTPUT_FILE)

cat(sprintf("\n✓ Successfully wrote %d samples for manual review\n", nrow(review_df)))

# ============================================================================
# Instructions
# ============================================================================

cat("\n", rep("=", 80), "\n", sep = "")
cat("Manual Review Instructions\n")
cat(rep("=", 80), "\n", sep = "")
cat("\n")
cat("1. Open the CSV file in a spreadsheet editor\n")
cat("2. For each row, verify if the assigned category is correct\n")
cat("3. Mark the 'correct' column:\n")
cat("   - Y = Correct categorization\n")
cat("   - N = Incorrect categorization\n")
cat("   - U = Uncertain (needs expert review)\n")
cat("4. Add notes in the 'notes' column if needed\n")
cat("5. Focus on samples near the threshold (lowest similarities)\n")
cat("\n")
cat("These represent the LEAST confident predictions.\n")
cat("If these are mostly correct, higher-scoring matches are very reliable.\n")
cat("\n", rep("=", 80), "\n\n", sep = "")

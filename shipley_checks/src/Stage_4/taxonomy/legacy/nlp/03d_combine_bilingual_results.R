#!/usr/bin/env Rscript
#' Combine English and Chinese Vector Classifications
#'
#' Merges English and Chinese vector classification results with priority:
#' 1. English classification (if available and above threshold)
#' 2. Chinese classification (if English not available and above threshold)
#'
#' Input:
#'   - data/taxonomy/vector_classifications_kalm.parquet (English)
#'   - data/taxonomy/vector_classifications_kalm_chinese.parquet (Chinese)
#'   - data/taxonomy/target_genera.parquet
#'
#' Output:
#'   - data/taxonomy/vector_classifications_bilingual.parquet
#'
#' Date: 2025-11-15

suppressPackageStartupMessages({
  library(duckdb)
  library(dplyr)
  library(arrow)
})

cat("=", rep("=", 78), "\n", sep = "")
cat("Combining English + Chinese Vector Classifications\n")
cat("=", rep("=", 78), "\n\n", sep = "")

# ============================================================================
# Configuration
# ============================================================================

TARGET_GENERA_FILE <- "/home/olier/ellenberg/data/taxonomy/target_genera.parquet"
ENGLISH_FILE <- "/home/olier/ellenberg/data/taxonomy/vector_classifications_kalm.parquet"
CHINESE_FILE <- "/home/olier/ellenberg/data/taxonomy/vector_classifications_kalm_chinese.parquet"
OUTPUT_FILE <- "/home/olier/ellenberg/data/taxonomy/vector_classifications_bilingual.parquet"

# Thresholds (standardized for quality)
ENGLISH_THRESHOLD <- 0.45  # Optimized from threshold analysis
CHINESE_THRESHOLD <- 0.45  # Standardized with English for consistency

# ============================================================================
# Connect to DuckDB
# ============================================================================

cat("Connecting to DuckDB...\n")
con <- dbConnect(duckdb::duckdb())

# ============================================================================
# Load Data
# ============================================================================

cat("\nLoading data...\n")

# Load target genera
target_genera <- read_parquet(TARGET_GENERA_FILE)
cat(sprintf("  Target genera: %d\n", nrow(target_genera)))

# Load English classifications
english_results <- read_parquet(ENGLISH_FILE)
cat(sprintf("  English results: %d genera\n", nrow(english_results)))

# Load Chinese classifications (if exists)
if (file.exists(CHINESE_FILE)) {
  chinese_results <- read_parquet(CHINESE_FILE)
  cat(sprintf("  Chinese results: %d genera\n", nrow(chinese_results)))
  has_chinese <- TRUE
} else {
  cat("  Chinese results not yet generated - using English only\n")
  has_chinese <- FALSE
}

# ============================================================================
# Apply Thresholds
# ============================================================================

cat("\nApplying similarity thresholds...\n")
cat(sprintf("  English threshold: %.2f\n", ENGLISH_THRESHOLD))
if (has_chinese) {
  cat(sprintf("  Chinese threshold: %.2f\n", CHINESE_THRESHOLD))
}

# Filter English results to threshold
english_filtered <- english_results %>%
  mutate(
    meets_threshold = vector_similarity >= ENGLISH_THRESHOLD,
    category_en = ifelse(meets_threshold, vector_category, NA_character_),
    category_index = ifelse(meets_threshold, NA_character_, NA_character_),  # Will add index later
    similarity_en = ifelse(meets_threshold, vector_similarity, NA_real_),
    source = ifelse(meets_threshold, "english", NA_character_)
  ) %>%
  select(genus, category_en, similarity_en, source,
         top3_en = vector_top3_categories,
         top3_scores_en = vector_top3_scores)

n_en_categorized <- sum(!is.na(english_filtered$category_en))
cat(sprintf("  English: %d categorized (%.1f%%)\n",
            n_en_categorized,
            n_en_categorized / nrow(english_filtered) * 100))

# Filter Chinese results to threshold
if (has_chinese) {
  chinese_filtered <- chinese_results %>%
    mutate(
      meets_threshold = vector_similarity >= CHINESE_THRESHOLD,
      category_zh = ifelse(meets_threshold, vector_category_zh, NA_character_),
      category_en_from_zh = ifelse(meets_threshold, vector_category_en, NA_character_),
      category_index = ifelse(meets_threshold, category_index, NA_character_),
      similarity_zh = ifelse(meets_threshold, vector_similarity, NA_real_),
      source_zh = ifelse(meets_threshold, "chinese", NA_character_)
    ) %>%
    select(genus, category_zh, category_en_from_zh, category_index,
           similarity_zh, source_zh,
           top3_zh = vector_top3_categories_zh,
           top3_en_from_zh = vector_top3_categories_en,
           top3_scores_zh = vector_top3_scores)

  n_zh_categorized <- sum(!is.na(chinese_filtered$category_zh))
  cat(sprintf("  Chinese: %d categorized (%.1f%%)\n",
              n_zh_categorized,
              n_zh_categorized / nrow(chinese_filtered) * 100))
}

# ============================================================================
# Combine with Priority Logic
# ============================================================================

cat("\nCombining classifications with priority...\n")
cat("  Priority: English > Chinese\n")

# Start with all target genera
combined <- target_genera %>%
  select(genus) %>%
  left_join(english_filtered, by = "genus")

if (has_chinese) {
  combined <- combined %>%
    left_join(chinese_filtered, by = "genus") %>%
    mutate(
      # Final category: English if available, else Chinese
      final_category_en = coalesce(category_en, category_en_from_zh),
      final_category_zh = case_when(
        !is.na(category_en) ~ NA_character_,  # No Chinese if English available
        !is.na(category_zh) ~ category_zh,
        TRUE ~ NA_character_
      ),
      final_similarity = coalesce(similarity_en, similarity_zh),
      final_source = coalesce(source, source_zh),
      final_category_index = category_index,
      # Store original categories for summary
      orig_en_category = category_en,
      orig_en_similarity = similarity_en,
      orig_zh_category = category_zh,
      orig_zh_similarity = similarity_zh,
      # Store top3 scores
      orig_top3_scores = coalesce(top3_scores_en, top3_scores_zh)
    ) %>%
    select(
      genus,
      category_en = final_category_en,
      category_zh = final_category_zh,
      category_index = final_category_index,
      similarity = final_similarity,
      source = final_source,
      # Keep individual results for reference
      en_category = orig_en_category,
      en_similarity = orig_en_similarity,
      zh_category = orig_zh_category,
      zh_similarity = orig_zh_similarity,
      # Top 3 matches
      top3_categories_en = top3_en,
      top3_categories_zh = top3_zh,
      top3_scores = orig_top3_scores
    )
} else {
  combined <- combined %>%
    mutate(
      category_zh = NA_character_,
      category_index = NA_character_,
      similarity = similarity_en,
      final_source = source,
      en_category = category_en,
      en_similarity = similarity_en,
      zh_category = NA_character_,
      zh_similarity = NA_real_,
      top3_categories_zh = NA_character_,
      top3_scores = top3_scores_en
    ) %>%
    select(
      genus, category_en, category_zh, category_index,
      similarity, source = final_source,
      en_category, en_similarity,
      zh_category, zh_similarity,
      top3_categories_en = top3_en,
      top3_categories_zh,
      top3_scores
    )
}

# ============================================================================
# Summary Statistics
# ============================================================================

cat("\n", rep("=", 80), "\n", sep = "")
cat("Summary Statistics\n")
cat(rep("=", 80), "\n", sep = "")

total_genera <- nrow(combined)
n_categorized <- sum(!is.na(combined$category_en))
n_uncategorized <- sum(is.na(combined$category_en))

cat(sprintf("\nTotal target genera: %d\n", total_genera))
cat(sprintf("Categorized: %d (%.1f%%)\n",
            n_categorized, n_categorized / total_genera * 100))
cat(sprintf("Uncategorized: %d (%.1f%%)\n",
            n_uncategorized, n_uncategorized / total_genera * 100))

# Breakdown by source
cat("\nCategorization source:\n")
source_breakdown <- combined %>%
  filter(!is.na(category_en)) %>%
  count(source) %>%
  arrange(desc(n))

for (i in 1:nrow(source_breakdown)) {
  cat(sprintf("  %s: %d (%.1f%%)\n",
              source_breakdown$source[i],
              source_breakdown$n[i],
              source_breakdown$n[i] / n_categorized * 100))
}

# Coverage gain from Chinese
if (has_chinese) {
  n_english_only <- sum(!is.na(combined$en_category))
  n_chinese_only <- sum(is.na(combined$en_category) & !is.na(combined$zh_category))
  n_both <- sum(!is.na(combined$en_category) & !is.na(combined$zh_category))

  cat("\nLanguage coverage:\n")
  cat(sprintf("  English only: %d\n", n_english_only))
  cat(sprintf("  Chinese fills gaps: %d\n", n_chinese_only))
  cat(sprintf("  Coverage gain: +%.1f%%\n",
              n_chinese_only / total_genera * 100))
}

# Similarity statistics
cat("\nSimilarity statistics (categorized genera):\n")
cat_similarities <- combined %>%
  filter(!is.na(category_en)) %>%
  pull(similarity)

cat(sprintf("  Mean: %.4f\n", mean(cat_similarities)))
cat(sprintf("  Median: %.4f\n", median(cat_similarities)))
cat(sprintf("  Min: %.4f\n", min(cat_similarities)))
cat(sprintf("  Max: %.4f\n", max(cat_similarities)))

# Top 10 categories
cat("\nTop 10 categories:\n")
top_categories <- combined %>%
  filter(!is.na(category_en)) %>%
  count(category_en) %>%
  arrange(desc(n)) %>%
  head(10)

for (i in 1:nrow(top_categories)) {
  pct <- top_categories$n[i] / n_categorized * 100
  cat(sprintf("  %d. %s: %d (%.1f%%)\n",
              i, top_categories$category_en[i],
              top_categories$n[i], pct))
}

# ============================================================================
# Write Output
# ============================================================================

cat("\nWriting output...\n")
cat(sprintf("  Output: %s\n", OUTPUT_FILE))

write_parquet(combined, OUTPUT_FILE)

cat(sprintf("\n✓ Successfully wrote %d genera with bilingual classifications\n",
            nrow(combined)))

# ============================================================================
# Cleanup
# ============================================================================

dbDisconnect(con, shutdown = TRUE)

cat("\n", rep("=", 80), "\n", sep = "")
cat("Complete\n")
cat(rep("=", 80), "\n\n", sep = "")

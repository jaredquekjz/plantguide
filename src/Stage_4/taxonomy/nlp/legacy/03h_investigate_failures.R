#!/usr/bin/env Rscript
#' Investigate Classification Failures - Raw Data Analysis
#'
#' Examines raw vernacular names and their categorizations to understand
#' why semantic matching is performing poorly.
#'
#' Input:
#'   - data/taxonomy/genus_vernacular_aggregations.parquet
#'   - data/taxonomy/vector_classifications_bilingual.parquet
#'
#' Output:
#'   - reports/taxonomy/classification_failure_analysis.csv
#'
#' Date: 2025-11-15

suppressPackageStartupMessages({
  library(duckdb)
  library(dplyr)
  library(arrow)
  library(stringr)
})

cat("=", rep("=", 78), "\n", sep = "")
cat("Classification Failure Analysis - Raw Vernacular Data\n")
cat("=", rep("=", 78), "\n\n", sep = "")

# ============================================================================
# Configuration
# ============================================================================

ENGLISH_VERNACULARS <- "/home/olier/ellenberg/data/taxonomy/genus_vernacular_aggregations.parquet"
CHINESE_VERNACULARS <- "/home/olier/ellenberg/data/taxonomy/genus_vernacular_aggregations_chinese.parquet"
BILINGUAL_RESULTS <- "/home/olier/ellenberg/data/taxonomy/vector_classifications_bilingual.parquet"
OUTPUT_FILE <- "/home/olier/ellenberg/reports/taxonomy/classification_failure_analysis.csv"

# ============================================================================
# Load Data
# ============================================================================

cat("Loading data...\n")
english_vern <- read_parquet(ENGLISH_VERNACULARS)
chinese_vern <- read_parquet(CHINESE_VERNACULARS)
results <- read_parquet(BILINGUAL_RESULTS)
cat(sprintf("  English vernaculars: %d genera\n", nrow(english_vern)))
cat(sprintf("  Chinese vernaculars: %d genera\n", nrow(chinese_vern)))
cat(sprintf("  Classification results: %d genera\n\n", nrow(results)))

# ============================================================================
# Sample Cases Across Similarity Ranges
# ============================================================================

cat("Selecting sample cases...\n\n")

# Take some known problematic cases from our manual review
problem_cases <- c(
  # High similarity but wrong
  "Tanysphyrus",  # 0.841 → duckweeds (actually weevil)
  "Glycobius",    # 0.719 → maples (actually beetle)
  "Paragrilus",   # 0.733 → woodpeckers (actually beetle)
  "Euschemon",    # 0.670 → skinks (actually butterfly)
  "Eidolon",      # 0.584 → strawberries (actually bat)

  # Medium similarity
  "Symbrenthia",  # ~0.52 → warblers (actually butterfly)
  "Rhizophora",   # 0.514 → magnolias (actually mangrove)
  "Liparis",      # 0.588 → snails (orchid/fish)

  # Correct cases for comparison
  "Boloria",      # 0.567 → butterflies ✓
  "Arctia",       # 0.577 → moths ✓
  "Heilipus",     # 0.820 → weevils ✓
  "Oxya",         # 0.677 → grasshoppers ✓

  # Low similarity
  "Apodemia",     # 0.450 → butterflies ✓
  "Myrsine",      # 0.450 → maples ✗
  "Graphium"      # 0.451 → butterflies ✓
)

# ============================================================================
# Extract Detailed Information
# ============================================================================

cat("Extracting detailed information for sample cases...\n")

detailed_cases <- list()

for (genus_name in problem_cases) {
  # Get classification result
  result_row <- results %>%
    filter(genus == genus_name) %>%
    slice(1)

  if (nrow(result_row) == 0) {
    cat(sprintf("  Warning: %s not found in results\n", genus_name))
    next
  }

  # Get English vernaculars
  eng_vern <- english_vern %>%
    filter(genus == genus_name) %>%
    pull(vernaculars_all)

  # Get Chinese vernaculars
  chn_vern <- chinese_vern %>%
    filter(genus == genus_name) %>%
    pull(vernaculars_all)

  # Determine which was used for classification
  if (!is.na(result_row$en_category) && result_row$source == "english") {
    used_language <- "English"
    used_vernaculars <- eng_vern
    assigned_category <- result_row$en_category
    similarity <- result_row$en_similarity
    top3_cats <- result_row$top3_categories_en
    top3_scores <- result_row$top3_scores
  } else if (!is.na(result_row$zh_category) && result_row$source == "chinese") {
    used_language <- "Chinese"
    used_vernaculars <- chn_vern
    assigned_category <- result_row$zh_category
    similarity <- result_row$zh_similarity
    top3_cats <- result_row$top3_categories_zh
    top3_scores <- result_row$top3_scores
  } else {
    used_language <- "None"
    used_vernaculars <- NA_character_
    assigned_category <- NA_character_
    similarity <- NA_real_
    top3_cats <- NA_character_
    top3_scores <- NA_character_
  }

  # Truncate vernaculars if too long (keep first 200 chars)
  if (length(used_vernaculars) == 0 || is.na(used_vernaculars[1])) {
    vernacular_display <- NA_character_
  } else if (nchar(used_vernaculars[1]) > 200) {
    vernacular_display <- paste0(substr(used_vernaculars[1], 1, 200), "...")
  } else {
    vernacular_display <- used_vernaculars[1]
  }

  detailed_cases[[length(detailed_cases) + 1]] <- data.frame(
    genus = genus_name,
    language = used_language,
    vernaculars = vernacular_display,
    assigned_category = assigned_category,
    similarity = similarity,
    top3_categories = top3_cats,
    top3_scores = top3_scores,
    stringsAsFactors = FALSE
  )
}

analysis_df <- bind_rows(detailed_cases)

# ============================================================================
# Write Output
# ============================================================================

cat("\nWriting output...\n")
cat(sprintf("  Output: %s\n", OUTPUT_FILE))

write.csv(analysis_df, OUTPUT_FILE, row.names = FALSE)

cat(sprintf("\n✓ Successfully wrote %d cases\n", nrow(analysis_df)))

# ============================================================================
# Display Examples
# ============================================================================

cat("\n", rep("=", 80), "\n", sep = "")
cat("Sample Cases with Raw Vernacular Data\n")
cat(rep("=", 80), "\n\n", sep = "")

for (i in 1:min(5, nrow(analysis_df))) {
  row <- analysis_df[i, ]
  cat(sprintf("Case %d: %s\n", i, row$genus))
  cat(sprintf("  Language: %s\n", row$language))
  cat(sprintf("  Vernaculars: %s\n", row$vernaculars))
  cat(sprintf("  Assigned: %s (similarity: %.4f)\n", row$assigned_category, row$similarity))
  cat(sprintf("  Top 3: %s\n", row$top3_categories))
  cat(sprintf("  Scores: %s\n\n", row$top3_scores))
}

cat("Full analysis in: ", OUTPUT_FILE, "\n")

cat("\n", rep("=", 80), "\n", sep = "")
cat("Complete\n")
cat(rep("=", 80), "\n\n", sep = "")

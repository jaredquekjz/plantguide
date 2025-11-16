#!/usr/bin/env Rscript
#' Label All Organisms with Functional Categories
#'
#' Applies genus→category mapping from bilingual vector classifications
#' to all organisms in the comprehensive organism dataset.
#'
#' Input:
#'   - data/taxonomy/organisms_vernacular_final.parquet (29,846 organisms)
#'   - data/taxonomy/vector_classifications_bilingual.parquet (9,168 genera)
#'
#' Output:
#'   - data/taxonomy/organisms_categorized_comprehensive.parquet
#'
#' Date: 2025-11-15

suppressPackageStartupMessages({
  library(duckdb)
  library(dplyr)
  library(arrow)
})

cat("=", rep("=", 78), "\n", sep = "")
cat("Label All Organisms with Functional Categories\n")
cat("=", rep("=", 78), "\n\n", sep = "")

# ============================================================================
# Configuration
# ============================================================================

ORGANISMS_FILE <- "/home/olier/ellenberg/data/taxonomy/organisms_vernacular_final.parquet"
CATEGORIES_FILE <- "/home/olier/ellenberg/data/taxonomy/vector_classifications_bilingual.parquet"
OUTPUT_FILE <- "/home/olier/ellenberg/data/taxonomy/organisms_categorized_comprehensive.parquet"

# ============================================================================
# Connect to DuckDB
# ============================================================================

cat("Connecting to DuckDB...\n")
con <- dbConnect(duckdb::duckdb())

# ============================================================================
# Load Data
# ============================================================================

cat("\nLoading data...\n")

# Load organisms
organisms <- read_parquet(ORGANISMS_FILE)
cat(sprintf("  Organisms: %d\n", nrow(organisms)))

# Load genus→category mapping
categories <- read_parquet(CATEGORIES_FILE)
cat(sprintf("  Categorized genera: %d\n", nrow(categories)))

# ============================================================================
# Join Organisms with Categories
# ============================================================================

cat("\nMapping categories to organisms...\n")

# Join on genus
organisms_categorized <- organisms %>%
  left_join(
    categories %>%
      select(genus, category_en, category_zh, category_index,
             similarity, source),
    by = "genus"
  )

# Summary statistics
n_total <- nrow(organisms_categorized)
n_categorized <- sum(!is.na(organisms_categorized$category_en))
n_uncategorized <- sum(is.na(organisms_categorized$category_en))

cat(sprintf("  Total organisms: %d\n", n_total))
cat(sprintf("  Categorized: %d (%.1f%%)\n",
            n_categorized, n_categorized / n_total * 100))
cat(sprintf("  Uncategorized: %d (%.1f%%)\n",
            n_uncategorized, n_uncategorized / n_total * 100))

# ============================================================================
# Summary Statistics
# ============================================================================

cat("\n", rep("=", 80), "\n", sep = "")
cat("Summary Statistics\n")
cat(rep("=", 80), "\n\n", sep = "")

# Breakdown by kingdom
cat("Categorization by kingdom:\n")
kingdom_summary <- organisms_categorized %>%
  group_by(kingdom) %>%
  summarise(
    total = n(),
    categorized = sum(!is.na(category_en)),
    pct = categorized / total * 100,
    .groups = "drop"
  ) %>%
  arrange(desc(total))

for (i in 1:nrow(kingdom_summary)) {
  cat(sprintf("  %s: %d categorized / %d total (%.1f%%)\n",
              kingdom_summary$kingdom[i],
              kingdom_summary$categorized[i],
              kingdom_summary$total[i],
              kingdom_summary$pct[i]))
}

# Breakdown by source
if (n_categorized > 0) {
  cat("\nCategorization source:\n")
  source_summary <- organisms_categorized %>%
    filter(!is.na(category_en)) %>%
    count(source) %>%
    arrange(desc(n))

  for (i in 1:nrow(source_summary)) {
    cat(sprintf("  %s: %d (%.1f%%)\n",
                source_summary$source[i],
                source_summary$n[i],
                source_summary$n[i] / n_categorized * 100))
  }
}

# Top 15 categories
cat("\nTop 15 categories:\n")
top_categories <- organisms_categorized %>%
  filter(!is.na(category_en)) %>%
  count(category_en) %>%
  arrange(desc(n)) %>%
  head(15)

for (i in 1:nrow(top_categories)) {
  pct <- top_categories$n[i] / n_categorized * 100
  cat(sprintf("  %d. %s: %d (%.1f%%)\n",
              i, top_categories$category_en[i],
              top_categories$n[i], pct))
}

# Similarity statistics
cat("\nSimilarity statistics (categorized organisms):\n")
cat_similarities <- organisms_categorized %>%
  filter(!is.na(category_en)) %>%
  pull(similarity)

cat(sprintf("  Mean: %.4f\n", mean(cat_similarities)))
cat(sprintf("  Median: %.4f\n", median(cat_similarities)))
cat(sprintf("  Min: %.4f\n", min(cat_similarities)))
cat(sprintf("  Max: %.4f\n", max(cat_similarities)))

# ============================================================================
# Write Output
# ============================================================================

cat("\nWriting output...\n")
cat(sprintf("  Output: %s\n", OUTPUT_FILE))

write_parquet(organisms_categorized, OUTPUT_FILE)

cat(sprintf("\n✓ Successfully wrote %d organisms with categories\n",
            nrow(organisms_categorized)))

# ============================================================================
# Cleanup
# ============================================================================

dbDisconnect(con, shutdown = TRUE)

cat("\n", rep("=", 80), "\n", sep = "")
cat("Complete\n")
cat(rep("=", 80), "\n\n", sep = "")

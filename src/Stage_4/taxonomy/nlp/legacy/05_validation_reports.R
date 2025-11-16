#!/usr/bin/env Rscript
#' Generate Validation Reports for Organism Categorization
#'
#' Creates comprehensive validation reports analyzing coverage,
#' quality, and distribution of organism categorizations.
#'
#' Input:
#'   - data/taxonomy/organisms_categorized_comprehensive.parquet
#'   - data/taxonomy/vector_classifications_bilingual.parquet
#'
#' Output:
#'   - reports/taxonomy/category_coverage.csv
#'   - reports/taxonomy/category_distribution.csv
#'   - reports/taxonomy/similarity_analysis.csv
#'   - reports/taxonomy/validation_summary.txt
#'
#' Date: 2025-11-15

suppressPackageStartupMessages({
  library(duckdb)
  library(dplyr)
  library(arrow)
  library(tidyr)
})

cat("=", rep("=", 78), "\n", sep = "")
cat("Organism Categorization - Validation Reports\n")
cat("=", rep("=", 78), "\n\n", sep = "")

# ============================================================================
# Configuration
# ============================================================================

ORGANISMS_FILE <- "/home/olier/ellenberg/data/taxonomy/organisms_categorized_comprehensive.parquet"
GENERA_FILE <- "/home/olier/ellenberg/data/taxonomy/vector_classifications_bilingual.parquet"

REPORTS_DIR <- "/home/olier/ellenberg/reports/taxonomy"
dir.create(REPORTS_DIR, showWarnings = FALSE, recursive = TRUE)

COVERAGE_REPORT <- file.path(REPORTS_DIR, "category_coverage.csv")
DISTRIBUTION_REPORT <- file.path(REPORTS_DIR, "category_distribution.csv")
SIMILARITY_REPORT <- file.path(REPORTS_DIR, "similarity_analysis.csv")
SUMMARY_REPORT <- file.path(REPORTS_DIR, "validation_summary.txt")

# ============================================================================
# Load Data
# ============================================================================

cat("Loading data...\n")

organisms <- read_parquet(ORGANISMS_FILE)
cat(sprintf("  Organisms: %d\n", nrow(organisms)))

genera <- read_parquet(GENERA_FILE)
cat(sprintf("  Genera: %d\n", nrow(genera)))

cat("\n")

# ============================================================================
# Report 1: Coverage Analysis
# ============================================================================

cat("Generating coverage analysis...\n")

# Overall coverage
coverage_overall <- tibble(
  level = "overall",
  group = "all",
  total = nrow(organisms),
  categorized = sum(!is.na(organisms$category_en)),
  uncategorized = sum(is.na(organisms$category_en)),
  pct_categorized = categorized / total * 100
)

# Coverage by kingdom
coverage_kingdom <- organisms %>%
  mutate(kingdom = ifelse(is.na(kingdom), "Unknown", kingdom)) %>%
  group_by(kingdom) %>%
  summarise(
    total = n(),
    categorized = sum(!is.na(category_en)),
    uncategorized = sum(is.na(category_en)),
    pct_categorized = categorized / total * 100,
    .groups = "drop"
  ) %>%
  mutate(
    level = "kingdom",
    group = kingdom
  ) %>%
  select(level, group, total, categorized, uncategorized, pct_categorized)

# Coverage by source
coverage_source <- organisms %>%
  filter(!is.na(category_en)) %>%
  group_by(source) %>%
  summarise(
    total = n(),
    categorized = n(),
    uncategorized = 0,
    pct_categorized = 100.0,
    .groups = "drop"
  ) %>%
  mutate(
    level = "source",
    group = source
  ) %>%
  select(level, group, total, categorized, uncategorized, pct_categorized)

# Combine coverage reports
coverage_combined <- bind_rows(
  coverage_overall,
  coverage_kingdom,
  coverage_source
)

write.csv(coverage_combined, COVERAGE_REPORT, row.names = FALSE)
cat(sprintf("  ✓ Coverage report: %s\n", COVERAGE_REPORT))

# ============================================================================
# Report 2: Category Distribution
# ============================================================================

cat("Generating category distribution...\n")

# Organism-level distribution
organism_distribution <- organisms %>%
  filter(!is.na(category_en)) %>%
  count(category_en, category_zh, category_index) %>%
  arrange(desc(n)) %>%
  mutate(
    pct = n / sum(n) * 100,
    cumulative_pct = cumsum(pct),
    level = "organism"
  ) %>%
  select(level, category_index, category_en, category_zh, count = n, pct, cumulative_pct)

# Genus-level distribution
genus_distribution <- genera %>%
  filter(!is.na(category_en)) %>%
  count(category_en, category_zh, category_index) %>%
  arrange(desc(n)) %>%
  mutate(
    pct = n / sum(n) * 100,
    cumulative_pct = cumsum(pct),
    level = "genus"
  ) %>%
  select(level, category_index, category_en, category_zh, count = n, pct, cumulative_pct)

# Combine distributions
distribution_combined <- bind_rows(
  organism_distribution,
  genus_distribution
)

write.csv(distribution_combined, DISTRIBUTION_REPORT, row.names = FALSE)
cat(sprintf("  ✓ Distribution report: %s\n", DISTRIBUTION_REPORT))

# ============================================================================
# Report 3: Similarity Analysis
# ============================================================================

cat("Generating similarity analysis...\n")

# Overall similarity stats
similarity_overall <- organisms %>%
  filter(!is.na(category_en)) %>%
  summarise(
    level = "organism_overall",
    group = "all",
    count = n(),
    mean_similarity = mean(similarity, na.rm = TRUE),
    median_similarity = median(similarity, na.rm = TRUE),
    sd_similarity = sd(similarity, na.rm = TRUE),
    min_similarity = min(similarity, na.rm = TRUE),
    max_similarity = max(similarity, na.rm = TRUE),
    q25_similarity = quantile(similarity, 0.25, na.rm = TRUE),
    q75_similarity = quantile(similarity, 0.75, na.rm = TRUE)
  )

# Similarity by source
similarity_source <- organisms %>%
  filter(!is.na(category_en)) %>%
  group_by(source) %>%
  summarise(
    count = n(),
    mean_similarity = mean(similarity, na.rm = TRUE),
    median_similarity = median(similarity, na.rm = TRUE),
    sd_similarity = sd(similarity, na.rm = TRUE),
    min_similarity = min(similarity, na.rm = TRUE),
    max_similarity = max(similarity, na.rm = TRUE),
    q25_similarity = quantile(similarity, 0.25, na.rm = TRUE),
    q75_similarity = quantile(similarity, 0.75, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    level = "organism_by_source",
    group = source
  ) %>%
  select(level, group, everything())

# Genus-level similarity stats
similarity_genus <- genera %>%
  filter(!is.na(category_en)) %>%
  summarise(
    level = "genus_overall",
    group = "all",
    count = n(),
    mean_similarity = mean(similarity, na.rm = TRUE),
    median_similarity = median(similarity, na.rm = TRUE),
    sd_similarity = sd(similarity, na.rm = TRUE),
    min_similarity = min(similarity, na.rm = TRUE),
    max_similarity = max(similarity, na.rm = TRUE),
    q25_similarity = quantile(similarity, 0.25, na.rm = TRUE),
    q75_similarity = quantile(similarity, 0.75, na.rm = TRUE)
  )

# Combine similarity reports
similarity_combined <- bind_rows(
  similarity_overall,
  similarity_source,
  similarity_genus
)

write.csv(similarity_combined, SIMILARITY_REPORT, row.names = FALSE)
cat(sprintf("  ✓ Similarity report: %s\n", SIMILARITY_REPORT))

# ============================================================================
# Report 4: Summary Text Report
# ============================================================================

cat("Generating summary report...\n")

sink(SUMMARY_REPORT)

cat("================================================================================\n")
cat("ORGANISM CATEGORIZATION - VALIDATION SUMMARY\n")
cat("================================================================================\n")
cat("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("\n")

cat("================================================================================\n")
cat("COVERAGE ANALYSIS\n")
cat("================================================================================\n\n")

cat("Overall Coverage:\n")
cat(sprintf("  Total organisms: %d\n", coverage_overall$total))
cat(sprintf("  Categorized: %d (%.1f%%)\n",
            coverage_overall$categorized,
            coverage_overall$pct_categorized))
cat(sprintf("  Uncategorized: %d (%.1f%%)\n\n",
            coverage_overall$uncategorized,
            100 - coverage_overall$pct_categorized))

cat("Coverage by Kingdom:\n")
for (i in 1:nrow(coverage_kingdom)) {
  cat(sprintf("  %s: %d / %d (%.1f%%)\n",
              coverage_kingdom$group[i],
              coverage_kingdom$categorized[i],
              coverage_kingdom$total[i],
              coverage_kingdom$pct_categorized[i]))
}
cat("\n")

cat("Coverage by Source:\n")
for (i in 1:nrow(coverage_source)) {
  cat(sprintf("  %s: %d organisms (%.1f%%)\n",
              coverage_source$group[i],
              coverage_source$total[i],
              coverage_source$total[i] / coverage_overall$categorized * 100))
}
cat("\n")

cat("================================================================================\n")
cat("CATEGORY DISTRIBUTION\n")
cat("================================================================================\n\n")

cat("Top 20 Categories (by organism count):\n")
top20_organisms <- organism_distribution %>%
  head(20)
for (i in 1:nrow(top20_organisms)) {
  cat(sprintf("  %2d. %s: %d organisms (%.1f%%)\n",
              i,
              top20_organisms$category_en[i],
              top20_organisms$count[i],
              top20_organisms$pct[i]))
}
cat("\n")

cat("Coverage Concentration:\n")
cat(sprintf("  Top 10 categories cover: %.1f%% of categorized organisms\n",
            organism_distribution$cumulative_pct[10]))
cat(sprintf("  Top 20 categories cover: %.1f%% of categorized organisms\n",
            organism_distribution$cumulative_pct[20]))
cat(sprintf("  Top 50 categories cover: %.1f%% of categorized organisms\n",
            organism_distribution$cumulative_pct[min(50, nrow(organism_distribution))]))
cat("\n")

cat("================================================================================\n")
cat("SIMILARITY ANALYSIS\n")
cat("================================================================================\n\n")

cat("Overall Similarity Statistics:\n")
cat(sprintf("  Mean: %.4f\n", similarity_overall$mean_similarity))
cat(sprintf("  Median: %.4f\n", similarity_overall$median_similarity))
cat(sprintf("  Std Dev: %.4f\n", similarity_overall$sd_similarity))
cat(sprintf("  Min: %.4f\n", similarity_overall$min_similarity))
cat(sprintf("  Max: %.4f\n", similarity_overall$max_similarity))
cat(sprintf("  Q25: %.4f\n", similarity_overall$q25_similarity))
cat(sprintf("  Q75: %.4f\n\n", similarity_overall$q75_similarity))

cat("Similarity by Source:\n")
for (i in 1:nrow(similarity_source)) {
  cat(sprintf("  %s:\n", similarity_source$group[i]))
  cat(sprintf("    Count: %d\n", similarity_source$count[i]))
  cat(sprintf("    Mean: %.4f\n", similarity_source$mean_similarity[i]))
  cat(sprintf("    Median: %.4f\n", similarity_source$median_similarity[i]))
  cat(sprintf("    Min: %.4f\n", similarity_source$min_similarity[i]))
  cat(sprintf("    Max: %.4f\n\n", similarity_source$max_similarity[i]))
}

cat("================================================================================\n")
cat("QUALITY ASSESSMENT\n")
cat("================================================================================\n\n")

# Quality thresholds
high_quality <- sum(organisms$similarity >= 0.65, na.rm = TRUE)
medium_quality <- sum(organisms$similarity >= 0.55 & organisms$similarity < 0.65, na.rm = TRUE)
low_quality <- sum(organisms$similarity >= 0.45 & organisms$similarity < 0.55, na.rm = TRUE)
threshold_quality <- sum(organisms$similarity < 0.45, na.rm = TRUE)

total_categorized <- coverage_overall$categorized

cat("Quality Distribution (by similarity score):\n")
cat(sprintf("  High quality (≥0.65): %d (%.1f%%)\n",
            high_quality, high_quality / total_categorized * 100))
cat(sprintf("  Medium quality (0.55-0.65): %d (%.1f%%)\n",
            medium_quality, medium_quality / total_categorized * 100))
cat(sprintf("  Low quality (0.45-0.55): %d (%.1f%%)\n",
            low_quality, low_quality / total_categorized * 100))
cat(sprintf("  Below threshold (<0.45): %d (%.1f%%)\n\n",
            threshold_quality, threshold_quality / total_categorized * 100))

cat("================================================================================\n")
cat("END OF REPORT\n")
cat("================================================================================\n")

sink()

cat(sprintf("  ✓ Summary report: %s\n", SUMMARY_REPORT))

# ============================================================================
# Console Summary
# ============================================================================

cat("\n", rep("=", 80), "\n", sep = "")
cat("Validation Reports Complete\n")
cat(rep("=", 80), "\n\n", sep = "")

cat("Generated 4 reports:\n")
cat(sprintf("  1. Coverage analysis: %s\n", basename(COVERAGE_REPORT)))
cat(sprintf("  2. Category distribution: %s\n", basename(DISTRIBUTION_REPORT)))
cat(sprintf("  3. Similarity analysis: %s\n", basename(SIMILARITY_REPORT)))
cat(sprintf("  4. Summary report: %s\n\n", basename(SUMMARY_REPORT)))

cat("Key Findings:\n")
cat(sprintf("  • Overall coverage: %.1f%% (%d / %d organisms)\n",
            coverage_overall$pct_categorized,
            coverage_overall$categorized,
            coverage_overall$total))
cat(sprintf("  • Mean similarity: %.4f\n", similarity_overall$mean_similarity))
cat(sprintf("  • High quality (≥0.65): %.1f%%\n",
            high_quality / total_categorized * 100))
cat(sprintf("  • Top 10 categories cover: %.1f%% of organisms\n",
            organism_distribution$cumulative_pct[10]))

cat("\n", rep("=", 80), "\n", sep = "")
cat("Complete\n")
cat(rep("=", 80), "\n\n", sep = "")

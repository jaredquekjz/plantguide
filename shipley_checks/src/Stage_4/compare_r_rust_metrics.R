#!/usr/bin/env Rscript
# Systematic R vs Rust metric-by-metric comparison
# Identifies which specific metrics cause parity differences

library(glue)
library(dplyr)
library(jsonlite)

# Set working directory to repository root
setwd("/home/olier/ellenberg")
source("shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R")

cat("======================================================================\n")
cat("SYSTEMATIC R vs RUST METRIC COMPARISON\n")
cat("======================================================================\n\n")

# Test guilds from Rust
guilds <- list(
  forest_garden = c('wfo-0000302676', 'wfo-0000281277', 'wfo-0000298245',
                    'wfo-0000364237', 'wfo-0000242554', 'wfo-0000239962', 'wfo-0000278287'),
  competitive_clash = c('wfo-0000285892', 'wfo-0000333502', 'wfo-0000302676',
                        'wfo-0000281277', 'wfo-0000298245'),
  stress_tolerant = c('wfo-0000379441', 'wfo-0000379389', 'wfo-0000331237'),
  entomopathogen = c('wfo-0000302676', 'wfo-0000281277', 'wfo-0000298245',
                     'wfo-0000364237', 'wfo-0000242554', 'wfo-0000239962',
                     'wfo-0000278287', 'wfo-0000285892', 'wfo-0000333502', 'wfo-0000379441')
)

# Expected Rust scores from Nov 22, 2025 (BILL_VERIFIED calibration)
rust_results <- list(
  forest_garden = list(
    overall = 92.641051,
    m1 = 57.073964, m2 = 100.0, m3 = 100.0, m4 = 95.113636,
    m5 = 100.0, m6 = 100.0, m7 = 95.0
  ),
  competitive_clash = list(
    overall = 55.291325,
    m1 = 70.238095, m2 = 0.0, m3 = 100.0, m4 = 100.0,
    m5 = 100.0, m6 = 16.409091, m7 = 0.0
  ),
  stress_tolerant = list(
    overall = 41.156793,
    m1 = 32.580645, m2 = 100.0, m3 = 0.0, m4 = 62.857143,
    m5 = 45.0, m6 = 46.212121, m7 = 0.0
  ),
  entomopathogen = list(
    overall = 85.588203,
    m1 = 40.020000, m2 = 60.0, m3 = 100.0, m4 = 97.741935,
    m5 = 100.0, m6 = 100.0, m7 = 100.0
  )
)

# Initialize scorer
cat("Initializing Guild Scorer (R)...\n\n")
scorer <- GuildScorerV3Shipley$new(
  calibration_type = "7plant",
  climate_tier = "tier_3_humid_temperate"
)

cat("\n======================================================================\n")
cat("METRIC-BY-METRIC COMPARISON\n")
cat("======================================================================\n\n")

all_diffs <- list()
metric_names <- c("M1: Pest Independence", "M2: Growth Compatibility",
                  "M3: Insect Control", "M4: Disease Control",
                  "M5: Beneficial Fungi", "M6: Structural Diversity",
                  "M7: Pollinator Support")

for (guild_name in names(guilds)) {
  cat(sprintf("----------------------------------------------------------------------\n"))
  cat(sprintf("GUILD: %s\n", toupper(gsub("_", " ", guild_name))))
  cat(sprintf("----------------------------------------------------------------------\n\n"))

  plants <- guilds[[guild_name]]
  rust <- rust_results[[guild_name]]

  # Calculate R scores
  result <- scorer$score_guild(plants)

  # Extract individual metrics
  r_metrics <- c(
    result$metrics$m1_pest_independence,
    result$metrics$m2_growth_compatibility,
    result$metrics$m3_insect_control,
    result$metrics$m4_disease_control,
    result$metrics$m5_beneficial_fungi,
    result$metrics$m6_structural_diversity,
    result$metrics$m7_pollinator_support
  )

  rust_metrics <- c(rust$m1, rust$m2, rust$m3, rust$m4, rust$m5, rust$m6, rust$m7)

  # Compare each metric
  cat(sprintf("%-30s %12s %12s %12s %8s\n", "Metric", "R", "Rust", "Difference", "Status"))
  cat(sprintf("%-30s %12s %12s %12s %8s\n", "------", "---", "----", "----------", "------"))

  for (i in 1:7) {
    diff <- abs(r_metrics[i] - rust_metrics[i])
    status <- if (diff < 0.0001) "✓ PERFECT"
              else if (diff < 0.01) "✓ EXCELLENT"
              else if (diff < 0.1) "✓ GOOD"
              else if (diff < 1.0) "⚠ ACCEPTABLE"
              else "✗ DIFFERS"

    cat(sprintf("%-30s %12.6f %12.6f %12.6f %8s\n",
                metric_names[i], r_metrics[i], rust_metrics[i], diff, status))

    # Store for summary
    all_diffs[[length(all_diffs) + 1]] <- list(
      guild = guild_name,
      metric = metric_names[i],
      r = r_metrics[i],
      rust = rust_metrics[i],
      diff = diff,
      status = status
    )
  }

  # Overall score
  overall_diff <- abs(result$score - rust$overall)
  overall_status <- if (overall_diff < 0.0001) "✓ PERFECT"
                    else if (overall_diff < 0.01) "✓ EXCELLENT"
                    else if (overall_diff < 0.1) "✓ GOOD"
                    else if (overall_diff < 1.0) "⚠ ACCEPTABLE"
                    else "✗ DIFFERS"

  cat(sprintf("%-30s %12s %12s %12s %8s\n", "------", "---", "----", "----------", "------"))
  cat(sprintf("%-30s %12.6f %12.6f %12.6f %8s\n",
              "OVERALL SCORE", result$score, rust$overall, overall_diff, overall_status))
  cat("\n")
}

cat("======================================================================\n")
cat("SUMMARY: Metrics with Differences > 0.0001\n")
cat("======================================================================\n\n")

# Find all metrics with meaningful differences
problem_metrics <- Filter(function(x) x$diff > 0.0001, all_diffs)

if (length(problem_metrics) > 0) {
  cat(sprintf("%-20s %-30s %12s %12s %12s\n",
              "Guild", "Metric", "R", "Rust", "Difference"))
  cat(sprintf("%-20s %-30s %12s %12s %12s\n",
              "-----", "------", "---", "----", "----------"))

  for (pm in problem_metrics) {
    cat(sprintf("%-20s %-30s %12.6f %12.6f %12.6f\n",
                pm$guild, pm$metric, pm$r, pm$rust, pm$diff))
  }

  cat("\n")
  cat(sprintf("Total metrics with differences: %d / %d\n",
              length(problem_metrics), length(all_diffs)))

  # Group by metric type
  cat("\n")
  cat("Affected metrics summary:\n")
  metric_counts <- table(sapply(problem_metrics, function(x) x$metric))
  for (m in names(metric_counts)) {
    cat(sprintf("  %s: %d guilds affected\n", m, metric_counts[m]))
  }
} else {
  cat("🎉 PERFECT PARITY! All metrics match Rust exactly (diff < 0.0001)\n")
}

cat("\n======================================================================\n")
cat("DIAGNOSIS\n")
cat("======================================================================\n\n")

if (length(problem_metrics) > 0) {
  # Identify which metrics need investigation
  unique_metrics <- unique(sapply(problem_metrics, function(x) x$metric))
  cat("Metrics requiring investigation:\n")
  for (m in unique_metrics) {
    cat(sprintf("  - %s\n", m))
  }
  cat("\nNext steps:\n")
  cat("1. Focus debugging on the above metrics\n")
  cat("2. Check data loading for these specific calculations\n")
  cat("3. Verify normalization parameters for affected metrics\n")
} else {
  cat("No issues found - perfect parity achieved!\n")
}

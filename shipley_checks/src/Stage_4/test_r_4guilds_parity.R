#!/usr/bin/env Rscript
#
# Test R Implementation with 4 Guilds for Full Parity Check
# Expected scores from Rust (Nov 22, 2025 - BILL_VERIFIED calibration)
#

suppressPackageStartupMessages({
  library(glue)
  library(dplyr)
})

# Source the Shipley R scorer (uses same data as Rust)
source('shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R')

cat("\n", strrep("=", 70), "\n", sep = "")
cat("R vs RUST PARITY TEST: 4 Guilds\n")
cat(strrep("=", 70), "\n")

cat("\nInitializing Guild Scorer (R)...\n\n")

# Initialize with timing
init_time <- system.time({
  scorer <- GuildScorerV3Shipley$new('7plant', 'tier_3_humid_temperate')
})

# Define 4 test guilds with ACTUAL Rust scores (from test_explanations_3_guilds run)
guilds <- list(
  list(
    name = "Forest Garden",
    plant_ids = c(
      "wfo-0000832453",
      "wfo-0000649136",
      "wfo-0000642673",
      "wfo-0000984977",
      "wfo-0000241769",
      "wfo-0000092746",
      "wfo-0000690499"
    ),
    expected = 92.641051
  ),
  list(
    name = "Competitive Clash",
    plant_ids = c(
      "wfo-0000757278",
      "wfo-0000944034",
      "wfo-0000186915",
      "wfo-0000421791",
      "wfo-0000418518",
      "wfo-0000841021",
      "wfo-0000394258"
    ),
    expected = 55.291325
  ),
  list(
    name = "Stress-Tolerant",
    plant_ids = c(
      "wfo-0000721951",
      "wfo-0000955348",
      "wfo-0000901050",
      "wfo-0000956222",
      "wfo-0000777518",
      "wfo-0000349035",
      "wfo-0000209726"
    ),
    expected = 41.156793
  ),
  list(
    name = "Entomopathogen Powerhouse",
    plant_ids = c(
      "wfo-0000910097",  # Coffea arabica
      "wfo-0000421791",  # Vitis vinifera
      "wfo-0000861498",  # Dactylis glomerata
      "wfo-0001007437",  # Prunus spinosa (Blackthorn)
      "wfo-0000292858",  # Quercus robur (English Oak)
      "wfo-0001005999",  # Rosa canina (Dog rose)
      "wfo-0000993770"   # Fragaria vesca (Wild strawberry)
    ),
    expected = 85.588203
  )
)

cat(strrep("=", 70), "\n")

max_diff <- 0
all_passed <- TRUE
guild_times <- numeric(0)
results_table <- data.frame(
  Guild = character(),
  R_Score = numeric(),
  Rust_Score = numeric(),
  Diff = numeric(),
  Status = character(),
  stringsAsFactors = FALSE
)

# Score guilds with timing
scoring_time_start <- proc.time()
for (guild in guilds) {
  cat("\n", strrep("-", 70), "\n", sep = "")
  cat("GUILD: ", guild$name, "\n", sep = "")
  cat(strrep("-", 70), "\n")

  guild_time_start <- proc.time()
  result <- scorer$score_guild(guild$plant_ids)
  guild_time <- proc.time() - guild_time_start
  guild_times <- c(guild_times, guild_time[3])

  diff <- abs(result$overall_score - guild$expected)
  max_diff <- max(max_diff, diff)

  status <- if (diff < 0.0001) {
    "✅ PERFECT"
  } else if (diff < 0.01) {
    "✓ EXCELLENT"
  } else if (diff < 0.1) {
    "✓ GOOD"
  } else if (diff < 1.0) {
    "⚠ ACCEPTABLE"
  } else {
    all_passed <- FALSE
    "✗ FAIL"
  }

  cat("\nScores:\n")
  cat(glue("  R:          {sprintf('%.6f', result$overall_score)}"), "\n")
  cat(glue("  Rust:       {sprintf('%.6f', guild$expected)}"), "\n")
  cat(glue("  Difference: {sprintf('%.6f', diff)}"), "\n")
  cat(glue("  Status:     {status}"), "\n")

  # Show individual metrics
  cat("\nMetrics:\n")
  cat(glue("  M1: Pest Independence     {sprintf('%.2f', result$metrics[1])}"), "\n")
  cat(glue("  M2: Growth Compatibility  {sprintf('%.2f', result$metrics[2])}"), "\n")
  cat(glue("  M3: Insect Control        {sprintf('%.2f', result$metrics[3])}"), "\n")
  cat(glue("  M4: Disease Control       {sprintf('%.2f', result$metrics[4])}"), "\n")
  cat(glue("  M5: Beneficial Fungi      {sprintf('%.2f', result$metrics[5])}"), "\n")
  cat(glue("  M6: Structural Diversity  {sprintf('%.2f', result$metrics[6])}"), "\n")
  cat(glue("  M7: Pollinator Support    {sprintf('%.2f', result$metrics[7])}"), "\n")

  cat(glue("\nTiming: {sprintf('%.3f', guild_time[3] * 1000)} ms"), "\n")

  # Store results for summary table
  results_table <- rbind(results_table, data.frame(
    Guild = guild$name,
    R_Score = result$overall_score,
    Rust_Score = guild$expected,
    Diff = diff,
    Status = status,
    stringsAsFactors = FALSE
  ))
}
total_scoring_time <- proc.time() - scoring_time_start

cat("\n", strrep("=", 70), "\n", sep = "")
cat("SUMMARY\n")
cat(strrep("=", 70), "\n\n")

# Print summary table
print(results_table, row.names = FALSE)

cat("\n", strrep("-", 70), "\n", sep = "")
cat(glue("Maximum difference: {sprintf('%.6f', max_diff)}"), "\n")
cat("Threshold: < 0.0001 (perfect), < 0.01 (excellent), < 0.1 (good), < 1.0 (acceptable)\n")

cat("\n", strrep("=", 70), "\n", sep = "")
cat("PERFORMANCE (R)\n")
cat(strrep("=", 70), "\n")
cat(glue("Initialization: {sprintf('%.3f', init_time[3] * 1000)} ms"), "\n")
cat(glue("4 Guild Scoring: {sprintf('%.3f', total_scoring_time[3] * 1000)} ms total"), "\n")
for (i in seq_along(guild_times)) {
  cat(glue("  Guild {i}: {sprintf('%.3f', guild_times[i] * 1000)} ms"), "\n")
}
cat(glue("Average per guild: {sprintf('%.3f', mean(guild_times) * 1000)} ms"), "\n")

# Final verdict
cat("\n", strrep("=", 70), "\n", sep = "")
if (max_diff < 0.0001) {
  cat("✅ PERFECT PARITY: 100% match with Rust\n")
  quit(status = 0)
} else if (max_diff < 0.01) {
  cat("✅ EXCELLENT PARITY: Within 0.01 of Rust (acceptable)\n")
  quit(status = 0)
} else if (max_diff < 0.1) {
  cat("✅ GOOD PARITY: Within 0.1 of Rust\n")
  quit(status = 0)
} else if (max_diff < 1.0) {
  cat("⚠ ACCEPTABLE PARITY: Within 1.0 of Rust\n")
  quit(status = 0)
} else {
  cat("✗ PARITY FAILED: Differences exceed 1.0\n")
  quit(status = 1)
}

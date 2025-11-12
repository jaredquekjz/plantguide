#!/usr/bin/env Rscript
#
# Test 3 guilds with R implementation (with timing)
#

suppressPackageStartupMessages({
  library(glue)
  library(dplyr)
})

# Source the modular R scorer
source('shipley_checks/src/Stage_4/guild_scorer_v3_modular.R')

cat("\nInitializing Guild Scorer (R)...\n\n")

# Initialize with timing
init_time <- system.time({
  scorer <- GuildScorerV3Modular$new('7plant', 'tier_3_humid_temperate')
})

# Define 3 test guilds
guilds <- list(
  list(
    name = "Forest Garden",
    plant_ids = c("wfo-0000832453", "wfo-0000649136", "wfo-0000642673",
                  "wfo-0000984977", "wfo-0000241769", "wfo-0000092746",
                  "wfo-0000690499"),
    expected = 90.467710
  ),
  list(
    name = "Competitive Clash",
    plant_ids = c("wfo-0000757278", "wfo-0000944034", "wfo-0000186915",
                  "wfo-0000421791", "wfo-0000418518", "wfo-0000841021",
                  "wfo-0000394258"),
    expected = 55.441621
  ),
  list(
    name = "Stress-Tolerant",
    plant_ids = c("wfo-0000721951", "wfo-0000955348", "wfo-0000901050",
                  "wfo-0000956222", "wfo-0000777518", "wfo-0000349035",
                  "wfo-0000209726"),
    expected = 45.442341
  )
)

cat("\n", strrep("=", 70), "\n", sep = "")
cat("PARITY TEST: 3 Guilds (R Implementation)\n")
cat(strrep("=", 70), "\n")

max_diff <- 0
all_passed <- TRUE
guild_times <- numeric(0)

# Score guilds with timing
scoring_time_start <- proc.time()
for (guild in guilds) {
  guild_time_start <- proc.time()
  result <- scorer$score_guild(guild$plant_ids)
  guild_time <- proc.time() - guild_time_start
  guild_times <- c(guild_times, guild_time[3])

  diff <- abs(result$overall_score - guild$expected)
  max_diff <- max(max_diff, diff)

  status <- if (diff < 0.0001) {
    "✅ PERFECT"
  } else if (diff < 0.01) {
    "✓ PASS"
  } else {
    all_passed <- FALSE
    "✗ FAIL"
  }

  cat("\n", guild$name, "\n", sep = "")
  cat(glue("  Expected:  {sprintf('%.6f', guild$expected)}"), "\n")
  cat(glue("  R:         {sprintf('%.6f', result$overall_score)}"), "\n")
  cat(glue("  Difference: {sprintf('%.6f', diff)}"), "\n")
  cat(glue("  Status:    {status}"), "\n")

  # Show individual metrics
  cat("  Metrics:\n")
  cat(glue("    M1: Pest Independence     {sprintf('%.1f', result$metrics[1])}"), "\n")
  cat(glue("    M2: Growth Compatibility  {sprintf('%.1f', result$metrics[2])}"), "\n")
  cat(glue("    M3: Insect Control        {sprintf('%.1f', result$metrics[3])}"), "\n")
  cat(glue("    M4: Disease Control       {sprintf('%.1f', result$metrics[4])}"), "\n")
  cat(glue("    M5: Beneficial Fungi      {sprintf('%.1f', result$metrics[5])}"), "\n")
  cat(glue("    M6: Structural Diversity  {sprintf('%.1f', result$metrics[6])}"), "\n")
  cat(glue("    M7: Pollinator Support    {sprintf('%.1f', result$metrics[7])}"), "\n")
}
total_scoring_time <- proc.time() - scoring_time_start

cat("\n", strrep("=", 70), "\n", sep = "")
cat("SUMMARY\n")
cat(strrep("=", 70), "\n")
cat(glue("Maximum difference: {sprintf('%.6f', max_diff)}"), "\n")
cat("Threshold: < 0.0001 (0.01%)\n")

cat("\n", strrep("=", 70), "\n", sep = "")
cat("PERFORMANCE (R)\n")
cat(strrep("=", 70), "\n")
cat(glue("Initialization: {sprintf('%.3f', init_time[3] * 1000)} ms"), "\n")
cat(glue("3 Guild Scoring: {sprintf('%.3f', total_scoring_time[3] * 1000)} ms total"), "\n")
for (i in seq_along(guild_times)) {
  cat(glue("  Guild {i}: {sprintf('%.3f', guild_times[i] * 1000)} ms"), "\n")
}
cat(glue("Average per guild: {sprintf('%.3f', mean(guild_times) * 1000)} ms"), "\n")

if (all_passed && max_diff < 0.0001) {
  cat("\n✅ PARITY ACHIEVED: 100% match\n")
  quit(status = 0)
} else if (all_passed) {
  cat("\n✓ NEAR PARITY: Within acceptable tolerance\n")
  quit(status = 0)
} else {
  cat("\n✗ PARITY FAILED: Differences exceed tolerance\n")
  quit(status = 1)
}

#!/usr/bin/env Rscript
#
# Test R Explanation Engine with 3 Guilds
# For end-to-end comparison with Rust implementation
#

suppressPackageStartupMessages({
  library(R6)
  library(dplyr)
  library(glue)
})

# Source the guild scorer and markdown exporter
source("shipley_checks/src/Stage_4/guild_scorer_v3_modular.R")
source("shipley_checks/src/Stage_4/export_explanation_md.R")

cat("==================================================================\n")
cat("R EXPLANATION ENGINE TEST (3 Guilds)\n")
cat("==================================================================\n\n")

# Initialize scorer
cat("Initializing Guild Scorer (R)...\n")
init_start <- Sys.time()
scorer <- GuildScorerV3Modular$new(
  calibration_type = "7plant",
  climate_tier = "tier_3_humid_temperate"
)
init_time <- as.numeric(difftime(Sys.time(), init_start, units = "secs")) * 1000
cat(sprintf("Initialization: %.3f ms\n\n", init_time))

# Define 3 test guilds
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
    expected_rust = 89.744099
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
    expected_rust = 53.011553
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
    expected_rust = 42.380873
  )
)

total_start <- Sys.time()
all_times <- list()

for (guild in guilds) {
  cat("\n----------------------------------------------------------------------\n")
  cat(sprintf("GUILD: %s\n", guild$name))
  cat("----------------------------------------------------------------------\n")

  guild_start <- Sys.time()

  # Score guild
  scoring_start <- Sys.time()
  result <- scorer$score_guild(guild$plant_ids)
  scoring_time <- as.numeric(difftime(Sys.time(), scoring_start, units = "secs")) * 1000

  # Export to markdown (Rust-compatible format)
  markdown_start <- Sys.time()
  safe_name <- tolower(gsub(" ", "_", guild$name))
  output_dir <- "shipley_checks/stage4/reports"
  output_path <- sprintf("%s/r_explanation_%s.md", output_dir, safe_name)
  export_guild_report_md(result, output_path, guild$name)
  markdown_time <- as.numeric(difftime(Sys.time(), markdown_start, units = "secs")) * 1000

  total_time <- as.numeric(difftime(Sys.time(), guild_start, units = "secs")) * 1000

  # Print results
  cat("\nScores:\n")
  cat(sprintf("  R Overall:    %.6f\n", result$overall_score))
  cat(sprintf("  Rust Overall: %.6f\n", guild$expected_rust))
  diff <- abs(result$overall_score - guild$expected_rust)
  status <- if (diff < 0.01) "✅ PERFECT PARITY" else if (diff < 0.1) "✅ EXCELLENT PARITY" else if (diff < 0.5) "✅ GOOD PARITY" else "⚠️ PARITY ISSUE"
  cat(sprintf("  Difference:   %.6f - %s\n", diff, status))

  cat("\nPerformance:\n")
  cat(sprintf("  Scoring:         %8.3f ms\n", scoring_time))
  cat(sprintf("  Markdown export: %8.3f ms\n", markdown_time))
  cat(sprintf("  Total:           %8.3f ms\n", total_time))

  cat(sprintf("\nOutput written:\n"))
  cat(sprintf("  %s/r_explanation_%s.md\n", output_dir, safe_name))

  all_times[[length(all_times) + 1]] <- total_time
}

total_elapsed <- as.numeric(difftime(Sys.time(), total_start, units = "secs")) * 1000

cat("\n======================================================================\n")
cat("SUMMARY\n")
cat("======================================================================\n")
cat(sprintf("Total time (3 guilds): %.3f ms\n", total_elapsed))
cat(sprintf("Average per guild: %.3f ms\n", mean(unlist(all_times))))
cat("\n✅ All R explanations generated successfully!\n")
cat("======================================================================\n\n")

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

# Source the guild scorer and explanation engine
source("shipley_checks/src/Stage_4/guild_scorer_v3_modular.R")
source("shipley_checks/src/Stage_4/explanation_engine_7metric.R")
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
    expected = 90.467710
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
    expected = 55.441621
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
    expected = 45.442341
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

  # Generate explanation
  explanation_start <- Sys.time()
  explanation <- generate_explanation(result)
  explanation_time <- as.numeric(difftime(Sys.time(), explanation_start, units = "secs")) * 1000

  # Format to markdown (simple version for timing)
  markdown_start <- Sys.time()
  markdown <- paste0(
    "# ", explanation$overall$stars, " - ", explanation$overall$label, "\n\n",
    "**Overall Score:** ", explanation$overall$score, "/100\n\n",
    "## Climate Compatibility\n\n",
    explanation$climate$message, "\n\n",
    "## Benefits\n\n",
    paste(sapply(explanation$benefits, function(b) {
      paste0("### ", b$title, "\n", b$message, "\n")
    }), collapse = "\n"),
    "\n## Warnings\n\n",
    paste(sapply(explanation$warnings, function(w) {
      paste0("**", w$message, "**\n", w$detail, "\n")
    }), collapse = "\n")
  )
  markdown_time <- as.numeric(difftime(Sys.time(), markdown_start, units = "secs")) * 1000

  total_time <- as.numeric(difftime(Sys.time(), guild_start, units = "secs")) * 1000

  # Write output
  safe_name <- tolower(gsub(" ", "_", guild$name))
  output_dir <- "shipley_checks/reports/explanations"
  writeLines(markdown, sprintf("%s/r_explanation_%s.md", output_dir, safe_name))

  # Print results
  cat("\nScores:\n")
  cat(sprintf("  Overall:  %.6f (expected: %.6f)\n", result$overall_score, guild$expected))
  diff <- abs(result$overall_score - guild$expected)
  status <- if (diff < 0.0001) "✅ PERFECT" else "⚠️ DIFF"
  cat(sprintf("  Difference: %.6f - %s\n", diff, status))

  cat("\nExplanation Summary:\n")
  cat(sprintf("  Rating: %s %s\n", explanation$overall$stars, explanation$overall$label))
  cat(sprintf("  Benefits: %d\n", length(explanation$benefits)))
  cat(sprintf("  Warnings: %d\n", length(explanation$warnings)))
  cat(sprintf("  Risks:    %d\n", length(explanation$risks)))

  cat("\nPerformance:\n")
  cat(sprintf("  Scoring:         %8.3f ms\n", scoring_time))
  cat(sprintf("  Explanation gen: %8.3f ms\n", explanation_time))
  cat(sprintf("  Markdown format: %8.3f ms\n", markdown_time))
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

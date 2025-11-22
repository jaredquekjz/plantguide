#!/usr/bin/env Rscript
#
# Test R Explanation Engine with 4 Guilds using Shipley Scorer
# For detailed comparison with Rust implementation
#

suppressPackageStartupMessages({
  library(R6)
  library(dplyr)
  library(glue)
})

# Source the SHIPLEY guild scorer (not modular)
source("shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R")

cat("==================================================================\n")
cat("R EXPLANATION ENGINE TEST (4 Guilds - Shipley Scorer)\n")
cat("==================================================================\n\n")

# Initialize scorer
cat("Initializing Guild Scorer (R Shipley)...\n")
init_start <- Sys.time()
scorer <- GuildScorerV3Shipley$new(
  calibration_type = "7plant",
  climate_tier = "tier_3_humid_temperate"
)
init_time <- as.numeric(difftime(Sys.time(), init_start, units = "secs")) * 1000
cat(sprintf("Initialization: %.3f ms\n\n", init_time))

# Define 4 test guilds (from parity test)
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
    expected_rust = 92.603018
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
    expected_rust = 55.478742
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
    expected_rust = 41.037741
  ),
  list(
    name = "Entomopathogen Powerhouse",
    plant_ids = c(
      "wfo-0000910097",  # Coffea arabica
      "wfo-0000421791",  # Vitis vinifera
      "wfo-0000861498",  # Dactylis glomerata
      "wfo-0001007437",  # Prunus spinosa
      "wfo-0000292858",  # Quercus robur
      "wfo-0001005999",  # Rosa canina
      "wfo-0000993770"   # Fragaria vesca
    ),
    expected_rust = 91.175641
  )
)

total_start <- Sys.time()

for (guild in guilds) {
  cat("\n----------------------------------------------------------------------\n")
  cat(sprintf("GUILD: %s\n", guild$name))
  cat("----------------------------------------------------------------------\n")

  guild_start <- Sys.time()

  # Score guild with details
  result <- scorer$score_guild(guild$plant_ids)

  scoring_time <- as.numeric(difftime(Sys.time(), guild_start, units = "secs")) * 1000

  # Print results
  cat("\nScores:\n")
  cat(sprintf("  R Overall:    %.6f\n", result$overall_score))
  cat(sprintf("  Rust Overall: %.6f\n", guild$expected_rust))
  diff <- abs(result$overall_score - guild$expected_rust)
  status <- if (diff < 0.0001) {
    "✅ PERFECT PARITY"
  } else if (diff < 0.01) {
    "✅ EXCELLENT PARITY"
  } else if (diff < 0.1) {
    "✅ GOOD PARITY"
  } else {
    "⚠️ PARITY ISSUE"
  }
  cat(sprintf("  Difference:   %.6f - %s\n", diff, status))

  cat("\nMetrics:\n")
  cat(sprintf("  M1 (Pest Independence):    %.2f (raw: %.6f)\n", result$metrics[1], result$raw_scores[1]))
  cat(sprintf("  M2 (Growth Compatibility): %.2f (raw: %.6f)\n", result$metrics[2], result$raw_scores[2]))
  cat(sprintf("  M3 (Insect Control):       %.2f (raw: %.6f)\n", result$metrics[3], result$raw_scores[3]))
  cat(sprintf("  M4 (Disease Control):      %.2f (raw: %.6f)\n", result$metrics[4], result$raw_scores[4]))
  cat(sprintf("  M5 (Beneficial Fungi):     %.2f (raw: %.6f)\n", result$metrics[5], result$raw_scores[5]))
  cat(sprintf("  M6 (Structural Diversity): %.2f (raw: %.6f)\n", result$metrics[6], result$raw_scores[6]))
  cat(sprintf("  M7 (Pollinator Support):   %.2f (raw: %.6f)\n", result$metrics[7], result$raw_scores[7]))

  # Show M4 details if available
  if (!is.null(result$details$m4)) {
    m4 <- result$details$m4
    cat("\nM4 Disease Control Details:\n")
    cat(sprintf("  Pathogen control raw: %.6f\n", m4$pathogen_control_raw))
    cat(sprintf("  Max possible: %d\n", m4$max_possible))
    cat(sprintf("  Mycoparasitic matches: %d\n", m4$mycoparasitic_matches))
    cat(sprintf("  Specific fungivore matches: %d\n", m4$specific_fungivore_matches))
    cat(sprintf("  Plants with pathogens: %d\n", m4$plants_with_pathogens))

    # Count mechanisms by type
    if (!is.null(m4$mechanisms)) {
      mech_types <- sapply(m4$mechanisms, function(m) m$type)
      cat(sprintf("\n  Total mechanisms: %d\n", length(m4$mechanisms)))
      cat(sprintf("    - specific_antagonist: %d\n", sum(mech_types == "specific_antagonist")))
      cat(sprintf("    - specific_fungivore_antagonist: %d\n", sum(mech_types == "specific_fungivore_antagonist")))
      cat(sprintf("    - general_mycoparasite: %d\n", sum(mech_types == "general_mycoparasite")))
      cat(sprintf("    - general_fungivore: %d\n", sum(mech_types == "general_fungivore")))
    }
  }

  cat(sprintf("\nPerformance: %.3f ms\n", scoring_time))
}

total_elapsed <- as.numeric(difftime(Sys.time(), total_start, units = "secs")) * 1000

cat("\n======================================================================\n")
cat("SUMMARY\n")
cat("======================================================================\n")
cat(sprintf("Total time (4 guilds): %.3f ms\n", total_elapsed))
cat("\n✅ All R scores computed successfully!\n")
cat("======================================================================\n\n")

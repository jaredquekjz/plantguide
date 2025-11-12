#!/usr/bin/env Rscript
#
# Test Forest Garden Guild - Compare R vs Python Results
#

suppressPackageStartupMessages({
  library(glue)
})

# Source the scorer
source("shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R")

cat("\n")
cat("==============================================================================\n")
cat("Test Forest Garden Guild - R Implementation\n")
cat("==============================================================================\n")

# Initialize scorer
scorer <- GuildScorerV3Shipley$new(calibration_type = '7plant', climate_tier = 'tier_3_humid_temperate')

# Forest Garden guild (from Python test_three_guilds.py)
forest_garden_ids <- c(
  'wfo-0000832453',  # Anaphalis margaritacea
  'wfo-0000649136',  # Mercurialis perennis
  'wfo-0000642673',  # Deutzia scabra
  'wfo-0000984977',  # Diospyros kaki
  'wfo-0000241769',  # Maianthemum racemosum
  'wfo-0000092746',  # Fraxinus excelsior
  'wfo-0000690499'   # Rubus moorei
)

cat("\nTesting Forest Garden (7 plants):\n")
cat(glue("  {paste(forest_garden_ids, collapse=', ')}\n"))
cat("\n")

# Score the guild
result <- scorer$score_guild(forest_garden_ids)

# Display results
cat("==============================================================================\n")
cat(glue("OVERALL SCORE: {round(result$overall_score, 1)} / 100\n"))
cat("==============================================================================\n")
cat("\nMETRIC BREAKDOWN (0-100 scale):\n")
cat(glue("  M1 (Pest Independence):    {round(result$metrics$m1, 1)}\n"))
cat(glue("  M2 (Growth Compatibility): {round(result$metrics$m2, 1)}\n"))
cat(glue("  M3 (Insect Control):       {round(result$metrics$m3, 1)}\n"))
cat(glue("  M4 (Disease Control):      {round(result$metrics$m4, 1)}\n"))
cat(glue("  M5 (Beneficial Fungi):     {round(result$metrics$m5, 1)}\n"))
cat(glue("  M6 (Structural Diversity): {round(result$metrics$m6, 1)}\n"))
cat(glue("  M7 (Pollinator Support):   {round(result$metrics$m7, 1)}\n"))
cat("\n")

cat("RAW SCORES:\n")
cat(glue("  M1 raw: {round(result$raw_scores$m1, 4)}\n"))
cat(glue("  M2 raw: {round(result$raw_scores$m2, 4)}\n"))
cat(glue("  M3 raw: {round(result$raw_scores$m3, 4)}\n"))
cat(glue("  M4 raw: {round(result$raw_scores$m4, 4)}\n"))
cat(glue("  M5 raw: {round(result$raw_scores$m5, 4)}\n"))
cat(glue("  M6 raw: {round(result$raw_scores$m6, 4)}\n"))
cat(glue("  M7 raw: {round(result$raw_scores$m7, 4)}\n"))
cat("\n")

# Display M3 and M4 details
cat("M3 DETAILS (Insect Control):\n")
cat(glue("  Biocontrol raw: {round(result$details$m3$biocontrol_raw, 2)}\n"))
cat(glue("  Max pairs: {result$details$m3$max_pairs}\n"))
cat(glue("  Mechanisms: {result$details$m3$n_mechanisms}\n"))
cat("\n")

cat("M4 DETAILS (Disease Control):\n")
cat(glue("  Pathogen control raw: {round(result$details$m4$pathogen_control_raw, 2)}\n"))
cat(glue("  Max pairs: {result$details$m4$max_pairs}\n"))
cat(glue("  Mechanisms: {result$details$m4$n_mechanisms}\n"))
cat("\n")

cat("==============================================================================\n")
cat("EXPECTED PYTHON RESULTS (from test_results/1_forest_garden.json):\n")
cat("==============================================================================\n")
cat("  Overall:  60.2\n")
cat("  M1:       54.2  (raw: 0.4297)\n")
cat("  M2:      100.0  (raw: 0.0000)\n")
cat("  M3:        0.0  (raw: 0.0000)\n")
cat("  M4:        0.0  (raw: 0.0000)\n")
cat("  M5:      100.0  (raw: 5.0857)\n")
cat("  M6:       75.2  (raw: 0.8800)\n")
cat("  M7:       91.9  (raw: 0.4082)\n")
cat("\n")

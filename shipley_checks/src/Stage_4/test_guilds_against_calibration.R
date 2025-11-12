#!/usr/bin/env Rscript
#
# Test Guild Scorer Against 100-Guild Calibration
#
# Tests the 7-metric framework frontend against calibration parameters
#

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
})

# Source components
cat("Loading components...\n")
source("shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R")
source("shipley_checks/src/Stage_4/explanation_engine_7metric.R")
source("shipley_checks/src/Stage_4/export_explanation_md.R")
source("shipley_checks/src/Stage_4/faiths_pd_calculator.R")

cat("\n")
cat(strrep("=", 80), "\n", sep="")
cat("Testing Guild Scorer V3 Against 100-Guild Calibration\n")
cat(strrep("=", 80), "\n", sep="")
cat("\n")

# Test guilds (same as Document 4.4)
test_guilds <- list(
  forest_garden = list(
    name = "Forest Garden",
    plant_ids = c(
      'wfo-0000832453',  # Fraxinus excelsior (Ash, 23.1m, C=36)
      'wfo-0000649136',  # Diospyros kaki (Persimmon, 12m, C=48)
      'wfo-0000642673',  # Deutzia scabra (Shrub, 2.1m, C=43)
      'wfo-0000984977',  # Rubus moorei (Bramble, 0.5m, C=43)
      'wfo-0000241769',  # Mercurialis perennis (Herb, 0.3m, C=36)
      'wfo-0000092746',  # Anaphalis margaritacea (Herb, 0.6m, C=32)
      'wfo-0000690499'   # Maianthemum racemosum (Herb, 0.5m, C=47)
    ),
    expected = "High M6 (structural diversity) - 4+ growth forms",
    expected_score = "60-80"
  ),

  competitive_clash = list(
    name = "Competitive Clash",
    plant_ids = c(
      'wfo-0000757278',  # Allium schoenoprasum (C=100)
      'wfo-0000944034',  # Alnus acuminata (C=69)
      'wfo-0000186915',  # Erythrina sandwicensis (C=67)
      'wfo-0000421791',  # Vitis vinifera (C=64)
      'wfo-0000418518',  # Virola bicuhyba (C=65)
      'wfo-0000841021',  # Cheirodendron trigynum (C=73)
      'wfo-0000394258'   # Pfaffia gnaphalioides (C=60)
    ),
    expected = "Low M2 (CSR conflicts) - multiple High-C plants",
    expected_score = "40-60"
  ),

  stress_tolerant = list(
    name = "Stress Tolerant",
    plant_ids = c(
      'wfo-0000721951',  # Hibbertia diffusa (S=80)
      'wfo-0000955348',  # Eucalyptus melanophloia (S=76)
      'wfo-0000901050',  # Sporobolus compositus (S=80)
      'wfo-0000956222',  # Alyxia ruscifolia (S=84)
      'wfo-0000777518',  # Juncus usitatus (S=86)
      'wfo-0000349035',  # Carex mucronata (S=90)
      'wfo-0000209726'   # Senna artemisioides (S=99)
    ),
    expected = "High M2 (perfect compatibility) - all High-S plants",
    expected_score = "50-70"
  )
)

# Initialize scorer
cat("Initializing scorer...\n")
scorer <- tryCatch({
  GuildScorerV3Shipley$new(
    calibration_type = '7plant',
    climate_tier = 'tier_3_humid_temperate'
  )
}, error = function(e) {
  cat("ERROR initializing scorer:\n")
  cat(conditionMessage(e), "\n")
  stop(e)
})

cat("\n")

# Create reports directory
dir.create("shipley_checks/reports", showWarnings = FALSE, recursive = TRUE)

# Test each guild
results <- list()
summary_data <- data.frame(
  guild = character(),
  overall_score = numeric(),
  m1 = numeric(),
  m2 = numeric(),
  m6 = numeric(),
  stringsAsFactors = FALSE
)

for (guild_name in names(test_guilds)) {
  guild <- test_guilds[[guild_name]]

  cat(strrep("=", 80), "\n", sep="")
  cat(glue("Testing: {guild$name}\n"))
  cat(strrep("=", 80), "\n", sep="")
  cat(glue("Expected: {guild$expected}\n"))
  cat(glue("Expected Score Range: {guild$expected_score}\n"))
  cat("\n")

  # Score guild
  result <- tryCatch({
    scorer$score_guild(guild$plant_ids)
  }, error = function(e) {
    cat("ERROR scoring guild:\n")
    cat(conditionMessage(e), "\n")
    return(NULL)
  })

  if (is.null(result)) {
    cat("Skipping due to error\n\n")
    next
  }

  # Generate explanation
  explanation <- tryCatch({
    generate_explanation(result)
  }, error = function(e) {
    cat("ERROR generating explanation:\n")
    cat(conditionMessage(e), "\n")
    return(NULL)
  })

  if (is.null(explanation)) {
    cat("Skipping due to error\n\n")
    next
  }

  # Export markdown
  output_path <- glue("shipley_checks/reports/{guild_name}_report.md")
  tryCatch({
    export_guild_report_md(result, explanation, output_path, guild$name)
  }, error = function(e) {
    cat("ERROR exporting report:\n")
    cat(conditionMessage(e), "\n")
  })

  # Print summary
  cat("\n")
  cat(glue("Overall Score: {round(result$overall_score, 1)}/100 {explanation$overall$stars} ({explanation$overall$label})\n"))
  cat("\n")
  cat("Metric Breakdown:\n")
  cat(glue("  M1 (Pest/Pathogen Independence): {round(result$metrics$m1, 1)}/100\n"))
  cat(glue("  M2 (Growth Compatibility): {round(result$metrics$m2, 1)}/100\n"))
  cat(glue("  M3 (Insect Control): {round(result$metrics$m3, 1)}/100\n"))
  cat(glue("  M4 (Disease Control): {round(result$metrics$m4, 1)}/100\n"))
  cat(glue("  M5 (Beneficial Fungi): {round(result$metrics$m5, 1)}/100\n"))
  cat(glue("  M6 (Structural Diversity): {round(result$metrics$m6, 1)}/100\n"))
  cat(glue("  M7 (Pollinator Support): {round(result$metrics$m7, 1)}/100\n"))
  cat("\n")
  cat(glue("Flags:\n"))
  cat(glue("  Nitrogen: {result$flags$nitrogen}\n"))
  cat(glue("  Soil pH: {result$flags$soil_ph}\n"))
  cat("\n")
  cat(glue("Report saved: {output_path}\n"))
  cat("\n")

  # Store result
  results[[guild_name]] <- result

  # Add to summary
  summary_data <- rbind(summary_data, data.frame(
    guild = guild$name,
    overall_score = round(result$overall_score, 1),
    m1 = round(result$metrics$m1, 1),
    m2 = round(result$metrics$m2, 1),
    m6 = round(result$metrics$m6, 1),
    stringsAsFactors = FALSE
  ))
}

# Print summary table
cat("\n")
cat(strrep("=", 80), "\n", sep="")
cat("SUMMARY TABLE\n")
cat(strrep("=", 80), "\n", sep="")
cat("\n")

if (nrow(summary_data) > 0) {
  print(summary_data, row.names = FALSE)
  cat("\n")

  # Export summary
  summary_path <- "shipley_checks/reports/summary.csv"
  write.csv(summary_data, summary_path, row.names = FALSE)
  cat(glue("Summary saved: {summary_path}\n"))
} else {
  cat("No results to summarize\n")
}

cat("\n")
cat(strrep("=", 80), "\n", sep="")
cat("All Tests Complete\n")
cat(strrep("=", 80), "\n", sep="")
cat("\n")
cat("Check reports in: shipley_checks/reports/\n")
cat("\n")

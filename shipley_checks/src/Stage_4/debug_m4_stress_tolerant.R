#!/usr/bin/env Rscript
#
# Debug M4 (Disease Control) discrepancy in Stress-Tolerant guild
# R: 73.70, Rust: 62.86 (difference: 10.84)
#

suppressPackageStartupMessages({
  library(dplyr)
  library(glue)
})

source('shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R')

cat("======================================================================\n")
cat("M4 DISEASE CONTROL DEBUG: Stress-Tolerant Guild\n")
cat("======================================================================\n\n")

# Initialize scorer
scorer <- GuildScorerV3Shipley$new('7plant', 'tier_3_humid_temperate')

# Stress-Tolerant guild
plant_ids <- c(
  "wfo-0000721951",
  "wfo-0000955348",
  "wfo-0000901050",
  "wfo-0000956222",
  "wfo-0000777518",
  "wfo-0000349035",
  "wfo-0000209726"
)

cat("Plants in guild:\n")
for (id in plant_ids) {
  plant_name <- scorer$plants_df %>%
    filter(wfo_taxon_id == id) %>%
    pull(wfo_scientific_name)
  cat(glue("  {id}: {plant_name}"), "\n")
}

cat("\n", strrep("-", 70), "\n\n")

# Score the guild and get details
result <- scorer$score_guild(plant_ids)

cat("Overall scores:\n")
cat(glue("  Overall: {sprintf('%.6f', result$overall_score)}"), "\n")
cat(glue("  M4 Score: {sprintf('%.2f', result$metrics[4])}"), "\n")
cat(glue("  M4 Raw: {sprintf('%.6f', result$raw_scores[4])}"), "\n")
cat("\n")

# Get M4 details
m4_details <- result$details$m4

cat("M4 Raw Score Components:\n")
cat(glue("  Total pathogen_control_raw: {sprintf('%.6f', m4_details$pathogen_control_raw)}"), "\n")
cat(glue("  Max possible: {m4_details$max_possible}"), "\n")
cat("\n")

cat("M4 Matching Details:\n")
cat(glue("  Mycoparasitic matches: {m4_details$mycoparasitic_matches}"), "\n")
cat(glue("  Specific fungivore matches: {m4_details$specific_fungivore_matches}"), "\n")
cat(glue("  Plants with pathogens: {m4_details$plants_with_pathogens}"), "\n")
cat("\n")

if (!is.null(m4_details$matched_mycoparasite_pairs)) {
  cat("Matched Mycoparasite Pairs:\n")
  for (pair in m4_details$matched_mycoparasite_pairs) {
    cat(glue("  {pair}"), "\n")
  }
  cat("\n")
}

if (!is.null(m4_details$matched_fungivore_pairs)) {
  cat("Matched Fungivore Pairs:\n")
  for (pair in m4_details$matched_fungivore_pairs) {
    cat(glue("  {pair}"), "\n")
  }
  cat("\n")
}

# Check pathogen data for each plant
cat(strrep("-", 70), "\n")
cat("Pathogen Data Per Plant:\n")
cat(strrep("-", 70), "\n\n")

for (plant_id in plant_ids) {
  plant_row <- scorer$fungi_df %>% filter(plant_wfo_id == plant_id)

  if (nrow(plant_row) > 0) {
    plant_name <- scorer$plants_df %>%
      filter(wfo_taxon_id == plant_id) %>%
      pull(wfo_scientific_name)

    pathogens <- plant_row$pathogens[[1]]
    cat(glue("{plant_id} ({plant_name}):"), "\n")

    if (!is.null(pathogens) && length(pathogens) > 0) {
      cat(glue("  Pathogens: {length(pathogens)} species"), "\n")
      if (length(pathogens) <= 10) {
        for (p in pathogens) {
          cat(glue("    - {p}"), "\n")
        }
      } else {
        for (p in pathogens[1:5]) {
          cat(glue("    - {p}"), "\n")
        }
        cat(glue("    ... and {length(pathogens) - 5} more"), "\n")
      }
    } else {
      cat("  Pathogens: NONE\n")
    }
    cat("\n")
  }
}

cat(strrep("=", 70), "\n")
cat("EXPECTED vs ACTUAL\n")
cat(strrep("=", 70), "\n")
cat(glue("Rust M4:     62.86"), "\n")
cat(glue("R M4:        {sprintf('%.2f', result$metrics[4])}"), "\n")
cat(glue("Difference:  {sprintf('%.2f', result$metrics[4] - 62.86)}"), "\n")
cat(strrep("=", 70), "\n")

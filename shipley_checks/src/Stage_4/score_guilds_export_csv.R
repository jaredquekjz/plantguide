#!/usr/bin/env Rscript
#
# Score guilds using R frontend and export to deterministic CSV
#
# Purpose: Generate gold standard CSV output for Python/R/Rust verification
#

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(jsonlite)
  library(readr)
})

source('shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R')

score_guilds <- function() {
  # Load test guild dataset
  guilds <- fromJSON('shipley_checks/stage4/100_guild_testset.json', simplifyVector = FALSE)

  cat(sprintf("Loaded %d test guilds\n", length(guilds)))

  results <- list()
  n_skipped <- 0

  for (i in seq_along(guilds)) {
    guild <- guilds[[i]]
    guild_id <- guild$guild_id
    plant_ids <- unlist(guild$plant_ids)  # Convert list to character vector
    climate_tier <- guild$climate_tier

    cat(sprintf("Scoring %s (%d plants, %s)...\n",
                guild_id, length(plant_ids), climate_tier))

    # Skip if no plants
    if (length(plant_ids) == 0) {
      cat(sprintf("  ⚠ Skipping %s: No plants\n", guild_id))
      n_skipped <- n_skipped + 1
      next
    }

    # Initialize scorer with correct climate tier
    scorer <- tryCatch({
      GuildScorerV3Shipley$new(
        calibration_type = '7plant',
        climate_tier = climate_tier
      )
    }, error = function(e) {
      cat(sprintf("  ⚠ Skipping %s: Scorer initialization failed - %s\n", guild_id, e$message))
      n_skipped <<- n_skipped + 1
      return(NULL)
    })

    if (is.null(scorer)) next

    # Score guild
    result <- tryCatch({
      scorer$score_guild(plant_ids)
    }, error = function(e) {
      cat(sprintf("  ⚠ Skipping %s: Scoring failed - %s\n", guild_id, e$message))
      n_skipped <<- n_skipped + 1
      return(NULL)
    })

    if (is.null(result)) next

    # Extract details from result
    details <- result$details

    # Build CSV row with deterministic precision
    row <- list(
      guild_id = guild_id,
      guild_name = guild$name,
      guild_size = guild$size,
      climate_tier = climate_tier,
      overall_score = round(result$overall_score, 1),

      # Normalized scores (M1-M7)
      m1_norm = round(result$metrics$m1, 1),
      m2_norm = round(result$metrics$m2, 1),
      m3_norm = round(result$metrics$m3, 1),
      m4_norm = round(result$metrics$m4, 1),
      m5_norm = round(result$metrics$m5, 1),
      m6_norm = round(result$metrics$m6, 1),
      m7_norm = round(result$metrics$m7, 1),

      # Raw scores
      m1_raw = round(result$raw_scores$m1, 6),
      m2_raw = round(result$raw_scores$m2, 6),
      m3_raw = round(result$raw_scores$m3, 6),
      m4_raw = round(result$raw_scores$m4, 6),
      m5_raw = round(result$raw_scores$m5, 6),
      m6_raw = round(result$raw_scores$m6, 6),
      m7_raw = round(result$raw_scores$m7, 6),

      # M1 details
      m1_faiths_pd = round(details$m1$faiths_pd %||% 0, 2),
      m1_pest_risk = round(result$raw_scores$m1, 6),

      # M2 details
      m2_conflicts = details$m2$n_conflicts %||% 0,
      m2_conflict_density = round(details$m2$conflict_density %||% 0, 6),

      # M3 details
      m3_biocontrol_raw = round(details$m3$biocontrol_raw %||% 0, 6),
      m3_max_pairs = details$m3$max_pairs %||% 0,
      m3_n_mechanisms = details$m3$n_mechanisms %||% 0,
      m3_mechanism_types = if (!is.null(details$m3$mechanisms) && length(details$m3$mechanisms) > 0) {
        paste(unique(sort(sapply(details$m3$mechanisms, function(m) m$type))), collapse = '|')
      } else '',

      # M4 details
      m4_pathogen_control_raw = round(details$m4$pathogen_control_raw %||% 0, 6),
      m4_max_pairs = details$m4$max_pairs %||% 0,
      m4_n_mechanisms = details$m4$n_mechanisms %||% 0,
      m4_mechanism_types = if (!is.null(details$m4$mechanisms) && length(details$m4$mechanisms) > 0) {
        paste(unique(sort(sapply(details$m4$mechanisms, function(m) m$type))), collapse = '|')
      } else '',

      # M5 details
      m5_n_shared_fungi = details$m5$n_shared_fungi %||% 0,
      m5_plants_with_fungi = details$m5$plants_with_fungi %||% 0,
      m5_shared_fungi_sample = if (!is.null(details$m5$shared_fungi_sample) && length(details$m5$shared_fungi_sample) > 0) {
        paste(head(details$m5$shared_fungi_sample, 5), collapse = '|')
      } else '',

      # M6 details
      m6_n_forms = details$m6$n_forms %||% 0,
      m6_height_range = round(details$m6$height_range %||% 0, 2),
      m6_forms = if (!is.null(details$m6$forms) && length(details$m6$forms) > 0) {
        paste(sort(details$m6$forms), collapse = '|')
      } else '',

      # M7 details
      m7_n_shared_pollinators = details$m7$n_shared_pollinators %||% 0,
      m7_plants_with_pollinators = details$m7$plants_with_pollinators %||% 0,
      m7_shared_pollinators_sample = if (!is.null(details$m7$shared_pollinators_sample) && length(details$m7$shared_pollinators_sample) > 0) {
        paste(head(details$m7$shared_pollinators_sample, 5), collapse = '|')
      } else '',

      # Flags
      flag_nitrogen = result$flags$nitrogen,
      flag_ph = result$flags$soil_ph,

      # Plant IDs
      plant_ids = paste(plant_ids, collapse = '|'),

      # Timestamp (fixed for deterministic output)
      timestamp = '2025-11-11T00:00:00Z'
    )

    results[[length(results) + 1]] <- row
  }

  # Convert to data frame and sort by guild_id
  df <- bind_rows(results) %>%
    arrange(guild_id)

  # Export to CSV
  output_path <- 'shipley_checks/stage4/guild_scores_r.csv'
  write_csv(df, output_path)

  cat(sprintf("\n✓ Exported %d guild scores to %s\n", nrow(df), output_path))
  cat(sprintf("  Skipped: %d guilds\n", n_skipped))
  cat(sprintf("  File size: %s bytes\n", format(file.size(output_path), big.mark = ',')))

  # Show summary
  cat(sprintf("\nSummary:\n"))
  cat(sprintf("  Mean overall score: %.1f\n", mean(df$overall_score)))
  cat(sprintf("  Score range: %.1f - %.1f\n", min(df$overall_score), max(df$overall_score)))

  return(df)
}

# Run if called directly
if (!interactive()) {
  score_guilds()
}

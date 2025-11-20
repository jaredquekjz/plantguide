#!/usr/bin/env Rscript
# M3 Debug Script for Guild 1

library(dplyr)
source('shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R')

# Initialize scorer
scorer <- GuildScorerV3Shipley$new('7plant', 'tier_3_humid_temperate')

# Guild 1: Forest Garden
plant_ids <- c('wfo-0000832453', 'wfo-0000649136', 'wfo-0000642673',
               'wfo-0000984977', 'wfo-0000241769', 'wfo-0000092746',
               'wfo-0000690499')

cat("\n=== M3 DEBUG (R): Guild organism data ===\n")

# Get guild organisms and fungi
guild_organisms <- scorer$organisms_df %>% filter(plant_wfo_id %in% plant_ids)
guild_fungi <- scorer$fungi_df %>% filter(plant_wfo_id %in% plant_ids)

cat("Total plants in guild:", length(plant_ids), "\n")

# Show first 3 plants
for (i in 1:min(3, nrow(guild_organisms))) {
  row <- guild_organisms[i, ]
  plant_id <- row$plant_wfo_id

  herbivores_count <- length(row$herbivores[[1]] %||% character(0))

  # Count predators from all 4 columns (matching R logic)
  predators <- c()
  if (!is.null(row$flower_visitors[[1]])) {
    predators <- c(predators, row$flower_visitors[[1]])
  }
  if ("predators_hasHost" %in% names(row) && !is.null(row$predators_hasHost[[1]])) {
    predators <- c(predators, row$predators_hasHost[[1]])
  }
  if ("predators_interactsWith" %in% names(row) && !is.null(row$predators_interactsWith[[1]])) {
    predators <- c(predators, row$predators_interactsWith[[1]])
  }
  if ("predators_adjacentTo" %in% names(row) && !is.null(row$predators_adjacentTo[[1]])) {
    predators <- c(predators, row$predators_adjacentTo[[1]])
  }
  predators <- unique(predators)

  # Get fungi
  fungi_row <- guild_fungi %>% filter(plant_wfo_id == plant_id)
  fungi_count <- 0
  if (nrow(fungi_row) > 0) {
    entomo <- fungi_row$entomopathogenic_fungi[[1]] %||% character(0)
    fungi_count <- length(entomo)
  }

  cat(sprintf("Plant %s: herbivores=%d, predators=%d, fungi=%d\n",
              plant_id, herbivores_count, length(predators), fungi_count))
}

# Now run the actual M3 calculation
guild_plants <- scorer$plants_df %>% filter(wfo_taxon_id %in% plant_ids)
result <- scorer$calculate_m3(plant_ids, guild_plants)

cat("\n=== M3 DEBUG (R): Final calculation ===\n")
cat("biocontrol_raw:", result$details$biocontrol_raw, "\n")
cat("max_pairs:", result$details$max_pairs, "\n")
cat("biocontrol_normalized (raw score):", result$raw, "\n")
cat("n_mechanisms:", result$details$n_mechanisms, "\n")
cat("===============================\n\n")

# Also print the overall result
cat("M3 normalized score:", result$norm, "\n")

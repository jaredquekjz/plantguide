#!/usr/bin/env Rscript
#
# PEST VULNERABILITY ANALYSIS FOR M1
#
# Analyzes herbivore pest profiles for guilds, identifying:
# - Shared pests (generalists attacking 2+ plants)
# - Top 10 pests by interaction count
# - Most vulnerable plants
#
# This module provides qualitative information about pest vulnerability
# that supplements M1 scoring (phylogenetic diversity).
#
# Rust reference: src/explanation/pest_analysis.rs

#' Analyze pest profile for a guild
#'
#' Extracts herbivore information from organisms_df and identifies generalist
#' pests and vulnerable plants.
#'
#' @param guild_plants Data frame with guild plant data
#' @param organisms_df Data frame with organism associations
#'
#' @return List with pest profile, or NULL if no pests
#'
analyze_guild_pests <- function(guild_plants,
                                organisms_df) {

  n_plants <- nrow(guild_plants)

  if (n_plants == 0) {
    return(NULL)
  }

  # Filter organisms_df to guild plants
  plant_ids <- guild_plants$wfo_taxon_id
  guild_organisms <- organisms_df %>% dplyr::filter(plant_wfo_id %in% plant_ids)

  if (nrow(guild_organisms) == 0) {
    return(NULL)
  }

  # Build plant ID → name mapping
  plant_names <- setNames(
    guild_plants$wfo_scientific_name,
    guild_plants$wfo_taxon_id
  )

  # Build pest-to-plants mapping and plant-to-pest-count mapping
  pest_to_plants <- list()
  plant_pest_counts <- list()

  for (i in seq_len(nrow(guild_organisms))) {
    row <- guild_organisms[i, ]
    plant_id <- row$plant_wfo_id
    plant_name <- plant_names[[plant_id]]

    herbivores <- row$herbivores
    if (is.list(herbivores)) herbivores <- herbivores[[1]]

    if (!is.null(herbivores) && length(herbivores) > 0) {
      # Count pests for this plant
      if (is.null(plant_pest_counts[[plant_name]])) {
        plant_pest_counts[[plant_name]] <- 0
      }
      plant_pest_counts[[plant_name]] <- plant_pest_counts[[plant_name]] + length(herbivores)

      # Map pests to plants
      for (pest in herbivores) {
        if (is.null(pest_to_plants[[pest]])) {
          pest_to_plants[[pest]] <- character()
        }
        pest_to_plants[[pest]] <- c(pest_to_plants[[pest]], plant_name)
      }
    }
  }

  if (length(pest_to_plants) == 0) {
    return(NULL)
  }

  # Deduplicate plants per pest
  for (pest in names(pest_to_plants)) {
    pest_to_plants[[pest]] <- unique(pest_to_plants[[pest]])
  }

  total_unique_pests <- length(pest_to_plants)

  # Identify shared pests (2+ plants)
  shared_pests <- data.frame(
    pest_name = character(),
    plant_count = integer(),
    plants = character(),
    stringsAsFactors = FALSE
  )

  for (pest in names(pest_to_plants)) {
    plants <- pest_to_plants[[pest]]
    if (length(plants) >= 2) {
      shared_pests <- rbind(shared_pests, data.frame(
        pest_name = pest,
        plant_count = length(plants),
        plants = paste(plants, collapse = ", "),
        stringsAsFactors = FALSE
      ))
    }
  }

  # Sort by plant_count descending, then pest_name ascending
  if (nrow(shared_pests) > 0) {
    shared_pests <- shared_pests[order(-shared_pests$plant_count, shared_pests$pest_name), ]
  }

  # Top 10 pests by plant count (even if only 1 plant)
  top_pests <- data.frame(
    pest_name = character(),
    plant_count = integer(),
    plants = character(),
    stringsAsFactors = FALSE
  )

  for (pest in names(pest_to_plants)) {
    plants <- pest_to_plants[[pest]]
    top_pests <- rbind(top_pests, data.frame(
      pest_name = pest,
      plant_count = length(plants),
      plants = paste(plants, collapse = ", "),
      stringsAsFactors = FALSE
    ))
  }

  # Sort by plant_count descending, then pest_name ascending
  if (nrow(top_pests) > 0) {
    top_pests <- top_pests[order(-top_pests$plant_count, top_pests$pest_name), ]
    top_pests <- head(top_pests, 10)
  }

  # Most vulnerable plants (by pest count)
  vulnerable_plants <- data.frame(
    plant_name = character(),
    pest_count = integer(),
    stringsAsFactors = FALSE
  )

  for (plant_name in names(plant_pest_counts)) {
    vulnerable_plants <- rbind(vulnerable_plants, data.frame(
      plant_name = plant_name,
      pest_count = plant_pest_counts[[plant_name]],
      stringsAsFactors = FALSE
    ))
  }

  # Sort by pest_count descending, then plant_name ascending
  if (nrow(vulnerable_plants) > 0) {
    vulnerable_plants <- vulnerable_plants[order(-vulnerable_plants$pest_count, vulnerable_plants$plant_name), ]
  }

  # Return pest profile
  list(
    total_unique_pests = total_unique_pests,
    shared_pests = shared_pests,
    top_pests = top_pests,
    vulnerable_plants = vulnerable_plants
  )
}

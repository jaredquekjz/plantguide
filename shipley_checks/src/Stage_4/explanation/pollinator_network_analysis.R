#!/usr/bin/env Rscript
#
# POLLINATOR NETWORK ANALYSIS FOR M7 (POLLINATOR SUPPORT)
#
# Analyzes pollinator networks to provide qualitative information about:
# - Shared pollinators and their connectivity
# - Top pollinators by interaction counts
# - Pollinator diversity by taxonomic group
# - Network hubs (plants with most pollinator associations)
#
# This module provides qualitative information about pollinator networks
# that supplement M7 scoring.
#
# Rust reference: src/explanation/pollinator_network_analysis.rs

#' Analyze pollinator network for a guild
#'
#' Takes M7Result with pollinator_counts and guild DataFrames to build detailed profile.
#'
#' @param m7_result List returned from calculate_m7_pollinator_support containing:
#'   - pollinator_counts: named list of pollinator → plant_count
#'   - pollinator_category_map: named list of pollinator → category string
#' @param guild_plants Data frame with guild plant data
#' @param organisms_df Data frame with organism associations
#'
#' @return List with pollinator network profile, or NULL if no pollinators
#'
analyze_pollinator_network <- function(m7_result,
                                       guild_plants,
                                       organisms_df) {

  n_plants <- nrow(guild_plants)

  pollinator_counts <- m7_result$pollinator_counts
  pollinator_category_map <- m7_result$pollinator_category_map

  if (length(pollinator_counts) == 0) {
    return(NULL)
  }

  # Build plant ID → name mapping
  plant_names <- setNames(
    guild_plants$wfo_scientific_name,
    guild_plants$wfo_taxon_id
  )

  # Build pollinator_to_plants mapping
  pollinator_to_plants <- build_pollinator_to_plants_mapping(
    organisms_df,
    guild_plants
  )

  # Build shared pollinators list (2+ plants)
  shared_pollinators <- data.frame(
    pollinator_name = character(),
    plant_count = integer(),
    plants = character(),
    category = character(),
    network_contribution = numeric(),
    stringsAsFactors = FALSE
  )

  for (pollinator_name in names(pollinator_counts)) {
    count <- pollinator_counts[[pollinator_name]]
    category <- pollinator_category_map[[pollinator_name]]

    if (count >= 2) {
      plants <- pollinator_to_plants[[pollinator_name]]
      if (is.null(plants)) plants <- character()

      # Map plant IDs to names
      plant_names_list <- sapply(plants, function(id) plant_names[[id]])
      plant_names_list <- plant_names_list[!is.na(plant_names_list)]
      plants_str <- paste(plant_names_list, collapse = ", ")

      shared_pollinators <- rbind(shared_pollinators, data.frame(
        pollinator_name = pollinator_name,
        plant_count = count,
        plants = plants_str,
        category = category,
        network_contribution = count / n_plants,
        stringsAsFactors = FALSE
      ))
    }
  }

  # Sort by network_contribution desc, then pollinator_name asc
  if (nrow(shared_pollinators) > 0) {
    shared_pollinators <- shared_pollinators[order(-shared_pollinators$network_contribution, shared_pollinators$pollinator_name), ]
  }

  # Build top 10 pollinators list
  top_pollinators <- data.frame(
    pollinator_name = character(),
    plant_count = integer(),
    plants = character(),
    category = character(),
    network_contribution = numeric(),
    stringsAsFactors = FALSE
  )

  for (pollinator_name in names(pollinator_counts)) {
    count <- pollinator_counts[[pollinator_name]]
    category <- pollinator_category_map[[pollinator_name]]

    plants <- pollinator_to_plants[[pollinator_name]]
    if (is.null(plants)) plants <- character()

    # Map plant IDs to names and limit to first 5
    plant_names_list <- sapply(plants, function(id) plant_names[[id]])
    plant_names_list <- plant_names_list[!is.na(plant_names_list)]
    plants_str <- paste(head(plant_names_list, 5), collapse = ", ")

    top_pollinators <- rbind(top_pollinators, data.frame(
      pollinator_name = pollinator_name,
      plant_count = count,
      plants = plants_str,
      category = category,
      network_contribution = count / n_plants,
      stringsAsFactors = FALSE
    ))
  }

  # Sort by network_contribution desc, then pollinator_name asc
  if (nrow(top_pollinators) > 0) {
    top_pollinators <- top_pollinators[order(-top_pollinators$network_contribution, top_pollinators$pollinator_name), ]
    top_pollinators <- head(top_pollinators, 10)
  }

  # Count pollinators by category
  category_counts <- table(unlist(pollinator_category_map))

  # Build plant pollinator hubs
  hub_plants <- build_plant_pollinator_hubs(
    guild_plants,
    organisms_df,
    pollinator_category_map
  )

  # Return pollinator network profile
  list(
    total_unique_pollinators = length(pollinator_counts),
    shared_pollinators = shared_pollinators,
    top_pollinators = top_pollinators,
    category_counts = as.list(category_counts),
    hub_plants = hub_plants
  )
}


#' Build pollinator_to_plants mapping
#'
#' @param organisms_df Data frame with organism associations
#' @param guild_plants Data frame with guild plant data
#'
#' @return Named list mapping pollinator_name → vector of plant_ids
#'
build_pollinator_to_plants_mapping <- function(organisms_df,
                                               guild_plants) {

  plant_ids <- guild_plants$wfo_taxon_id
  map <- list()

  for (i in seq_len(nrow(organisms_df))) {
    row <- organisms_df[i, ]
    plant_id <- row$plant_wfo_id

    # Only process plants in guild
    if (!(plant_id %in% plant_ids)) {
      next
    }

    # Process both pollinators and flower_visitors columns
    for (col in c("pollinators", "flower_visitors")) {
      col_val <- row[[col]]
      if (is.list(col_val)) col_val <- col_val[[1]]

      if (!is.null(col_val) && length(col_val) > 0) {
        for (pollinator in col_val) {
          if (is.null(map[[pollinator]])) {
            map[[pollinator]] <- character()
          }
          map[[pollinator]] <- c(map[[pollinator]], plant_id)
        }
      }
    }
  }

  # Deduplicate plant lists
  for (pollinator in names(map)) {
    map[[pollinator]] <- unique(map[[pollinator]])
  }

  map
}


#' Build plant pollinator hubs
#'
#' @param guild_plants Data frame with guild plant data
#' @param organisms_df Data frame with organism associations
#' @param pollinator_category_map Named list of pollinator → category
#'
#' @return Data frame with columns: plant_name, total, Bees, Butterflies, Moths, Flies, Beetles, Wasps, Birds, Bats, Other
#'
build_plant_pollinator_hubs <- function(guild_plants,
                                        organisms_df,
                                        pollinator_category_map) {

  result <- data.frame(
    plant_name = character(),
    total = integer(),
    Bees = integer(),
    Butterflies = integer(),
    Moths = integer(),
    Flies = integer(),
    Beetles = integer(),
    Wasps = integer(),
    Birds = integer(),
    Bats = integer(),
    Other = integer(),
    stringsAsFactors = FALSE
  )

  for (i in seq_len(nrow(guild_plants))) {
    plant_id <- guild_plants$wfo_taxon_id[i]
    plant_name <- guild_plants$wfo_scientific_name[i]

    # Find this plant in organisms_df
    org_row <- organisms_df[organisms_df$plant_wfo_id == plant_id, ]

    if (nrow(org_row) == 0) {
      next
    }

    org_row <- org_row[1, ]  # Take first row if multiple

    # Collect all pollinators for this plant
    pollinators <- character()
    for (col in c("pollinators", "flower_visitors")) {
      col_val <- org_row[[col]]
      if (is.list(col_val)) col_val <- col_val[[1]]
      if (!is.null(col_val) && length(col_val) > 0) {
        pollinators <- c(pollinators, col_val)
      }
    }

    pollinators <- unique(pollinators)

    if (length(pollinators) == 0) {
      next
    }

    # Count by category
    category_counts <- list(
      Bees = 0,
      Butterflies = 0,
      Moths = 0,
      Flies = 0,
      Beetles = 0,
      Wasps = 0,
      Birds = 0,
      Bats = 0,
      Other = 0
    )

    for (pollinator in pollinators) {
      category <- pollinator_category_map[[pollinator]]
      if (is.null(category)) category <- "Other"
      category_counts[[category]] <- category_counts[[category]] + 1
    }

    result <- rbind(result, data.frame(
      plant_name = plant_name,
      total = length(pollinators),
      Bees = category_counts$Bees,
      Butterflies = category_counts$Butterflies,
      Moths = category_counts$Moths,
      Flies = category_counts$Flies,
      Beetles = category_counts$Beetles,
      Wasps = category_counts$Wasps,
      Birds = category_counts$Birds,
      Bats = category_counts$Bats,
      Other = category_counts$Other,
      stringsAsFactors = FALSE
    ))
  }

  # Sort by total descending, then plant_name ascending
  if (nrow(result) > 0) {
    result <- result[order(-result$total, result$plant_name), ]
    result <- head(result, 10)
  }

  result
}

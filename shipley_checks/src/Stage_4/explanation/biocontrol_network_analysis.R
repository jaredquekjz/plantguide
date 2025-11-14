#!/usr/bin/env Rscript
#
# BIOCONTROL NETWORK ANALYSIS FOR M3 (INSECT PEST CONTROL)
#
# Analyzes which plants attract beneficial predators and entomopathogenic fungi,
# identifies generalist biocontrol agents, and finds network hubs.
#
# This module provides qualitative information about pest control mechanisms
# that influence M3 scoring.
#
# Rust reference: src/explanation/biocontrol_network_analysis.rs

# Source unified taxonomic categorization
source("shipley_checks/src/Stage_4/explanation/unified_taxonomy.R")

#' Categorize a predator (wrapper for backward compatibility)
#' @deprecated Use categorize_organism(name, "predator") instead
categorize_predator <- function(name) {
  categorize_organism(name, "predator")
}

#' Categorize a herbivore pest (wrapper for backward compatibility)
#' @deprecated Use categorize_organism(name, "herbivore") instead
categorize_herbivore <- function(name) {
  categorize_organism(name, "herbivore")
}

#' Analyze biocontrol network for M3
#'
#' Extracts predator and entomopathogenic fungi information from organisms and
#' fungi DataFrames, identifies generalist agents, and finds hub plants.
#'
#' @param m3_result List returned from calculate_m3_insect_control containing:
#'   - predator_counts: named list of predator → plant_count
#'   - entomo_fungi_counts: named list of fungus → plant_count
#'   - specific_predator_matches: integer count
#'   - specific_fungi_matches: integer count
#'   - matched_predator_pairs: data.frame with herbivore, predator columns
#'   - matched_fungi_pairs: data.frame with herbivore, fungus columns
#' @param guild_plants Data frame with guild plant data
#' @param organisms_df Data frame with organism associations
#' @param fungi_df Data frame with fungal associations
#'
#' @return List with biocontrol network profile, or NULL if no biocontrol agents
#'
analyze_biocontrol_network <- function(m3_result,
                                       guild_plants,
                                       organisms_df,
                                       fungi_df) {

  n_plants <- nrow(guild_plants)

  if (n_plants == 0) {
    return(NULL)
  }

  # Extract counts from M3 result
  predator_counts <- m3_result$predator_counts
  entomo_fungi_counts <- m3_result$entomo_fungi_counts

  total_unique_predators <- length(predator_counts)
  total_unique_entomo_fungi <- length(entomo_fungi_counts)

  # Calculate general entomopathogenic fungi count (sum of all fungi counts)
  general_entomo_fungi_count <- sum(unlist(entomo_fungi_counts))

  if (total_unique_predators == 0 && total_unique_entomo_fungi == 0) {
    return(NULL)
  }

  # Build plant ID → name mapping
  plant_names <- setNames(
    guild_plants$wfo_scientific_name,
    guild_plants$wfo_taxon_id
  )

  # Get top predators by connectivity (visiting 2+ plants)
  top_predators <- get_top_biocontrol_agents(
    predator_counts,
    plant_names,
    organisms_df,
    "Predator",
    n_plants,
    limit = 10
  )

  # Get top entomopathogenic fungi by connectivity (visiting 2+ plants)
  top_entomo_fungi <- get_top_biocontrol_agents(
    entomo_fungi_counts,
    plant_names,
    fungi_df,
    "Entomopathogenic Fungus",
    n_plants,
    limit = 10
  )

  # Build filter sets from M3 result counts (these are already filtered agents)
  known_predators <- names(predator_counts)
  known_entomo_fungi <- names(entomo_fungi_counts)

  # Find hub plants (using filtered agent sets)
  hub_plants <- find_biocontrol_hubs(
    guild_plants,
    organisms_df,
    fungi_df,
    known_predators,
    known_entomo_fungi
  )

  # Categorize predators and build category counts
  predator_category_map <- sapply(names(predator_counts), categorize_predator)
  predator_category_counts <- table(predator_category_map)

  # Categorize herbivores from matched pairs and build category counts
  herbivore_category_map <- list()
  if (nrow(m3_result$matched_predator_pairs) > 0) {
    unique_herbivores <- unique(m3_result$matched_predator_pairs$herbivore)
    herbivore_category_map <- sapply(unique_herbivores, categorize_herbivore)
  }
  herbivore_category_counts <- if (length(herbivore_category_map) > 0) {
    table(herbivore_category_map)
  } else {
    list()
  }

  # Add category columns to matched predator pairs
  matched_predator_pairs_with_categories <- m3_result$matched_predator_pairs
  if (nrow(matched_predator_pairs_with_categories) > 0) {
    matched_predator_pairs_with_categories$herbivore_category <- sapply(
      matched_predator_pairs_with_categories$herbivore,
      categorize_herbivore
    )
    matched_predator_pairs_with_categories$predator_category <- sapply(
      matched_predator_pairs_with_categories$predator,
      categorize_predator
    )
  }

  # Return biocontrol network profile
  list(
    total_unique_predators = total_unique_predators,
    total_unique_entomo_fungi = total_unique_entomo_fungi,
    specific_predator_matches = m3_result$specific_predator_matches,
    specific_fungi_matches = m3_result$specific_fungi_matches,
    general_entomo_fungi_count = general_entomo_fungi_count,
    matched_predator_pairs = matched_predator_pairs_with_categories,
    matched_fungi_pairs = m3_result$matched_fungi_pairs,
    top_predators = top_predators,
    top_entomo_fungi = top_entomo_fungi,
    hub_plants = hub_plants,
    predator_category_counts = as.list(predator_category_counts),
    herbivore_category_counts = as.list(herbivore_category_counts)
  )
}


#' Get top biocontrol agents by connectivity
#'
#' Returns agents that visit 2+ plants, sorted by plant_count descending.
#'
#' @param agent_counts Named list of agent → plant_count
#' @param plant_names Named vector of plant_id → scientific_name
#' @param df Data frame (organisms_df or fungi_df)
#' @param agent_type String: "Predator" or "Entomopathogenic Fungus"
#' @param n_plants Total number of plants in guild
#' @param limit Maximum number of agents to return
#'
#' @return Data frame with columns: agent_name, agent_type, plant_count, plants, network_contribution
#'
get_top_biocontrol_agents <- function(agent_counts,
                                      plant_names,
                                      df,
                                      agent_type,
                                      n_plants,
                                      limit = 10) {

  if (length(agent_counts) == 0) {
    return(data.frame(
      agent_name = character(),
      agent_type = character(),
      plant_count = integer(),
      plants = character(),
      network_contribution = numeric()
    ))
  }

  # Build agent → [plant_ids] mapping from DataFrame
  if (agent_type == "Predator") {
    agent_to_plants <- build_predator_to_plants_map(df)
  } else {
    agent_to_plants <- build_fungi_to_plants_map(df)
  }

  # Build result data frame
  result <- data.frame(
    agent_name = character(),
    agent_type = character(),
    plant_count = integer(),
    plants = character(),
    network_contribution = numeric(),
    stringsAsFactors = FALSE
  )

  for (agent_name in names(agent_counts)) {
    count <- agent_counts[[agent_name]]

    # Only show agents visiting 2+ plants
    if (count < 2) {
      next
    }

    plant_ids <- agent_to_plants[[agent_name]]
    if (is.null(plant_ids)) {
      plant_ids <- character()
    }

    # Map plant IDs to names and limit to first 5
    plant_names_list <- sapply(plant_ids, function(id) plant_names[[id]])
    plant_names_list <- plant_names_list[!is.na(plant_names_list)]
    plants_str <- paste(head(plant_names_list, 5), collapse = ", ")

    result <- rbind(result, data.frame(
      agent_name = agent_name,
      agent_type = agent_type,
      plant_count = count,
      plants = plants_str,
      network_contribution = count / n_plants,
      stringsAsFactors = FALSE
    ))
  }

  # Sort by plant_count descending, then agent_name ascending
  if (nrow(result) > 0) {
    result <- result[order(-result$plant_count, result$agent_name), ]
    result <- head(result, limit)
  }

  result
}


#' Build predator → [plant_ids] mapping from organisms DataFrame
#'
#' @param organisms_df Data frame with organism associations
#' @return Named list mapping predator_name → vector of plant_ids
#'
build_predator_to_plants_map <- function(organisms_df) {
  map <- list()

  predator_columns <- c(
    "predators_hasHost",
    "predators_interactsWith",
    "predators_adjacentTo"
  )

  for (i in seq_len(nrow(organisms_df))) {
    row <- organisms_df[i, ]
    plant_id <- row$plant_wfo_id

    for (col_name in predator_columns) {
      col_val <- row[[col_name]]
      if (is.list(col_val)) col_val <- col_val[[1]]

      if (!is.null(col_val) && length(col_val) > 0) {
        for (predator in col_val) {
          if (is.null(map[[predator]])) {
            map[[predator]] <- character()
          }
          map[[predator]] <- c(map[[predator]], plant_id)
        }
      }
    }
  }

  # Deduplicate plant lists
  for (agent in names(map)) {
    map[[agent]] <- unique(map[[agent]])
  }

  map
}


#' Build entomopathogenic_fungi → [plant_ids] mapping from fungi DataFrame
#'
#' @param fungi_df Data frame with fungal associations
#' @return Named list mapping fungus_name → vector of plant_ids
#'
build_fungi_to_plants_map <- function(fungi_df) {
  map <- list()

  for (i in seq_len(nrow(fungi_df))) {
    row <- fungi_df[i, ]
    plant_id <- row$plant_wfo_id

    entomo <- row$entomopathogenic_fungi
    if (is.list(entomo)) entomo <- entomo[[1]]

    if (!is.null(entomo) && length(entomo) > 0) {
      for (fungus in entomo) {
        if (is.null(map[[fungus]])) {
          map[[fungus]] <- character()
        }
        map[[fungus]] <- c(map[[fungus]], plant_id)
      }
    }
  }

  # Deduplicate plant lists
  for (agent in names(map)) {
    map[[agent]] <- unique(map[[agent]])
  }

  map
}


#' Find plants that are biocontrol hubs (attract most agents)
#'
#' @param guild_plants Data frame with guild plant data
#' @param organisms_df Data frame with organism associations
#' @param fungi_df Data frame with fungal associations
#' @param known_predators Character vector of known predator names
#' @param known_entomo_fungi Character vector of known entomopathogenic fungus names
#'
#' @return Data frame with columns: plant_name, total_predators, total_entomo_fungi, total_biocontrol_agents
#'
find_biocontrol_hubs <- function(guild_plants,
                                 organisms_df,
                                 fungi_df,
                                 known_predators,
                                 known_entomo_fungi) {

  result <- data.frame(
    plant_name = character(),
    total_predators = integer(),
    total_entomo_fungi = integer(),
    total_biocontrol_agents = integer(),
    stringsAsFactors = FALSE
  )

  for (i in seq_len(nrow(guild_plants))) {
    plant_id <- guild_plants$wfo_taxon_id[i]
    plant_name <- guild_plants$wfo_scientific_name[i]

    # Count predators for this plant (filtered to known predators only)
    total_predators <- count_predators_for_plant(
      organisms_df,
      plant_id,
      known_predators
    )

    # Count entomopathogenic fungi for this plant (filtered to known fungi only)
    total_entomo_fungi <- count_entomo_fungi_for_plant(
      fungi_df,
      plant_id,
      known_entomo_fungi
    )

    total_biocontrol_agents <- total_predators + total_entomo_fungi

    if (total_biocontrol_agents > 0) {
      result <- rbind(result, data.frame(
        plant_name = plant_name,
        total_predators = total_predators,
        total_entomo_fungi = total_entomo_fungi,
        total_biocontrol_agents = total_biocontrol_agents,
        stringsAsFactors = FALSE
      ))
    }
  }

  # Sort by total_biocontrol_agents descending, then plant_name ascending
  if (nrow(result) > 0) {
    result <- result[order(-result$total_biocontrol_agents, result$plant_name), ]
    result <- head(result, 10)
  }

  result
}


#' Count predators for a specific plant (filtered to known predators only)
#'
#' @param organisms_df Data frame with organism associations
#' @param target_plant_id String: plant WFO ID
#' @param known_predators Character vector of known predator names
#'
#' @return Integer count of unique predators
#'
count_predators_for_plant <- function(organisms_df,
                                      target_plant_id,
                                      known_predators) {

  predator_columns <- c(
    "predators_hasHost",
    "predators_interactsWith",
    "predators_adjacentTo"
  )

  predators <- character()

  for (i in seq_len(nrow(organisms_df))) {
    row <- organisms_df[i, ]
    plant_id <- row$plant_wfo_id

    if (plant_id == target_plant_id) {
      for (col_name in predator_columns) {
        col_val <- row[[col_name]]
        if (is.list(col_val)) col_val <- col_val[[1]]

        if (!is.null(col_val) && length(col_val) > 0) {
          for (predator in col_val) {
            # ONLY count if this is a known predator from lookup table
            if (predator %in% known_predators) {
              predators <- c(predators, predator)
            }
          }
        }
      }

      predators <- unique(predators)
      return(length(predators))
    }
  }

  0
}


#' Count entomopathogenic fungi for a specific plant (filtered to known fungi only)
#'
#' @param fungi_df Data frame with fungal associations
#' @param target_plant_id String: plant WFO ID
#' @param known_entomo_fungi Character vector of known entomopathogenic fungus names
#'
#' @return Integer count of unique entomopathogenic fungi
#'
count_entomo_fungi_for_plant <- function(fungi_df,
                                         target_plant_id,
                                         known_entomo_fungi) {

  for (i in seq_len(nrow(fungi_df))) {
    row <- fungi_df[i, ]
    plant_id <- row$plant_wfo_id

    if (plant_id == target_plant_id) {
      entomo <- row$entomopathogenic_fungi
      if (is.list(entomo)) entomo <- entomo[[1]]

      if (!is.null(entomo) && length(entomo) > 0) {
        # ONLY count fungi that are known entomopathogenic fungi from lookup table
        count <- sum(entomo %in% known_entomo_fungi)
        return(count)
      }
      return(0)
    }
  }

  0
}

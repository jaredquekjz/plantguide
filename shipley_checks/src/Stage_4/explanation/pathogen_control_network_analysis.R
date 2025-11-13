#!/usr/bin/env Rscript
#
# PATHOGEN CONTROL NETWORK ANALYSIS FOR M4 (DISEASE SUPPRESSION)
#
# Analyzes which plants harbor beneficial mycoparasitic fungi that suppress
# pathogenic fungi, identifies generalist mycoparasites, and finds network hubs.
#
# This module provides qualitative information about disease control mechanisms
# that influence M4 scoring.
#
# Rust reference: src/explanation/pathogen_control_network_analysis.rs

#' Analyze pathogen control network for M4
#'
#' Extracts mycoparasite and pathogen information from fungi DataFrame,
#' identifies protective relationships, and finds hub plants.
#'
#' @param m4_result List returned from calculate_m4_disease_control containing:
#'   - mycoparasite_counts: named list of mycoparasite → plant_count
#'   - pathogen_counts: named list of pathogen → plant_count
#'   - specific_antagonist_matches: integer count
#'   - matched_antagonist_pairs: data.frame with pathogen, antagonist columns
#' @param guild_plants Data frame with guild plant data
#' @param fungi_df Data frame with fungal associations
#'
#' @return List with pathogen control network profile, or NULL if no agents
#'
analyze_pathogen_control_network <- function(m4_result,
                                             guild_plants,
                                             fungi_df) {

  n_plants <- nrow(guild_plants)

  if (n_plants == 0) {
    return(NULL)
  }

  # Extract counts from M4 result
  mycoparasite_counts <- m4_result$mycoparasite_counts
  pathogen_counts <- m4_result$pathogen_counts

  total_unique_mycoparasites <- length(mycoparasite_counts)
  total_unique_pathogens <- length(pathogen_counts)

  # Calculate general mycoparasite count (sum of all mycoparasite counts)
  general_mycoparasite_count <- sum(unlist(mycoparasite_counts))

  if (total_unique_mycoparasites == 0) {
    return(NULL)
  }

  # Build plant ID → name mapping
  plant_names <- setNames(
    guild_plants$wfo_scientific_name,
    guild_plants$wfo_taxon_id
  )

  # Get top mycoparasites by connectivity (visiting 2+ plants)
  top_mycoparasites <- get_top_mycoparasites(
    mycoparasite_counts,
    plant_names,
    fungi_df,
    n_plants,
    limit = 10
  )

  # Build filter sets from M4 result counts (these are already filtered agents)
  known_mycoparasites <- names(mycoparasite_counts)

  # Find hub plants (using filtered mycoparasite set)
  hub_plants <- find_pathogen_control_hubs(
    guild_plants,
    fungi_df,
    known_mycoparasites
  )

  # Return pathogen control network profile
  list(
    total_unique_mycoparasites = total_unique_mycoparasites,
    total_unique_pathogens = total_unique_pathogens,
    specific_antagonist_matches = m4_result$specific_antagonist_matches,
    general_mycoparasite_count = general_mycoparasite_count,
    matched_antagonist_pairs = m4_result$matched_antagonist_pairs,
    top_mycoparasites = top_mycoparasites,
    hub_plants = hub_plants
  )
}


#' Get top mycoparasites by connectivity
#'
#' Returns mycoparasites that visit 2+ plants, sorted by plant_count descending.
#'
#' @param mycoparasite_counts Named list of mycoparasite → plant_count
#' @param plant_names Named vector of plant_id → scientific_name
#' @param fungi_df Data frame with fungal associations
#' @param n_plants Total number of plants in guild
#' @param limit Maximum number of agents to return
#'
#' @return Data frame with columns: mycoparasite_name, plant_count, plants, network_contribution
#'
get_top_mycoparasites <- function(mycoparasite_counts,
                                  plant_names,
                                  fungi_df,
                                  n_plants,
                                  limit = 10) {

  if (length(mycoparasite_counts) == 0) {
    return(data.frame(
      mycoparasite_name = character(),
      plant_count = integer(),
      plants = character(),
      network_contribution = numeric()
    ))
  }

  # Build mycoparasite → [plant_ids] mapping from DataFrame
  myco_to_plants <- build_mycoparasite_to_plants_map(fungi_df)

  # Build result data frame
  result <- data.frame(
    mycoparasite_name = character(),
    plant_count = integer(),
    plants = character(),
    network_contribution = numeric(),
    stringsAsFactors = FALSE
  )

  for (myco_name in names(mycoparasite_counts)) {
    count <- mycoparasite_counts[[myco_name]]

    # Only show mycoparasites visiting 2+ plants
    if (count < 2) {
      next
    }

    plant_ids <- myco_to_plants[[myco_name]]
    if (is.null(plant_ids)) {
      plant_ids <- character()
    }

    # Map plant IDs to names and limit to first 5
    plant_names_list <- sapply(plant_ids, function(id) plant_names[[id]])
    plant_names_list <- plant_names_list[!is.na(plant_names_list)]
    plants_str <- paste(head(plant_names_list, 5), collapse = ", ")

    result <- rbind(result, data.frame(
      mycoparasite_name = myco_name,
      plant_count = count,
      plants = plants_str,
      network_contribution = count / n_plants,
      stringsAsFactors = FALSE
    ))
  }

  # Sort by plant_count descending, then mycoparasite_name ascending
  if (nrow(result) > 0) {
    result <- result[order(-result$plant_count, result$mycoparasite_name), ]
    result <- head(result, limit)
  }

  result
}


#' Build mycoparasite_fungi → [plant_ids] mapping from fungi DataFrame
#'
#' @param fungi_df Data frame with fungal associations
#' @return Named list mapping mycoparasite_name → vector of plant_ids
#'
build_mycoparasite_to_plants_map <- function(fungi_df) {
  map <- list()

  for (i in seq_len(nrow(fungi_df))) {
    row <- fungi_df[i, ]
    plant_id <- row$plant_wfo_id

    mycos <- row$mycoparasite_fungi
    if (is.list(mycos)) mycos <- mycos[[1]]

    if (!is.null(mycos) && length(mycos) > 0) {
      for (myco in mycos) {
        if (is.null(map[[myco]])) {
          map[[myco]] <- character()
        }
        map[[myco]] <- c(map[[myco]], plant_id)
      }
    }
  }

  # Deduplicate plant lists
  for (agent in names(map)) {
    map[[agent]] <- unique(map[[agent]])
  }

  map
}


#' Find plants that are pathogen control hubs (harbor most mycoparasites)
#'
#' @param guild_plants Data frame with guild plant data
#' @param fungi_df Data frame with fungal associations
#' @param known_mycoparasites Character vector of known mycoparasite names
#'
#' @return Data frame with columns: plant_name, mycoparasites, pathogens
#'
find_pathogen_control_hubs <- function(guild_plants,
                                       fungi_df,
                                       known_mycoparasites) {

  result <- data.frame(
    plant_name = character(),
    mycoparasites = integer(),
    pathogens = integer(),
    stringsAsFactors = FALSE
  )

  for (i in seq_len(nrow(guild_plants))) {
    plant_id <- guild_plants$wfo_taxon_id[i]
    plant_name <- guild_plants$wfo_scientific_name[i]

    # Count mycoparasites for this plant (filtered to known mycoparasites only)
    total_mycoparasites <- count_mycoparasites_for_plant(
      fungi_df,
      plant_id,
      known_mycoparasites
    )

    # Count pathogens for this plant
    total_pathogens <- count_pathogens_for_plant(
      fungi_df,
      plant_id
    )

    # Only include plants with mycoparasites OR pathogens
    if (total_mycoparasites > 0 || total_pathogens > 0) {
      result <- rbind(result, data.frame(
        plant_name = plant_name,
        mycoparasites = total_mycoparasites,
        pathogens = total_pathogens,
        stringsAsFactors = FALSE
      ))
    }
  }

  # Sort by mycoparasites descending (primary), then pathogens descending, then plant_name ascending
  if (nrow(result) > 0) {
    result <- result[order(-result$mycoparasites, -result$pathogens, result$plant_name), ]
    result <- head(result, 10)
  }

  result
}


#' Count mycoparasites for a specific plant (filtered to known mycoparasites only)
#'
#' @param fungi_df Data frame with fungal associations
#' @param target_plant_id String: plant WFO ID
#' @param known_mycoparasites Character vector of known mycoparasite names
#'
#' @return Integer count of unique mycoparasites
#'
count_mycoparasites_for_plant <- function(fungi_df,
                                          target_plant_id,
                                          known_mycoparasites) {

  for (i in seq_len(nrow(fungi_df))) {
    row <- fungi_df[i, ]
    plant_id <- row$plant_wfo_id

    if (plant_id == target_plant_id) {
      mycos <- row$mycoparasite_fungi
      if (is.list(mycos)) mycos <- mycos[[1]]

      if (!is.null(mycos) && length(mycos) > 0) {
        # ONLY count fungi that are known mycoparasites from lookup table
        count <- sum(mycos %in% known_mycoparasites)
        return(count)
      }
      return(0)
    }
  }

  0
}


#' Count pathogens for a specific plant
#'
#' @param fungi_df Data frame with fungal associations
#' @param target_plant_id String: plant WFO ID
#'
#' @return Integer count of unique pathogens
#'
count_pathogens_for_plant <- function(fungi_df,
                                      target_plant_id) {

  for (i in seq_len(nrow(fungi_df))) {
    row <- fungi_df[i, ]
    plant_id <- row$plant_wfo_id

    if (plant_id == target_plant_id) {
      pathogens <- row$pathogenic_fungi
      if (is.list(pathogens)) pathogens <- pathogens[[1]]

      if (!is.null(pathogens) && length(pathogens) > 0) {
        return(length(pathogens))
      }
      return(0)
    }
  }

  0
}

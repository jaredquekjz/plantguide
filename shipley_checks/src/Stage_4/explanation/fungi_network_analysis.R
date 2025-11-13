#!/usr/bin/env Rscript
#
# FUNGI NETWORK ANALYSIS FOR M5 (BENEFICIAL FUNGI)
#
# Provides detailed breakdown of beneficial fungi networks showing:
# - Fungal diversity by category (AMF, EMF, endophytic, saprotrophic)
# - Top network fungi ranked by connectivity
# - Plant fungal hubs ranked by total associations
#
# This module provides qualitative information about fungal networks
# that supplement M5 scoring.
#
# Rust reference: src/explanation/fungi_network_analysis.rs

#' Analyze fungi network for a guild
#'
#' Takes M5Result with fungi_counts and guild DataFrames to build detailed profile.
#'
#' @param m5_result List returned from calculate_m5_beneficial_fungi containing:
#'   - fungi_counts: named list of fungus → plant_count
#'   - fungus_category_map: named list of fungus → category string
#' @param guild_plants Data frame with guild plant data
#' @param fungi_df Data frame with fungal associations
#'
#' @return List with fungi network profile, or NULL if no fungi
#'
analyze_fungi_network <- function(m5_result,
                                  guild_plants,
                                  fungi_df) {

  n_plants <- nrow(guild_plants)

  fungi_counts <- m5_result$fungi_counts
  fungus_category_map <- m5_result$fungus_category_map

  if (length(fungi_counts) == 0) {
    return(NULL)
  }

  # Build plant ID → name mapping
  plant_names <- setNames(
    guild_plants$wfo_scientific_name,
    guild_plants$wfo_taxon_id
  )

  # Build fungus_to_plants mapping by inverting fungi_counts
  fungus_to_plants <- build_fungus_to_plants_mapping(
    fungi_df,
    guild_plants,
    fungus_category_map
  )

  # Build shared fungi list (2+ plants)
  shared_fungi <- data.frame(
    fungus_name = character(),
    plant_count = integer(),
    plants = character(),
    category = character(),
    network_contribution = numeric(),
    stringsAsFactors = FALSE
  )

  for (fungus_name in names(fungus_to_plants)) {
    entry <- fungus_to_plants[[fungus_name]]
    plants <- entry$plants
    category <- entry$category

    if (length(plants) >= 2) {
      # Map plant IDs to names
      plant_names_list <- sapply(plants, function(id) plant_names[[id]])
      plant_names_list <- plant_names_list[!is.na(plant_names_list)]
      plants_str <- paste(plant_names_list, collapse = ", ")

      shared_fungi <- rbind(shared_fungi, data.frame(
        fungus_name = fungus_name,
        plant_count = length(plants),
        plants = plants_str,
        category = category,
        network_contribution = length(plants) / n_plants,
        stringsAsFactors = FALSE
      ))
    }
  }

  # Sort by network_contribution desc, then fungus_name asc
  if (nrow(shared_fungi) > 0) {
    shared_fungi <- shared_fungi[order(-shared_fungi$network_contribution, shared_fungi$fungus_name), ]
  }

  # Build top 10 fungi list
  top_fungi <- data.frame(
    fungus_name = character(),
    plant_count = integer(),
    plants = character(),
    category = character(),
    network_contribution = numeric(),
    stringsAsFactors = FALSE
  )

  for (fungus_name in names(fungus_to_plants)) {
    entry <- fungus_to_plants[[fungus_name]]
    plants <- entry$plants
    category <- entry$category

    # Map plant IDs to names and limit to first 5
    plant_names_list <- sapply(plants, function(id) plant_names[[id]])
    plant_names_list <- plant_names_list[!is.na(plant_names_list)]
    plants_str <- paste(head(plant_names_list, 5), collapse = ", ")

    top_fungi <- rbind(top_fungi, data.frame(
      fungus_name = fungus_name,
      plant_count = length(plants),
      plants = plants_str,
      category = category,
      network_contribution = length(plants) / n_plants,
      stringsAsFactors = FALSE
    ))
  }

  # Sort by network_contribution desc, then fungus_name asc
  if (nrow(top_fungi) > 0) {
    top_fungi <- top_fungi[order(-top_fungi$network_contribution, top_fungi$fungus_name), ]
    top_fungi <- head(top_fungi, 10)
  }

  # Count fungi by category
  amf_count <- sum(fungus_category_map == "AMF")
  emf_count <- sum(fungus_category_map == "EMF")
  endophytic_count <- sum(fungus_category_map == "Endophytic")
  saprotrophic_count <- sum(fungus_category_map == "Saprotrophic")

  # Find top fungus per category
  top_per_category <- data.frame(
    category = character(),
    fungus_name = character(),
    plant_count = integer(),
    stringsAsFactors = FALSE
  )

  for (cat in c("AMF", "EMF", "Endophytic", "Saprotrophic")) {
    # Filter to fungi in this category
    cat_fungi <- names(fungus_category_map)[fungus_category_map == cat]

    if (length(cat_fungi) > 0) {
      # Find the one with most plants
      max_count <- 0
      max_fungus <- ""

      for (fungus_name in cat_fungi) {
        entry <- fungus_to_plants[[fungus_name]]
        if (!is.null(entry)) {
          count <- length(entry$plants)
          if (count > max_count) {
            max_count <- count
            max_fungus <- fungus_name
          }
        }
      }

      if (max_fungus != "") {
        top_per_category <- rbind(top_per_category, data.frame(
          category = cat,
          fungus_name = max_fungus,
          plant_count = max_count,
          stringsAsFactors = FALSE
        ))
      }
    }
  }

  # Build plant fungal hubs
  hub_plants <- build_plant_fungal_hubs(
    guild_plants,
    fungi_df,
    fungus_category_map
  )

  # Return fungi network profile
  list(
    total_unique_fungi = length(fungus_to_plants),
    shared_fungi = shared_fungi,
    top_fungi = top_fungi,
    fungi_by_category = list(
      amf_count = amf_count,
      emf_count = emf_count,
      endophytic_count = endophytic_count,
      saprotrophic_count = saprotrophic_count,
      top_per_category = top_per_category
    ),
    hub_plants = hub_plants
  )
}


#' Build fungus_to_plants mapping
#'
#' @param fungi_df Data frame with fungal associations
#' @param guild_plants Data frame with guild plant data
#' @param fungus_category_map Named list of fungus → category
#'
#' @return Named list mapping fungus_name → list(plants, category)
#'
build_fungus_to_plants_mapping <- function(fungi_df,
                                           guild_plants,
                                           fungus_category_map) {

  plant_ids <- guild_plants$wfo_taxon_id
  map <- list()

  for (i in seq_len(nrow(fungi_df))) {
    row <- fungi_df[i, ]
    plant_id <- row$plant_wfo_id

    # Only process plants in guild
    if (!(plant_id %in% plant_ids)) {
      next
    }

    # Process each fungal column
    columns <- list(
      list(col = "amf_fungi", category = "AMF"),
      list(col = "emf_fungi", category = "EMF"),
      list(col = "endophytic_fungi", category = "Endophytic"),
      list(col = "saprotrophic_fungi", category = "Saprotrophic")
    )

    for (col_info in columns) {
      col_val <- row[[col_info$col]]
      if (is.list(col_val)) col_val <- col_val[[1]]

      if (!is.null(col_val) && length(col_val) > 0) {
        for (fungus in col_val) {
          if (is.null(map[[fungus]])) {
            map[[fungus]] <- list(
              plants = character(),
              category = col_info$category
            )
          }
          map[[fungus]]$plants <- c(map[[fungus]]$plants, plant_id)
        }
      }
    }
  }

  # Deduplicate plant lists
  for (fungus in names(map)) {
    map[[fungus]]$plants <- unique(map[[fungus]]$plants)
  }

  map
}


#' Build plant fungal hubs
#'
#' @param guild_plants Data frame with guild plant data
#' @param fungi_df Data frame with fungal associations
#' @param fungus_category_map Named list of fungus → category
#'
#' @return Data frame with columns: plant_name, fungus_count, amf_count, emf_count, endophytic_count, saprotrophic_count
#'
build_plant_fungal_hubs <- function(guild_plants,
                                    fungi_df,
                                    fungus_category_map) {

  result <- data.frame(
    plant_name = character(),
    fungus_count = integer(),
    amf_count = integer(),
    emf_count = integer(),
    endophytic_count = integer(),
    saprotrophic_count = integer(),
    stringsAsFactors = FALSE
  )

  for (i in seq_len(nrow(guild_plants))) {
    plant_id <- guild_plants$wfo_taxon_id[i]
    plant_name <- guild_plants$wfo_scientific_name[i]

    # Find this plant in fungi_df
    fungi_row <- fungi_df[fungi_df$plant_wfo_id == plant_id, ]

    if (nrow(fungi_row) == 0) {
      next
    }

    fungi_row <- fungi_row[1, ]  # Take first row if multiple

    # Count fungi by category
    amf <- fungi_row$amf_fungi
    if (is.list(amf)) amf <- amf[[1]]
    amf_count <- if (!is.null(amf)) length(amf) else 0

    emf <- fungi_row$emf_fungi
    if (is.list(emf)) emf <- emf[[1]]
    emf_count <- if (!is.null(emf)) length(emf) else 0

    endo <- fungi_row$endophytic_fungi
    if (is.list(endo)) endo <- endo[[1]]
    endophytic_count <- if (!is.null(endo)) length(endo) else 0

    sapro <- fungi_row$saprotrophic_fungi
    if (is.list(sapro)) sapro <- sapro[[1]]
    saprotrophic_count <- if (!is.null(sapro)) length(sapro) else 0

    fungus_count <- amf_count + emf_count + endophytic_count + saprotrophic_count

    if (fungus_count > 0) {
      result <- rbind(result, data.frame(
        plant_name = plant_name,
        fungus_count = fungus_count,
        amf_count = amf_count,
        emf_count = emf_count,
        endophytic_count = endophytic_count,
        saprotrophic_count = saprotrophic_count,
        stringsAsFactors = FALSE
      ))
    }
  }

  # Sort by fungus_count descending, then plant_name ascending
  if (nrow(result) > 0) {
    result <- result[order(-result$fungus_count, result$plant_name), ]
    result <- head(result, 10)
  }

  result
}

#!/usr/bin/env Rscript
#
# SHARED ORGANISM COUNTER UTILITY
#
# ============================================================================
# PURPOSE
# ============================================================================
#
# Counts how many plants in a guild share each organism (pollinator, fungus, etc.).
# Used by:
# - M5 (Beneficial Fungi): Count plants sharing mycorrhizal fungi
# - M7 (Pollinator Support): Count plants sharing pollinators
#
# KEY CONCEPT: Network Connectivity
# An organism shared by multiple plants creates ecological networks:
# - Common Mycorrhizal Networks (CMNs) for fungi
# - Pollinator visitation networks for flower visitors
# - Higher sharing = stronger network effects
#
# ============================================================================
# ALGORITHM
# ============================================================================
#
# Given:
# - Guild with plant IDs: ['plant_A', 'plant_B', 'plant_C']
# - Organism data:
#   * plant_A: pollinators = ['bee_1', 'bee_2', 'butterfly_1']
#   * plant_B: pollinators = ['bee_1', 'fly_1']
#   * plant_C: pollinators = ['bee_1', 'butterfly_1', 'fly_2']
#
# Process:
# 1. Filter organism_df to guild members
# 2. For each plant, extract organisms from specified columns
#    (e.g., 'pollinators', 'flower_visitors')
# 3. Build count dict:
#    * bee_1: 3 plants (A, B, C)
#    * butterfly_1: 2 plants (A, C)
#    * bee_2: 1 plant (A)
#    * fly_1: 1 plant (B)
#    * fly_2: 1 plant (C)
#
# Return: Named list with organism → count mapping
#
# ============================================================================
# FILTERING
# ============================================================================
#
# Only organisms shared by ≥2 plants contribute to network metrics.
# Single-plant organisms are excluded during scoring, not during counting.
#
# ============================================================================
# PARITY REQUIREMENTS
# ============================================================================
#
# To maintain 100% parity with Python scorer:
# 1. Must handle list-type columns correctly (R list-columns)
# 2. Must aggregate organisms across multiple columns
# 3. Must deduplicate organisms within each plant
# 4. Must handle NA/empty values correctly
#
# Python implementation: guild_scorer_v3.py lines 1713-1764 (_count_shared_organisms)
#
# ============================================================================


#' Count organisms shared across plants in a guild
#'
#' For each organism, counts how many plants in the guild host/associate with it.
#' Aggregates organisms across multiple columns (e.g., pollinators + flower_visitors).
#'
#' @param df Data frame with organism data (organisms_df or fungi_df)
#' @param plant_ids Character vector of WFO taxon IDs for the guild
#' @param ... Column names to aggregate organisms from
#'
#' @return Named list mapping organism ID → plant count
#'
#' @details
#' Handles R list-columns where organisms are stored as character vectors.
#' Deduplicates organisms within each plant before counting.
#' Filters out NA and empty string values.
#'
#' @examples
#' # Count shared pollinators
#' shared_polls <- count_shared_organisms(
#'   organisms_df, guild_ids,
#'   'pollinators', 'flower_visitors'
#' )
#'
#' # Count shared beneficial fungi
#' shared_fungi <- count_shared_organisms(
#'   fungi_df, guild_ids,
#'   'amf_fungi', 'emf_fungi', 'endophytic_fungi'
#' )
#'
count_shared_organisms <- function(df, plant_ids, ...) {
  columns <- c(...)
  organism_counts <- list()

  guild_df <- df %>% dplyr::filter(plant_wfo_id %in% plant_ids)

  if (nrow(guild_df) == 0) {
    return(organism_counts)
  }

  # For each plant in the guild
  for (i in seq_len(nrow(guild_df))) {
    row <- guild_df[i, ]
    plant_organisms <- c()

    # Aggregate organisms from all specified columns
    for (col in columns) {
      col_val <- row[[col]]

      # Handle list-column format (R stores pipe-separated strings as lists after csv_to_lists)
      if (is.list(col_val)) col_val <- col_val[[1]]

      # Skip if NA or empty
      if (!is.null(col_val) && length(col_val) > 0 && !all(is.na(col_val))) {
        plant_organisms <- c(plant_organisms, col_val)
      }
    }

    # Deduplicate organisms for this plant
    plant_organisms <- unique(plant_organisms[!is.na(plant_organisms)])

    # Count each organism
    if (length(plant_organisms) > 0) {
      for (org in plant_organisms) {
        # Filter out empty strings and ensure valid organism ID
        if (!is.null(org) && !is.na(org) && nzchar(as.character(org))) {
          org_key <- as.character(org)
          if (is.null(organism_counts[[org_key]])) {
            organism_counts[[org_key]] <- 0
          }
          organism_counts[[org_key]] <- organism_counts[[org_key]] + 1
        }
      }
    }
  }

  organism_counts
}

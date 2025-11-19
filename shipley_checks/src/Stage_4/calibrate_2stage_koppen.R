#!/usr/bin/env Rscript
#
# 2-Stage Köppen-Stratified Calibration Script (R Implementation)
#
# Stage 1: 2-Plant Pairs (20K per tier × 6 tiers = 120K pairs)
# Stage 2: 7-Plant Guilds (20K per tier × 6 tiers = 120K guilds)
#
# Based on Document 4.2c: 7-Metric Framework (2025-11-05)
# - N1 (Pathogen Fungi) and N2 (Herbivore Overlap) REMOVED
# - P4 (Phylogenetic Diversity) → M1 (Pathogen & Pest Independence)
# - M1 applies exponential transformation: exp(-3.0 × distance)
#
# Dual verification against Python baseline implementation.
#

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(jsonlite)
  library(R6)
})

# Source canonical guild scorer (contains all 7 metric calculation methods)
source("shipley_checks/src/Stage_4/guild_scorer_v3_shipley.R")

# Köppen tier structure
TIERS <- list(
  tier_1_tropical = c('Af', 'Am', 'As', 'Aw'),
  tier_2_mediterranean = c('Csa', 'Csb', 'Csc'),
  tier_3_humid_temperate = c('Cfa', 'Cfb', 'Cfc', 'Cwa', 'Cwb', 'Cwc'),
  tier_4_continental = c('Dfa', 'Dfb', 'Dfc', 'Dfd', 'Dwa', 'Dwb', 'Dwc', 'Dwd', 'Dsa', 'Dsb', 'Dsc', 'Dsd'),
  tier_5_boreal_polar = c('ET', 'EF'),
  tier_6_arid = c('BWh', 'BWk', 'BSh', 'BSk')
)

COMPONENTS <- c('m1', 'n4', 'p1', 'p2', 'p3', 'p5', 'p6')
PERCENTILES <- c(1, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99)


#' Load all necessary datasets and initialize canonical GuildScorer
#'
#' @return List with guild_scorer instance and plant organization
load_all_data <- function() {
  cat("\nLoading datasets and initializing GuildScorer...\n")

  # Plants with Köppen tiers (SHIPLEY_CHECKS DATASET - 11,711 plants)
  plants_df <- read_parquet('shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet') %>%
    select(
      wfo_taxon_id, wfo_scientific_name, family, genus,
      height_m, try_growth_form,
      CSR_C = C, CSR_S = S, CSR_R = R,
      light_pref = `EIVEres-L`,
      tier_1_tropical, tier_2_mediterranean, tier_3_humid_temperate,
      tier_4_continental, tier_5_boreal_polar, tier_6_arid,
      starts_with("phylo_ev")
    ) %>%
    filter(!is.na(phylo_ev1))

  # Organisms (SHIPLEY_CHECKS DATASET) - Include predator columns for M3
  # Phase 0-4 canonical output location (validation/, not legacy stage4/)
  organisms_path <- 'shipley_checks/phase0_output/organism_profiles_11711.parquet'
  if (file.exists(organisms_path)) {
    organisms_df <- read_parquet(organisms_path) %>%
      select(plant_wfo_id, herbivores, flower_visitors, pollinators,
             predators_hasHost, predators_interactsWith, predators_adjacentTo,
             fungivores_eats)  # For M4 disease control mechanism 3
  } else {
    organisms_df <- tibble()
  }

  # Fungi (SHIPLEY_CHECKS DATASET) - Include all fungal guilds for M3/M4/M5
  # Phase 0-4 canonical output location (validation/, not legacy stage4/)
  fungi_path <- 'shipley_checks/phase0_output/fungal_guilds_hybrid_11711.parquet'
  if (file.exists(fungi_path)) {
    fungi_df <- read_parquet(fungi_path) %>%
      select(plant_wfo_id, pathogenic_fungi, pathogenic_fungi_host_specific,
             amf_fungi, emf_fungi, endophytic_fungi, saprotrophic_fungi,
             entomopathogenic_fungi, mycoparasite_fungi)
  } else {
    fungi_df <- tibble()
  }

  # Load lookup tables for M3/M4
  # Phase 0-4 canonical output location (validation/, not legacy stage4/)
  herbivore_predators_path <- 'shipley_checks/phase0_output/herbivore_predators_11711.parquet'
  herbivore_predators <- if (file.exists(herbivore_predators_path)) {
    df <- read_parquet(herbivore_predators_path)
    setNames(df$predators, df$herbivore)
  } else {
    list()
  }

  insect_parasites_path <- 'shipley_checks/phase0_output/insect_fungal_parasites_11711.parquet'
  insect_parasites <- if (file.exists(insect_parasites_path)) {
    df <- read_parquet(insect_parasites_path)
    setNames(df$entomopathogenic_fungi, df$herbivore)
  } else {
    list()
  }

  pathogen_antagonists_path <- 'shipley_checks/phase0_output/pathogen_antagonists_11711.parquet'
  pathogen_antagonists <- if (file.exists(pathogen_antagonists_path)) {
    df <- read_parquet(pathogen_antagonists_path)
    setNames(df$antagonists, df$pathogen)
  } else {
    list()
  }

  cat(sprintf("  Plants: %s\n", format(nrow(plants_df), big.mark = ",")))
  cat(sprintf("  Organisms: %s\n", format(nrow(organisms_df), big.mark = ",")))
  cat(sprintf("  Fungi: %s\n", format(nrow(fungi_df), big.mark = ",")))
  cat(sprintf("  Herbivore predators: %s\n", format(length(herbivore_predators), big.mark = ",")))
  cat(sprintf("  Insect parasites: %s\n", format(length(insect_parasites), big.mark = ",")))
  cat(sprintf("  Pathogen antagonists: %s\n", format(length(pathogen_antagonists), big.mark = ",")))

  # Initialize canonical GuildScorer (uses same metric logic as production scorer)
  cat("\nInitializing GuildScorer...\n")
  guild_scorer <- GuildScorerV3Shipley$new(
    calibration_type = '2plant',  # Dummy - not used in calibration mode
    climate_tier = "tier_3_humid_temperate"  # Dummy - not used in calibration mode
  )

  # Set data fields (GuildScorer stores these as public fields)
  guild_scorer$plants_df <- plants_df
  guild_scorer$organisms_df <- organisms_df
  guild_scorer$fungi_df <- fungi_df
  guild_scorer$herbivore_predators <- herbivore_predators
  guild_scorer$insect_parasites <- insect_parasites
  guild_scorer$pathogen_antagonists <- pathogen_antagonists

  cat("✓ GuildScorer initialized\n")

  list(
    guild_scorer = guild_scorer,
    plants_df = plants_df
  )
}


#' Organize plant IDs by Köppen tier
#'
#' @param plants_df Plant dataset
#' @return Named list of plant IDs per tier
organize_by_tier <- function(plants_df) {
  tier_plants <- list()

  for (tier_name in names(TIERS)) {
    tier_mask <- plants_df[[tier_name]] == TRUE
    tier_ids <- plants_df$wfo_taxon_id[tier_mask]
    tier_plants[[tier_name]] <- tier_ids
    cat(sprintf("  %-30s: %5s plants\n", tier_name, format(length(tier_ids), big.mark = ",")))
  }

  tier_plants
}


#' Count organisms shared across plants
#'
#' @param df DataFrame (organisms or fungi)
#' @param plant_ids Vector of plant WFO IDs
#' @param ... Column names to check
#' @return Named vector of organism counts
count_shared_organisms <- function(df, plant_ids, ...) {
  columns <- c(...)
  organism_counts <- list()

  guild_df <- df %>% filter(plant_wfo_id %in% plant_ids)

  if (nrow(guild_df) == 0) {
    return(organism_counts)
  }

  for (i in seq_len(nrow(guild_df))) {
    row <- guild_df[i, ]
    plant_organisms <- c()

    for (col in columns) {
      col_val <- row[[col]]
      # Check if column value is list and not NULL/NA
      if (is.list(col_val)) {
        col_val <- col_val[[1]]  # Extract from list wrapper
      }
      if (!is.null(col_val) && length(col_val) > 0 && !all(is.na(col_val))) {
        plant_organisms <- c(plant_organisms, col_val)
      }
    }

    # Remove NA and ensure unique
    plant_organisms <- unique(plant_organisms[!is.na(plant_organisms)])

    if (length(plant_organisms) > 0) {
      for (org in plant_organisms) {
        # Ensure org is valid (not NULL, not NA, not empty string)
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


#' Compute raw component scores for a guild using canonical GuildScorer methods
#'
#' @param guild_ids Vector of plant WFO IDs
#' @param guild_scorer GuildScorer R6 instance (canonical implementation)
#' @param plants_df Plant dataset (for filtering guild_plants)
#' @return Named list of scores (m1, n4, p1-p6) or NULL if missing data
compute_raw_scores <- function(guild_ids, guild_scorer, plants_df) {
  n_plants <- length(guild_ids)
  guild_plants <- plants_df %>% filter(wfo_taxon_id %in% guild_ids)

  if (nrow(guild_plants) != n_plants) {
    return(NULL)  # Missing data
  }

  # Call canonical GuildScorer methods (exact same logic as production scorer)
  # Extract raw scores from each metric result

  m1_result <- guild_scorer$calculate_m1(guild_ids, guild_plants)

  # M2 (CSR compatibility) - skip if missing CSR data
  m2_result <- tryCatch(
    guild_scorer$calculate_m2(guild_plants),
    error = function(e) {
      if (grepl("missing CSR data", e$message)) {
        return(NULL)  # Skip this guild for calibration
      }
      stop(e)  # Re-throw other errors
    }
  )
  if (is.null(m2_result)) {
    return(NULL)  # Skip guild with missing CSR data
  }

  m3_result <- guild_scorer$calculate_m3(guild_ids, guild_plants)
  m4_result <- guild_scorer$calculate_m4(guild_ids, guild_plants)
  m5_result <- guild_scorer$calculate_m5(guild_ids, guild_plants)
  m6_result <- guild_scorer$calculate_m6(guild_plants)
  m7_result <- guild_scorer$calculate_m7(guild_ids, guild_plants)

  # Return raw scores (used for calibration percentile computation)
  list(
    m1 = m1_result$raw,     # Pest & pathogen independence (Faith's PD)
    n4 = m2_result$raw,     # Growth compatibility (CSR conflicts)
    p1 = m3_result$raw,     # Biocontrol (insect predators/fungi)
    p2 = m4_result$raw,     # Disease suppression (antagonist fungi)
    p3 = m5_result$raw,     # Beneficial fungi networks
    p5 = m6_result$raw,     # Structural diversity
    p6 = m7_result$raw      # Pollinator support
  )
}


#' Run calibration for one stage
#'
#' @param tier_plants Named list of plant IDs per tier
#' @param guild_scorer GuildScorer R6 instance with canonical metric methods
#' @param plants_df Plant dataset
#' @param guild_size Number of plants per guild
#' @param n_guilds_per_tier Number of guilds to sample per tier
#' @param stage_name Stage description
#' @return Named list of calibration results
calibrate_stage <- function(tier_plants, guild_scorer, plants_df,
                            guild_size, n_guilds_per_tier, stage_name) {
  cat("\n================================================================================\n")
  cat(sprintf("STAGE: %s\n", stage_name))
  cat("================================================================================\n")
  cat(sprintf("Guild size: %d plants\n", guild_size))
  cat(sprintf("Guilds per tier: %s\n", format(n_guilds_per_tier, big.mark = ",")))

  calibration_results <- list()

  for (tier_name in names(tier_plants)) {
    plant_ids <- tier_plants[[tier_name]]
    cat(sprintf("\n%s:\n", tier_name))
    cat(sprintf("  Plant pool: %s\n", format(length(plant_ids), big.mark = ",")))

    # Initialize storage for raw scores
    tier_raw_scores <- list()
    for (comp in COMPONENTS) {
      tier_raw_scores[[comp]] <- numeric(0)
    }

    successful <- 0
    attempts <- 0
    max_attempts <- n_guilds_per_tier * 100  # Safety limit

    while (successful < n_guilds_per_tier && attempts < max_attempts) {
      attempts <- attempts + 1

      # Sample guild
      guild_ids <- sample(plant_ids, size = guild_size, replace = FALSE)
      raw_scores <- compute_raw_scores(guild_ids, guild_scorer, plants_df)

      if (!is.null(raw_scores)) {
        for (comp in COMPONENTS) {
          tier_raw_scores[[comp]] <- c(tier_raw_scores[[comp]], raw_scores[[comp]])
        }
        successful <- successful + 1
      }

      # Progress indicator
      if (successful %% 10 == 0) {
        cat(sprintf("\r  Sampling: %d/%d", successful, n_guilds_per_tier))
      }
    }
    cat(sprintf("\r  Sampling: %d/%d - Complete\n", successful, n_guilds_per_tier))

    # Compute percentiles
    tier_percentiles <- list()
    for (comp in COMPONENTS) {
      values <- tier_raw_scores[[comp]]
      percentiles <- setNames(
        quantile(values, probs = PERCENTILES / 100, names = FALSE),
        sprintf("p%02d", PERCENTILES)
      )
      tier_percentiles[[comp]] <- as.list(percentiles)

      cat(sprintf("  %s: p01=%.4f, p50=%.4f, p99=%.4f\n",
                  comp, percentiles["p01"], percentiles["p50"], percentiles["p99"]))
    }

    calibration_results[[tier_name]] <- tier_percentiles
  }

  calibration_results
}


#' Main calibration function
#'
#' @param stage Which stage to run: '1', '2', or 'both'
#' @param n_guilds Number of guilds per tier (default 20000)
main <- function(stage = 'both', n_guilds = 20000) {
  # Load data and initialize canonical GuildScorer
  data <- load_all_data()
  tier_plants <- organize_by_tier(data$plants_df)

  # Stage 1: 2-plant
  if (stage %in% c('1', 'both')) {
    results <- calibrate_stage(
      tier_plants, data$guild_scorer, data$plants_df,
      2, n_guilds, 'Stage 1: 2-Plant'
    )

    output_file <- 'shipley_checks/stage4/normalization_params_2plant_R.json'
    dir.create(dirname(output_file), showWarnings = FALSE, recursive = TRUE)
    write_json(results, output_file, pretty = TRUE, auto_unbox = TRUE)
    cat(sprintf("\n✓ Saved: %s\n", output_file))
  }

  # Stage 2: 7-plant
  if (stage %in% c('2', 'both')) {
    results <- calibrate_stage(
      tier_plants, data$guild_scorer, data$plants_df,
      7, n_guilds, 'Stage 2: 7-Plant'
    )

    output_file <- 'shipley_checks/stage4/normalization_params_7plant_R.json'
    dir.create(dirname(output_file), showWarnings = FALSE, recursive = TRUE)
    write_json(results, output_file, pretty = TRUE, auto_unbox = TRUE)
    cat(sprintf("\n✓ Saved: %s\n", output_file))
  }

  cat("\n================================================================================\n")
  cat("CALIBRATION COMPLETE\n")
  cat("================================================================================\n")
}


# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
stage <- if (length(args) >= 1) args[1] else 'both'
n_guilds <- if (length(args) >= 2) as.integer(args[2]) else 20000

# Run calibration
main(stage = stage, n_guilds = n_guilds)

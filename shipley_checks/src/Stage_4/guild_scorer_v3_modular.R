#!/usr/bin/env Rscript
#
# Guild Scorer V3 (7-Metric Framework) - MODULAR IMPLEMENTATION
#
# This is a refactored version of guild_scorer_v3_shipley.R with:
# - Comprehensive inline documentation for each metric component
# - Modular architecture (metrics/, utils/ directories)
# - 100% parity with Python guild_scorer_v3.py
# - Clear separation of concerns for maintainability
#
# STRUCTURE:
# - metrics/: One file per metric (M1-M7) with detailed ecological rationale
# - utils/: Shared utilities (normalization, organism counting)
# - This file: R6 coordinator class that orchestrates scoring
#
# ============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(readr)
  library(purrr)
  library(jsonlite)
  library(R6)
  library(glue)
})

# Source Faith's PD calculator
source("shipley_checks/src/Stage_4/faiths_pd_calculator.R")

# Source utility modules
source("shipley_checks/src/Stage_4/utils/normalization.R")
source("shipley_checks/src/Stage_4/utils/shared_organism_counter.R")

# Source metric modules
source("shipley_checks/src/Stage_4/metrics/m1_pest_pathogen_indep.R")
source("shipley_checks/src/Stage_4/metrics/m2_growth_compatibility.R")
source("shipley_checks/src/Stage_4/metrics/m3_insect_control.R")
source("shipley_checks/src/Stage_4/metrics/m4_disease_control.R")
source("shipley_checks/src/Stage_4/metrics/m5_beneficial_fungi.R")
source("shipley_checks/src/Stage_4/metrics/m6_structural_diversity.R")
source("shipley_checks/src/Stage_4/metrics/m7_pollinator_support.R")


#' Guild Scorer V3 Class (Modular)
#'
#' Coordinator class that manages data loading, calibration, and metric calculation.
#' Delegates metric-specific logic to modular functions in metrics/ directory.
#'
#' @field calibration_type Character '2plant' or '7plant'
#' @field climate_tier Character Köppen tier for normalization
#' @field calibration_params List with tier-stratified percentile parameters
#' @field csr_percentiles List with global CSR percentile parameters
#' @field phylo_calculator PhyloPDCalculator R6 object
#' @field plants_df Data frame with plant metadata
#' @field organisms_df Data frame with plant-organism associations
#' @field fungi_df Data frame with plant-fungi associations
#' @field herbivore_predators Named list mapping herbivore IDs to predator IDs
#' @field insect_parasites Named list mapping herbivore IDs to fungal parasite IDs
#' @field pathogen_antagonists Named list mapping pathogen IDs to antagonist IDs
#'
GuildScorerV3Modular <- R6Class("GuildScorerV3Modular",
  public = list(
    calibration_type = NULL,
    climate_tier = NULL,
    calibration_params = NULL,
    csr_percentiles = NULL,
    phylo_calculator = NULL,
    plants_df = NULL,
    organisms_df = NULL,
    fungi_df = NULL,
    herbivore_predators = NULL,
    insect_parasites = NULL,
    pathogen_antagonists = NULL,

    #' Initialize scorer with calibration and data loading
    #'
    #' @param calibration_type Character '2plant' or '7plant'
    #' @param climate_tier Character Köppen tier (e.g., 'tier_3_humid_temperate')
    #'
    initialize = function(calibration_type = '7plant', climate_tier = 'tier_3_humid_temperate') {
      self$calibration_type <- calibration_type
      self$climate_tier <- climate_tier

      # Load calibration parameters (tier-stratified)
      cal_file <- glue("shipley_checks/stage4/normalization_params_{calibration_type}.json")
      if (!file.exists(cal_file)) {
        stop(glue("Calibration file not found: {cal_file}"))
      }
      self$calibration_params <- fromJSON(cal_file)

      # Load CSR percentile calibration (global, not tier-specific)
      csr_cal_file <- "shipley_checks/stage4/csr_percentile_calibration_global.json"
      if (file.exists(csr_cal_file)) {
        self$csr_percentiles <- fromJSON(csr_cal_file)
        cat("Loaded CSR percentile calibration (global)\n")
      } else {
        self$csr_percentiles <- NULL
        cat("CSR percentile calibration not found - using fixed thresholds for M2\n")
      }

      # Initialize Faith's PD calculator (C++ CompactTree binary)
      cat("Initializing Faith's PD calculator...\n")
      self$phylo_calculator <- PhyloPDCalculator$new()

      # Load datasets
      self$load_datasets()

      cat("\n")
      cat(glue("Guild Scorer V3 (Modular) initialized:\n"))
      cat(glue("  Calibration: {calibration_type}\n"))
      cat(glue("  Climate tier: {climate_tier}\n"))
      cat(glue("  Plants: {format(nrow(self$plants_df), big.mark=',')}\n"))
      cat("\n")
    },

    #' Load datasets from shipley_checks directory
    #'
    #' Plants: Shared parquet from stage 3
    #' Organisms/Fungi: R-generated parity-checked CSVs
    #' Lookup tables: Biocontrol, parasites, antagonists
    #'
    load_datasets = function() {
      cat("Loading datasets (R-generated Parquet files for independence)...\n")

      # Plants - from R-generated parquet
      self$plants_df <- read_parquet('shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711_r.parquet') %>%
        select(
          wfo_taxon_id, wfo_scientific_name, family, genus,
          height_m, try_growth_form,
          CSR_C = C, CSR_S = S, CSR_R = R,
          light_pref = `EIVEres-L`,
          tier_1_tropical, tier_2_mediterranean, tier_3_humid_temperate,
          tier_4_continental, tier_5_boreal_polar, tier_6_arid
        )

      # Helper function to convert pipe-separated strings back to lists
      csv_to_lists <- function(df, list_cols) {
        for (col in list_cols) {
          if (col %in% names(df)) {
            df <- df %>%
              mutate(!!col := map(.data[[col]], function(x) {
                if (is.na(x) || x == '') character(0) else strsplit(x, '\\|')[[1]]
              }))
          }
        }
        df
      }

      # Organisms - from R-generated Parquet (complete independence from Python)
      self$organisms_df <- read_parquet('shipley_checks/validation/organism_profiles_pure_r.parquet') %>%
        csv_to_lists(c('herbivores', 'flower_visitors', 'pollinators',
                       'predators_hasHost', 'predators_interactsWith', 'predators_adjacentTo'))

      # Fungi - from R-generated Parquet
      self$fungi_df <- read_parquet('shipley_checks/validation/fungal_guilds_pure_r.parquet') %>%
        csv_to_lists(c('pathogenic_fungi', 'pathogenic_fungi_host_specific',
                       'amf_fungi', 'emf_fungi', 'mycoparasite_fungi',
                       'entomopathogenic_fungi', 'endophytic_fungi', 'saprotrophic_fungi'))

      # Biocontrol lookup tables - from R-generated Parquet
      pred_df <- read_parquet('shipley_checks/validation/herbivore_predators_pure_r.parquet') %>%
        csv_to_lists('predators')
      self$herbivore_predators <- setNames(pred_df$predators, pred_df$herbivore)

      para_df <- read_parquet('shipley_checks/validation/insect_fungal_parasites_pure_r.parquet') %>%
        csv_to_lists('entomopathogenic_fungi')
      self$insect_parasites <- setNames(para_df$entomopathogenic_fungi, para_df$herbivore)

      antag_df <- read_parquet('shipley_checks/validation/pathogen_antagonists_pure_r.parquet') %>%
        csv_to_lists('antagonists')
      self$pathogen_antagonists <- setNames(antag_df$antagonists, antag_df$pathogen)

      cat(glue("  Plants: {format(nrow(self$plants_df), big.mark=',')}\n"))
      cat(glue("  Organisms: {format(nrow(self$organisms_df), big.mark=',')}\n"))
      cat(glue("  Fungi: {format(nrow(self$fungi_df), big.mark=',')}\n"))
      cat(glue("  Herbivore predators: {format(length(self$herbivore_predators), big.mark=',')}\n"))
      cat(glue("  Insect parasites: {format(length(self$insect_parasites), big.mark=',')}\n"))
      cat(glue("  Pathogen antagonists: {format(length(self$pathogen_antagonists), big.mark=',')}\n"))
    },

    #' Check climate compatibility (Köppen tier overlap)
    #'
    #' Verifies that all plants share at least one Köppen climate tier.
    #' If no overlap exists, guild is rejected with veto = TRUE.
    #'
    #' @param guild_plants Data frame of plants with tier membership columns
    #' @return List with veto status, shared_tiers, and message
    #'
    check_climate_compatibility = function(guild_plants) {
      tier_columns <- c('tier_1_tropical', 'tier_2_mediterranean', 'tier_3_humid_temperate',
                       'tier_4_continental', 'tier_5_boreal_polar', 'tier_6_arid')

      # Find which tiers each plant belongs to
      plant_tier_memberships <- list()
      for (i in seq_len(nrow(guild_plants))) {
        plant <- guild_plants[i, ]
        plant_tiers <- character(0)
        for (tier_col in tier_columns) {
          if (tier_col %in% colnames(guild_plants) && !is.na(plant[[tier_col]]) && plant[[tier_col]] == 1) {
            plant_tiers <- c(plant_tiers, tier_col)
          }
        }
        plant_tier_memberships[[i]] <- plant_tiers
      }

      # Find shared tiers (intersection of all plants' tiers)
      if (length(plant_tier_memberships) == 0) {
        return(list(
          veto = TRUE,
          message = "Plants missing Köppen tier membership data"
        ))
      }

      # Calculate intersection
      shared_tiers <- plant_tier_memberships[[1]]
      if (length(plant_tier_memberships) > 1) {
        for (i in 2:length(plant_tier_memberships)) {
          shared_tiers <- intersect(shared_tiers, plant_tier_memberships[[i]])
        }
      }

      if (length(shared_tiers) == 0) {
        # No shared tier - incompatible
        plant_names <- guild_plants$wfo_scientific_name
        tier_summary <- sapply(seq_along(plant_tier_memberships), function(i) {
          tiers <- plant_tier_memberships[[i]]
          glue("{plant_names[i]}: {paste(tiers, collapse=', ')}")
        })

        return(list(
          veto = TRUE,
          message = "Plants have no overlapping climate zones",
          details = head(tier_summary, 3)
        ))
      }

      # PASS: Plants share at least one tier
      list(
        veto = FALSE,
        shared_tiers = shared_tiers,
        message = glue("Plants share {length(shared_tiers)} Köppen tier(s): {paste(shared_tiers, collapse=', ')}")
      )
    },

    #' Score a guild of plants using all 7 metrics
    #'
    #' @param plant_ids Character vector of WFO taxon IDs
    #' @return List with overall_score, metrics, raw_scores, details, flags, metadata
    #'
    score_guild = function(plant_ids) {
      n_plants <- length(plant_ids)
      guild_plants <- self$plants_df %>% filter(wfo_taxon_id %in% plant_ids)

      if (nrow(guild_plants) != n_plants) {
        missing <- setdiff(plant_ids, guild_plants$wfo_taxon_id)
        stop(glue("Missing plant data for: {paste(missing, collapse=', ')}"))
      }

      # Check climate compatibility (Köppen tier overlap)
      climate_check <- self$check_climate_compatibility(guild_plants)
      if (climate_check$veto) {
        stop(glue("Climate incompatibility: {climate_check$message}"))
      }

      # Calculate 7 metrics using modular functions
      # Each metric module is fully documented with ecological rationale
      m1_result <- calculate_m1_pest_pathogen_indep(
        plant_ids, guild_plants,
        self$phylo_calculator,
        function(raw, metric, invert = FALSE) {
          percentile_normalize(raw, metric, self$calibration_params, self$climate_tier, invert)
        }
      )

      m2_result <- calculate_m2_growth_compatibility(
        guild_plants,
        function(raw, strategy) {
          csr_to_percentile(raw, strategy, self$csr_percentiles)
        },
        function(raw, metric, invert = FALSE) {
          percentile_normalize(raw, metric, self$calibration_params, self$climate_tier, invert)
        }
      )

      m3_result <- calculate_m3_insect_control(
        plant_ids, guild_plants,
        self$organisms_df, self$fungi_df,
        self$herbivore_predators, self$insect_parasites,
        function(raw, metric, invert = FALSE) {
          percentile_normalize(raw, metric, self$calibration_params, self$climate_tier, invert)
        }
      )

      m4_result <- calculate_m4_disease_control(
        plant_ids, guild_plants,
        self$fungi_df, self$pathogen_antagonists,
        function(raw, metric, invert = FALSE) {
          percentile_normalize(raw, metric, self$calibration_params, self$climate_tier, invert)
        }
      )

      m5_result <- calculate_m5_beneficial_fungi(
        plant_ids, guild_plants,
        self$fungi_df,
        count_shared_organisms,
        function(raw, metric, invert = FALSE) {
          percentile_normalize(raw, metric, self$calibration_params, self$climate_tier, invert)
        }
      )

      m6_result <- calculate_m6_structural_diversity(
        guild_plants,
        function(raw, metric, invert = FALSE) {
          percentile_normalize(raw, metric, self$calibration_params, self$climate_tier, invert)
        }
      )

      m7_result <- calculate_m7_pollinator_support(
        plant_ids, guild_plants,
        self$organisms_df,
        count_shared_organisms,
        function(raw, metric, invert = FALSE) {
          percentile_normalize(raw, metric, self$calibration_params, self$climate_tier, invert)
        }
      )

      # Calculate flags (nitrogen fixation, pH compatibility)
      flags <- self$calculate_flags(guild_plants)

      # Build metrics dict (7 metrics, all HIGH = GOOD)
      # M1 and M2 require final inversion (100 - norm) to match Python line 406-407
      metrics <- list(
        m1 = 100 - m1_result$norm,  # Matches Python line 406
        m2 = 100 - m2_result$norm,  # Matches Python line 407
        m3 = m3_result$norm,        # Matches Python line 408
        m4 = m4_result$norm,        # Matches Python line 409
        m5 = m5_result$norm,        # Matches Python line 410
        m6 = m6_result$norm,        # Matches Python line 411
        m7 = m7_result$norm         # Matches Python line 412
      )

      # Overall score (simple average) - matches Python line 416
      overall_score <- mean(unlist(metrics))

      # Return result
      list(
        overall_score = overall_score,
        metrics = metrics,
        raw_scores = list(
          m1 = m1_result$raw,
          m2 = m2_result$raw,
          m3 = m3_result$raw,
          m4 = m4_result$raw,
          m5 = m5_result$raw,
          m6 = m6_result$raw,
          m7 = m7_result$raw
        ),
        details = list(
          m1 = m1_result$details,
          m2 = m2_result$details,
          m3 = m3_result$details,
          m4 = m4_result$details,
          m5 = m5_result$details,
          m6 = m6_result$details,
          m7 = m7_result$details
        ),
        flags = flags,
        n_plants = n_plants,
        plant_ids = plant_ids,
        plant_names = guild_plants$wfo_scientific_name,
        climate_tier = self$climate_tier
      )
    },

    #' Calculate flags (N5: nitrogen fixation, N6: pH compatibility)
    #'
    #' @param guild_plants Data frame with plant metadata
    #' @return List with nitrogen and soil_ph flags
    #'
    calculate_flags = function(guild_plants) {
      # N5: Nitrogen fixation (check if column exists)
      if ("n_fixer" %in% colnames(guild_plants)) {
        n_fixers <- sum(!is.na(guild_plants$n_fixer) & guild_plants$n_fixer == TRUE, na.rm = TRUE)
        nitrogen_flag <- if (n_fixers > 0) glue("{n_fixers} legumes") else "None"
      } else {
        # Check family for known N-fixers (Fabaceae)
        n_fixers <- sum(guild_plants$family == "Fabaceae", na.rm = TRUE)
        nitrogen_flag <- if (n_fixers > 0) glue("{n_fixers} Fabaceae") else "None"
      }

      # N6: pH compatibility (placeholder)
      ph_flag <- "Compatible"

      list(
        nitrogen = nitrogen_flag,
        soil_ph = ph_flag
      )
    }
  )
)

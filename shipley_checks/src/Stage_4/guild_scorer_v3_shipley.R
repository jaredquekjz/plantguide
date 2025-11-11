#!/usr/bin/env Rscript
#
# Guild Scorer V3 (7-Metric Framework) - Shipley Checks Implementation
#
# This R6 class scores plant guilds using the 7-metric framework:
#   M1: Pest & Pathogen Independence (Faith's PD)
#   M2: Growth Compatibility (CSR conflicts)
#   M3: Beneficial Insect Networks (biocontrol)
#   M4: Disease Suppression (antagonist fungi)
#   M5: Beneficial Fungi Networks (mycorrhizae)
#   M6: Structural Diversity (stratification)
#   M7: Pollinator Support (shared pollinators)
#
# Uses C++ CompactTree for Faith's PD calculations (708× faster than R picante)
#

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


#' Guild Scorer V3 Class
#'
#' Scores plant guilds using Köppen-stratified calibration parameters
#'
GuildScorerV3Shipley <- R6Class("GuildScorerV3Shipley",
  public = list(
    calibration_type = NULL,
    climate_tier = NULL,
    calibration_params = NULL,
    phylo_calculator = NULL,
    plants_df = NULL,
    organisms_df = NULL,
    fungi_df = NULL,
    herbivore_predators = NULL,
    insect_parasites = NULL,
    pathogen_antagonists = NULL,

    #' Initialize scorer
    #'
    #' @param calibration_type '2plant' or '7plant'
    #' @param climate_tier Köppen tier for normalization
    initialize = function(calibration_type = '7plant', climate_tier = 'tier_3_humid_temperate') {
      self$calibration_type <- calibration_type
      self$climate_tier <- climate_tier

      # Load calibration parameters (use Python calibration for parity testing)
      cal_file <- glue("shipley_checks/stage4/normalization_params_{calibration_type}.json")
      if (!file.exists(cal_file)) {
        stop(glue("Calibration file not found: {cal_file}"))
      }
      self$calibration_params <- fromJSON(cal_file)

      # Initialize Faith's PD calculator
      cat("Initializing Faith's PD calculator...\n")
      self$phylo_calculator <- PhyloPDCalculator$new()

      # Load datasets
      self$load_datasets()

      cat("\n")
      cat(glue("Guild Scorer V3 initialized:\n"))
      cat(glue("  Calibration: {calibration_type}\n"))
      cat(glue("  Climate tier: {climate_tier}\n"))
      cat(glue("  Plants: {format(nrow(self$plants_df), big.mark=',')}\n"))
      cat("\n")
    },

    #' Load datasets
    load_datasets = function() {
      cat("Loading datasets (R-generated CSV files for independence)...\n")

      # Plants - from shared parquet (stage 3 output)
      self$plants_df <- read_parquet('shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet') %>%
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

      # Organisms - from R-generated CSV (complete independence from Python)
      self$organisms_df <- read_csv('shipley_checks/validation/organism_profiles_pure_r.csv', show_col_types = FALSE) %>%
        csv_to_lists(c('herbivores', 'flower_visitors', 'pollinators',
                       'predators_hasHost', 'predators_interactsWith', 'predators_adjacentTo'))

      # Fungi - from R-generated CSV
      self$fungi_df <- read_csv('shipley_checks/validation/fungal_guilds_pure_r.csv', show_col_types = FALSE) %>%
        csv_to_lists(c('pathogenic_fungi', 'pathogenic_fungi_host_specific',
                       'amf_fungi', 'emf_fungi', 'mycoparasite_fungi',
                       'entomopathogenic_fungi', 'endophytic_fungi', 'saprotrophic_fungi'))

      # Biocontrol lookup tables - from R-generated CSV
      pred_df <- read_csv('shipley_checks/validation/herbivore_predators_pure_r.csv', show_col_types = FALSE) %>%
        csv_to_lists('predators')
      self$herbivore_predators <- setNames(pred_df$predators, pred_df$herbivore)

      para_df <- read_csv('shipley_checks/validation/insect_fungal_parasites_pure_r.csv', show_col_types = FALSE) %>%
        csv_to_lists('entomopathogenic_fungi')
      self$insect_parasites <- setNames(para_df$entomopathogenic_fungi, para_df$herbivore)

      antag_df <- read_csv('shipley_checks/validation/pathogen_antagonists_pure_r.csv', show_col_types = FALSE) %>%
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
    #' @param guild_plants Data frame of plants with tier membership columns
    #' @return List with veto status and message
    check_climate_compatibility = function(guild_plants) {
      # All Köppen tier columns
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

    #' Score a guild of plants
    #'
    #' @param plant_ids Character vector of WFO taxon IDs
    #' @return List with scores, metrics, flags, and metadata
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

      # Calculate 7 metrics
      m1_result <- self$calculate_m1(plant_ids, guild_plants)
      m2_result <- self$calculate_m2(guild_plants)
      m3_result <- self$calculate_m3(plant_ids, guild_plants)
      m4_result <- self$calculate_m4(plant_ids, guild_plants)
      m5_result <- self$calculate_m5(plant_ids, guild_plants)
      m6_result <- self$calculate_m6(guild_plants)
      m7_result <- self$calculate_m7(plant_ids, guild_plants)

      # Calculate flags
      flags <- self$calculate_flags(guild_plants)

      # Overall score (simple average for now)
      overall_score <- mean(c(
        m1_result$norm, m2_result$norm, m3_result$norm,
        m4_result$norm, m5_result$norm, m6_result$norm, m7_result$norm
      ))

      # Return result
      list(
        overall_score = overall_score,
        metrics = list(
          m1 = m1_result$norm,
          m2 = m2_result$norm,
          m3 = m3_result$norm,
          m4 = m4_result$norm,
          m5 = m5_result$norm,
          m6 = m6_result$norm,
          m7 = m7_result$norm
        ),
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

    #' M1: Pest & Pathogen Independence (Faith's PD)
    calculate_m1 = function(plant_ids, guild_plants) {
      if (length(plant_ids) < 2) {
        return(list(
          raw = 1.0,  # Single plant = maximum risk
          norm = 0.0,
          details = list(faiths_pd = 0, note = "Single plant - no phylogenetic diversity")
        ))
      }

      # Calculate Faith's PD using C++ binary
      faiths_pd <- self$phylo_calculator$calculate_pd(plant_ids, use_wfo_ids = TRUE)

      # Apply exponential transformation
      k <- 0.001
      pest_risk_raw <- exp(-k * faiths_pd)

      # Percentile normalization (inverted - low risk = high score)
      m1_norm <- self$percentile_normalize(pest_risk_raw, 'm1', invert = TRUE)

      list(
        raw = pest_risk_raw,
        norm = m1_norm,
        details = list(
          faiths_pd = faiths_pd,
          k = k,
          formula = "exp(-k × faiths_pd)"
        )
      )
    },

    #' M2: Growth Compatibility (CSR conflicts inverted)
    calculate_m2 = function(guild_plants) {
      HIGH_C <- 60
      HIGH_S <- 60
      HIGH_R <- 50
      n_plants <- nrow(guild_plants)
      conflicts <- 0

      # C-C conflicts
      high_c <- guild_plants %>% filter(CSR_C > HIGH_C)
      if (nrow(high_c) >= 2) {
        conflicts <- conflicts + choose(nrow(high_c), 2)
      }

      # C-S conflicts
      high_s <- guild_plants %>% filter(CSR_S > HIGH_S)
      if (nrow(high_c) > 0 && nrow(high_s) > 0) {
        for (i in seq_len(nrow(high_c))) {
          for (j in seq_len(nrow(high_s))) {
            if (high_c$wfo_taxon_id[i] != high_s$wfo_taxon_id[j]) {
              s_light <- ifelse(is.na(high_s$light_pref[j]), 5.0, high_s$light_pref[j])
              conflict <- if (s_light < 3.2) 0.0 else if (s_light > 7.47) 0.9 else 0.6
              conflicts <- conflicts + conflict
            }
          }
        }
      }

      # C-R conflicts
      high_r <- guild_plants %>% filter(CSR_R > HIGH_R)
      if (nrow(high_c) > 0 && nrow(high_r) > 0) {
        for (i in seq_len(nrow(high_c))) {
          for (j in seq_len(nrow(high_r))) {
            if (high_c$wfo_taxon_id[i] != high_r$wfo_taxon_id[j]) {
              conflicts <- conflicts + 0.8
            }
          }
        }
      }

      # R-R conflicts
      if (nrow(high_r) >= 2) {
        conflicts <- conflicts + choose(nrow(high_r), 2) * 0.3
      }

      max_pairs <- if (n_plants > 1) n_plants * (n_plants - 1) else 1
      conflict_density <- conflicts / max_pairs

      # Percentile normalize (inverted - low conflicts = high score)
      m2_norm <- self$percentile_normalize(conflict_density, 'n4', invert = TRUE)

      list(
        raw = conflict_density,
        norm = m2_norm,
        details = list(
          n_conflicts = conflicts,
          conflict_density = conflict_density,
          high_c = nrow(high_c),
          high_s = nrow(high_s),
          high_r = nrow(high_r)
        )
      )
    },

    #' M3: Beneficial Insect Networks (biocontrol)
    calculate_m3 = function(plant_ids, guild_plants) {
      n_plants <- nrow(guild_plants)
      biocontrol_raw <- 0.0
      mechanisms <- list()

      # Get guild organism and fungi data
      guild_organisms <- self$organisms_df %>% filter(plant_wfo_id %in% plant_ids)
      guild_fungi <- self$fungi_df %>% filter(plant_wfo_id %in% plant_ids)

      if (nrow(guild_organisms) == 0) {
        return(list(
          raw = 0.0,
          norm = 0.0,
          details = list(note = "No organism data available")
        ))
      }

      # Pairwise analysis: vulnerable plant A vs protective plant B
      for (i in seq_len(nrow(guild_organisms))) {
        row_a <- guild_organisms[i, ]
        plant_a_id <- row_a$plant_wfo_id
        herbivores_a <- row_a$herbivores[[1]]

        if (is.null(herbivores_a) || length(herbivores_a) == 0) {
          next
        }

        for (j in seq_len(nrow(guild_organisms))) {
          if (i == j) next

          row_b <- guild_organisms[j, ]
          plant_b_id <- row_b$plant_wfo_id

          # Aggregate ALL animals from plant B across all relationship types
          predators_b <- c()
          if (!is.null(row_b$flower_visitors[[1]])) {
            predators_b <- c(predators_b, row_b$flower_visitors[[1]])
          }
          if ("predators_hasHost" %in% names(row_b) && !is.null(row_b$predators_hasHost[[1]])) {
            predators_b <- c(predators_b, row_b$predators_hasHost[[1]])
          }
          if ("predators_interactsWith" %in% names(row_b) && !is.null(row_b$predators_interactsWith[[1]])) {
            predators_b <- c(predators_b, row_b$predators_interactsWith[[1]])
          }
          if ("predators_adjacentTo" %in% names(row_b) && !is.null(row_b$predators_adjacentTo[[1]])) {
            predators_b <- c(predators_b, row_b$predators_adjacentTo[[1]])
          }
          predators_b <- unique(predators_b)

          # Mechanism 1: Specific animal predators (weight 1.0)
          for (herbivore in herbivores_a) {
            if (herbivore %in% names(self$herbivore_predators)) {
              known_predators <- self$herbivore_predators[[herbivore]]
              if (!is.null(known_predators) && length(known_predators) > 0) {
                matching <- intersect(predators_b, known_predators)
                if (length(matching) > 0) {
                  biocontrol_raw <- biocontrol_raw + length(matching) * 1.0
                  mechanisms[[length(mechanisms) + 1]] <- list(
                    type = 'animal_predator',
                    herbivore = herbivore,
                    predator_plant = plant_b_id,
                    predators = head(matching, 3)
                  )
                }
              }
            }
          }

          # Mechanism 2 & 3: Entomopathogenic fungi
          fungi_b <- guild_fungi %>% filter(plant_wfo_id == plant_b_id)
          if (nrow(fungi_b) > 0) {
            entomo_b <- fungi_b$entomopathogenic_fungi[[1]]
            if (!is.null(entomo_b) && length(entomo_b) > 0) {

              # Mechanism 2: Specific entomopathogenic fungi (weight 1.0)
              for (herbivore in herbivores_a) {
                if (herbivore %in% names(self$insect_parasites)) {
                  known_parasites <- self$insect_parasites[[herbivore]]
                  if (!is.null(known_parasites) && length(known_parasites) > 0) {
                    matching <- intersect(entomo_b, known_parasites)
                    if (length(matching) > 0) {
                      biocontrol_raw <- biocontrol_raw + length(matching) * 1.0
                      mechanisms[[length(mechanisms) + 1]] <- list(
                        type = 'fungal_parasite',
                        herbivore = herbivore,
                        fungi_plant = plant_b_id,
                        fungi = head(matching, 3)
                      )
                    }
                  }
                }
              }

              # Mechanism 3: General entomopathogenic fungi (weight 0.2)
              if (length(herbivores_a) > 0 && length(entomo_b) > 0) {
                biocontrol_raw <- biocontrol_raw + length(entomo_b) * 0.2
              }
            }
          }
        }
      }

      # Normalize by guild size
      max_pairs <- n_plants * (n_plants - 1)
      biocontrol_normalized <- if (max_pairs > 0) {
        biocontrol_raw / max_pairs * 20
      } else {
        0
      }

      # Percentile normalize
      m3_norm <- self$percentile_normalize(biocontrol_normalized, 'p1')

      list(
        raw = biocontrol_normalized,
        norm = m3_norm,
        details = list(
          biocontrol_raw = biocontrol_raw,
          max_pairs = max_pairs,
          n_mechanisms = length(mechanisms),
          mechanisms = head(mechanisms, 10)
        )
      )
    },

    #' M4: Disease Suppression (antagonist fungi)
    calculate_m4 = function(plant_ids, guild_plants) {
      n_plants <- nrow(guild_plants)
      pathogen_control_raw <- 0.0
      mechanisms <- list()

      # Get guild fungi data
      guild_fungi <- self$fungi_df %>% filter(plant_wfo_id %in% plant_ids)

      if (nrow(guild_fungi) == 0) {
        return(list(
          raw = 0.0,
          norm = 0.0,
          details = list(note = "No fungi data available")
        ))
      }

      # Pairwise analysis: vulnerable plant A vs protective plant B
      for (i in seq_len(nrow(guild_fungi))) {
        row_a <- guild_fungi[i, ]
        plant_a_id <- row_a$plant_wfo_id
        pathogens_a <- row_a$pathogenic_fungi[[1]]

        if (is.null(pathogens_a) || length(pathogens_a) == 0) {
          next
        }

        for (j in seq_len(nrow(guild_fungi))) {
          if (i == j) next

          row_b <- guild_fungi[j, ]
          plant_b_id <- row_b$plant_wfo_id
          mycoparasites_b <- row_b$mycoparasite_fungi[[1]]

          if (is.null(mycoparasites_b) || length(mycoparasites_b) == 0) {
            next
          }

          # Mechanism 1: Specific antagonist matches (weight 1.0) - RARELY FIRES
          for (pathogen in pathogens_a) {
            if (pathogen %in% names(self$pathogen_antagonists)) {
              known_antagonists <- self$pathogen_antagonists[[pathogen]]
              if (!is.null(known_antagonists) && length(known_antagonists) > 0) {
                matching <- intersect(mycoparasites_b, known_antagonists)
                if (length(matching) > 0) {
                  pathogen_control_raw <- pathogen_control_raw + length(matching) * 1.0
                  mechanisms[[length(mechanisms) + 1]] <- list(
                    type = 'specific_antagonist',
                    pathogen = pathogen,
                    control_plant = plant_b_id,
                    antagonists = head(matching, 3)
                  )
                }
              }
            }
          }

          # Mechanism 2: General mycoparasites (weight 1.0) - PRIMARY MECHANISM
          if (length(pathogens_a) > 0 && length(mycoparasites_b) > 0) {
            pathogen_control_raw <- pathogen_control_raw + length(mycoparasites_b) * 1.0
            mechanisms[[length(mechanisms) + 1]] <- list(
              type = 'general_mycoparasite',
              vulnerable_plant = plant_a_id,
              n_pathogens = length(pathogens_a),
              control_plant = plant_b_id,
              mycoparasites = head(mycoparasites_b, 5)
            )
          }
        }
      }

      # Normalize by guild size
      max_pairs <- n_plants * (n_plants - 1)
      pathogen_control_normalized <- if (max_pairs > 0) {
        pathogen_control_raw / max_pairs * 10
      } else {
        0
      }

      # Percentile normalize
      m4_norm <- self$percentile_normalize(pathogen_control_normalized, 'p2')

      list(
        raw = pathogen_control_normalized,
        norm = m4_norm,
        details = list(
          pathogen_control_raw = pathogen_control_raw,
          max_pairs = max_pairs,
          n_mechanisms = length(mechanisms),
          mechanisms = mechanisms
        )
      )
    },

    #' M5: Beneficial Fungi Networks (mycorrhizae)
    calculate_m5 = function(plant_ids, guild_plants) {
      n_plants <- nrow(guild_plants)

      # Count shared beneficial fungi
      beneficial_counts <- self$count_shared_organisms(
        self$fungi_df, plant_ids,
        'amf_fungi', 'emf_fungi', 'endophytic_fungi', 'saprotrophic_fungi'
      )

      # Network score
      network_raw <- 0
      for (org_name in names(beneficial_counts)) {
        count <- beneficial_counts[[org_name]]
        if (count >= 2) {
          network_raw <- network_raw + (count / n_plants)
        }
      }

      # Coverage ratio
      guild_fungi <- self$fungi_df %>% filter(plant_wfo_id %in% plant_ids)
      plants_with_beneficial <- 0

      if (nrow(guild_fungi) > 0) {
        for (i in seq_len(nrow(guild_fungi))) {
          row <- guild_fungi[i, ]
          has_beneficial <- FALSE
          for (col in c('amf_fungi', 'emf_fungi', 'endophytic_fungi', 'saprotrophic_fungi')) {
            col_val <- row[[col]]
            if (is.list(col_val)) col_val <- col_val[[1]]
            if (!is.null(col_val) && length(col_val) > 0 && !all(is.na(col_val))) {
              has_beneficial <- TRUE
              break
            }
          }
          if (has_beneficial) {
            plants_with_beneficial <- plants_with_beneficial + 1
          }
        }
      }

      coverage_ratio <- plants_with_beneficial / n_plants
      p5_raw <- network_raw * 0.6 + coverage_ratio * 0.4

      # Percentile normalize
      m5_norm <- self$percentile_normalize(p5_raw, 'p3')

      list(
        raw = p5_raw,
        norm = m5_norm,
        details = list(
          network_score = network_raw,
          coverage_ratio = coverage_ratio,
          n_shared_fungi = length(beneficial_counts),  # Total unique fungi
          plants_with_fungi = plants_with_beneficial
        )
      )
    },

    #' M6: Structural Diversity (stratification)
    calculate_m6 = function(guild_plants) {
      forms <- guild_plants$try_growth_form[!is.na(guild_plants$try_growth_form)]

      # COMPONENT 1: Light-validated height stratification (70%) - Python lines 1598-1631
      valid_stratification <- 0.0
      invalid_stratification <- 0.0

      if (nrow(guild_plants) >= 2) {
        # Sort by height
        sorted_guild <- guild_plants[order(guild_plants$height_m), ]

        # Analyze all tall-short pairs
        for (i in 1:(nrow(sorted_guild) - 1)) {
          for (j in (i + 1):nrow(sorted_guild)) {
            short <- sorted_guild[i, ]
            tall <- sorted_guild[j, ]

            height_diff <- tall$height_m - short$height_m

            # Only significant height differences (>2m = different canopy layers)
            if (!is.na(height_diff) && height_diff > 2.0) {
              short_light <- short$light_pref

              if (length(short_light) == 0 || is.na(short_light)) {
                # Conservative: neutral/flexible (missing data)
                valid_stratification <- valid_stratification + height_diff * 0.5
              } else if (short_light < 3.2) {
                # Shade-tolerant (EIVE-L 1-3): Can thrive under canopy
                valid_stratification <- valid_stratification + height_diff
              } else if (short_light > 7.47) {
                # Sun-loving (EIVE-L 8-9): Will be shaded out
                invalid_stratification <- invalid_stratification + height_diff
              } else {
                # Flexible (EIVE-L 4-7): Partial compatibility
                valid_stratification <- valid_stratification + height_diff * 0.6
              }
            }
          }
        }
      }

      # Stratification quality: valid / total
      total_height_diffs <- valid_stratification + invalid_stratification
      stratification_quality <- if (total_height_diffs > 0) {
        valid_stratification / total_height_diffs
      } else {
        0.0  # No vertical diversity
      }

      # COMPONENT 2: Form diversity (30%) - Python line 1635
      n_forms <- length(unique(forms))
      form_diversity <- if (n_forms > 0) (n_forms - 1) / 5 else 0  # 6 forms max

      # Combined (70% light-validated height, 30% form) - Python line 1638
      p6_raw <- 0.7 * stratification_quality + 0.3 * form_diversity

      # Percentile normalize
      m6_norm <- self$percentile_normalize(p6_raw, 'p5')

      # Calculate height range for details
      heights <- guild_plants$height_m[!is.na(guild_plants$height_m)]
      height_range <- if (length(heights) >= 2) max(heights) - min(heights) else 0

      list(
        raw = p6_raw,
        norm = m6_norm,
        details = list(
          height_range = height_range,
          n_forms = length(unique(forms)),
          forms = unique(forms),
          stratification_quality = stratification_quality,
          form_diversity = form_diversity
        )
      )
    },

    #' M7: Pollinator Support (shared pollinators)
    calculate_m7 = function(plant_ids, guild_plants) {
      n_plants <- nrow(guild_plants)

      # Count shared pollinators
      shared_pollinators <- self$count_shared_organisms(
        self$organisms_df, plant_ids,
        'pollinators', 'flower_visitors'
      )

      # Score with QUADRATIC weighting (matches Python line 1670)
      p7_raw <- 0
      for (org_name in names(shared_pollinators)) {
        count <- shared_pollinators[[org_name]]
        if (count >= 2) {
          overlap_ratio <- count / n_plants
          p7_raw <- p7_raw + overlap_ratio ^ 2  # Quadratic BENEFIT
        }
      }

      # Percentile normalize
      m7_norm <- self$percentile_normalize(p7_raw, 'p6')

      list(
        raw = p7_raw,
        norm = m7_norm,
        details = list(
          n_shared_pollinators = length(shared_pollinators),  # Total unique pollinators
          pollinators = names(shared_pollinators)[1:min(5, length(shared_pollinators))]
        )
      )
    },

    #' Calculate flags (N5, N6)
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
    },

    #' Count organisms shared across plants
    count_shared_organisms = function(df, plant_ids, ...) {
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
          if (is.list(col_val)) col_val <- col_val[[1]]
          if (!is.null(col_val) && length(col_val) > 0 && !all(is.na(col_val))) {
            plant_organisms <- c(plant_organisms, col_val)
          }
        }

        plant_organisms <- unique(plant_organisms[!is.na(plant_organisms)])

        if (length(plant_organisms) > 0) {
          for (org in plant_organisms) {
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
    },

    #' Percentile normalize a raw score using linear interpolation
    #' Matches Python guild_scorer_v3._raw_to_percentile() logic
    percentile_normalize = function(raw_value, metric_name, invert = FALSE) {
      # Get calibration percentiles for this tier and metric
      tier_params <- self$calibration_params[[self$climate_tier]]
      if (is.null(tier_params)) {
        warning(glue("No calibration params for tier: {self$climate_tier}"))
        return(50.0)
      }

      metric_params <- tier_params[[metric_name]]
      if (is.null(metric_params)) {
        warning(glue("No calibration params for metric: {metric_name}"))
        return(50.0)
      }

      # Percentiles: p1, p5, p10, ..., p99
      percentiles <- c(1, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99)
      values <- sapply(percentiles, function(p) {
        # Try both 'p1' and 'p01' formats
        val <- metric_params[[paste0('p', p)]]
        if (is.null(val)) val <- metric_params[[paste0('p', sprintf('%02d', p))]]
        if (is.null(val)) return(NA)
        return(as.numeric(val))
      })

      # Remove NAs
      valid_idx <- !is.na(values)
      percentiles <- percentiles[valid_idx]
      values <- values[valid_idx]

      if (length(values) == 0) {
        warning(glue("No valid calibration values for metric: {metric_name}"))
        return(50.0)
      }

      # Handle edge cases
      if (raw_value <= values[1]) {
        return(if (invert) 100.0 else 0.0)
      }
      if (raw_value >= values[length(values)]) {
        return(if (invert) 0.0 else 100.0)
      }

      # Find bracketing percentiles and do LINEAR INTERPOLATION
      for (i in 1:(length(values) - 1)) {
        if (values[i] <= raw_value && raw_value <= values[i + 1]) {
          # Linear interpolation between percentiles[i] and percentiles[i+1]
          if (values[i + 1] - values[i] > 0) {
            fraction <- (raw_value - values[i]) / (values[i + 1] - values[i])
            percentile <- percentiles[i] + fraction * (percentiles[i + 1] - percentiles[i])
          } else {
            percentile <- percentiles[i]
          }

          # Handle inversion (for M1, M2 where low raw = good)
          if (invert) {
            percentile <- 100.0 - percentile
          }

          return(percentile)
        }
      }

      # Fallback (should not reach here)
      return(50.0)
    }
  )
)

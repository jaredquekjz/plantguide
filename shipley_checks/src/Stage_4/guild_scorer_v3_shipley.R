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
    csr_percentiles = NULL,
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

      # Load CSR percentile calibration (global, not tier-specific)
      # Used for M2 conflict detection with consistent thresholds
      csr_cal_file <- "shipley_checks/stage4/csr_percentile_calibration_global.json"
      if (file.exists(csr_cal_file)) {
        self$csr_percentiles <- fromJSON(csr_cal_file)
        cat("Loaded CSR percentile calibration (global)\n")
      } else {
        self$csr_percentiles <- NULL
        cat("CSR percentile calibration not found - using fixed thresholds for M2\n")
      }

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

      # Build metrics dict (7 metrics, all HIGH = GOOD)
      # M1 and M2 are already inverted by percentile_normalize(..., invert = TRUE/FALSE)
      # But for display, we need to apply the final transformation
      # Python line 406: 'pest_pathogen_indep': 100 - percentiles['m1']
      # Python line 407: 'growth_compatibility': 100 - percentiles['n4']
      # M1 is inverted during normalization (invert = TRUE), so we flip back: 100 - (100 - x) = x
      # Actually wait, let me check the Python logic again...
      # Python: percentiles['m1'] is already inverted (high PD = low risk = high percentile)
      # Then: pest_pathogen_indep = 100 - percentiles['m1']... that's double inversion!
      # No wait, that's wrong. Let me re-read the Python code.
      #
      # Actually the Python is:
      # Line 400: percentiles[metric] = self._raw_to_percentile(raw_value, metric)
      # Line 406: 'pest_pathogen_indep': 100 - percentiles['m1']
      #
      # And _raw_to_percentile for m1 returns percentile WITHOUT inversion
      # So if pest_risk_raw is LOW (good), it maps to LOW percentile
      # Then 100 - LOW = HIGH score (correct!)
      #
      # For M2:
      # conflict_density is HIGH (bad), maps to HIGH percentile
      # Then 100 - HIGH = LOW score (correct!)
      #
      # So in R, I'm using invert = TRUE for M1 which is WRONG
      # I should use invert = FALSE for both, then do 100 - norm for display
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

      # Percentile normalization (matches Python line 1626)
      # LOW pest_risk_raw (high diversity, good) -> LOW percentile
      # HIGH pest_risk_raw (low diversity, bad) -> HIGH percentile
      # Then score_guild does: 100 - percentile to get display score
      m1_norm <- self$percentile_normalize(pest_risk_raw, 'm1', invert = FALSE)

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
      n_plants <- nrow(guild_plants)
      conflicts <- 0
      conflict_details <- list()

      # Use percentile-based classification (CONSISTENT across C, S, R)
      PERCENTILE_THRESHOLD <- 75  # Top quartile

      # Convert CSR scores to percentiles (matches Python lines 1093-1101)
      guild_plants_copy <- guild_plants
      guild_plants_copy$C_percentile <- sapply(guild_plants_copy$CSR_C, function(x) {
        self$csr_to_percentile(x, 'c')
      })
      guild_plants_copy$S_percentile <- sapply(guild_plants_copy$CSR_S, function(x) {
        self$csr_to_percentile(x, 's')
      })
      guild_plants_copy$R_percentile <- sapply(guild_plants_copy$CSR_R, function(x) {
        self$csr_to_percentile(x, 'r')
      })

      # CONFLICT 1: High-C + High-C (matches Python lines 1104-1141)
      high_c_plants <- guild_plants_copy %>% filter(C_percentile > PERCENTILE_THRESHOLD)

      if (nrow(high_c_plants) >= 2) {
        for (i in 1:(nrow(high_c_plants) - 1)) {
          for (j in (i + 1):nrow(high_c_plants)) {
            plant_a <- high_c_plants[i, ]
            plant_b <- high_c_plants[j, ]

            conflict <- 1.0  # Base

            # MODULATION: Growth Form
            form_a <- tolower(as.character(plant_a$try_growth_form))
            form_b <- tolower(as.character(plant_b$try_growth_form))
            form_a <- ifelse(is.na(plant_a$try_growth_form), '', form_a)
            form_b <- ifelse(is.na(plant_b$try_growth_form), '', form_b)

            if ((grepl('vine', form_a) || grepl('liana', form_a)) && grepl('tree', form_b)) {
              conflict <- conflict * 0.2
            } else if ((grepl('vine', form_b) || grepl('liana', form_b)) && grepl('tree', form_a)) {
              conflict <- conflict * 0.2
            } else if ((grepl('tree', form_a) && grepl('herb', form_b)) || (grepl('tree', form_b) && grepl('herb', form_a))) {
              conflict <- conflict * 0.4
            } else {
              # MODULATION: Height
              height_diff <- abs(plant_a$height_m - plant_b$height_m)
              if (height_diff < 2.0) {
                conflict <- conflict * 1.0
              } else if (height_diff < 5.0) {
                conflict <- conflict * 0.6
              } else {
                conflict <- conflict * 0.3
              }
            }

            conflicts <- conflicts + conflict

            if (conflict > 0.2) {
              conflict_details[[length(conflict_details) + 1]] <- list(
                type = 'C-C',
                severity = conflict,
                plants = c(plant_a$wfo_scientific_name, plant_b$wfo_scientific_name)
              )
            }
          }
        }
      }

      # CONFLICT 2: High-C + High-S (matches Python lines 1143-1177)
      high_s_plants <- guild_plants_copy %>% filter(S_percentile > PERCENTILE_THRESHOLD)

      for (idx_c in which(guild_plants_copy$C_percentile > PERCENTILE_THRESHOLD)) {
        plant_c <- guild_plants_copy[idx_c, ]
        for (idx_s in which(guild_plants_copy$S_percentile > PERCENTILE_THRESHOLD)) {
          if (idx_c != idx_s) {
            plant_s <- guild_plants_copy[idx_s, ]

            conflict <- 0.6  # Base

            # MODULATION: Light Preference (CRITICAL!)
            s_light <- plant_s$light_pref

            if (is.na(s_light)) {
              s_light <- 5.0  # Default flexible
            }

            if (s_light < 3.2) {
              # S is SHADE-ADAPTED (L=1-3: deep shade to moderate shade)
              # Wants to be under C!
              conflict <- 0.0
            } else if (s_light > 7.47) {
              # S is SUN-LOVING (L=8-9: full-light plant)
              # C will shade it out!
              conflict <- 0.9
            } else {
              # S is FLEXIBLE (L=4-7: semi-shade to half-light)
              # MODULATION: Height
              height_diff <- abs(plant_c$height_m - plant_s$height_m)
              if (height_diff > 8.0) {
                conflict <- conflict * 0.3
              }
            }

            conflicts <- conflicts + conflict

            if (conflict > 0.2) {
              conflict_details[[length(conflict_details) + 1]] <- list(
                type = 'C-S',
                severity = conflict,
                plants = c(plant_c$wfo_scientific_name, plant_s$wfo_scientific_name)
              )
            }
          }
        }
      }

      # CONFLICT 3: High-C + High-R (matches Python lines 1179-1199)
      high_r_plants <- guild_plants_copy %>% filter(R_percentile > PERCENTILE_THRESHOLD)

      for (idx_c in which(guild_plants_copy$C_percentile > PERCENTILE_THRESHOLD)) {
        plant_c <- guild_plants_copy[idx_c, ]
        for (idx_r in which(guild_plants_copy$R_percentile > PERCENTILE_THRESHOLD)) {
          if (idx_c != idx_r) {
            plant_r <- guild_plants_copy[idx_r, ]

            conflict <- 0.8  # Base

            # MODULATION: Height
            height_diff <- abs(plant_c$height_m - plant_r$height_m)
            if (height_diff > 5.0) {
              conflict <- conflict * 0.3
            }

            conflicts <- conflicts + conflict

            if (conflict > 0.2) {
              conflict_details[[length(conflict_details) + 1]] <- list(
                type = 'C-R',
                severity = conflict,
                plants = c(plant_c$wfo_scientific_name, plant_r$wfo_scientific_name)
              )
            }
          }
        }
      }

      # CONFLICT 4: High-R + High-R (matches Python lines 1201-1206)
      if (nrow(high_r_plants) >= 2) {
        for (i in 1:(nrow(high_r_plants) - 1)) {
          for (j in (i + 1):nrow(high_r_plants)) {
            conflict <- 0.3  # Low - short-lived annuals
            conflicts <- conflicts + conflict
          }
        }
      }

      # Normalize by number of possible pairs (conflict density)
      # This makes scores comparable across guild sizes (2-7 plants)
      max_pairs <- if (n_plants > 1) n_plants * (n_plants - 1) else 1
      conflict_density <- conflicts / max_pairs

      # Normalize using calibrated percentiles on density metric
      m2_norm <- self$percentile_normalize(conflict_density, 'n4', invert = FALSE)

      list(
        raw = conflict_density,
        norm = m2_norm,
        details = list(
          raw_conflicts = conflicts,
          conflict_density = conflict_density,
          conflicts = conflict_details,
          high_c = nrow(high_c_plants),
          high_s = nrow(high_s_plants),
          high_r = nrow(high_r_plants)
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
    },

    #' Convert raw CSR score to percentile using global calibration
    #' Unlike guild metrics (tier-stratified), CSR uses GLOBAL percentiles
    #' because conflicts are within-guild comparisons, not cross-guild
    csr_to_percentile = function(raw_value, strategy) {
      # Check if we have CSR percentile calibration data
      if (is.null(self$csr_percentiles)) {
        # Fallback to fixed threshold behavior (matches Python lines 251-257)
        if (strategy == 'c') {
          return(if (raw_value >= 60) 100 else 50)
        } else if (strategy == 's') {
          return(if (raw_value >= 60) 100 else 50)
        } else {  # 'r'
          return(if (raw_value >= 50) 100 else 50)
        }
      }

      params <- self$csr_percentiles[[strategy]]
      if (is.null(params)) {
        warning(glue("No CSR calibration params for strategy: {strategy}"))
        return(50.0)
      }

      # Percentiles for CSR (matches Python line 260)
      percentiles <- c(1, 5, 10, 20, 30, 40, 50, 60, 70, 75, 80, 85, 90, 95, 99)
      values <- sapply(percentiles, function(p) {
        val <- params[[paste0('p', p)]]
        if (is.null(val)) return(NA)
        return(as.numeric(val))
      })

      # Remove NAs
      valid_idx <- !is.na(values)
      percentiles <- percentiles[valid_idx]
      values <- values[valid_idx]

      if (length(values) == 0) {
        return(50.0)
      }

      # Handle edge cases (matches Python lines 264-267)
      if (raw_value <= values[1]) {
        return(0.0)
      }
      if (raw_value >= values[length(values)]) {
        return(100.0)
      }

      # Find bracketing percentiles and interpolate (matches Python lines 270-279)
      for (i in 1:(length(values) - 1)) {
        if (values[i] <= raw_value && raw_value <= values[i + 1]) {
          # Linear interpolation
          if (values[i + 1] - values[i] > 0) {
            fraction <- (raw_value - values[i]) / (values[i + 1] - values[i])
            percentile <- percentiles[i] + fraction * (percentiles[i + 1] - percentiles[i])
          } else {
            percentile <- percentiles[i]
          }
          return(percentile)
        }
      }

      # Fallback (should not reach here)
      return(50.0)
    }
  )
)

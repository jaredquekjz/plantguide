#!/usr/bin/env Rscript
#
# METRIC 2: GROWTH COMPATIBILITY (CSR CONFLICTS)
#
# ============================================================================
# ECOLOGICAL RATIONALE
# ============================================================================
#
# The CSR framework (Grime 1977) classifies plant strategies along 3 axes:
#
# C (COMPETITIVE): Fast-growing, resource-demanding plants that dominate in
#                  high-resource environments. Tall, broad leaves, rapid
#                  biomass accumulation. Examples: trees, large shrubs.
#
# S (STRESS-TOLERANT): Slow-growing, efficient plants adapted to low-resource
#                      environments (drought, poor soil, shade). Conservative
#                      growth, long-lived leaves. Examples: succulents, alpine
#                      plants, shade-tolerant understory.
#
# R (RUDERAL): Short-lived, opportunistic plants that exploit temporary
#              resource pulses. Rapid maturation, high seed production.
#              Examples: annuals, weedy herbs.
#
# CONFLICTS arise when plants with incompatible strategies compete for space
# and resources:
#
# 1. C-C (High-Competitive vs High-Competitive):
#    - Both plants aggressively compete for light, water, nutrients
#    - SEVERITY: 1.0 (base) - highest conflict
#    - MODULATION:
#      * Growth form: Vines on trees = 0.2× (complementary)
#      * Growth form: Trees + herbs = 0.4× (different niches)
#      * Height difference: >5m = 0.3×, 2-5m = 0.6×, <2m = 1.0×
#
# 2. C-S (High-Competitive vs High-Stress-Tolerant):
#    - C plants create shade/resource depletion that S plants cannot tolerate
#    - SEVERITY: 0.6 (base) - moderate conflict
#    - CRITICAL MODULATION: Light preference of S plant
#      * S is shade-adapted (EIVE-L 1-3) → 0.0× (S WANTS shade from C!)
#      * S is sun-loving (EIVE-L 8-9) → 0.9× (C will shade out S)
#      * S is flexible (EIVE-L 4-7) → 0.6× with height modulation
#
# 3. C-R (High-Competitive vs High-Ruderal):
#    - C plants shade and outcompete short-lived R plants
#    - SEVERITY: 0.8 (base) - high conflict
#    - MODULATION: Height difference >5m = 0.3× (R can exploit gaps)
#
# 4. R-R (High-Ruderal vs High-Ruderal):
#    - Both are short-lived, rapid-turnover species
#    - SEVERITY: 0.3 - low conflict (ephemeral, different timing)
#
# ============================================================================
# CALCULATION STEPS
# ============================================================================
#
# STEP 1: Classify plants using PERCENTILE-BASED thresholds
#   - Convert raw CSR scores (0-100) to percentiles using GLOBAL calibration
#   - High-C: C_percentile > 75 (top quartile)
#   - High-S: S_percentile > 75
#   - High-R: R_percentile > 75
#   - WHY GLOBAL? Conflicts are within-guild comparisons, not cross-guild
#
# STEP 2: Detect pairwise conflicts
#   - For each conflict type (C-C, C-S, C-R, R-R), iterate through all pairs
#   - Apply base conflict severity
#   - Apply modulation factors (growth form, height, light preference)
#   - Sum all conflict scores
#
# STEP 3: Normalize by guild size (conflict density)
#   - conflict_density = total_conflicts / max_possible_pairs
#   - max_possible_pairs = n_plants × (n_plants - 1)
#   - This makes scores comparable across guild sizes (2-7 plants)
#
# STEP 4: Percentile normalization
#   - Uses Köppen tier-stratified calibration for metric 'n4'
#   - HIGH conflict_density → HIGH percentile (bad compatibility)
#   - Note: invert = FALSE (no inversion during normalization)
#
# STEP 5: Convert to display score
#   - Final score: 100 - percentile
#   - This inverts the scale so HIGH = GOOD for display
#   - Matches Python guild_scorer_v3.py line 407:
#     'growth_compatibility': 100 - percentiles['n4']
#
# ============================================================================
# PARITY REQUIREMENTS
# ============================================================================
#
# To maintain 100% parity with Python scorer:
# 1. Must use same CSR percentile calibration:
#    shipley_checks/stage4/csr_percentile_calibration_global.json
# 2. Must use same percentile threshold: 75 (top quartile)
# 3. Must apply same modulation factors and weights
# 4. Must use same conflict density normalization
# 5. Must use same Köppen tier calibration file for 'n4' metric
# 6. Must apply same final transformation (100 - percentile)
#
# Python implementation: guild_scorer_v3.py lines 1047-1209
#
# ============================================================================


#' Calculate M2: Growth Compatibility (CSR Conflicts)
#'
#' Scores ecological compatibility based on Grime's CSR strategy conflicts.
#' Detects 4 types of conflicts (C-C, C-S, C-R, R-R) with context-specific
#' modulation based on growth form, height, and light preference.
#'
#' @param guild_plants Data frame with columns:
#'   - CSR_C, CSR_S, CSR_R: Raw CSR scores (0-100)
#'   - height_m: Plant height in meters
#'   - try_growth_form: Growth form (tree, shrub, herb, vine, etc.)
#'   - light_pref: EIVE Light preference (1-9 scale)
#'   - wfo_scientific_name: Plant name (for conflict details)
#' @param csr_to_percentile_fn Function to convert raw CSR to percentile
#' @param percentile_normalize_fn Function to convert raw score to percentile
#'
#' @return List with three elements:
#'   - raw: Conflict density (conflicts per possible pair)
#'   - norm: Normalized percentile (0-100, matches Python before inversion)
#'   - details: List with raw_conflicts, conflict_density, conflict list,
#'              and counts of high-C/S/R plants
#'
#' @details
#' The PERCENTILE_THRESHOLD (75) ensures consistent classification across
#' the full plant database. Plants with C/S/R scores in the top quartile
#' are considered "high" in that strategy.
#'
#' @references
#' Python implementation: src/Stage_4/guild_scorer_v3.py lines 1047-1209
#' Grime, J. P. (1977). Evidence for the existence of three primary strategies
#' in plants and its relevance to ecological and evolutionary theory.
#'
calculate_m2_growth_compatibility <- function(guild_plants,
                                              csr_to_percentile_fn,
                                              percentile_normalize_fn) {

  n_plants <- nrow(guild_plants)
  conflicts <- 0
  conflict_details <- list()

  # -------------------------------------------------------------------------
  # STEP 1: Convert raw CSR scores to GLOBAL percentiles
  # -------------------------------------------------------------------------
  # Why global? CSR conflicts are relative within the guild, not across guilds.
  # A plant with C=60 might be "high-C" in a guild of stress-tolerant plants,
  # but "low-C" in a guild of competitive trees.
  #
  # The percentile transformation provides consistent classification across
  # the entire plant database.

  PERCENTILE_THRESHOLD <- 75  # Top quartile

  guild_plants_copy <- guild_plants
  guild_plants_copy$C_percentile <- sapply(guild_plants_copy$CSR_C, function(x) {
    csr_to_percentile_fn(x, 'c')
  })
  guild_plants_copy$S_percentile <- sapply(guild_plants_copy$CSR_S, function(x) {
    csr_to_percentile_fn(x, 's')
  })
  guild_plants_copy$R_percentile <- sapply(guild_plants_copy$CSR_R, function(x) {
    csr_to_percentile_fn(x, 'r')
  })

  # -------------------------------------------------------------------------
  # CONFLICT TYPE 1: High-C + High-C (Competitive vs Competitive)
  # -------------------------------------------------------------------------
  # ECOLOGICAL CONTEXT:
  # Two fast-growing, resource-demanding plants in the same guild will
  # aggressively compete for light, water, and nutrients. This is the most
  # severe conflict type.
  #
  # MODULATION FACTORS:
  # 1. Vine/Liana + Tree: Vines use trees as structural support without
  #    competing for light (complementary relationship) → 0.2× severity
  #
  # 2. Tree + Herb: Trees occupy canopy, herbs occupy ground layer.
  #    Different niches reduce competition → 0.4× severity
  #
  # 3. Height difference (for plants in same growth form):
  #    - <2m: Same canopy layer, direct competition → 1.0× severity
  #    - 2-5m: Partial niche separation → 0.6× severity
  #    - >5m: Different canopy layers, reduced competition → 0.3× severity
  #
  # Python reference: lines 1104-1141

  high_c_plants <- guild_plants_copy %>% dplyr::filter(C_percentile > PERCENTILE_THRESHOLD)

  if (nrow(high_c_plants) >= 2) {
    for (i in 1:(nrow(high_c_plants) - 1)) {
      for (j in (i + 1):nrow(high_c_plants)) {
        plant_a <- high_c_plants[i, ]
        plant_b <- high_c_plants[j, ]

        conflict <- 1.0  # Base severity

        # Get growth forms (handle NA values)
        form_a <- tolower(as.character(plant_a$try_growth_form))
        form_b <- tolower(as.character(plant_b$try_growth_form))
        form_a <- ifelse(is.na(plant_a$try_growth_form), '', form_a)
        form_b <- ifelse(is.na(plant_b$try_growth_form), '', form_b)

        # MODULATION: Growth form complementarity
        if ((grepl('vine', form_a) || grepl('liana', form_a)) && grepl('tree', form_b)) {
          conflict <- conflict * 0.2  # Vine can climb tree
        } else if ((grepl('vine', form_b) || grepl('liana', form_b)) && grepl('tree', form_a)) {
          conflict <- conflict * 0.2  # Vine can climb tree
        } else if ((grepl('tree', form_a) && grepl('herb', form_b)) ||
                   (grepl('tree', form_b) && grepl('herb', form_a))) {
          conflict <- conflict * 0.4  # Different vertical niches
        } else {
          # MODULATION: Height separation
          height_diff <- abs(plant_a$height_m - plant_b$height_m)
          if (height_diff < 2.0) {
            conflict <- conflict * 1.0  # Same canopy layer
          } else if (height_diff < 5.0) {
            conflict <- conflict * 0.6  # Partial separation
          } else {
            conflict <- conflict * 0.3  # Different canopy layers
          }
        }

        conflicts <- conflicts + conflict

        # Record significant conflicts (severity > 0.2) for diagnostics
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

  # -------------------------------------------------------------------------
  # CONFLICT TYPE 2: High-C + High-S (Competitive vs Stress-Tolerant)
  # -------------------------------------------------------------------------
  # ECOLOGICAL CONTEXT:
  # Competitive plants create environmental stress (shade, resource depletion)
  # that stress-tolerant plants may or may not tolerate depending on their
  # adaptations.
  #
  # CRITICAL MODULATION: Light preference of S plant (EIVE-L scale 1-9)
  #
  # EIVE-L INTERPRETATION:
  # 1-3: Deep shade to moderate shade (< 10% full sunlight)
  # 4-7: Semi-shade to half-light (10-50% full sunlight)
  # 8-9: Full light (> 50% full sunlight)
  #
  # LOGIC:
  # - S is shade-adapted (L < 3.2): S plant WANTS to grow under C plant's
  #   canopy. This is a BENEFICIAL relationship, not a conflict → 0.0× severity
  #
  # - S is sun-loving (L > 7.47): S plant requires full sun. C plant will
  #   shade it out, causing severe stress → 0.9× severity
  #
  # - S is flexible (L 3.2-7.47): S plant can tolerate partial shade.
  #   Conflict depends on height separation:
  #   * >8m height difference: C provides overhead canopy, S thrives below → 0.3×
  #   * Otherwise: base conflict of 0.6×
  #
  # Python reference: lines 1143-1177

  high_s_plants <- guild_plants_copy %>% dplyr::filter(S_percentile > PERCENTILE_THRESHOLD)

  for (idx_c in which(guild_plants_copy$C_percentile > PERCENTILE_THRESHOLD)) {
    plant_c <- guild_plants_copy[idx_c, ]
    for (idx_s in which(guild_plants_copy$S_percentile > PERCENTILE_THRESHOLD)) {
      if (idx_c != idx_s) {
        plant_s <- guild_plants_copy[idx_s, ]

        conflict <- 0.6  # Base severity

        # Get S plant's light preference
        s_light <- plant_s$light_pref

        if (is.na(s_light)) {
          s_light <- 5.0  # Default: flexible (mid-range)
        }

        # CRITICAL: Light-based modulation
        if (s_light < 3.2) {
          # S is SHADE-ADAPTED (L=1-3: deep shade to moderate shade)
          # The S plant WANTS to be under the C plant's canopy!
          # This is a BENEFICIAL relationship, not a conflict
          conflict <- 0.0
        } else if (s_light > 7.47) {
          # S is SUN-LOVING (L=8-9: full-light plant)
          # The C plant will shade it out, causing severe stress
          conflict <- 0.9
        } else {
          # S is FLEXIBLE (L=4-7: semi-shade to half-light)
          # MODULATION: Height difference
          # If C plant is much taller (>8m), S plant can thrive below
          height_diff <- abs(plant_c$height_m - plant_s$height_m)
          if (height_diff > 8.0) {
            conflict <- conflict * 0.3  # Beneficial vertical niche separation
          }
          # Otherwise: use base conflict of 0.6
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

  # -------------------------------------------------------------------------
  # CONFLICT TYPE 3: High-C + High-R (Competitive vs Ruderal)
  # -------------------------------------------------------------------------
  # ECOLOGICAL CONTEXT:
  # Competitive plants create long-term resource monopolies that short-lived
  # ruderal plants cannot tolerate. Ruderals need open, disturbed habitats
  # with temporary resource pulses.
  #
  # MODULATION:
  # - Height difference >5m: R plants can exploit gaps and edges around
  #   C plants before canopy closure → 0.3× severity
  # - Otherwise: High conflict → 0.8× severity (base)
  #
  # Python reference: lines 1179-1199

  high_r_plants <- guild_plants_copy %>% dplyr::filter(R_percentile > PERCENTILE_THRESHOLD)

  for (idx_c in which(guild_plants_copy$C_percentile > PERCENTILE_THRESHOLD)) {
    plant_c <- guild_plants_copy[idx_c, ]
    for (idx_r in which(guild_plants_copy$R_percentile > PERCENTILE_THRESHOLD)) {
      if (idx_c != idx_r) {
        plant_r <- guild_plants_copy[idx_r, ]

        conflict <- 0.8  # Base severity

        # MODULATION: Height difference
        # Tall C plants create gaps where R plants can complete their
        # rapid life cycle before canopy closure
        height_diff <- abs(plant_c$height_m - plant_r$height_m)
        if (height_diff > 5.0) {
          conflict <- conflict * 0.3  # Temporal niche separation
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

  # -------------------------------------------------------------------------
  # CONFLICT TYPE 4: High-R + High-R (Ruderal vs Ruderal)
  # -------------------------------------------------------------------------
  # ECOLOGICAL CONTEXT:
  # Both plants are short-lived, opportunistic species with rapid turnover.
  # They typically have different timing (spring ephemerals vs summer annuals)
  # or occupy slightly different microsites within disturbed patches.
  #
  # SEVERITY: 0.3 - Low conflict (temporal/spatial niche separation)
  #
  # Python reference: lines 1201-1206

  if (nrow(high_r_plants) >= 2) {
    for (i in 1:(nrow(high_r_plants) - 1)) {
      for (j in (i + 1):nrow(high_r_plants)) {
        conflict <- 0.3  # Low severity - ephemeral species
        conflicts <- conflicts + conflict

        # Note: We don't record R-R conflicts in details (always low severity)
      }
    }
  }

  # -------------------------------------------------------------------------
  # STEP 3: Normalize by guild size (conflict density)
  # -------------------------------------------------------------------------
  # Conflict density = total conflicts / maximum possible pairs
  #
  # This normalization ensures scores are comparable across guild sizes:
  # - 2 plants: max 2 pairs (A→B, B→A)
  # - 3 plants: max 6 pairs (A→B, A→C, B→A, B→C, C→A, C→B)
  # - 7 plants: max 42 pairs
  #
  # Without this normalization, larger guilds would always have higher
  # conflict scores simply due to more pairwise comparisons.

  max_pairs <- if (n_plants > 1) n_plants * (n_plants - 1) else 1
  conflict_density <- conflicts / max_pairs

  # -------------------------------------------------------------------------
  # STEP 4: Percentile normalization using Köppen tier calibration
  # -------------------------------------------------------------------------
  # Converts absolute conflict density to relative percentile within the
  # calibration dataset for the specified Köppen climate tier.
  #
  # Metric name: 'n4' (legacy naming from earlier versions)
  # invert = FALSE: HIGH conflict_density → HIGH percentile (bad compatibility)

  m2_norm <- percentile_normalize_fn(conflict_density, 'n4', invert = FALSE)

  # -------------------------------------------------------------------------
  # RETURN: Raw conflict density, normalized percentile, and diagnostics
  # -------------------------------------------------------------------------

  list(
    raw = conflict_density,
    norm = m2_norm,
    details = list(
      raw_conflicts = conflicts,
      conflict_density = conflict_density,
      conflicts = conflict_details,  # List of significant conflicts for debugging
      high_c = nrow(high_c_plants),
      high_s = nrow(high_s_plants),
      high_r = nrow(high_r_plants)
    )
  )
}

#!/usr/bin/env Rscript
#
# METRIC 7: POLLINATOR SUPPORT (SHARED POLLINATORS)
#
# ============================================================================
# ECOLOGICAL RATIONALE
# ============================================================================
#
# Shared pollinators create mutualistic networks that benefit both plants
# and pollinators:
#
# 1. RESOURCE CONTINUITY:
#    - Multiple plants provide sequential/overlapping flowering
#    - Reduces seasonal gaps in nectar/pollen availability
#    - Supports stable pollinator populations
#
# 2. POLLINATOR FIDELITY:
#    - Generalist pollinators visit multiple plant species in sequence
#    - Increases pollen transfer efficiency
#    - Higher visitation rates benefit plant reproduction
#
# 3. NETWORK RESILIENCE:
#    - If one plant species fails (drought, disease), pollinators have
#      alternative resources
#    - Redundancy protects against pollinator population crashes
#
# KEY CONCEPT: Quadratic Benefit
# The value of shared pollinators increases NON-LINEARLY with plant overlap:
# - 2 plants sharing a pollinator: Moderate benefit
# - 5 plants sharing a pollinator: HIGH benefit (pollinator visits all frequently)
# - Quadratic weighting: (count / n_plants)²
#
# This reflects:
# - Increased pollinator retention (more resources = longer stays)
# - Network effects (pollinator movements between plants)
# - Flowering synchrony benefits
#
# ============================================================================
# CALCULATION STEPS
# ============================================================================
#
# STEP 1: Count shared pollinators across guild members
#   - For each pollinator taxon, count how many plants host it
#   - Only pollinators shared by ≥2 plants contribute to score
#   - Includes both strict pollinators AND flower visitors (nectar feeders)
#
# STEP 2: Score with quadratic weighting
#   - For each shared pollinator:
#     * overlap_ratio = count / n_plants
#     * contribution = overlap_ratio²
#   - Sum across all shared pollinators
#   - Interpretation:
#     * 2/7 plants (29% overlap) → 0.08 contribution
#     * 5/7 plants (71% overlap) → 0.51 contribution (6× higher!)
#     * 7/7 plants (100% overlap) → 1.00 contribution (12× higher!)
#
# STEP 3: Percentile normalization
#   - Uses Köppen tier-stratified calibration for metric 'p6'
#   - HIGH p7_raw → HIGH percentile (good pollinator support)
#   - Note: No final inversion needed (high percentile = high score)
#
# ============================================================================
# DATA SOURCES
# ============================================================================
#
# organisms_df (organism_profiles_pure_r.csv):
# - Columns: plant_wfo_id, pollinators, flower_visitors
# - Each column contains pipe-separated GBIF animal taxon IDs
# - Derived from GloBI interaction network
# - Includes:
#   * Strict pollinators (bees, specialized flies, hummingbirds)
#   * Flower visitors (butterflies, beetles, generalist flies)
#
# ============================================================================
# PARITY REQUIREMENTS
# ============================================================================
#
# To maintain 100% parity with Python scorer:
# 1. Must use same count_shared_organisms logic (≥2 plants threshold)
# 2. Must use same quadratic weighting formula: (count / n_plants)²
# 3. Must include both pollinators AND flower_visitors columns
# 4. Must use same Köppen tier calibration file for 'p6' metric
#
# Python implementation: guild_scorer_v3.py lines 1645-1674
#
# ============================================================================


#' Calculate M7: Pollinator Support
#'
#' Scores shared pollinator networks using quadratic weighting to reflect
#' non-linear benefits of high-overlap pollinator communities.
#'
#' @param plant_ids Character vector of WFO taxon IDs for the guild
#' @param guild_plants Data frame with plant metadata (not used in M7)
#' @param organisms_df Data frame with plant-organism associations
#' @param count_shared_organisms_fn Function to count shared organisms
#' @param percentile_normalize_fn Function to convert raw score to percentile
#'
#' @return List with three elements:
#'   - raw: Quadratic-weighted pollinator overlap score
#'   - norm: Percentile score (0-100, HIGH = GOOD)
#'   - details: List with n_shared_pollinators and top 5 pollinator names
#'
calculate_m7_pollinator_support <- function(plant_ids,
                                            guild_plants,
                                            organisms_df,
                                            count_shared_organisms_fn,
                                            percentile_normalize_fn) {

  n_plants <- length(plant_ids)

  # Count shared pollinators (pollinators hosted by ≥2 plants)
  # Includes both strict pollinators AND flower visitors
  shared_pollinators <- count_shared_organisms_fn(
    organisms_df, plant_ids,
    'pollinators', 'flower_visitors'
  )

  # Score with QUADRATIC weighting
  # Reflects non-linear benefits of high-overlap pollinator communities
  p7_raw <- 0
  for (org_name in names(shared_pollinators)) {
    count <- shared_pollinators[[org_name]]
    if (count >= 2) {
      overlap_ratio <- count / n_plants
      p7_raw <- p7_raw + overlap_ratio ^ 2  # QUADRATIC benefit
    }
  }

  # Percentile normalize
  m7_norm <- percentile_normalize_fn(p7_raw, 'p6')

  list(
    raw = p7_raw,
    norm = m7_norm,
    details = list(
      n_shared_pollinators = length(shared_pollinators),
      pollinators = names(shared_pollinators)[1:min(5, length(shared_pollinators))]
    )
  )
}

#!/usr/bin/env Rscript
#
# METRIC 5: BENEFICIAL FUNGI NETWORKS (MYCORRHIZAE & ENDOPHYTES)
#
# ============================================================================
# ECOLOGICAL RATIONALE
# ============================================================================
#
# Beneficial fungi provide critical ecosystem services:
#
# 1. ARBUSCULAR MYCORRHIZAL FUNGI (AMF):
#    - Form symbiotic associations with ~80% of plant species
#    - Extend root systems via hyphal networks
#    - Enhance nutrient uptake (especially phosphorus)
#    - Improve drought resistance
#    - Create underground networks connecting multiple plants (Common Mycorrhizal Networks)
#
# 2. ECTOMYCORRHIZAL FUNGI (EMF):
#    - Form associations with trees (especially conifers, oaks, beeches)
#    - Sheath root tips in fungal mantle
#    - Critical for nutrient cycling in forest ecosystems
#
# 3. ENDOPHYTIC FUNGI:
#    - Live inside plant tissues without causing disease
#    - Produce defensive compounds (alkaloids, terpenoids)
#    - Enhance stress tolerance
#    - Some provide systemic acquired resistance
#
# 4. SAPROTROPHIC FUNGI:
#    - Decompose organic matter
#    - Recycle nutrients from dead plant material
#    - Improve soil structure
#
# KEY CONCEPT: Common Mycorrhizal Networks (CMNs)
# When multiple plants share the same beneficial fungi, they form underground
# networks that:
# - Transfer resources between plants (carbon, nitrogen, water)
# - Communicate defense signals
# - Support establishment of new seedlings
# - Stabilize plant communities
#
# ============================================================================
# CALCULATION STEPS
# ============================================================================
#
# STEP 1: Count shared beneficial fungi across guild members
#   - For each fungal taxon, count how many plants host it
#   - Only fungi shared by ≥2 plants contribute to network score
#   - Rationale: Single-plant fungi don't create networks
#
# STEP 2: Network score (weight: 0.6)
#   - For each shared fungus, calculate: count / n_plants
#   - This gives the "network connectivity" (0-1 scale)
#   - Sum across all shared fungi
#   - Interpretation:
#     * High score: Many fungi shared by most plants (strong CMNs)
#     * Low score: Few fungi, or fungi shared by only 2-3 plants
#
# STEP 3: Coverage ratio (weight: 0.4)
#   - Count how many plants have ANY beneficial fungi
#   - coverage_ratio = plants_with_fungi / total_plants
#   - Rationale: Even without shared networks, individual fungal associations
#     provide plant benefits (nutrient uptake, stress tolerance)
#
# STEP 4: Combined score
#   - p5_raw = network_score × 0.6 + coverage_ratio × 0.4
#   - This balances network effects (60%) with individual benefits (40%)
#
# STEP 5: Percentile normalization
#   - Uses Köppen tier-stratified calibration for metric 'p3'
#   - HIGH p5_raw → HIGH percentile (good fungal networks)
#   - Note: No final inversion needed (high percentile = high score)
#
# ============================================================================
# DATA SOURCES
# ============================================================================
#
# fungi_df (fungal_guilds_pure_r.csv):
# - Columns: plant_wfo_id, amf_fungi, emf_fungi, endophytic_fungi, saprotrophic_fungi
# - Each column contains pipe-separated GBIF fungal taxon IDs
# - Derived from FunGuild, GlobalFungi, and literature mining
#
# ============================================================================
# PARITY REQUIREMENTS
# ============================================================================
#
# To maintain 100% parity with Python scorer:
# 1. Must use same count_shared_organisms logic (≥2 plants threshold)
# 2. Must use same network score formula (count / n_plants)
# 3. Must use same coverage ratio calculation
# 4. Must use same weights (0.6 network, 0.4 coverage)
# 5. Must use same Köppen tier calibration file for 'p3' metric
#
# Python implementation: guild_scorer_v3.py lines 1420-1477
#
# ============================================================================


#' Calculate M5: Beneficial Fungi Networks
#'
#' Scores Common Mycorrhizal Networks and individual fungal associations
#' using shared organism counting and coverage analysis.
#'
#' @param plant_ids Character vector of WFO taxon IDs for the guild
#' @param guild_plants Data frame with plant metadata (not used in M5)
#' @param fungi_df Data frame with plant-fungi associations
#' @param count_shared_organisms_fn Function to count shared organisms
#' @param percentile_normalize_fn Function to convert raw score to percentile
#'
#' @return List with three elements:
#'   - raw: Combined network + coverage score (0-1 scale)
#'   - norm: Percentile score (0-100, HIGH = GOOD)
#'   - details: List with network_score, coverage_ratio, n_shared_fungi,
#'              plants_with_fungi
#'
calculate_m5_beneficial_fungi <- function(plant_ids,
                                          guild_plants,
                                          fungi_df,
                                          count_shared_organisms_fn,
                                          percentile_normalize_fn) {

  n_plants <- length(plant_ids)

  # Count shared beneficial fungi (fungi hosted by ≥2 plants)
  beneficial_counts <- count_shared_organisms_fn(
    fungi_df, plant_ids,
    'amf_fungi', 'emf_fungi', 'endophytic_fungi', 'saprotrophic_fungi'
  )

  # COMPONENT 1: Network score (weight 0.6)
  # For each shared fungus, calculate network connectivity
  network_raw <- 0
  for (org_name in names(beneficial_counts)) {
    count <- beneficial_counts[[org_name]]
    if (count >= 2) {
      network_raw <- network_raw + (count / n_plants)
    }
  }

  # COMPONENT 2: Coverage ratio (weight 0.4)
  # What fraction of plants have ANY beneficial fungi?
  guild_fungi <- fungi_df %>% dplyr::filter(plant_wfo_id %in% plant_ids)
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

  # Combined score: 60% network, 40% coverage
  p5_raw <- network_raw * 0.6 + coverage_ratio * 0.4

  # Percentile normalize
  m5_norm <- percentile_normalize_fn(p5_raw, 'p3')

  # -------------------------------------------------------------------------
  # STEP 6: Build fungi counts by category (for network profile generation)
  # -------------------------------------------------------------------------
  # Build fungi_counts: fungus_name → number of plants hosting it
  # Also track category for each fungus (AMF, EMF, Endophytic, Saprotrophic)

  fungi_counts <- list()
  fungus_category_map <- list()  # fungus_name → category string

  for (i in seq_len(nrow(guild_fungi))) {
    row <- guild_fungi[i, ]

    # AMF fungi
    amf <- row$amf_fungi[[1]]
    if (!is.null(amf) && length(amf) > 0) {
      for (fungus in amf) {
        if (is.null(fungi_counts[[fungus]])) {
          fungi_counts[[fungus]] <- 0
          fungus_category_map[[fungus]] <- "AMF"
        }
        fungi_counts[[fungus]] <- fungi_counts[[fungus]] + 1
      }
    }

    # EMF fungi
    emf <- row$emf_fungi[[1]]
    if (!is.null(emf) && length(emf) > 0) {
      for (fungus in emf) {
        if (is.null(fungi_counts[[fungus]])) {
          fungi_counts[[fungus]] <- 0
          fungus_category_map[[fungus]] <- "EMF"
        }
        fungi_counts[[fungus]] <- fungi_counts[[fungus]] + 1
      }
    }

    # Endophytic fungi
    endo <- row$endophytic_fungi[[1]]
    if (!is.null(endo) && length(endo) > 0) {
      for (fungus in endo) {
        if (is.null(fungi_counts[[fungus]])) {
          fungi_counts[[fungus]] <- 0
          fungus_category_map[[fungus]] <- "Endophytic"
        }
        fungi_counts[[fungus]] <- fungi_counts[[fungus]] + 1
      }
    }

    # Saprotrophic fungi
    sapro <- row$saprotrophic_fungi[[1]]
    if (!is.null(sapro) && length(sapro) > 0) {
      for (fungus in sapro) {
        if (is.null(fungi_counts[[fungus]])) {
          fungi_counts[[fungus]] <- 0
          fungus_category_map[[fungus]] <- "Saprotrophic"
        }
        fungi_counts[[fungus]] <- fungi_counts[[fungus]] + 1
      }
    }
  }

  list(
    raw = p5_raw,
    norm = m5_norm,
    fungi_counts = fungi_counts,
    fungus_category_map = fungus_category_map,
    details = list(
      network_score = network_raw,
      coverage_ratio = coverage_ratio,
      n_shared_fungi = length(beneficial_counts),
      plants_with_fungi = plants_with_beneficial
    )
  )
}

#!/usr/bin/env Rscript
#
# METRIC 4: DISEASE SUPPRESSION (ANTAGONIST FUNGI)
#
# ============================================================================
# ECOLOGICAL RATIONALE
# ============================================================================
#
# Plant guilds can suppress fungal diseases through mycoparasitism and
# competitive exclusion. Key mechanisms:
#
# 1. SPECIFIC ANTAGONIST MATCHES (Weight: 1.0) - RARELY FIRES
#    - Plant A hosts pathogenic fungi (diseases)
#    - Plant B hosts mycoparasitic fungi that specifically target those pathogens
#    - Example: Trichoderma harzianum (on tomato) parasitizes Fusarium
#      oxysporum (pathogen of beans)
#    - Database: pathogen_antagonists lookup table
#    - Note: Data coverage is limited due to sparse mycoparasitism research
#
# 2. GENERAL MYCOPARASITES (Weight: 1.0) - PRIMARY MECHANISM
#    - Plant B hosts broad-spectrum mycoparasitic fungi (Trichoderma, Gliocladium)
#    - These fungi provide generalist protection against multiple pathogens
#    - Rationale: Most mycoparasites have broad host ranges, attacking multiple
#      fungal genera through direct parasitism or antibiotic production
#    - This mechanism fires much more frequently than specific matches
#
# KEY CONCEPT: Pairwise Protection (identical to M3)
# - For each vulnerable plant A (with pathogens), check all other plants B
# - Sum protection scores where B provides disease suppression for A
# - Normalize by guild size to enable cross-guild comparison
#
# ============================================================================
# CALCULATION STEPS
# ============================================================================
#
# STEP 1: Extract guild fungi data
#   - Filter fungi_df to guild members
#   - Extract pathogenic_fungi and mycoparasite_fungi columns
#
# STEP 2: Pairwise analysis (nested loop)
#   - Outer loop: Plant A (vulnerable - has pathogens)
#   - Inner loop: Plant B (protective - has mycoparasites)
#   - For each A→B pair, check 2 disease suppression mechanisms
#
# STEP 3: Mechanism scoring
#   - Mechanism 1: For each pathogen on A, check if B hosts known antagonists
#     * Match pathogen against pathogen_antagonists lookup
#     * Count matching mycoparasites on B
#     * Score: n_matches × 1.0
#     * Note: This rarely fires due to sparse data coverage
#
#   - Mechanism 2: General mycoparasites on B (PRIMARY MECHANISM)
#     * If A has any pathogens AND B has any mycoparasites
#     * Score: n_mycoparasites_on_B × 1.0
#     * This is the dominant scoring mechanism
#
# STEP 4: Normalize by guild size
#   - pathogen_control_normalized = (pathogen_control_raw / max_pairs) × 10
#   - max_pairs = n_plants × (n_plants - 1)
#   - The ×10 scaling factor (vs ×20 for M3) reflects:
#     * Lower mechanism diversity (2 vs 3 in M3)
#     * Sparser data coverage for fungal interactions
#
# STEP 5: Percentile normalization
#   - Uses Köppen tier-stratified calibration for metric 'p2'
#   - HIGH pathogen_control_normalized → HIGH percentile (good suppression)
#   - Note: No final inversion needed (high percentile = high score)
#
# ============================================================================
# DATA SOURCES
# ============================================================================
#
# 1. fungi_df (fungal_guilds_pure_r.csv):
#    - Columns: plant_wfo_id, pathogenic_fungi, mycoparasite_fungi, ...
#    - Each fungal column contains pipe-separated GBIF fungal taxon IDs
#
# 2. pathogen_antagonists (pathogen_antagonists_pure_r.csv):
#    - Lookup table: pathogen GBIF ID → list of antagonist fungal GBIF IDs
#    - Derived from FunGuild, GloBI, and mycoparasitism literature
#    - WARNING: Coverage is sparse (~5% of pathogens have known antagonists)
#
# ============================================================================
# PARITY REQUIREMENTS
# ============================================================================
#
# To maintain 100% parity with Python scorer:
# 1. Must use same fungi extraction logic
# 2. Must use same lookup tables (MD5-verified CSVs)
# 3. Must use same weights (1.0, 1.0)
# 4. Must use same normalization (/ max_pairs × 10)
# 5. Must use same Köppen tier calibration file for 'p2' metric
#
# Python implementation: guild_scorer_v3.py lines 1331-1418
#
# ============================================================================


#' Calculate M4: Disease Suppression (Antagonist Fungi)
#'
#' Scores fungal disease control provided by mycoparasitic fungi associated
#' with guild plants. Uses pairwise analysis to identify protective relationships
#' between vulnerable (disease-prone) and protective (mycoparasite-hosting) plants.
#'
#' @param plant_ids Character vector of WFO taxon IDs for the guild
#' @param guild_plants Data frame with plant metadata (not used in M4)
#' @param fungi_df Data frame with plant-fungi associations
#' @param pathogen_antagonists Named list mapping pathogen IDs to antagonist IDs
#' @param percentile_normalize_fn Function to convert raw score to percentile
#'
#' @return List with three elements:
#'   - raw: Normalized pathogen control score (scaled by guild size)
#'   - norm: Percentile score (0-100, HIGH = GOOD)
#'   - details: List with pathogen_control_raw, max_pairs, n_mechanisms, and
#'              mechanism details for diagnostics
#'
#' @details
#' Edge case: If no fungi data is available for guild, returns zero score.
#' Mechanism 2 (general mycoparasites) is the primary contributor to the score,
#' accounting for 95%+ of protection due to sparse specific antagonist data.
#'
#' @references
#' Python implementation: src/Stage_4/guild_scorer_v3.py lines 1331-1418
#'
calculate_m4_disease_control <- function(plant_ids,
                                         guild_plants,
                                         fungi_df,
                                         pathogen_antagonists,
                                         percentile_normalize_fn) {

  n_plants <- length(plant_ids)
  pathogen_control_raw <- 0.0
  mechanisms <- list()

  # -------------------------------------------------------------------------
  # STEP 1: Extract guild fungi data
  # -------------------------------------------------------------------------

  guild_fungi <- fungi_df %>% dplyr::filter(plant_wfo_id %in% plant_ids)

  if (nrow(guild_fungi) == 0) {
    return(list(
      raw = 0.0,
      norm = 0.0,
      details = list(note = "No fungi data available")
    ))
  }

  # -------------------------------------------------------------------------
  # STEP 2: Pairwise analysis - vulnerable plant A vs protective plant B
  # -------------------------------------------------------------------------
  # For each plant A that has pathogenic fungi (vulnerable), check all other
  # plants B for mycoparasitic fungi (protective agents)

  for (i in seq_len(nrow(guild_fungi))) {
    row_a <- guild_fungi[i, ]
    plant_a_id <- row_a$plant_wfo_id
    pathogens_a <- row_a$pathogenic_fungi[[1]]

    # Skip if plant A has no pathogens (not vulnerable)
    if (is.null(pathogens_a) || length(pathogens_a) == 0) {
      next
    }

    # Check all other plants B for protective mycoparasites
    for (j in seq_len(nrow(guild_fungi))) {
      if (i == j) next  # Skip self-comparison

      row_b <- guild_fungi[j, ]
      plant_b_id <- row_b$plant_wfo_id
      mycoparasites_b <- row_b$mycoparasite_fungi[[1]]

      # Skip if plant B has no mycoparasites
      if (is.null(mycoparasites_b) || length(mycoparasites_b) == 0) {
        next
      }

      # -----------------------------------------------------------------
      # MECHANISM 1: Specific antagonist matches (weight 1.0) - RARELY FIRES
      # -----------------------------------------------------------------
      # For each pathogen on plant A, check if plant B hosts known antagonists
      # of that pathogen.
      #
      # Example:
      # - Plant A (bean) hosts Fusarium oxysporum (wilt pathogen)
      # - Plant B (tomato) hosts Trichoderma harzianum (mycoparasite)
      # - Lookup: pathogen_antagonists["Fusarium oxysporum"] contains "Trichoderma..."
      # - Match found → pathogen_control_raw += 1.0
      #
      # NOTE: This mechanism rarely fires because:
      # 1. Mycoparasitism research is sparse (few known pairings)
      # 2. Most databases focus on agricultural pathogens only
      # 3. GloBI/FunGuild coverage is incomplete
      #
      # In practice, Mechanism 2 (general mycoparasites) accounts for 95%+ of score

      for (pathogen in pathogens_a) {
        if (pathogen %in% names(pathogen_antagonists)) {
          known_antagonists <- pathogen_antagonists[[pathogen]]
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

      # -----------------------------------------------------------------
      # MECHANISM 2: General mycoparasites (weight 1.0) - PRIMARY MECHANISM
      # -----------------------------------------------------------------
      # If plant A has any pathogens AND plant B has any mycoparasites,
      # award score based on the number of mycoparasites.
      #
      # Rationale:
      # Most mycoparasitic fungi (especially Trichoderma, Gliocladium,
      # Clonostachys) have broad host ranges, attacking multiple fungal
      # genera through:
      # 1. Direct mycoparasitism (coiling around hyphae, penetrating cells)
      # 2. Antibiotic production (gliotoxin, peptaibols)
      # 3. Competition for nutrients and space
      # 4. Induced systemic resistance in plants
      #
      # Examples of broad-spectrum mycoparasites:
      # - Trichoderma spp.: Attack Fusarium, Rhizoctonia, Pythium, Botrytis
      # - Gliocladium spp.: Attack Pythium, Phytophthora, Sclerotinia
      # - Clonostachys rosea: Attack Botrytis, Sclerotinia, Fusarium
      #
      # Weight = 1.0 (same as specific matches) because:
      # - Broad-spectrum activity is well-documented
      # - Reliability is similar to specific matches in practice
      # - This mechanism is the primary source of protection in most guilds

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

  # -------------------------------------------------------------------------
  # STEP 4: Normalize by guild size
  # -------------------------------------------------------------------------
  # Dividing by max_pairs ensures scores are comparable across guild sizes.
  # Multiplying by 10 (vs 20 for M3) reflects lower mechanism diversity.

  max_pairs <- n_plants * (n_plants - 1)
  pathogen_control_normalized <- if (max_pairs > 0) {
    pathogen_control_raw / max_pairs * 10
  } else {
    0
  }

  # -------------------------------------------------------------------------
  # STEP 5: Percentile normalization
  # -------------------------------------------------------------------------
  # Converts absolute pathogen control score to relative percentile within
  # the calibration dataset for the specified Köppen climate tier.
  #
  # Metric name: 'p2'
  # HIGH pathogen_control_normalized → HIGH percentile (good suppression)
  # No final inversion needed (high percentile already means high score)

  m4_norm <- percentile_normalize_fn(pathogen_control_normalized, 'p2')

  # -------------------------------------------------------------------------
  # RETURN: Normalized score, percentile, and mechanism diagnostics
  # -------------------------------------------------------------------------

  list(
    raw = pathogen_control_normalized,
    norm = m4_norm,
    details = list(
      pathogen_control_raw = pathogen_control_raw,
      max_pairs = max_pairs,
      n_mechanisms = length(mechanisms),
      mechanisms = mechanisms  # Return all mechanisms (typically <10)
    )
  )
}

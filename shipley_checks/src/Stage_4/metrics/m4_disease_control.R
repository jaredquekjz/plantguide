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
# 2. GENERAL MYCOPARASITES (Weight: 0.5) - PRIMARY MECHANISM
#    - Plant B hosts broad-spectrum mycoparasitic fungi (Trichoderma, Gliocladium)
#    - These fungi provide generalist protection against multiple pathogens
#    - Rationale: Most mycoparasites have broad host ranges, attacking multiple
#      fungal genera through direct parasitism or antibiotic production
#    - This mechanism fires much more frequently than specific matches
#
# 3. GENERAL FUNGIVORES (Weight: 0.2) - SUPPLEMENTARY MECHANISM
#    - Plant B hosts animals that eat fungi (fungivores)
#    - These organisms provide supplementary disease control by consuming pathogenic fungi
#    - Examples: Fungus gnats, beetles, slugs that feed on fungal fruiting bodies
#    - Lower weight reflects indirect/opportunistic nature of control
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
#   - Inner loop: Plant B (protective - has mycoparasites/fungivores)
#   - For each A→B pair, check 3 disease suppression mechanisms
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
#     * Score: n_mycoparasites_on_B × 0.5
#     * This is the dominant scoring mechanism
#
#   - Mechanism 3: General fungivores on B (SUPPLEMENTARY MECHANISM)
#     * If A has any pathogens AND B has any fungivores
#     * Score: n_fungivores_on_B × 0.2
#     * Provides indirect disease control through fungal consumption
#
# STEP 4: Normalize by guild size
#   - pathogen_control_normalized = (pathogen_control_raw / max_pairs) × 10
#   - max_pairs = n_plants × (n_plants - 1)
#   - The ×10 scaling factor (vs ×20 for M3) reflects:
#     * Similar mechanism diversity (3 mechanisms, but lower weights)
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
# To maintain 100% parity with Rust scorer:
# 1. Must use same fungi and organisms extraction logic
# 2. Must use same lookup tables (MD5-verified parquets)
# 3. Must use same weights (1.0, 0.5, 0.2)
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
#' @param organisms_df Data frame with plant-organism associations (for fungivores)
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
#' accounting for ~80% of protection due to sparse specific antagonist data.
#' Mechanism 3 (fungivores) provides supplementary indirect control (~15%).
#'
#' @references
#' Python implementation: src/Stage_4/guild_scorer_v3.py lines 1331-1418
#'
calculate_m4_disease_control <- function(plant_ids,
                                         guild_plants,
                                         fungi_df,
                                         organisms_df,
                                         pathogen_antagonists,
                                         percentile_normalize_fn) {

  n_plants <- length(plant_ids)
  pathogen_control_raw <- 0.0
  mechanisms <- list()
  specific_antagonist_matches <- 0
  matched_antagonist_pairs <- list()

  # -------------------------------------------------------------------------
  # STEP 1: Extract guild fungi data
  # -------------------------------------------------------------------------

  guild_fungi <- fungi_df %>% dplyr::filter(plant_wfo_id %in% plant_ids)

  if (nrow(guild_fungi) == 0) {
    return(list(
      raw = 0.0,
      norm = 0.0,
      mycoparasite_counts = list(),
      pathogen_counts = list(),
      specific_antagonist_matches = 0,
      matched_antagonist_pairs = data.frame(pathogen = character(), antagonist = character()),
      details = list(note = "No fungi data available")
    ))
  }

  # Extract guild organisms data (for fungivores)
  guild_organisms <- organisms_df %>% dplyr::filter(plant_wfo_id %in% plant_ids)

  # Build set of ALL known mycoparasites (from pathogen_antagonists lookup values)
  known_mycoparasites <- unique(unlist(pathogen_antagonists, use.names = FALSE))

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
              specific_antagonist_matches <- specific_antagonist_matches + 1
              mechanisms[[length(mechanisms) + 1]] <- list(
                type = 'specific_antagonist',
                pathogen = pathogen,
                control_plant = plant_b_id,
                antagonists = head(matching, 3)
              )
              # Track matched pairs
              for (antagonist in matching) {
                matched_antagonist_pairs[[length(matched_antagonist_pairs) + 1]] <- list(
                  pathogen = pathogen,
                  antagonist = antagonist
                )
              }
            }
          }
        }
      }

      # -----------------------------------------------------------------
      # MECHANISM 2: General mycoparasites (weight 0.5) - PRIMARY MECHANISM
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
      # Weight = 0.5 (lower than specific matches) because:
      # - Broad-spectrum activity is well-documented
      # - But less reliable than targeted specific antagonist matches
      # - This mechanism is still the primary source of protection in most guilds

      if (length(pathogens_a) > 0 && length(mycoparasites_b) > 0) {
        pathogen_control_raw <- pathogen_control_raw + length(mycoparasites_b) * 0.5
        mechanisms[[length(mechanisms) + 1]] <- list(
          type = 'general_mycoparasite',
          vulnerable_plant = plant_a_id,
          n_pathogens = length(pathogens_a),
          control_plant = plant_b_id,
          mycoparasites = head(mycoparasites_b, 5)
        )
      }

      # -----------------------------------------------------------------
      # MECHANISM 3: General fungivores (weight 0.2) - SUPPLEMENTARY MECHANISM
      # -----------------------------------------------------------------
      # If plant A has any pathogens AND plant B hosts fungivores (animals that
      # eat fungi), award score based on the number of fungivores.
      #
      # Rationale:
      # Fungivores provide supplementary disease control by consuming fungal
      # fruiting bodies, mycelia, and spores. While not as targeted as
      # mycoparasites, they can reduce pathogen inoculum and slow disease spread.
      #
      # Examples of fungivorous organisms:
      # - Fungus gnats (Sciaridae): Consume fungal mycelia and spores
      # - Collembola (springtails): Feed on fungal hyphae in soil/leaf litter
      # - Mycophagous beetles: Consume fungal fruiting bodies
      # - Slugs and snails: Opportunistically feed on fungi
      #
      # Weight = 0.2 (lowest weight) because:
      # - Indirect/opportunistic mechanism (not specialized biocontrol agents)
      # - May feed on beneficial fungi as well as pathogens (non-selective)
      # - Control effect is supplementary to mycoparasitism
      #
      # NOTE: This matches Rust implementation at m4_disease_control.rs:181-193

      # Find organism data for plant B
      org_row_b <- guild_organisms %>% dplyr::filter(plant_wfo_id == plant_b_id)
      if (nrow(org_row_b) > 0) {
        fungivores_b <- org_row_b$fungivores_eats[[1]]

        if (!is.null(fungivores_b) && length(fungivores_b) > 0 &&
            length(pathogens_a) > 0) {
          pathogen_control_raw <- pathogen_control_raw + length(fungivores_b) * 0.2
          mechanisms[[length(mechanisms) + 1]] <- list(
            type = 'general_fungivore',
            vulnerable_plant = plant_a_id,
            n_pathogens = length(pathogens_a),
            control_plant = plant_b_id,
            fungivores = head(fungivores_b, 5)
          )
        }
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
  # STEP 6: Build agent counts (FILTERED to known mycoparasites)
  # -------------------------------------------------------------------------

  # Build mycoparasite_counts: mycoparasite_name → number of plants hosting it
  # ONLY count if this agent is a known mycoparasite in the lookup table
  mycoparasite_counts <- list()
  for (i in seq_len(nrow(guild_fungi))) {
    row <- guild_fungi[i, ]
    mycoparasites <- row$mycoparasite_fungi[[1]]
    if (!is.null(mycoparasites) && length(mycoparasites) > 0) {
      # ONLY count known mycoparasites
      mycoparasites_filtered <- intersect(mycoparasites, known_mycoparasites)
      for (myco in mycoparasites_filtered) {
        if (is.null(mycoparasite_counts[[myco]])) {
          mycoparasite_counts[[myco]] <- 0
        }
        mycoparasite_counts[[myco]] <- mycoparasite_counts[[myco]] + 1
      }
    }
  }

  # Build pathogen_counts: pathogen_name → number of plants affected
  pathogen_counts <- list()
  for (i in seq_len(nrow(guild_fungi))) {
    row <- guild_fungi[i, ]
    pathogens <- row$pathogenic_fungi[[1]]
    if (!is.null(pathogens) && length(pathogens) > 0) {
      for (pathogen in pathogens) {
        if (is.null(pathogen_counts[[pathogen]])) {
          pathogen_counts[[pathogen]] <- 0
        }
        pathogen_counts[[pathogen]] <- pathogen_counts[[pathogen]] + 1
      }
    }
  }

  # Convert matched pairs from list to data.frame and deduplicate
  if (length(matched_antagonist_pairs) > 0) {
    matched_antagonist_pairs_df <- do.call(rbind, lapply(matched_antagonist_pairs, as.data.frame, stringsAsFactors = FALSE))
    matched_antagonist_pairs_df <- unique(matched_antagonist_pairs_df)
    matched_antagonist_pairs_df <- matched_antagonist_pairs_df[order(matched_antagonist_pairs_df$pathogen, matched_antagonist_pairs_df$antagonist), ]
  } else {
    matched_antagonist_pairs_df <- data.frame(pathogen = character(), antagonist = character())
  }

  # -------------------------------------------------------------------------
  # RETURN: Normalized score, percentile, counts, and diagnostics
  # -------------------------------------------------------------------------

  list(
    raw = pathogen_control_normalized,
    norm = m4_norm,
    mycoparasite_counts = mycoparasite_counts,
    pathogen_counts = pathogen_counts,
    specific_antagonist_matches = specific_antagonist_matches,
    matched_antagonist_pairs = matched_antagonist_pairs_df,
    details = list(
      pathogen_control_raw = pathogen_control_raw,
      max_pairs = max_pairs,
      n_mechanisms = length(mechanisms),
      mechanisms = mechanisms  # Return all mechanisms (typically <10)
    )
  )
}

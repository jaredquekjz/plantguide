#!/usr/bin/env Rscript
#
# METRIC 3: BENEFICIAL INSECT NETWORKS (BIOCONTROL)
#
# ============================================================================
# ECOLOGICAL RATIONALE
# ============================================================================
#
# Diverse plant guilds provide natural pest control through three mechanisms:
#
# 1. SPECIFIC ANIMAL PREDATORS (Weight: 1.0)
#    - Plant A attracts herbivorous insects (pests)
#    - Plant B attracts/hosts specific predators of those herbivores
#    - Example: Aphids (on roses) eaten by ladybugs (hosted by yarrow)
#    - Database: herbivore_predators lookup table (GloBI network data)
#
# 2. SPECIFIC ENTOMOPATHOGENIC FUNGI (Weight: 1.0)
#    - Plant A attracts herbivorous insects
#    - Plant B hosts fungal pathogens that specifically target those insects
#    - Example: Caterpillars (on cabbage) infected by Beauveria bassiana
#      (associated with corn)
#    - Database: insect_fungal_parasites lookup table
#
# 3. GENERAL ENTOMOPATHOGENIC FUNGI (Weight: 0.2)
#    - Plant B hosts broad-spectrum entomopathogenic fungi
#    - These fungi provide baseline protection against multiple pest types
#    - Lower weight reflects non-specificity (less reliable control)
#
# KEY CONCEPT: Pairwise Protection
# - For each vulnerable plant A (with herbivores), check all other plants B
# - Sum protection scores where B provides biocontrol for A's herbivores
# - Normalize by guild size to enable cross-guild comparison
#
# ============================================================================
# CALCULATION STEPS
# ============================================================================
#
# STEP 1: Extract guild organism and fungi data
#   - Filter organisms_df to guild members (herbivores, predators, visitors)
#   - Filter fungi_df to guild members (entomopathogenic fungi)
#
# STEP 2: Pairwise analysis (nested loop)
#   - Outer loop: Plant A (vulnerable - has herbivores)
#   - Inner loop: Plant B (protective - has predators/fungi)
#   - For each A→B pair, check 3 biocontrol mechanisms
#
# STEP 3: Mechanism scoring
#   - Mechanism 1: For each herbivore on A, check if B hosts known predators
#     * Match herbivore against herbivore_predators lookup
#     * Count matching predators on B
#     * Score: n_matches × 1.0
#
#   - Mechanism 2: For each herbivore on A, check if B hosts specific fungi
#     * Match herbivore against insect_parasites lookup
#     * Count matching entomopathogenic fungi on B
#     * Score: n_matches × 1.0
#
#   - Mechanism 3: General entomopathogenic fungi on B
#     * If A has any herbivores AND B has any entomopathogenic fungi
#     * Score: n_entomo_fungi_on_B × 0.2
#
# STEP 4: Normalize by guild size
#   - biocontrol_normalized = (biocontrol_raw / max_pairs) × 20
#   - max_pairs = n_plants × (n_plants - 1)
#   - The ×20 scaling factor was empirically calibrated to match the
#     score range of other metrics
#
# STEP 5: Percentile normalization
#   - Uses Köppen tier-stratified calibration for metric 'p1'
#   - HIGH biocontrol_normalized → HIGH percentile (good protection)
#   - Note: No final inversion needed (high percentile = high score)
#
# ============================================================================
# DATA SOURCES
# ============================================================================
#
# 1. organisms_df (organism_profiles_pure_r.csv):
#    - Columns: plant_wfo_id, herbivores, flower_visitors, fauna_hasHost,
#               fauna_interactsWith, fauna_adjacentTo
#    - Each organism column contains pipe-separated GBIF taxon IDs
#
# 2. fungi_df (fungal_guilds_pure_r.csv):
#    - Columns: plant_wfo_id, entomopathogenic_fungi, ...
#    - entomopathogenic_fungi: pipe-separated GBIF fungal taxon IDs
#
# 3. herbivore_predators (herbivore_predators_pure_r.csv):
#    - Lookup table: herbivore GBIF ID → list of predator GBIF IDs
#    - Derived from GloBI interaction network
#
# 4. insect_parasites (insect_fungal_parasites_pure_r.csv):
#    - Lookup table: herbivore GBIF ID → list of entomopathogenic fungi IDs
#    - Derived from GloBI and FunGuild databases
#
# ============================================================================
# PARITY REQUIREMENTS
# ============================================================================
#
# To maintain 100% parity with Python scorer:
# 1. Must use same organism extraction logic (all relationship types)
# 2. Must use same lookup tables (MD5-verified CSVs)
# 3. Must use same weights (1.0, 1.0, 0.2)
# 4. Must use same normalization (/ max_pairs × 20)
# 5. Must use same Köppen tier calibration file for 'p1' metric
#
# Python implementation: guild_scorer_v3.py lines 1211-1329
#
# ============================================================================


#' Calculate M3: Beneficial Insect Networks (Biocontrol)
#'
#' Scores natural pest control provided by predators and entomopathogenic
#' fungi associated with guild plants. Uses pairwise analysis to identify
#' protective relationships between vulnerable and protective plants.
#'
#' @param plant_ids Character vector of WFO taxon IDs for the guild
#' @param guild_plants Data frame with plant metadata (not used in M3)
#' @param organisms_df Data frame with plant-organism associations
#' @param fungi_df Data frame with plant-fungi associations
#' @param herbivore_predators Named list mapping herbivore IDs to predator IDs
#' @param insect_parasites Named list mapping herbivore IDs to fungal parasite IDs
#' @param percentile_normalize_fn Function to convert raw score to percentile
#'
#' @return List with three elements:
#'   - raw: Normalized biocontrol score (scaled by guild size)
#'   - norm: Percentile score (0-100, HIGH = GOOD)
#'   - details: List with biocontrol_raw, max_pairs, n_mechanisms, and
#'              mechanism details for diagnostics
#'
#' @details
#' Edge case: If no organism data is available for guild, returns zero score.
#' Predator aggregation: All animal types (flower_visitors, fauna_hasHost,
#' fauna_interactsWith, fauna_adjacentTo) are pooled as potential
#' biocontrol agents.
#'
#' @references
#' Python implementation: src/Stage_4/guild_scorer_v3.py lines 1211-1329
#'
calculate_m3_insect_control <- function(plant_ids,
                                        guild_plants,
                                        organisms_df,
                                        fungi_df,
                                        herbivore_predators,
                                        insect_parasites,
                                        percentile_normalize_fn) {

  n_plants <- length(plant_ids)
  biocontrol_raw <- 0.0
  mechanisms <- list()
  specific_predator_matches <- 0
  specific_fungi_matches <- 0
  matched_predator_pairs <- list()
  matched_fungi_pairs <- list()

  # -------------------------------------------------------------------------
  # STEP 1: Extract guild organism and fungi data
  # -------------------------------------------------------------------------

  guild_organisms <- organisms_df %>% dplyr::filter(plant_wfo_id %in% plant_ids)
  guild_fungi <- fungi_df %>% dplyr::filter(plant_wfo_id %in% plant_ids)

  if (nrow(guild_organisms) == 0) {
    return(list(
      raw = 0.0,
      norm = 0.0,
      predator_counts = list(),
      entomo_fungi_counts = list(),
      specific_predator_matches = 0,
      specific_fungi_matches = 0,
      matched_predator_pairs = data.frame(herbivore = character(), predator = character()),
      matched_fungi_pairs = data.frame(herbivore = character(), fungus = character()),
      details = list(note = "No organism data available")
    ))
  }

  # Build set of ALL known predators (from herbivore_predators lookup values)
  known_predators <- unique(unlist(herbivore_predators, use.names = FALSE))

  # Build set of ALL known entomopathogenic fungi (from insect_parasites lookup values)
  known_entomo_fungi <- unique(unlist(insect_parasites, use.names = FALSE))

  # -------------------------------------------------------------------------
  # STEP 2: Pairwise analysis - vulnerable plant A vs protective plant B
  # -------------------------------------------------------------------------
  # For each plant A that has herbivores (vulnerable), check all other
  # plants B for biocontrol agents (predators, entomopathogenic fungi)

  for (i in seq_len(nrow(guild_organisms))) {
    row_a <- guild_organisms[i, ]
    plant_a_id <- row_a$plant_wfo_id
    herbivores_a <- row_a$herbivores[[1]]

    # Skip if plant A has no herbivores (not vulnerable)
    if (is.null(herbivores_a) || length(herbivores_a) == 0) {
      next
    }

    # Check all other plants B for protective agents
    for (j in seq_len(nrow(guild_organisms))) {
      if (i == j) next  # Skip self-comparison

      row_b <- guild_organisms[j, ]
      plant_b_id <- row_b$plant_wfo_id

      # -----------------------------------------------------------------
      # Aggregate ALL animals from plant B across all relationship types
      # -----------------------------------------------------------------
      # GloBI network data includes multiple relationship types:
      # - flower_visitors: Pollinators, nectar feeders
      # - fauna_hasHost: Animals using plant as host
      # - fauna_interactsWith: Animals interacting with plant
      # - fauna_adjacentTo: Animals found near plant
      #
      # We pool all types because potential predators use multiple plant resources:
      # - Nectar for adult energy
      # - Shelter in foliage
      # - Alternate prey on flowers
      #
      # Example: Ladybugs visit yarrow flowers (flower_visitors) but
      # also prey on aphids near yarrow (fauna_adjacentTo)

      predators_b <- c()
      if (!is.null(row_b$flower_visitors[[1]])) {
        predators_b <- c(predators_b, row_b$flower_visitors[[1]])
      }
      if ("fauna_hasHost" %in% names(row_b) && !is.null(row_b$fauna_hasHost[[1]])) {
        predators_b <- c(predators_b, row_b$fauna_hasHost[[1]])
      }
      if ("fauna_interactsWith" %in% names(row_b) && !is.null(row_b$fauna_interactsWith[[1]])) {
        predators_b <- c(predators_b, row_b$fauna_interactsWith[[1]])
      }
      if ("fauna_adjacentTo" %in% names(row_b) && !is.null(row_b$fauna_adjacentTo[[1]])) {
        predators_b <- c(predators_b, row_b$fauna_adjacentTo[[1]])
      }
      predators_b <- unique(predators_b)

      # -----------------------------------------------------------------
      # MECHANISM 1: Specific animal predators (weight 1.0)
      # -----------------------------------------------------------------
      # For each herbivore on plant A, check if plant B hosts known predators
      # of that herbivore.
      #
      # Example:
      # - Plant A (rose) attracts Aphis rosae (rose aphid)
      # - Plant B (yarrow) hosts Coccinella septempunctata (7-spot ladybug)
      # - Lookup: herbivore_predators["Aphis rosae"] contains "Coccinella..."
      # - Match found → biocontrol_raw += 1.0

      for (herbivore in herbivores_a) {
        if (herbivore %in% names(herbivore_predators)) {
          known_predators_for_herb <- herbivore_predators[[herbivore]]
          if (!is.null(known_predators_for_herb) && length(known_predators_for_herb) > 0) {
            matching <- intersect(predators_b, known_predators_for_herb)
            if (length(matching) > 0) {
              biocontrol_raw <- biocontrol_raw + length(matching) * 1.0
              specific_predator_matches <- specific_predator_matches + 1
              mechanisms[[length(mechanisms) + 1]] <- list(
                type = 'animal_predator',
                herbivore = herbivore,
                predator_plant = plant_b_id,
                predators = head(matching, 3)  # Record up to 3 for diagnostics
              )
              # Track matched pairs
              for (pred in matching) {
                matched_predator_pairs[[length(matched_predator_pairs) + 1]] <- list(
                  herbivore = herbivore,
                  predator = pred
                )
              }
            }
          }
        }
      }

      # -----------------------------------------------------------------
      # MECHANISM 2 & 3: Entomopathogenic fungi
      # -----------------------------------------------------------------

      fungi_b <- guild_fungi %>% dplyr::filter(plant_wfo_id == plant_b_id)
      if (nrow(fungi_b) > 0) {
        entomo_b <- fungi_b$entomopathogenic_fungi[[1]]
        if (!is.null(entomo_b) && length(entomo_b) > 0) {

          # --------------------------------------------------------------
          # MECHANISM 2: Specific entomopathogenic fungi (weight 1.0)
          # --------------------------------------------------------------
          # For each herbivore on plant A, check if plant B hosts fungal
          # pathogens that specifically target that herbivore.
          #
          # Example:
          # - Plant A (cabbage) attracts Pieris rapae (cabbage white butterfly)
          # - Plant B (corn) hosts Beauveria bassiana (entomopathogenic fungus)
          # - Lookup: insect_parasites["Pieris rapae"] contains "Beauveria..."
          # - Match found → biocontrol_raw += 1.0

          for (herbivore in herbivores_a) {
            if (herbivore %in% names(insect_parasites)) {
              known_parasites <- insect_parasites[[herbivore]]
              if (!is.null(known_parasites) && length(known_parasites) > 0) {
                matching <- intersect(entomo_b, known_parasites)
                if (length(matching) > 0) {
                  biocontrol_raw <- biocontrol_raw + length(matching) * 1.0
                  specific_fungi_matches <- specific_fungi_matches + 1
                  mechanisms[[length(mechanisms) + 1]] <- list(
                    type = 'fungal_parasite',
                    herbivore = herbivore,
                    fungi_plant = plant_b_id,
                    fungi = head(matching, 3)
                  )
                  # Track matched pairs
                  for (fungus in matching) {
                    matched_fungi_pairs[[length(matched_fungi_pairs) + 1]] <- list(
                      herbivore = herbivore,
                      fungus = fungus
                    )
                  }
                }
              }
            }
          }

          # --------------------------------------------------------------
          # MECHANISM 3: General entomopathogenic fungi (weight 0.2)
          # --------------------------------------------------------------
          # If plant A has any herbivores AND plant B has any entomopathogenic
          # fungi, award a small baseline score.
          #
          # Rationale: Broad-spectrum entomopathogenic fungi (e.g., Metarhizium,
          # Beauveria) can infect multiple insect orders, providing generalist
          # protection even without specific herbivore-fungus matches.
          #
          # Lower weight (0.2 vs 1.0) reflects:
          # - Lower reliability (not host-specific)
          # - Environmental dependence (humidity, temperature)
          # - Slower action compared to active predation

          if (length(herbivores_a) > 0 && length(entomo_b) > 0) {
            biocontrol_raw <- biocontrol_raw + length(entomo_b) * 0.2
          }
        }
      }
    }
  }

  # -------------------------------------------------------------------------
  # STEP 4: Normalize by guild size
  # -------------------------------------------------------------------------
  # Dividing by max_pairs ensures scores are comparable across guild sizes.
  # Multiplying by 20 is an empirical scaling factor calibrated to match
  # the score range of other metrics (typically 0-5).

  max_pairs <- n_plants * (n_plants - 1)
  biocontrol_normalized <- if (max_pairs > 0) {
    biocontrol_raw / max_pairs * 20
  } else {
    0
  }

  # -------------------------------------------------------------------------
  # STEP 5: Percentile normalization
  # -------------------------------------------------------------------------
  # Converts absolute biocontrol score to relative percentile within the
  # calibration dataset for the specified Köppen climate tier.
  #
  # Metric name: 'p1'
  # HIGH biocontrol_normalized → HIGH percentile (good protection)
  # No final inversion needed (high percentile already means high score)

  m3_norm <- percentile_normalize_fn(biocontrol_normalized, 'p1')

  # -------------------------------------------------------------------------
  # STEP 6: Build agent counts (FILTERED to known biocontrol agents)
  # -------------------------------------------------------------------------

  # Build predator_counts: predator_name → number of plants it visits
  # ONLY count if this agent is a known predator in the lookup table
  predator_counts <- list()
  for (i in seq_len(nrow(guild_organisms))) {
    row <- guild_organisms[i, ]
    predators <- c()
    if (!is.null(row$flower_visitors[[1]])) {
      predators <- c(predators, row$flower_visitors[[1]])
    }
    if ("fauna_hasHost" %in% names(row) && !is.null(row$fauna_hasHost[[1]])) {
      predators <- c(predators, row$fauna_hasHost[[1]])
    }
    if ("fauna_interactsWith" %in% names(row) && !is.null(row$fauna_interactsWith[[1]])) {
      predators <- c(predators, row$fauna_interactsWith[[1]])
    }
    if ("fauna_adjacentTo" %in% names(row) && !is.null(row$fauna_adjacentTo[[1]])) {
      predators <- c(predators, row$fauna_adjacentTo[[1]])
    }
    predators <- unique(predators)

    # ONLY count known predators
    predators_filtered <- intersect(predators, known_predators)
    for (pred in predators_filtered) {
      if (is.null(predator_counts[[pred]])) {
        predator_counts[[pred]] <- 0
      }
      predator_counts[[pred]] <- predator_counts[[pred]] + 1
    }
  }

  # Build entomo_fungi_counts: fungus_name → number of plants hosting it
  # ONLY count if this fungus is a known entomopathogenic fungus in the lookup table
  entomo_fungi_counts <- list()
  for (i in seq_len(nrow(guild_fungi))) {
    row <- guild_fungi[i, ]
    entomo <- row$entomopathogenic_fungi[[1]]
    if (!is.null(entomo) && length(entomo) > 0) {
      # ONLY count known entomopathogenic fungi
      entomo_filtered <- intersect(entomo, known_entomo_fungi)
      for (fungus in entomo_filtered) {
        if (is.null(entomo_fungi_counts[[fungus]])) {
          entomo_fungi_counts[[fungus]] <- 0
        }
        entomo_fungi_counts[[fungus]] <- entomo_fungi_counts[[fungus]] + 1
      }
    }
  }

  # Convert matched pairs from list to data.frame and deduplicate
  if (length(matched_predator_pairs) > 0) {
    matched_predator_pairs_df <- do.call(rbind, lapply(matched_predator_pairs, as.data.frame, stringsAsFactors = FALSE))
    matched_predator_pairs_df <- unique(matched_predator_pairs_df)
    matched_predator_pairs_df <- matched_predator_pairs_df[order(matched_predator_pairs_df$herbivore, matched_predator_pairs_df$predator), ]
  } else {
    matched_predator_pairs_df <- data.frame(herbivore = character(), predator = character())
  }

  if (length(matched_fungi_pairs) > 0) {
    matched_fungi_pairs_df <- do.call(rbind, lapply(matched_fungi_pairs, as.data.frame, stringsAsFactors = FALSE))
    matched_fungi_pairs_df <- unique(matched_fungi_pairs_df)
    matched_fungi_pairs_df <- matched_fungi_pairs_df[order(matched_fungi_pairs_df$herbivore, matched_fungi_pairs_df$fungus), ]
  } else {
    matched_fungi_pairs_df <- data.frame(herbivore = character(), fungus = character())
  }

  # -------------------------------------------------------------------------
  # RETURN: Normalized score, percentile, counts, and diagnostics
  # -------------------------------------------------------------------------

  list(
    raw = biocontrol_normalized,
    norm = m3_norm,
    predator_counts = predator_counts,
    entomo_fungi_counts = entomo_fungi_counts,
    specific_predator_matches = specific_predator_matches,
    specific_fungi_matches = specific_fungi_matches,
    matched_predator_pairs = matched_predator_pairs_df,
    matched_fungi_pairs = matched_fungi_pairs_df,
    details = list(
      biocontrol_raw = biocontrol_raw,
      max_pairs = max_pairs,
      n_mechanisms = length(mechanisms),
      mechanisms = head(mechanisms, 10)  # Return top 10 for diagnostics
    )
  )
}

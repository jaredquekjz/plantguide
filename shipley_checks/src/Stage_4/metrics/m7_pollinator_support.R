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
#   - Uses ONLY strict pollinators (NOT flower_visitors - contaminated)
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
# - Column: plant_wfo_id, pollinators (ONLY - NOT flower_visitors)
# - Contains pipe-separated GBIF animal taxon IDs
# - Derived from GloBI interaction network (interactionTypeName == 'pollinates')
# - Includes only strict pollinators (bees, specialized flies, hummingbirds)
# - DATA QUALITY NOTE: flower_visitors column is contaminated with:
#   * Herbivore pests (mites, caterpillars) feeding on flowers
#   * Pathogenic fungi growing on flowers
#   * Other non-pollinator organisms found on flowers
#
# ============================================================================
# PARITY REQUIREMENTS
# ============================================================================
#
# To maintain 100% parity with Python scorer:
# 1. Must use same count_shared_organisms logic (≥2 plants threshold)
# 2. Must use same quadratic weighting formula: (count / n_plants)²
# 3. Must use ONLY pollinators column (NOT flower_visitors - contaminated)
# 4. Must use same Köppen tier calibration file for 'p6' metric
#
# Python implementation: guild_scorer_v3.py lines 1645-1674
# NOTE: Python version also updated to use only 'pollinators' column
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
  # Uses ONLY strict pollinators (NOT flower_visitors - contaminated with herbivores/fungi)
  shared_pollinators <- count_shared_organisms_fn(
    organisms_df, plant_ids,
    'pollinators'  # ONLY verified pollinators
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

  # -------------------------------------------------------------------------
  # STEP 4: Build pollinator counts and categorization (for network profile)
  # -------------------------------------------------------------------------
  # Build pollinator_counts: pollinator_name → number of plants it visits
  # Also categorize each pollinator by taxonomic group

  categorize_pollinator <- function(name) {
    # Convert to lowercase for case-insensitive matching
    name_lower <- tolower(name)

    # Honey Bees (Apis) - most specific first
    if (grepl("\\bapis\\b", name_lower)) {
      return("Honey Bees")
    }
    # Bumblebees (Bombus)
    if (grepl("bombus", name_lower)) {
      return("Bumblebees")
    }
    # Hover Flies (Syrphidae) - before general "fly"
    if (grepl("syrph|episyrphus|eristalis|eupeodes|melanostoma|platycheirus|sphaerophoria|cheilosia", name_lower)) {
      return("Hover Flies")
    }
    # Mosquitoes (Culicidae) - before general "fly"
    if (grepl("aedes|culex|anopheles|culiseta|mosquito", name_lower)) {
      return("Mosquitoes")
    }
    # Muscid Flies (Muscidae/Anthomyiidae) - before general "fly"
    if (grepl("anthomyia|\\bmusca\\b|fannia|phaonia|delia|drymeia|muscidae", name_lower)) {
      return("Muscid Flies")
    }
    # Solitary Bees (after Apis/Bombus, before general "bee")
    if (grepl("andrena|lasioglossum|halictus|osmia|megachile|ceratina|xylocopa|anthophora|anthidium|colletes|nomada|agapostemon|amegilla|trigona|melipona|eulaema|epicharis|augochlora|chelostoma|tetralonia|bee", name_lower)) {
      return("Solitary Bees")
    }
    # Other Flies (catch remaining Diptera)
    if (grepl("fly|empis|calliphora|scathophaga|drosophila|bibio|diptera|rhamphomyia", name_lower)) {
      return("Other Flies")
    }
    # Pollen Beetles (before general "beetle")
    if (grepl("meligethes|brassicogethes|oedemera", name_lower)) {
      return("Pollen Beetles")
    }
    # Other Beetles
    if (grepl("beetle|cetonia|trichius|anaspis|coleoptera", name_lower)) {
      return("Other Beetles")
    }
    # Butterflies (Lepidoptera - Rhopalocera)
    if (grepl("papilio|pieris|vanessa|danaus|colias|lycaena|polyommatus|aglais|coenonympha|erebia|gonepteryx|anthocharis|maniola|butterfly", name_lower)) {
      return("Butterflies")
    }
    # Moths (Lepidoptera - Heterocera)
    if (grepl("moth|sphinx|manduca|hyles|macroglossum", name_lower)) {
      return("Moths")
    }
    # Wasps (Hymenoptera - non-Apoidea)
    if (grepl("wasp|vespula|vespa|polistes|dolichovespula", name_lower)) {
      return("Wasps")
    }
    # Birds
    if (grepl("bird|hummingbird|trochilidae|amazilia|phaethornis|coereba|anthracothorax|\\baves\\b", name_lower)) {
      return("Birds")
    }
    # Bats
    if (grepl("bat|chiroptera|pteropus|artibeus", name_lower)) {
      return("Bats")
    }

    return("Other")
  }

  # Build pollinator counts from organisms_df
  guild_organisms <- organisms_df %>% dplyr::filter(plant_wfo_id %in% plant_ids)
  pollinator_counts <- list()
  pollinator_category_map <- list()

  for (i in seq_len(nrow(guild_organisms))) {
    row <- guild_organisms[i, ]

    # Aggregate from ONLY pollinators column (NOT flower_visitors - contaminated)
    col_val <- row[['pollinators']]
    if (is.list(col_val)) col_val <- col_val[[1]]
    if (!is.null(col_val) && length(col_val) > 0) {
      for (pollinator in col_val) {
        if (is.null(pollinator_counts[[pollinator]])) {
          pollinator_counts[[pollinator]] <- 0
          pollinator_category_map[[pollinator]] <- categorize_pollinator(pollinator)
        }
        pollinator_counts[[pollinator]] <- pollinator_counts[[pollinator]] + 1
      }
    }
  }

  list(
    raw = p7_raw,
    norm = m7_norm,
    pollinator_counts = pollinator_counts,
    pollinator_category_map = pollinator_category_map,
    details = list(
      n_shared_pollinators = length(shared_pollinators),
      pollinators = names(shared_pollinators)[1:min(5, length(shared_pollinators))]
    )
  )
}

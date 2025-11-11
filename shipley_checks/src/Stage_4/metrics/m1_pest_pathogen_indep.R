#!/usr/bin/env Rscript
#
# METRIC 1: PEST & PATHOGEN INDEPENDENCE
#
# ============================================================================
# ECOLOGICAL RATIONALE
# ============================================================================
#
# Phylogenetically diverse plant guilds reduce pest/pathogen risk through
# multiple mechanisms:
#
# 1. HOST SPECIFICITY: Most pests and pathogens are host-specific at the
#    genus or family level. Phylogenetically distant plants share fewer
#    specialist enemies.
#
# 2. DILUTION EFFECT: When vulnerable plants are mixed with non-host plants,
#    pest/pathogen populations are diluted across the landscape, reducing
#    transmission and reproduction rates.
#
# 3. ASSOCIATIONAL RESISTANCE: Non-host plants can physically or chemically
#    interfere with pest foraging, masking host plant volatiles or providing
#    refuge for natural enemies.
#
# KEY METRIC: Faith's Phylogenetic Diversity (PD)
# - Sums branch lengths spanning all guild members on a phylogenetic tree
# - Higher PD = greater evolutionary distance = fewer shared enemies
# - Units: millions of years of evolutionary divergence
#
# ============================================================================
# CALCULATION STEPS
# ============================================================================
#
# STEP 1: Calculate Faith's PD
#   - Uses C++ CompactTree binary (708× faster than R picante)
#   - Input: Vector of WFO taxon IDs
#   - Output: Total branch length in millions of years
#
# STEP 2: Transform to pest risk score
#   - Formula: pest_risk_raw = exp(-k × faiths_pd)
#   - k = 0.001 (decay constant)
#   - Interpretation:
#     * LOW faiths_pd (closely related) → HIGH pest_risk_raw (bad)
#     * HIGH faiths_pd (diverse) → LOW pest_risk_raw (good)
#
# STEP 3: Normalize to percentile (0-100 scale)
#   - Uses Köppen tier-stratified calibration parameters
#   - LOW pest_risk_raw → LOW percentile (good diversity)
#   - HIGH pest_risk_raw → HIGH percentile (bad diversity)
#   - Note: invert = FALSE (no inversion during normalization)
#
# STEP 4: Convert to display score
#   - Final score: 100 - percentile
#   - This inverts the scale so HIGH = GOOD for display
#   - Matches Python guild_scorer_v3.py line 406:
#     'pest_pathogen_indep': 100 - percentiles['m1']
#
# ============================================================================
# PARITY REQUIREMENTS
# ============================================================================
#
# To maintain 100% parity with Python scorer:
# 1. Must use same Faith's PD calculator (C++ CompactTree binary)
# 2. Must use same exponential transformation (k = 0.001)
# 3. Must use same calibration file:
#    shipley_checks/stage4/normalization_params_7plant.json
# 4. Must use same Köppen tier (e.g., tier_3_humid_temperate)
# 5. Must apply same percentile normalization (invert = FALSE)
# 6. Must apply same final transformation (100 - percentile)
#
# ============================================================================


#' Calculate M1: Pest & Pathogen Independence
#'
#' Scores phylogenetic diversity using Faith's PD as a proxy for pest/pathogen
#' risk reduction. Higher diversity (more evolutionary distance) = lower risk.
#'
#' @param plant_ids Character vector of WFO taxon IDs for the guild
#' @param guild_plants Data frame with plant metadata (not used in M1)
#' @param phylo_calculator PhyloPDCalculator R6 object with calculate_pd() method
#' @param percentile_normalize_fn Function to convert raw score to percentile
#'
#' @return List with three elements:
#'   - raw: Raw pest risk score (0-1, LOW = good)
#'   - norm: Normalized percentile (0-100, matches Python before inversion)
#'   - details: List with faiths_pd, k parameter, and formula reference
#'
#' @details
#' Edge case: Single plant guilds return maximum risk (raw = 1.0, norm = 0.0)
#' because there is no phylogenetic diversity by definition.
#'
#' @references
#' Python implementation: src/Stage_4/guild_scorer_v3.py lines 1612-1629
#'
calculate_m1_pest_pathogen_indep <- function(plant_ids,
                                             guild_plants,
                                             phylo_calculator,
                                             percentile_normalize_fn) {

  # -------------------------------------------------------------------------
  # EDGE CASE: Single plant guild
  # -------------------------------------------------------------------------
  # A single plant has zero phylogenetic diversity (no other plants to compare)
  # Therefore, maximum pest risk (no dilution effect, no associational resistance)

  if (length(plant_ids) < 2) {
    return(list(
      raw = 1.0,   # Maximum risk
      norm = 0.0,  # Minimum percentile (will become 100 after display inversion)
      details = list(
        faiths_pd = 0,
        note = "Single plant - no phylogenetic diversity"
      )
    ))
  }

  # -------------------------------------------------------------------------
  # STEP 1: Calculate Faith's Phylogenetic Diversity (PD)
  # -------------------------------------------------------------------------
  # Faith's PD: Sum of all phylogenetic branch lengths connecting guild members
  #
  # Example: For a guild with 3 plants from different families:
  #   Plant A (Rosaceae) ----50 MY---- Common Ancestor 1
  #   Plant B (Fabaceae)  ----40 MY----/                \
  #   Plant C (Poaceae)   ----60 MY-------- Common Ancestor 2
  #
  # Faith's PD = 50 + 40 + 60 + (branch to Common Ancestor 2) = ~200 MY
  #
  # Higher PD = plants are more evolutionarily distant = fewer shared pests

  faiths_pd <- phylo_calculator$calculate_pd(plant_ids, use_wfo_ids = TRUE)

  # -------------------------------------------------------------------------
  # STEP 2: Transform PD to pest risk score (exponential decay)
  # -------------------------------------------------------------------------
  # Formula: pest_risk_raw = exp(-k × faiths_pd)
  #
  # k = 0.001: Decay constant (controls sensitivity to PD)
  #
  # Intuition:
  # - faiths_pd = 0 MY (same species)     → pest_risk = 1.00 (maximum risk)
  # - faiths_pd = 500 MY (different orders) → pest_risk = 0.61
  # - faiths_pd = 1000 MY (very diverse)   → pest_risk = 0.37
  #
  # The exponential transformation ensures:
  # 1. Diminishing returns: Each additional MY of diversity has smaller impact
  # 2. Never reaches zero: Even maximum diversity has some residual risk
  # 3. Biological realism: Matches observed pest/pathogen spillover patterns

  k <- 0.001
  pest_risk_raw <- exp(-k * faiths_pd)

  # -------------------------------------------------------------------------
  # STEP 3: Normalize to percentile using Köppen-stratified calibration
  # -------------------------------------------------------------------------
  # Converts absolute pest risk (0-1) to relative percentile (0-100)
  # within the calibration dataset for the specified Köppen climate tier
  #
  # Example: If pest_risk_raw = 0.5 falls at the 30th percentile of the
  # calibration distribution, then m1_norm = 30.0
  #
  # KEY: invert = FALSE means no inversion during normalization
  # LOW pest_risk_raw → LOW percentile (good diversity)
  # HIGH pest_risk_raw → HIGH percentile (bad diversity)
  #
  # The final display inversion happens in score_guild() with: 100 - m1_norm

  m1_norm <- percentile_normalize_fn(pest_risk_raw, 'm1', invert = FALSE)

  # -------------------------------------------------------------------------
  # RETURN: Raw score, normalized percentile, and calculation details
  # -------------------------------------------------------------------------

  list(
    raw = pest_risk_raw,
    norm = m1_norm,
    details = list(
      faiths_pd = faiths_pd,
      k = k,
      formula = "exp(-k × faiths_pd)",
      interpretation = glue::glue(
        "Faith's PD = {round(faiths_pd, 1)} MY; ",
        "Pest risk = {round(pest_risk_raw, 3)}; ",
        "Percentile = {round(m1_norm, 1)}; ",
        "Display score = {round(100 - m1_norm, 1)}"
      )
    )
  )
}

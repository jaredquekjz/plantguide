#!/usr/bin/env Rscript
#
# METRIC 6: STRUCTURAL DIVERSITY (VERTICAL STRATIFICATION)
#
# ============================================================================
# ECOLOGICAL RATIONALE
# ============================================================================
#
# Vertical stratification creates niche partitioning that:
#
# 1. REDUCES COMPETITION:
#    - Tall plants access upper canopy light
#    - Mid-height plants fill middle layer
#    - Short plants exploit ground layer
#    - Different root depths reduce below-ground competition
#
# 2. ENHANCES MICROCLIMATE DIVERSITY:
#    - Canopy creates shade, humidity gradients
#    - Wind protection for understory
#    - Temperature buffering
#
# 3. INCREASES BIODIVERSITY:
#    - More habitat niches → more associated organisms
#    - Different flowering times across strata
#    - Structural complexity supports wildlife
#
# CRITICAL CONSTRAINT: Light Compatibility
# Stratification only works if short plants can tolerate shade from tall plants.
# A sun-loving short plant under a dense canopy = INVALID stratification.
#
# ============================================================================
# CALCULATION STEPS
# ============================================================================
#
# COMPONENT 1: Light-Validated Height Stratification (70% weight)
#
# STEP 1: Sort plants by height
#
# STEP 2: For each tall-short pair with height difference >2m:
#   - Extract short plant's light preference (EIVE-L scale 1-9)
#   - Categorize light requirement:
#     * L < 3.2: Shade-adapted (can thrive under canopy) → VALID ×1.0
#     * L > 7.47: Sun-loving (will be shaded out) → INVALID (penalty)
#     * L 3.2-7.47: Flexible (partial tolerance) → VALID ×0.6
#     * L missing: Conservative assumption → VALID ×0.5
#
# STEP 3: Calculate stratification quality
#   - valid_stratification = Σ(height_diff × light_weight)
#   - invalid_stratification = Σ(height_diff) for sun-loving shorts
#   - stratification_quality = valid / (valid + invalid)
#   - Range: 0 (all invalid) to 1 (all valid)
#
# COMPONENT 2: Growth Form Diversity (30% weight)
#
# STEP 4: Count unique growth forms (tree, shrub, herb, vine, grass, etc.)
#   - form_diversity = (n_unique_forms - 1) / 5
#   - Assumes maximum 6 distinct forms
#   - Rationale: Different forms occupy different niches even at same height
#
# STEP 5: Combined score
#   - p6_raw = 0.7 × stratification_quality + 0.3 × form_diversity
#
# STEP 6: Percentile normalization
#   - Uses Köppen tier-stratified calibration for metric 'p5'
#   - HIGH p6_raw → HIGH percentile (good structural diversity)
#
# ============================================================================
# EIVE LIGHT SCALE INTERPRETATION
# ============================================================================
#
# 1: Deep shade (<1% full sunlight) - forest floor specialists
# 2: Moderate shade (1-3% full sunlight) - understory herbs
# 3: Moderate shade (3-10% full sunlight) - shade-tolerant perennials
# 4: Semi-shade (10-20% full sunlight) - woodland edge species
# 5: Semi-shade (20-30% full sunlight) - partial shade plants
# 6: Semi-shade (30-40% full sunlight) - flexible species
# 7: Half-light (40-50% full sunlight) - sun-preferring but shade-tolerant
# 8: Full light (50-80% full sunlight) - sun-requiring plants
# 9: Full light (>80% full sunlight) - sun-obligate species
#
# ============================================================================
# PARITY REQUIREMENTS
# ============================================================================
#
# To maintain 100% parity with Python scorer:
# 1. Must use same light preference thresholds (3.2, 7.47)
# 2. Must use same height difference threshold (>2m)
# 3. Must use same light weights (1.0, 0.6, 0.5, 0.0)
# 4. Must use same stratification quality formula
# 5. Must use same form diversity calculation
# 6. Must use same weights (0.7, 0.3)
# 7. Must use same Köppen tier calibration file for 'p5' metric
#
# Python implementation: guild_scorer_v3.py lines 1562-1643
#
# ============================================================================


#' Calculate M6: Structural Diversity
#'
#' Scores vertical stratification quality and growth form diversity.
#' Validates that height differences are compatible with light preferences.
#'
#' @param guild_plants Data frame with columns:
#'   - height_m: Plant height in meters
#'   - light_pref: EIVE Light preference (1-9 scale)
#'   - try_growth_form: Growth form (tree, shrub, herb, etc.)
#' @param percentile_normalize_fn Function to convert raw score to percentile
#'
#' @return List with three elements:
#'   - raw: Combined stratification + form diversity (0-1 scale)
#'   - norm: Percentile score (0-100, HIGH = GOOD)
#'   - details: List with height_range, n_forms, forms, stratification_quality,
#'              form_diversity
#'
calculate_m6_structural_diversity <- function(guild_plants,
                                              percentile_normalize_fn) {

  forms <- guild_plants$try_growth_form[!is.na(guild_plants$try_growth_form)]

  # COMPONENT 1: Light-validated height stratification (70%)
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

  # COMPONENT 2: Form diversity (30%)
  n_forms <- length(unique(forms))
  form_diversity <- if (n_forms > 0) (n_forms - 1) / 5 else 0  # 6 forms max

  # Combined (70% light-validated height, 30% form)
  p6_raw <- 0.7 * stratification_quality + 0.3 * form_diversity

  # Percentile normalize
  m6_norm <- percentile_normalize_fn(p6_raw, 'p5')

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
}

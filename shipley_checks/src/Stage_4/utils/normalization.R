#!/usr/bin/env Rscript
#
# NORMALIZATION UTILITIES
#
# ============================================================================
# PURPOSE
# ============================================================================
#
# Converts raw metric scores to percentiles using Köppen climate tier-stratified
# calibration parameters. This enables:
#
# 1. CROSS-METRIC COMPARABILITY:
#    - Different metrics have different scales (e.g., Faith's PD: 0-2000 MY,
#      conflict density: 0-2, pollinator overlap: 0-5)
#    - Percentile normalization maps all to common 0-100 scale
#
# 2. CLIMATE-APPROPRIATE BASELINES:
#    - Plants in humid_temperate zones have different typical ranges than
#      plants in arid or tropical zones
#    - Tier-stratified calibration ensures fair comparison within climate context
#
# 3. NON-LINEAR TRANSFORMATIONS:
#    - Linear interpolation between calibration percentiles preserves
#      distribution shape while mapping to 0-100 scale
#
# ============================================================================
# CALIBRATION FILE FORMAT
# ============================================================================
#
# JSON structure (normalization_params_7plant.json):
# {
#   "tier_3_humid_temperate": {
#     "m1": {  // Metric name
#       "p1": 0.5234,   // 1st percentile value
#       "p5": 0.5789,   // 5th percentile value
#       "p10": 0.6123,  // 10th percentile value
#       ...
#       "p99": 0.9876   // 99th percentile value
#     },
#     "n4": { ... },  // Conflict density metric
#     "p1": { ... },  // Biocontrol metric
#     ...
#   },
#   "tier_1_tropical": { ... },
#   ...
# }
#
# ============================================================================
# LINEAR INTERPOLATION ALGORITHM
# ============================================================================
#
# Given raw_value = 0.65 and metric "m1":
#
# 1. Load calibration percentiles: [1, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99]
# 2. Load corresponding values: [0.52, 0.58, 0.61, 0.64, 0.68, ...]
# 3. Find bracketing interval: 0.64 (p20) ≤ 0.65 < 0.68 (p30)
# 4. Calculate fraction: (0.65 - 0.64) / (0.68 - 0.64) = 0.25
# 5. Interpolate percentile: 20 + 0.25 × (30 - 20) = 22.5
# 6. Return: 22.5 percentile
#
# ============================================================================
# INVERSION LOGIC
# ============================================================================
#
# Some metrics have inverted interpretation:
# - M1 (pest risk): LOW raw value = GOOD (high diversity)
# - M2 (conflicts): LOW raw value = GOOD (low conflicts)
#
# When invert = TRUE:
# - After interpolation, apply: percentile = 100 - percentile
# - This flips the scale so HIGH percentile = GOOD
#
# However, in practice we use invert = FALSE for both M1 and M2,
# and apply the inversion in score_guild() with: 100 - percentile
# This matches Python implementation exactly.
#
# ============================================================================
# PARITY REQUIREMENTS
# ============================================================================
#
# To maintain 100% parity with Python scorer:
# 1. Must use same calibration files
# 2. Must use same interpolation algorithm (linear between percentiles)
# 3. Must handle edge cases identically (below p1, above p99)
# 4. Must use same default return value (50.0) for missing data
#
# Python implementation: guild_scorer_v3.py lines 334-391 (_raw_to_percentile)
#
# ============================================================================


#' Percentile normalize a raw score using linear interpolation
#'
#' Converts an absolute raw score to a relative percentile (0-100) using
#' Köppen climate tier-stratified calibration parameters.
#'
#' @param raw_value Numeric raw score from metric calculation
#' @param metric_name Character metric identifier ('m1', 'n4', 'p1', etc.)
#' @param calibration_params List with tier → metric → percentile structure
#' @param climate_tier Character Köppen tier identifier (e.g., 'tier_3_humid_temperate')
#' @param invert Logical. If TRUE, invert percentile scale (100 - percentile)
#'
#' @return Numeric percentile value (0-100)
#'
#' @details
#' Uses linear interpolation between calibration percentiles.
#' Edge cases:
#' - raw_value ≤ p1 → return 0.0 (or 100.0 if inverted)
#' - raw_value ≥ p99 → return 100.0 (or 0.0 if inverted)
#' - Missing calibration → return 50.0 (neutral)
#'
percentile_normalize <- function(raw_value,
                                 metric_name,
                                 calibration_params,
                                 climate_tier,
                                 invert = FALSE) {

  # Get calibration percentiles for this tier and metric
  tier_params <- calibration_params[[climate_tier]]
  if (is.null(tier_params)) {
    warning(glue::glue("No calibration params for tier: {climate_tier}"))
    return(50.0)
  }

  metric_params <- tier_params[[metric_name]]
  if (is.null(metric_params)) {
    warning(glue::glue("No calibration params for metric: {metric_name}"))
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
    warning(glue::glue("No valid calibration values for metric: {metric_name}"))
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

      # Handle inversion (for metrics where low raw = good)
      if (invert) {
        percentile <- 100.0 - percentile
      }

      return(percentile)
    }
  }

  # Fallback (should not reach here)
  return(50.0)
}


#' Convert raw CSR score to percentile using global calibration
#'
#' Unlike guild metrics (tier-stratified), CSR uses GLOBAL percentiles
#' because conflicts are within-guild comparisons, not cross-guild.
#'
#' @param raw_value Numeric raw CSR score (0-100)
#' @param strategy Character strategy identifier ('c', 's', or 'r')
#' @param csr_percentiles List with strategy → percentile structure
#'
#' @return Numeric percentile value (0-100)
#'
#' @details
#' Fallback behavior (if csr_percentiles is NULL):
#' - C strategy: raw ≥ 60 → 100, else 50
#' - S strategy: raw ≥ 60 → 100, else 50
#' - R strategy: raw ≥ 50 → 100, else 50
#'
#' Python implementation: guild_scorer_v3.py lines 242-284 (_csr_to_percentile)
#'
csr_to_percentile <- function(raw_value, strategy, csr_percentiles = NULL) {

  # Check if we have CSR percentile calibration data
  if (is.null(csr_percentiles)) {
    # Fallback to fixed threshold behavior (matches Python lines 251-257)
    if (strategy == 'c') {
      return(if (raw_value >= 60) 100 else 50)
    } else if (strategy == 's') {
      return(if (raw_value >= 60) 100 else 50)
    } else {  # 'r'
      return(if (raw_value >= 50) 100 else 50)
    }
  }

  params <- csr_percentiles[[strategy]]
  if (is.null(params)) {
    warning(glue::glue("No CSR calibration params for strategy: {strategy}"))
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

# ==============================================================================
# CATEGORIZATION UTILITY MODULE
# ==============================================================================
#
# PURPOSE:
#   Categorical classification functions for plant traits, strategies, and
#   ecological attributes. Converts continuous/binary data to user-friendly
#   categories for encyclopedia text generation.
#
# DEPENDENCIES:
#   - dplyr
#
# ==============================================================================

library(dplyr)

# ==============================================================================
# CSR STRATEGY CATEGORIZATION
# ==============================================================================

#' Determine Dominant CSR Strategy
#'
#' Classifies plant into primary CSR category based on C, S, R scores.
#' Uses threshold logic to identify dominant strategy or mixed strategies.
#'
#' @param C Competitor score (0-1)
#' @param S Stress-tolerator score (0-1)
#' @param R Ruderal score (0-1)
#' @return Character: one of "C", "S", "R", "CS", "CR", "SR", "CSR", or NA
#'
#' @details
#' ALGORITHM:
#'   1. Single strategy if one score > 0.6 and others < 0.3
#'   2. Binary mix if two scores > 0.35 and third < 0.25
#'   3. Ternary mix (CSR) if no single or binary dominance
#'   4. Return NA if any score is NA
#'
#' RATIONALE:
#'   Thresholds based on Grime's CSR triangle partitioning where
#'   corner strategies occupy ~30% of triangle, edges ~20%, center ~10%
#'
#' @examples
#' get_csr_category(0.8, 0.1, 0.1)  # "C" - Competitor
#' get_csr_category(0.4, 0.5, 0.1)  # "CS" - Competitor/Stress-tolerator
#' get_csr_category(0.35, 0.35, 0.3) # "CSR" - Generalist
#'
#' @export
get_csr_category <- function(C, S, R) {

  # STEP 1: Handle missing values
  if (any(is.na(c(C, S, R)))) {
    return(NA_character_)
  }

  # STEP 2: Check for single-strategy dominance
  # RATIONALE: Clear dominance when score > 0.6 and others minimal
  if (C > 0.6 && S < 0.3 && R < 0.3) return("C")
  if (S > 0.6 && C < 0.3 && R < 0.3) return("S")
  if (R > 0.6 && C < 0.3 && S < 0.3) return("R")

  # STEP 3: Check for binary mixes (edge strategies)
  # RATIONALE: Two strategies roughly equal, third minimal
  if (C >= 0.35 && S >= 0.35 && R < 0.25) return("CS")
  if (C >= 0.35 && R >= 0.35 && S < 0.25) return("CR")
  if (S >= 0.35 && R >= 0.35 && C < 0.25) return("SR")

  # STEP 4: Default to ternary mix (center of triangle)
  return("CSR")
}

#' Get CSR Strategy Description
#'
#' Returns user-friendly description of CSR strategy category.
#'
#' @param csr_category Character CSR category code
#' @return Character description
#' @export
get_csr_description <- function(csr_category) {

  descriptions <- list(
    "C" = "Competitor: fast-growing, resource-demanding, dominant in fertile undisturbed habitats",
    "S" = "Stress-tolerator: slow-growing, efficient resource use, survives poor/extreme conditions",
    "R" = "Ruderal: rapid lifecycle, opportunistic colonizer of disturbed sites",
    "CS" = "Competitor/Stress-tolerator: vigorous growth in stressful but stable habitats",
    "CR" = "Competitor/Ruderal: fast-growing, tolerates moderate disturbance",
    "SR" = "Stress-tolerator/Ruderal: hardy pioneer in harsh or disturbed environments",
    "CSR" = "Generalist: balanced strategy, adaptable to varied conditions"
  )

  if (is.na(csr_category)) {
    return(NA_character_)
  }

  desc <- descriptions[[csr_category]]
  if (is.null(desc)) {
    return(sprintf("Unknown CSR category: %s", csr_category))
  }

  return(desc)
}

# ==============================================================================
# KÖPPEN CLIMATE ZONE MAPPING
# ==============================================================================

#' Map Köppen Tiers to USDA Hardiness Zones
#'
#' Approximate USDA zone ranges for Köppen climate tiers.
#' Used for US-centric gardening advice.
#'
#' @param koppen_tier Integer 1-6 (tropical, Mediterranean, humid temperate,
#'                     continental, boreal/polar, arid)
#' @return Character USDA zone range (e.g., "3-5", "7-10")
#'
#' @details
#' MAPPING LOGIC:
#'   - Tier 1 (Tropical): USDA 10-13 (frost-free, >30°F min)
#'   - Tier 2 (Mediterranean): USDA 8-10 (mild winters, 10-40°F)
#'   - Tier 3 (Humid temperate): USDA 6-9 (moderate, -10 to 30°F)
#'   - Tier 4 (Continental): USDA 4-7 (cold winters, -30 to 10°F)
#'   - Tier 5 (Boreal/Polar): USDA 1-5 (very cold, <-30°F)
#'   - Tier 6 (Arid): USDA 5-9 (variable by latitude, dry)
#'
#' CAVEAT:
#'   Köppen is based on temperature + precipitation patterns, while USDA
#'   zones only reflect minimum winter temperature. Mapping is approximate.
#'
#' @export
map_koppen_to_usda <- function(koppen_tier) {

  if (is.na(koppen_tier)) {
    return(NA_character_)
  }

  usda_zones <- c(
    "1" = "10-13",  # Tropical
    "2" = "8-10",   # Mediterranean
    "3" = "6-9",    # Humid temperate
    "4" = "4-7",    # Continental
    "5" = "1-5",    # Boreal/Polar
    "6" = "5-9"     # Arid
  )

  zone <- usda_zones[as.character(koppen_tier)]
  if (is.na(zone)) {
    return(NA_character_)
  }

  return(zone)
}

#' Get Köppen Tier Description
#'
#' Returns descriptive name for Köppen tier.
#'
#' @param koppen_tier Integer 1-6
#' @return Character description
#' @export
get_koppen_description <- function(koppen_tier) {

  descriptions <- c(
    "1" = "Tropical",
    "2" = "Mediterranean",
    "3" = "Humid Temperate",
    "4" = "Continental",
    "5" = "Boreal/Polar",
    "6" = "Arid"
  )

  if (is.na(koppen_tier)) {
    return(NA_character_)
  }

  desc <- descriptions[as.character(koppen_tier)]
  if (is.na(desc)) {
    return(sprintf("Unknown Köppen tier: %d", koppen_tier))
  }

  return(desc)
}

# ==============================================================================
# ECOSYSTEM SERVICE CONFIDENCE
# ==============================================================================

#' Categorize Ecosystem Service Confidence
#'
#' Converts numeric confidence scores to qualitative levels.
#'
#' @param confidence Numeric confidence score (0-1)
#' @return Character: "High", "Moderate", "Low", or NA
#'
#' @details
#' THRESHOLDS:
#'   - High: confidence >= 0.7
#'   - Moderate: 0.4 <= confidence < 0.7
#'   - Low: confidence < 0.4
#'
#' @export
categorize_confidence <- function(confidence) {

  if (is.na(confidence)) {
    return(NA_character_)
  }

  if (confidence >= 0.7) {
    return("High")
  } else if (confidence >= 0.4) {
    return("Moderate")
  } else {
    return("Low")
  }
}

# ==============================================================================
# GROWTH FORM CATEGORIZATION
# ==============================================================================

#' Categorize Plant by Woodiness
#'
#' Classifies growth form based on woodiness score.
#'
#' @param woodiness Numeric woodiness score (0-1 continuous scale)
#' @return Character: "Herbaceous", "Semi-woody", "Woody", or NA
#'
#' @details
#' THRESHOLDS (0-1 continuous scale):
#'   - Herbaceous: woodiness < 0.3
#'   - Semi-woody: 0.3 <= woodiness < 0.7 (subshrubs)
#'   - Woody: woodiness >= 0.7 (shrubs, trees)
#'
#' NOTE: If your dataset uses discrete 0/1/2 scale, convert to 0-1 by dividing by 2.
#'
#' @export
categorize_woodiness <- function(woodiness) {

  if (is.na(woodiness)) {
    return(NA_character_)
  }

  # Use continuous 0-1 scale thresholds
  if (woodiness < 0.3) {
    return("Herbaceous")
  } else if (woodiness < 0.7) {
    return("Semi-woody")
  } else {
    return("Woody")
  }
}

# ==============================================================================
# HEIGHT CATEGORIZATION
# ==============================================================================

#' Categorize Plant Height
#'
#' Classifies plant into height categories for garden planning.
#'
#' @param height_m Numeric height in meters
#' @return Character: "Ground cover", "Low", "Medium", "Tall", "Very tall", or NA
#'
#' @details
#' THRESHOLDS:
#'   - Ground cover: < 0.3m (< 1 ft)
#'   - Low: 0.3-1m (1-3 ft)
#'   - Medium: 1-2.5m (3-8 ft)
#'   - Tall: 2.5-5m (8-16 ft)
#'   - Very tall: >= 5m (>16 ft)
#'
#' @export
categorize_height <- function(height_m) {

  if (is.na(height_m)) {
    return(NA_character_)
  }

  if (height_m < 0.3) {
    return("Ground cover")
  } else if (height_m < 1.0) {
    return("Low")
  } else if (height_m < 2.5) {
    return("Medium")
  } else if (height_m < 5.0) {
    return("Tall")
  } else {
    return("Very tall")
  }
}

# ==============================================================================
# LEAF PHENOLOGY
# ==============================================================================

#' Categorize Leaf Phenology
#'
#' Classifies deciduous vs evergreen based on leaf longevity.
#'
#' @param leaf_longevity_months Numeric leaf longevity in months
#' @return Character: "Evergreen", "Semi-evergreen", "Deciduous", or NA
#'
#' @details
#' THRESHOLDS:
#'   - Deciduous: < 9 months (drops leaves seasonally)
#'   - Semi-evergreen: 9-15 months (partial leaf retention)
#'   - Evergreen: >= 15 months (retains foliage year-round)
#'
#' @export
categorize_phenology <- function(leaf_longevity_months) {

  if (is.na(leaf_longevity_months)) {
    return(NA_character_)
  }

  if (leaf_longevity_months < 9) {
    return("Deciduous")
  } else if (leaf_longevity_months < 15) {
    return("Semi-evergreen")
  } else {
    return("Evergreen")
  }
}

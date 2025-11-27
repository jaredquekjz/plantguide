# ==============================================================================
# SECTION 4: ECOSYSTEM SERVICES (FUNCTIONAL BENEFITS)
# ==============================================================================
#
# PURPOSE:
#   Translate ecosystem service ratings into user-friendly environmental
#   benefits with star ratings and practical planting advice.
#
# DATA SOURCES:
#   - carbon_biomass_rating, carbon_biomass_confidence: Carbon storage (0-10 scale)
#   - nitrogen_fixation_rating, nitrogen_fixation_confidence: N-fixing ability
#   - nitrogen_fixation_has_try: Whether plant has N-fixing data from TRY
#   - nutrient_cycling_rating, nutrient_cycling_confidence: Nutrient cycling contribution
#   - erosion_protection_rating, erosion_protection_confidence: Soil erosion control
#   - decomposition_rating, decomposition_confidence: Litter decomposition rate
#   - height_m, try_woodiness, try_growth_form: For benefit quantification
#
# OUTPUT FORMAT:
#   Markdown text with service subsections using star ratings (⭐) and icons:
#   🌿 Carbon Sequestration | 🌾 Soil Improvement | 🌊 Erosion Control |
#   ♻️ Nutrient Cycling
#
# DEPENDENCIES:
#   - utils/categorization.R: categorize_confidence()
#
# ==============================================================================

library(dplyr)
library(glue)

# Source dependencies
if (!exists("categorize_confidence")) {
  source("shipley_checks/src/encyclopedia/utils/categorization.R")
}

# ==============================================================================
# MAIN GENERATION FUNCTION
# ==============================================================================

#' Generate Section 4: Ecosystem Services
#'
#' Creates environmental benefits summary with star ratings and descriptions.
#'
#' @param plant_row Single-row data frame with plant data
#' @return Character string of markdown-formatted ecosystem services
#'
#' @details
#' ALGORITHM:
#'   1. Extract ecosystem service ratings and confidence scores
#'   2. Generate star ratings for each service
#'   3. Create benefit descriptions with quantification
#'   4. Highlight top 3-4 services
#'   5. Add planting recommendations
#'
#' @export
generate_section_4_ecosystem_services <- function(plant_row) {

  # ===========================================================================
  # STEP 1: Extract and normalize ecosystem service ratings
  # ===========================================================================
  # RATIONALE: Ratings are stored as text labels ("Low", "Moderate", "High", "Very High")
  #            Convert to numeric 0-10 scale for consistent processing

  services <- list(
    carbon = convert_rating_to_numeric(plant_row$carbon_biomass_rating),
    carbon_conf = convert_confidence_to_numeric(plant_row$carbon_biomass_confidence),
    nitrogen_fix = convert_rating_to_numeric(plant_row$nitrogen_fixation_rating),
    nitrogen_fix_conf = convert_confidence_to_numeric(plant_row$nitrogen_fixation_confidence),
    nitrogen_fix_has_try = plant_row$nitrogen_fixation_has_try,
    nutrient_cycle = convert_rating_to_numeric(plant_row$nutrient_cycling_rating),
    nutrient_cycle_conf = convert_confidence_to_numeric(plant_row$nutrient_cycling_confidence),
    erosion = convert_rating_to_numeric(plant_row$erosion_protection_rating),
    erosion_conf = convert_confidence_to_numeric(plant_row$erosion_protection_confidence),
    decomposition = convert_rating_to_numeric(plant_row$decomposition_rating),
    decomp_conf = convert_confidence_to_numeric(plant_row$decomposition_confidence)
  )

  # ===========================================================================
  # STEP 2: Generate sections for high-confidence services only
  # ===========================================================================

  service_sections <- c()

  # Carbon sequestration
  if (!is.na(services$carbon) && !is.na(services$carbon_conf) && services$carbon_conf >= 0.4) {
    carbon_section <- generate_carbon_service(services$carbon, services$carbon_conf,
                                                plant_row$height_m,
                                                plant_row$try_woodiness,
                                                plant_row$try_growth_form)
    service_sections <- c(service_sections, carbon_section)
  }

  # Nitrogen fixation (soil improvement)
  if (!is.na(services$nitrogen_fix) && !is.na(services$nitrogen_fix_conf) && services$nitrogen_fix_conf >= 0.4) {
    nfix_section <- generate_nitrogen_fixation_service(services$nitrogen_fix,
                                                         services$nitrogen_fix_conf,
                                                         services$nitrogen_fix_has_try)
    service_sections <- c(service_sections, nfix_section)
  }

  # Erosion control
  if (!is.na(services$erosion) && !is.na(services$erosion_conf) && services$erosion_conf >= 0.4) {
    erosion_section <- generate_erosion_service(services$erosion, services$erosion_conf,
                                                  plant_row$try_growth_form)
    service_sections <- c(service_sections, erosion_section)
  }

  # Nutrient cycling
  if (!is.na(services$nutrient_cycle) && !is.na(services$nutrient_cycle_conf) && services$nutrient_cycle_conf >= 0.4) {
    nutrient_section <- generate_nutrient_cycling_service(services$nutrient_cycle,
                                                            services$nutrient_cycle_conf,
                                                            services$decomposition)
    service_sections <- c(service_sections, nutrient_section)
  }

  # ===========================================================================
  # STEP 3: Assemble section (only if services exist)
  # ===========================================================================

  if (length(service_sections) == 0) {
    ecosystem_services <- glue("
      ## Ecosystem Services

      **Environmental benefits**: Data insufficient for confident assessment
    ")
  } else {
    services_text <- paste(service_sections, collapse = "\n\n    ")

    ecosystem_services <- glue("
      ## Ecosystem Services

      **Environmental Benefits**:

      {services_text}
    ")
  }

  return(as.character(ecosystem_services))
}

# ==============================================================================
# HELPER FUNCTIONS FOR EACH SERVICE
# ==============================================================================

#' Convert Text Rating to Numeric
#'
#' Maps ecosystem service text ratings to numeric 0-10 scale.
#'
#' @param rating_text Character rating ("Low", "Moderate", "High", "Very High")
#' @return Numeric rating on 0-10 scale, or NA if unable to classify
#' @keywords internal
convert_rating_to_numeric <- function(rating_text) {

  if (is.na(rating_text) || rating_text == "" || rating_text == "Unable to Classify") {
    return(NA_real_)
  }

  # Try to convert to numeric first (in case it's already numeric)
  numeric_val <- suppressWarnings(as.numeric(rating_text))
  if (!is.na(numeric_val)) {
    return(numeric_val)
  }

  # Map text labels to numeric ratings
  rating_map <- c(
    "Very Low" = 1,
    "Low" = 2,
    "Moderate" = 5,
    "High" = 7,
    "Very High" = 9
  )

  # Case-insensitive match
  rating_text_clean <- trimws(rating_text)
  numeric_rating <- rating_map[rating_text_clean]

  if (is.na(numeric_rating)) {
    warning(sprintf("Unknown rating text: '%s'", rating_text))
    return(NA_real_)
  }

  return(as.numeric(numeric_rating))
}

#' Convert Text Confidence to Numeric
#'
#' Maps confidence text labels to numeric 0-1 scale.
#'
#' @param confidence_text Character confidence ("Low", "Moderate", "High")
#' @return Numeric confidence on 0-1 scale, or NA if unable to classify
#' @keywords internal
convert_confidence_to_numeric <- function(confidence_text) {

  if (is.na(confidence_text) || confidence_text == "" || confidence_text == "Unable to Classify") {
    return(NA_real_)
  }

  # Try to convert to numeric first (in case it's already numeric)
  numeric_val <- suppressWarnings(as.numeric(confidence_text))
  if (!is.na(numeric_val)) {
    # If already 0-1 scale, return as is
    if (numeric_val >= 0 && numeric_val <= 1) {
      return(numeric_val)
    }
    # If on 0-10 scale, convert to 0-1
    if (numeric_val >= 0 && numeric_val <= 10) {
      return(numeric_val / 10)
    }
    return(NA_real_)
  }

  # Map text labels to numeric confidence (0-1 scale)
  confidence_map <- c(
    "Very Low" = 0.1,
    "Low" = 0.3,
    "Moderate" = 0.5,
    "High" = 0.8,
    "Very High" = 0.95
  )

  # Case-insensitive match
  confidence_text_clean <- trimws(confidence_text)
  numeric_conf <- confidence_map[confidence_text_clean]

  if (is.na(numeric_conf)) {
    warning(sprintf("Unknown confidence text: '%s'", confidence_text))
    return(NA_real_)
  }

  return(as.numeric(numeric_conf))
}

#' Generate Star Rating
#' @keywords internal
get_star_rating <- function(rating) {
  # Map 0-10 rating to 1-5 stars
  if (is.na(rating)) return("")

  stars <- ceiling(rating / 2)
  stars <- max(1, min(5, stars))  # Clamp to 1-5
  return(paste(rep("⭐", stars), collapse = ""))
}

#' Get Rating Descriptor
#' @keywords internal
get_rating_descriptor <- function(rating) {
  if (is.na(rating)) return("Unknown")

  if (rating >= 8) {
    return("Excellent")
  } else if (rating >= 6) {
    return("High")
  } else if (rating >= 4) {
    return("Moderate")
  } else if (rating >= 2) {
    return("Low")
  } else {
    return("Minimal")
  }
}

#' Generate Carbon Sequestration Service
#' @keywords internal
generate_carbon_service <- function(rating, confidence, height_m, woodiness, growth_form) {

  stars <- get_star_rating(rating)
  descriptor <- get_rating_descriptor(rating)
  conf_level <- categorize_confidence(confidence)

  # Quantify carbon storage based on height and woodiness
  carbon_kg <- NA
  if (!is.na(height_m) && !is.na(woodiness)) {
    # Simple estimation: woody plants store more C proportional to height
    woodiness_num <- suppressWarnings(as.numeric(woodiness))
    if (is.na(woodiness_num)) {
      # Handle text labels
      if (woodiness == "woody") woodiness_num <- 1
      else if (woodiness == "semi-woody") woodiness_num <- 0.5
      else woodiness_num <- 0
    }
    # Very rough estimate: ~5-10 kg CO2/year per meter height for woody plants
    carbon_kg <- round(height_m * woodiness_num * 7)
  }

  # Build description
  if (!is.na(carbon_kg) && carbon_kg > 0) {
    quant_text <- sprintf("Stores ~%d kg CO₂/year in biomass", carbon_kg)
  } else {
    quant_text <- "Carbon storage in plant tissues"
  }

  # Planting advice based on rating
  if (rating >= 7) {
    advice <- "→ Excellent choice for carbon-conscious gardening"
  } else if (rating >= 5) {
    advice <- "→ Contributes to garden carbon sequestration"
  } else {
    advice <- "→ Modest carbon storage"
  }

  carbon_section <- glue("
    🌿 **Carbon Sequestration**: {stars} {descriptor} (confidence: {conf_level})
       {quant_text}
       {advice}
  ")

  return(as.character(carbon_section))
}

#' Generate Nitrogen Fixation Service
#' @keywords internal
generate_nitrogen_fixation_service <- function(rating, confidence, has_try_data) {

  stars <- get_star_rating(rating)
  descriptor <- get_rating_descriptor(rating)
  conf_level <- categorize_confidence(confidence)

  # Check if it's a nitrogen fixer
  if (rating >= 7) {
    mechanism <- "Fixes atmospheric nitrogen via root nodules"
    advice <- "→ Plant near nitrogen-demanding crops | Improves soil fertility naturally"
  } else if (rating >= 4) {
    mechanism <- "Moderate nitrogen contribution to soil"
    advice <- "→ Useful in mixed planting for soil improvement"
  } else {
    mechanism <- "Not a nitrogen fixer | Relies on soil nitrogen"
    advice <- "→ Ensure adequate nitrogen in soil amendments"
  }

  # Note data source if from TRY database
  data_note <- ""
  if (!is.na(has_try_data) && (has_try_data == TRUE || has_try_data == "true" || has_try_data == 1)) {
    data_note <- "(verified by TRY database)"
  }

  nfix_section <- glue("
    🌾 **Soil Improvement - Nitrogen**: {stars} {descriptor} (confidence: {conf_level}) {data_note}
       {mechanism}
       {advice}
  ")

  return(as.character(nfix_section))
}

#' Generate Erosion Control Service
#' @keywords internal
generate_erosion_service <- function(rating, confidence, growth_form) {

  stars <- get_star_rating(rating)
  descriptor <- get_rating_descriptor(rating)
  conf_level <- categorize_confidence(confidence)

  # Mechanism description based on growth form
  if (!is.na(growth_form)) {
    if (grepl("grass", growth_form, ignore.case = TRUE)) {
      mechanism <- "Dense fibrous root system stabilizes soil"
    } else if (growth_form %in% c("tree", "shrub")) {
      mechanism <- "Deep woody roots anchor soil on slopes"
    } else if (growth_form == "climber") {
      mechanism <- "Ground cover reduces water runoff"
    } else {
      mechanism <- "Root system provides soil stabilization"
    }
  } else {
    mechanism <- "Contributes to soil stability"
  }

  # Planting advice based on rating
  if (rating >= 7) {
    advice <- "→ Excellent for slopes, banks, and erosion-prone sites"
  } else if (rating >= 5) {
    advice <- "→ Useful for moderate erosion control"
  } else {
    advice <- "→ Limited erosion protection"
  }

  erosion_section <- glue("
    🌊 **Erosion Control**: {stars} {descriptor} (confidence: {conf_level})
       {mechanism}
       {advice}
  ")

  return(as.character(erosion_section))
}

#' Generate Nutrient Cycling Service
#' @keywords internal
generate_nutrient_cycling_service <- function(rating, confidence, decomp_rating) {

  stars <- get_star_rating(rating)
  descriptor <- get_rating_descriptor(rating)
  conf_level <- categorize_confidence(confidence)

  # Link to decomposition rate if available
  if (!is.na(decomp_rating)) {
    if (decomp_rating >= 7) {
      mechanism <- "Fast-decomposing litter rapidly returns nutrients to soil"
    } else if (decomp_rating >= 4) {
      mechanism <- "Moderate decomposition contributes to nutrient availability"
    } else {
      mechanism <- "Slow-decomposing litter provides long-term organic matter"
    }
  } else {
    mechanism <- "Contributes organic matter to soil food web"
  }

  # Planting advice
  if (rating >= 6) {
    advice <- "→ Excellent for building soil health over time"
  } else {
    advice <- "→ Modest contribution to nutrient cycling"
  }

  nutrient_section <- glue("
    ♻️ **Nutrient Cycling**: {stars} {descriptor} (confidence: {conf_level})
       {mechanism}
       {advice}
  ")

  return(as.character(nutrient_section))
}

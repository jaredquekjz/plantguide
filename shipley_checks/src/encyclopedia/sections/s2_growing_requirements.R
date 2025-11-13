# ==============================================================================
# SECTION 2: GROWING REQUIREMENTS (SITE SELECTION)
# ==============================================================================
#
# PURPOSE:
#   Translate EIVE indicators, CSR strategy, and Köppen climate data into
#   user-friendly site selection and growing requirement advice.
#
# DATA SOURCES:
#   - EIVEres-L: Light requirement (0-10 scale, 100% coverage)
#   - EIVEres-M: Moisture requirement (0-10 scale, 100% coverage)
#   - EIVEres-T: Temperature affinity (0-10 scale, 100% coverage)
#   - EIVEres-N: Fertility/nitrogen need (0-10 scale, 100% coverage)
#   - EIVEres-R: pH/reaction preference (0-10 scale, 100% coverage)
#   - C, S, R: CSR strategy scores (0-1 scale, 99.88% coverage)
#   - tier_1 through tier_6: Köppen tier memberships (boolean)
#   - n_tier_memberships: Count of Köppen tier memberships (1-6)
#
# OUTPUT FORMAT:
#   Markdown text with 5 subsections using icons:
#   ☀️ Light | 💧 Water | 🌡️ Climate | 🌱 Fertility | ⚗️ pH
#
# DEPENDENCIES:
#   - utils/lookup_tables.R: get_eive_label()
#   - utils/categorization.R: get_csr_category(), map_koppen_to_usda()
#
# ==============================================================================

library(dplyr)
library(glue)

# Source dependencies
if (!exists("get_eive_label")) {
  source("shipley_checks/src/encyclopedia/utils/lookup_tables.R")
}
if (!exists("get_csr_category")) {
  source("shipley_checks/src/encyclopedia/utils/categorization.R")
}

# ==============================================================================
# MAIN GENERATION FUNCTION
# ==============================================================================

#' Generate Section 2: Growing Requirements
#'
#' Creates site selection advice based on EIVE, CSR, and climate data.
#'
#' @param plant_row Single-row data frame with plant data
#' @return Character string of markdown-formatted growing requirements
#'
#' @details
#' ALGORITHM:
#'   1. Map EIVE scores to semantic labels
#'   2. Generate context-specific advice for each axis
#'   3. Adjust advice based on CSR strategy (e.g., S-dominant = drought tolerance)
#'   4. Map Köppen tiers to gardening zones
#'   5. Assemble subsections with icons
#'
#' @export
generate_section_2_growing_requirements <- function(plant_row) {

  # ===========================================================================
  # STEP 1: Extract EIVE scores and map to semantic labels
  # ===========================================================================

  eive_L <- plant_row[["EIVEres-L"]]
  eive_M <- plant_row[["EIVEres-M"]]
  eive_T <- plant_row[["EIVEres-T"]]
  eive_N <- plant_row[["EIVEres-N"]]
  eive_R <- plant_row[["EIVEres-R"]]

  light_label <- get_eive_label(eive_L, "L")
  moisture_label <- get_eive_label(eive_M, "M")
  temp_label <- get_eive_label(eive_T, "T")
  fertility_label <- get_eive_label(eive_N, "N")
  ph_label <- get_eive_label(eive_R, "R")

  # ===========================================================================
  # STEP 2: Extract CSR strategy for contextual advice
  # ===========================================================================

  csr_C <- plant_row$C
  csr_S <- plant_row$S
  csr_R <- plant_row$R

  csr_category <- get_csr_category(csr_C, csr_S, csr_R)

  # ===========================================================================
  # STEP 3: Light requirements
  # ===========================================================================

  light_section <- generate_light_advice(eive_L, light_label)

  # ===========================================================================
  # STEP 4: Water requirements (adjust based on CSR-S)
  # ===========================================================================

  water_section <- generate_water_advice(eive_M, moisture_label, csr_S, csr_category)

  # ===========================================================================
  # STEP 5: Climate suitability (Köppen tiers)
  # ===========================================================================

  climate_section <- generate_climate_advice(plant_row)

  # ===========================================================================
  # STEP 6: Fertility requirements (adjust based on CSR-C)
  # ===========================================================================

  fertility_section <- generate_fertility_advice(eive_N, fertility_label, csr_C, csr_category)

  # ===========================================================================
  # STEP 7: pH requirements
  # ===========================================================================

  ph_section <- generate_ph_advice(eive_R, ph_label)

  # ===========================================================================
  # STEP 8: Assemble complete section
  # ===========================================================================

  growing_requirements <- glue("
    ## Growing Requirements

    {light_section}

    {water_section}

    {climate_section}

    {fertility_section}

    {ph_section}
  ")

  return(as.character(growing_requirements))
}

# ==============================================================================
# HELPER FUNCTIONS FOR EACH REQUIREMENT AXIS
# ==============================================================================

#' Generate Light Advice
#' @keywords internal
generate_light_advice <- function(eive_L, light_label) {

  if (is.na(eive_L)) {
    return("☀️ **Light**: Requirements unknown")
  }

  # Planting advice based on light requirement
  if (eive_L < 3) {
    advice <- "Plant in shade beneath trees or north-facing sites"
  } else if (eive_L < 5) {
    advice <- "Suitable for partial shade or dappled light"
  } else if (eive_L < 7) {
    advice <- "Prefers open sites with good light but tolerates some shade"
  } else {
    advice <- "Requires full sun in open positions"
  }

  light_section <- glue("
    ☀️ **Light**: {stringr::str_to_sentence(light_label)} (EIVE-L: {round(eive_L, 1)}/10)
       → {advice}
  ")

  return(as.character(light_section))
}

#' Generate Water Advice with CSR Context
#' @keywords internal
generate_water_advice <- function(eive_M, moisture_label, csr_S, csr_category) {

  if (is.na(eive_M)) {
    return("💧 **Water**: Requirements unknown")
  }

  # Base watering advice
  if (eive_M < 2) {
    advice <- "Requires very dry conditions; avoid irrigation after establishment"
  } else if (eive_M < 4) {
    advice <- "Water sparingly; allow soil to dry between waterings"
  } else if (eive_M < 6) {
    advice <- "Water regularly during growing season; moderate moisture"
  } else if (eive_M < 8) {
    advice <- "Keep consistently moist; do not allow to dry out"
  } else {
    advice <- "Requires waterlogged or aquatic conditions; plant in bog or pond"
  }

  # RATIONALE: S-dominant plants have stress-tolerance mechanisms
  # If S > 0.5 and moisture is low-moderate, emphasize drought tolerance
  if (!is.na(csr_S) && csr_S > 0.5 && eive_M < 6) {
    drought_note <- "Drought-tolerant once established (stress-tolerator strategy)"
    advice <- paste(advice, drought_note, sep = " | ")
  }

  water_section <- glue("
    💧 **Water**: {stringr::str_to_sentence(moisture_label)} (EIVE-M: {round(eive_M, 1)}/10)
       → {advice}
  ")

  return(as.character(water_section))
}

#' Generate Climate Advice from Köppen Tiers
#' @keywords internal
generate_climate_advice <- function(plant_row) {

  # Extract Köppen tier memberships
  tiers <- c()
  tier_names <- c("Tropical", "Mediterranean", "Humid Temperate", "Continental", "Boreal/Polar", "Arid")

  for (i in 1:6) {
    tier_col <- paste0("tier_", i, "_", tolower(gsub("[/ ]", "_", tier_names[i])))
    if (tier_col %in% names(plant_row) && !is.na(plant_row[[tier_col]]) && plant_row[[tier_col]] == TRUE) {
      tiers <- c(tiers, tier_names[i])
    }
  }

  n_tiers <- plant_row$n_tier_memberships

  if (length(tiers) == 0) {
    return("🌡️ **Climate**: Climate preferences unknown")
  }

  # Adaptability note
  if (!is.na(n_tiers) && n_tiers >= 4) {
    adaptability <- "Highly adaptable across diverse climates"
  } else if (!is.na(n_tiers) && n_tiers >= 2) {
    adaptability <- "Adaptable to multiple climate types"
  } else {
    adaptability <- "Specialized climate requirements"
  }

  # Format tier list
  tier_list <- paste(tiers, collapse = ", ")

  # Map to USDA zones (use first tier as primary)
  # Note: This is approximate since Köppen != USDA hardiness
  primary_tier_idx <- which(tier_names %in% tiers)[1]
  usda_zones <- map_koppen_to_usda(primary_tier_idx)

  climate_section <- glue("
    🌡️ **Climate**: {tier_list} climates
       → {adaptability}
       → Approximate USDA zones: {usda_zones}
  ")

  return(as.character(climate_section))
}

#' Generate Fertility Advice with CSR Context
#' @keywords internal
generate_fertility_advice <- function(eive_N, fertility_label, csr_C, csr_category) {

  if (is.na(eive_N)) {
    return("🌱 **Fertility**: Requirements unknown")
  }

  # Base fertility advice
  if (eive_N < 2) {
    advice <- "Thrives in infertile soils; avoid fertilizing"
  } else if (eive_N < 4) {
    advice <- "Low fertility needs; light annual feeding sufficient"
  } else if (eive_N < 6) {
    advice <- "Moderate fertility; balanced fertilizer in spring"
  } else if (eive_N < 8) {
    advice <- "Hungry feeder; fertilize monthly during growing season"
  } else {
    advice <- "Extremely high nutrient needs; heavy fertilization required"
  }

  # RATIONALE: C-dominant plants are resource-demanding
  # If C > 0.5 and fertility is moderate-high, emphasize feeding
  if (!is.na(csr_C) && csr_C > 0.5 && eive_N >= 5) {
    competitive_note <- "Vigorous grower; benefits from rich soil"
    advice <- paste(advice, competitive_note, sep = " | ")
  }

  fertility_section <- glue("
    🌱 **Fertility**: {stringr::str_to_sentence(fertility_label)} (EIVE-N: {round(eive_N, 1)}/10)
       → {advice}
  ")

  return(as.character(fertility_section))
}

#' Generate pH Advice
#' @keywords internal
generate_ph_advice <- function(eive_R, ph_label) {

  if (is.na(eive_R)) {
    return("⚗️ **pH**: Requirements unknown")
  }

  # pH advice
  if (eive_R < 3) {
    advice <- "Requires acidic conditions; use ericaceous compost | pH 4.0-5.5"
  } else if (eive_R < 5) {
    advice <- "Prefers acidic to neutral soil; avoid lime | pH 5.0-6.5"
  } else if (eive_R < 7) {
    advice <- "Adaptable to slightly acidic to neutral soil | pH 6.0-7.0"
  } else if (eive_R < 9) {
    advice <- "Tolerates alkaline conditions; can add lime | pH 6.5-8.0"
  } else {
    advice <- "Requires alkaline soil; thrives on chalk or limestone | pH 7.5-8.5"
  }

  ph_section <- glue("
    ⚗️ **pH**: {stringr::str_to_sentence(ph_label)} (EIVE-R: {round(eive_R, 1)}/10)
       → {advice}
  ")

  return(as.character(ph_section))
}

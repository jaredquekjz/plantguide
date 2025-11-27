# ==============================================================================
# SECTION 3: MAINTENANCE PROFILE (LABOR REQUIREMENTS)
# ==============================================================================
#
# PURPOSE:
#   Translate CSR strategy and plant traits into practical maintenance advice
#   including growth rate, pruning needs, seasonal tasks, and time commitment.
#
# DATA SOURCES:
#   - C, S, R: CSR strategy scores (0-1 scale, 99.88% coverage)
#   - try_growth_form: Growth form classification
#   - height_m: Maximum height in meters
#   - try_leaf_phenology: Deciduous vs evergreen
#   - decomposition_rating: Decomposition rate (0-10 scale if available)
#   - decomposition_confidence: Confidence in decomposition rating
#
# OUTPUT FORMAT:
#   Markdown text with maintenance level header and 4 subsections:
#   🌿 Growth Rate | 🍂 Seasonal Tasks | ♻️ Waste Management | ⏰ Time Commitment
#
# DEPENDENCIES:
#   - utils/categorization.R: get_csr_category()
#
# ==============================================================================

library(dplyr)
library(glue)

# Source dependencies
if (!exists("get_csr_category")) {
  source("shipley_checks/src/encyclopedia/utils/categorization.R")
}

# ==============================================================================
# MAIN GENERATION FUNCTION
# ==============================================================================

#' Generate Section 3: Maintenance Profile
#'
#' Creates maintenance and labor requirement advice based on CSR strategy
#' and plant traits.
#'
#' @param plant_row Single-row data frame with plant data
#' @return Character string of markdown-formatted maintenance profile
#'
#' @details
#' ALGORITHM:
#'   1. Determine overall maintenance level from CSR strategy
#'   2. Calculate growth rate and pruning needs
#'   3. Generate seasonal task recommendations
#'   4. Assess waste management (decomposition characteristics)
#'   5. Estimate annual time commitment
#'
#' @export
generate_section_3_maintenance_profile <- function(plant_row) {

  # ===========================================================================
  # STEP 1: Extract CSR strategy
  # ===========================================================================

  csr_C <- plant_row$C
  csr_S <- plant_row$S
  csr_R <- plant_row$R

  csr_category <- get_csr_category(csr_C, csr_S, csr_R)

  # ===========================================================================
  # STEP 2: Determine overall maintenance level
  # ===========================================================================
  # RATIONALE: C-dominant = high maintenance (fast growth, vigorous)
  #            S-dominant = low maintenance (slow growth, hardy)
  #            R-dominant = medium (opportunistic but not as vigorous as C)

  maintenance_level <- calculate_maintenance_level(csr_C, csr_S, csr_R)

  # ===========================================================================
  # STEP 3: Growth rate section
  # ===========================================================================

  growth_section <- generate_growth_rate_advice(csr_C, csr_S, csr_R, csr_category,
                                                  plant_row$try_growth_form,
                                                  plant_row$height_m)

  # ===========================================================================
  # STEP 4: Seasonal tasks section
  # ===========================================================================

  seasonal_section <- generate_seasonal_tasks(plant_row$try_leaf_phenology,
                                                plant_row$try_growth_form,
                                                csr_C, csr_S)

  # ===========================================================================
  # STEP 5: Waste management section
  # ===========================================================================

  waste_section <- generate_waste_management(plant_row$decomposition_rating,
                                               plant_row$decomposition_confidence,
                                               csr_S,
                                               plant_row$try_leaf_phenology)

  # ===========================================================================
  # STEP 6: Time commitment estimate
  # ===========================================================================

  time_section <- estimate_time_commitment(maintenance_level,
                                             plant_row$try_growth_form,
                                             plant_row$try_leaf_phenology)

  # ===========================================================================
  # STEP 7: Assemble complete section
  # ===========================================================================

  maintenance_profile <- glue("
    ## Maintenance Profile

    **Maintenance Level: {toupper(maintenance_level)}**

    {growth_section}

    {seasonal_section}

    {waste_section}

    {time_section}
  ")

  return(as.character(maintenance_profile))
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Calculate Overall Maintenance Level
#' @keywords internal
calculate_maintenance_level <- function(csr_C, csr_S, csr_R) {

  if (any(is.na(c(csr_C, csr_S, csr_R)))) {
    return("MEDIUM")
  }

  # Normalize to 0-1 scale if in percentage form (0-100)
  if (csr_C > 1 || csr_S > 1 || csr_R > 1) {
    csr_C <- csr_C / 100
    csr_S <- csr_S / 100
    csr_R <- csr_R / 100
  }

  # RATIONALE: Thresholds based on CSR triangle partitioning
  if (csr_C > 0.6) {
    return("HIGH")
  } else if (csr_S > 0.6) {
    return("LOW")
  } else if (csr_R > 0.6) {
    return("MEDIUM")
  } else {
    # Mixed strategies
    if (csr_C > csr_S && csr_C > csr_R) {
      return("MEDIUM-HIGH")
    } else if (csr_S > csr_C && csr_S > csr_R) {
      return("LOW-MEDIUM")
    } else {
      return("MEDIUM")
    }
  }
}

#' Generate Growth Rate Advice
#' @keywords internal
generate_growth_rate_advice <- function(csr_C, csr_S, csr_R, csr_category,
                                         growth_form, height_m) {

  if (any(is.na(c(csr_C, csr_S, csr_R)))) {
    return("🌿 **Growth Rate**: Unknown")
  }

  # Normalize to 0-1 scale if in percentage form (0-100)
  if (csr_C > 1 || csr_S > 1 || csr_R > 1) {
    csr_C <- csr_C / 100
    csr_S <- csr_S / 100
    csr_R <- csr_R / 100
  }

  # Determine growth rate
  if (csr_C > 0.6) {
    growth_rate <- "Fast"
    growth_desc <- "Vigorous grower, can outcompete neighbors"
  } else if (csr_S > 0.6) {
    growth_rate <- "Slow"
    growth_desc <- "Slow but steady growth, compact habit"
  } else if (csr_R > 0.6) {
    growth_rate <- "Rapid"
    growth_desc <- "Quick to establish, opportunistic growth"
  } else {
    growth_rate <- "Moderate"
    growth_desc <- "Steady growth rate"
  }

  # Pruning frequency
  pruning_advice <- ""
  if (!is.na(growth_form) && growth_form %in% c("tree", "shrub")) {
    if (csr_C > 0.6) {
      pruning_advice <- "→ Annual pruning recommended to control vigor"
    } else if (csr_S > 0.6) {
      pruning_advice <- "→ Minimal pruning needed (every 2-3 years)"
    } else {
      pruning_advice <- "→ Prune as needed to maintain shape"
    }
  } else if (!is.na(growth_form) && growth_form == "climber") {
    if (csr_C > 0.6) {
      pruning_advice <- "→ Requires regular training and pruning"
    } else {
      pruning_advice <- "→ Light pruning to guide growth"
    }
  } else {
    # Herbaceous plants
    if (csr_C > 0.6) {
      pruning_advice <- "→ May require cutting back to prevent spreading"
    } else {
      pruning_advice <- "→ Cut back after flowering if desired"
    }
  }

  growth_section <- glue("
    🌿 **Growth Rate**: {growth_rate} ({csr_category} strategy)
       → {growth_desc}
       {pruning_advice}
  ")

  return(as.character(growth_section))
}

#' Generate Seasonal Tasks Advice
#' @keywords internal
generate_seasonal_tasks <- function(leaf_phenology, growth_form, csr_C, csr_S) {

  # Normalize CSR if in percentage form
  if (!is.na(csr_C) && csr_C > 1) csr_C <- csr_C / 100
  if (!is.na(csr_S) && csr_S > 1) csr_S <- csr_S / 100

  tasks <- c()

  # Spring tasks
  if (!is.na(growth_form) && growth_form %in% c("tree", "shrub")) {
    spring_task <- "Spring: Shape after frost risk passes"
  } else {
    spring_task <- "Spring: Remove dead growth, apply mulch"
  }
  tasks <- c(tasks, spring_task)

  # Summer tasks
  if (!is.na(csr_C) && csr_C > 0.6) {
    summer_task <- "Summer: Monitor for excessive growth, deadhead spent flowers"
  } else {
    summer_task <- "Summer: Minimal intervention, occasional deadheading"
  }
  tasks <- c(tasks, summer_task)

  # Autumn tasks
  if (!is.na(leaf_phenology) && leaf_phenology == "deciduous") {
    autumn_task <- "Autumn: Rake fallen leaves for compost"
  } else {
    autumn_task <- "Autumn: Minimal leaf cleanup (evergreen foliage)"
  }
  tasks <- c(tasks, autumn_task)

  # Winter tasks
  if (!is.na(growth_form) && growth_form %in% c("tree", "shrub")) {
    winter_task <- "Winter: Structural pruning while dormant (if deciduous)"
  } else {
    winter_task <- "Winter: Protect from frost if tender"
  }
  tasks <- c(tasks, winter_task)

  seasonal_section <- glue("
    🍂 **Seasonal Tasks**:
       → {paste(tasks, collapse = '\n       → ')}
  ")

  return(as.character(seasonal_section))
}

#' Generate Waste Management Advice
#' @keywords internal
generate_waste_management <- function(decomp_rating, decomp_confidence,
                                       csr_S, leaf_phenology) {

  # Convert to numeric if needed
  decomp_rating <- suppressWarnings(as.numeric(decomp_rating))
  decomp_confidence <- suppressWarnings(as.numeric(decomp_confidence))

  # Normalize CSR-S if in percentage form
  if (!is.na(csr_S) && csr_S > 1) csr_S <- csr_S / 100

  # Use decomposition rating if available and confident
  if (!is.na(decomp_rating) && !is.na(decomp_confidence) && decomp_confidence >= 0.5) {

    if (decomp_rating >= 7) {
      decomp_desc <- "Fast-decomposing foliage"
      compost_advice <- "Excellent for compost; breaks down quickly"
      mulch_advice <- "Good green mulch but short-lived"
    } else if (decomp_rating >= 4) {
      decomp_desc <- "Moderate decomposition rate"
      compost_advice <- "Suitable for compost; mix with other materials"
      mulch_advice <- "Decent mulch material"
    } else {
      decomp_desc <- "Slow-decomposing foliage"
      compost_advice <- "Add to compost in thin layers; may take time"
      mulch_advice <- "Excellent for long-lasting mulch"
    }

  } else {
    # Fall back to CSR strategy
    if (!is.na(csr_S) && csr_S > 0.6) {
      decomp_desc <- "Likely slow-decomposing (stress-tolerator strategy)"
      compost_advice <- "Tough foliage; shred before composting"
      mulch_advice <- "Good for long-lasting mulch"
    } else {
      decomp_desc <- "Moderate decomposition rate"
      compost_advice <- "Suitable for composting"
      mulch_advice <- "Can be used as mulch"
    }
  }

  # Add note about volume if deciduous
  if (!is.na(leaf_phenology) && leaf_phenology == "deciduous") {
    volume_note <- "Seasonal leaf drop creates moderate waste volume"
  } else {
    volume_note <- "Minimal waste volume (evergreen)"
  }

  waste_section <- glue("
    ♻️ **Waste Management**:
       → {decomp_desc}
       → {compost_advice}
       → {mulch_advice}
       → {volume_note}
  ")

  return(as.character(waste_section))
}

#' Estimate Annual Time Commitment
#' @keywords internal
estimate_time_commitment <- function(maintenance_level, growth_form, leaf_phenology) {

  # Base time by maintenance level
  base_minutes <- switch(maintenance_level,
    "LOW" = 15,
    "LOW-MEDIUM" = 30,
    "MEDIUM" = 60,
    "MEDIUM-HIGH" = 120,
    "HIGH" = 240,
    60  # default
  )

  # Adjust for growth form
  if (!is.na(growth_form)) {
    if (growth_form %in% c("tree", "shrub")) {
      base_minutes <- base_minutes * 1.5
    } else if (growth_form == "climber") {
      base_minutes <- base_minutes * 2
    }
  }

  # Adjust for deciduous (more cleanup)
  if (!is.na(leaf_phenology) && leaf_phenology == "deciduous") {
    base_minutes <- base_minutes * 1.3
  }

  # Format time
  if (base_minutes < 60) {
    time_text <- sprintf("~%d minutes per year", round(base_minutes))
  } else if (base_minutes < 180) {
    time_text <- sprintf("~%.1f hours per year", base_minutes / 60)
  } else {
    time_text <- sprintf("~%.0f hours per year", round(base_minutes / 60))
  }

  time_section <- glue("
    ⏰ **Time Commitment**: {time_text}
  ")

  return(as.character(time_section))
}

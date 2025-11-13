# ==============================================================================
# SECTION 1: PLANT IDENTITY CARD
# ==============================================================================
#
# PURPOSE:
#   Generate concise plant identification summary with taxonomic classification
#   and key morphological traits. Template-based deterministic generation.
#
# DATA SOURCES:
#   - wfo_scientific_name: Scientific name (binomial)
#   - family: Taxonomic family
#   - genus: Taxonomic genus
#   - height_m: Maximum height in meters
#   - try_growth_form: Growth form classification
#   - try_leaf_type: Leaf morphology type
#   - try_woodiness: Woodiness score (0-1)
#   - try_leaf_phenology: Deciduous vs evergreen
#   - try_photosynthesis_pathway: C3, C4, or CAM
#
# OUTPUT FORMAT:
#   Markdown text block with taxonomic header and trait summary
#
# DEPENDENCIES:
#   - utils/categorization.R: categorize_height(), categorize_woodiness(), etc.
#
# ==============================================================================

library(dplyr)
library(glue)

# Source dependencies
if (!exists("categorize_height")) {
  source("shipley_checks/src/encyclopedia/utils/categorization.R")
}

# ==============================================================================
# MAIN GENERATION FUNCTION
# ==============================================================================

#' Generate Section 1: Plant Identity Card
#'
#' Creates taxonomic and morphological summary for encyclopedia header.
#'
#' @param plant_row Single-row data frame with plant data
#' @return Character string of markdown-formatted identity card
#'
#' @details
#' ALGORITHM:
#'   1. Extract taxonomic identifiers
#'   2. Classify height category
#'   3. Classify growth form and woodiness
#'   4. Classify leaf traits
#'   5. Assemble template with conditional special adaptations
#'
#' @export
generate_section_1_identity_card <- function(plant_row) {

  # ===========================================================================
  # STEP 1: Extract taxonomic data
  # ===========================================================================

  scientific_name <- plant_row$wfo_scientific_name
  family <- if (!is.na(plant_row$family)) plant_row$family else "Unknown family"
  genus <- if (!is.na(plant_row$genus)) plant_row$genus else "Unknown genus"

  # ===========================================================================
  # STEP 2: Height classification
  # ===========================================================================

  height_m <- plant_row$height_m

  if (!is.na(height_m)) {
    height_cat <- categorize_height(height_m)
    height_text <- sprintf("%s (%.1fm)", tolower(height_cat), height_m)
  } else {
    height_text <- "height unknown"
  }

  # ===========================================================================
  # STEP 3: Growth form and woodiness
  # ===========================================================================

  # Growth form text
  growth_form <- plant_row$try_growth_form
  if (is.na(growth_form) || growth_form == "") {
    growth_form_text <- "plant"
  } else {
    growth_form_text <- tolower(growth_form)
  }

  # Woodiness classification
  woodiness <- plant_row$try_woodiness
  if (!is.na(woodiness) && woodiness != "") {
    # Handle text labels (some datasets use "non-woody", "semi-woody", "woody")
    if (is.character(woodiness) && woodiness %in% c("non-woody", "semi-woody", "woody")) {
      if (woodiness == "non-woody") {
        woodiness_text <- "herbaceous"
      } else {
        woodiness_text <- tolower(woodiness)  # Keep hyphen for "semi-woody"
      }
    } else {
      # Convert to numeric if needed
      woodiness_num <- suppressWarnings(as.numeric(woodiness))
      if (!is.na(woodiness_num)) {
        woodiness_cat <- categorize_woodiness(woodiness_num)
        woodiness_text <- tolower(woodiness_cat)
      } else {
        woodiness_text <- "plant"
      }
    }
  } else {
    woodiness_text <- "plant"
  }

  # ===========================================================================
  # STEP 4: Leaf traits
  # ===========================================================================

  # Leaf type
  leaf_type <- plant_row$try_leaf_type
  if (is.na(leaf_type) || leaf_type == "") {
    leaf_type_text <- "foliage"
  } else {
    leaf_type_text <- tolower(leaf_type)
  }

  # Leaf phenology
  leaf_phenology <- plant_row$try_leaf_phenology
  if (is.na(leaf_phenology) || leaf_phenology == "") {
    phenology_text <- ""
  } else {
    phenology_text <- tolower(leaf_phenology)
  }

  # ===========================================================================
  # STEP 5: Special adaptations
  # ===========================================================================

  special_adaptations <- c()

  # Photosynthesis pathway
  photosynthesis <- plant_row$try_photosynthesis_pathway
  if (!is.na(photosynthesis)) {
    if (photosynthesis == "CAM") {
      special_adaptations <- c(special_adaptations,
                               "Drought-adapted (CAM photosynthesis)")
    } else if (photosynthesis == "C4") {
      special_adaptations <- c(special_adaptations,
                               "Heat-efficient (C4 photosynthesis)")
    }
  }

  # Mycorrhizal associations (if column exists)
  if ("try_mycorrhiza_type" %in% names(plant_row)) {
    mycorrhiza <- plant_row$try_mycorrhiza_type
    if (!is.na(mycorrhiza) && mycorrhiza != "" && mycorrhiza != "none") {
      myco_text <- sprintf("Forms %s associations", tolower(mycorrhiza))
      special_adaptations <- c(special_adaptations, myco_text)
    }
  }

  # ===========================================================================
  # STEP 6: Assemble template
  # ===========================================================================

  # RATIONALE: Simple template format for header section
  # No LLM needed - deterministic assembly of classified traits

  # Build main description line
  components <- c()

  # Add phenology if available
  if (phenology_text != "") {
    components <- c(components, phenology_text)
  }

  # Add woodiness only if not redundant with growth form
  # RATIONALE: "herbaceous herbaceous" or "woody tree" is redundant
  if (woodiness_text != "plant" &&
      !grepl(woodiness_text, growth_form_text, ignore.case = TRUE)) {
    components <- c(components, woodiness_text)
  }

  # Add growth form
  components <- c(components, growth_form_text)

  # Combine components
  description <- paste(components, collapse = " ")

  # Build identity card text
  identity_card <- glue("
    **{scientific_name}**
    *Family*: {family} | *Genus*: {genus}

    {stringr::str_to_sentence(description)} - {height_text}
    {leaf_type_text} foliage
  ")

  # Add special adaptations if any
  if (length(special_adaptations) > 0) {
    adaptations_text <- paste("*Special traits*:", paste(special_adaptations, collapse = "; "))
    identity_card <- paste(identity_card, adaptations_text, sep = "\n    ")
  }

  return(as.character(identity_card))
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Validate Plant Data for Section 1
#'
#' Checks that required columns exist and have reasonable values.
#'
#' @param plant_row Single-row data frame with plant data
#' @return Logical TRUE if valid, FALSE otherwise
#' @export
validate_section_1_data <- function(plant_row) {

  required_cols <- c("wfo_scientific_name", "family", "genus")

  # Check required columns exist
  if (!all(required_cols %in% names(plant_row))) {
    missing <- setdiff(required_cols, names(plant_row))
    warning(sprintf("Missing required columns: %s", paste(missing, collapse = ", ")))
    return(FALSE)
  }

  # Check scientific name is not NA
  if (is.na(plant_row$wfo_scientific_name)) {
    warning("Scientific name is NA")
    return(FALSE)
  }

  return(TRUE)
}

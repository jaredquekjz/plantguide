# ==============================================================================
# SECTION 5: BIOLOGICAL INTERACTIONS SUMMARY
# ==============================================================================
#
# PURPOSE:
#   Summarize multi-trophic network data including pollinators, pests,
#   diseases, and beneficial organisms with pest/disease pressure assessment.
#
# DATA SOURCES:
#   From organism profiles parquet:
#   - pollinators, pollinator_count
#   - herbivores, herbivore_count
#   - pathogens, pathogen_count
#   - flower_visitors, visitor_count
#   - predators_hasHost, predators_hasHost_count (natural pest control)
#
#   From fungal guilds parquet:
#   - amf_fungi, amf_fungi_count (arbuscular mycorrhizae)
#   - emf_fungi, emf_fungi_count (ectomycorrhizae)
#   - mycoparasite_fungi, mycoparasite_fungi_count (fungal antagonists)
#   - entomopathogenic_fungi, entomopathogenic_fungi_count
#   - endophytic_fungi, endophytic_fungi_count
#
# OUTPUT FORMAT:
#   Markdown text with 4 subsections:
#   🐝 Pollinators | 🐛 Pest Pressure | 🦠 Disease Risk | 🍄 Beneficial Fungi
#
# DEPENDENCIES:
#   - None (standalone section)
#
# NOTE:
#   This section requires joining organism_profiles and fungal_guilds data.
#   When generating full encyclopedia, these should be pre-joined or loaded
#   separately and passed as parameters.
#
# ==============================================================================

library(dplyr)
library(glue)

# ==============================================================================
# MAIN GENERATION FUNCTION
# ==============================================================================

#' Generate Section 5: Biological Interactions Summary
#'
#' Creates summary of pollinators, pests, diseases, and beneficial organisms
#' with risk assessment and biological control recommendations.
#'
#' @param plant_row Single-row data frame with plant data
#' @param organism_profile Single-row data frame from organism_profiles parquet
#' @param fungal_guilds Single-row data frame from fungal_guilds parquet
#' @return Character string of markdown-formatted biological interactions
#'
#' @details
#' ALGORITHM:
#'   1. Extract pollinator counts and summarize
#'   2. Calculate pest pressure (herbivores vs predators ratio)
#'   3. Calculate disease risk (pathogens vs antagonists ratio)
#'   4. Summarize beneficial fungi (mycorrhizae, endophytes, biocontrol)
#'   5. Generate horticultural advice for each category
#'
#' @export
generate_section_5_biological_interactions <- function(plant_row,
                                                        organism_profile = NULL,
                                                        fungal_guilds = NULL) {

  # ===========================================================================
  # STEP 1: Extract organism profile data
  # ===========================================================================

  has_organism_data <- !is.null(organism_profile)
  has_fungal_data <- !is.null(fungal_guilds)

  if (!has_organism_data && !has_fungal_data) {
    return(glue("
      ## Biological Interactions

      **Natural Relationships**: Data not available for this species
    "))
  }

  # Pollinator data
  pollinator_count <- 0
  herbivore_count <- 0
  pathogen_count <- 0
  predator_count <- 0
  visitor_count <- 0

  if (has_organism_data) {
    pollinator_count <- as.integer(organism_profile$pollinator_count[1])
    herbivore_count <- as.integer(organism_profile$herbivore_count[1])
    pathogen_count <- as.integer(organism_profile$pathogen_count[1])
    predator_count <- as.integer(organism_profile$predators_hasHost_count[1])
    visitor_count <- as.integer(organism_profile$visitor_count[1])

    # Handle NA values
    if (is.na(pollinator_count)) pollinator_count <- 0
    if (is.na(herbivore_count)) herbivore_count <- 0
    if (is.na(pathogen_count)) pathogen_count <- 0
    if (is.na(predator_count)) predator_count <- 0
    if (is.na(visitor_count)) visitor_count <- 0
  }

  # Fungal data
  amf_count <- 0
  emf_count <- 0
  endophyte_count <- 0
  mycoparasite_count <- 0
  entomopath_count <- 0

  if (has_fungal_data) {
    amf_count <- as.integer(fungal_guilds$amf_fungi_count[1])
    emf_count <- as.integer(fungal_guilds$emf_fungi_count[1])
    endophyte_count <- as.integer(fungal_guilds$endophytic_fungi_count[1])
    mycoparasite_count <- as.integer(fungal_guilds$mycoparasite_fungi_count[1])
    entomopath_count <- as.integer(fungal_guilds$entomopathogenic_fungi_count[1])

    # Handle NA values
    if (is.na(amf_count)) amf_count <- 0
    if (is.na(emf_count)) emf_count <- 0
    if (is.na(endophyte_count)) endophyte_count <- 0
    if (is.na(mycoparasite_count)) mycoparasite_count <- 0
    if (is.na(entomopath_count)) entomopath_count <- 0
  }

  # ===========================================================================
  # STEP 2: Generate pollinator section
  # ===========================================================================

  pollinator_section <- generate_pollinator_summary(pollinator_count, visitor_count)

  # ===========================================================================
  # STEP 3: Generate pest pressure section
  # ===========================================================================

  pest_section <- generate_pest_pressure_summary(herbivore_count, predator_count,
                                                   entomopath_count)

  # ===========================================================================
  # STEP 4: Generate disease risk section
  # ===========================================================================

  disease_section <- generate_disease_risk_summary(pathogen_count, mycoparasite_count)

  # ===========================================================================
  # STEP 5: Generate beneficial fungi section
  # ===========================================================================

  fungi_section <- generate_beneficial_fungi_summary(amf_count, emf_count,
                                                       endophyte_count,
                                                       plant_row$try_mycorrhiza_type)

  # ===========================================================================
  # STEP 6: Assemble complete section
  # ===========================================================================

  biological_interactions <- glue("
    ## Biological Interactions

    **Natural Relationships**:

    {pollinator_section}

    {pest_section}

    {disease_section}

    {fungi_section}
  ")

  return(as.character(biological_interactions))
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Generate Pollinator Summary
#' @keywords internal
generate_pollinator_summary <- function(pollinator_count, visitor_count) {

  total_pollinators <- pollinator_count + visitor_count

  if (total_pollinators == 0) {
    return(glue("
      🐝 **Pollinators**: Unknown pollination strategy
         → May be wind-pollinated or self-fertile
    "))
  }

  # Categorize pollinator value
  if (total_pollinators >= 20) {
    value <- "Excellent"
    advice <- "→ Plant in groups to maximize pollinator benefit\n       → Peak pollinator activity during flowering season"
  } else if (total_pollinators >= 10) {
    value <- "Good"
    advice <- "→ Attracts diverse pollinators\n       → Consider companion planting with other pollinator plants"
  } else if (total_pollinators >= 3) {
    value <- "Moderate"
    advice <- "→ Provides some pollinator support"
  } else {
    value <- "Limited"
    advice <- "→ Likely supplemented by generalist pollinators"
  }

  pollinator_text <- glue("
    🐝 **Pollinators**: {value} pollinator value ({total_pollinators} species documented)
       {advice}
  ")

  return(as.character(pollinator_text))
}

#' Generate Pest Pressure Summary
#' @keywords internal
generate_pest_pressure_summary <- function(herbivore_count, predator_count,
                                            entomopath_count) {

  if (herbivore_count == 0) {
    return(glue("
      🐛 **Pest Pressure**: LOW - Few known pests
         → Minimal pest management required
    "))
  }

  # Calculate pest control ratio
  # RATIONALE: Predators + entomopathogenic fungi provide natural control
  total_control_agents <- predator_count + entomopath_count
  control_ratio <- total_control_agents / herbivore_count

  # Assess pressure level
  if (control_ratio >= 0.5) {
    pressure_level <- "LOW with excellent natural control"
    advice <- "→ Avoid chemical sprays to preserve beneficial predators\n       → Natural enemies provide good pest suppression"
  } else if (control_ratio >= 0.2) {
    pressure_level <- "MODERATE with good natural control"
    advice <- "→ Monitor pests but rely on natural enemies first\n       → Avoid broad-spectrum pesticides"
  } else {
    pressure_level <- "MODERATE-HIGH"
    advice <- "→ Consider companion planting for additional pest control\n       → Use targeted organic controls if needed"
  }

  pest_text <- glue("
    🐛 **Pest Pressure**: {pressure_level}
       {herbivore_count} known herbivore species
       {predator_count} predator species + {entomopath_count} entomopathogenic fungi
       {advice}
  ")

  return(as.character(pest_text))
}

#' Generate Disease Risk Summary
#' @keywords internal
generate_disease_risk_summary <- function(pathogen_count, mycoparasite_count) {

  if (pathogen_count == 0) {
    return(glue("
      🦠 **Disease Risk**: LOW - No major documented pathogens
         → Minimal disease management required
    "))
  }

  # Calculate disease control ratio
  # RATIONALE: Mycoparasites (e.g., Trichoderma) antagonize pathogenic fungi
  control_ratio <- mycoparasite_count / pathogen_count

  # Assess risk level
  if (control_ratio >= 0.3) {
    risk_level <- "LOW"
    advice <- "→ Beneficial fungi provide natural disease suppression\n       → Avoid fungicides to preserve antagonists"
  } else if (control_ratio >= 0.1) {
    risk_level <- "MODERATE"
    advice <- "→ Ensure good air circulation and drainage\n       → Monitor for common fungal diseases"
  } else {
    risk_level <- "MODERATE-HIGH"
    advice <- "→ Preventive measures recommended\n       → Ensure good drainage, avoid overhead watering\n       → Consider biocontrol inoculants (e.g., Trichoderma)"
  }

  disease_text <- glue("
    🦠 **Disease Risk**: {risk_level}
       {pathogen_count} documented pathogen species
       {mycoparasite_count} antagonistic fungi available
       {advice}
  ")

  return(as.character(disease_text))
}

#' Generate Beneficial Fungi Summary
#' @keywords internal
generate_beneficial_fungi_summary <- function(amf_count, emf_count,
                                               endophyte_count,
                                               mycorrhiza_type) {

  mycorrhiza_total <- amf_count + emf_count

  if (mycorrhiza_total == 0 && endophyte_count == 0) {
    return(glue("
      🍄 **Beneficial Fungi**: Associations not well documented
         → May benefit from general mycorrhizal inoculant
    "))
  }

  # Determine mycorrhiza type
  if (amf_count > 0 && emf_count == 0) {
    myco_type <- "Arbuscular mycorrhizae (AMF)"
    myco_benefit <- "enhances water and phosphorus uptake"
    myco_advice <- "Use AMF inoculant at planting"
  } else if (emf_count > 0 && amf_count == 0) {
    myco_type <- "Ectomycorrhizae (EMF)"
    myco_benefit <- "enhances nutrient uptake and drought resistance"
    myco_advice <- "Use EMF inoculant for woody plants"
  } else if (amf_count > 0 && emf_count > 0) {
    myco_type <- sprintf("Mixed mycorrhizae (%d AMF, %d EMF)", amf_count, emf_count)
    myco_benefit <- "versatile nutrient partnerships"
    myco_advice <- "Use mixed mycorrhizal inoculant"
  } else {
    myco_type <- "Mycorrhizal associations possible"
    myco_benefit <- "may enhance nutrient uptake"
    myco_advice <- "Consider general mycorrhizal inoculant"
  }

  # Endophyte information
  endophyte_text <- ""
  if (endophyte_count > 0) {
    endophyte_text <- sprintf("\n       Endophytic fungi (%d species) - boost disease resistance",
                               endophyte_count)
  }

  fungi_text <- glue("
    🍄 **Beneficial Fungi**: Active soil partnerships
       {myco_type} - {myco_benefit}{endophyte_text}
       → {myco_advice}
       → Avoid fungicides; preserve soil biology
  ")

  return(as.character(fungi_text))
}

# ==============================================================================
# ENCYCLOPEDIA PAGE GENERATOR - R6 COORDINATOR CLASS
# ==============================================================================
#
# PURPOSE:
#   Orchestrate generation of complete encyclopedia pages by combining multiple
#   section modules. Provides batch processing capabilities.
#
# ARCHITECTURE:
#   - R6 class pattern for state management
#   - Loads plant dataset and organism/fungal data once
#   - Generates pages section-by-section
#   - Supports sequential or parallel section generation
#
# USAGE:
#   generator <- EncyclopediaGenerator$new("path/to/plant_data.csv")
#   page <- generator$generate_page("wfo-0000649953")
#   generator$batch_generate(output_dir = "output/encyclopedia")
#
# ==============================================================================

library(R6)
library(dplyr)
library(arrow)
library(glue)

# Source all section modules
source("shipley_checks/src/encyclopedia/utils/lookup_tables.R")
source("shipley_checks/src/encyclopedia/utils/categorization.R")
source("shipley_checks/src/encyclopedia/sections/s1_identity_card.R")
source("shipley_checks/src/encyclopedia/sections/s2_growing_requirements.R")
source("shipley_checks/src/encyclopedia/sections/s3_maintenance_profile.R")
source("shipley_checks/src/encyclopedia/sections/s4_ecosystem_services.R")
source("shipley_checks/src/encyclopedia/sections/s5_biological_interactions.R")

# ==============================================================================
# R6 CLASS DEFINITION
# ==============================================================================

#' Encyclopedia Page Generator
#'
#' @description
#' R6 class for generating complete plant encyclopedia pages from modular
#' section generators. Handles data loading, page assembly, and batch processing.
#'
#' @export
EncyclopediaGenerator <- R6Class("EncyclopediaGenerator",
  public = list(

    #' @description
    #' Initialize generator with data sources
    #'
    #' @param plant_data_path Path to main plant dataset CSV
    #' @param organism_profiles_path Path to organism profiles parquet
    #' @param fungal_guilds_path Path to fungal guilds parquet
    initialize = function(plant_data_path,
                          organism_profiles_path = "shipley_checks/stage4/phase0_output/organism_profiles_11711.parquet",
                          fungal_guilds_path = "shipley_checks/stage4/phase0_output/fungal_guilds_hybrid_11711.parquet") {

      cat("Loading plant dataset...\n")
      private$plants_df <- read.csv(plant_data_path, stringsAsFactors = FALSE, check.names = FALSE)
      cat(sprintf("  Loaded %d plants\n", nrow(private$plants_df)))

      if (file.exists(organism_profiles_path)) {
        cat("Loading organism profiles...\n")
        private$organisms_df <- arrow::read_parquet(organism_profiles_path)
        cat(sprintf("  Loaded %d organism profiles\n", nrow(private$organisms_df)))
      } else {
        warning("Organism profiles not found - Section 5 will be limited")
      }

      if (file.exists(fungal_guilds_path)) {
        cat("Loading fungal guilds...\n")
        private$fungal_guilds_df <- arrow::read_parquet(fungal_guilds_path)
        cat(sprintf("  Loaded %d fungal guilds\n", nrow(private$fungal_guilds_df)))
      } else {
        warning("Fungal guilds not found - Section 5 will be limited")
      }

      cat("Encyclopedia generator initialized\n\n")
    },

    #' @description
    #' Generate complete encyclopedia page for single plant
    #'
    #' @param wfo_taxon_id WFO taxon identifier
    #' @return Character string of complete markdown page
    generate_page = function(wfo_taxon_id) {

      # STEP 1: Extract plant data
      plant_data <- private$plants_df %>%
        filter(wfo_taxon_id == !!wfo_taxon_id)

      if (nrow(plant_data) == 0) {
        stop(sprintf("Plant not found: %s", wfo_taxon_id))
      }

      # STEP 2: Extract organism and fungal data
      organism_data <- NULL
      if (!is.null(private$organisms_df)) {
        organism_data <- private$organisms_df %>%
          filter(wfo_taxon_id == !!wfo_taxon_id)
        if (nrow(organism_data) == 0) organism_data <- NULL
      }

      fungal_data <- NULL
      if (!is.null(private$fungal_guilds_df)) {
        fungal_data <- private$fungal_guilds_df %>%
          filter(plant_wfo_id == !!wfo_taxon_id)
        if (nrow(fungal_data) == 0) fungal_data <- NULL
      }

      # STEP 3: Generate each section
      sections <- list()

      sections$identity <- tryCatch(
        generate_section_1_identity_card(plant_data),
        error = function(e) sprintf("# Section 1 Error: %s", e$message)
      )

      sections$growing <- tryCatch(
        generate_section_2_growing_requirements(plant_data),
        error = function(e) sprintf("## Growing Requirements\nError: %s", e$message)
      )

      sections$maintenance <- tryCatch(
        generate_section_3_maintenance_profile(plant_data),
        error = function(e) sprintf("## Maintenance Profile\nError: %s", e$message)
      )

      sections$ecosystem <- tryCatch(
        generate_section_4_ecosystem_services(plant_data),
        error = function(e) sprintf("## Ecosystem Services\nError: %s", e$message)
      )

      sections$biological <- tryCatch(
        generate_section_5_biological_interactions(plant_data, organism_data, fungal_data),
        error = function(e) sprintf("## Biological Interactions\nError: %s", e$message)
      )

      # STEP 4: Assemble page
      page <- private$assemble_page(wfo_taxon_id, plant_data, sections)

      return(page)
    },

    #' @description
    #' Generate encyclopedia pages for multiple plants
    #'
    #' @param wfo_ids Vector of WFO taxon IDs (NULL = all plants)
    #' @param output_dir Output directory for markdown files
    #' @param max_plants Maximum number of plants to process (for testing)
    #' @return Invisible NULL
    batch_generate = function(wfo_ids = NULL, output_dir = "output/encyclopedia", max_plants = NULL) {

      # Determine plants to process
      if (is.null(wfo_ids)) {
        wfo_ids <- private$plants_df$wfo_taxon_id
      }

      if (!is.null(max_plants)) {
        wfo_ids <- head(wfo_ids, max_plants)
      }

      n_plants <- length(wfo_ids)
      cat(sprintf("Generating encyclopedia pages for %d plants...\n\n", n_plants))

      # Create output directory
      if (!dir.exists(output_dir)) {
        dir.create(output_dir, recursive = TRUE)
      }

      # Generate pages
      for (i in seq_along(wfo_ids)) {
        wfo_id <- wfo_ids[i]

        if (i %% 100 == 0 || i == 1) {
          cat(sprintf("Progress: %d / %d (%.1f%%)\n", i, n_plants, 100 * i / n_plants))
        }

        tryCatch({
          page <- self$generate_page(wfo_id)

          # Write to file
          safe_filename <- gsub("[^A-Za-z0-9_-]", "_", wfo_id)
          output_path <- file.path(output_dir, sprintf("%s.md", safe_filename))
          writeLines(page, output_path)

        }, error = function(e) {
          warning(sprintf("Failed to generate page for %s: %s", wfo_id, e$message))
        })
      }

      cat(sprintf("\nBatch generation complete: %d pages\n", n_plants))
      cat(sprintf("Output directory: %s\n", output_dir))
    }
  ),

  private = list(
    plants_df = NULL,
    organisms_df = NULL,
    fungal_guilds_df = NULL,

    #' @description
    #' Assemble complete page from section components
    assemble_page = function(wfo_id, plant_data, sections) {

      scientific_name <- plant_data$wfo_scientific_name[1]
      timestamp <- format(Sys.time(), "%Y-%m-%d")

      page <- glue("
        ---
        wfo_id: {wfo_id}
        scientific_name: {scientific_name}
        generated: {timestamp}
        generator: Encyclopedia Generator v0.1
        ---

        {sections$identity}

        ---

        {sections$growing}

        ---

        {sections$maintenance}

        ---

        {sections$ecosystem}

        ---

        {sections$biological}

        ---

        *Generated by rules-based encyclopedia generator*
        *Data sources: EIVE (Dengler et al. 2023), CSR (Pierce et al. 2017), TRY database*
      ")

      return(as.character(page))
    }
  )
)

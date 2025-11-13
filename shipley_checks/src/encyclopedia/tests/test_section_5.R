# ==============================================================================
# TEST: Section 5 - Biological Interactions
# ==============================================================================

library(dplyr)
library(arrow)

# Source dependencies
source("shipley_checks/src/encyclopedia/sections/s5_biological_interactions.R")

cat("\n=== TEST: Section 5 - Biological Interactions Generation ===\n\n")

# ==============================================================================
# Load sample plants and organism data
# ==============================================================================

cat("Loading sample plants...\n")
sample_plants <- read.csv("/tmp/test_plants_sample.csv", stringsAsFactors = FALSE, check.names = FALSE)

cat("Loading organism profiles parquet...\n")
organism_profiles <- arrow::read_parquet("shipley_checks/stage4/plant_organism_profiles_11711.parquet")

cat("Loading fungal guilds parquet...\n")
fungal_guilds <- arrow::read_parquet("shipley_checks/stage4/plant_fungal_guilds_hybrid_11711.parquet")

cat(sprintf("Loaded %d sample plants\n", nrow(sample_plants)))
cat(sprintf("Organism profiles: %d rows\n", nrow(organism_profiles)))
cat(sprintf("Fungal guilds: %d rows\n\n", nrow(fungal_guilds)))

# ==============================================================================
# Generate biological interactions for each sample
# ==============================================================================

for (i in 1:nrow(sample_plants)) {
  plant <- sample_plants[i, ]

  cat(sprintf("--- Plant %d: %s ---\n", i, plant$wfo_scientific_name))

  # Find matching organism profile
  org_profile <- organism_profiles %>%
    filter(wfo_taxon_id == plant$wfo_taxon_id)

  # Find matching fungal guilds
  fungal_data <- fungal_guilds %>%
    filter(plant_wfo_id == plant$wfo_taxon_id)

  # Show key data
  if (nrow(org_profile) > 0) {
    cat("Organism interactions:\n")
    cat(sprintf("  - Pollinators: %d species\n", org_profile$pollinator_count[1]))
    cat(sprintf("  - Herbivores: %d species\n", org_profile$herbivore_count[1]))
    cat(sprintf("  - Pathogens: %d species\n", org_profile$pathogen_count[1]))
    cat(sprintf("  - Predators: %d species\n", org_profile$predators_hasHost_count[1]))
  } else {
    cat("Organism interactions: No data\n")
  }

  if (nrow(fungal_data) > 0) {
    cat("\nFungal associations:\n")
    cat(sprintf("  - AMF: %d species\n", fungal_data$amf_fungi_count[1]))
    cat(sprintf("  - EMF: %d species\n", fungal_data$emf_fungi_count[1]))
    cat(sprintf("  - Endophytes: %d species\n", fungal_data$endophytic_fungi_count[1]))
    cat(sprintf("  - Mycoparasites: %d species\n", fungal_data$mycoparasite_fungi_count[1]))
    cat(sprintf("  - Entomopathogens: %d species\n", fungal_data$entomopathogenic_fungi_count[1]))
  } else {
    cat("\nFungal associations: No data\n")
  }

  # Generate biological interactions
  cat("\n")
  if (nrow(org_profile) > 0 || nrow(fungal_data) > 0) {
    org_data <- if (nrow(org_profile) > 0) org_profile else NULL
    fungal <- if (nrow(fungal_data) > 0) fungal_data else NULL

    bio_interactions <- generate_section_5_biological_interactions(plant,
                                                                     org_data,
                                                                     fungal)
    cat("Generated Biological Interactions:\n")
    cat(bio_interactions)
  } else {
    cat("Skipping generation - no organism or fungal data\n")
  }

  cat("\n")
  cat(strrep("=", 70))
  cat("\n\n")
}

cat("\n=== TEST COMPLETE ===\n")
cat("All sample biological interactions generated successfully!\n")

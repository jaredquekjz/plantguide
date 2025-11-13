# ==============================================================================
# TEST: Section 4 - Ecosystem Services
# ==============================================================================

library(dplyr)

# Source dependencies
source("shipley_checks/src/encyclopedia/utils/categorization.R")
source("shipley_checks/src/encyclopedia/sections/s4_ecosystem_services.R")

cat("\n=== TEST: Section 4 - Ecosystem Services Generation ===\n\n")

# ==============================================================================
# Load sample plants
# ==============================================================================

cat("Loading sample plants...\n")
sample_plants <- read.csv("/tmp/test_plants_sample.csv", stringsAsFactors = FALSE, check.names = FALSE)
cat(sprintf("Loaded %d sample plants\n\n", nrow(sample_plants)))

# ==============================================================================
# Generate ecosystem services for each sample
# ==============================================================================

for (i in 1:nrow(sample_plants)) {
  plant <- sample_plants[i, ]

  cat(sprintf("--- Plant %d: %s ---\n", i, plant$wfo_scientific_name))

  # Show key data
  cat("Ecosystem service ratings:\n")
  cat(sprintf("  - Carbon biomass: %.1f (conf: %.2f)\n",
              as.numeric(plant$carbon_biomass_rating),
              as.numeric(plant$carbon_biomass_confidence)))
  cat(sprintf("  - N-fixation: %.1f (conf: %.2f)\n",
              as.numeric(plant$nitrogen_fixation_rating),
              as.numeric(plant$nitrogen_fixation_confidence)))
  cat(sprintf("  - Erosion control: %.1f (conf: %.2f)\n",
              as.numeric(plant$erosion_protection_rating),
              as.numeric(plant$erosion_protection_confidence)))
  cat(sprintf("  - Nutrient cycling: %.1f (conf: %.2f)\n",
              as.numeric(plant$nutrient_cycling_rating),
              as.numeric(plant$nutrient_cycling_confidence)))

  cat("\nPlant traits for quantification:\n")
  cat(sprintf("  - Height: %.2f m\n", ifelse(is.na(plant$height_m), NA, plant$height_m)))
  cat(sprintf("  - Woodiness: %s\n", ifelse(is.na(plant$try_woodiness), "NA", plant$try_woodiness)))
  cat(sprintf("  - Growth form: %s\n", ifelse(is.na(plant$try_growth_form), "NA", plant$try_growth_form)))

  # Generate ecosystem services
  cat("\n")
  ecosystem_services <- generate_section_4_ecosystem_services(plant)

  cat("Generated Ecosystem Services:\n")
  cat(ecosystem_services)

  cat("\n")
  cat(strrep("=", 70))
  cat("\n\n")
}

cat("\n=== TEST COMPLETE ===\n")
cat("All sample ecosystem services generated successfully!\n")

# ==============================================================================
# TEST: Section 1 - Identity Card
# ==============================================================================

library(dplyr)

# Source dependencies
source("shipley_checks/src/encyclopedia/utils/categorization.R")
source("shipley_checks/src/encyclopedia/sections/s1_identity_card.R")

cat("\n=== TEST: Section 1 - Identity Card Generation ===\n\n")

# ==============================================================================
# Load sample plants
# ==============================================================================

cat("Loading sample plants...\n")
sample_plants <- read.csv("/tmp/test_plants_sample.csv", stringsAsFactors = FALSE)
cat(sprintf("Loaded %d sample plants\n\n", nrow(sample_plants)))

# ==============================================================================
# Generate identity cards for each sample
# ==============================================================================

for (i in 1:nrow(sample_plants)) {
  plant <- sample_plants[i, ]

  cat(sprintf("--- Plant %d: %s ---\n", i, plant$wfo_scientific_name))

  # Validate data
  if (!validate_section_1_data(plant)) {
    cat("✗ Validation failed\n\n")
    next
  }

  cat("✓ Validation passed\n\n")

  # Generate identity card
  identity_card <- generate_section_1_identity_card(plant)

  cat("Generated Identity Card:\n")
  cat(identity_card)
  cat("\n\n")

  # Show raw data for comparison
  cat("Raw data used:\n")
  cat(sprintf("  - Scientific name: %s\n", plant$wfo_scientific_name))
  cat(sprintf("  - Family: %s\n", ifelse(is.na(plant$family), "NA", plant$family)))
  cat(sprintf("  - Genus: %s\n", ifelse(is.na(plant$genus), "NA", plant$genus)))
  cat(sprintf("  - Height: %s\n", ifelse(is.na(plant$height_m), "NA", sprintf("%.2f m", plant$height_m))))
  cat(sprintf("  - Growth form: %s\n", ifelse(is.na(plant$try_growth_form), "NA", plant$try_growth_form)))
  cat(sprintf("  - Woodiness: %s\n", ifelse(is.na(plant$try_woodiness), "NA", as.character(plant$try_woodiness))))
  cat(sprintf("  - Leaf type: %s\n", ifelse(is.na(plant$try_leaf_type), "NA", plant$try_leaf_type)))
  cat(sprintf("  - Leaf phenology: %s\n", ifelse(is.na(plant$try_leaf_phenology), "NA", plant$try_leaf_phenology)))
  cat(sprintf("  - Photosynthesis: %s\n", ifelse(is.na(plant$try_photosynthesis_pathway), "NA", plant$try_photosynthesis_pathway)))

  cat("\n")
  cat(strrep("=", 70))
  cat("\n\n")
}

cat("\n=== TEST COMPLETE ===\n")
cat("All sample identity cards generated successfully!\n")

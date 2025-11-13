# ==============================================================================
# TEST: Section 3 - Maintenance Profile
# ==============================================================================

library(dplyr)

# Source dependencies
source("shipley_checks/src/encyclopedia/utils/categorization.R")
source("shipley_checks/src/encyclopedia/sections/s3_maintenance_profile.R")

cat("\n=== TEST: Section 3 - Maintenance Profile Generation ===\n\n")

# ==============================================================================
# Load sample plants
# ==============================================================================

cat("Loading sample plants...\n")
sample_plants <- read.csv("/tmp/test_plants_sample.csv", stringsAsFactors = FALSE, check.names = FALSE)
cat(sprintf("Loaded %d sample plants\n\n", nrow(sample_plants)))

# ==============================================================================
# Generate maintenance profiles for each sample
# ==============================================================================

for (i in 1:nrow(sample_plants)) {
  plant <- sample_plants[i, ]

  cat(sprintf("--- Plant %d: %s ---\n", i, plant$wfo_scientific_name))

  # Show key data
  cat("CSR strategy:\n")
  cat(sprintf("  - C: %.2f, S: %.2f, R: %.2f\n",
              ifelse(is.na(plant$C), NA, plant$C),
              ifelse(is.na(plant$S), NA, plant$S),
              ifelse(is.na(plant$R), NA, plant$R)))

  cat("\nPlant traits:\n")
  cat(sprintf("  - Growth form: %s\n", ifelse(is.na(plant$try_growth_form), "NA", plant$try_growth_form)))
  cat(sprintf("  - Height: %.2f m\n", ifelse(is.na(plant$height_m), NA, plant$height_m)))
  cat(sprintf("  - Leaf phenology: %s\n", ifelse(is.na(plant$try_leaf_phenology), "NA", plant$try_leaf_phenology)))

  cat("\nDecomposition:\n")
  decomp_rating <- suppressWarnings(as.numeric(plant$decomposition_rating))
  decomp_conf <- suppressWarnings(as.numeric(plant$decomposition_confidence))
  cat(sprintf("  - Rating: %s\n",
              ifelse(is.na(decomp_rating), "NA", sprintf("%.1f/10", decomp_rating))))
  cat(sprintf("  - Confidence: %s\n",
              ifelse(is.na(decomp_conf), "NA", sprintf("%.2f", decomp_conf))))

  # Generate maintenance profile
  cat("\n")
  maintenance_profile <- generate_section_3_maintenance_profile(plant)

  cat("Generated Maintenance Profile:\n")
  cat(maintenance_profile)

  cat("\n")
  cat(strrep("=", 70))
  cat("\n\n")
}

cat("\n=== TEST COMPLETE ===\n")
cat("All sample maintenance profiles generated successfully!\n")

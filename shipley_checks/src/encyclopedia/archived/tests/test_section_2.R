# ==============================================================================
# TEST: Section 2 - Growing Requirements
# ==============================================================================

library(dplyr)

# Source dependencies
source("shipley_checks/src/encyclopedia/utils/lookup_tables.R")
source("shipley_checks/src/encyclopedia/utils/categorization.R")
source("shipley_checks/src/encyclopedia/sections/s2_growing_requirements.R")

cat("\n=== TEST: Section 2 - Growing Requirements Generation ===\n\n")

# ==============================================================================
# Load sample plants
# ==============================================================================

cat("Loading sample plants...\n")
sample_plants <- read.csv("/tmp/test_plants_sample.csv", stringsAsFactors = FALSE, check.names = FALSE)
cat(sprintf("Loaded %d sample plants\n\n", nrow(sample_plants)))

# ==============================================================================
# Generate growing requirements for each sample
# ==============================================================================

for (i in 1:nrow(sample_plants)) {
  plant <- sample_plants[i, ]

  cat(sprintf("--- Plant %d: %s ---\n", i, plant$wfo_scientific_name))

  # Show key data
  cat("EIVE scores:\n")
  cat(sprintf("  - Light (L): %.2f\n", ifelse(is.na(plant[["EIVEres-L"]]), NA, plant[["EIVEres-L"]])))
  cat(sprintf("  - Moisture (M): %.2f\n", ifelse(is.na(plant[["EIVEres-M"]]), NA, plant[["EIVEres-M"]])))
  cat(sprintf("  - Temperature (T): %.2f\n", ifelse(is.na(plant[["EIVEres-T"]]), NA, plant[["EIVEres-T"]])))
  cat(sprintf("  - Nitrogen (N): %.2f\n", ifelse(is.na(plant[["EIVEres-N"]]), NA, plant[["EIVEres-N"]])))
  cat(sprintf("  - Reaction (R): %.2f\n", ifelse(is.na(plant[["EIVEres-R"]]), NA, plant[["EIVEres-R"]])))

  cat("\nCSR strategy:\n")
  cat(sprintf("  - C: %.2f, S: %.2f, R: %.2f\n",
              ifelse(is.na(plant$C), NA, plant$C),
              ifelse(is.na(plant$S), NA, plant$S),
              ifelse(is.na(plant$R), NA, plant$R)))

  cat("\nKöppen climate tiers:\n")
  cat(sprintf("  - Number of tier memberships: %d\n",
              ifelse(is.na(plant$n_tier_memberships), 0, plant$n_tier_memberships)))

  # Generate growing requirements
  cat("\n")
  growing_reqs <- generate_section_2_growing_requirements(plant)

  cat("Generated Growing Requirements:\n")
  cat(growing_reqs)

  cat("\n")
  cat(strrep("=", 70))
  cat("\n\n")
}

cat("\n=== TEST COMPLETE ===\n")
cat("All sample growing requirements generated successfully!\n")

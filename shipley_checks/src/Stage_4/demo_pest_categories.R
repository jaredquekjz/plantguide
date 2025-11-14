#!/usr/bin/env Rscript
# Demo showing herbivore categories in pest table

library(dplyr)

# Source unified categorization
source("shipley_checks/src/Stage_4/explanation/unified_taxonomy.R")
source("shipley_checks/src/Stage_4/explanation/pest_analysis.R")

# Create mock organism data for demo
mock_organisms <- data.frame(
  plant_wfo_id = c("plant1", "plant1", "plant2", "plant2", "plant3"),
  plant_scientific_name = c("Fraxinus excelsior", "Fraxinus excelsior", "Diospyros kaki", "Diospyros kaki", "Anaphalis margaritacea"),
  herbivores = I(list(
    c("Aceria fraxini", "Aceria fraxinicola", "Acronicta rumicis"),
    c("Aculus epiphyllus", "Aculus fraxini"),
    c("Adoxophyes orana", "Myzus persicae"),
    c("Aphis fabae"),
    c("Agrilus convexicollis", "Agrilus planipennis")
  ))
)

# Flatten to get unique pests with categories
all_pests <- unlist(mock_organisms$herbivores)
unique_pests <- unique(all_pests)

cat("\n=== HERBIVORE PEST CATEGORIZATION DEMO ===\n\n")
cat("**Top Herbivore Pests** (showing new format with categories)\n\n")
cat("| Rank | Pest Species | Herbivore Category | Plants Attacked |\n")
cat("|------|--------------|-------------------|------------------|\n")

for (i in 1:min(10, length(unique_pests))) {
  pest <- unique_pests[i]
  category <- categorize_organism(pest, "herbivore")
  # Count how many plant records contain this pest
  plant_count <- sum(sapply(mock_organisms$herbivores, function(x) pest %in% x))
  plants <- if (plant_count > 1) paste(plant_count, "plants") else "1 plant"

  cat(sprintf("| %d | %s | %s | %s |\n", i, pest, category, plants))
}

cat("\n")
cat("✓ Categories now shown for all herbivore pests!\n")
cat("✓ Same unified categorization used across M1, M3, M7\n\n")

# Show some specific examples
cat("\n=== EXAMPLE CATEGORIZATIONS ===\n")
test_pests <- c(
  "Aceria fraxini",
  "Aphis fabae",
  "Myzus persicae",
  "Adoxophyes orana",
  "Agrilus convexicollis"
)

for (pest in test_pests) {
  category <- categorize_organism(pest, "herbivore")
  cat(sprintf("%s → %s\n", pest, category))
}

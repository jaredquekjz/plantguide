#!/usr/bin/env Rscript
# Quick test of unified categorization

cat("=== Testing Unified Categorization ===\n\n")

# Source unified taxonomy
source("shipley_checks/src/Stage_4/explanation/unified_taxonomy.R")

# Test some examples
test_cases <- list(
  list(name = "Aphis fabae", role = "herbivore"),
  list(name = "Platycheirus scutatus", role = "predator"),
  list(name = "Platycheirus scutatus", role = "pollinator"),
  list(name = "Bombus terrestris", role = "pollinator"),
  list(name = "Adalia bipunctata", role = "predator"),
  list(name = "Aceria fraxini", role = "herbivore")
)

for (test in test_cases) {
  category <- categorize_organism(test$name, test$role)
  cat(sprintf("%s (%s) → %s\n", test$name, test$role, category))
}

#!/usr/bin/env Rscript
#
# Flatten predator master list for encyclopedia
#
# Purpose:
# - Extract unique predators from herbivore_predators parquet
# - These are species known to prey on plant pests (from GloBI eats/preysOn)
# - Used by encyclopedia to identify beneficial insects visiting plants
#
# Input:
#   - shipley_checks/stage4/phase0_output/herbivore_predators_11711.parquet
#
# Output:
#   - shipley_checks/stage4/phase7_output/predators_master.parquet
#
# Schema (1 column):
#   - predator_taxon: Unique predator species name
#

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
})

# Paths
project_root <- "/home/olier/ellenberg"
input_file <- file.path(project_root, "shipley_checks/stage4/phase0_output/herbivore_predators_11711.parquet")
output_file <- file.path(project_root, "shipley_checks/stage4/phase7_output/predators_master.parquet")

cat("================================================================================\n")
cat("PHASE 7: FLATTEN PREDATORS MASTER LIST\n")
cat("================================================================================\n\n")

# Check input exists
if (!file.exists(input_file)) {
  stop("Input file not found: ", input_file, "\n  Run Phase 0 first.")
}

cat("Loading herbivore-predator relationships...\n")
cat("  Input: ", input_file, "\n")

herbivore_predators <- read_parquet(input_file)
cat("  Herbivores with known predators:", nrow(herbivore_predators), "\n\n")

cat("Extracting unique predators...\n")

# Unnest predator lists and get unique values
predators_master <- herbivore_predators %>%
  select(predators) %>%
  unnest_longer(predators) %>%
  distinct(predator_taxon = predators) %>%
  filter(!is.na(predator_taxon), predator_taxon != "") %>%
  arrange(predator_taxon)

cat("  Unique predators:", nrow(predators_master), "\n")

# Sample predators
cat("\nSample predators (first 10):\n")
print(head(predators_master, 10))

# Write output
cat("\n================================================================================\n")
cat("EXPORT TO PARQUET\n")
cat("================================================================================\n\n")

dir.create(dirname(output_file), showWarnings = FALSE, recursive = TRUE)

write_parquet(
  predators_master,
  output_file,
  compression = "zstd",
  compression_level = 9
)

output_size_kb <- file.size(output_file) / 1024
cat("Output:", output_file, "\n")
cat("  Rows:", nrow(predators_master), "\n")
cat("  Size:", round(output_size_kb, 2), "KB\n\n")

cat("Schema:\n")
cat("  - predator_taxon: Unique predator species (known to eat plant pests)\n\n")

cat("Done.\n")

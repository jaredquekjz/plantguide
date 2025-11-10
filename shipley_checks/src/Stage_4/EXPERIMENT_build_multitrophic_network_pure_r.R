#!/usr/bin/env Rscript
#
# Pure R Extraction: Multi-Trophic Network (NO DuckDB)
#
# Purpose:
#   Build predator-prey network for multi-trophic analysis
#   - Find predators of herbivores that attack our plants
#   - Find antagonists of pathogens that attack our plants
#
# Learnings applied:
#   - Use %in% TRUE for boolean subsetting (excludes NA)
#   - Use n_distinct() for counting unique values
#   - Set locale to C for ASCII sorting (matches Python)
#   - Handle NA explicitly with !is.na()
#
# Usage:
#   Rscript shipley_checks/src/Stage_4/EXPERIMENT_build_multitrophic_network_pure_r.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(readr)
  library(purrr)
  library(tidyr)
})

# Set locale to C for ASCII sorting (matches Python's default sorted())
Sys.setlocale("LC_COLLATE", "C")

cat("================================================================================\n")
cat("PURE R EXTRACTION: Multi-Trophic Network (NO DuckDB)\n")
cat("================================================================================\n")
cat("Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# Paths
PROFILES_PATH <- "shipley_checks/stage4/plant_organism_profiles_11711.parquet"
GLOBI_FULL_PATH <- "data/stage1/globi_interactions_original.parquet"

# Load plant organism profiles
cat("Loading plant organism profiles...\n")
profiles <- read_parquet(PROFILES_PATH)
cat("  ✓ Loaded", nrow(profiles), "plant profiles\n\n")

# ==============================================================================
# Step 1: Extract All Herbivores from Our Plants
# ==============================================================================

cat("Step 1: Extracting all herbivores that eat our plants...\n")

# Unnest herbivores list column
all_herbivores <- profiles %>%
  filter(herbivore_count > 0) %>%
  select(herbivores) %>%
  unnest(herbivores) %>%
  distinct(herbivores) %>%
  rename(herbivore = herbivores)

cat("  ✓ Found", nrow(all_herbivores), "unique herbivore species\n\n")

# ==============================================================================
# Step 2: Find Predators of Herbivores in Full GloBI
# ==============================================================================

cat("Step 2: Finding predators of herbivores in full GloBI dataset...\n")
cat("  (This may take 10-20 minutes - scanning 20M rows)\n")

# Load full GloBI interactions
globi_full <- read_parquet(GLOBI_FULL_PATH)
cat("  ✓ Loaded", nrow(globi_full), "GloBI interaction records\n")

# Filter to predator-prey relationships targeting our herbivores
predators_of_herbivores <- globi_full %>%
  filter(
    targetTaxonName %in% all_herbivores$herbivore,
    interactionTypeName %in% c('eats', 'preysOn')
  ) %>%
  group_by(herbivore = targetTaxonName) %>%
  summarize(
    predators = list(unique(sourceTaxonName)),
    predator_count = n_distinct(sourceTaxonName),
    .groups = 'drop'
  )

total_predators <- sum(predators_of_herbivores$predator_count)
cat("  ✓ Found predators for", nrow(predators_of_herbivores), "herbivores\n")
cat("  ✓ Total predator relationships:", format(total_predators, big.mark = ","), "\n\n")

# ==============================================================================
# Step 3: Extract All Pathogens from Our Plants
# ==============================================================================

cat("Step 3: Extracting all pathogens that attack our plants...\n")

# Unnest pathogens list column
all_pathogens <- profiles %>%
  filter(pathogen_count > 0) %>%
  select(pathogens) %>%
  unnest(pathogens) %>%
  distinct(pathogens) %>%
  rename(pathogen = pathogens)

cat("  ✓ Found", nrow(all_pathogens), "unique pathogen species\n\n")

# ==============================================================================
# Step 4: Find Antagonists of Pathogens in Full GloBI
# ==============================================================================

cat("Step 4: Finding antagonists of pathogens in full GloBI dataset...\n")
cat("  (This may take 10-20 minutes)\n")

# Filter to antagonistic relationships targeting our pathogens
antagonists_of_pathogens <- globi_full %>%
  filter(
    targetTaxonName %in% all_pathogens$pathogen,
    interactionTypeName %in% c('eats', 'preysOn', 'parasiteOf', 'pathogenOf')
  ) %>%
  group_by(pathogen = targetTaxonName) %>%
  summarize(
    antagonists = list(unique(sourceTaxonName)),
    antagonist_count = n_distinct(sourceTaxonName),
    .groups = 'drop'
  )

total_antagonists <- sum(antagonists_of_pathogens$antagonist_count)
cat("  ✓ Found antagonists for", nrow(antagonists_of_pathogens), "pathogens\n")
cat("  ✓ Total antagonist relationships:", format(total_antagonists, big.mark = ","), "\n\n")

# ==============================================================================
# Convert to CSV Format
# ==============================================================================

cat("Step 5: Preparing CSV outputs with sorted rows and sorted list columns...\n")

# Sort predators dataframe
predators_csv <- predators_of_herbivores %>%
  arrange(herbivore)

# Convert list column to sorted pipe-separated strings
predators_csv$predators <- map_chr(predators_csv$predators, function(x) {
  if (length(x) == 0) {
    return('')
  } else {
    return(paste(sort(x), collapse = '|'))
  }
})

# Sort antagonists dataframe
antagonists_csv <- antagonists_of_pathogens %>%
  arrange(pathogen)

# Convert list column to sorted pipe-separated strings
antagonists_csv$antagonists <- map_chr(antagonists_csv$antagonists, function(x) {
  if (length(x) == 0) {
    return('')
  } else {
    return(paste(sort(x), collapse = '|'))
  }
})

cat("  ✓ Lists converted to sorted pipe-separated strings\n\n")

# ==============================================================================
# Save CSVs
# ==============================================================================

predators_file <- "shipley_checks/validation/herbivore_predators_pure_r.csv"
antagonists_file <- "shipley_checks/validation/pathogen_antagonists_pure_r.csv"

cat("Saving herbivore predators to", predators_file, "...\n")
write_csv(predators_csv, predators_file)
cat("  ✓ Saved\n")

cat("Saving pathogen antagonists to", antagonists_file, "...\n")
write_csv(antagonists_csv, antagonists_file)
cat("  ✓ Saved\n\n")

# ==============================================================================
# Generate Checksums
# ==============================================================================

cat("Generating checksums for herbivore predators...\n")

md5_result <- system2("md5sum", args = predators_file, stdout = TRUE)
md5_hash <- trimws(strsplit(md5_result, "\\s+")[[1]][1])

sha256_result <- system2("sha256sum", args = predators_file, stdout = TRUE)
sha256_hash <- trimws(strsplit(sha256_result, "\\s+")[[1]][1])

cat("  MD5:   ", md5_hash, "\n")
cat("  SHA256:", sha256_hash, "\n\n")

# Save checksums
checksum_file <- "shipley_checks/validation/herbivore_predators_pure_r.checksums.txt"
writeLines(
  c(
    paste0("MD5:    ", md5_hash),
    paste0("SHA256: ", sha256_hash),
    "",
    paste0("File: ", predators_file),
    paste0("Size: ", format(file.size(predators_file), big.mark = ","), " bytes"),
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
  ),
  checksum_file
)

cat("  ✓ Checksums saved to", checksum_file, "\n\n")

cat("Generating checksums for pathogen antagonists...\n")

md5_result <- system2("md5sum", args = antagonists_file, stdout = TRUE)
md5_hash <- trimws(strsplit(md5_result, "\\s+")[[1]][1])

sha256_result <- system2("sha256sum", args = antagonists_file, stdout = TRUE)
sha256_hash <- trimws(strsplit(sha256_result, "\\s+")[[1]][1])

cat("  MD5:   ", md5_hash, "\n")
cat("  SHA256:", sha256_hash, "\n\n")

# Save checksums
checksum_file <- "shipley_checks/validation/pathogen_antagonists_pure_r.checksums.txt"
writeLines(
  c(
    paste0("MD5:    ", md5_hash),
    paste0("SHA256: ", sha256_hash),
    "",
    paste0("File: ", antagonists_file),
    paste0("Size: ", format(file.size(antagonists_file), big.mark = ","), " bytes"),
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
  ),
  checksum_file
)

cat("  ✓ Checksums saved to", checksum_file, "\n\n")

# ==============================================================================
# Summary Statistics
# ==============================================================================

cat("================================================================================\n")
cat("SUMMARY STATISTICS\n")
cat("================================================================================\n")

cat("Herbivore-Predator Network:\n")
cat("  - Herbivores with predators:", format(nrow(predators_csv), big.mark = ","), "\n")
cat("  - Total predator species:", format(total_predators, big.mark = ","), "\n")
avg_pred <- mean(predators_csv$predator_count)
cat(sprintf("  - Avg predators per herbivore: %.1f\n", avg_pred))
cat("\n")

cat("Pathogen-Antagonist Network:\n")
cat("  - Pathogens with antagonists:", format(nrow(antagonists_csv), big.mark = ","), "\n")
cat("  - Total antagonist species:", format(total_antagonists, big.mark = ","), "\n")
avg_ant <- mean(antagonists_csv$antagonist_count)
cat(sprintf("  - Avg antagonists per pathogen: %.1f\n", avg_ant))
cat("\n")

cat("================================================================================\n")
cat("Completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("================================================================================\n")

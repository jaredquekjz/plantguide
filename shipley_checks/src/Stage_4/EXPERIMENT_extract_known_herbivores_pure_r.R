#!/usr/bin/env Rscript
#
# Pure R Extraction: Known Herbivore Insects from Full GloBI (NO DuckDB)
#
# Purpose:
#   Build definitive lookup of insects/arthropods that eat plants
#   by analyzing FULL GloBI dataset (20.3M interactions, all kingdoms)
#
# Approach:
#   1. Extract ALL insects/arthropods with 'eats'/'preysOn' relationships to Plantae
#   2. Create comprehensive "known herbivore" lookup with taxonomic info
#   3. Count plant-eating records per herbivore
#
# Learnings applied:
#   - Set locale to C for ASCII sorting (matches Python)
#   - Handle NA explicitly with !is.na()
#   - Use n_distinct() for counting unique values
#
# Usage:
#   Rscript shipley_checks/src/Stage_4/EXPERIMENT_extract_known_herbivores_pure_r.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(readr)
  library(stringr)
})

# Set locale to C for ASCII sorting (matches Python's default sorted())
Sys.setlocale("LC_COLLATE", "C")

cat("================================================================================\n")
cat("PURE R EXTRACTION: Known Herbivore Insects from Full GloBI (NO DuckDB)\n")
cat("================================================================================\n")
cat("Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# Paths
GLOBI_FULL_PATH <- "data/stage1/globi_interactions_worldflora_enriched.parquet"

# ==============================================================================
# Step 1: Extract Known Herbivores from Full GloBI
# ==============================================================================

cat("Step 1: Extracting known herbivore insects/arthropods from full GloBI...\n")
cat("  Source:", GLOBI_FULL_PATH, "(20.3M rows)\n")
cat("  (This may take 5-10 minutes to process)\n\n")

# Load full GloBI interactions
globi_full <- read_parquet(GLOBI_FULL_PATH)
cat("  ✓ Loaded", nrow(globi_full), "interaction records\n")

# Arthropod classes to include
HERBIVORE_CLASSES <- c(
  'Insecta',      # Insects
  'Arachnida',    # Spiders, mites, ticks
  'Chilopoda',    # Centipedes
  'Diplopoda',    # Millipedes
  'Malacostraca', # Crustaceans (woodlice, etc.)
  'Gastropoda',   # Snails, slugs
  'Bivalvia'      # Clams (some terrestrial)
)

# Filter to herbivore insects eating plants
herbivore_interactions <- globi_full %>%
  filter(
    # Source is an insect or arthropod
    sourceTaxonClassName %in% HERBIVORE_CLASSES,
    # Target is a plant
    targetTaxonKingdomName == 'Plantae',
    # Interaction is eating
    interactionTypeName %in% c('eats', 'preysOn'),
    # Valid names
    !is.na(sourceTaxonName),
    sourceTaxonName != 'no name',
    !is.na(targetTaxonName)
  )

cat("  ✓ Filtered to", nrow(herbivore_interactions), "herbivory records\n")

# Create unique herbivore lookup with plant-eating record counts
known_herbivores <- herbivore_interactions %>%
  # Create unique interaction key for counting
  mutate(interaction_key = paste(targetTaxonName, interactionTypeName, sep = '|')) %>%
  group_by(
    herbivore_name = sourceTaxonName,
    sourceTaxonId,
    sourceTaxonRank,
    sourceTaxonKingdomName,
    sourceTaxonPhylumName,
    sourceTaxonClassName,
    sourceTaxonOrderName,
    sourceTaxonFamilyName,
    sourceTaxonGenusName,
    sourceTaxonSpeciesName
  ) %>%
  summarize(
    plant_eating_records = n_distinct(interaction_key),
    .groups = 'drop'
  ) %>%
  arrange(desc(plant_eating_records))

cat("  ✓ Found", nrow(known_herbivores), "unique herbivore species/taxa\n\n")

# ==============================================================================
# Step 2: Breakdown by Class
# ==============================================================================

cat("Step 2: Breakdown by taxonomic class...\n")

class_breakdown <- known_herbivores %>%
  group_by(class = sourceTaxonClassName) %>%
  summarize(species_count = n(), .groups = 'drop') %>%
  arrange(desc(species_count))

print(class_breakdown)
cat("\n")

# ==============================================================================
# Convert to CSV Format
# ==============================================================================

cat("Preparing CSV output with sorted rows...\n")

# Sort by herbivore_name, then sourceTaxonId for deterministic output
# (Some herbivores have multiple IDs from different databases)
known_herbivores_csv <- known_herbivores %>%
  arrange(herbivore_name, sourceTaxonId)

cat("  ✓ Sorted by herbivore_name, sourceTaxonId\n\n")

# ==============================================================================
# Save CSV
# ==============================================================================

output_file <- "shipley_checks/validation/known_herbivore_insects_pure_r.csv"

cat("Saving to", output_file, "...\n")
write_csv(known_herbivores_csv, output_file, na = "")
cat("  ✓ Saved\n\n")

# ==============================================================================
# Generate Checksums
# ==============================================================================

cat("Generating checksums...\n")

md5_result <- system2("md5sum", args = output_file, stdout = TRUE)
md5_hash <- trimws(strsplit(md5_result, "\\s+")[[1]][1])

sha256_result <- system2("sha256sum", args = output_file, stdout = TRUE)
sha256_hash <- trimws(strsplit(sha256_result, "\\s+")[[1]][1])

cat("  MD5:   ", md5_hash, "\n")
cat("  SHA256:", sha256_hash, "\n\n")

# Save checksums
checksum_file <- "shipley_checks/validation/known_herbivore_insects_pure_r.checksums.txt"
writeLines(
  c(
    paste0("MD5:    ", md5_hash),
    paste0("SHA256: ", sha256_hash),
    "",
    paste0("File: ", output_file),
    paste0("Size: ", format(file.size(output_file), big.mark = ","), " bytes"),
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
  ),
  checksum_file
)

cat("  ✓ Checksums saved to", checksum_file, "\n\n")

# ==============================================================================
# Summary Statistics
# ==============================================================================

cat("================================================================================\n")
cat("SUMMARY\n")
cat("================================================================================\n")
cat("Total known herbivore insects/arthropods:", format(nrow(known_herbivores_csv), big.mark = ","), "\n")
cat("Output:", output_file, "\n\n")
cat("Next step: Match these known herbivores against our 11,711 plant dataset\n")
cat("  (wherever they appear: hasHost, interactsWith, eats, etc.)\n\n")
cat("Completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("================================================================================\n")

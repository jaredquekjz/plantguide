#!/usr/bin/env Rscript
#
# Pure R Extraction: Organism Profiles (NO DuckDB)
#
# Purpose:
#   Extract pollinators, herbivores, pathogens, and flower visitors for plants
#   using pure R (arrow + dplyr, no DuckDB)
#
# Learnings from fungal guilds:
#   - Use %in% TRUE for boolean subsetting (excludes NA)
#   - Use n_distinct() for counting unique values (not sum())
#   - Match column order to Python for checksum comparison
#
# Usage:
#   Rscript shipley_checks/src/Stage_4/EXPERIMENT_extract_organism_profiles_pure_r.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(readr)
  library(purrr)
})

# Set locale to C for ASCII sorting (matches Python's default sorted())
Sys.setlocale("LC_COLLATE", "C")

cat("================================================================================\n")
cat("PURE R EXTRACTION: Organism Profiles (NO DuckDB)\n")
cat("================================================================================\n")
cat("Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# Paths
PLANT_DATASET_PATH <- "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet"
GLOBI_PATH <- "data/stage1/globi_interactions_plants_wfo.parquet"
# Use R-generated herbivore data from independent verification pipeline
HERBIVORES_PATH <- "shipley_checks/validation/matched_herbivores_per_plant_pure_r.csv"

# Load target plants
cat("Loading target plants...\n")
plants <- read_parquet(PLANT_DATASET_PATH) %>%
  select(wfo_taxon_id, wfo_scientific_name) %>%
  arrange(wfo_taxon_id)

cat("  ✓ Loaded", nrow(plants), "plants\n\n")

# Load GloBI interactions
cat("Loading GloBI interactions...\n")
globi <- read_parquet(GLOBI_PATH)
cat("  ✓ Loaded", nrow(globi), "interaction records\n\n")

# ==============================================================================
# Step 1: Extract Pollinators
# ==============================================================================

cat("Step 1: Extracting pollinators...\n")

pollinators <- globi %>%
  filter(
    !is.na(target_wfo_taxon_id),
    interactionTypeName == 'pollinates',
    sourceTaxonName != 'no name'
  ) %>%
  group_by(target_wfo_taxon_id) %>%
  summarize(
    pollinators = list(unique(sourceTaxonName)),
    pollinator_count = n_distinct(sourceTaxonName),
    .groups = 'drop'
  ) %>%
  rename(plant_wfo_id = target_wfo_taxon_id)

cat("  ✓ Found pollinators for", nrow(pollinators), "plants\n\n")

# ==============================================================================
# Step 2: Load Matched Herbivores
# ==============================================================================

cat("Step 2: Loading matched herbivores from comprehensive lookup (R-generated CSV)...\n")

# Load from CSV (R-generated from independent pipeline)
herbivores_csv <- read_csv(HERBIVORES_PATH, show_col_types = FALSE)

# Convert pipe-separated strings back to lists
herbivores <- herbivores_csv %>%
  mutate(
    herbivores = map(herbivores, function(x) {
      if (is.na(x) || x == '') {
        return(character(0))
      } else {
        return(strsplit(x, '\\|')[[1]])
      }
    })
  ) %>%
  select(plant_wfo_id, herbivores, herbivore_count)  # Exclude relationship_types

cat("  ✓ Found herbivores for", nrow(herbivores), "plants\n\n")

# ==============================================================================
# Step 3: Extract Pathogens
# ==============================================================================

cat("Step 3: Extracting pathogens...\n")

# Generic names to exclude
GENERIC_NAMES <- c('Fungi', 'Bacteria', 'Insecta', 'Plantae', 'Animalia', 'Viruses')
EXCLUDED_KINGDOMS <- c('Plantae', 'Animalia')

pathogens <- globi %>%
  filter(
    !is.na(target_wfo_taxon_id),
    (interactionTypeName %in% c('pathogenOf', 'parasiteOf')) |
      (interactionTypeName == 'hasHost' & sourceTaxonKingdomName == 'Fungi'),
    sourceTaxonName != 'no name',
    !sourceTaxonName %in% GENERIC_NAMES,
    # CRITICAL: Explicitly handle NA - SQL NOT IN excludes NULLs, R %in% includes NAs
    !is.na(sourceTaxonKingdomName),
    !sourceTaxonKingdomName %in% EXCLUDED_KINGDOMS
  ) %>%
  group_by(target_wfo_taxon_id) %>%
  summarize(
    pathogens = list(unique(sourceTaxonName)),
    pathogen_count = n_distinct(sourceTaxonName),
    .groups = 'drop'
  ) %>%
  rename(plant_wfo_id = target_wfo_taxon_id)

cat("  ✓ Found pathogens for", nrow(pathogens), "plants\n\n")

# ==============================================================================
# Step 4: Extract Flower Visitors
# ==============================================================================

cat("Step 4: Extracting flower visitors...\n")

flower_visitors <- globi %>%
  filter(
    !is.na(target_wfo_taxon_id),
    interactionTypeName %in% c('pollinates', 'visitsFlowersOf', 'visits'),
    sourceTaxonName != 'no name'
  ) %>%
  group_by(target_wfo_taxon_id) %>%
  summarize(
    flower_visitors = list(unique(sourceTaxonName)),
    visitor_count = n_distinct(sourceTaxonName),
    .groups = 'drop'
  ) %>%
  rename(plant_wfo_id = target_wfo_taxon_id)

cat("  ✓ Found flower visitors for", nrow(flower_visitors), "plants\n\n")

# ==============================================================================
# Step 5: Extract Predators (by relationship type)
# ==============================================================================

# Marine/aquatic classes to exclude
MARINE_CLASSES <- c('Asteroidea', 'Homoscleromorpha', 'Anthozoa', 'Actinopterygii',
                    'Malacostraca', 'Polychaeta', 'Bivalvia', 'Cephalopoda')

cat("Step 5a: Extracting animals with hasHost relationship...\n")

fauna_hasHost <- globi %>%
  filter(
    !is.na(target_wfo_taxon_id),
    interactionTypeName == 'hasHost',
    sourceTaxonKingdomName == 'Animalia',
    sourceTaxonName != 'no name',
    # CRITICAL: Explicitly handle NA - SQL NOT IN excludes NULLs, R %in% includes NAs
    !is.na(sourceTaxonClassName),
    !sourceTaxonClassName %in% MARINE_CLASSES
  ) %>%
  group_by(target_wfo_taxon_id) %>%
  summarize(
    fauna_hasHost = list(unique(sourceTaxonName)),
    fauna_hasHost_count = n_distinct(sourceTaxonName),
    .groups = 'drop'
  ) %>%
  rename(plant_wfo_id = target_wfo_taxon_id)

cat("  ✓ Found hasHost animals for", nrow(fauna_hasHost), "plants\n\n")

cat("Step 5b: Extracting animals with interactsWith relationship...\n")

fauna_interactsWith <- globi %>%
  filter(
    !is.na(target_wfo_taxon_id),
    interactionTypeName == 'interactsWith',
    sourceTaxonKingdomName == 'Animalia',
    sourceTaxonName != 'no name',
    # CRITICAL: Explicitly handle NA - SQL NOT IN excludes NULLs, R %in% includes NAs
    !is.na(sourceTaxonClassName),
    !sourceTaxonClassName %in% MARINE_CLASSES
  ) %>%
  group_by(target_wfo_taxon_id) %>%
  summarize(
    fauna_interactsWith = list(unique(sourceTaxonName)),
    fauna_interactsWith_count = n_distinct(sourceTaxonName),
    .groups = 'drop'
  ) %>%
  rename(plant_wfo_id = target_wfo_taxon_id)

cat("  ✓ Found interactsWith animals for", nrow(fauna_interactsWith), "plants\n\n")

cat("Step 5c: Extracting animals with adjacentTo relationship...\n")

fauna_adjacentTo <- globi %>%
  filter(
    !is.na(target_wfo_taxon_id),
    interactionTypeName == 'adjacentTo',
    sourceTaxonKingdomName == 'Animalia',
    sourceTaxonName != 'no name',
    # CRITICAL: Explicitly handle NA - SQL NOT IN excludes NULLs, R %in% includes NAs
    !is.na(sourceTaxonClassName),
    !sourceTaxonClassName %in% MARINE_CLASSES
  ) %>%
  group_by(target_wfo_taxon_id) %>%
  summarize(
    fauna_adjacentTo = list(unique(sourceTaxonName)),
    fauna_adjacentTo_count = n_distinct(sourceTaxonName),
    .groups = 'drop'
  ) %>%
  rename(plant_wfo_id = target_wfo_taxon_id)

cat("  ✓ Found adjacentTo animals for", nrow(fauna_adjacentTo), "plants\n\n")

# ==============================================================================
# Step 6: Combine into Single Profile Table
# ==============================================================================

cat("Step 6: Combining into unified profiles...\n")

profiles <- plants %>%
  select(plant_wfo_id = wfo_taxon_id, wfo_scientific_name) %>%
  left_join(pollinators, by = "plant_wfo_id") %>%
  left_join(herbivores, by = "plant_wfo_id") %>%
  left_join(pathogens, by = "plant_wfo_id") %>%
  left_join(flower_visitors, by = "plant_wfo_id") %>%
  left_join(fauna_hasHost, by = "plant_wfo_id") %>%
  left_join(fauna_interactsWith, by = "plant_wfo_id") %>%
  left_join(fauna_adjacentTo, by = "plant_wfo_id") %>%
  mutate(
    # Replace NULL lists with empty lists
    pollinators = map(pollinators, ~if(is.null(.x)) character(0) else .x),
    herbivores = map(herbivores, ~if(is.null(.x)) character(0) else .x),
    pathogens = map(pathogens, ~if(is.null(.x)) character(0) else .x),
    flower_visitors = map(flower_visitors, ~if(is.null(.x)) character(0) else .x),
    fauna_hasHost = map(fauna_hasHost, ~if(is.null(.x)) character(0) else .x),
    fauna_interactsWith = map(fauna_interactsWith, ~if(is.null(.x)) character(0) else .x),
    fauna_adjacentTo = map(fauna_adjacentTo, ~if(is.null(.x)) character(0) else .x),

    # Replace NA counts with 0
    pollinator_count = coalesce(pollinator_count, 0L),
    herbivore_count = coalesce(herbivore_count, 0L),
    pathogen_count = coalesce(pathogen_count, 0L),
    visitor_count = coalesce(visitor_count, 0L),
    fauna_hasHost_count = coalesce(fauna_hasHost_count, 0L),
    fauna_interactsWith_count = coalesce(fauna_interactsWith_count, 0L),
    fauna_adjacentTo_count = coalesce(fauna_adjacentTo_count, 0L),

    # Add wfo_taxon_id (redundant copy of plant_wfo_id) to match Python
    wfo_taxon_id = plant_wfo_id
  ) %>%
  # Ensure column order matches Python exactly
  select(
    plant_wfo_id, wfo_scientific_name,
    pollinators, pollinator_count,
    herbivores, herbivore_count,
    pathogens, pathogen_count,
    flower_visitors, visitor_count,
    fauna_hasHost, fauna_hasHost_count,
    fauna_interactsWith, fauna_interactsWith_count,
    fauna_adjacentTo, fauna_adjacentTo_count,
    wfo_taxon_id
  )

cat("  ✓ Created profiles for", nrow(profiles), "plants\n\n")

# ==============================================================================
# Convert to CSV Format
# ==============================================================================

cat("Preparing CSV output with sorted rows and sorted list columns...\n")

# Sort by plant_wfo_id
profiles <- profiles %>% arrange(plant_wfo_id)

# Convert list columns to sorted pipe-separated strings
list_cols <- c('pollinators', 'herbivores', 'pathogens', 'flower_visitors',
               'fauna_hasHost', 'fauna_interactsWith', 'fauna_adjacentTo')

for (col in list_cols) {
  profiles[[col]] <- map_chr(profiles[[col]], function(x) {
    if (length(x) == 0) {
      return('')
    } else {
      return(paste(sort(x), collapse = '|'))
    }
  })
}

cat("  ✓ Lists converted to sorted pipe-separated strings\n\n")

# ==============================================================================
# Save CSV
# ==============================================================================

output_file <- "shipley_checks/validation/organism_profiles_pure_r.csv"

cat("Saving CSV to", output_file, "...\n")
write_csv(profiles, output_file)

file_size_mb <- file.size(output_file) / 1024 / 1024
cat(sprintf("  ✓ Saved (%.2f MB)\n\n", file_size_mb))

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
checksum_file <- "shipley_checks/validation/organism_profiles_pure_r.checksums.txt"
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
cat("SUMMARY STATISTICS\n")
cat("================================================================================\n")

total_plants <- nrow(profiles)
plants_with_pollinators <- sum(profiles$pollinator_count > 0)
plants_with_herbivores <- sum(profiles$herbivore_count > 0)
plants_with_pathogens <- sum(profiles$pathogen_count > 0)
plants_with_visitors <- sum(profiles$visitor_count > 0)

cat("Total plants:", format(total_plants, big.mark = ","), "\n")
cat(sprintf("  - With pollinators: %s (%.1f%%)\n",
            format(plants_with_pollinators, big.mark = ","),
            plants_with_pollinators/total_plants*100))
cat(sprintf("  - With herbivores: %s (%.1f%%)\n",
            format(plants_with_herbivores, big.mark = ","),
            plants_with_herbivores/total_plants*100))
cat(sprintf("  - With pathogens: %s (%.1f%%)\n",
            format(plants_with_pathogens, big.mark = ","),
            plants_with_pathogens/total_plants*100))
cat(sprintf("  - With flower visitors: %s (%.1f%%)\n",
            format(plants_with_visitors, big.mark = ","),
            plants_with_visitors/total_plants*100))
cat("\n")

cat("================================================================================\n")
cat("Completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Output:", output_file, "\n")
cat("================================================================================\n")

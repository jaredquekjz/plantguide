#!/usr/bin/env Rscript
#
# Pure R Extraction: Match Known Herbivores to Plants (NO DuckDB)
#
# Purpose:
#   Match 14,345 known herbivore insects against our 11,711 plant dataset
#   wherever they appear (hasHost, interactsWith, eats, adjacentTo, etc.)
#
# Approach:
#   1. Load known herbivore insects from Step 1
#   2. Load our final plant dataset GloBI interactions
#   3. Match herbivores as SOURCE organisms (eating/hosting/interacting with plants)
#   4. Exclude nonsensical relations (plants eating insects)
#   5. Exclude pollinators even if they're in herbivore list
#   6. Create clean herbivore lists per plant
#
# Learnings applied:
#   - Set locale to C for ASCII sorting (matches Python)
#   - Handle NA explicitly with !is.na()
#   - Use n_distinct() for counting unique values
#   - Use anti_join for pollinator exclusion
#
# Usage:
#   Rscript shipley_checks/src/Stage_4/EXPERIMENT_match_known_herbivores_pure_r.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(readr)
  library(purrr)
})

# Set locale to C for ASCII sorting (matches Python's default sorted())
Sys.setlocale("LC_COLLATE", "C")

cat("================================================================================\n")
cat("PURE R EXTRACTION: Match Known Herbivores to Plants (NO DuckDB)\n")
cat("================================================================================\n")
cat("Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# Paths
KNOWN_HERBIVORES_PATH <- "data/stage4/known_herbivore_insects.parquet"
GLOBI_FINAL_PATH <- "data/stage4/globi_interactions_final_dataset_11680.parquet"

# ==============================================================================
# Step 1: Load Known Herbivore Insects
# ==============================================================================

cat("Step 1: Loading known herbivore insects lookup...\n")
cat("  Source:", KNOWN_HERBIVORES_PATH, "\n")

known_herbivores <- read_parquet(KNOWN_HERBIVORES_PATH)
cat("  ✓", nrow(known_herbivores), "known herbivore species/taxa\n\n")

# Extract just the herbivore names for matching
herbivore_names <- known_herbivores %>%
  select(herbivore_name) %>%
  distinct()

# ==============================================================================
# Step 2: Load Pollinator List (to Exclude)
# ==============================================================================

cat("Step 2: Loading pollinators to exclude...\n")

# Load GloBI final dataset
globi_final <- read_parquet(GLOBI_FINAL_PATH)

# Extract pollinators
pollinators <- globi_final %>%
  filter(
    interactionTypeName %in% c('visitsFlowersOf', 'pollinates'),
    !is.na(sourceTaxonName)
  ) %>%
  select(sourceTaxonName) %>%
  distinct()

cat("  ✓", nrow(pollinators), "pollinator organisms to exclude\n\n")

# ==============================================================================
# Step 3: Match Known Herbivores in Our Final Dataset
# ==============================================================================

cat("Step 3: Matching known herbivores in final plant dataset...\n")
cat("  Matching wherever they appear as SOURCE: eats, preysOn, hasHost, interactsWith, adjacentTo\n")
cat("  Excluding: pollinators, nonsensical plant→insect relations\n\n")

# Filter to matched herbivore interactions
matched <- globi_final %>%
  filter(
    # Target is a plant in our dataset
    !is.na(target_wfo_taxon_id),
    # Source is a known herbivore
    sourceTaxonName %in% herbivore_names$herbivore_name,
    # Relationship types where source interacts with plant
    interactionTypeName %in% c('eats', 'preysOn', 'hasHost', 'interactsWith', 'adjacentTo'),
    # Valid names
    sourceTaxonName != 'no name'
  ) %>%
  # Exclude pollinators
  anti_join(pollinators, by = "sourceTaxonName")

cat("  ✓ Found", nrow(matched), "herbivore-plant interactions\n")

# Aggregate by plant
matched_herbivores <- matched %>%
  group_by(plant_wfo_id = target_wfo_taxon_id) %>%
  summarize(
    herbivores = list(unique(sourceTaxonName)),
    herbivore_count = n_distinct(sourceTaxonName),
    relationship_types = list(unique(interactionTypeName)),
    .groups = 'drop'
  ) %>%
  arrange(desc(herbivore_count))

cat("  ✓ Found herbivores on", nrow(matched_herbivores), "plants\n")
cat(sprintf("  ✓ Coverage: %.1f%% of 11,680 plants\n", nrow(matched_herbivores)/11680*100))
cat("\n")

# ==============================================================================
# Step 4: Statistics
# ==============================================================================

cat("Step 4: Herbivore statistics...\n")

min_herb <- min(matched_herbivores$herbivore_count)
avg_herb <- as.integer(mean(matched_herbivores$herbivore_count))
max_herb <- max(matched_herbivores$herbivore_count)
median_herb <- median(matched_herbivores$herbivore_count)

cat(sprintf("  min_herbivores: %d\n", min_herb))
cat(sprintf("  avg_herbivores: %d\n", avg_herb))
cat(sprintf("  max_herbivores: %d\n", max_herb))
cat(sprintf("  median_herbivores: %.1f\n", median_herb))
cat("\n")

# ==============================================================================
# Convert to CSV Format
# ==============================================================================

cat("Preparing CSV output with sorted rows and sorted list columns...\n")

# Sort by plant_wfo_id
matched_herbivores_csv <- matched_herbivores %>%
  arrange(plant_wfo_id)

# Convert list columns to sorted pipe-separated strings
matched_herbivores_csv$herbivores <- map_chr(matched_herbivores_csv$herbivores, function(x) {
  if (length(x) == 0) {
    return('')
  } else {
    return(paste(sort(x), collapse = '|'))
  }
})

matched_herbivores_csv$relationship_types <- map_chr(matched_herbivores_csv$relationship_types, function(x) {
  if (length(x) == 0) {
    return('')
  } else {
    return(paste(sort(x), collapse = '|'))
  }
})

cat("  ✓ Lists converted to sorted pipe-separated strings\n\n")

# ==============================================================================
# Save CSV
# ==============================================================================

output_file <- "shipley_checks/validation/matched_herbivores_per_plant_pure_r.csv"

cat("Saving to", output_file, "...\n")
write_csv(matched_herbivores_csv, output_file)
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
checksum_file <- "shipley_checks/validation/matched_herbivores_per_plant_pure_r.checksums.txt"
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
# Summary
# ==============================================================================

cat("================================================================================\n")
cat("SUMMARY\n")
cat("================================================================================\n")
cat("Known herbivores from full GloBI:", format(nrow(known_herbivores), big.mark = ","), "\n")
cat(sprintf("Plants with matched herbivores: %s / 11,680 (%.1f%%)\n",
            format(nrow(matched_herbivores_csv), big.mark = ","),
            nrow(matched_herbivores_csv)/11680*100))
cat("\n")
cat("Output:", output_file, "\n\n")
cat("Completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("================================================================================\n")

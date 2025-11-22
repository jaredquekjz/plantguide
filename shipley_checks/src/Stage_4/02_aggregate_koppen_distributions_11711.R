#!/usr/bin/env Rscript
#
# Aggregate Köppen zone distributions to plant level for 11,711 dataset
#
# Purpose:
#   - Read occurrence data with Köppen zones
#   - Aggregate to plant × Köppen zone counts
#   - Calculate percentages for each plant
#   - Filter outlier zones (keep zones with ≥5% of plant's occurrences)
#   - Save plant-level Köppen distributions
#
# Input:  data/stage1/worldclim_occ_samples_with_koppen_11711.parquet
# Output: shipley_checks/stage4/plant_koppen_distributions_11711.parquet
#
# Usage:
#   env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
#     /usr/bin/Rscript shipley_checks/src/Stage_4/02_aggregate_koppen_distributions_11711.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(data.table)
  library(jsonlite)
})

cat(rep("=", 80), "\n", sep = "")
cat("AGGREGATE KÖPPEN DISTRIBUTIONS TO PLANT LEVEL (11,711 PLANTS)\n")
cat(rep("=", 80), "\n", sep = "")

# Paths
INPUT_FILE <- "data/stage1/worldclim_occ_samples_with_koppen_11711.parquet"
OUTPUT_DIR <- "shipley_checks/stage4"
OUTPUT_FILE <- file.path(OUTPUT_DIR, "plant_koppen_distributions_11711.parquet")

# Create output directory
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)

# Delete old output if exists (always regenerate)
if (file.exists(OUTPUT_FILE)) {
  cat("\n🔄 Removing old output file:", OUTPUT_FILE, "\n")
  file.remove(OUTPUT_FILE)
}

# Check if input exists
if (!file.exists(INPUT_FILE)) {
  cat("\n❌ Input file not found:", INPUT_FILE, "\n")
  cat("Run 01_assign_koppen_zones_11711.R first.\n")
  quit(status = 1)
}

cat("\nInput file:", INPUT_FILE, "\n")

# Check input structure
ds <- open_dataset(INPUT_FILE, format = "parquet")
row_count <- ds %>% count() %>% collect() %>% pull(n)
cat("  Total occurrences:", format(row_count, big.mark = ","), "\n")

# Check if koppen_zone column exists
schema <- ds$schema
if (!"koppen_zone" %in% names(schema)) {
  cat("\n❌ Error: Input file missing 'koppen_zone' column\n")
  quit(status = 1)
}

cat("\n", rep("=", 80), "\n", sep = "")
cat("STEP 1: COUNT OCCURRENCES PER PLANT × KÖPPEN ZONE\n")
cat(rep("=", 80), "\n", sep = "")

# Aggregate using arrow (efficient for large datasets)
plant_koppen_counts <- ds %>%
  filter(!is.na(koppen_zone)) %>%
  group_by(wfo_taxon_id, koppen_zone) %>%
  summarise(n_occurrences = n()) %>%
  collect() %>%
  as.data.table() %>%
  .[order(wfo_taxon_id, -n_occurrences)]

cat("  Plant × Köppen combinations:", format(nrow(plant_koppen_counts), big.mark = ","), "\n")
cat("  Unique plants:", plant_koppen_counts[, uniqueN(wfo_taxon_id)], "\n")
cat("  Unique Köppen zones:", plant_koppen_counts[, uniqueN(koppen_zone)], "\n")

cat("\n", rep("=", 80), "\n", sep = "")
cat("STEP 2: CALCULATE PERCENTAGES\n")
cat(rep("=", 80), "\n", sep = "")

# Calculate total occurrences per plant
plant_totals <- plant_koppen_counts[, .(total_occurrences = sum(n_occurrences)), by = wfo_taxon_id]

# Merge and calculate percentages
plant_koppen_counts <- plant_koppen_counts[plant_totals, on = "wfo_taxon_id"]
plant_koppen_counts[, percent := 100.0 * n_occurrences / total_occurrences]

cat("\n", rep("=", 80), "\n", sep = "")
cat("STEP 3: RANK ZONES WITHIN EACH PLANT\n")
cat(rep("=", 80), "\n", sep = "")

# Rank zones within each plant
plant_koppen_counts[, rank := frank(-n_occurrences, ties.method = "first"), by = wfo_taxon_id]

cat("\n", rep("=", 80), "\n", sep = "")
cat("STEP 4: CREATE PLANT-LEVEL SUMMARIES\n")
cat(rep("=", 80), "\n", sep = "")

# For each plant, create summary with JSON arrays
plant_summaries <- plant_koppen_counts[, {
  # Get all zones ranked
  ranked_zones <- koppen_zone[order(rank)]

  # Get main zones (≥5% occurrences)
  main_zones <- koppen_zone[percent >= 5.0]

  # Create dictionaries for counts and percentages
  zone_counts <- as.list(n_occurrences)
  names(zone_counts) <- koppen_zone

  zone_percents <- as.list(percent)
  names(zone_percents) <- koppen_zone

  # Top zone info
  top_idx <- which.min(rank)

  list(
    total_occurrences = total_occurrences[1],
    n_koppen_zones = .N,
    n_main_zones = sum(percent >= 5.0),
    top_zone_code = koppen_zone[top_idx],
    top_zone_percent = percent[top_idx],
    ranked_zones_json = toJSON(ranked_zones, auto_unbox = TRUE),
    main_zones_json = toJSON(main_zones, auto_unbox = TRUE),
    zone_counts_json = toJSON(zone_counts, auto_unbox = TRUE),
    zone_percents_json = toJSON(zone_percents, auto_unbox = TRUE)
  )
}, by = wfo_taxon_id]

cat("  Created summaries for", format(nrow(plant_summaries), big.mark = ","), "plants\n")

cat("\n", rep("=", 80), "\n", sep = "")
cat("STEP 5: SAVE TO PARQUET\n")
cat(rep("=", 80), "\n", sep = "")

cat("\nSaving to:", OUTPUT_FILE, "\n")
write_parquet(plant_summaries, OUTPUT_FILE, compression = "zstd")

cat("\n", rep("=", 80), "\n", sep = "")
cat("SUMMARY STATISTICS\n")
cat(rep("=", 80), "\n", sep = "")

cat("\nPlant-level statistics:\n")
cat("  Total plants:", format(nrow(plant_summaries), big.mark = ","), "\n")

cat("\nKöppen zones per plant:\n")
cat("  Mean:", sprintf("%.1f", mean(plant_summaries$n_koppen_zones)), "\n")
cat("  Median:", median(plant_summaries$n_koppen_zones), "\n")
cat("  Min:", min(plant_summaries$n_koppen_zones), "\n")
cat("  Max:", max(plant_summaries$n_koppen_zones), "\n")

cat("\nMain zones (≥5% occurrences) per plant:\n")
cat("  Mean:", sprintf("%.1f", mean(plant_summaries$n_main_zones)), "\n")
cat("  Median:", median(plant_summaries$n_main_zones), "\n")

n_main_1 <- sum(plant_summaries$n_main_zones == 1)
n_main_2_3 <- sum(plant_summaries$n_main_zones >= 2 & plant_summaries$n_main_zones <= 3)
n_main_4plus <- sum(plant_summaries$n_main_zones >= 4)

cat("  Plants with 1 main zone:", format(n_main_1, big.mark = ","),
    sprintf("(%.1f%%)", 100 * n_main_1 / nrow(plant_summaries)), "\n")
cat("  Plants with 2-3 main zones:", format(n_main_2_3, big.mark = ","),
    sprintf("(%.1f%%)", 100 * n_main_2_3 / nrow(plant_summaries)), "\n")
cat("  Plants with 4+ main zones:", format(n_main_4plus, big.mark = ","),
    sprintf("(%.1f%%)", 100 * n_main_4plus / nrow(plant_summaries)), "\n")

cat("\nTop zone dominance:\n")
cat("  Mean top zone percent:", sprintf("%.1f%%", mean(plant_summaries$top_zone_percent)), "\n")
cat("  Median top zone percent:", sprintf("%.1f%%", median(plant_summaries$top_zone_percent)), "\n")

cat("\nMost common top Köppen zones:\n")
top_zones <- plant_summaries[, .N, by = top_zone_code][order(-N)][1:10]
top_zones[, percent := 100 * N / nrow(plant_summaries)]
for (i in 1:nrow(top_zones)) {
  cat(sprintf("  %s: %5s plants (%5.1f%%)\n",
              top_zones$top_zone_code[i],
              format(top_zones$N[i], big.mark = ","),
              top_zones$percent[i]))
}

cat("\n", rep("=", 80), "\n", sep = "")
cat("OUTPUT FILE\n")
cat(rep("=", 80), "\n", sep = "")

output_size <- file.info(OUTPUT_FILE)$size / (1024^2)

cat(sprintf("\n✅ Successfully aggregated Köppen distributions for %s plants\n\n",
            format(nrow(plant_summaries), big.mark = ",")))

cat("Output file:", OUTPUT_FILE, "\n")
cat("  - Rows:", format(nrow(plant_summaries), big.mark = ","), "(one per plant)\n")
cat("  - Columns:", ncol(plant_summaries), "\n")
cat("  - Size:", sprintf("%.2f MB", output_size), "\n")

cat("\nColumn descriptions:\n")
cat("  - wfo_taxon_id: Plant identifier\n")
cat("  - total_occurrences: Total GBIF occurrences for this plant\n")
cat("  - n_koppen_zones: Total number of Köppen zones plant occurs in\n")
cat("  - n_main_zones: Number of zones with ≥5% of occurrences\n")
cat("  - top_zone_code: Most common Köppen zone\n")
cat("  - top_zone_percent: % of occurrences in top zone\n")
cat("  - ranked_zones_json: JSON array of all zones (ranked by frequency)\n")
cat("  - main_zones_json: JSON array of zones with ≥5% occurrences\n")
cat("  - zone_counts_json: JSON dict {zone: count}\n")
cat("  - zone_percents_json: JSON dict {zone: percent}\n")

cat("\nNext Steps:\n")
cat("1. Run 03_integrate_koppen_to_dataset_11711.R to merge with bill_with_csr_ecoservices_11711.csv\n")

cat("\n", rep("=", 80), "\n", sep = "")
cat("COMPLETE\n")
cat(rep("=", 80), "\n", sep = "")

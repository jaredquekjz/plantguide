#!/usr/bin/env Rscript
#
# Integrate Köppen distributions and tier assignments into bill_with_csr_ecoservices_11711_20251122.csv
#
# Purpose:
#   - Merge plant_koppen_distributions_11711.parquet with bill_with_csr_ecoservices_11711_20251122.csv
#   - Add tier assignment columns (boolean flags for each tier)
#   - Create final dataset ready for climate-stratified calibration
#
# Input:
#   - shipley_checks/stage4/plant_koppen_distributions_11711.parquet (Köppen data)
#   - shipley_checks/stage3/bill_with_csr_ecoservices_11711_20251122.csv (main dataset)
#
# Output:
#   - shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet
#
# Usage:
#   env R_LIBS_USER="/home/olier/ellenberg/.Rlib" \
#     /usr/bin/Rscript shipley_checks/src/Stage_4/03_integrate_koppen_to_dataset_11711.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(data.table)
  library(jsonlite)
})

cat(rep("=", 80), "\n", sep = "")
cat("INTEGRATE KÖPPEN TIERS INTO 11,711 PLANT DATASET\n")
cat(rep("=", 80), "\n", sep = "")

# File paths
KOPPEN_FILE <- "shipley_checks/stage4/plant_koppen_distributions_11711.parquet"
MAIN_DATASET <- "shipley_checks/stage3/bill_with_csr_ecoservices_11711_20251122.csv"
OUTPUT_FILE <- "shipley_checks/stage3/bill_with_csr_ecoservices_koppen_11711.parquet"

# Tier structure
TIER_STRUCTURE <- list(
  tier_1_tropical = c("Af", "Am", "As", "Aw"),
  tier_2_mediterranean = c("Csa", "Csb", "Csc"),
  tier_3_humid_temperate = c("Cfa", "Cfb", "Cfc", "Cwa", "Cwb", "Cwc"),
  tier_4_continental = c("Dfa", "Dfb", "Dfc", "Dfd", "Dwa", "Dwb", "Dwc", "Dwd",
                          "Dsa", "Dsb", "Dsc", "Dsd"),
  tier_5_boreal_polar = c("ET", "EF"),
  tier_6_arid = c("BWh", "BWk", "BSh", "BSk")
)

# Check if output already exists
if (file.exists(OUTPUT_FILE)) {
  cat("\n⚠️  Output file already exists:", OUTPUT_FILE, "\n")
  cat("Delete it first if you want to regenerate.\n")
  quit(status = 0)
}

# Check inputs
if (!file.exists(KOPPEN_FILE)) {
  cat("\n❌ Köppen file not found:", KOPPEN_FILE, "\n")
  cat("Run 02_aggregate_koppen_distributions_11711.R first.\n")
  quit(status = 1)
}

if (!file.exists(MAIN_DATASET)) {
  cat("\n❌ Main dataset not found:", MAIN_DATASET, "\n")
  quit(status = 1)
}

cat("\n", rep("=", 80), "\n", sep = "")
cat("STEP 1: LOAD KÖPPEN DISTRIBUTIONS\n")
cat(rep("=", 80), "\n", sep = "")

koppen_dt <- read_parquet(KOPPEN_FILE) %>% as.data.table()
cat("  Loaded:", format(nrow(koppen_dt), big.mark = ","), "plants with Köppen data\n")

# Parse JSON fields
koppen_dt[, main_zones := lapply(main_zones_json, fromJSON)]

cat("\n", rep("=", 80), "\n", sep = "")
cat("STEP 2: CALCULATE TIER MEMBERSHIPS\n")
cat(rep("=", 80), "\n", sep = "")

# Function to check tier membership
check_tier_membership <- function(main_zones, tier_codes) {
  any(main_zones %in% tier_codes)
}

# Calculate tier flags for each plant
for (tier_name in names(TIER_STRUCTURE)) {
  tier_codes <- TIER_STRUCTURE[[tier_name]]
  koppen_dt[, (tier_name) := sapply(main_zones, check_tier_membership, tier_codes = tier_codes)]
}

# Create tier list column
get_tier_list <- function(row_idx) {
  tiers <- character(0)
  for (tier_name in names(TIER_STRUCTURE)) {
    if (koppen_dt[[tier_name]][row_idx]) {
      tiers <- c(tiers, tier_name)
    }
  }
  return(tiers)
}

koppen_dt[, tier_memberships := lapply(1:.N, get_tier_list)]
koppen_dt[, n_tier_memberships := sapply(tier_memberships, length)]

# Convert tier list to JSON for storage
koppen_dt[, tier_memberships_json := sapply(tier_memberships, toJSON, auto_unbox = TRUE)]

cat("\nTier membership counts:\n")
for (tier_name in names(TIER_STRUCTURE)) {
  count <- sum(koppen_dt[[tier_name]])
  pct <- 100 * count / nrow(koppen_dt)
  cat(sprintf("   %-30s: %5s plants (%5.1f%%)\n",
              tier_name, format(count, big.mark = ","), pct))
}

cat(sprintf("\n   Total tier assignments: %s\n", format(sum(koppen_dt$n_tier_memberships), big.mark = ",")))
cat(sprintf("   Average tiers per plant: %.2f\n", mean(koppen_dt$n_tier_memberships)))

# Check for plants without tier assignments
no_tier <- koppen_dt[n_tier_memberships == 0, .N]
if (no_tier > 0) {
  cat(sprintf("\n   ⚠️  %s plants have NO tier assignment (rare Köppen zones)\n",
              format(no_tier, big.mark = ",")))
}

cat("\n", rep("=", 80), "\n", sep = "")
cat("STEP 3: LOAD MAIN PLANT DATASET\n")
cat(rep("=", 80), "\n", sep = "")

main_dt <- fread(MAIN_DATASET)
cat("  Loaded:", format(nrow(main_dt), big.mark = ","), "plants with", ncol(main_dt), "columns\n")

cat("\n", rep("=", 80), "\n", sep = "")
cat("STEP 4: MERGE DATASETS\n")
cat(rep("=", 80), "\n", sep = "")

# Select Köppen columns to merge (drop intermediate columns)
koppen_cols <- c(
  "wfo_taxon_id",
  "total_occurrences",
  "n_koppen_zones",
  "n_main_zones",
  "top_zone_code",
  "top_zone_percent",
  "ranked_zones_json",
  "main_zones_json",
  "zone_counts_json",
  "zone_percents_json",
  names(TIER_STRUCTURE),  # All tier flags
  "tier_memberships_json",
  "n_tier_memberships"
)

koppen_merge <- koppen_dt[, ..koppen_cols]

# Merge with main dataset
merged_dt <- merge(main_dt, koppen_merge, by = "wfo_taxon_id", all.x = TRUE)

cat("  Merged dataset:", format(nrow(merged_dt), big.mark = ","), "plants with", ncol(merged_dt), "columns\n")

# Check for plants without Köppen data
no_koppen <- merged_dt[is.na(top_zone_code), .N]
cat("  Plants without Köppen data:", format(no_koppen, big.mark = ","), "\n")

if (no_koppen > 0) {
  cat("\n   ⚠️  Warning: Some plants lack Köppen data!\n")
  cat("   These plants have no GBIF occurrences or all occurrences had invalid coordinates.\n")

  cat("\n   Sample plants without Köppen data:\n")
  no_koppen_sample <- merged_dt[is.na(top_zone_code)][1:min(10, no_koppen)]
  for (i in 1:nrow(no_koppen_sample)) {
    cat(sprintf("     - %s: %s\n",
                no_koppen_sample$wfo_taxon_id[i],
                no_koppen_sample$wfo_scientific_name[i]))
  }
}

cat("\n", rep("=", 80), "\n", sep = "")
cat("STEP 5: SAVE INTEGRATED DATASET\n")
cat(rep("=", 80), "\n", sep = "")

cat("\nSaving to:", OUTPUT_FILE, "\n")
write_parquet(merged_dt, OUTPUT_FILE, compression = "zstd")

output_size <- file.info(OUTPUT_FILE)$size / (1024^2)
cat("  Size:", sprintf("%.2f MB", output_size), "\n")

cat("\n", rep("=", 80), "\n", sep = "")
cat("COLUMN SUMMARY\n")
cat(rep("=", 80), "\n", sep = "")

cat("\nNew Köppen-related columns added:\n")
cat("  - total_occurrences: Total GBIF occurrences used\n")
cat("  - n_koppen_zones: Number of Köppen zones plant occurs in\n")
cat("  - n_main_zones: Number of zones with ≥5% occurrences\n")
cat("  - top_zone_code: Most common Köppen zone (e.g., 'Cfb')\n")
cat("  - top_zone_percent: % of occurrences in top zone\n")
cat("  - ranked_zones_json: JSON array of all zones (ranked)\n")
cat("  - main_zones_json: JSON array of main zones (≥5%)\n")
cat("  - zone_counts_json: JSON dict of occurrence counts per zone\n")
cat("  - zone_percents_json: JSON dict of percentages per zone\n")
cat("\n")
cat("Tier assignment columns (boolean flags):\n")
cat("  - tier_1_tropical: TRUE if plant has main zone in Tropical tier\n")
cat("  - tier_2_mediterranean: TRUE if plant has main zone in Mediterranean tier\n")
cat("  - tier_3_humid_temperate: TRUE if plant has main zone in Humid Temperate tier\n")
cat("  - tier_4_continental: TRUE if plant has main zone in Continental tier\n")
cat("  - tier_5_boreal_polar: TRUE if plant has main zone in Boreal/Polar tier\n")
cat("  - tier_6_arid: TRUE if plant has main zone in Arid tier\n")
cat("\n")
cat("Convenience columns:\n")
cat("  - tier_memberships_json: JSON array of tier names\n")
cat("  - n_tier_memberships: Number of tiers plant belongs to\n")

cat("\n", rep("=", 80), "\n", sep = "")
cat("USAGE FOR CALIBRATION\n")
cat(rep("=", 80), "\n", sep = "")

cat("\nThis dataset is ready for climate-stratified Monte Carlo calibration.\n\n")
cat("Example usage in R:\n\n")
cat("```r\n")
cat("library(arrow)\n")
cat("library(data.table)\n\n")
cat("# Load dataset\n")
cat(sprintf("plants <- read_parquet('%s') %>%% as.data.table()\n\n", OUTPUT_FILE))
cat("# Sample guilds for Tier 3 (Humid Temperate)\n")
cat("tier_3_plants <- plants[tier_3_humid_temperate == TRUE]\n")
cat("cat('Tier 3 pool:', nrow(tier_3_plants), 'plants\\n')\n\n")
cat("# Sample random 7-plant guilds from Tier 3\n")
cat("for (i in 1:20000) {\n")
cat("  guild_plants <- tier_3_plants[sample(.N, 7)]\n")
cat("  # Score this guild...\n")
cat("}\n")
cat("```\n")

cat("\n", rep("=", 80), "\n", sep = "")
cat("COMPLETE\n")
cat(rep("=", 80), "\n", sep = "")

n_with_koppen <- nrow(merged_dt) - no_koppen
pct_with_koppen <- 100 * n_with_koppen / nrow(merged_dt)
pct_without_koppen <- 100 * no_koppen / nrow(merged_dt)

cat(sprintf("\n✅ Successfully integrated Köppen tiers into 11,711 plant dataset\n\n"))
cat("Final dataset:", OUTPUT_FILE, "\n")
cat("  - Plants:", format(nrow(merged_dt), big.mark = ","), "\n")
cat("  - Columns:", ncol(merged_dt), "\n")
cat("  - Size:", sprintf("%.2f MB", output_size), "\n")
cat("  - Created:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

cat(sprintf("Plants with Köppen tier assignments: %s (%.1f%%)\n",
            format(n_with_koppen, big.mark = ","), pct_with_koppen))
cat(sprintf("Plants without Köppen data: %s (%.1f%%)\n",
            format(no_koppen, big.mark = ","), pct_without_koppen))

cat("\nThis dataset is now ready to replace perm2_11680_with_koppen_tiers_20251103.parquet\n")
cat("in all Stage 4 scripts (guild_scorer_v3.py, calibration scripts, etc.).\n")

cat("\n", rep("=", 80), "\n", sep = "")

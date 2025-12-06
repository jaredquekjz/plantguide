#!/usr/bin/env Rscript
# ============================================================================
# ASSIGN KÖPPEN-GEIGER ZONES TO 11,711 PLANT OCCURRENCE DATA (OPTIMIZED)
# ============================================================================
#
# OPTIMIZATION STRATEGY:
# Instead of calling LookupCZ for each of 31.5M occurrences, we:
# 1. Extract unique rounded coordinates (reduces ~31.5M → ~500k, 63X fewer)
# 2. Assign Köppen zones to unique coordinates only
# 3. Join results back to original occurrences
#
# This leverages the fact that RoundCoordinates creates many duplicates
# (0.5 degree grid means many raw coordinates map to same grid point)
#
# Input:  data/stage1/worldclim_occ_samples.parquet (31.5M rows, November 2025)
#         shipley_checks/output/stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv
#
# Output: data/stage1/worldclim_occ_samples_with_koppen_11711.parquet
#
# Runtime: ~5-10 minutes (vs ~16 hours with naive approach)
# ============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(data.table)
  library(kgc)  # R native Köppen-Geiger classification
})

cat("================================================================================\n")
cat("ASSIGN KÖPPEN-GEIGER ZONES TO 11,711 PLANT OCCURRENCE DATA (OPTIMIZED)\n")
cat("================================================================================\n\n")

start_time <- Sys.time()

# ============================================================================
# STEP 1: READ AND FILTER DATA
# ============================================================================
cat("================================================================================\n")
cat("STEP 1: READ AND FILTER DATA\n")
cat("================================================================================\n")

worldclim_path <- "data/stage1/worldclim_occ_samples.parquet"
shortlist_path <- "shipley_checks/output/stage3/bill_with_csr_ecoservices_11711_BILL_VERIFIED.csv"

if (!file.exists(worldclim_path)) {
  stop("❌ Input file not found: ", worldclim_path)
}
if (!file.exists(shortlist_path)) {
  stop("❌ Shortlist file not found: ", shortlist_path)
}

cat("Reading shortlist (11,711 plants)...\n")
shortlist <- fread(shortlist_path, select = "wfo_taxon_id")
cat(sprintf("✓ Shortlist loaded: %s plants\n", format(nrow(shortlist), big.mark = ",")))

cat("\nReading worldclim occurrence samples...\n")
ds <- open_dataset(worldclim_path)

cat("Filtering to shortlist plants...\n")
worldclim_dt <- ds %>%
  filter(wfo_taxon_id %in% !!shortlist$wfo_taxon_id) %>%
  select(wfo_taxon_id, lon, lat) %>%
  collect() %>%
  as.data.table()

cat(sprintf("✓ Filtered data: %s occurrences\n", format(nrow(worldclim_dt), big.mark = ",")))
cat(sprintf("  Plants: %s\n", format(length(unique(worldclim_dt$wfo_taxon_id)), big.mark = ",")))

# ============================================================================
# STEP 2: ROUND COORDINATES AND IDENTIFY UNIQUE GRID POINTS
# ============================================================================
cat("\n================================================================================\n")
cat("STEP 2: DEDUPLICATION - IDENTIFY UNIQUE GRID POINTS\n")
cat("================================================================================\n")

cat("Rounding coordinates to Köppen grid (0.5 degree resolution)...\n")
worldclim_dt[, rndCoord.lon := RoundCoordinates(lon, latlong = "lon")]
worldclim_dt[, rndCoord.lat := RoundCoordinates(lat, latlong = "lat")]

cat("✓ Coordinates rounded\n\n")

# Extract unique rounded coordinate pairs
cat("Extracting unique coordinate pairs...\n")
unique_coords <- unique(worldclim_dt[, .(rndCoord.lon, rndCoord.lat)])

n_occurrences <- nrow(worldclim_dt)
n_unique <- nrow(unique_coords)
dedup_factor <- n_occurrences / n_unique

cat(sprintf("\n✓ DEDUPLICATION ANALYSIS:\n"))
cat(sprintf("  Total occurrences:        %s\n", format(n_occurrences, big.mark = ",")))
cat(sprintf("  Unique grid coordinates:  %s\n", format(n_unique, big.mark = ",")))
cat(sprintf("  Deduplication factor:     %.1fX\n", dedup_factor))
cat(sprintf("  Speedup:                  %.1fX fewer LookupCZ calls!\n\n", dedup_factor))

# ============================================================================
# STEP 3: ASSIGN KÖPPEN ZONES TO UNIQUE COORDINATES ONLY
# ============================================================================
cat("================================================================================\n")
cat("STEP 3: ASSIGN KÖPPEN ZONES (UNIQUE COORDINATES ONLY)\n")
cat("================================================================================\n")

# Add site IDs for unique coordinates
unique_coords[, site_id := paste0("grid_", .I)]

# Prepare dataframe for LookupCZ
# MUST have columns: Site, Longitude, Latitude, rndCoord.lon, rndCoord.lat
cat(sprintf("Preparing %s unique coordinates for Köppen lookup...\n",
            format(n_unique, big.mark = ",")))

lookup_df <- data.frame(
  Site = unique_coords$site_id,
  Longitude = unique_coords$rndCoord.lon,
  Latitude = unique_coords$rndCoord.lat,
  rndCoord.lon = unique_coords$rndCoord.lon,
  rndCoord.lat = unique_coords$rndCoord.lat
)

cat("✓ Lookup dataframe prepared\n\n")

# Assign Köppen zones
cat(sprintf("Calling kgc::LookupCZ for %s unique points...\n",
            format(n_unique, big.mark = ",")))
assign_start <- Sys.time()

koppen_zones <- LookupCZ(lookup_df, res = "course")

assign_time <- as.numeric(difftime(Sys.time(), assign_start, units = "secs"))
cat(sprintf("✓ Köppen zones assigned in %.1f seconds (%.0f coords/sec)\n",
            assign_time, n_unique / assign_time))

# Add to unique coords table
unique_coords[, koppen_zone := koppen_zones]

# Validation
n_assigned <- sum(!is.na(unique_coords$koppen_zone))
n_ocean <- sum(unique_coords$koppen_zone == "Ocean", na.rm = TRUE)
n_valid <- n_assigned - n_ocean

cat(sprintf("\n✓ ASSIGNMENT SUMMARY:\n"))
cat(sprintf("  Unique coordinates:       %s\n", format(n_unique, big.mark = ",")))
cat(sprintf("  Köppen zones assigned:    %s (%.1f%%)\n",
            format(n_assigned, big.mark = ","),
            100 * n_assigned / n_unique))
cat(sprintf("  Ocean points:             %s (%.1f%%)\n",
            format(n_ocean, big.mark = ","),
            100 * n_ocean / n_unique))
cat(sprintf("  Valid land zones:         %s (%.1f%%)\n\n",
            format(n_valid, big.mark = ","),
            100 * n_valid / n_unique))

# ============================================================================
# STEP 4: JOIN BACK TO ORIGINAL OCCURRENCES
# ============================================================================
cat("================================================================================\n")
cat("STEP 4: JOIN KÖPPEN ZONES BACK TO ALL OCCURRENCES\n")
cat("================================================================================\n")

cat(sprintf("Joining %s unique zones back to %s occurrences...\n",
            format(n_unique, big.mark = ","),
            format(n_occurrences, big.mark = ",")))

join_start <- Sys.time()

# Join on rounded coordinates
# Keep only the koppen_zone column from unique_coords
setkey(unique_coords, rndCoord.lon, rndCoord.lat)
setkey(worldclim_dt, rndCoord.lon, rndCoord.lat)

worldclim_with_koppen <- unique_coords[worldclim_dt, .(
  wfo_taxon_id,
  lon,
  lat,
  koppen_zone
)]

join_time <- as.numeric(difftime(Sys.time(), join_start, units = "secs"))
cat(sprintf("✓ Join completed in %.1f seconds\n", join_time))

# Verify join completeness
cat(sprintf("\n✓ JOIN VERIFICATION:\n"))
cat(sprintf("  Input occurrences:        %s\n", format(n_occurrences, big.mark = ",")))
cat(sprintf("  Output occurrences:       %s\n", format(nrow(worldclim_with_koppen), big.mark = ",")))
cat(sprintf("  Match:                    %s\n\n",
            ifelse(nrow(worldclim_with_koppen) == n_occurrences, "✓ PASS", "✗ FAIL")))

# ============================================================================
# STEP 5: VALIDATION AND SUMMARY
# ============================================================================
cat("================================================================================\n")
cat("STEP 5: VALIDATION\n")
cat("================================================================================\n")

n_total <- nrow(worldclim_with_koppen)
n_assigned_final <- sum(!is.na(worldclim_with_koppen$koppen_zone))
n_ocean_final <- sum(worldclim_with_koppen$koppen_zone == "Ocean", na.rm = TRUE)
n_valid_final <- n_assigned_final - n_ocean_final

cat(sprintf("Total occurrences:        %s\n", format(n_total, big.mark = ",")))
cat(sprintf("Köppen zones assigned:    %s (%.1f%%)\n",
            format(n_assigned_final, big.mark = ","),
            100 * n_assigned_final / n_total))
cat(sprintf("Ocean points:             %s (%.1f%%)\n",
            format(n_ocean_final, big.mark = ","),
            100 * n_ocean_final / n_total))
cat(sprintf("Valid land zones:         %s (%.1f%%)\n",
            format(n_valid_final, big.mark = ","),
            100 * n_valid_final / n_total))

cat("\nKöppen zone distribution (top 15):\n")
zone_counts <- worldclim_with_koppen[!is.na(koppen_zone) & koppen_zone != "Ocean",
                                      .N, by = koppen_zone][order(-N)]
print(head(zone_counts, 15))

# ============================================================================
# STEP 6: SAVE OUTPUT
# ============================================================================
cat("\n================================================================================\n")
cat("STEP 6: SAVE OUTPUT\n")
cat("================================================================================\n")

output_path <- "data/stage1/worldclim_occ_samples_with_koppen_11711.parquet"

cat(sprintf("Writing to: %s\n", output_path))
write_parquet(worldclim_with_koppen, output_path, compression = "zstd")

file_size_mb <- file.info(output_path)$size / 1024^2
cat(sprintf("✓ Output written: %.1f MB\n", file_size_mb))

# ============================================================================
# SUMMARY
# ============================================================================
total_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

cat("\n================================================================================\n")
cat("ASSIGNMENT COMPLETE\n")
cat("================================================================================\n\n")
cat(sprintf("Total runtime:            %.1f minutes (%.1f seconds)\n",
            total_time / 60, total_time))
cat(sprintf("Deduplication factor:     %.1fX\n", dedup_factor))
cat(sprintf("LookupCZ calls:           %s (vs %s naive)\n",
            format(n_unique, big.mark = ","),
            format(n_occurrences, big.mark = ",")))
cat(sprintf("Output file:              %s\n", output_path))
cat(sprintf("Output size:              %.1f MB\n", file_size_mb))
cat(sprintf("Occurrences:              %s\n", format(nrow(worldclim_with_koppen), big.mark = ",")))
cat(sprintf("Plants:                   %s\n",
            format(length(unique(worldclim_with_koppen$wfo_taxon_id)), big.mark = ",")))
cat(sprintf("Valid land zones:         %s (%.1f%%)\n",
            format(n_valid_final, big.mark = ","),
            100 * n_valid_final / n_total))
cat("\n")

#!/usr/bin/env Rscript
# extract_soil_from_local.R - Fast extraction from downloaded SoilGrids files

library(terra)
library(data.table)
library(tidyverse)

cat("=====================================\n")
cat("Soil Extraction from Local Files\n")
cat("=====================================\n\n")

# Configuration
SOIL_DIR <- "/home/olier/ellenberg/data/soilgrids_global"
OUTPUT_DIR <- "/home/olier/ellenberg/data/soil_extractions"

# Check if files exist
if (!dir.exists(SOIL_DIR)) {
  stop("Soil data directory not found. Run download_soilgrids_global.sh first!")
}

tif_files <- list.files(SOIL_DIR, pattern = "\\.tif$", full.names = TRUE)
if (length(tif_files) == 0) {
  stop("No TIF files found. Run download_soilgrids_global.sh first!")
}

cat(sprintf("Found %d soil raster files\n", length(tif_files)))

# Load occurrences
cat("\nLoading occurrence data...\n")
occurrences <- fread("/home/olier/ellenberg/data/bioclim_extractions_cleaned/occurrences_with_bioclim.csv")
cat(sprintf("  Loaded %d occurrences for %d species\n", 
            nrow(occurrences), 
            length(unique(occurrences$species))))

# Convert to SpatVector
points <- vect(occurrences,
               geom = c("decimalLongitude", "decimalLatitude"),
               crs = "EPSG:4326")

# Extract from each raster
cat("\nExtracting soil values...\n")
results <- occurrences[, .(gbifID, species, decimalLongitude, decimalLatitude)]

for (tif_file in tif_files) {
  # Get property name from filename
  prop_name <- gsub(".*/(.*?)_.*\\.tif", "\\1_\\2", tif_file)
  prop_name <- gsub("\\.tif", "", basename(tif_file))
  prop_name <- gsub("-", "_", prop_name)
  
  cat(sprintf("\n  Processing %s...\n", basename(tif_file)))
  
  start_time <- Sys.time()
  
  # Load raster
  raster <- rast(tif_file)
  
  # Extract values (FAST with local files!)
  values <- extract(raster, points, ID = FALSE)[, 2]
  
  # Apply scaling factors
  if (grepl("phh2o|soc|clay|sand|cec", prop_name)) {
    values <- values / 10  # These are stored as integers × 10
  } else if (grepl("nitrogen", prop_name)) {
    values <- values / 100  # Stored as integer × 100
  } else if (grepl("bdod", prop_name)) {
    values <- values / 100  # Stored as integer × 100
  }
  
  # Store in results
  results[[prop_name]] <- values
  
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  valid <- sum(!is.na(values))
  
  cat(sprintf("    Time: %.1f sec | Valid: %d/%d (%.1f%%) | Speed: %.0f pts/sec\n",
              elapsed, valid, length(values), 
              100 * valid / length(values),
              length(values) / elapsed))
}

# Aggregate to species level
cat("\nAggregating to species level...\n")

species_soil <- results %>%
  group_by(species) %>%
  summarise(
    n_occurrences = n(),
    across(starts_with("phh2o") | starts_with("soc") | 
           starts_with("clay") | starts_with("sand") |
           starts_with("cec") | starts_with("nitrogen") | 
           starts_with("bdod"),
           list(
             mean = ~mean(.x, na.rm = TRUE),
             sd = ~sd(.x, na.rm = TRUE),
             q25 = ~quantile(.x, 0.25, na.rm = TRUE),
             q75 = ~quantile(.x, 0.75, na.rm = TRUE),
             n_valid = ~sum(!is.na(.x))
           ),
           .names = "{.col}_{.fn}")
  ) %>%
  filter(n_occurrences >= 30)

cat(sprintf("  Species with ≥30 occurrences: %d\n", nrow(species_soil)))

# Save results
cat("\nSaving results...\n")
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

# Save full results
fwrite(results, file.path(OUTPUT_DIR, "occurrences_with_soil.csv"))
cat(sprintf("  Saved: occurrences_with_soil.csv (%.1f MB)\n",
            file.size(file.path(OUTPUT_DIR, "occurrences_with_soil.csv")) / 1024^2))

# Save species summary
write.csv(species_soil, 
          file.path(OUTPUT_DIR, "species_soil_summary.csv"),
          row.names = FALSE)
cat(sprintf("  Saved: species_soil_summary.csv (%.1f MB)\n",
            file.size(file.path(OUTPUT_DIR, "species_soil_summary.csv")) / 1024^2))

cat("\n=====================================\n")
cat("EXTRACTION COMPLETE!\n")
cat("=====================================\n")

# Print summary stats
cat("\nExtraction Summary:\n")
cat(sprintf("  Total occurrences: %d\n", nrow(results)))
cat(sprintf("  Species processed: %d\n", length(unique(results$species))))
cat(sprintf("  Species with sufficient data: %d\n", nrow(species_soil)))

# Show sample of results
cat("\nSample results (first 5 species):\n")
print(head(species_soil[, c("species", "n_occurrences", 
                            "phh2o_0_5cm_1km_mean",
                            "soc_0_5cm_1km_mean",
                            "clay_0_5cm_1km_mean")], 5))
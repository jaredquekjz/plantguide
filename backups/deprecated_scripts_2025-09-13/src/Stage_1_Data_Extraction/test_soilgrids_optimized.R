#!/usr/bin/env Rscript
# Optimized test of SoilGrids extraction with proper handling

library(terra)
library(tidyverse)
# Fix namespace conflict - use terra's extract
extract <- terra::extract

cat("===========================================\n")
cat("Optimized SoilGrids Extraction Test\n")
cat("===========================================\n\n")

# Configure GDAL for better performance
terraOptions(verbose = FALSE)  # Reduce verbosity for cleaner output

# Test alternative access methods
cat("Testing different access methods...\n\n")

# Load 100 test points from your actual data
occurrence_file <- "/home/olier/ellenberg/data/bioclim_extractions_cleaned/occurrences_with_bioclim.csv"

if (file.exists(occurrence_file)) {
  # Use real occurrence data
  occurrences <- read.csv(occurrence_file, nrows = 5000)
  
  # Sample 100 geographically clustered points (more realistic)
  # This simulates extracting for one species at a time
  set.seed(42)
  
  # Pick 3 species with good coverage
  selected_species <- occurrences %>%
    count(species) %>%
    filter(n >= 30) %>%
    slice_sample(n = min(3, n())) %>%
    pull(species)
  
  test_data <- occurrences %>%
    filter(species %in% selected_species) %>%
    group_by(species) %>%
    slice_sample(n = min(33, n())) %>%
    ungroup() %>%
    slice_sample(n = 100)
  
} else {
  # Synthetic clustered data
  test_data <- data.frame(
    species = rep(c("sp1", "sp2", "sp3"), c(40, 35, 25)),
    decimalLongitude = c(
      rnorm(40, 10, 2),   # Cluster 1: Central Europe
      rnorm(35, 0, 3),    # Cluster 2: Western Europe  
      rnorm(25, 20, 2)    # Cluster 3: Eastern Europe
    ),
    decimalLatitude = c(
      rnorm(40, 50, 1),   # Cluster 1
      rnorm(35, 45, 2),   # Cluster 2
      rnorm(25, 52, 1.5)  # Cluster 3
    )
  )
}

cat(sprintf("Using %d points from %d species\n", 
            nrow(test_data), 
            length(unique(test_data$species))))

# Convert to SpatVector
points <- vect(test_data, 
               geom = c("decimalLongitude", "decimalLatitude"),
               crs = "EPSG:4326")

# ============================================
# METHOD 1: Direct VRT access
# ============================================

cat("\n--- Method 1: Direct VRT Access ---\n")

ph_vrt <- "/vsicurl/https://files.isric.org/soilgrids/latest/data/phh2o/phh2o_0-5cm_mean.vrt"

start <- Sys.time()
ph_raster <- rast(ph_vrt)
load_time <- as.numeric(difftime(Sys.time(), start, units = "secs"))
cat(sprintf("VRT loaded in %.2f seconds\n", load_time))

# Check actual resolution
cat("\nRaster info:\n")
cat(sprintf("  CRS: %s\n", crs(ph_raster, describe = TRUE)$name))
cat(sprintf("  Extent: %.2f, %.2f, %.2f, %.2f\n", 
            xmin(ph_raster), xmax(ph_raster), 
            ymin(ph_raster), ymax(ph_raster)))

# Extract values
cat("\nExtracting values...\n")
start <- Sys.time()
values_vrt <- extract(ph_raster, points)
extract_time_vrt <- as.numeric(difftime(Sys.time(), start, units = "secs"))

cat(sprintf("  Extracted %d values in %.2f seconds\n", 
            nrow(values_vrt), extract_time_vrt))
cat(sprintf("  Points per second: %.1f\n", nrow(values_vrt) / extract_time_vrt))

# ============================================
# METHOD 2: COG Access (if available)
# ============================================

cat("\n--- Method 2: Cloud-Optimized GeoTIFF ---\n")

# SoilGrids also provides COGs at lower resolution
ph_cog_1km <- "/vsicurl/https://files.isric.org/soilgrids/latest/data_aggregated/1000m/phh2o/phh2o_0-5cm_mean_1000m.tif"

tryCatch({
  start <- Sys.time()
  ph_raster_cog <- rast(ph_cog_1km)
  load_time_cog <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  cat(sprintf("COG loaded in %.2f seconds\n", load_time_cog))
  
  start <- Sys.time()
  values_cog <- extract(ph_raster_cog, points)
  extract_time_cog <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  
  cat(sprintf("  Extracted %d values in %.2f seconds\n", 
              nrow(values_cog), extract_time_cog))
  cat(sprintf("  Points per second: %.1f\n", nrow(values_cog) / extract_time_cog))
  
}, error = function(e) {
  cat("  COG access failed (may not be available)\n")
})

# ============================================
# METHOD 3: Regional subset (Europe only)
# ============================================

cat("\n--- Method 3: Regional Subset ---\n")

# Define Europe bounds
europe_ext <- ext(-10, 40, 35, 70)

cat("Creating Europe window...\n")
start <- Sys.time()

# Use window to limit the raster extent
ph_europe <- crop(ph_raster, europe_ext)
crop_time <- as.numeric(difftime(Sys.time(), start, units = "secs"))

cat(sprintf("  Cropped to Europe in %.2f seconds\n", crop_time))

# Extract from cropped raster
start <- Sys.time()
values_europe <- extract(ph_europe, points)
extract_time_europe <- as.numeric(difftime(Sys.time(), start, units = "secs"))

cat(sprintf("  Extracted %d values in %.2f seconds\n", 
            nrow(values_europe), extract_time_europe))
cat(sprintf("  Points per second: %.1f\n", nrow(values_europe) / extract_time_europe))

# ============================================
# PERFORMANCE COMPARISON
# ============================================

cat("\n===========================================\n")
cat("PERFORMANCE SUMMARY\n")
cat("===========================================\n")

methods <- data.frame(
  Method = c("Direct VRT", "Regional crop"),
  Load_Time = c(load_time, crop_time),
  Extract_Time = c(extract_time_vrt, extract_time_europe),
  Total_Time = c(load_time + extract_time_vrt, crop_time + extract_time_europe),
  Points_Per_Sec = c(100 / extract_time_vrt, 100 / extract_time_europe)
)

print(methods)

# Projections
best_rate <- max(methods$Points_Per_Sec)
cat(sprintf("\nBest extraction rate: %.1f points/second\n", best_rate))

cat("\nProjections for full dataset:\n")
cat(sprintf("  1,000 points: %.1f seconds\n", 1000 / best_rate))
cat(sprintf("  100,000 points: %.1f minutes\n", 100000 / best_rate / 60))
cat(sprintf("  1M points: %.1f hours\n", 1000000 / best_rate / 3600))
cat(sprintf("  5M points: %.1f hours\n", 5000000 / best_rate / 3600))

# For multiple properties
cat(sprintf("\n  5M points × 7 properties × 3 depths: %.1f hours\n", 
            5000000 * 21 / best_rate / 3600))

# ============================================
# DATA VALIDATION
# ============================================

cat("\n--- Data Validation ---\n")

# Check pH values
ph_values <- values_vrt[, 2] / 10  # Convert to actual pH
valid_ph <- ph_values[!is.na(ph_values)]

cat(sprintf("Valid values: %d/%d (%.1f%%)\n", 
            length(valid_ph), length(ph_values),
            100 * length(valid_ph) / length(ph_values)))

if (length(valid_ph) > 0) {
  cat(sprintf("pH range: %.1f - %.1f\n", min(valid_ph), max(valid_ph)))
  cat(sprintf("pH mean: %.2f (SD: %.2f)\n", mean(valid_ph), sd(valid_ph)))
  
  # Check for reasonable soil pH (3-9)
  if (any(valid_ph < 3 | valid_ph > 9)) {
    cat("WARNING: Some pH values outside typical range (3-9)\n")
  } else {
    cat("✓ All pH values within reasonable range\n")
  }
}

# Save results
output_dir <- "/home/olier/ellenberg/artifacts/soil_test"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

results <- data.frame(
  test_data,
  pH = ph_values,
  extraction_method = "vsicurl_vrt"
)

write.csv(results, 
          file.path(output_dir, "soilgrids_test_results.csv"),
          row.names = FALSE)

cat(sprintf("\nResults saved to: %s\n", 
            file.path(output_dir, "soilgrids_test_results.csv")))

cat("\n===========================================\n")
cat("TEST COMPLETE\n")
cat("===========================================\n")